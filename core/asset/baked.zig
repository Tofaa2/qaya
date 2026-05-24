const std = @import("std");
const bgfx = @import("bgfx").bgfx;
const stb = @import("stb");

pub const BakedAsset = struct {
    data: []const u8,
    path: []const u8,
};

pub fn createBakedTexture(asset: BakedAsset) !bgfx.TextureHandle {
    const ext = std.fs.path.extension(asset.path);
    const is_hdr = std.ascii.eqlIgnoreCase(ext, ".hdr");

    if (is_hdr) {
        var w: c_int = undefined;
        var h: c_int = undefined;
        const data = stb.image.c.stbi_loadf_from_memory(
            @ptrCast(asset.data.ptr),
            @intCast(asset.data.len),
            &w,
            &h,
            null,
            4,
        );
        if (data == null) return error.BakedImageLoadFailed;
        defer stb.image.c.stbi_image_free(data);

        const byte_len = @as(usize, @intCast(w * h * 4 * @sizeOf(f32)));
        const mem = bgfx.copy(@ptrCast(data), @intCast(byte_len));
        const handle = bgfx.createTexture2D(
            @intCast(w),
            @intCast(h),
            false,
            1,
            .RGBA32F,
            0,
            mem,
            0,
        );
        if (!isValid(handle)) return error.BakedTextureCreateFailed;
        return handle;
    } else {
        var w: c_int = undefined;
        var h: c_int = undefined;
        var ch: c_int = undefined;
        const data = stb.image.c.stbi_load_from_memory(
            @ptrCast(asset.data.ptr),
            @intCast(asset.data.len),
            &w,
            &h,
            &ch,
            4,
        );
        if (data == null) return error.BakedImageLoadFailed;
        defer stb.image.c.stbi_image_free(data);

        const mem = bgfx.copy(@ptrCast(data), @intCast(w * h * 4));
        const handle = bgfx.createTexture2D(
            @intCast(w),
            @intCast(h),
            false,
            1,
            .RGBA8,
            0,
            mem,
            0,
        );
        if (!isValid(handle)) return error.BakedTextureCreateFailed;
        return handle;
    }
}

fn isValid(handle: anytype) bool {
    return handle.idx < std.math.maxInt(u16);
}

pub const Error = error{
    BakedImageLoadFailed,
    BakedTextureCreateFailed,
};
