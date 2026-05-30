const std = @import("std");
const bgfx = @import("bgfx_util.zig").bgfx;
const isValidFn = @import("bgfx_util.zig").isValid;
const pool = @import("pool");

const Program = @This();

pub const Pool = pool.PoolManaged(16, Program, Info, Error);
pub const Handle = Pool.Handle;

handle: bgfx.ProgramHandle,
fs_handle: bgfx.ShaderHandle,
vs_handle: bgfx.ShaderHandle,

pub fn init(info: *const Info) Error!Program {
    const vert = bgfx.createShader(info.vs_mem);
    if (!isValidFn(vert)) return error.InvalidVertexShader;
    const frag = bgfx.createShader(info.fs_mem);
    if (!isValidFn(frag)) {
        bgfx.destroyShader(vert);
        return error.InvalidFragmentShader;
    }
    const handle = bgfx.createProgram(vert, frag, false);
    if (!isValidFn(handle)) {
        bgfx.destroyShader(vert);
        bgfx.destroyShader(frag);
        return error.InvalidProgram;
    }
    return .{
        .handle = handle,
        .fs_handle = frag,
        .vs_handle = vert,
    };
}

pub fn deinit(self: *Program) void {
    bgfx.destroyProgram(self.handle);
    bgfx.destroyShader(self.fs_handle);
    bgfx.destroyShader(self.vs_handle);
}

pub const Error = error{
    InvalidVertexShader,
    InvalidFragmentShader,
    InvalidProgram,
};

pub fn basicProgramInfo() Info {
    const builtin = @import("builtin_shaders");
    return Info.initBuiltin(builtin.fs_basic, builtin.vs_basic);
}

pub const Info = struct {
    fs_mem: [*c]const bgfx.Memory,
    vs_mem: [*c]const bgfx.Memory,

    pub fn initBuiltin(fs: anytype, vs: anytype) Info {
        return .{
            .fs_mem = fs.getShaderForRenderer(bgfx.getRendererType()),
            .vs_mem = vs.getShaderForRenderer(bgfx.getRendererType()),
        };
    }

    pub fn initCopy(vertex_src: []const u8, fragment_src: []const u8) Info {
        return .{
            .fs_mem = bgfx.copy(@ptrCast(fragment_src.ptr), @intCast(fragment_src.len)),
            .vs_mem = bgfx.copy(@ptrCast(vertex_src.ptr), @intCast(vertex_src.len)),
        };
    }

    pub fn initRef(vertex_src: []const u8, fragment_src: []const u8) Info {
        return .{
            .fs_mem = bgfx.makeRef(@ptrCast(fragment_src.ptr), @intCast(fragment_src.len)),
            .vs_mem = bgfx.makeRef(@ptrCast(vertex_src.ptr), @intCast(vertex_src.len)),
        };
    }
};
