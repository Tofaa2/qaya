const std = @import("std");
const ecs = @import("ecs");
const qaya = @import("app-sdk");
const math = qaya.math;
const renderer = qaya.rendering;
const ui = @import("ui");

pub const EditorName = struct {
    value: [64]u8,
    len: usize,
};

const EditorState = struct {
    allocator: std.mem.Allocator,
    selected: ?ecs.Entity,
    tracked_names: std.AutoHashMapUnmanaged(ecs.Entity, []u8),
};

pub const Plugin = struct {
    pub fn build(_: *const Plugin, app: *qaya.App) void {
        app.world.scheduler.add(.post_init, init) catch unreachable;
        app.world.scheduler.add(.update, editorUI) catch unreachable;
        app.world.scheduler.add(.deinit, deinitEditor) catch unreachable;
    }
};

fn init(world: *ecs.World) !void {
    world.insertResource(EditorState{
        .allocator = world.allocator,
        .selected = null,
        .tracked_names = .empty,
    });
}

fn deinitEditor(state_res: ecs.ResMut(EditorState)) void {
    const state: *EditorState = state_res.value;
    state.tracked_names.deinit(state.allocator);
}

fn editorUI(
    world: *ecs.World,
    ctx_res: ecs.ResMut(ui.Context),
    state_res: ecs.ResMut(EditorState),
    mesh_pool: ecs.ResMut(renderer.Mesh.Pool),
    mat_pool: ecs.ResMut(renderer.Material.Pool),
) void {
    const ctx = ctx_res.value;
    const state: *EditorState = state_res.value;

    ctx.begin();

    if (ctx.beginWindow("Scene Editor", .{ .x = 10, .y = 50, .width = 360, .height = 500 }).active) {
        drawHierarchy(world, ctx, state, mesh_pool, mat_pool);
        ctx.endWindow();
    }

    if (state.selected) |sel| {
        if (world.isAlive(sel)) {
            if (ctx.beginWindow("Inspector", .{ .x = 380, .y = 50, .width = 260, .height = 360 }).active) {
                drawInspector(world, ctx, state, sel);
                ctx.endWindow();
            }
        } else {
            state.selected = null;
        }
    }

    ctx.end();
}

fn drawHierarchy(
    world: *ecs.World,
    ctx: *ui.Context,
    state: *EditorState,
    mesh_pool: ecs.ResMut(renderer.Mesh.Pool),
    mat_pool: ecs.ResMut(renderer.Material.Pool),
) void {
    _ = ctx.header("Hierarchy");
    ctx.layoutRow(-1, null, 0);

    var query = world.query(&.{EditorName});
    while (query.next()) |entry| {
        const en = entry.entity;
        if (world.get(en, EditorName)) |name_comp| {
            const is_sel = if (state.selected) |s| s == en else false;
            if (is_sel) {
                var name_buf: [65]u8 = undefined;
                @memcpy(name_buf[0..name_comp.len], name_comp.value[0..name_comp.len]);
                name_buf[name_comp.len] = 0;
                ctx.labelColor(name_buf[0..name_comp.len :0], .{ .r = 255, .g = 200, .b = 50, .a = 255 });
            }
            var name_buf: [65]u8 = undefined;
            @memcpy(name_buf[0..name_comp.len], name_comp.value[0..name_comp.len]);
            name_buf[name_comp.len] = 0;
            if (ctx.button(name_buf[0..name_comp.len :0]).submit) {
                state.selected = en;
            }
        }
    }

    ctx.layoutRow(-1, null, 0);
    ctx.layoutHeight(24);
    if (ctx.button("+ Spawn").submit) {
        ctx.openPopup("spawn_menu");
    }

    if (ctx.beginPopup("spawn_menu").active) {
        defer ctx.endPopup();
        if (ctx.button("Sphere").submit) {
            spawnPrimitive(world, mesh_pool, mat_pool, "Sphere", .sphere);
        }
        if (ctx.button("Plane").submit) {
            spawnPrimitive(world, mesh_pool, mat_pool, "Plane", .plane);
        }
        if (ctx.button("Cylinder").submit) {
            spawnPrimitive(world, mesh_pool, mat_pool, "Cylinder", .cylinder);
        }
        if (ctx.button("Cube (OBJ)").submit) {
            spawnObjFile(world, mesh_pool, mat_pool, "sandbox/assets/cube-tex.obj", "OBJ Cube");
        }
    }
}

