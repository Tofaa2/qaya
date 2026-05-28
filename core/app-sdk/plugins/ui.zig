const App = @import("../App.zig");
const ecs = @import("ecs");
const std = @import("std");
const math = @import("math");
const renderer = @import("renderer");
const ui_layout = @import("../ui_layout.zig");
const comp = @import("../components/root.zig");
const res = @import("../resources/root.zig");
const RenderEncoder = @import("../RenderEncoder.zig").RenderEncoder;
const bgfx = renderer.bgfx;
const builtin = renderer.builtin_shaders;

const window_mod = @import("window");
const log = std.log.scoped(.ui);

const UiRenderer = struct {
    program: renderer.Program.Pool.Handle,
    program_textured: renderer.Program.Pool.Handle,
    program_text: renderer.Program.Pool.Handle,
    sampler_tex_color: bgfx.UniformHandle,
    text_color_uniform: bgfx.UniformHandle,
};

pub const Plugin = struct {
    pub fn build(_: *const Plugin, app: *App) void {
        app.world.registerComponent(comp.UiNode);
        app.world.registerComponent(comp.ComputedLayout);
        app.world.registerComponent(comp.UiBackground);
        app.world.registerComponent(comp.UiInteraction);
        app.world.registerComponent(comp.UiTextOffset);
        app.world.registerComponent(comp.ClickAction);
        app.world.registerComponent(comp.Scroll);
        app.world.registerComponent(comp.UiImage);
        app.world.registerComponent(comp.UiTextInput);

        app.world.scheduler.add(.post_init, uiInit) catch unreachable;
        app.world.scheduler.add(.post_update, uiLayoutSystem) catch unreachable;
        app.world.scheduler.add(.post_update, applyScrollSystem) catch unreachable;
        app.world.scheduler.add(.update, autoSizeText) catch unreachable;
        app.world.scheduler.add(.update, uiInteractionSystem) catch unreachable;
        app.world.scheduler.add(.update, textInputSystem) catch unreachable;
        app.world.scheduler.add(.update, syncComputedLayoutTransforms) catch unreachable;
        app.world.scheduler.add(.update, dispatchClickActions) catch unreachable;
        app.world.scheduler.add(.render, renderUiPanels) catch unreachable;
        app.world.scheduler.add(.render, renderUiImages) catch unreachable;
        app.world.scheduler.add(.render, renderTextCursors) catch unreachable;

        log.info("UI plugin initialized", .{});
    }
};

fn uiInit(world: *ecs.World) void {
    const program_pool = world.getMutResource(renderer.Program.Pool) orelse return;
    const program = program_pool.load(&renderer.Program.Info.initBuiltin(builtin.fs_basic, builtin.vs_basic)) catch |err| {
        log.err("Failed to load UI shader program: {s}", .{@errorName(err)});
        return;
    };
    const program_textured = program_pool.load(&renderer.Program.Info.initBuiltin(builtin.fs_textured, builtin.vs_textured)) catch |err| {
        log.err("Failed to load UI textured shader program: {s}", .{@errorName(err)});
        return;
    };
    const program_text = program_pool.load(&renderer.Program.Info.initBuiltin(builtin.fs_text, builtin.vs_text)) catch |err| {
        log.err("Failed to load UI text shader program: {s}", .{@errorName(err)});
        return;
    };
    const sampler_tex_color = bgfx.createUniform("s_texColor", .Sampler, 1);
    const text_color_uniform = bgfx.createUniform("u_color", .Vec4, 1);
    world.insertResource(UiRenderer{
        .program = program,
        .program_textured = program_textured,
        .program_text = program_text,
        .sampler_tex_color = sampler_tex_color,
        .text_color_uniform = text_color_uniform,
    });
}

fn uiLayoutSystem(
    world: *ecs.World,
    window: ecs.ResMut(@import("window.zig").Plugin.api.Window),
) void {
    const size = window.value.getSize();
    ui_layout.run(world, @floatFromInt(size[0]), @floatFromInt(size[1]));
}

