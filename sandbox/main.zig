const std = @import("std");
const qaya = @import("app-sdk");
const ecs = qaya.ecs;
const math = qaya.math;

pub const std_options = qaya.default_options;

pub fn main(init: std.process.Init) !void {
    var app = qaya.App.init(init);
    defer app.deinit();

    try app.addPlugins(qaya.plugins.Defaults);
    try app.addSystem(.post_init, spawnPlayer);
    try app.addSystem(.post_init, spawnEnvironmentMap);
    try app.addSystem(.post_init, spawnGround);
    try app.addSystem(.post_init, spawnBalls);
    try app.addSystem(.post_init, spawnDirLight);
    try app.addSystem(.post_init, spawnText);
    try app.addSystem(.post_init, spawnUi);
    try app.addSystem(.update, myUiSystem);
    try app.addSystem(.post_update, lockMouse);
    try app.addSystem(.post_update, orbitLight);
    app.run();
}

fn lockMouse(
    world: *ecs.World,
    window_res: ecs.ResMut(qaya.windowing.Window),
    input_res: ecs.ResMut(qaya.resources.InputState),
    cameras: ecs.Query(.{ *qaya.components.Camera, *qaya.components.MainCamera }),
) void {
    const window = window_res.value;
    const input = input_res.value;

    // Don't toggle mouse capture while typing in a text input
    {
        var ti_q = world.query(&.{ qaya.components.ui.UiTextInput });
        while (ti_q.next()) |hit| {
            const ti = world.get(hit.entity, qaya.components.ui.UiTextInput) orelse continue;
            if (ti.focused) return;
        }
    }

    const was_captured = window.getMouseCaptured();

    if (input.isJustPressed(.l)) {
        window.setMouseCaptured(!was_captured);
        std.log.info("Updated mouse capture state", .{});
    }

    if (window.getMouseCaptured()) {
        if (!was_captured) window.resetMouseDelta();
        const delta = window.getMouseDelta();
        window.resetMouseDelta();

        if (delta[0] == 0 and delta[1] == 0) return;

        const cam = cameras.first() orelse return;
        const camera: *math.Camera = cam.Camera;
        if (camera.is3d()) {
            camera.kind.perspective.lookFromMouse(delta[0], delta[1], 0.001);
        }
    }
}

fn spawnPlayer(world: *ecs.World) !void {
    _ = try world.spawn(qaya.bundles.CameraBundle{
        .camera = qaya.components.Camera.fps(.init(0, 4, 12), .zero(), 16.0 / 9.0),
    });
}

fn spawnEnvironmentMap(
    world: *ecs.World,
    tex_pool: ecs.ResMut(qaya.rendering.Texture.Pool),
) void {
    const env_hdr = "sandbox/assets/skybox.hdr";
    const info: qaya.rendering.Texture.Info = .{ .hdr_file = .{ .path = env_hdr } };
    const handle = tex_pool.value.load(&info) catch |err| {
        std.log.err("Failed to load environment map: {s}", .{@errorName(err)});
        return;
    };
    const tex = tex_pool.value.get(handle) orelse return;
    if (world.getMutResource(qaya.rendering.EnvironmentMap)) |env| {
        env.* = qaya.rendering.EnvironmentMap{
            .texture = tex.handle,
            .intensity = 1.0,
        };
    }
}

fn spawnGround(
    world: *ecs.World,
    mesh_pool: ecs.ResMut(qaya.rendering.Mesh.Pool),
    mat_pool: ecs.ResMut(qaya.rendering.Material.Pool),
) !void {
    const mesh = try mesh_pool.value.load(&.{ .plane = .{ .width = 30, .depth = 20 } });
    const mat = try mat_pool.value.load(&.{ .pbr = .{
        .base_color = math.Color{ .r = 60, .g = 62, .b = 68, .a = 255 },
        .roughness = 0.95,
        .metallic = 0.0,
    } });
    _ = try world.spawn(qaya.bundles.PbrBundle{
        .mesh_component = .{ .value = mesh, .material = mat },
        .transform = .{ .position = .init(0, 0, 0) },
    });
}

