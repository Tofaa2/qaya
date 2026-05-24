const ecs = @import("ecs");
const Time = @import("../resources/Time.zig");
const App = @import("../App.zig");

pub const Plugin = struct {
    pub fn build(_: *const Plugin, app: *App) void {
        app.world.insertResource(Time.init(app.world.io));
        app.world.scheduler.add(.pre_update, tickTime) catch unreachable;
    }

    fn tickTime(time: ecs.ResMut(Time)) void {
        time.value.tick();
    }
};