fn uiInteractionSystem(
    window: ecs.ResMut(window_mod.Window),
    buttons: ecs.Query(.{ *comp.ComputedLayout, *comp.UiInteraction }),
) void {
    const mouse = window.value.getMouse();
    const mx: f32 = @floatFromInt(mouse[0]);
    const my: f32 = @floatFromInt(mouse[1]);
    const just_pressed = window.value.isMousePressed(.left);

    var it = buttons.iter();
    while (it.next()) |row| {
        const layout = row.ComputedLayout;
        const interaction = row.UiInteraction;

        const hovered = mx >= layout.x and mx < layout.x + layout.width and
            my >= layout.y and my < layout.y + layout.height;

        if (hovered and just_pressed) {
            interaction.* = .pressed;
        } else if (hovered) {
            interaction.* = .hovered;
        } else {
            interaction.* = .none;
        }
    }
}

fn autoSizeText(
    pool: ecs.ResMut(renderer.Font.Pool),
    texts: ecs.Query(.{ *comp.Text, *comp.UiNode }),
) void {
    var it = texts.iter();
    while (it.next()) |row| {
        if (row.UiNode.width > 0 and row.UiNode.height > 0) continue;
        const font = pool.value.get(row.Text.font) orelse continue;
        const text_slice = row.Text.value[0..row.Text.len];
        const m = renderer.Text.measureText(font, text_slice, row.Text.size);
        row.UiNode.width = m.width;
        row.UiNode.height = m.height;
    }
}

fn syncComputedLayoutTransforms(
    nodes: ecs.Query(.{ *comp.Transform, *comp.ComputedLayout }),
) void {
    var it = nodes.iter();
    while (it.next()) |row| {
        row.Transform.position.x = row.ComputedLayout.x;
        row.Transform.position.y = row.ComputedLayout.y;
    }
}

fn dispatchClickActions(
    world: *ecs.World,
    buttons: ecs.Query(.{ *const comp.UiInteraction, *const comp.ClickAction }),
) void {
    var it = buttons.iter();
    while (it.next()) |row| {
        if (row.UiInteraction.* != .pressed) continue;
        row.ClickAction.callback(world);
    }
}

fn renderUiPanels(
    enc_param: RenderEncoder(),
    program_pool: ecs.ResMut(renderer.Program.Pool),
    ui_renderer: ecs.Res(UiRenderer),
    panels: ecs.Query(.{ *comp.ComputedLayout, *comp.UiBackground, *const comp.UiNode }),
) void {
    const enc = enc_param.value;
    const program = program_pool.value.get(ui_renderer.value.program) orelse {
        log.warn("UI program not found in pool", .{});
        return;
    };

    const PanelInfo = struct {
        rect: *const comp.ComputedLayout,
        bg: *const comp.UiBackground,
        z: i32,
    };

    var buffer: [256]PanelInfo = undefined;
    var count: usize = 0;

    var it = panels.iter();
    while (it.next()) |row| {
        if (count >= buffer.len) break;
        buffer[count] = .{
            .rect = row.ComputedLayout,
            .bg = row.UiBackground,
            .z = row.UiNode.z_index,
        };
        count += 1;
    }

    std.sort.insertion(PanelInfo, buffer[0..count], {}, struct {
        fn lessThan(_: void, a: PanelInfo, b: PanelInfo) bool {
            return a.z < b.z;
        }
    }.lessThan);

    const layout = renderer.vertex_parser.createLayout(renderer.vertices.PosColor, .{}, bgfx.getRendererType());

    for (buffer[0..count]) |info| {
        const rect = info.rect;
        const bg = info.bg;
        const x0 = rect.x;
        const y0 = rect.y;
        const x1 = rect.x + rect.width;
        const y1 = rect.y + rect.height;

        const vertex_count: u32 = 4;
        const index_count: u32 = 6;

        var tvb: bgfx.TransientVertexBuffer = undefined;
        var tib: bgfx.TransientIndexBuffer = undefined;
        if (!bgfx.allocTransientBuffers(&tvb, &layout, vertex_count, &tib, index_count, false)) {
            continue;
        }

        const verts: [*]renderer.vertices.PosColor = @ptrCast(@alignCast(tvb.data));
        const indices: [*]u16 = @ptrCast(@alignCast(tib.data));

        verts[0] = .{ .position = .init(x0, y0, 0), .color0 = bg.color };
        verts[1] = .{ .position = .init(x1, y0, 0), .color0 = bg.color };
        verts[2] = .{ .position = .init(x1, y1, 0), .color0 = bg.color };
        verts[3] = .{ .position = .init(x0, y1, 0), .color0 = bg.color };

        indices[0] = 0; indices[1] = 1; indices[2] = 2;
        indices[3] = 0; indices[4] = 2; indices[5] = 3;

        enc.setTransientVertexBuffer(0, &tvb, 0, vertex_count);
        enc.setTransientIndexBuffer(&tib, 0, index_count);
        const src_alpha: u64 = 5;
        const inv_src_alpha: u64 = 6;
        const blend = (src_alpha << 12) | (inv_src_alpha << 16) | (src_alpha << 20) | (inv_src_alpha << 24);
        enc.setState(
            bgfx.StateFlags_WriteRgb | bgfx.StateFlags_WriteA | bgfx.StateFlags_Msaa | bgfx.StateFlags_DepthTestAlways | blend,
            0,
        );
        enc.submit(@intFromEnum(renderer.View.Id.@"2d"), program.handle, 1, 0xff);
    }
}

