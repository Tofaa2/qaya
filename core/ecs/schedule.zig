const std = @import("std");
const World = @import("world.zig").World;
const registry = @import("registry.zig");
const system = @import("system.zig");
const Allocator = std.mem.Allocator;

pub const Masks = struct {
    read_mask: registry.Mask,
    write_mask: registry.Mask,
};

pub fn masksConflict(a: Masks, b: Masks) bool {
    if (a.write_mask & b.write_mask != 0) return true;
    if (a.write_mask & b.read_mask != 0) return true;
    if (a.read_mask & b.write_mask != 0) return true;
    return false;
}

pub const Schedule = struct {
    allocator: std.mem.Allocator,
    systems: std.ArrayListUnmanaged(SystemEntry),
    cached_masks: ?[]Masks = null,
    cached_batches: ?[]const []const usize = null,

    const SystemEntry = struct {
        run: *const fn (*World, *u32) anyerror!void,
        run_if: ?*const fn (*World, *u32) anyerror!bool = null,
        last_run_tick: *u32,
        last_cond_tick: ?*u32 = null,
        read_mask: registry.Mask,
        write_mask: registry.Mask,
        dependencies: []usize = &[_]usize{},
        before_label: ?[]const u8 = null,
        after_label: ?[]const u8 = null,
    };

    pub fn reset(self: *@This()) void {
        self.systems.clearAndFree(self.allocator);
        self.cached_masks = null;
        self.cached_batches = null;
    }

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .systems = .empty,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.systems.deinit(self.allocator);
        if (self.cached_masks) |m| self.allocator.free(m);
        if (self.cached_batches) |b| freeBatches(self.allocator, b);
    }

    fn invalidateCache(self: *@This()) void {
        if (self.cached_masks) |m| {
            self.allocator.free(m);
            self.cached_masks = null;
        }
        if (self.cached_batches) |b| {
            freeBatches(self.allocator, b);
            self.cached_batches = null;
        }
    }

    pub fn add(self: *@This(), comptime config: anytype) !void {
        _ = try self.addRecursive(config, null);
    }

    fn addRecursive(self: *@This(), comptime config: anytype, prev: ?usize) !usize {
        const T = @TypeOf(config);
        const is_struct = @typeInfo(T) == .@"struct";
        if (is_struct and @hasDecl(T, "qaya_system_chain")) {
            var last_idx = prev;
            inline for (config.systems) |sys| {
                last_idx = try self.addRecursive(sys, last_idx);
            }
            return last_idx.?;
        } else if (is_struct and @hasDecl(T, "qaya_system_config")) {
            if (@hasDecl(T, "qaya_label")) {
                // before() / after() ordering label
                const w = system.wrap(T.system_fn);
                self.invalidateCache();

                var deps: []usize = &[_]usize{};
                if (prev) |p| {
                    deps = try self.allocator.alloc(usize, 1);
                    deps[0] = p;
                }
                try self.systems.append(self.allocator, .{
                    .run = w.run,
                    .last_run_tick = w.last_run_tick,
                    .read_mask = w.read_mask,
                    .write_mask = w.write_mask,
                    .dependencies = deps,
                    .before_label = if (T.qaya_kind == .before) T.qaya_label else null,
                    .after_label = if (T.qaya_kind == .after) T.qaya_label else null,
                });
                return self.systems.items.len - 1;
            } else {
                // runIf system
                const sys_w = system.wrap(config.sys);
                const cond_w = system.wrapCond(config.cond);
                self.invalidateCache();

                var deps: []usize = &[_]usize{};
                if (prev) |p| {
                    deps = try self.allocator.alloc(usize, 1);
                    deps[0] = p;
                }
                try self.systems.append(self.allocator, .{
                    .run = sys_w.run,
                    .run_if = cond_w.run,
                    .last_run_tick = sys_w.last_run_tick,
                    .last_cond_tick = cond_w.last_run_tick,
                    .read_mask = sys_w.read_mask | cond_w.read_mask,
                    .write_mask = sys_w.write_mask | cond_w.write_mask,
                    .dependencies = deps,
                });
                return self.systems.items.len - 1;
            }
        } else {
            const w = system.wrap(config);
            self.invalidateCache();

            var deps: []usize = &[_]usize{};
            if (prev) |p| {
                deps = try self.allocator.alloc(usize, 1);
                deps[0] = p;
            }
            try self.systems.append(self.allocator, .{
                .run = w.run,
                .last_run_tick = w.last_run_tick,
                .read_mask = w.read_mask,
                .write_mask = w.write_mask,
                .dependencies = deps,
            });
            return self.systems.items.len - 1;
        }
    }

    pub fn addWithMasks(
        self: *@This(),
        comptime read: []const type,
        comptime write: []const type,
        f: *const fn (*World, *u32) anyerror!void,
        tick_ptr: *u32,
    ) !void {
        self.invalidateCache();
        try self.systems.append(self.allocator, .{
            .run = f,
            .last_run_tick = tick_ptr,
            .read_mask = registry.maskMany(read),
            .write_mask = registry.maskMany(write),
        });
    }

    pub fn run(self: *@This(), world: *World, io: std.Io) !void {
        const sys = self.systems.items;
        if (sys.len == 0) return;

        if (self.cached_masks == null) {
            try self.resolveLabels();
            const masks = try self.allocator.alloc(Masks, sys.len);
            for (sys, 0..) |e, i| {
                masks[i] = .{ .read_mask = e.read_mask, .write_mask = e.write_mask };
            }
            self.cached_masks = masks;
            self.cached_batches = try computeBatchesFromMasks(self.allocator, masks, sys);
        }

        const batches = self.cached_batches.?;

        for (batches) |batch| {
            var g: std.Io.Group = .init;
            errdefer g.cancel(io);

            for (batch) |idx| {
                const entry = sys[idx];
                const Runner = struct {
                    fn call(w: *World, e: SystemEntry) void {
                        if (e.run_if) |cond_fn| {
                            const should_run = cond_fn(w, e.last_cond_tick.?) catch |err| {
                                std.debug.panic("condition failed: {s}", .{@errorName(err)});
                            };
                            if (!should_run) return;
                        }
                        e.run(w, e.last_run_tick) catch |err| {
                            std.debug.panic("system failed: {s}", .{@errorName(err)});
                        };
                    }
                };
                g.concurrent(io, Runner.call, .{ world, entry }) catch {
                    Runner.call(world, entry); // Fallback to synchronous execution
                };
            }
            try g.await(io);
        }
    }

    pub fn len(self: *const @This()) usize {
        return self.systems.items.len;
    }

    /// Resolves before/after ordering labels into index-based dependencies.
    /// After resolution, systems with `after("X")` depend on systems with `before("X")`.
    fn resolveLabels(self: *@This()) !void {
        // Collect (label, index) pairs for all before-label systems
        var before_pairs: std.ArrayListUnmanaged(struct { label: []const u8, idx: usize }) = .empty;
        defer before_pairs.deinit(self.allocator);

        for (self.systems.items, 0..) |entry, idx| {
            if (entry.before_label) |label| {
                try before_pairs.append(self.allocator, .{ .label = label, .idx = idx });
            }
        }
        if (before_pairs.items.len == 0) return;

        // For each after-label system, add dependencies to matching before systems
        for (self.systems.items) |*entry| {
            const after_label = entry.after_label orelse continue;

            var deps: std.ArrayListUnmanaged(usize) = .empty;
            errdefer deps.deinit(self.allocator);
            // Copy existing chain dependencies
            for (entry.dependencies) |d| try deps.append(self.allocator, d);

            var added = false;
            for (before_pairs.items) |bp| {
                if (std.mem.eql(u8, bp.label, after_label)) {
                    try deps.append(self.allocator, bp.idx);
                    added = true;
                }
            }

            if (added) {
                const old_deps = entry.dependencies;
                const is_static = @as(*const usize, @ptrCast(old_deps.ptr)) == @as(*const usize, @ptrCast(&[_]usize{}));
                entry.dependencies = try deps.toOwnedSlice(self.allocator);
                if (!is_static) self.allocator.free(old_deps);
            } else {
                deps.deinit(self.allocator);
            }
        }
    }
};

