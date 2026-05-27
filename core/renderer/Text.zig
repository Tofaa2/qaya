const std = @import("std");
const bgfx = @import("bgfx_util.zig").bgfx;
const math = @import("math");
const Font = @import("Font.zig");
const Program = @import("Program.zig");
const Encoder = @import("Encoder.zig");
const UniformStore = @import("UniformStore.zig");
const builtin = @import("builtin_shaders");
const vertex_parser = @import("vertex_parser.zig");
const vertices = @import("vertices.zig");

pub fn programInfo() Program.Info {
    return Program.Info.initBuiltin(builtin.fs_text, builtin.vs_text);
}

pub const TextUniforms = struct {
    u_color: bgfx.UniformHandle,
    s_tex_color: bgfx.UniformHandle,
};

pub fn initUniforms(store: *UniformStore) TextUniforms {
    return .{
        .u_color = store.create("u_color", .vec4),
        .s_tex_color = store.create("s_texColor", .sampler),
    };
}

pub fn renderText(
    enc: Encoder,
    font: *const Font,
    text: []const u8,
    font_size: f32,
    color: math.Color,
    position: math.Vec3,
    view_id: u16,
    program: bgfx.ProgramHandle,
    uniforms: TextUniforms,
) void {
    const char_count = @min(text.len, @as(usize, 255));
    if (char_count == 0) return;

    const vertex_count = char_count * 4;
    const index_count = char_count * 6;

    const layout = vertex_parser.createLayout(vertices.PosTex, .{}, bgfx.getRendererType());
    var tvb: bgfx.TransientVertexBuffer = undefined;
    var tib: bgfx.TransientIndexBuffer = undefined;
    if (!bgfx.allocTransientBuffers(&tvb, &layout, @intCast(vertex_count), &tib, @intCast(index_count), false)) {
        std.log.warn("allocTransientBuffers failed ({} verts, {} idxs)", .{ vertex_count, index_count });
        return;
    }

    const verts: [*]vertices.PosTex = @ptrCast(@alignCast(tvb.data));
    const indices: [*]u16 = @ptrCast(@alignCast(tib.data));

    const atlas_w: f32 = @floatFromInt(font.atlas_width);
    const atlas_h: f32 = @floatFromInt(font.atlas_height);
    const scale = font_size / font.size;

    var cursor_x: f32 = position.x;
    const cursor_y: f32 = position.y;
    const baseline_y: f32 = cursor_y + font.ascent * scale;

    const r: f32 = @floatFromInt(color.r);
    const g: f32 = @floatFromInt(color.g);
    const b: f32 = @floatFromInt(color.b);

    var vi: u32 = 0;
    var ii: u32 = 0;

    for (text[0..char_count]) |ch| {
        if (ch < font.first_char or ch > font.last_char) continue;
        const ch_idx = ch - font.first_char;
        const bc = font.chardata[ch_idx];

        if (ch == '\n') {
            cursor_x = position.x;
            continue;
        }

        const x0: f32 = cursor_x + bc.xoff * scale;
        const y0: f32 = baseline_y + bc.yoff * scale;
        const x1: f32 = x0 + @as(f32, @floatFromInt(bc.x1 - bc.x0)) * scale;
        const y1: f32 = y0 + @as(f32, @floatFromInt(bc.y1 - bc.y0)) * scale;

        const @"u0": f32 = @as(f32, @floatFromInt(bc.x0)) / atlas_w;
        const @"v0": f32 = @as(f32, @floatFromInt(bc.y0)) / atlas_h;
        const @"u1": f32 = @as(f32, @floatFromInt(bc.x1)) / atlas_w;
        const @"v1": f32 = @as(f32, @floatFromInt(bc.y1)) / atlas_h;

        const vbase = vi;
        verts[vi] = .{ .position = .init(x0, y0, 0), .texcoord0 = .init(@"u0", @"v0") }; vi += 1;
        verts[vi] = .{ .position = .init(x1, y0, 0), .texcoord0 = .init(@"u1", @"v0") }; vi += 1;
        verts[vi] = .{ .position = .init(x1, y1, 0), .texcoord0 = .init(@"u1", @"v1") }; vi += 1;
        verts[vi] = .{ .position = .init(x0, y1, 0), .texcoord0 = .init(@"u0", @"v1") }; vi += 1;

        const ibase = @as(u16, @intCast(vbase));
        indices[ii] = ibase;       ii += 1;
        indices[ii] = ibase + 1;   ii += 1;
        indices[ii] = ibase + 2;   ii += 1;
        indices[ii] = ibase;       ii += 1;
        indices[ii] = ibase + 2;   ii += 1;
        indices[ii] = ibase + 3;   ii += 1;

        cursor_x += bc.xadvance * scale;
    }

    if (vi == 0) return;

    const color_arr = [_]f32{ r / 255.0, g / 255.0, b / 255.0, 1.0 };

    enc.setTransientVertexBuffer(0, &tvb, 0, vi);
    enc.setTransientIndexBuffer(&tib, 0, ii);

    enc.setUniform(uniforms.u_color, &color_arr, 1);
    enc.setTexture(0, uniforms.s_tex_color, font.handle, std.math.maxInt(u32));
    const src_alpha: u64 = 5;
    const inv_src_alpha: u64 = 6;
    const blend = (src_alpha << 12) | (inv_src_alpha << 16) | (src_alpha << 20) | (inv_src_alpha << 24);
    enc.setState(
        bgfx.StateFlags_WriteRgb | bgfx.StateFlags_WriteA | bgfx.StateFlags_Msaa | bgfx.StateFlags_DepthTestAlways | blend,
        0,
    );
    enc.submit(view_id, program, 0, 0xff);
}
