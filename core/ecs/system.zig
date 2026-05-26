const std = @import("std");
const world_mod = @import("world.zig");
const World = world_mod.World;
const Entity = world_mod.Entity;
const registry = @import("registry.zig");
const CommandBuffer = @import("commands.zig").CommandBuffer;

/// System parameter for immutable resource access.
pub fn Res(comptime T: type) type {
    return struct {
        value: *const T,
        pub const qaya_system_param = true;
        pub fn init(world: *World) @This() {
            return .{ .value = world.getResource(T) orelse @panic("Resource not found: " ++ @typeName(T)) };
        }
        pub fn masks() [2]registry.Mask {
            return .{ registry.mask(T), 0 };
        }
    };
}

/// System parameter for mutable resource access.
pub fn ResMut(comptime T: type) type {
    return struct {
        value: *T,
        pub const qaya_system_param = true;
        pub fn init(world: *World) @This() {
            return .{ .value = world.getMutResource(T) orelse @panic("Resource not found: " ++ @typeName(T)) };
        }
        pub fn masks() [2]registry.Mask {
            return .{ 0, registry.mask(T) };
        }
    };
}

/// System parameter for reading events.
pub fn Events(comptime E: type) type {
    return struct {
        view: world_mod.EventChannel(E).View,
        pub const qaya_system_param = true;
        pub fn init(world: *World) @This() {
            return .{ .view = world.eventReader(E) };
        }
        pub fn deinit(self: @This()) void {
            self.view.release();
        }
        pub fn masks() [2]registry.Mask {
            return .{ registry.mask(E), 0 };
        }
    };
}

/// System parameter for recording world commands.
pub fn Commands() type {
    return struct {
        buffer: *CommandBuffer,
        pub const qaya_system_param = true;
        pub fn init(world: *World) @This() {
            _ = world;
            unreachable; // Handled specially in wrap
        }
        pub fn masks() [2]registry.Mask {
            return .{ 0, 0 }; // Commands don't conflict with components/resources
        }

        pub fn spawn(self: @This(), values: anytype) !void {
            try self.buffer.spawn(values);
        }
        pub fn despawn(self: @This(), entity: world_mod.Entity) !void {
            try self.buffer.despawn(entity);
        }
        pub fn addComponent(self: @This(), entity: world_mod.Entity, value: anytype) !void {
            try self.buffer.addComponent(entity, value);
        }
        pub fn removeComponent(self: @This(), entity: world_mod.Entity, comptime T: type) !void {
            try self.buffer.removeComponent(entity, T);
        }
    };
}

pub fn Changed(comptime T: type) type {
    return struct {
        pub const qaya_ecs_changed = T;
    };
}

pub fn Added(comptime T: type) type {
    return struct {
        pub const qaya_ecs_added = T;
    };
}

fn childType(comptime C: type) type {
    const info = @typeInfo(C);
    if (info == .@"struct") {
        if (@hasDecl(C, "qaya_ecs_changed")) return C.qaya_ecs_changed;
        if (@hasDecl(C, "qaya_ecs_added")) return C.qaya_ecs_added;
    }
    return if (info == .pointer) info.pointer.child else C;
}

fn isChanged(comptime C: type) bool {
    return @typeInfo(C) == .@"struct" and @hasDecl(C, "qaya_ecs_changed");
}
fn isAdded(comptime C: type) bool {
    return @typeInfo(C) == .@"struct" and @hasDecl(C, "qaya_ecs_added");
}

fn componentName(comptime T: type) []const u8 {
    const full = @typeName(T);
    const last_dot = std.mem.lastIndexOfScalar(u8, full, '.');
    if (last_dot) |dot| return full[dot + 1 ..];
    return full;
}

