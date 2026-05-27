const App = @import("../App.zig");
const ecs = @import("ecs");
const std = @import("std");
const renderer = @import("renderer");
const ui_layout = @import("../ui_layout.zig");
const comp = @import("../components/root.zig");
const res = @import("../resources/root.zig");
const RenderEncoder = @import("../RenderEncoder.zig").RenderEncoder;
const bgfx = renderer.bgfx;
const builtin = renderer.builtin_shaders;

const log = std.log.scoped(.ui);

const UiRenderer = struct {
    program: renderer.Program.Pool.Handle,
};

pub const Plugin = struct {
    pub fn build(_: *const Plugin, app: *App) void {
        app.world.registerComponent(comp.UiNode);
        app.world.registerComponent(comp.ComputedLayout);
        app.world.registerComponent(comp.UiBackground);
        app.world.registerComponent(comp.UiInteraction);

        app.world.scheduler.add(.post_init, uiInit) catch unreachable;
        app.world.scheduler.add(.post_update, uiLayoutSystem) catch unreachable;
        app.world.scheduler.add(.update, uiInteractionSystem) catch unreachable;
        app.world.scheduler.add(.render, renderUiPanels) catch unreachable;

        log.info("UI plugin initialized", .{});
    }
};

fn uiInit(world: *ecs.World) void {
    const program_pool = world.getMutResource(renderer.Program.Pool) orelse return;
    const program = program_pool.load(&renderer.Program.Info.initBuiltin(builtin.fs_basic, builtin.vs_basic)) catch |err| {
        log.err("Failed to load UI shader program: {s}", .{@errorName(err)});
        return;
    };
    world.insertResource(UiRenderer{ .program = program });
}

fn uiLayoutSystem(
    world: *ecs.World,
    window: ecs.ResMut(@import("window.zig").Plugin.api.Window),
) void {
    const size = window.value.getSize();
    ui_layout.run(world, @floatFromInt(size[0]), @floatFromInt(size[1]));
}

fn uiInteractionSystem(
    input: ecs.Res(res.InputState),
    buttons: ecs.Query(.{ *comp.ComputedLayout, *comp.UiInteraction }),
) void {
    const mouse = input.value.getMousePos();
    const mx: f32 = @floatFromInt(mouse[0]);
    const my: f32 = @floatFromInt(mouse[1]);
    const just_pressed = input.value.isMouseJustPressed(.left);

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

fn renderUiPanels(
    enc_param: RenderEncoder(),
    program_pool: ecs.ResMut(renderer.Program.Pool),
    ui_renderer: ecs.Res(UiRenderer),
    panels: ecs.Query(.{ *comp.ComputedLayout, *comp.UiBackground }),
) void {
    const enc = enc_param.value;
    const program = program_pool.value.get(ui_renderer.value.program) orelse return;

    const layout = renderer.vertex_parser.createLayout(renderer.vertices.PosColor, .{}, bgfx.getRendererType());

    var it = panels.iter();
    while (it.next()) |row| {
        const rect = row.ComputedLayout;
        const bg = row.UiBackground;
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
        enc.submit(@intFromEnum(renderer.View.Id.@"2d"), program.handle, 0, 0xff);
    }
}
