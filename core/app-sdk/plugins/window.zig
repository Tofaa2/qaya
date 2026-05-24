const window = @import("window");
const App = @import("../App.zig");
const ecs = @import("ecs");
const std = @import("std");
const events = @import("../events.zig");
const InputState = @import("../resources/InputState.zig");

pub const Plugin = struct {
    pub const api = @import("window");
    pub const log = std.log.scoped(.window);

    pub fn build(_: *const Plugin, app: *App) void {
        app.world.insertResource(window.Window{});
        app.world.insertResource(InputState{});

        app.world.scheduler.add(.pre_init, init) catch unreachable;
        app.world.scheduler.add(.pre_update, update) catch unreachable;
        app.world.scheduler.add(.frame_end, frameEnd) catch unreachable;
    }

    fn init(res: ecs.ResMut(window.Window), env: ecs.ResMut(std.process.Environ.Map)) !void {
        var ptr = res.value;
        try ptr.init("Qaya", 800, 600, env.value);

        ptr.setExitKey(.escape);
        log.info("Window Initialized", .{});
    }

    fn frameEnd(res: ecs.ResMut(InputState)) void {
        res.value.frameEnd();
    }

    fn update(
        res: ecs.ResMut(window.Window),
        world: *ecs.World,
        input_res: ecs.ResMut(InputState),
    ) !void {
        var w = res.value;

        if (w.shouldClose()) {
            world.publish(events.Quit, events.Quit{});
            log.info("Window Close Requested", .{});
            return;
        }

        while (w.pollEvent()) |e| {
            if (e == .quit) {
                world.publish(events.Quit, events.Quit{});
                log.info("Window Close Requested", .{});
                break;
            }
            if (e == .window_resized) {
                world.publish(events.WindowResize, .{
                    .width = e.window_resized[0],
                    .height = e.window_resized[1],
                });
            }
            input_res.value.handleEvent(e);
        }
    }
};
