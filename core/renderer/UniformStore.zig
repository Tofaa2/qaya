const std = @import("std");
const bgfx = @import("bgfx_util.zig").bgfx;
const util = @import("bgfx_util.zig");
const math = @import("math");

const UniformStore = @This();

pub const UniformHandle = bgfx.UniformHandle;
pub const UniformType = enum {
    sampler,
    vec4,
    mat3,
    mat4,
};
pub const UniformValue = union(UniformType) {
    sampler: struct {
        texture: bgfx.TextureHandle,
        flags: u32,
        stage: u8,
    },
    vec4: math.Vec4,
    mat3: math.Mat3,
    mat4: math.Mat4,
};

allocator: std.mem.Allocator,
name_to_id: std.StringHashMap(UniformHandle),
id_to_name: std.AutoHashMap(UniformHandle, [:0]const u8),

pub fn create(self: *UniformStore, name: [:0]const u8, uniform_type: UniformType) UniformHandle {
    return self.createN(name, uniform_type, 1);
}

pub fn createN(self: *UniformStore, name: [:0]const u8, uniform_type: UniformType, num: u16) UniformHandle {
    if (self.name_to_id.get(name)) |handle| {
        return handle;
    }

    const utype: bgfx.UniformType = switch (uniform_type) {
        .sampler => .Sampler,
        .vec4 => .Vec4,
        .mat3 => .Mat3,
        .mat4 => .Mat4,
    };

    const handle = bgfx.createUniform(name, utype, num);
    self.name_to_id.put(name, handle) catch {};
    self.id_to_name.put(handle, name) catch {};
    return handle;
}

pub fn getName(self: *UniformStore, handle: UniformHandle) ?[:0]const u8 {
    return self.id_to_name.get(handle);
}

pub fn getId(self: *UniformStore, name: [:0]const u8) ?UniformHandle {
    return self.name_to_id.get(name);
}

pub fn init(allocator: std.mem.Allocator) UniformStore {
    return .{
        .allocator = allocator,
        .id_to_name = .init(allocator),
        .name_to_id = .init(allocator),
    };
}

pub fn deinit(self: *UniformStore) void {
    var iter = self.id_to_name.iterator();
    while (iter.next()) |entry| {
        bgfx.destroyUniform(entry.key_ptr.*);
    }
    self.id_to_name.deinit();
    self.name_to_id.deinit();
}
