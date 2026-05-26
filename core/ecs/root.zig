const std = @import("std");

pub const Entity = @import("entity.zig").Entity;
pub const EntitySlot = @import("entity.zig").EntitySlot;

pub const registry = @import("registry.zig");

pub const World = @import("world.zig").World;
pub const WorldError = @import("world.zig").Error;

pub const Archetype = @import("archetype.zig").Archetype;
pub const ArchetypeId = @import("archetype.zig").ArchetypeId;

pub const Column = @import("column.zig").Column;

pub const ResourcePool = @import("ResourcePool.zig");
pub const EventChannel = @import("EventChannel.zig").EventChannel;
pub const EventSystem = @import("EventSystem.zig").EventSystem;

pub const ComponentHooks = @import("hooks.zig").ComponentHooks;
pub const Hierarchy = @import("hierarchy.zig").Hierarchy;

pub const serialize = @import("serialize.zig");
pub const assertBundleSerializable = serialize.assertBundleSerializable;
pub const assertSerializable = serialize.assertSerializable;

pub const schedule = @import("schedule.zig");
pub const Schedule = schedule.Schedule;
pub const Masks = schedule.Masks;
pub const masksConflict = schedule.masksConflict;

pub const system = @import("system.zig");
pub const Res = system.Res;
pub const ResMut = system.ResMut;
pub const Events = system.Events;
pub const Query = system.Query;
pub const Commands = system.Commands;
pub const Changed = system.Changed;
pub const Added = system.Added;
pub const runIf = system.runIf;
pub const chain = system.chain;
pub const before = system.before;
pub const after = system.after;

// ---- Tests ------------------------------------------------------------------

test "ecs spawn migrate query" {
    const Position = struct { x: f32, y: f32 };
    const Velocity = struct { vx: f32, vy: f32 };

    var world = World.init(std.testing.allocator, std.testing.io);
    defer world.deinit();

    const e0 = try world.spawn(.{Velocity{ .vx = 3, .vy = 4 }});
    try world.addComponent(e0, Position, .{ .x = 10, .y = 20 });

    const p = world.get(e0, Position).?;
    try std.testing.expectApproxEqAbs(@as(f32, 10), p.x, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 20), p.y, 1e-6);

    if (world.getMut(e0, Velocity)) |v| v.vx = 0.5;

    var q = world.query(&.{ Position, Velocity });
    var seen: usize = 0;
    while (q.next()) |hit| {
        try std.testing.expect(world.isAlive(hit.entity));
        seen += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), seen);

    world.despawn(e0);
    try std.testing.expect(!world.isAlive(e0));
}

test "mask conflict rules" {
    const a = Masks{ .read_mask = 0b001, .write_mask = 0b010 };
    const b = Masks{ .read_mask = 0b100, .write_mask = 0b010 };
    try std.testing.expect(masksConflict(a, b));

    const c = Masks{ .read_mask = 0b001, .write_mask = 0 };
    const d = Masks{ .read_mask = 0, .write_mask = 0b001 };
    try std.testing.expect(masksConflict(c, d));

    const e = Masks{ .read_mask = 0b1, .write_mask = 0 };
    const f = Masks{ .read_mask = 0b10, .write_mask = 0 };
    try std.testing.expect(!masksConflict(e, f));
}

test "resources and events" {
    const MyRes = struct { value: i32 };
    const MyEvent = struct { msg: u32 };

    var world = World.init(std.testing.allocator, std.testing.io);
    defer world.deinit();

    world.insertResource(MyRes{ .value = 42 });
    try std.testing.expectEqual(@as(i32, 42), world.getResource(MyRes).?.value);

    world.registerEvent(MyEvent);
    world.emit(MyEvent{ .msg = 7 });

    {
        const view = world.eventReader(MyEvent);
        defer view.release();
        try std.testing.expectEqual(@as(usize, 1), view.current.len);
        try std.testing.expectEqual(@as(u32, 7), view.current[0].msg);
        try std.testing.expectEqual(@as(usize, 0), view.previous.len);
    }

    world.tickEvents();

    {
        const view = world.eventReader(MyEvent);
        defer view.release();
        // After tick: last frame's event is now in previous, current is empty.
        try std.testing.expectEqual(@as(usize, 0), view.current.len);
        try std.testing.expectEqual(@as(usize, 1), view.previous.len);
        try std.testing.expectEqual(@as(u32, 7), view.previous[0].msg);
    }
}

test "event listeners" {
    const MyEvent = struct { val: u32 };
    const Context = struct {
        sum: u32 = 0,
        fn onEvent(ctx: ?*anyopaque, event: MyEvent) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.sum += event.val;
        }
    };

    var world = World.init(std.testing.allocator, std.testing.io);
    defer world.deinit();

    world.registerEvent(MyEvent);
    var ctx = Context{};
    try world.subscribe(MyEvent, &ctx, Context.onEvent);

    world.emit(MyEvent{ .val = 10 });
    world.emit(MyEvent{ .val = 20 });

    try std.testing.expectEqual(@as(u32, 30), ctx.sum);
}

