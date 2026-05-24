const std = @import("std");
const bgfx = @import("bgfx_util.zig").bgfx;
const isValid = @import("bgfx_util.zig").isValid;
const math = @import("math");
const Encoder = @import("Encoder.zig");
const Program = @import("Program.zig");
const UniformStore = @import("UniformStore.zig");
const vertex_parser = @import("vertex_parser.zig");

pub const EnvironmentMap = struct {
    texture: bgfx.TextureHandle,
    intensity: f32,
};

const Skybox = @This();

program: bgfx.ProgramHandle,
vb: bgfx.VertexBufferHandle,
ib: bgfx.IndexBufferHandle,
s_env_map: bgfx.UniformHandle,
u_env_intensity: bgfx.UniformHandle,

pub fn deinit(self: *Skybox) void {
    if (isValid(self.vb)) bgfx.destroyVertexBuffer(self.vb);
    if (isValid(self.ib)) bgfx.destroyIndexBuffer(self.ib);
}

pub fn init(program_pool: *Program.Pool, uniform_store: *UniformStore) !Skybox {
    const builtin = @import("builtin_shaders");
    const prog_handle = try program_pool.load(&Program.Info.initBuiltin(builtin.fs_skybox, builtin.vs_skybox));
    const prog = program_pool.get(prog_handle) orelse return error.SkyboxInitFailed;

    const cube = generateUnitCube();
    errdefer bgfx.destroyVertexBuffer(cube.vb);
    errdefer bgfx.destroyIndexBuffer(cube.ib);

    return Skybox{
        .program = prog.handle,
        .vb = cube.vb,
        .ib = cube.ib,
        .s_env_map = uniform_store.create("s_envMap", .sampler),
        .u_env_intensity = uniform_store.create("u_envIntensity", .vec4),
    };
}

pub fn render(self: *const Skybox, enc: Encoder, env_map: *const EnvironmentMap, view_id: u16, camera_pos: math.Vec3) void {
    const intensity = [_]f32{ env_map.intensity, 0, 0, 1.0 };
    enc.setUniform(self.u_env_intensity, &intensity, 1);
    enc.setTexture(0, self.s_env_map, env_map.texture, std.math.maxInt(u32));
    const model = math.Mat4.translationFromVec(camera_pos);
    enc.setTransform(&model);
    enc.setVertexBuffer(0, self.vb, 0, 24);
    enc.setIndexBuffer(self.ib, 0, 36);
    enc.setState(bgfx.StateFlags_WriteRgb | bgfx.StateFlags_WriteA | bgfx.StateFlags_DepthTestAlways, 0);
    enc.submit(view_id, self.program, 0, 0xff);
}

const PosVertex = struct {
    position: math.Vec3,
};

fn generateUnitCube() struct { vb: bgfx.VertexBufferHandle, ib: bgfx.IndexBufferHandle } {
    const V = PosVertex;
    const vs = [_]V{
        .{ .position = .{ .x = -1, .y = -1, .z = -1 } },
        .{ .position = .{ .x = 1, .y = -1, .z = -1 } },
        .{ .position = .{ .x = 1, .y =  1, .z = -1 } },
        .{ .position = .{ .x = -1, .y =  1, .z = -1 } },
        .{ .position = .{ .x = 1, .y = -1, .z =  1 } },
        .{ .position = .{ .x = -1, .y = -1, .z =  1 } },
        .{ .position = .{ .x = -1, .y =  1, .z =  1 } },
        .{ .position = .{ .x = 1, .y =  1, .z =  1 } },
        .{ .position = .{ .x = -1, .y =  1, .z = -1 } },
        .{ .position = .{ .x = -1, .y =  1, .z =  1 } },
        .{ .position = .{ .x = -1, .y = -1, .z =  1 } },
        .{ .position = .{ .x = -1, .y = -1, .z = -1 } },
        .{ .position = .{ .x = 1, .y = -1, .z = -1 } },
        .{ .position = .{ .x = 1, .y = -1, .z =  1 } },
        .{ .position = .{ .x = 1, .y =  1, .z =  1 } },
        .{ .position = .{ .x = 1, .y =  1, .z = -1 } },
        .{ .position = .{ .x = -1, .y = -1, .z =  1 } },
        .{ .position = .{ .x = 1, .y = -1, .z =  1 } },
        .{ .position = .{ .x = 1, .y = -1, .z = -1 } },
        .{ .position = .{ .x = -1, .y = -1, .z = -1 } },
        .{ .position = .{ .x = -1, .y =  1, .z = -1 } },
        .{ .position = .{ .x = 1, .y =  1, .z = -1 } },
        .{ .position = .{ .x = 1, .y =  1, .z =  1 } },
        .{ .position = .{ .x = -1, .y =  1, .z =  1 } },
    };
    const idx = [_]u16{
         0,  1,  2,  0,  2,  3,
         4,  5,  6,  4,  6,  7,
         8,  9, 10,  8, 10, 11,
        12, 13, 14, 12, 14, 15,
        16, 17, 18, 16, 18, 19,
        20, 21, 22, 20, 22, 23,
    };

    const layout = vertex_parser.createLayout(V, .{}, bgfx.getRendererType());
    const mem = bgfx.copy(@ptrCast(&vs), @sizeOf(@TypeOf(vs)));
    const vb = bgfx.createVertexBuffer(mem, &layout, 0);
    const ib_mem = bgfx.copy(@ptrCast(&idx), @sizeOf(@TypeOf(idx)));
    const ib = bgfx.createIndexBuffer(ib_mem, 0);
    return .{ .vb = vb, .ib = ib };
}

pub const Error = error{
    SkyboxInitFailed,
} || Program.Error;