fn renderUiImages(
    enc_param: RenderEncoder(),
    program_pool: ecs.ResMut(renderer.Program.Pool),
    tex_pool: ecs.ResMut(renderer.Texture.Pool),
    ui_renderer: ecs.Res(UiRenderer),
    images: ecs.Query(.{ *comp.ComputedLayout, *comp.UiImage }),
) void {
    const enc = enc_param.value;
    // Use the text program (its s_texColor sampler compiles correctly).
    // With u_color.a = 0 the shader outputs texel directly (image mode).
    const program = program_pool.value.get(ui_renderer.value.program_text) orelse return;
    const layout = renderer.vertex_parser.createLayout(renderer.vertices.PosTex, .{}, bgfx.getRendererType());

    const image_uniform = [_]f32{ 1.0, 1.0, 1.0, 0.0 }; // a=0 → pass through texel.rgb

    var count: usize = 0;
    var it = images.iter();
    while (it.next()) |row| {
        const tex = tex_pool.value.get(row.UiImage.texture) orelse continue;
        const rect = row.ComputedLayout;
        if (count == 0) {
            log.info("Rendering image at x={d:.1} y={d:.1} w={d:.1} h={d:.1}", .{
                rect.x, rect.y, rect.width, rect.height,
            });
        }
        count += 1;
        const x0 = rect.x;
        const y0 = rect.y;
        const x1 = rect.x + rect.width;
        const y1 = rect.y + rect.height;

        const vertex_count: u32 = 4;
        const index_count: u32 = 6;

        var tvb: bgfx.TransientVertexBuffer = undefined;
        var tib: bgfx.TransientIndexBuffer = undefined;
        if (!bgfx.allocTransientBuffers(&tvb, &layout, vertex_count, &tib, index_count, false)) continue;

        const verts: [*]renderer.vertices.PosTex = @ptrCast(@alignCast(tvb.data));
        const indices: [*]u16 = @ptrCast(@alignCast(tib.data));

        verts[0] = .{ .position = .init(x0, y0, 0), .texcoord0 = .init(0, 0) };
        verts[1] = .{ .position = .init(x1, y0, 0), .texcoord0 = .init(1, 0) };
        verts[2] = .{ .position = .init(x1, y1, 0), .texcoord0 = .init(1, 1) };
        verts[3] = .{ .position = .init(x0, y1, 0), .texcoord0 = .init(0, 1) };

        indices[0] = 0; indices[1] = 1; indices[2] = 2;
        indices[3] = 0; indices[4] = 2; indices[5] = 3;

        enc.setTransientVertexBuffer(0, &tvb, 0, vertex_count);
        enc.setTransientIndexBuffer(&tib, 0, index_count);
        enc.setTexture(0, ui_renderer.value.sampler_tex_color, tex.handle, std.math.maxInt(u32));
        enc.setUniform(ui_renderer.value.text_color_uniform, &image_uniform, 1);
        const src_alpha: u64 = 5;
        const inv_src_alpha: u64 = 6;
        const blend = (src_alpha << 12) | (inv_src_alpha << 16) | (src_alpha << 20) | (inv_src_alpha << 24);
        enc.setState(
            bgfx.StateFlags_WriteRgb | bgfx.StateFlags_WriteA | bgfx.StateFlags_Msaa | bgfx.StateFlags_DepthTestAlways | blend,
            0,
        );
        enc.submit(@intFromEnum(renderer.View.Id.@"2d"), program.handle, 1, 0xff);
    }
}