/// `components` should be a tuple of types, e.g. `.{Position, *Velocity}`.
pub fn Query(comptime components: anytype) type {
    return struct {
        const Self = @This();
        world: *World,

        last_run_tick: u32,
        world_tick: u32,

        pub const qaya_system_param = true;
        pub fn init(world: *World, last_run_tick: u32) Self {
            return .{ .world = world, .last_run_tick = last_run_tick, .world_tick = world.change_tick };
        }

        pub fn masks() [2]registry.Mask {
            var read: registry.Mask = 0;
            var write: registry.Mask = 0;
            inline for (components) |C| {
                const info = @typeInfo(C);
                if (info == .pointer) {
                    if (info.pointer.is_const) {
                        read |= registry.mask(info.pointer.child);
                    } else {
                        write |= registry.mask(info.pointer.child);
                    }
                } else {
                    read |= registry.mask(C);
                }
            }
            return .{ read, write };
        }

        pub fn get(self: Self, entity: Entity, comptime T: type) ?*T {
            if (comptime !isDeclared(T)) {
                if (!std.debug.runtime_safety) {
                    @compileLog("q.get(" ++ @typeName(T) ++ ") is not in Query(.{" ++ declaredTypes() ++ "}) — may cause races if another system writes to this component");
                }
            }
            return self.world.get(entity, T);
        }

        fn isDeclared(comptime T: type) bool {
            inline for (components) |C| {
                if (childType(C) == T) return true;
            }
            return false;
        }

        fn declaredTypes() []const u8 {
            comptime var s: []const u8 = "";
            inline for (components, 0..) |C, i| {
                const child = childType(C);
                if (i > 0) s = s ++ ", ";
                s = s ++ @typeName(child);
            }
            return s;
        }

        pub const Row = blk: {
            const n = 1 + components.len;
            var field_names: [n][]const u8 = undefined;
            var field_types: [n]type = undefined;
            var field_attrs: [n]std.builtin.Type.StructField.Attributes = undefined;

            for (&field_attrs) |*a| a.* = .{};
            field_names[0] = "entity";
            field_types[0] = world_mod.Entity;

            for (components, 0..) |C, i| {
                const info = @typeInfo(C);
                const child = childType(C);
                field_names[1 + i] = componentName(child);
                field_types[1 + i] = if (isChanged(C) or isAdded(C)) *const child else if (info == .pointer) C else *const C;
            }

            break :blk @Struct(.auto, null, &field_names, &field_types, &field_attrs);
        };

        pub fn iter(self: Self) Iterator {
            const types = comptime blk: {
                var ts: [components.len]type = undefined;
                for (components, 0..) |C, i| {
                    ts[i] = childType(C);
                }
                break :blk ts;
            };
            return .{
                .inner = self.world.queryChunked(&types, 1024),
                .last_run_tick = self.last_run_tick,
            };
        }

        pub fn first(self: Self) ?Row {
            var iterator = self.iter();
            return iterator.next();
        }

        pub const Iterator = struct {
            inner: world_mod.World.QueryChunkIter,
            chunk_entities: []const world_mod.Entity = &.{},
            chunk_row: usize = 0,
            chunk_len: usize = 0,
            chunk_start_row: usize = 0,
            col_bases: [components.len][*]u8 = undefined,
            strides: [components.len]usize = undefined,

            last_run_tick: u32,
            col_ticks: [components.len][*]const @import("column.zig").Column.ComponentTicks = undefined,

            pub fn next(self: *@This()) ?Row {
                while (true) {
                    if (self.chunk_row >= self.chunk_len) {
                        const c = self.inner.next() orelse return null;
                        self.chunk_entities = c.entities;
                        self.chunk_row = 0;
                        self.chunk_len = c.len;
                        self.chunk_start_row = c.start_row;
                        const arch = &self.inner.world.archetypes.items[c.archetype_id];
                        inline for (components, 0..) |C, i| {
                            const child = childType(C);
                            const col = arch.getColumn(registry.id(child)).?;
                            self.col_bases[i] = @as([*]u8, @ptrCast(col.data.ptr));
                            self.strides[i] = col.stride;
                            self.col_ticks[i] = col.ticks.ptr;
                        }
                    }
                    const row_idx = self.chunk_row;
                    self.chunk_row += 1;
                    const abs_row = self.chunk_start_row + row_idx;

                    var skip = false;
                    inline for (components, 0..) |C, i| {
                        if (isChanged(C)) {
                            // If world tick has wrapped or if changed_tick > last_run_tick
                            // A simple > is mostly fine unless you handle wrapping perfectly
                            const changed_tick = self.col_ticks[i][abs_row].changed;
                            if (changed_tick <= self.last_run_tick) {
                                skip = true;
                                break;
                            }
                        } else if (isAdded(C)) {
                            const added_tick = self.col_ticks[i][abs_row].added;
                            if (added_tick <= self.last_run_tick) {
                                skip = true;
                                break;
                            }
                        }
                    }
                    if (skip) continue;

                    var result: Row = undefined;
                    @field(result, "entity") = self.chunk_entities[row_idx];
                    inline for (components, 0..) |C, i| {
                        const byte_ptr = self.col_bases[i] + self.strides[i] * abs_row;
                        const child = childType(C);
                        @field(result, componentName(child)) = @ptrCast(@alignCast(byte_ptr));
                    }
                    return result;
                }
            }
        };
    };
}