fn computeBatchesFromMasks(allocator: std.mem.Allocator, masks: []const Masks, systems: []const Schedule.SystemEntry) ![]const []const usize {
    var batch_lists: std.ArrayListUnmanaged(std.ArrayListUnmanaged(usize)) = .empty;
    errdefer {
        for (batch_lists.items) |*b| b.deinit(allocator);
        batch_lists.deinit(allocator);
    }

    for (masks, 0..) |sys_mask, i| {
        var min_batch: usize = 0;
        for (systems[i].dependencies) |dep| {
            for (batch_lists.items, 0..) |batch, b_idx| {
                for (batch.items) |sys_idx| {
                    if (sys_idx == dep) {
                        if (b_idx + 1 > min_batch) min_batch = b_idx + 1;
                    }
                }
            }
        }

        var target_batch: usize = min_batch;
        var b = batch_lists.items.len;
        while (b > min_batch) {
            b -= 1;
            const batch = batch_lists.items[b];
            var conflict = false;
            for (batch.items) |j| {
                if (masksConflict(sys_mask, masks[j])) {
                    conflict = true;
                    break;
                }
            }
            if (conflict) {
                target_batch = @max(target_batch, b + 1);
                break;
            }
        }

        if (target_batch == batch_lists.items.len) {
            var nb: std.ArrayListUnmanaged(usize) = .empty;
            try nb.append(allocator, i);
            try batch_lists.append(allocator, nb);
        } else {
            try batch_lists.items[target_batch].append(allocator, i);
        }
    }

    const out = try allocator.alloc([]const usize, batch_lists.items.len);
    errdefer {
        for (out) |batch| allocator.free(batch);
        allocator.free(out);
    }

    for (batch_lists.items, 0..) |*b, bi| {
        out[bi] = try b.toOwnedSlice(allocator);
    }
    for (batch_lists.items) |*b| {
        b.deinit(allocator);
    }
    batch_lists.deinit(allocator);
    return out;
}

