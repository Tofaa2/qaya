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
    try app.addSystem(.update, lockMouse);
    try app.addSystem(.post_update, orbitLight);
    app.run();
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
    const speed = 0.6;
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

fn lockMouse(
    window_res: ecs.ResMut(qaya.windowing.Window),
    input_res: ecs.ResMut(qaya.resources.InputState),
    cameras: ecs.Query(.{ *qaya.components.Camera, *qaya.components.MainCamera }),
) void {
    const window = window_res.value;
    const input = input_res.value;

    const was_captured = window.getMouseCaptured();

    if (input.isJustPressed(.l)) {
        window.setMouseCaptured(!was_captured);
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
