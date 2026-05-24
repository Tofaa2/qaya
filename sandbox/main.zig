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
    try app.addSystem(.post_init, spawnCube);
    try app.addSystem(.post_init, spawnSphere);
    try app.addSystem(.post_init, spawnGround);
    try app.addSystem(.post_init, spawnDirLight);
    try app.addSystem(.post_update, lockMouse);
    app.run();
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

fn spawnCube(
    world: *ecs.World,
    mesh_pool: ecs.ResMut(qaya.rendering.Mesh.Pool),
    mat_pool: ecs.ResMut(qaya.rendering.Material.Pool),
) !void {
    const mesh = try mesh_pool.value.load(&.{ .lit_cube = {} });
    const mat = try mat_pool.value.load(&.{ .pbr = .{
        .base_color_texture = "sandbox/assets/shinoa.png",
        .roughness = 0.3,
        .metallic = 0.1,
    } });
    _ = try world.spawn(qaya.bundles.PbrBundle{
        .mesh_component = .{ .value = mesh, .material = mat },
        .transform = .{ .position = .init(-2.5, 1.5, 0) },
    });
}

fn spawnSphere(
    world: *ecs.World,
    mesh_pool: ecs.ResMut(qaya.rendering.Mesh.Pool),
    mat_pool: ecs.ResMut(qaya.rendering.Material.Pool),
) !void {
    const mesh = try mesh_pool.value.load(&.{ .lit_sphere = .{ .radius = 1.0, .segments = 32 } });
    const mat = try mat_pool.value.load(&.{ .pbr = .{
        .base_color = math.Color{ .r = 255, .g = 215, .b = 0, .a = 255 },
        .metallic = 0.95,
        .roughness = 0.1,
        .environment_texture = "sandbox/assets/818-hdri-skies-com/818-hdri-skies-com.hdr",
    } });
    _ = try world.spawn(qaya.bundles.PbrBundle{
        .mesh_component = .{ .value = mesh, .material = mat },
        .transform = .{ .position = .init(2.5, 1.5, 0) },
    });
}

fn spawnGround(
    world: *ecs.World,
    mesh_pool: ecs.ResMut(qaya.rendering.Mesh.Pool),
    mat_pool: ecs.ResMut(qaya.rendering.Material.Pool),
) !void {
    const mesh = try mesh_pool.value.load(&.{ .plane = .{ .width = 20, .depth = 20 } });
    const mat = try mat_pool.value.load(&.{ .pbr = .{
        .base_color = math.Color{ .r = 50, .g = 50, .b = 55, .a = 255 },
        .roughness = 0.9,
    } });
    _ = try world.spawn(qaya.bundles.PbrBundle{
        .mesh_component = .{ .value = mesh, .material = mat },
        .transform = .{ .position = .init(0, 0, 0) },
    });
}

fn spawnEnvironmentMap(
    world: *ecs.World,
    tex_pool: ecs.ResMut(qaya.rendering.Texture.Pool),
) !void {
    const info: qaya.rendering.Texture.Info = .{ .hdr_file = .{ .path = "818-hdri-skies-com/818-hdri-skies-com.hdr" } };
    const handle = try tex_pool.value.load(&info);
    const tex = tex_pool.value.get(handle).?;
    if (world.getMutResource(qaya.rendering.EnvironmentMap)) |env| {
        env.* = qaya.rendering.EnvironmentMap{
            .texture = tex.handle,
            .intensity = 1.0,
        };
    }
}

fn spawnPlayer(world: *ecs.World) !void {
    _ = try world.spawn(qaya.bundles.CameraBundle{
        .camera = qaya.components.Camera.fps(.init(0, 3.5, 7), .zero(), 16.0 / 9.0),
    });
}

fn spawnDirLight(world: *ecs.World) !void {
    _ = try world.spawn(qaya.bundles.LightBundle{
        .light = .{
            .direction = .init(-1, -2, -1),
            .color = math.Color.white,
            .intensity = 0.8,
        },
    });
}