/// Wraps a function into a system entry.
pub fn wrap(comptime f: anytype) struct {
    run: *const fn (*World, *u32) anyerror!void,
    last_run_tick: *u32,
    read_mask: registry.Mask,
    write_mask: registry.Mask,
} {
    const F = @TypeOf(f);
    const info = @typeInfo(F);
    if (info != .@"fn") @compileError("System must be a function, found " ++ @typeName(F));

    comptime var is_error: bool = false;
    comptime {
        if (info.@"fn".return_type) |ret| {
            is_error = @typeInfo(ret) == .error_union;
        }
    }

    const Args = std.meta.ArgsTuple(F);

    const WrapperState = struct {
        var last_run_tick: u32 = 0;
        fn run(world: *World, tick_ptr: *u32) anyerror!void {
            var args: Args = undefined;
            var cb: ?CommandBuffer = null;

            inline for (std.meta.fields(Args), 0..) |field, i| {
                if (field.type == *World) {
                    args[i] = world;
                } else if (field.type == Commands()) {
                    cb = CommandBuffer.init(world.allocator);
                    args[i] = .{ .buffer = &cb.? };
                } else if (@hasDecl(field.type, "qaya_system_param")) {
                    if (@hasField(field.type, "last_run_tick")) {
                        args[i] = field.type.init(world, tick_ptr.*);
                    } else {
                        args[i] = field.type.init(world);
                    }
                } else {
                    @compileError("Unsupported system parameter: " ++ @typeName(field.type));
                }
            }

            defer {
                if (cb) |*c| {
                    c.apply(world) catch |err| {
                        std.debug.panic("failed to apply commands: {s}", .{@errorName(err)});
                    };
                    c.deinit();
                }
                inline for (std.meta.fields(Args), 0..) |field, i| {
                    if (field.type != *World and field.type != Commands() and @hasDecl(field.type, "deinit")) {
                        args[i].deinit();
                    }
                }
            }

            if (is_error) {
                try @call(.auto, f, args);
            } else {
                @call(.auto, f, args);
            }
            tick_ptr.* = world.change_tick;
        }
    };

    var read: registry.Mask = 0;
    var write: registry.Mask = 0;
    inline for (info.@"fn".params) |p| {
        const T = p.type orelse continue;
        if (T == *World) continue;
        if (@hasDecl(T, "qaya_system_param")) {
            const m = T.masks();
            read |= m[0];
            write |= m[1];
        }
    }

    return .{
        .run = WrapperState.run,
        .last_run_tick = &WrapperState.last_run_tick,
        .read_mask = read,
        .write_mask = write,
    };
}

/// Wraps a run condition function into an evaluator.
pub fn wrapCond(comptime f: anytype) struct {
    run: *const fn (*World, *u32) anyerror!bool,
    last_run_tick: *u32,
    read_mask: registry.Mask,
    write_mask: registry.Mask,
} {
    const F = @TypeOf(f);
    const info = @typeInfo(F);
    if (info != .@"fn") @compileError("Condition must be a function, found " ++ @typeName(F));

    const Args = std.meta.ArgsTuple(F);

    const CondState = struct {
        var last_run_tick: u32 = 0;
        fn run(world: *World, tick_ptr: *u32) anyerror!bool {
            var args: Args = undefined;

            inline for (std.meta.fields(Args), 0..) |field, i| {
                if (field.type == *World) {
                    args[i] = world;
                } else if (@hasDecl(field.type, "qaya_system_param")) {
                    if (@hasField(field.type, "last_run_tick")) {
                        args[i] = field.type.init(world, tick_ptr.*);
                    } else {
                        args[i] = field.type.init(world);
                    }
                } else {
                    @compileError("Unsupported condition parameter: " ++ @typeName(field.type));
                }
            }

            defer {
                inline for (std.meta.fields(Args), 0..) |field, i| {
                    if (field.type != *World and @hasDecl(field.type, "deinit")) {
                        args[i].deinit();
                    }
                }
            }

            const result = @call(.auto, f, args);
            tick_ptr.* = world.change_tick;
            return result;
        }
    };

    var read: registry.Mask = 0;
    var write: registry.Mask = 0;
    inline for (info.@"fn".params) |p| {
        const T = p.type orelse continue;
        if (T == *World) continue;
        if (@hasDecl(T, "qaya_system_param")) {
            const m = T.masks();
            read |= m[0];
            write |= m[1];
        }
    }

    return .{
        .run = CondState.run,
        .last_run_tick = &CondState.last_run_tick,
        .read_mask = read,
        .write_mask = write,
    };
}

pub fn runIf(sys: anytype, cond: anytype) struct {
    sys: @TypeOf(sys),
    cond: @TypeOf(cond),
    pub const qaya_system_config = true;
} {
    return .{ .sys = sys, .cond = cond };
}

pub fn chain(systems: anytype) struct {
    systems: @TypeOf(systems),
    pub const qaya_system_chain = true;
} {
    return .{ .systems = systems };
}

fn BeforeAfter(comptime f: anytype, comptime label: []const u8, comptime kind: enum { before, after }) type {
    return struct {
        pub const qaya_system_config = true;
        pub const qaya_label = label;
        pub const qaya_kind = kind;
        pub const system_fn = f;
    };
}

pub fn before(comptime label: []const u8, comptime f: anytype) BeforeAfter(f, label, .before) {
    return .{};
}

pub fn after(comptime label: []const u8, comptime f: anytype) BeforeAfter(f, label, .after) {
    return .{};
}
