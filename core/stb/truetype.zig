const std = @import("std");
pub const c = @cImport({
    @cInclude("stb_truetype.h");
});

pub const BakedChar = c.stbtt_bakedchar;

pub fn bakeFontBitmap(
    data: []const u8,
    offset: i32,
    pixel_height: f32,
    pixels: []u8,
    pw: i32,
    ph: i32,
    first_char: i32,
    num_chars: i32,
    chardata: []BakedChar,
) i32 {
    return c.stbtt_BakeFontBitmap(
        data.ptr,
        offset,
        pixel_height,
        pixels.ptr,
        pw,
        ph,
        first_char,
        num_chars,
        chardata.ptr,
    );
}