const BallConfig = struct {
    name: []const u8,
    color: math.Color,
    metallic: f32,
    roughness: f32,
    texture: ?[:0]const u8 = null,
};

fn spawnBalls(
    world: *ecs.World,
    mesh_pool: ecs.ResMut(qaya.rendering.Mesh.Pool),
    mat_pool: ecs.ResMut(qaya.rendering.Material.Pool),
) !void {
    const mesh = try mesh_pool.value.load(&.{ .lit_sphere = .{ .radius = 0.5, .segments = 32 } });

    const balls = [_]BallConfig{
        .{ .name = "Red Plastic", .color = .{ .r = 220, .g = 40, .b = 40, .a = 255 }, .metallic = 0.0, .roughness = 0.5 },
        .{ .name = "Blue Plastic", .color = .{ .r = 40, .g = 80, .b = 220, .a = 255 }, .metallic = 0.0, .roughness = 0.3 },
        .{ .name = "Green Plastic", .color = .{ .r = 40, .g = 180, .b = 60, .a = 255 }, .metallic = 0.0, .roughness = 0.7 },
        .{ .name = "White Ceramic", .color = .{ .r = 230, .g = 230, .b = 230, .a = 255 }, .metallic = 0.0, .roughness = 0.1 },
        .{ .name = "Brushed Steel", .color = .{ .r = 180, .g = 180, .b = 190, .a = 255 }, .metallic = 0.7, .roughness = 0.55 },
        .{ .name = "Copper", .color = .{ .r = 220, .g = 120, .b = 70, .a = 255 }, .metallic = 0.9, .roughness = 0.35 },
        .{ .name = "Gold Rough", .color = .{ .r = 255, .g = 200, .b = 50, .a = 255 }, .metallic = 1.0, .roughness = 0.6 },
        .{ .name = "Gold Smooth", .color = .{ .r = 255, .g = 200, .b = 50, .a = 255 }, .metallic = 1.0, .roughness = 0.15 },
        .{ .name = "Chrome Rough", .color = .{ .r = 200, .g = 200, .b = 210, .a = 255 }, .metallic = 1.0, .roughness = 0.5 },
        .{ .name = "Chrome Mirror", .color = .{ .r = 200, .g = 200, .b = 210, .a = 255 }, .metallic = 1.0, .roughness = 0.05 },
    };

    const count = balls.len;
    const spacing = 1.5;
    const start_x = -@as(f32, @floatFromInt(count - 1)) * spacing / 2.0;

    for (balls, 0..) |ball, i| {
        const x: f32 = start_x + @as(f32, @floatFromInt(i)) * spacing;
        const mat = try mat_pool.value.load(&.{ .pbr = .{
            .base_color = ball.color,
            .base_color_texture = ball.texture,
            .metallic = ball.metallic,
            .roughness = ball.roughness,
        } });
        _ = try world.spawn(qaya.bundles.PbrBundle{
            .mesh_component = .{ .value = mesh, .material = mat },
            .transform = .{ .position = .init(x, 0.55, 0) },
        });
        std.log.info("Spawned ball: {s} at x={d:.1}", .{ ball.name, x });
    }
}
fn spawnDirLight(world: *ecs.World) !void {
    _ = try world.spawn(.{
        qaya.components.Light{
            .direction = .init(-1, -2, -1),
            .color = math.Color.white,
            .intensity = 1.5,
        },
    });
}

var orbit_angle: f32 = 0.0;

fn orbitLight(
    time: ecs.Res(qaya.resources.Time),
    lights: ecs.Query(.{*qaya.components.Light}),
) void {
    const dt = time.value.delta;
    const speed = 0.6; // radians per second
    orbit_angle += dt * speed;

    const radius = 4.0;
    const height = -2.0;
    const dx = @cos(orbit_angle) * radius;
    const dz = @sin(orbit_angle) * radius;

    var it = lights.iter();
    while (it.next()) |row| {
        row.Light.direction = .init(dx, height, dz);
    }
}