fn drawInspector(
    world: *ecs.World,
    ctx: *ui.Context,
    state: *EditorState,
    entity: ecs.Entity,
) void {
    if (world.get(entity, EditorName)) |name_comp| {
        ctx.textFmt("Name: {s}", .{name_comp.value[0..name_comp.len]});
    }

    ctx.layoutRow(-1, null, 0);

    if (world.getMut(entity, math.Transform)) |transform| {
        _ = ctx.header("Transform");

        var px = transform.position.x;
        var py = transform.position.y;
        var pz = transform.position.z;
        ctx.layoutRow(3, &.{ 20, -1, -1 }, 0);
        ctx.label("P");
        if (ctx.number(&px, 0.1).change) transform.position.x = px;
        if (ctx.number(&py, 0.1).change) transform.position.y = py;
        if (ctx.number(&pz, 0.1).change) transform.position.z = pz;

        var sx = transform.scale.x;
        var sy = transform.scale.y;
        var sz = transform.scale.z;
        ctx.layoutRow(3, &.{ 20, -1, -1 }, 0);
        ctx.label("S");
        if (ctx.number(&sx, 0.1).change) transform.scale.x = sx;
        if (ctx.number(&sy, 0.1).change) transform.scale.y = sy;
        if (ctx.number(&sz, 0.1).change) transform.scale.z = sz;
    }

    ctx.layoutRow(-1, null, 0);
    ctx.layoutHeight(24);
    if (ctx.button("Delete").submit) {
        world.despawn(entity);
        state.selected = null;
    }
}

fn spawnPrimitive(
    world: *ecs.World,
    mesh_pool: ecs.ResMut(renderer.Mesh.Pool),
    mat_pool: ecs.ResMut(renderer.Material.Pool),
    comptime label: []const u8,
    comptime kind: enum { sphere, plane, cylinder },
) void {
    const mesh = mesh_pool.value.load(&switch (kind) {
        .sphere => renderer.Mesh.Info{ .lit_sphere = .{ .radius = 0.5, .segments = 24 } },
        .plane => renderer.Mesh.Info{ .plane = .{ .width = 2, .depth = 2 } },
        .cylinder => renderer.Mesh.Info{ .cylinder = .{ .radius = 0.5, .height = 1, .segments = 24 } },
    }) catch return;

    const mat = mat_pool.value.load(&.{ .pbr = .{
        .base_color = math.Color{ .r = 180, .g = 180, .b = 190, .a = 255 },
        .roughness = 0.5,
        .metallic = 0.5,
    } }) catch return;

    const entity = world.spawn(qaya.bundles.PbrBundle{
        .mesh_component = .{ .value = mesh, .material = mat },
        .transform = .{ .position = .{ .x = 0, .y = 1, .z = 0 } },
    }) catch return;

    var buf: [64]u8 = undefined;
    const len = @min(label.len, buf.len);
    @memcpy(buf[0..len], label[0..len]);
    world.addComponent(entity, EditorName, .{ .value = buf, .len = len }) catch {};
}

fn spawnObjFile(
    world: *ecs.World,
    mesh_pool: ecs.ResMut(renderer.Mesh.Pool),
    mat_pool: ecs.ResMut(renderer.Material.Pool),
    path: []const u8,
    label: []const u8,
) void {
    const mesh = mesh_pool.value.load(&.{ .file = .{ .path = path } }) catch return;
    const mat = mat_pool.value.load(&.{ .pbr = .{
        .base_color = math.Color{ .r = 220, .g = 60, .b = 60, .a = 255 },
        .roughness = 0.4,
        .metallic = 0.6,
    } }) catch return;

    const entity = world.spawn(qaya.bundles.PbrBundle{
        .mesh_component = .{ .value = mesh, .material = mat },
        .transform = .{ .position = .{ .x = 0, .y = 1, .z = 0 } },
    }) catch return;

    var buf: [64]u8 = undefined;
    const len = @min(label.len, buf.len);
    @memcpy(buf[0..len], label[0..len]);
    world.addComponent(entity, EditorName, .{ .value = buf, .len = len }) catch {};
}