test "bevy-style systems" {
    const P = struct { x: f32 };
    const V = struct { vx: f32 };
    const MyRes = struct { score: u32 };

    var world = World.init(std.testing.allocator, std.testing.io);
    defer world.deinit();

    _ = try world.spawn(.{ P{ .x = 0 }, V{ .vx = 1 } });
    world.insertResource(MyRes{ .score = 100 });

    const sys = struct {
        fn move(q: Query(.{ *P, V }), res: Res(MyRes)) !void {
            try std.testing.expectEqual(@as(u32, 100), res.value.score);
            var it = q.iter();
            while (it.next()) |row| {
                row.P.x += row.V.vx;
            }
        }
    }.move;

    var sched = Schedule.init(std.testing.allocator);
    defer sched.deinit();
    try sched.add(sys);

    try sched.run(&world, std.testing.io);

    var q = world.query(&.{P});
    const hit = q.next().?;
    try std.testing.expectEqual(@as(f32, 1.0), world.get(hit.entity, P).?.x);
}

test "command buffer systems" {
    const P = struct { x: f32 };
    var world = World.init(std.testing.allocator, std.testing.io);
    defer world.deinit();

    const sys = struct {
        fn spawnThings(cmds: Commands()) !void {
            try cmds.spawn(.{ P{ .x = 123 } });
            try cmds.spawn(.{ P{ .x = 456 } });
        }
    }.spawnThings;

    var sched = Schedule.init(std.testing.allocator);
    defer sched.deinit();
    try sched.add(sys);

    try sched.run(&world, std.testing.io);

    var q = world.query(&.{P});
    var count: usize = 0;
    while (q.next()) |hit| {
        count += 1;
        _ = hit;
    }
    try std.testing.expectEqual(@as(usize, 2), count);
}

test "perf spawn and query" {
    const P = struct { x: f32, y: f32 };
    const V = struct { vx: f32, vy: f32 };

    var world = World.init(std.testing.allocator, std.testing.io);
    defer world.deinit();

    const n: usize = 10_000;
    const t0 = std.Io.Clock.now(.awake, std.testing.io);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        _ = try world.spawn(.{
            P{ .x = @floatFromInt(i), .y = 0 },
            V{ .vx = 0, .vy = 0 },
        });
    }
    const spawn_ns = std.Io.Clock.now(.awake, std.testing.io).nanoseconds - t0.nanoseconds;

    const t1 = std.Io.Clock.now(.awake, std.testing.io);
    var q = world.query(&.{ P, V });
    var count: usize = 0;
    while (q.next()) |_| count += 1;
    const query_ns = std.Io.Clock.now(.awake, std.testing.io).nanoseconds - t1.nanoseconds;

    try std.testing.expectEqual(n, count);
    try std.testing.expect(spawn_ns < 5_000_000_000);
    try std.testing.expect(query_ns < 1_000_000_000);
}

test "event systems are called when events are emitted" {
    const Position = struct { x: f32, y: f32 };
    const CollisionEvent = struct { a: Entity, b: Entity };

    var world = World.init(std.testing.allocator, std.testing.io);
    defer world.deinit();

    const Counter = struct {
        var call_count: usize = 0;
    };
    Counter.call_count = 0;

    const handler = struct {
        fn handle(event: CollisionEvent, world_ptr: *World) void {
            _ = world_ptr;
            Counter.call_count += 1;
            _ = event;
        }
    }.handle;

    world.addEventSystem(CollisionEvent, handler);

    const e1 = try world.spawn(.{ Position{ .x = 0, .y = 0 } });
    const e2 = try world.spawn(.{ Position{ .x = 1, .y = 1 } });

    world.emit(CollisionEvent{ .a = e1, .b = e2 });
    world.tickEvents();

    try std.testing.expectEqual(@as(usize, 1), Counter.call_count);
}

test "event systems can use Query parameter" {
    const Position = struct { x: f32, y: f32 };
    const Velocity = struct { vx: f32, vy: f32 };
    const MoveEvent = struct { amount: f32 };

    var world = World.init(std.testing.allocator, std.testing.io);
    defer world.deinit();

    _ = try world.spawn(.{ Position{ .x = 0, .y = 0 }, Velocity{ .vx = 1, .vy = 0 } });
    _ = try world.spawn(.{ Position{ .x = 10, .y = 10 }, Velocity{ .vx = 0, .vy = 1 } });

    const handler = struct {
        fn handle(event: MoveEvent, query: Query(.{ *Position })) void {
            var it = query.iter();
            while (it.next()) |row| {
                row.Position.x += event.amount;
            }
        }
    }.handle;

    world.addEventSystem(MoveEvent, handler);

    world.emit(MoveEvent{ .amount = 5.0 });
    world.tickEvents();

    var q = world.query(&.{Position});
    while (q.next()) |hit| {
        const pos = world.get(hit.entity, Position).?;
        try std.testing.expect(pos.x >= 5.0);
    }
}

test "event systems can use Res parameter" {
    const Score = struct { value: u32 };
    const ScoreEvent = struct { points: u32 };

    var world = World.init(std.testing.allocator, std.testing.io);
    defer world.deinit();

    world.insertResource(Score{ .value = 0 });

    const handler = struct {
        fn handle(event: ScoreEvent, res: Res(Score)) void {
            _ = event;
            _ = res;
        }
    }.handle;

    world.addEventSystem(ScoreEvent, handler);

    world.emit(ScoreEvent{ .points = 10 });
    world.tickEvents();
}

