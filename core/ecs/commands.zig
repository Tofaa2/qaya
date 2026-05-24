const std = @import("std");
const world_mod = @import("world.zig");
const World = world_mod.World;
const Entity = world_mod.Entity;
const registry = @import("registry.zig");
const Mask = registry.Mask;

pub const CommandBuffer = struct {
    allocator: std.mem.Allocator,
    commands: std.ArrayListUnmanaged(Command) = .empty,
    data: std.ArrayListUnmanaged(u8) = .empty,

    const Command = union(enum) {
        spawn: struct {
            data_start: usize,
            component_count: usize,
            signature: Mask,
        },
        despawn: Entity,
        add_component: struct {
            entity: Entity,
            data_start: usize,
            apply_fn: *const fn (*World, Entity, *CommandBuffer, usize) anyerror!void,
        },
        remove_component: struct {
            entity: Entity,
            apply_fn: *const fn (*World, Entity) anyerror!void,
        },
    };

    const ComponentHeader = struct {
        type_id: registry.ComponentId,
        size: usize,
        alignment: u8,
    };

    pub fn init(allocator: std.mem.Allocator) CommandBuffer {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *CommandBuffer) void {
        self.commands.deinit(self.allocator);
        self.data.deinit(self.allocator);
    }

    pub fn reset(self: *CommandBuffer) void {
        self.commands.clearRetainingCapacity();
        self.data.clearRetainingCapacity();
    }

    pub fn spawn(self: *CommandBuffer, bundle: anytype) !void {
        const V = @TypeOf(bundle);
        const info = @typeInfo(V);

        if (info != .@"struct") @compileError("spawn expects a tuple or a bundle struct");

        const fields = if (info.@"struct".is_tuple)
            std.meta.fields(V)
        else if (@hasDecl(V, "qaya_bundle"))
            std.meta.fields(V)
        else
            @compileError("spawn expects a tuple or a bundle struct (with `pub const qaya_bundle = true;`)");

        const data_start = self.data.items.len;
        var sig: Mask = 0;

        inline for (fields, 0..) |field, i| {
            const T = field.type;
            const cid = registry.id(T);
            sig |= registry.mask(T);

            const header = ComponentHeader{ .type_id = cid, .size = @sizeOf(T), .alignment = std.meta.alignment(T) };
            try self.data.appendSlice(self.allocator, std.mem.asBytes(&header));
            const val = if (info.@"struct".is_tuple) bundle[i] else @field(bundle, field.name);
            try self.data.appendSlice(self.allocator, std.mem.asBytes(&val));
        }

        try self.commands.append(self.allocator, .{
            .spawn = .{
                .data_start = data_start,
                .component_count = fields.len,
                .signature = sig,
            },
        });
    }

    pub fn despawn(self: *CommandBuffer, entity: Entity) !void {
        try self.commands.append(self.allocator, .{ .despawn = entity });
    }

    pub fn addComponent(self: *CommandBuffer, entity: Entity, value: anytype) !void {
        const T = @TypeOf(value);
        const data_start = self.data.items.len;
        const header = ComponentHeader{ .type_id = registry.id(T), .size = @sizeOf(T), .alignment = std.meta.alignment(T) };
        try self.data.appendSlice(self.allocator, std.mem.asBytes(&header));
        try self.data.appendSlice(self.allocator, std.mem.asBytes(&value));

        const Applier = struct {
            fn apply(w: *World, e: Entity, cb: *CommandBuffer, start: usize) anyerror!void {
                const h = std.mem.bytesAsValue(ComponentHeader, cb.data.items[start..][0..@sizeOf(ComponentHeader)]);
                const d = cb.data.items[start + @sizeOf(ComponentHeader) ..][0..h.size];
                const val = std.mem.bytesAsValue(T, d);
                try w.addComponent(e, T, val.*);
            }
        };

        try self.commands.append(self.allocator, .{
            .add_component = .{
                .entity = entity,
                .data_start = data_start,
                .apply_fn = Applier.apply,
            },
        });
    }

    pub fn removeComponent(self: *CommandBuffer, entity: Entity, comptime T: type) !void {
        const Applier = struct {
            fn apply(w: *World, e: Entity) anyerror!void {
                try w.removeComponent(e, T);
            }
        };
        try self.commands.append(self.allocator, .{
            .remove_component = .{
                .entity = entity,
                .apply_fn = Applier.apply,
            },
        });
    }

    pub fn apply(self: *CommandBuffer, world: *World) !void {
        for (self.commands.items) |cmd| {
            switch (cmd) {
                .spawn => |s| {
                    const e = try world.allocEntity();
                    const arch_id = try world.ensureArchetype(s.signature);
                    const arch = &world.archetypes.items[arch_id];

                    try arch.entities.append(world.allocator, e);
                    const row = arch.entities.items.len - 1;

                    var ptr = s.data_start;
                    var i: usize = 0;
                    while (i < s.component_count) : (i += 1) {
                        const header = std.mem.bytesAsValue(ComponentHeader, self.data.items[ptr..][0..@sizeOf(ComponentHeader)]);
                        ptr += @sizeOf(ComponentHeader);
                        const comp_data = self.data.items[ptr..][0..header.size];
                        ptr += header.size;

                        try arch.ensureColumnRaw(world.allocator, header.type_id, header.size, header.alignment, header.size);
                        const col = arch.getColumn(header.type_id).?;
                        _ = try col.pushUninitialized(world.allocator, world.change_tick);
                        @memcpy(col.rowPtr(row)[0..header.size], comp_data);
                    }

                    world.entities.items[e.index] = .{
                        .generation = e.generation,
                        .alive = true,
                        .archetype = arch_id,
                        .row = @intCast(row),
                    };
                },
                .despawn => |e| world.despawn(e),
                .add_component => |a| try a.apply_fn(world, a.entity, self, a.data_start),
                .remove_component => |r| try r.apply_fn(world, r.entity),
            }
        }
        self.reset();
    }
};
