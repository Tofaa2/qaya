const std = @import("std");
const app_sdk = @import("app-sdk");
const ecs = app_sdk.ecs;
const renderer = @import("renderer");
pub const Context = @import("context.zig").Context;
pub const UIRenderer = @import("renderer.zig").UIRenderer;

const input_system = @import("input.zig").system;
const render_system = @import("renderer.zig").system;

pub const Plugin = struct {
    pub fn build(_: *const Plugin, app: *app_sdk.App) void {
        app.world.scheduler.add(.post_init, init) catch unreachable;
        app.world.scheduler.add(.update, input_system) catch unreachable;
        app.world.scheduler.add(.render, render_system) catch unreachable;
    }
};

fn init(world: *ecs.World) void {
    var ctx: Context = undefined;
    ctx.allocator = world.allocator;
    ctx.init();
    world.insertResource(ctx);

    var program_pool = world.getMutResource(renderer.Program.Pool).?;
    const basic_program = program_pool.load(&renderer.Program.basicProgramInfo()) catch |err| {
        std.log.err("Failed to load UI basic shader program: {s}", .{@errorName(err)});
        return;
    };
    world.insertResource(UIRenderer{ .basic_program = basic_program });
}
