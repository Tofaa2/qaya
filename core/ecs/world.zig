const std = @import("std");
const registry = @import("registry.zig");
const archetype_mod = @import("archetype.zig");
const Archetype = archetype_mod.Archetype;
pub const ArchetypeId = archetype_mod.ArchetypeId;
pub const Entity = @import("entity.zig").Entity;
const ResourcePool = @import("ResourcePool.zig");
const EventChannel = @import("EventChannel.zig").EventChannel;
const schedule = @import("schedule.zig");
const EventSystemRegistry = @import("EventSystem.zig").EventSystemRegistry;
const hooks_mod = @import("hooks.zig");

pub const World = struct {
    const Self = @This();

    pub const EntitySlot = struct {
        generation: u32,
        alive: bool,
        archetype: ArchetypeId,
        row: u32,
    };

    allocator: std.mem.Allocator,
    io: std.Io,
    archetypes: std.ArrayListUnmanaged(Archetype),
    archetype_by_sig: std.AutoHashMapUnmanaged(registry.Mask, ArchetypeId),
    entities: std.ArrayListUnmanaged(EntitySlot),
    free_slots: std.ArrayListUnmanaged(u32),
    resources: ResourcePool,
    event_tick_fns: std.ArrayListUnmanaged(*const fn (*Self) void),
    event_systems: EventSystemRegistry,
    scheduler: schedule.Scheduler,
    rw_lock: std.Io.RwLock,
    migration_cache: struct {
        src: ArchetypeId = 0,
        dst: ArchetypeId = 0,
        comp_id: u32 = 0,
        valid: bool = false,
    } = .{},
    collision_guard: registry.CollisionGuard = .{},
    change_tick: u32 = 1,
    last_change_tick: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) Self {
        var res: ResourcePool = undefined;
        res.init(allocator, io);
        return .{
            .allocator = allocator,
            .io = io,
            .archetypes = .empty,
            .archetype_by_sig = .empty,
            .entities = .empty,
            .free_slots = .empty,
            .resources = res,
            .event_tick_fns = .empty,
            .event_systems = EventSystemRegistry.init(allocator),
            .scheduler = schedule.Scheduler.init(allocator),
            .rw_lock = .init,
            .change_tick = 1,
            .last_change_tick = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.scheduler.deinit();
        self.event_systems.deinit();
        self.resources.deinit();
        const it = self.archetypes.items;
        for (it) |*arch| {
            arch.deinit(self.allocator);
        }
        self.archetypes.deinit(self.allocator);
        self.archetype_by_sig.deinit(self.allocator);
        self.entities.deinit(self.allocator);
        self.free_slots.deinit(self.allocator);
        self.event_tick_fns.deinit(self.allocator);
    }

    pub fn reset(self: *Self) void {
        self.lock();
        defer self.unlock();
        for (self.archetypes.items) |*arch| {
            arch.deinit(self.allocator);
        }
        self.archetypes.clearRetainingCapacity();
        self.archetype_by_sig.clearRetainingCapacity();
        self.entities.clearRetainingCapacity();
        self.free_slots.clearRetainingCapacity();
        self.resources.reset();
        self.change_tick = 1;
        self.last_change_tick = 0;
    }

    pub fn incrementTick(self: *Self) void {
        self.last_change_tick = self.change_tick;
        self.change_tick +%= 1;
    }

    pub fn lock(self: *Self) void {
        self.rw_lock.lock(self.io) catch unreachable;
    }

    pub fn unlock(self: *Self) void {
        self.rw_lock.unlock(self.io);
    }

    pub fn sharedLock(self: *Self) void {
        self.rw_lock.lockShared(self.io) catch unreachable;
    }

    pub fn sharedUnlock(self: *Self) void {
        self.rw_lock.unlockShared(self.io);
    }

    pub fn isAlive(self: *Self, e: Entity) bool {
        if (e.index >= self.entities.items.len) return false;
        const s = self.entities.items[e.index];
        return s.alive and s.generation == e.generation;
    }

    pub fn spawn(self: *Self, bundle: anytype) !Entity {
        const V = @TypeOf(bundle);
        const info = @typeInfo(V);

        if (info != .@"struct") @compileError("spawn expects a tuple or a bundle struct");
        const is_tuple = info.@"struct".is_tuple;
        if (!is_tuple and !@hasDecl(V, "qaya_bundle"))
            @compileError("spawn expects a tuple or a bundle struct (with `pub const qaya_bundle = true;`)");

        const fields = std.meta.fields(V);
        const types = comptime blk: {
            var ts: [fields.len]type = undefined;
            for (fields, 0..) |field, i| ts[i] = field.type;
            const final_ts = ts;
            break :blk &final_ts;
        };

        self.lock();
        defer self.unlock();

        if (comptime std.debug.runtime_safety) {
            inline for (fields) |field| {
                self.collision_guard.check(field.type);
            }
        }

        const sig = registry.maskMany(types);
        const e = try self.allocEntity();
        const arch_id = try self.ensureArchetype(sig);
        const arch = &self.archetypes.items[arch_id];
        const row = try arch.appendRow(self.allocator, e, sig, types, bundle, self.change_tick);
        self.entities.items[e.index] = .{
            .generation = e.generation,
            .alive = true,
            .archetype = arch_id,
            .row = @intCast(row),
        };
        return e;
    }

    pub fn despawn(self: *Self, e: Entity) void {
        self.lock();
        defer self.unlock();
        if (!self.isAlive(e)) return;
        const slot = &self.entities.items[e.index];
        const arch = &self.archetypes.items[slot.archetype];
        const moved = arch.swapRemoveRow(self.allocator, slot.row) catch return;
        if (moved) |m| {
            if (m.index != e.index) {
                self.entities.items[m.index].row = slot.row;
            }
        }
        slot.alive = false;
        slot.generation +|= 1;
        self.free_slots.append(self.allocator, e.index) catch {};
    }

    pub fn despawnBatch(self: *Self, entities: []const Entity) void {
        self.lock();
        defer self.unlock();

        self.free_slots.ensureUnusedCapacity(self.allocator, entities.len) catch {};

        for (entities) |e| {
            if (!self.isAlive(e)) continue;
            const slot = &self.entities.items[e.index];
            const arch = &self.archetypes.items[slot.archetype];
            const moved = arch.swapRemoveRow(self.allocator, slot.row) catch continue;
            if (moved) |m| {
                if (m.index != e.index) {
                    self.entities.items[m.index].row = slot.row;
                }
            }
            slot.alive = false;
            slot.generation +|= 1;
            self.free_slots.appendAssumeCapacity(e.index);
        }
    }

    pub fn triggerAddHook(self: *Self, comptime T: type, e: Entity) void {
        if (self.resources.get(hooks_mod.ComponentHooks)) |hooks| {
            if (hooks.on_add.get(registry.id(T))) |hook| {
                hook(self, e);
            }
        }
    }

    pub fn triggerRemoveHook(self: *Self, comptime T: type, e: Entity) void {
        if (self.resources.get(hooks_mod.ComponentHooks)) |hooks| {
            if (hooks.on_remove.get(registry.id(T))) |hook| {
                hook(self, e);
            }
        }
    }

    pub fn addComponent(self: *Self, e: Entity, comptime T: type, value: T) !void {
        if (!self.isAlive(e)) return error.DeadEntity;

        if (comptime std.debug.runtime_safety) {
            self.collision_guard.check(T);
        }

        self.lock();
        defer self.unlock();

        const slot = &self.entities.items[e.index];
        const old_arch_id = slot.archetype;
        const old_row: u32 = slot.row;
        const cid = registry.id(T);

        var new_arch_id: ArchetypeId = undefined;
        if (self.migration_cache.valid and self.migration_cache.src == old_arch_id and self.migration_cache.comp_id == cid) {
            new_arch_id = self.migration_cache.dst;
        } else {
            const old_sig = self.archetypes.items[old_arch_id].signature;
            const bit = registry.mask(T);
            if (old_sig & bit != 0) return error.AlreadyHasComponent;
            new_arch_id = try self.ensureArchetype(old_sig | bit);
            self.migration_cache = .{ .src = old_arch_id, .dst = new_arch_id, .comp_id = cid, .valid = true };
        }

        const old_arch = &self.archetypes.items[old_arch_id];
        const moved_entity = try old_arch.migrate(self.allocator, old_row, &self.archetypes.items[new_arch_id]);
        if (moved_entity) |m| {
            if (m.index != e.index) {
                self.entities.items[m.index].row = old_row;
            }
        }

        const new_arch = &self.archetypes.items[new_arch_id];
        const new_row = new_arch.entities.items.len - 1;
        try new_arch.ensureColumn(self.allocator, cid, T);
        const col = new_arch.getColumn(cid).?;
        _ = try col.pushUninitialized(self.allocator, self.change_tick);
        @as(*T, @ptrCast(@alignCast(col.rowPtr(new_row)))).* = value;
        col.ticks[new_row].changed = self.change_tick;

        slot.archetype = new_arch_id;
        slot.row = @intCast(new_row);

        self.triggerAddHook(T, e);
    }

    pub fn addComponents(self: *Self, e: Entity, values: anytype) !void {
        const V = @TypeOf(values);
        const info = @typeInfo(V);
        if (info != .@"struct" or !info.@"struct".is_tuple) @compileError("addComponents expects a tuple");

        const types = comptime blk: {
            const fields = std.meta.fields(V);
            var ts: [fields.len]type = undefined;
            for (fields, 0..) |field, i| ts[i] = field.type;
            const final_ts = ts;
            break :blk &final_ts;
        };

        self.lock();
        defer self.unlock();
        if (!self.isAlive(e)) return error.DeadEntity;

        const slot = &self.entities.items[e.index];
        const old_arch_id = slot.archetype;
        const old_row: u32 = slot.row;
        const old_sig = self.archetypes.items[old_arch_id].signature;
        const new_mask = registry.maskMany(types);

        if (old_sig & new_mask != 0) return error.AlreadyHasComponent;
        const new_sig = old_sig | new_mask;
        const new_arch_id = try self.ensureArchetype(new_sig);
        if (new_arch_id == old_arch_id) return;

        const old_arch = &self.archetypes.items[old_arch_id];
        const moved_entity = try old_arch.migrate(self.allocator, old_row, &self.archetypes.items[new_arch_id]);
        if (moved_entity) |m| {
            if (m.index != e.index) {
                self.entities.items[m.index].row = old_row;
            }
        }

        const new_arch = &self.archetypes.items[new_arch_id];
        const new_row = new_arch.entities.items.len - 1;

        inline for (std.meta.fields(V), 0..) |field, i| {
            const T = field.type;
            try new_arch.ensureColumn(self.allocator, registry.id(T), T);
            const col = new_arch.getColumn(registry.id(T)).?;
            _ = try col.pushUninitialized(self.allocator, self.change_tick);
            @as(*T, @ptrCast(@alignCast(col.rowPtr(new_row)))).* = values[i];
            col.ticks[new_row].changed = self.change_tick;
        }

        slot.archetype = new_arch_id;
        slot.row = @intCast(new_row);
        self.migration_cache.valid = false; // Invalidate cache for complex mutations

        inline for (std.meta.fields(V)) |field| {
            self.triggerAddHook(field.type, e);
        }
    }

    pub fn removeComponent(self: *Self, e: Entity, comptime T: type) !void {
        self.lock();
        defer self.unlock();
        if (!self.isAlive(e)) return error.DeadEntity;

        const slot = &self.entities.items[e.index];
        const old_arch_id = slot.archetype;
        const old_row: u32 = slot.row;
        const cid = registry.id(T);

        var new_arch_id: ArchetypeId = undefined;
        if (self.migration_cache.valid and self.migration_cache.src == old_arch_id and self.migration_cache.comp_id == ~cid) {
            new_arch_id = self.migration_cache.dst;
        } else {
            const old_sig = self.archetypes.items[old_arch_id].signature;
            const bit = registry.mask(T);
            if (old_sig & bit == 0) return error.ComponentNotFound;
            new_arch_id = try self.ensureArchetype(old_sig & ~bit);
            self.migration_cache = .{ .src = old_arch_id, .dst = new_arch_id, .comp_id = ~cid, .valid = true };
        }

        const old_arch = &self.archetypes.items[old_arch_id];
        const moved_entity = try old_arch.migrate(self.allocator, old_row, &self.archetypes.items[new_arch_id]);
        if (moved_entity) |m| {
            if (m.index != e.index) {
                self.entities.items[m.index].row = old_row;
            }
        }

        slot.archetype = new_arch_id;
        slot.row = @intCast(self.archetypes.items[new_arch_id].entities.items.len - 1);

        self.triggerRemoveHook(T, e);
    }

    pub fn removeComponents(self: *Self, e: Entity, comptime types: []const type) !void {
        self.lock();
        defer self.unlock();
        if (!self.isAlive(e)) return error.DeadEntity;

        const slot = &self.entities.items[e.index];
        const old_arch_id = slot.archetype;
        const old_row: u32 = slot.row;
        const old_sig = self.archetypes.items[old_arch_id].signature;
        const rem_mask = registry.maskMany(types);

        if (old_sig & rem_mask != rem_mask) return error.ComponentNotFound;
        const new_sig = old_sig & ~rem_mask;
        const new_arch_id = try self.ensureArchetype(new_sig);
        if (new_arch_id == old_arch_id) return;

        const old_arch = &self.archetypes.items[old_arch_id];
        const moved_entity = try old_arch.migrate(self.allocator, old_row, &self.archetypes.items[new_arch_id]);
        if (moved_entity) |m| {
            if (m.index != e.index) {
                self.entities.items[m.index].row = old_row;
            }
        }

        slot.archetype = new_arch_id;
        slot.row = @intCast(self.archetypes.items[new_arch_id].entities.items.len - 1);

        inline for (types) |T| {
            self.triggerRemoveHook(T, e);
        }
    }

    pub fn emit(self: *Self, event: anytype) void {
        const T = @TypeOf(event);
        const chan = self.resources.getMut(EventChannel(T)) orelse {
            var new_chan = EventChannel(T).init(self.allocator, self.io);
            new_chan.send(event) catch unreachable;
            self.insertResource(new_chan);
            self.event_tick_fns.append(self.allocator, struct {
                fn tick(w: *Self) void {
                    if (w.resources.getMut(EventChannel(T))) |c| {
                        // Dispatch event systems before ticking
                        w.event_systems.dispatch(w, T, c.buffers[c.write_idx].items);
                        c.tick();
                    }
                }
            }.tick) catch unreachable;
            return;
        };
        chan.send(event) catch unreachable;
    }

    pub fn subscribe(self: *Self, comptime E: type, ctx: anytype, callback: anytype) !void {
        const chan = self.resources.getMut(EventChannel(E)) orelse {
            var new_chan = EventChannel(E).init(self.allocator, self.io);
            self.insertResource(new_chan);
            self.event_tick_fns.append(self.allocator, struct {
                fn tick(w: *Self) void {
                    if (w.resources.getMut(EventChannel(E))) |c| {
                        w.event_systems.dispatch(w, E, c.buffers[c.write_idx].items);
                        c.tick();
                    }
                }
            }.tick) catch unreachable;
            try new_chan.subscribe(ctx, callback);
            return;
        };
        try chan.subscribe(ctx, callback);
    }

    /// Register an event handler as an ECS system.
    /// The handler will be called once per event during tickEvents().
    ///
    /// Handler signature: `fn(event: E, ...ecs_params...) !void`
    /// Supported params: the event type, `*World`, `Res`, `ResMut`, `Query`, `Commands`, `Events`
    ///
    /// Example:
    ///   world.addEventSystem(CollisionEvent, handleCollision);
    ///
    ///   fn handleCollision(event: CollisionEvent, query: Query(.{ *Position }), res: Res(GameState)) !void {
    ///       // process event
    ///   }
    pub fn addEventSystem(self: *Self, comptime E: type, comptime handler: anytype) void {
        self.event_systems.add(E, handler);
    }

    pub fn registerComponent(self: *Self, comptime T: type) void {
        if (comptime std.debug.runtime_safety) {
            self.collision_guard.check(T);
        }
    }

    pub fn registerEvent(self: *Self, comptime E: type) void {
        _ = self.eventReader(E);
    }

    pub fn allocEntity(self: *Self) !Entity {
        if (self.free_slots.items.len > 0) {
            const idx = self.free_slots.pop().?;
            const s = &self.entities.items[idx];
            s.generation +|= 1;
            return .{ .index = idx, .generation = s.generation };
        }
        const idx: u32 = @intCast(self.entities.items.len);
        try self.entities.append(self.allocator, .{
            .generation = 0,
            .alive = false,
            .archetype = 0,
            .row = 0,
        });
        return .{ .index = idx, .generation = 0 };
    }

    pub fn ensureArchetype(self: *Self, sig: registry.Mask) !ArchetypeId {
        const gop = try self.archetype_by_sig.getOrPut(self.allocator, sig);
        if (gop.found_existing) return gop.value_ptr.*;

        const id = @as(ArchetypeId, @intCast(self.archetypes.items.len));
        const arch = try archetype_mod.create(self.allocator, id, sig);
        try self.archetypes.append(self.allocator, arch);
        gop.value_ptr.* = id;
        return id;
    }

    pub fn get(self: *Self, e: Entity, comptime T: type) ?*T {
        if (!self.isAlive(e)) return null;
        const slot = self.entities.items[e.index];
        const arch = &self.archetypes.items[slot.archetype];
        if (arch.signature & registry.mask(T) == 0) return null;
        const col = arch.getColumn(registry.id(T)).?;
        return @ptrCast(@alignCast(col.rowPtr(slot.row)));
    }

    pub fn getMut(self: *Self, e: Entity, comptime T: type) ?*T {
        if (!self.isAlive(e)) return null;
        const slot = &self.entities.items[e.index];
        const arch = &self.archetypes.items[slot.archetype];
        if (arch.signature & registry.mask(T) == 0) return null;
        const col = arch.getColumn(registry.id(T)).?;
        col.ticks[slot.row].changed = self.change_tick;
        return @ptrCast(@alignCast(col.rowPtr(slot.row)));
    }

    pub fn insertResource(self: *Self, value: anytype) void {
        self.resources.add(value) catch |err| {
            if (err != error.ResourceAlreadyExists) {
                std.debug.panic("failed to insert resource: {s}", .{@errorName(err)});
            }
        };
    }

    pub fn getResource(self: *Self, comptime T: type) ?*const T {
        return self.resources.get(T);
    }

    pub fn getMutResource(self: *Self, comptime T: type) ?*T {
        return self.resources.getMut(T);
    }

    /// WARNING: Deprecated, use `getEventChannel` instead.
    pub fn eventReader(self: *Self, comptime E: type) EventChannel(E).View {
        const chan = self.resources.getMut(EventChannel(E)) orelse {
            var new_chan = EventChannel(E).init(self.allocator, self.io);
            self.insertResource(new_chan);
            self.event_tick_fns.append(self.allocator, struct {
                fn tick(w: *Self) void {
                    if (w.resources.getMut(EventChannel(E))) |c| {
                        w.event_systems.dispatch(w, E, c.buffers[c.write_idx].items);
                        c.tick();
                    }
                }
            }.tick) catch unreachable;
            return new_chan.read();
        };
        return chan.read();
    }

    pub fn eventChannelExists(self: *Self, comptime E: type) bool {
        return self.resources.getMut(EventChannel(E)) != null;
    }

    pub fn getEventChannel(self: *Self, comptime E: type) *EventChannel(E) {
        return self.resources.getMut(EventChannel(E)) orelse {
            const new_chan = EventChannel(E).init(self.allocator, self.io);
            self.insertResource(new_chan);
            self.event_tick_fns.append(self.allocator, struct {
                fn tick(w: *Self) void {
                    if (w.resources.getMut(EventChannel(E))) |c| {
                        w.event_systems.dispatch(w, E, c.buffers[c.write_idx].items);
                        c.tick();
                    }
                }
            }.tick) catch unreachable;
            return self.resources.getMut(EventChannel(E)).?;
        };
    }

    pub fn publish(self: *Self, comptime E: type, event: E) void {
        const chan = self.resources.getMut(EventChannel(E)) orelse {
            var new_chan = EventChannel(E).init(self.allocator, self.io);
            new_chan.send(event) catch unreachable;
            self.insertResource(new_chan);
            self.event_tick_fns.append(self.allocator, struct {
                fn tick(w: *Self) void {
                    if (w.resources.getMut(EventChannel(E))) |c| {
                        w.event_systems.dispatch(w, E, c.buffers[c.write_idx].items);
                        c.tick();
                    }
                }
            }.tick) catch unreachable;
            return;
        };
        chan.send(event) catch unreachable;
    }

    pub fn tickEvents(self: *Self) void {
        for (self.event_tick_fns.items) |tick| {
            tick(self);
        }
    }

    pub fn query(self: *Self, comptime types: []const type) QueryIter {
        return .{
            .world = self,
            .arch_index = 0,
            .row = 0,
            .required_mask = registry.maskMany(types),
        };
    }

    pub const QueryIter = struct {
        world: *Self,
        arch_index: usize,
        row: usize,
        required_mask: registry.Mask,

        pub fn next(self: *QueryIter) ?struct {
            entity: Entity,
            signature: registry.Mask,
            archetype_id: ArchetypeId,
            row: usize,
        } {
            while (self.arch_index < self.world.archetypes.items.len) {
                const arch = &self.world.archetypes.items[self.arch_index];
                if (arch.signature & self.required_mask != self.required_mask) {
                    self.arch_index += 1;
                    self.row = 0;
                    continue;
                }
                if (self.row < arch.entities.items.len) {
                    const r = self.row;
                    self.row += 1;
                    return .{
                        .entity = arch.entities.items[r],
                        .signature = arch.signature,
                        .archetype_id = arch.id,
                        .row = r,
                    };
                }
                self.arch_index += 1;
                self.row = 0;
            }
            return null;
        }
    };

    pub fn queryChunked(self: *Self, comptime types: []const type, chunk_size: usize) QueryChunkIter {
        return .{
            .world = self,
            .arch_index = 0,
            .row = 0,
            .required_mask = registry.maskMany(types),
            .chunk_size = chunk_size,
        };
    }

    pub const QueryChunkIter = struct {
        world: *Self,
        arch_index: usize,
        row: usize,
        required_mask: registry.Mask,
        chunk_size: usize,

        pub fn next(self: *QueryChunkIter) ?struct {
            signature: registry.Mask,
            archetype_id: ArchetypeId,
            start_row: usize,
            len: usize,
            entities: []const Entity,
        } {
            while (self.arch_index < self.world.archetypes.items.len) {
                const arch = &self.world.archetypes.items[self.arch_index];
                if (arch.signature & self.required_mask != self.required_mask) {
                    self.arch_index += 1;
                    self.row = 0;
                    continue;
                }
                if (self.row < arch.entities.items.len) {
                    const start = self.row;
                    const len = @min(self.chunk_size, arch.entities.items.len - start);
                    self.row += len;
                    return .{
                        .signature = arch.signature,
                        .archetype_id = arch.id,
                        .start_row = start,
                        .len = len,
                        .entities = arch.entities.items[start .. start + len],
                    };
                }
                self.arch_index += 1;
                self.row = 0;
            }
            return null;
        }
    };

    pub fn columnPtr(self: *Self, comptime T: type, arch_id: ArchetypeId, row: usize) *T {
        const arch = &self.archetypes.items[arch_id];
        const col = arch.getColumn(registry.id(T)).?;
        return @ptrCast(@alignCast(col.rowPtr(row)));
    }

    pub fn columnSlice(self: *Self, comptime T: type, arch_id: ArchetypeId, start: usize, len: usize) ?[]T {
        const arch = &self.archetypes.items[arch_id];
        const col = arch.getColumn(registry.id(T)) orelse return null;
        for (start..start + len) |i| {
            col.ticks[i].changed = self.change_tick;
        }
        return @ptrCast(@alignCast(col.rowPtr(start)[0 .. len * col.stride]));
    }
};
