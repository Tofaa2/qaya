const std = @import("std");

pub const ComponentId = u16;
pub const Mask = u2048;
pub const max_components = 2048;

/// A stable 64-bit hash of a type's name.
pub fn typeId(comptime T: type) u64 {
    return std.hash.Fnv1a_64.hash(@typeName(T));
}

/// Returns a unique ID for a component, mapped to a bitmask index.
/// Guaranteed to be in range [0, max_components).
pub fn id(comptime T: type) ComponentId {
    return @intCast(typeId(T) % max_components);
}

/// Returns a bitmask with only the bit for type T set.
pub fn mask(comptime T: type) Mask {
    return @as(Mask, 1) << @as(std.math.Log2Int(Mask), @intCast(id(T)));
}

pub fn maskMany(comptime types: []const type) Mask {
    var m: Mask = 0;
    inline for (types) |T| {
        m |= mask(T);
    }
    return m;
}

pub fn elementSize(comptime T: type) usize {
    return @sizeOf(T);
}

pub fn elementAlign(comptime T: type) u8 {
    return std.meta.alignment(T);
}

pub fn elementStride(comptime T: type) usize {
    return std.mem.alignForward(usize, @sizeOf(T), std.meta.alignment(T));
}

/// A runtime tracker to detect component ID collisions.
pub const CollisionGuard = struct {
    ids: [max_components]?[]const u8 = .{null} ** max_components,

    pub fn check(self: *CollisionGuard, comptime T: type) void {
        const cid = id(T);
        const name = @typeName(T);
        if (self.ids[cid]) |existing| {
            if (!std.mem.eql(u8, existing, name)) {
                std.debug.panic("Qaya ECS Type Collision! Types '{s}' and '{s}' both hash to ComponentID {d}. Please rename one of them.", .{ existing, name, cid });
            }
        } else {
            self.ids[cid] = name;
        }
    }
};
