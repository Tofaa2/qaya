const std = @import("std");
const registry = @import("registry.zig");

const World = @import("world.zig").World;
const Entity = @import("entity.zig").Entity;

pub const HookFn = *const fn (*World, Entity) void;

/// Per-component lifecycle hooks.
/// Insert as a resource into the World to enable.
pub const ComponentHooks = struct {
    allocator: std.mem.Allocator,
    on_add: std.AutoHashMapUnmanaged(u32, HookFn) = .empty,
    on_remove: std.AutoHashMapUnmanaged(u32, HookFn) = .empty,

    pub fn init(allocator: std.mem.Allocator) ComponentHooks {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *ComponentHooks) void {
        self.on_add.deinit(self.allocator);
        self.on_remove.deinit(self.allocator);
    }

    pub fn onAdd(self: *ComponentHooks, comptime T: type, callback: HookFn) !void {
        try self.on_add.put(self.allocator, registry.id(T), callback);
    }

    pub fn onRemove(self: *ComponentHooks, comptime T: type, callback: HookFn) !void {
        try self.on_remove.put(self.allocator, registry.id(T), callback);
    }
};
