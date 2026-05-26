const std = @import("std");
const Entity = @import("entity.zig").Entity;

/// Tracks parent->children relationships.
/// Insert as a resource into the World to enable relationship queries.
pub const Hierarchy = struct {
    allocator: std.mem.Allocator,
    children: std.AutoHashMapUnmanaged(Entity, std.ArrayListUnmanaged(Entity)) = .empty,

    pub fn init(allocator: std.mem.Allocator) Hierarchy {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Hierarchy) void {
        var it = self.children.valueIterator();
        while (it.next()) |list| {
            list.deinit(self.allocator);
        }
        self.children.deinit(self.allocator);
    }

    pub fn addChild(self: *Hierarchy, parent: Entity, child: Entity) !void {
        const gop = try self.children.getOrPut(self.allocator, parent);
        if (!gop.found_existing) {
            gop.value_ptr.* = std.ArrayListUnmanaged(Entity).empty;
        }
        try gop.value_ptr.append(self.allocator, child);
    }

    pub fn removeChild(self: *Hierarchy, parent: Entity, child: Entity) void {
        const list = self.children.getPtr(parent) orelse return;
        for (list.items, 0..) |c, i| {
            if (c.index == child.index and c.generation == child.generation) {
                _ = list.swapRemove(i);
                break;
            }
        }
        if (list.items.len == 0) {
            list.deinit(self.allocator);
            _ = self.children.remove(parent);
        }
    }

    pub fn removeAll(self: *Hierarchy, parent: Entity) void {
        const list = self.children.getPtr(parent) orelse return;
        list.deinit(self.allocator);
        _ = self.children.remove(parent);
    }

    pub fn getChildren(self: *Hierarchy, parent: Entity) ?[]const Entity {
        const list = self.children.getPtr(parent) orelse return null;
        return list.items;
    }
};
