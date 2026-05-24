const std = @import("std");
const bgfx = @import("bgfx_util.zig").bgfx;
const isValid = @import("bgfx_util.zig").isValid;
const pool = @import("pool");
const stb = @import("stb");
const truetype = stb.truetype;

pub const Font = @This();
pub const Pool = pool.PoolManaged(16, Font, Info, Error);

pub const Error = error{
    FontBakeFailed,
    InvalidTexture,
};

pub const Info = struct {
    ttf_data: []const u8,
    size: f32,
};

handle: bgfx.TextureHandle,
atlas_width: i32,
atlas_height: i32,
size: f32,
ascent: f32,
first_char: u8,
last_char: u8,
chardata: [256]truetype.BakedChar,

pub fn init(info: *const Info) Error!Font {
    var c_font: truetype.c.stbtt_fontinfo = undefined;
    if (truetype.c.stbtt_InitFont(&c_font, info.ttf_data.ptr, 0) == 0) {
        return error.FontBakeFailed;
    }
    const scale = truetype.c.stbtt_ScaleForPixelHeight(&c_font, info.size);
    var ascent: i32 = 0;
    var _descent: i32 = 0;
    var _linegap: i32 = 0;
    truetype.c.stbtt_GetFontVMetrics(&c_font, &ascent, &_descent, &_linegap);
    const font_ascent = @as(f32, @floatFromInt(ascent)) * scale;

    const atlas_w: i32 = 512;
    const atlas_h: i32 = 512;
    const first_char: i32 = 32;
    const num_chars: i32 = 224;

    const allocator = std.heap.page_allocator;
    const pixels = allocator.alloc(u8, @as(usize, @intCast(atlas_w * atlas_h))) catch return error.FontBakeFailed;
    defer allocator.free(pixels);
    @memset(pixels, 0);

    var chardata: [256]truetype.BakedChar = undefined;

    const result = truetype.bakeFontBitmap(
        info.ttf_data,
        0,
        info.size,
        pixels,
        atlas_w,
        atlas_h,
        first_char,
        num_chars,
        &chardata,
    );
    if (result < 0) return error.FontBakeFailed;

    const rgba_size = @as(usize, @intCast(atlas_w * atlas_h * 4));
    const rgba_buffer = allocator.alloc(u8, rgba_size) catch return error.FontBakeFailed;
    defer allocator.free(rgba_buffer);

    for (0..@as(usize, @intCast(atlas_w * atlas_h))) |i| {
        rgba_buffer[i * 4 + 0] = 255;
        rgba_buffer[i * 4 + 1] = 255;
        rgba_buffer[i * 4 + 2] = 255;
        rgba_buffer[i * 4 + 3] = pixels[i];
    }

    const mem = bgfx.copy(rgba_buffer.ptr, @intCast(rgba_buffer.len));

    const handle = bgfx.createTexture2D(
        @intCast(atlas_w),
        @intCast(atlas_h),
        false,
        1,
        .RGBA8,
        0,
        mem,
        0,
    );
    if (!isValid(handle)) return error.InvalidTexture;

    return Font{
        .handle = handle,
        .atlas_width = atlas_w,
        .atlas_height = atlas_h,
        .size = info.size,
        .ascent = font_ascent,
        .first_char = @intCast(first_char),
        .last_char = @intCast(first_char + num_chars - 1),
        .chardata = chardata,
    };
}

pub fn deinit(self: *Font) void {
    bgfx.destroyTexture(self.handle);
}