fn spawnText(
    world: *ecs.World,
    font_pool: ecs.ResMut(qaya.rendering.Font.Pool),
) !void {
    std.log.info("spawnText: loading font...", .{});
    const font = try font_pool.value.load(&.{
        .ttf_data = @embedFile("assets/DejaVuSans.ttf"),
        .size = 48.0,
    });
    const text_bytes = "Hello Qaya!";
    var buf: [256]u8 = undefined;
    @memcpy(buf[0..text_bytes.len], text_bytes);
    _ = try world.spawn(.{
        qaya.components.Text{
            .value = buf,
            .len = text_bytes.len,
            .font = font,
            .size = 32.0,
            .color = math.Color{ .r = 255, .g = 255, .b = 255, .a = 255 },
        },
        qaya.components.Transform{ .position = .init(240, 40, 0) },
    });
    std.log.info("spawnText: done", .{});
}

fn spawnUi(
    world: *ecs.World,
    font_pool: ecs.ResMut(qaya.rendering.Font.Pool),
    tex_pool: ecs.ResMut(qaya.rendering.Texture.Pool),
) !void {
    const root = try world.spawn(.{
        qaya.components.ui.UiNode{
            .flex_grow = 1,
            .direction = .row,
        },
    });

    const sidebar = try world.spawn(.{
        qaya.components.ui.UiNode{
            .width = 220,
            .flex_grow = 0,
            .padding = .{ .left = 20, .right = 20, .top = 20, .bottom = 20 },
            .direction = .column,
            .align_items = .stretch,
        },
        qaya.components.ui.UiBackground{ .color = .{ .r = 20, .g = 22, .b = 28, .a = 200 } },
        qaya.components.Parent{ .entity = root },
    });

    const button = try world.spawn(.{
        qaya.components.ui.UiNode{
            .height = 40,
            .flex_grow = 0,
        },
        qaya.components.ui.UiBackground{ .color = .{ .r = 50, .g = 120, .b = 200, .a = 255 } },
        @as(qaya.components.ui.UiInteraction, .none),
        qaya.components.ui.ClickAction{ .callback = toggleLights },
        qaya.components.Parent{ .entity = sidebar },
    });

    // Font shared by UI text children
    const font = try font_pool.value.load(&.{
        .ttf_data = @embedFile("assets/DejaVuSans.ttf"),
        .size = 48.0,
    });

    // Text input field (Text and UiTextInput on the same entity)
    const input_text = "Type here...";
    var input_buf: [256]u8 = undefined;
    @memcpy(input_buf[0..input_text.len], input_text);
    _ = try world.spawn(.{
        qaya.components.ui.UiNode{
            .width = 180,
            .height = 36,
            .flex_grow = 0,
            .padding = .{ .left = 8, .right = 8, .top = 4, .bottom = 4 },
        },
        qaya.components.ui.UiBackground{ .color = .{ .r = 40, .g = 42, .b = 48, .a = 255 } },
        @as(qaya.components.ui.UiInteraction, .none),
        qaya.components.ui.UiTextInput{
            .on_submit = submitInput,
        },
        qaya.components.Text{
            .value = input_buf,
            .len = input_text.len,
            .font = font,
            .size = 16.0,
            .color = math.Color{ .r = 180, .g = 180, .b = 180, .a = 255 },
        },
        qaya.components.Parent{ .entity = sidebar },
    });

    // Image panel
    // Image panel
    const img_handle = try tex_pool.value.load(&.{ .file = .{ .path = "sandbox/assets/shinoa.png" } });
    const img_tex = tex_pool.value.get(img_handle) orelse return error.FileNotFound;
    std.log.info("shinoa.png: {}x{}", .{ img_tex.width, img_tex.height });
    _ = try world.spawn(.{
        qaya.components.ui.UiNode{
            .height = 180,
            .flex_grow = 0,
        },
        qaya.components.ui.UiImage{ .texture = img_handle },
        qaya.components.Parent{ .entity = sidebar },
    });

    // Main area with wrapping swatch grid
    const main_area = try world.spawn(.{
        qaya.components.ui.UiNode{
            .flex_grow = 1,
            .padding = .{ .left = 20, .right = 20, .top = 20, .bottom = 20 },
            .direction = .row,
            .wrap = .wrap,
            .justify_content = .space_around,
            .gap = 12,
        },
        qaya.components.ui.Scroll{},
        qaya.components.Parent{ .entity = root },
    });

    const swatch_colors = [_]math.Color{
        .{ .r = 255, .g = 60, .b = 60, .a = 255 },
        .{ .r = 255, .g = 160, .b = 40, .a = 255 },
        .{ .r = 255, .g = 220, .b = 50, .a = 255 },
        .{ .r = 80, .g = 200, .b = 80, .a = 255 },
        .{ .r = 50, .g = 180, .b = 220, .a = 255 },
        .{ .r = 100, .g = 120, .b = 255, .a = 255 },
        .{ .r = 180, .g = 80, .b = 220, .a = 255 },
        .{ .r = 200, .g = 200, .b = 200, .a = 255 },
        .{ .r = 255, .g = 100, .b = 140, .a = 255 },
        .{ .r = 60, .g = 200, .b = 160, .a = 255 },
        .{ .r = 140, .g = 100, .b = 60, .a = 255 },
        .{ .r = 200, .g = 180, .b = 140, .a = 255 },
        .{ .r = 220, .g = 80, .b = 200, .a = 255 },
        .{ .r = 80, .g = 220, .b = 200, .a = 255 },
        .{ .r = 100, .g = 140, .b = 60, .a = 255 },
        .{ .r = 60, .g = 100, .b = 140, .a = 255 },
    };
    for (swatch_colors) |color| {
        _ = try world.spawn(.{
            qaya.components.ui.UiNode{
                .width = 80,
                .height = 80,
                .flex_grow = 0,
                .flex_shrink = 0,
            },
            qaya.components.ui.UiBackground{ .color = color },
            qaya.components.Parent{ .entity = main_area },
        });
    }

    // Button label text
    const label = "Toggle";
    var label_buf: [256]u8 = undefined;
    @memcpy(label_buf[0..label.len], label);
    _ = try world.spawn(.{
        qaya.components.Text{
            .value = label_buf,
            .len = label.len,
            .font = font,
            .size = 18.0,
            .color = math.Color{ .r = 255, .g = 255, .b = 255, .a = 255 },
        },
        qaya.components.ui.UiNode{ .flex_grow = 0 },
        qaya.components.Transform{ .position = .init(0, 0, 0) },
        qaya.components.Parent{ .entity = button },
    });

    std.log.info("spawnUi: done", .{});
}