fn shiftedChar(c: u8) u8 {
    return switch (c) {
        '`' => '~',
        '1' => '!', '2' => '@', '3' => '#', '4' => '$', '5' => '%',
        '6' => '^', '7' => '&', '8' => '*', '9' => '(', '0' => ')',
        '-' => '_', '=' => '+',
        '[' => '{', ']' => '}', '\\' => '|',
        ';' => ':', '\'' => '"',
        ',' => '<', '.' => '>', '/' => '?',
        else => c,
    };
}

fn textInputSystem(
    world: *ecs.World,
    window: ecs.ResMut(window_mod.Window),
    inputs: ecs.Query(.{ *comp.UiTextInput, *comp.Text, *const comp.ComputedLayout }),
) void {
    const mouse = window.value.getMouse();
    const mx: f32 = @floatFromInt(mouse[0]);
    const my: f32 = @floatFromInt(mouse[1]);
    const just_pressed = window.value.isMousePressed(.left);
    const is_captured = window.value.getMouseCaptured();

    if (!is_captured) {
        var it = inputs.iter();
        while (it.next()) |row| {
            const layout = row.ComputedLayout;
            const hovered = mx >= layout.x and mx < layout.x + layout.width and
                my >= layout.y and my < layout.y + layout.height;
            if (hovered and just_pressed) {
                row.UiTextInput.focused = true;
            } else if (just_pressed) {
                row.UiTextInput.focused = false;
            }
        }
    }

    {
        var it = inputs.iter();
        while (it.next()) |row| {
            if (!row.UiTextInput.focused) continue;

            const input = world.getResource(res.InputState) orelse continue;
            const shift_down = input.isDown(.shiftL) or input.isDown(.shiftR);
            const ctrl_down = input.isDown(.controlL) or input.isDown(.controlR);
            const caps_down = input.isDown(.capsLock);
            const uppercase = shift_down != caps_down;

            var key_iter = input.keys_pressed.iterator(.{});
            while (key_iter.next()) |key_int| {
                const key: window_mod.enums.Key = @enumFromInt(@as(u8, @intCast(key_int)));
                const text = row.Text;
                const ti = row.UiTextInput;
                switch (key) {
                    .left => {
                        if (ctrl_down) {
                            // Move to start of previous word
                            var pos = ti.cursor;
                            if (pos > 0) pos -= 1;
                            while (pos > 0 and text.value[pos - 1] == ' ') pos -= 1;
                            while (pos > 0 and text.value[pos - 1] != ' ') pos -= 1;
                            ti.cursor = pos;
                        } else {
                            if (ti.cursor > 0) ti.cursor -= 1;
                        }
                    },
                    .right => {
                        if (ctrl_down) {
                            // Move to start of next word
                            var pos = ti.cursor;
                            while (pos < text.len and text.value[pos] != ' ') pos += 1;
                            while (pos < text.len and text.value[pos] == ' ') pos += 1;
                            ti.cursor = pos;
                        } else {
                            if (ti.cursor < text.len) ti.cursor += 1;
                        }
                    },
                    .home => ti.cursor = 0,
                    .end => ti.cursor = text.len,
                    .backSpace => {
                        if (ctrl_down) {
                            // Delete word before cursor
                            if (ti.cursor > 0) {
                                var start = ti.cursor;
                                start -= 1;
                                while (start > 0 and text.value[start - 1] == ' ') start -= 1;
                                while (start > 0 and text.value[start - 1] != ' ') start -= 1;
                                const len = ti.cursor - start;
                                std.mem.copyBackwards(u8, text.value[start..], text.value[ti.cursor..text.len]);
                                text.len -= len;
                                ti.cursor = start;
                            }
                        } else {
                            if (ti.cursor > 0) {
                                std.mem.copyBackwards(u8, text.value[ti.cursor - 1 ..], text.value[ti.cursor..text.len]);
                                text.len -= 1;
                                ti.cursor -= 1;
                            }
                        }
                        ti.dirty = true;
                    },
                    .delete => {
                        if (ctrl_down) {
                            // Delete word after cursor
                            if (ti.cursor < text.len) {
                                var end = ti.cursor;
                                while (end < text.len and text.value[end] == ' ') end += 1;
                                while (end < text.len and text.value[end] != ' ') end += 1;
                                const len = end - ti.cursor;
                                std.mem.copyForwards(u8, text.value[ti.cursor..], text.value[end..text.len]);
                                text.len -= len;
                            }
                        } else {
                            if (ti.cursor < text.len) {
                                std.mem.copyForwards(u8, text.value[ti.cursor..], text.value[ti.cursor + 1 .. text.len]);
                                text.len -= 1;
                            }
                        }
                        ti.dirty = true;
                    },
                    .@"return" => {
                        if (ti.on_submit) |cb| {
                            cb(world, text.value[0..text.len]);
                        }
                    },
                    else => {
                        const c = @intFromEnum(key);
                        if (c >= 32 and c <= 126 and text.len < 255) {
                            var ch: u8 = @intCast(c);
                            if (uppercase and ch >= 'a' and ch <= 'z') {
                                ch -= 32;
                            }
                            if (shift_down) {
                                ch = shiftedChar(ch);
                            }
                            if (!ti.dirty) {
                                text.len = 0;
                                ti.cursor = 0;
                                ti.dirty = true;
                            }
                            std.mem.copyBackwards(u8, text.value[ti.cursor + 1 .. text.len + 1], text.value[ti.cursor..text.len]);
                            text.value[ti.cursor] = ch;
                            text.len += 1;
                            ti.cursor += 1;
                        }
                    },
                }
            }
        }
    }
}

