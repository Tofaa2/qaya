const std = @import("std");
const bgfx = @import("bgfx_util.zig").bgfx;
const isValid = @import("bgfx_util.zig").isValid;
const pool = @import("pool");
const stb = @import("stb");

const Texture = @This();

pub const Pool = pool.PoolManaged(16, Texture, Info, Error);
pub const Handle = Pool.Handle;

handle: bgfx.TextureHandle,
width: u32,
height: u32,

pub fn init(info: *const Info) Error!Texture {
    return switch (info.*) {
        inline .file => |f| loadFile(f.path),
        inline .hdr_file => |f| loadHdrFile(f.path),
        .memory => |m| loadMemory(m.data, m.width, m.height, m.format),
        .raw => |r| Texture{
            .handle = r.handle,
            .width = r.width,
            .height = r.height,
        },
        .baked => |b| loadBaked(b.data, b.path),
    };
}

pub fn deinit(self: *Texture) void {
    bgfx.destroyTexture(self.handle);
}

fn loadFile(path: [:0]const u8) Error!Texture {
    var image = stb.image.Image.init(path, .rgba, null) catch |err| switch (err) {
        error.FailedToLoad => return error.FileNotFound,
        error.FailedToFormat => return error.InvalidFormat,
    };
    defer image.deinit();

    const flags = SamplerFlags.u_clamp | SamplerFlags.v_clamp | SamplerFlags.min_point | SamplerFlags.mag_point;
    const mem = bgfx.copy(@ptrCast(image.data), image.width * image.height * 4);
    const handle = bgfx.createTexture2D(
        @intCast(image.width),
        @intCast(image.height),
        false,
        1,
        .RGBA8,
        flags,
        mem,
        0,
    );
    if (!isValid(handle)) return error.InvalidTexture;
    return .{
        .handle = handle,
        .width = image.width,
        .height = image.height,
    };
}

fn loadHdrFile(path: [:0]const u8) Error!Texture {
    var hdr = stb.image.HdrImage.init(path, 4) catch |err| switch (err) {
        error.FailedToLoad => return error.FileNotFound,
        error.FailedToFormat => return error.InvalidFormat,
    };

    const w = hdr.width;
    const h = hdr.height;
    const num_pixels = w * h;
    const byte_len = num_pixels * 4 * @sizeOf(f32);

    const flags = SamplerFlags.u_clamp | SamplerFlags.v_clamp;
    const mem = bgfx.copy(@ptrCast(hdr.data), @intCast(byte_len));
    const handle = bgfx.createTexture2D(
        @intCast(w),
        @intCast(h),
        false,
        1,
        .RGBA32F,
        flags,
        mem,
        0,
    );
    hdr.deinit();
    if (!isValid(handle)) return error.InvalidTexture;
    return .{
        .handle = handle,
        .width = w,
        .height = h,
    };
}

fn loadMemory(data: []const u8, width: u32, height: u32, format: bgfx.TextureFormat) Error!Texture {
    const flags = SamplerFlags.u_clamp | SamplerFlags.v_clamp | SamplerFlags.min_point | SamplerFlags.mag_point;
    const mem = bgfx.copy(@ptrCast(data.ptr), @intCast(data.len));
    const handle = bgfx.createTexture2D(
        @intCast(width),
        @intCast(height),
        false,
        1,
        format,
        flags,
        mem,
        0,
    );
    if (!isValid(handle)) return error.InvalidTexture;
    return .{ .handle = handle, .width = width, .height = height };
}

fn loadBaked(data: []const u8, path: []const u8) Error!Texture {
    const ext = std.fs.path.extension(path);
    const is_hdr = std.ascii.eqlIgnoreCase(ext, ".hdr");

    if (is_hdr) {
        var w: c_int = undefined;
        var h: c_int = undefined;
        const img = stb.image.c.stbi_loadf_from_memory(
            @ptrCast(data.ptr),
            @intCast(data.len),
            &w,
            &h,
            null,
            4,
        );
        if (img == null) return error.InvalidFormat;
        defer stb.image.c.stbi_image_free(img);

        const byte_len = @as(usize, @intCast(w * h * 4 * @sizeOf(f32)));
        const mem = bgfx.copy(@ptrCast(img), @intCast(byte_len));
        const handle = bgfx.createTexture2D(@intCast(w), @intCast(h), false, 1, .RGBA32F, 0, mem, 0);
        if (!isValid(handle)) return error.InvalidTexture;
        return .{ .handle = handle, .width = @intCast(w), .height = @intCast(h) };
    } else {
        var w: c_int = undefined;
        var h: c_int = undefined;
        var ch: c_int = undefined;
        const img = stb.image.c.stbi_load_from_memory(
            @ptrCast(data.ptr),
            @intCast(data.len),
            &w,
            &h,
            &ch,
            4,
        );
        if (img == null) return error.InvalidFormat;
        defer stb.image.c.stbi_image_free(img);

        const mem = bgfx.copy(@ptrCast(img), @intCast(w * h * 4));
        const handle = bgfx.createTexture2D(@intCast(w), @intCast(h), false, 1, .RGBA8, 0, mem, 0);
        if (!isValid(handle)) return error.InvalidTexture;
        return .{ .handle = handle, .width = @intCast(w), .height = @intCast(h) };
    }
}

pub const Error = error{
    FileNotFound,
    InvalidFormat,
    InvalidTexture,
};

/// Sampler flags (from bgfx/defines.h, not exposed in zig bindings).
pub const SamplerFlags = struct {
    pub const u_clamp: u64 = 0x00000002;
    pub const v_clamp: u64 = 0x00000008;
    pub const min_point: u64 = 0x00000040;
    pub const mag_point: u64 = 0x00000100;
};

pub const Info = union(enum) {
    file: struct { path: [:0]const u8 },
    hdr_file: struct { path: [:0]const u8 },
    memory: struct { data: []const u8, width: u32, height: u32, format: bgfx.TextureFormat },
    raw: struct { handle: bgfx.TextureHandle, width: u32, height: u32 },
    baked: struct { data: []const u8, path: []const u8 },
};
