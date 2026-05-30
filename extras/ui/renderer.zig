const std = @import("std");
const bgfx = @import("renderer").bgfx;
const Encoder = @import("renderer").Encoder;
const renderer = @import("renderer");
const vertices = renderer.vertices;
const vertex_parser = renderer.vertex_parser;
const math = @import("math");
const app = @import("app-sdk");
const ecs = app.ecs;
const ctx_mod = @import("context.zig");
const TextRenderer = app.plugins.TextRenderer;

pub const UIRenderer = struct {
    basic_program: renderer.Program.Pool.Handle,
};

pub fn system(
    ctx_res: ecs.ResMut(ctx_mod.Context),
    ui_renderer: ecs.Res(UIRenderer),
    program_pool: ecs.ResMut(renderer.Program.Pool),
    text_renderer: ecs.Res(TextRenderer),
) void {
    var enc = Encoder.init();
    defer enc.deinit();

    const ctx = ctx_res.value;
    const program = program_pool.value.get(ui_renderer.value.basic_program) orelse return;
    const text_prog = program_pool.value.get(text_renderer.value.program) orelse return;

    const view_id: u16 = @intFromEnum(renderer.View.Id.@"2d");
    const layout = vertex_parser.createLayout(vertices.PosColor, .{}, bgfx.getRendererType());

    var idx: usize = 0;
    const commands = &ctx.command_list;
    while (idx < commands.items.len) : (idx += 1) {
        switch (commands.items[idx]) {
            .clip => |c| {
                const rx = @max(0, @as(i32, @intFromFloat(c.rect.x)));
                const ry = @max(0, @as(i32, @intFromFloat(c.rect.y)));
                const rw = @max(0, @as(i32, @intFromFloat(c.rect.width)));
                const rh = @max(0, @as(i32, @intFromFloat(c.rect.height)));
                if (rw > 0 and rh > 0) {
                    enc.setScissor(
                        @intCast(@min(rx, std.math.maxInt(u16))),
                        @intCast(@min(ry, std.math.maxInt(u16))),
                        @intCast(@min(rw, std.math.maxInt(u16))),
                        @intCast(@min(rh, std.math.maxInt(u16))),
                    );
                }
            },
            .rect => |r| {
                drawRect(&enc, &layout, r.rect, r.color, view_id, program.handle);
            },
            .text => |t| {
                renderer.Text.renderText(
                    enc,
                    t.font,
                    t.str,
                    t.font.size,
                    t.color,
                    math.Vec3.init(t.pos.x, t.pos.y, 0),
                    view_id,
                    text_prog.handle,
                    text_renderer.value.uniforms,
                );
            },
            .icon => |i| {
                const col = i.color;
                const r = i.rect;
                const cx = r.x + r.width / 2;
                const cy = r.y + r.height / 2;
                const s = @min(r.width, r.height) * 0.3;
                switch (i.id) {
                    .close => {
                        drawLine(&enc, &layout, cx - s, cy - s, cx + s, cy + s, col, view_id, program.handle);
                        drawLine(&enc, &layout, cx + s, cy - s, cx - s, cy + s, col, view_id, program.handle);
                    },
                    .check => {
                        drawLine(&enc, &layout, cx - s, cy, cx, cy + s, col, view_id, program.handle);
                        drawLine(&enc, &layout, cx, cy + s, cx + s, cy - s, col, view_id, program.handle);
                    },
                    .collapsed => {
                        drawTriangle(&enc, &layout, cx - s, cy - s, cx + s, cy, cx - s, cy + s, col, view_id, program.handle);
                    },
                    .expanded => {
                        drawTriangle(&enc, &layout, cx - s, cy - s, cx, cy + s, cx + s, cy - s, col, view_id, program.handle);
                    },
                    else => {},
                }
            },
        }
    }
}

