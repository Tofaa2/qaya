const std = @import("std");
const bgfx = @import("bgfx_util.zig").bgfx;
const math = @import("math");
const Material = @import("Material.zig");

const Encoder = @This();

handle: *bgfx.Encoder,

pub fn init() Encoder {
    const enc = bgfx.encoderBegin(false) orelse @panic("failed to create bgfx encoder");
    return .{ .handle = enc };
}

pub fn deinit(self: *Encoder) void {
    bgfx.encoderEnd(self.handle);
}

pub fn setState(self: Encoder, state_flags: u64, rgba: u32) void {
    _ = self.handle.setState(state_flags, rgba);
}

pub fn setTransform(self: Encoder, mtx: *const math.Mat4) void {
    _ = self.handle.setTransform(&mtx.m, 1);
}

pub fn setTransformPtr(self: Encoder, mtx: *const anyopaque) void {
    _ = self.handle.setTransform(mtx, 1);
}

pub fn setUniform(self: Encoder, handle: bgfx.UniformHandle, value: *const anyopaque, num: u16) void {
    _ = self.handle.setUniform(handle, value, num);
}

pub fn setTexture(self: Encoder, stage: u8, sampler: bgfx.UniformHandle, texture: bgfx.TextureHandle, flags: u32) void {
    _ = self.handle.setTexture(stage, sampler, texture, flags);
}

pub fn setVertexBuffer(self: Encoder, stream: u8, handle: bgfx.VertexBufferHandle, start: u32, num: u32) void {
    _ = self.handle.setVertexBuffer(stream, handle, start, num);
}

pub fn setDynamicVertexBuffer(self: Encoder, stream: u8, handle: bgfx.DynamicVertexBufferHandle, start: u32, num: u32) void {
    _ = self.handle.setDynamicVertexBuffer(stream, handle, start, num);
}

pub fn setTransientVertexBuffer(self: Encoder, stream: u8, tvb: *const bgfx.TransientVertexBuffer, start: u32, num: u32) void {
    _ = self.handle.setTransientVertexBuffer(stream, tvb, start, num);
}

pub fn setIndexBuffer(self: Encoder, handle: bgfx.IndexBufferHandle, first: u32, num: u32) void {
    _ = self.handle.setIndexBuffer(handle, first, num);
}

pub fn setDynamicIndexBuffer(self: Encoder, handle: bgfx.DynamicIndexBufferHandle, first: u32, num: u32) void {
    _ = self.handle.setDynamicIndexBuffer(handle, first, num);
}

pub fn setTransientIndexBuffer(self: Encoder, tib: *const bgfx.TransientIndexBuffer, first: u32, num: u32) void {
    _ = self.handle.setTransientIndexBuffer(tib, first, num);
}

pub fn setScissor(self: Encoder, x: u16, y: u16, width: u16, height: u16) void {
    _ = self.handle.setScissor(x, y, width, height);
}

pub fn submit(self: Encoder, view_id: u16, program: bgfx.ProgramHandle, depth: u32, flags: u8) void {
    _ = self.handle.submit(view_id, program, depth, flags);
}

pub fn touch(self: Encoder, view_id: u16) void {
    _ = self.handle.touch(view_id);
}

/// Flush all uniforms from a material onto the encoder.
pub fn submitMaterial(self: Encoder, mat: *const Material) void {
    var iter = mat.uniforms.iterator();
    while (iter.next()) |entry| {
        const handle = entry.key_ptr.*;
        switch (entry.value_ptr.*) {
            .vec4 => |v| {
                const arr = [_]f32{ v.x, v.y, v.z, v.w };
                self.setUniform(handle, &arr, 1);
            },
            .mat3 => |m| {
                var padded: [12]f32 = undefined;
                @memcpy(padded[0..3], m.m[0..3]);
                padded[3] = 0;
                @memcpy(padded[4..7], m.m[3..6]);
                padded[7] = 0;
                @memcpy(padded[8..11], m.m[6..9]);
                padded[11] = 0;
                self.setUniform(handle, &padded, 3);
            },
            .mat4 => |m| {
                self.setUniform(handle, &m.m, 4);
            },
            .sampler => |s| {
                self.setTexture(s.stage, handle, s.texture, std.math.maxInt(u32));
            },
        }
    }
}