fn submitInput(world: *ecs.World, text: []const u8) void {
    std.log.info("INPUT SUBMIT: \"{s}\"", .{text});
    _ = world;
}

fn toggleLights(world: *ecs.World) void {
    std.log.info("CLICK!", .{});
    var q = world.query(&.{ qaya.components.Light });
    while (q.next()) |hit| {
        const light = world.getMut(hit.entity, qaya.components.Light).?;
        light.intensity = if (light.intensity > 0) 0 else 1.5;
        std.log.info("toggle light: intensity={d:.1}", .{light.intensity});
    }
}

fn myUiSystem(
    world: *ecs.World,
    buttons: ecs.Query(.{ *const qaya.components.ui.UiInteraction, *qaya.components.ui.UiBackground }),
) void {
    // Button visual feedback
    var hit = buttons.iter();
    while (hit.next()) |row| {
        const bg = row.UiBackground;
        switch (row.UiInteraction.*) {
            .pressed => {
                bg.* = .{ .color = .{ .r = 30, .g = 90, .b = 170, .a = 255 } };
            },
            .hovered => {
                bg.* = .{ .color = .{ .r = 70, .g = 150, .b = 230, .a = 255 } };
            },
            .none => {
                bg.* = .{ .color = .{ .r = 50, .g = 120, .b = 200, .a = 255 } };
            },
        }
    }

    // Scroll main_area with mouse wheel
    const input = world.getResource(qaya.resources.InputState) orelse return;
    const scroll_delta = input.getScrollDelta();
    var sq = world.query(&.{ qaya.components.ui.Scroll });
    while (sq.next()) |srow| {
        const scroll = world.getMut(srow.entity, qaya.components.ui.Scroll) orelse continue;
        scroll.offset_y += scroll_delta[1] * 3;
        scroll.offset_y = @max(scroll.offset_y, 0);
    }
}
