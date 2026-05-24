const std = @import("std");
const ecs = @import("ecs");
const plugin = @import("plugin.zig");
const events = @import("events.zig");
const log = std.log.scoped(.App);
const App = @This();

io: std.Io,
allocator: std.mem.Allocator,
world: ecs.World,
plugins: std.ArrayList(plugin.PluginVTable),
env: *std.process.Environ.Map,
running: bool,

pub fn run(self: *App) void {
    std.debug.assert(!self.running);
    self.running = true;

    self.world.resources.addBorrowed(std.mem.Allocator, &self.allocator) catch unreachable;
    self.world.resources.addBorrowed(std.process.Environ.Map, self.env) catch unreachable;

    self.runStage(.pre_init);
    self.runStage(.init);
    self.runStage(.post_init);

    while (self.running) {
        self.world.tickEvents();

        self.runStage(.pre_update);
        self.runStage(.update);
        self.runStage(.post_update);

        self.runStage(.physics);
        self.runStage(.render);
        self.runStage(.present);

        self.runStage(.frame_end);
        if (self.checkClose()) {
            self.running = false;
            break;
        }
    }
    log.info("Calling shutdown stages...", .{});

    self.runStage(.pre_deinit);
    self.runStage(.deinit);
    self.runStage(.post_deinit);
}

fn checkClose(self: *App) bool {
    var chan = self.world.getEventChannel(events.Quit);
    var r = chan.read();
    defer r.release();
    if (r.current.len != 0) {
        return true;
    }
    if (r.previous.len != 0) {
        return false;
    }
    return false;
}

fn runStage(self: *App, stage: anytype) void {
    self.world.scheduler.run(stage, &self.world, self.io) catch |err| {
        log.err("Failed to run stage {s}: {s}\n", .{ @tagName(stage), @errorName(err) });
    };
}

pub fn init(init_t: std.process.Init) App {
    return .{
        .allocator = init_t.gpa,
        .io = init_t.io,
        .world = ecs.World.init(init_t.gpa, init_t.io),
        .plugins = .empty,
        .env = init_t.environ_map,
        .running = false,
    };
}

pub fn deinit(self: *App) void {
    for (self.plugins.items) |*vtable| {
        vtable.deinit(self.allocator);
    }
    self.plugins.deinit(self.allocator);
    self.world.deinit();
}

pub fn addPlugin(self: *App, comptime T: type) !void {
    var vtable = try plugin.makePluginZeroes(T, self.allocator);
    vtable.build(self);
    try self.plugins.append(self.allocator, vtable);
}

pub fn addPlugins(self: *App, comptime plugins: []const type) !void {
    inline for (plugins) |T| {
        try self.addPlugin(T);
    }
}

pub fn addSystem(self: *App, stage: anytype, comptime f: anytype) !void {
    try self.world.scheduler.add(stage, f);
}