fn freeBatches(allocator: std.mem.Allocator, batches: []const []const usize) void {
    for (batches) |b| allocator.free(b);
    allocator.free(batches);
}

pub const Scheduler = struct {
    allocator: std.mem.Allocator,
    stages: std.StringArrayHashMapUnmanaged(Schedule),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .stages = .empty,
        };
    }

    pub fn deinit(self: *@This()) void {
        var it = self.stages.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.stages.deinit(self.allocator);
    }

    /// Add a system to a flexible stage.
    /// Stage can be an enum literal (e.g. .update) or a string.
    pub fn add(self: *@This(), stage: anytype, comptime f: anytype) !void {
        const stage_name = try self.ensureStageName(stage);
        const gop = try self.stages.getOrPut(self.allocator, stage_name);
        if (!gop.found_existing) {
            gop.value_ptr.* = Schedule.init(self.allocator);
        }
        try gop.value_ptr.add(f);
    }

    pub fn run(self: *@This(), stage: anytype, world: *World, io: std.Io) !void {
        const stage_name = try self.ensureStageName(stage);
        if (self.stages.getPtr(stage_name)) |sched| {
            try sched.run(world, io);
        }
    }

    fn ensureStageName(_: *@This(), stage: anytype) ![]const u8 {
        const T = @TypeOf(stage);
        if (T == []const u8) return stage;
        const info = @typeInfo(T);
        if (info == .@"enum_literal") {
            return @tagName(stage);
        }
        if (info == .@"enum") {
            return @tagName(stage);
        }
        @compileError("Stage must be an enum literal, enum, or string, found " ++ @typeName(T));
    }
};