fn drawRect(
    enc: *Encoder,
    layout: *const bgfx.VertexLayout,
    rect: math.Rect(f32),
    color: math.Color,
    view_id: u16,
    program: bgfx.ProgramHandle,
) void {
    const x0 = rect.x;
    const y0 = rect.y;
    const x1 = rect.x + rect.width;
    const y1 = rect.y + rect.height;

    var tvb: bgfx.TransientVertexBuffer = undefined;
    var tib: bgfx.TransientIndexBuffer = undefined;
    if (!bgfx.allocTransientBuffers(&tvb, layout, 4, &tib, 6, false)) return;

    const verts: [*]vertices.PosColor = @ptrCast(@alignCast(tvb.data));
    const indices: [*]u16 = @ptrCast(@alignCast(tib.data));

    verts[0] = .{ .position = .init(x0, y0, 0), .color0 = color };
    verts[1] = .{ .position = .init(x1, y0, 0), .color0 = color };
    verts[2] = .{ .position = .init(x1, y1, 0), .color0 = color };
    verts[3] = .{ .position = .init(x0, y1, 0), .color0 = color };

    @memcpy(indices[0..6], &[_]u16{ 0, 1, 2, 0, 2, 3 });

    enc.setTransientVertexBuffer(0, &tvb, 0, 4);
    enc.setTransientIndexBuffer(&tib, 0, 6);
    const flags = bgfx.StateFlags_WriteRgb | bgfx.StateFlags_WriteA | bgfx.StateFlags_Msaa | bgfx.StateFlags_DepthTestAlways;
    enc.setState(flags, 0);
    enc.submit(view_id, program, 0, 0xff);
}

fn drawLine(
    enc: *Encoder,
    layout: *const bgfx.VertexLayout,
    x0: f32, y0: f32,
    x1: f32, y1: f32,
    color: math.Color,
    view_id: u16,
    program: bgfx.ProgramHandle,
) void {
    const dx = x1 - x0;
    const dy = y1 - y0;
    const len = @sqrt(dx * dx + dy * dy);
    if (len < 0.001) return;
    const nx = -dy / len * 1.0;
    const ny = dx / len * 1.0;

    var tvb: bgfx.TransientVertexBuffer = undefined;
    var tib: bgfx.TransientIndexBuffer = undefined;
    if (!bgfx.allocTransientBuffers(&tvb, layout, 4, &tib, 6, false)) return;

    const verts: [*]vertices.PosColor = @ptrCast(@alignCast(tvb.data));
    const indices: [*]u16 = @ptrCast(@alignCast(tib.data));

    verts[0] = .{ .position = .init(x0 + nx, y0 + ny, 0), .color0 = color };
    verts[1] = .{ .position = .init(x1 + nx, y1 + ny, 0), .color0 = color };
    verts[2] = .{ .position = .init(x1 - nx, y1 - ny, 0), .color0 = color };
    verts[3] = .{ .position = .init(x0 - nx, y0 - ny, 0), .color0 = color };

    @memcpy(indices[0..6], &[_]u16{ 0, 1, 2, 0, 2, 3 });

    enc.setTransientVertexBuffer(0, &tvb, 0, 4);
    enc.setTransientIndexBuffer(&tib, 0, 6);
    const flags = bgfx.StateFlags_WriteRgb | bgfx.StateFlags_WriteA | bgfx.StateFlags_Msaa | bgfx.StateFlags_DepthTestAlways;
    enc.setState(flags, 0);
    enc.submit(view_id, program, 0, 0xff);
}

fn drawTriangle(
    enc: *Encoder,
    layout: *const bgfx.VertexLayout,
    x0: f32, y0: f32,
    x1: f32, y1: f32,
    x2: f32, y2: f32,
    color: math.Color,
    view_id: u16,
    program: bgfx.ProgramHandle,
) void {
    var tvb: bgfx.TransientVertexBuffer = undefined;
    var tib: bgfx.TransientIndexBuffer = undefined;
    if (!bgfx.allocTransientBuffers(&tvb, layout, 3, &tib, 3, false)) return;

    const verts: [*]vertices.PosColor = @ptrCast(@alignCast(tvb.data));
    const indices: [*]u16 = @ptrCast(@alignCast(tib.data));

    verts[0] = .{ .position = .init(x0, y0, 0), .color0 = color };
    verts[1] = .{ .position = .init(x1, y1, 0), .color0 = color };
    verts[2] = .{ .position = .init(x2, y2, 0), .color0 = color };

    indices[0..3].* = .{ 0, 1, 2 };

    enc.setTransientVertexBuffer(0, &tvb, 0, 3);
    enc.setTransientIndexBuffer(&tib, 0, 3);
    const flags = bgfx.StateFlags_WriteRgb | bgfx.StateFlags_WriteA | bgfx.StateFlags_Msaa | bgfx.StateFlags_DepthTestAlways;
    enc.setState(flags, 0);
    enc.submit(view_id, program, 0, 0xff);
}
