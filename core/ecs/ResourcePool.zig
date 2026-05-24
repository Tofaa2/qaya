/// Type-safe, type-keyed resource storage.
/// Resources are singletons keyed by their Zig type — one instance per type.
const std = @import("std");
const typeIdInt = @import("util/type_id.zig").typeIdInt;
const ResourcePool = @This();

const ResourceEntry = struct {
    ptr: *anyopaque,
    destroyFn: *const fn (allocator: std.mem.Allocator, ptr: *anyopaque) void,
    priority: i32 = 0,
};

allocator: std.mem.Allocator,
io: std.Io,
map: std.AutoHashMapUnmanaged(usize, ResourceEntry),
rwl: std.Io.RwLock = .init,

pub fn init(self: *ResourcePool, allocator: std.mem.Allocator, io: std.Io) void {
    self.* = .{
        .allocator = allocator,
        .io = io,
        .map = .{},
    };
}

pub fn deinit(self: *ResourcePool) void {
    self.rwl.lockUncancelable(self.io);

    const count = self.map.count();
    const entries = self.allocator.alloc(ResourceEntry, count) catch @panic("OOM");
    defer self.allocator.free(entries);
    {
        var it = self.map.valueIterator();
        var i: usize = 0;
        while (it.next()) |entry| : (i += 1) {
            entries[i] = entry.*;
        }
    }
    std.sort.pdq(ResourceEntry, entries, {}, struct {
        fn lessThan(_: void, a: ResourceEntry, b: ResourceEntry) bool {
            return a.priority > b.priority;
        }
    }.lessThan);
    for (entries) |entry| {
        entry.destroyFn(self.allocator, entry.ptr);
    }

    self.map.deinit(self.allocator);
    // No unlock — pool is dead after deinit.
}

/// Resets the entire pool, destroying all stored resources.
pub fn reset(self: *ResourcePool) void {
    self.rwl.lockUncancelable(self.io);
    defer self.rwl.unlock(self.io);

    const count = self.map.count();
    const entries = self.allocator.alloc(ResourceEntry, count) catch @panic("OOM");
    defer self.allocator.free(entries);
    {
        var it = self.map.valueIterator();
        var i: usize = 0;
        while (it.next()) |entry| : (i += 1) {
            entries[i] = entry.*;
        }
    }
    std.sort.pdq(ResourceEntry, entries, {}, struct {
        fn lessThan(_: void, a: ResourceEntry, b: ResourceEntry) bool {
            return a.priority > b.priority;
        }
    }.lessThan);
    for (entries) |entry| {
        entry.destroyFn(self.allocator, entry.ptr);
    }

    self.map.clearAndFree(self.allocator);
}

/// Add a resource by value (copied into the pool).
pub fn add(self: *ResourcePool, value: anytype) !void {
    self.rwl.lockUncancelable(self.io);
    defer self.rwl.unlock(self.io);

    const T = @TypeOf(value);
    const id = typeIdInt(T);
    if (self.map.contains(id)) return error.ResourceAlreadyExists;

    const ptr = try self.allocator.create(T);
    ptr.* = value;
    try self.map.put(self.allocator, id, .{
        .ptr = ptr,
        .destroyFn = makeDestroyFn(T),
        .priority = priorityOf(T),
    });
}

/// Add a resource by pointer (pool takes ownership).
pub fn addOwned(self: *ResourcePool, comptime T: type, ptr: *T) !void {
    self.rwl.lockUncancelable(self.io);
    defer self.rwl.unlock(self.io);

    const id = typeIdInt(T);
    if (self.map.contains(id)) return error.ResourceAlreadyExists;
    try self.map.put(self.allocator, id, .{
        .ptr = ptr,
        .destroyFn = makeDestroyFn(T),
        .priority = priorityOf(T),
    });
}

/// Add a resource by pointer without taking ownership.
pub fn addBorrowed(self: *ResourcePool, comptime T: type, ptr: *T) !void {
    self.rwl.lockUncancelable(self.io);
    defer self.rwl.unlock(self.io);

    const id = typeIdInt(T);
    if (self.map.contains(id)) return error.ResourceAlreadyExists;
    try self.map.put(self.allocator, id, .{
        .ptr = ptr,
        .destroyFn = struct {
            fn noop(_: std.mem.Allocator, _: *anyopaque) void {}
        }.noop,
    });
}

/// Immutable (shared) access. Returns null if resource not found.
pub fn get(self: *ResourcePool, comptime T: type) ?*const T {
    self.rwl.lockSharedUncancelable(self.io);
    defer self.rwl.unlockShared(self.io);

    const entry = self.map.get(typeIdInt(T)) orelse return null;
    return @as(*const T, @ptrCast(@alignCast(entry.ptr)));
}

/// Mutable (exclusive) access. Returns null if resource not found.
pub fn getMut(self: *ResourcePool, comptime T: type) ?*T {
    self.rwl.lockUncancelable(self.io);
    defer self.rwl.unlock(self.io);

    const entry = self.map.get(typeIdInt(T)) orelse return null;
    return @as(*T, @ptrCast(@alignCast(entry.ptr)));
}

pub fn has(self: *ResourcePool, comptime T: type) bool {
    self.rwl.lockSharedUncancelable(self.io);
    defer self.rwl.unlockShared(self.io);
    return self.map.contains(typeIdInt(T));
}

fn priorityOf(comptime T: type) i32 {
    return if (@hasDecl(T, "deinit_priority")) T.deinit_priority else @as(i32, 0);
}

fn makeDestroyFn(comptime T: type) *const fn (std.mem.Allocator, *anyopaque) void {
    return struct {
        fn destroy(allocator: std.mem.Allocator, raw: *anyopaque) void {
            const typed: *T = @ptrCast(@alignCast(raw));
            if (@hasDecl(T, "deinit")) {
                typed.deinit();
            }
            allocator.destroy(typed);
        }
    }.destroy;
}
