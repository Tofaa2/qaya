const std = @import("std");
const bgfx = @import("bgfx_util.zig").bgfx;
const bgfx_util = @import("bgfx_util.zig");
const UniformStore = @import("UniformStore.zig");
const Program = @import("Program.zig");
const Texture = @import("Texture.zig");
const Material = @This();
const pool = @import("pool");
const math = @import("math");
const Data = UniformStore.UniformValue;
const builtin = @import("builtin_shaders");

pub const Pool = pool.PoolManaged(16, Material, Info, Error);

program: Program.Handle,
uniforms: std.AutoArrayHashMapUnmanaged(UniformStore.UniformHandle, Data),
allocator: std.mem.Allocator = undefined,
info: Info,
baked: bool = false,

pub const Info = union(enum) {
    custom: CustomInfo,
    lit: LitInfo,
    pbr: PbrInfo,
    basic: BasicInfo,

    pub const CustomInfo = struct {
        name: []const u8,
        shader: Program.Handle,
    };

    pub const LitInfo = struct {
        base_color_texture: ?[:0]const u8 = null,
        base_color: math.Color = .white,
        shininess: f32 = 32.0,
        specular_strength: f32 = 0.5,
    };

    pub const PbrInfo = struct {
        base_color_texture: ?[:0]const u8 = null,
        base_color: math.Color = .white,
        metallic: f32 = 0.0,
        roughness: f32 = 0.5,
    };

    pub const BasicInfo = struct {};
};

pub fn set(self: *Material, store: *UniformStore, name: [:0]const u8, value: Data) !void {
    const tag = std.meta.activeTag(value);
    const id = store.create(name, tag);
    try self.uniforms.put(self.allocator, id, value);
}

pub fn get(self: *Material, store: *UniformStore, name: [:0]const u8) ?Data {
    const id = store.getId(name) orelse return null;
    return self.uniforms.get(id);
}

pub fn init(info: *const Info) Error!Material {
    return switch (info.*) {
        .custom => |c| Material{
            .program = c.shader,
            .uniforms = .empty,
            .info = info.*,
        },
        .lit, .pbr, .basic => Material{
            .program = undefined,
            .uniforms = .empty,
            .info = info.*,
            .baked = false,
        },
    };
}

pub fn deinit(self: *Material) void {
    self.uniforms.deinit(self.allocator);
}

pub fn needsBake(self: *const Material) bool {
    return switch (self.info) {
        .custom => false,
        .lit, .pbr, .basic => !self.baked,
    };
}

pub fn bake(self: *Material, program_pool: *Program.Pool, uniform_store: *UniformStore, texture_pool: *Texture.Pool) BakeError!void {
    return self.bakeWithFallback(program_pool, uniform_store, texture_pool, null);
}

pub fn bakeWithFallback(self: *Material, program_pool: *Program.Pool, uniform_store: *UniformStore, texture_pool: *Texture.Pool, fallback_texture: ?bgfx.TextureHandle) BakeError!void {
    switch (self.info) {
        .custom => return,
        .lit => {
            const program = try program_pool.load(&Program.Info.initBuiltin(builtin.fs_lit, builtin.vs_lit));
            self.program = program;

            const sampler = uniform_store.create("s_texColor", .sampler);
            if (self.info.lit.base_color_texture) |path| {
                const tex_handle = try texture_pool.load(&.{ .file = .{ .path = path } });
                const tex = texture_pool.get(tex_handle) orelse return error.TextureNotFound;
                try self.uniforms.put(self.allocator, sampler, .{ .sampler = .{ .texture = tex.handle, .flags = 0, .stage = 0 } });
            } else if (fallback_texture) |ft| {
                try self.uniforms.put(self.allocator, sampler, .{ .sampler = .{ .texture = ft, .flags = 0, .stage = 0 } });
            }

            const bc = self.info.lit.base_color;
            const bc_u = uniform_store.create("u_baseColor", .vec4);
            try self.uniforms.put(self.allocator, bc_u, .{ .vec4 = math.Vec4.init(@as(f32, @floatFromInt(bc.r)) / 255.0, @as(f32, @floatFromInt(bc.g)) / 255.0, @as(f32, @floatFromInt(bc.b)) / 255.0, @as(f32, @floatFromInt(bc.a)) / 255.0) });

            const props = uniform_store.create("u_surfaceProps", .vec4);
            try self.uniforms.put(self.allocator, props, .{ .vec4 = math.Vec4.init(self.info.lit.shininess, self.info.lit.specular_strength, 0, 0) });
        },
        .pbr => {
            const program = try program_pool.load(&Program.Info.initBuiltin(builtin.fs_pbr, builtin.vs_pbr));
            self.program = program;

            const sampler = uniform_store.create("s_texColor", .sampler);
            if (self.info.pbr.base_color_texture) |path| {
                const tex_handle = try texture_pool.load(&.{ .file = .{ .path = path } });
                const tex = texture_pool.get(tex_handle) orelse return error.TextureNotFound;
                try self.uniforms.put(self.allocator, sampler, .{ .sampler = .{ .texture = tex.handle, .flags = 0, .stage = 1 } });
            } else if (fallback_texture) |ft| {
                try self.uniforms.put(self.allocator, sampler, .{ .sampler = .{ .texture = ft, .flags = 0, .stage = 1 } });
            }

            const bc = self.info.pbr.base_color;
            const bc_u = uniform_store.create("u_baseColor", .vec4);
            try self.uniforms.put(self.allocator, bc_u, .{ .vec4 = math.Vec4.init(@as(f32, @floatFromInt(bc.r)) / 255.0, @as(f32, @floatFromInt(bc.g)) / 255.0, @as(f32, @floatFromInt(bc.b)) / 255.0, @as(f32, @floatFromInt(bc.a)) / 255.0) });

            const props = uniform_store.create("u_metallicRoughness", .vec4);
            try self.uniforms.put(self.allocator, props, .{ .vec4 = math.Vec4.init(self.info.pbr.metallic, self.info.pbr.roughness, 0, 0) });
        },
        .basic => {
            const program = try program_pool.load(&Program.Info.initBuiltin(builtin.fs_basic, builtin.vs_basic));
            self.program = program;
        },
    }
    self.baked = true;
}

pub const Error = error{};

pub const BakeError = error{
    TextureNotFound,
} || Program.Error || Texture.Error || std.mem.Allocator.Error;
