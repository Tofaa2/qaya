const App = @import("../App.zig");
const ecs = @import("ecs");
const std = @import("std");
const events = @import("../events.zig");
const renderer = @import("renderer");
const Window = @import("window.zig").Plugin.api.Window;
const bgfx = renderer.bgfx;
const comp = @import("../components/root.zig");
const res = @import("../resources/root.zig");

const LightUniforms = struct {
    light_dir: bgfx.UniformHandle,
    light_color: bgfx.UniformHandle,
    ambient_color: bgfx.UniformHandle,
    camera_pos: bgfx.UniformHandle,
    light_counts: bgfx.UniformHandle,
    light_pos: bgfx.UniformHandle,
    light_pos_color: bgfx.UniformHandle,
    s_env_map: bgfx.UniformHandle,
    u_env_intensity: bgfx.UniformHandle,
};

const FallbackResources = struct {
    white_texture: bgfx.TextureHandle,
    s_tex_color: bgfx.UniformHandle,
};

const RenderEncoder = @import("../RenderEncoder.zig").RenderEncoder;

pub const TextRenderer = struct {
    program: renderer.Program.Pool.Handle,
    uniforms: renderer.Text.TextUniforms,
};

pub const Plugin = struct {
    pub const api = renderer;
    pub const log = std.log.scoped(.renderer);

    pub fn build(_: *const Plugin, app: *App) void {
        app.world.scheduler.add(.init, init) catch unreachable;
        app.world.scheduler.add(.update, cameraControl) catch unreachable;
        app.world.scheduler.add(.render, prepareRenderViews) catch unreachable;
        app.world.scheduler.add(.render, renderSkybox) catch unreachable;
        app.world.scheduler.add(.render, renderPbrMeshes) catch unreachable;
        app.world.scheduler.add(.render, renderTexts) catch unreachable;
        app.world.scheduler.add(.present, present) catch unreachable;
        app.world.addEventSystem(events.WindowResize, handleResize);
    }

    fn init(world: *ecs.World) void {
        var w_ptr = world.getMutResource(Window) orelse @panic("Could not find window plugin");
        const ndt = w_ptr.getNativeNdt();
        const ptr = w_ptr.getNativePtr();
        const size = w_ptr.getSize();
        world.insertResource(renderer.Device.init(.{
            .allocator = undefined,
            .height = @intCast(size[1]),
            .ndt = ndt,
            .nwh = ptr,
            .width = @intCast(size[0]),
            .debug = true,
            .aa_mode = .msaa4x,
        }) catch unreachable);
        world.insertResource(renderer.State.init(world.allocator));
        world.insertResource(renderer.Program.Pool.init(world.allocator, world.io));
        world.insertResource(renderer.Mesh.Pool.init(world.allocator, world.io));
        world.insertResource(renderer.UniformStore.init(world.allocator));
        world.insertResource(renderer.Texture.Pool.init(world.allocator, world.io));
        world.insertResource(renderer.Material.Pool.init(world.allocator, world.io));
        world.insertResource(renderer.Font.Pool.init(world.allocator, world.io));

        var state_ptr = world.getMutResource(renderer.State).?;
        state_ptr.refreshViewports(.init(0, 0, @intCast(size[0]), @intCast(size[1])));
        {
            var view_2d = state_ptr.getView(.@"2d");
            view_2d.camera = .ui(@floatFromInt(size[0]), @floatFromInt(size[1]));
            view_2d.refresh();
        }

        var store = world.getMutResource(renderer.UniformStore).?;
        world.insertResource(LightUniforms{
            .light_dir = store.create("u_lightDir", .vec4),
            .light_color = store.create("u_lightColor", .vec4),
            .ambient_color = store.create("u_ambientColor", .vec4),
            .camera_pos = store.create("u_cameraPos", .vec4),
            .light_counts = store.create("u_lightCounts", .vec4),
            .light_pos = store.createN("u_lightPos", .vec4, 4),
            .light_pos_color = store.createN("u_lightPosColor", .vec4, 4),
            .s_env_map = store.create("s_envMap", .sampler),
            .u_env_intensity = store.create("u_envIntensity", .vec4),
        });

        // Create a 1x1 white fallback texture so untextured materials don't sample garbage
        {
            var tex_pool = world.getMutResource(renderer.Texture.Pool).?;
            const white_pixel = [_]u8{ 255, 255, 255, 255 };
            const wt = tex_pool.load(&.{ .memory = .{
                .data = &white_pixel,
                .width = 1,
                .height = 1,
                .format = .RGBA8,
            } }) catch |err| {
                log.err("Failed to create white fallback texture: {s}", .{@errorName(err)});
                return;
            };
            const white_texture = tex_pool.get(wt).?;
            world.insertResource(FallbackResources{
                .white_texture = white_texture.handle,
                .s_tex_color = store.create("s_texColor", .sampler),
            });
        }

        {
            const skybox = renderer.Skybox.init(
                world.getMutResource(renderer.Program.Pool).?,
                world.getMutResource(renderer.UniformStore).?,
            ) catch |err| {
                log.err("Failed to init skybox: {s}", .{@errorName(err)});
                return;
            };
            world.insertResource(skybox);
        }

        // Insert a default (invalid) environment map; users can overwrite this later.
        // The skybox will simply not render until a valid EnvironmentMap is provided.
        world.insertResource(renderer.EnvironmentMap{
            .texture = .{ .idx = std.math.maxInt(u16) },
            .intensity = 1.0,
        });

        {
            const program_pool = world.getMutResource(renderer.Program.Pool).?;
            const text_program = program_pool.load(&renderer.Text.programInfo()) catch |err| {
                log.err("Failed to load text shader program: {s}", .{@errorName(err)});
                return;
            };
            world.insertResource(TextRenderer{
                .program = text_program,
                .uniforms = renderer.Text.initUniforms(store),
            });
        }

        log.info("Renderer initialized {}", .{world.getResource(renderer.Device).?.getRendererType()});
    }

fn cameraControl(
    input: ecs.Res(res.InputState),
    time: ecs.Res(res.Time),
    query: ecs.Query(.{ *comp.Camera, *comp.MainCamera }),
) void {
    const delta = time.value.delta;
        const speed = 5.0 * delta;

        var qit = query.iter();
        while (qit.next()) |row| {
            var cam = row.Camera;
            if (cam.is3d()) {
                const p = cam.perspectiveRef();
                if (input.value.isDown(.w)) p.moveForward(speed);
                if (input.value.isDown(.s)) p.moveBackward(speed);
                if (input.value.isDown(.a)) p.moveLeft(speed);
                if (input.value.isDown(.d)) p.moveRight(speed);
                if (input.value.isDown(.space)) p.moveUp(speed);
                if (input.value.isDown(.shiftL)) p.moveDown(speed);
            }
        }
    }

    fn prepareRenderViews(
        state_res: ecs.ResMut(renderer.State),
        cameras: ecs.Query(.{ *comp.Camera, *comp.MainCamera }),
    ) void {
        const state = state_res.value;
        var cam_it = cameras.iter();
        if (cam_it.next()) |cam| {
            var view = state.getView(.@"3d");
            view.camera = cam.Camera.*;
        }
        state.enableView(.@"3d");
        state.enableView(.@"2d");
        state.refreshActiveViews();
    }

    fn renderSkybox(
        enc_param: RenderEncoder(),
        cameras: ecs.Query(.{ *comp.Camera, *comp.MainCamera }),
        skybox: ecs.Res(renderer.Skybox),
        env_map: ecs.Res(renderer.EnvironmentMap),
    ) void {
        const enc = enc_param.value;
        if (env_map.value.texture.idx != std.math.maxInt(u16)) {
            if (cameras.first()) |cam| {
                skybox.value.render(enc, env_map.value, @intFromEnum(renderer.View.Id.@"3d"), cam.Camera.position());
            }
        } else {
            log.warn("No environment map available — skybox will not be rendered", .{});
        }
    }

    fn renderPbrMeshes(
        enc_param: RenderEncoder(),
        program_pool: ecs.ResMut(renderer.Program.Pool),
        mesh_pool: ecs.ResMut(renderer.Mesh.Pool),
        mat_pool: ecs.ResMut(renderer.Material.Pool),
        texture_pool: ecs.ResMut(renderer.Texture.Pool),
        uniform_store: ecs.ResMut(renderer.UniformStore),
        light_uniforms: ecs.Res(LightUniforms),
        fallback: ecs.Res(FallbackResources),
        cameras: ecs.Query(.{ *comp.Camera, *comp.MainCamera }),
        meshes: ecs.Query(.{ *comp.MeshComponent, *comp.GlobalTransform, *comp.RenderVisible }),
        lights: ecs.Query(.{*comp.Light}),
        point_lights: ecs.Query(.{ *comp.Transform, *comp.Light }),
        env_map: ecs.Res(renderer.EnvironmentMap),
    ) void {
        const enc = enc_param.value;
        const lu = light_uniforms.value;

        // --- Collect point lights (entities with both Transform and Light) ---
        var pt_pos: [4][4]f32 = .{.{ 0, 0, 0, 0 }} ** 4;
        var pt_color: [4][4]f32 = .{.{ 0, 0, 0, 0 }} ** 4;
        var num_pt: u32 = 0;

        var pt_it = point_lights.iter();
        while (pt_it.next()) |row| : (num_pt += 1) {
            if (num_pt >= 4) break;
            const t = row.Transform;
            const l = row.Light;
            pt_pos[num_pt] = .{ t.position.x, t.position.y, t.position.z, 10.0 };
            pt_color[num_pt] = .{
                @as(f32, @floatFromInt(l.color.r)) / 255.0,
                @as(f32, @floatFromInt(l.color.g)) / 255.0,
                @as(f32, @floatFromInt(l.color.b)) / 255.0,
                l.intensity,
            };
        }

        // --- Directional light (first non-zero direction Light without Transform) ---
        var has_dir: f32 = 0;
        var dir_dir: [4]f32 = .{ 0, 0, 0, 0 };
        var dir_color: [4]f32 = .{ 0, 0, 0, 0 };
        var ambient: [4]f32 = .{ 0.8, 0.85, 1.0, 1.0 };

        var light_it = lights.iter();
        while (light_it.next()) |row| {
            const l = row.Light;
            const lx: f32 = l.direction.x;
            const ly: f32 = l.direction.y;
            const lz: f32 = l.direction.z;
            const len = @sqrt(lx * lx + ly * ly + lz * lz);
            if (len > 0.0001 and has_dir == 0) {
                has_dir = 1.0;
                dir_dir = .{ lx / len, ly / len, lz / len, 0 };
                dir_color = .{
                    @as(f32, @floatFromInt(l.color.r)) / 255.0,
                    @as(f32, @floatFromInt(l.color.g)) / 255.0,
                    @as(f32, @floatFromInt(l.color.b)) / 255.0,
                    l.intensity,
                };
            }
        }

        var camera_pos: [4]f32 = .{ 0, 0, 0, 0 };
        if (cameras.first()) |cam| {
            const pos = cam.Camera.position();
            camera_pos = .{ pos.x, pos.y, pos.z, 0 };
        }

        var mesh_it = meshes.iter();
        while (mesh_it.next()) |row| {
            const mesh = mesh_pool.value.get(row.MeshComponent.value) orelse continue;
            const mat = mat_pool.value.get(row.MeshComponent.material) orelse continue;

            if (mat.needsBake()) {
                mat.bakeWithFallback(program_pool.value, uniform_store.value, texture_pool.value, fallback.value.white_texture) catch |err| {
                    std.log.err("Failed to bake material: {s}", .{@errorName(err)});
                    continue;
                };
            }

            const program = program_pool.value.get(mat.program) orelse continue;
            const model = row.GlobalTransform.value;

            // Set transform for current draw call
            enc.setTransform(&model);

            // BGFX is stateless between submit calls; we MUST bind global light and env map uniforms on the encoder for EVERY mesh draw call.
            enc.setUniform(lu.light_dir, &dir_dir, 1);
            enc.setUniform(lu.light_color, &dir_color, 1);
            enc.setUniform(lu.ambient_color, &ambient, 1);
            enc.setUniform(lu.camera_pos, &camera_pos, 1);
            const counts = [_]f32{ @floatFromInt(num_pt), has_dir, 0, 0 };
            enc.setUniform(lu.light_counts, &counts, 1);
            enc.setUniform(lu.light_pos, &pt_pos, 4);
            enc.setUniform(lu.light_pos_color, &pt_color, 4);

            if (env_map.value.texture.idx != std.math.maxInt(u16)) {
                enc.setTexture(0, lu.s_env_map, env_map.value.texture, std.math.maxInt(u32));
                const env_intensity = [_]f32{ env_map.value.intensity, 0, 0, 0 };
                enc.setUniform(lu.u_env_intensity, &env_intensity, 1);
            }

            enc.submitMaterial(mat);
            enc.setVertexBuffer(0, mesh.vb, 0, mesh.vertex_count);
            enc.setIndexBuffer(mesh.ib, 0, mesh.index_count);
            enc.setState(bgfx.StateFlags_Default, 0);
            enc.submit(@intFromEnum(renderer.View.Id.@"3d"), program.handle, 0, 0xff);
        }
    }

fn renderTexts(
    enc_param: RenderEncoder(),
    program_pool: ecs.ResMut(renderer.Program.Pool),
    font_pool: ecs.ResMut(renderer.Font.Pool),
    text_renderer: ecs.Res(TextRenderer),
    texts: ecs.Query(.{ *comp.Text, *comp.Transform }),
) void {
    const enc = enc_param.value;
    const program = program_pool.value.get(text_renderer.value.program) orelse {
        log.warn("text program not found", .{});
        return;
    };
    const uniforms = text_renderer.value.uniforms;

    var it = texts.iter();
    var count: u32 = 0;
    while (it.next()) |row| {
            const text_comp = row.Text;
            const transform = row.Transform;
            const font = font_pool.value.get(text_comp.font) orelse {
                log.warn("font not found", .{});
                continue;
            };

            renderer.Text.renderText(
                enc,
                font,
                text_comp.value[0..text_comp.len],
                text_comp.size,
                text_comp.color,
                transform.position,
                @intFromEnum(renderer.View.Id.@"2d"),
                program.handle,
                uniforms,
            );
            count += 1;
        }
    }

    fn present(dev: ecs.ResMut(renderer.Device), state_res: ecs.ResMut(renderer.State)) void {
        dev.value.frame();
        state_res.value.clearActiveViews();
    }

    fn handleResize(event: events.WindowResize, dev: ecs.ResMut(renderer.Device), state_res: ecs.ResMut(renderer.State)) void {
        dev.value.resize(event.width, event.height);
        const f32w: f32 = @floatFromInt(event.width);
        const f32h: f32 = @floatFromInt(event.height);

        {
            var view = state_res.value.getView(.@"3d");
            view.viewport.height = @intCast(event.height);
            view.viewport.width = @intCast(event.width);
            view.refresh();
        }
        {
            var view = state_res.value.getView(.@"2d");
            view.viewport.height = @intCast(event.height);
            view.viewport.width = @intCast(event.width);
            view.camera = .ui(f32w, f32h);
            view.refresh();
        }
    }
};