fn renderTextCursors(
    enc_param: RenderEncoder(),
    program_pool: ecs.ResMut(renderer.Program.Pool),
    ui_renderer: ecs.Res(UiRenderer),
    font_pool: ecs.ResMut(renderer.Font.Pool),
    inputs: ecs.Query(.{ *const comp.UiTextInput, *const comp.Text, *const comp.ComputedLayout, *const comp.UiNode }),
) void {
    const enc = enc_param.value;
    const program = program_pool.value.get(ui_renderer.value.program_text) orelse return;
    const basic_program = program_pool.value.get(ui_renderer.value.program) orelse return;
    const cursor_layout = renderer.vertex_parser.createLayout(renderer.vertices.PosColor, .{}, bgfx.getRendererType());

    var it = inputs.iter();
    while (it.next()) |row| {
        const font = font_pool.value.get(row.Text.font) orelse continue;
        const text_slice = row.Text.value[0..row.Text.len];
        const font_size = row.Text.size;
        const color = row.Text.color;
        const pad = row.UiNode.padding;
        const tx = row.ComputedLayout.x + pad.left;
        const ty = row.ComputedLayout.y + pad.top;

        // Render text using text shader
        renderer.Text.renderText(
            enc,
            font,
            text_slice,
            font_size,
            color,
            math.Vec3.init(tx, ty, 0),
            @intFromEnum(renderer.View.Id.@"2d"),
            program.handle,
            .{
                .u_color = ui_renderer.value.text_color_uniform,
                .s_tex_color = ui_renderer.value.sampler_tex_color,
            },
        );

        if (!row.UiTextInput.focused) continue;

        // Draw cursor
        const cursor = @min(row.UiTextInput.cursor, text_slice.len);
        const prefix = text_slice[0..cursor];
        const m = renderer.Text.measureText(font, prefix, font_size);

        const cx = tx + m.width;
        const cy = row.ComputedLayout.y;
        const ch = row.ComputedLayout.height;
        const cw: f32 = 2;

        const vertex_count: u32 = 4;
        const index_count: u32 = 6;

        var tvb: bgfx.TransientVertexBuffer = undefined;
        var tib: bgfx.TransientIndexBuffer = undefined;
        if (!bgfx.allocTransientBuffers(&tvb, &cursor_layout, vertex_count, &tib, index_count, false)) continue;

        const verts: [*]renderer.vertices.PosColor = @ptrCast(@alignCast(tvb.data));
        const indices: [*]u16 = @ptrCast(@alignCast(tib.data));

        verts[0] = .{ .position = .init(cx, cy, 0), .color0 = .{ .r = 255, .g = 255, .b = 255, .a = 255 } };
        verts[1] = .{ .position = .init(cx + cw, cy, 0), .color0 = .{ .r = 255, .g = 255, .b = 255, .a = 255 } };
        verts[2] = .{ .position = .init(cx + cw, cy + ch, 0), .color0 = .{ .r = 255, .g = 255, .b = 255, .a = 255 } };
        verts[3] = .{ .position = .init(cx, cy + ch, 0), .color0 = .{ .r = 255, .g = 255, .b = 255, .a = 255 } };

        indices[0] = 0; indices[1] = 1; indices[2] = 2;
        indices[3] = 0; indices[4] = 2; indices[5] = 3;

        enc.setTransientVertexBuffer(0, &tvb, 0, vertex_count);
        enc.setTransientIndexBuffer(&tib, 0, index_count);
        const src_alpha: u64 = 5;
        const inv_src_alpha: u64 = 6;
        const blend = (src_alpha << 12) | (inv_src_alpha << 16) | (src_alpha << 20) | (inv_src_alpha << 24);
        enc.setState(
            bgfx.StateFlags_WriteRgb | bgfx.StateFlags_WriteA | bgfx.StateFlags_Msaa | bgfx.StateFlags_DepthTestAlways | blend,
            0,
        );
        enc.submit(@intFromEnum(renderer.View.Id.@"2d"), basic_program.handle, 1, 0xff);
    }
}

fn applyScrollSystem(world: *ecs.World) void {
    const hierarchy = world.getMutResource(ecs.Hierarchy) orelse return;
    var q = world.query(&.{ comp.Scroll });
    while (q.next()) |hit| {
        const scroll = world.get(hit.entity, comp.Scroll) orelse continue;
        const children = hierarchy.getChildren(hit.entity) orelse continue;
        for (children) |child| {
            offsetDescendants(world, hierarchy, child, -scroll.offset_x, -scroll.offset_y);
        }
    }
}

fn offsetDescendants(
    world: *ecs.World,
    hierarchy: *ecs.Hierarchy,
    entity: ecs.Entity,
    dx: f32,
    dy: f32,
) void {
    if (world.getMut(entity, comp.ComputedLayout)) |layout| {
        layout.x += dx;
        layout.y += dy;
    }
    const children = hierarchy.getChildren(entity) orelse return;
    for (children) |child| {
        offsetDescendants(world, hierarchy, child, dx, dy);
    }
}
