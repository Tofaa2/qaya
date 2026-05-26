const std = @import("std");
const ecs = @import("ecs");

/// Resource holding the current state and a pending transition.
/// Inserted by `addStatePlugin`.
pub fn State(comptime T: type) type {
    return struct {
        current: T,
        next: ?T = null,
    };
}

/// Event emitted to request a state transition.
/// The transition happens at the start of the next frame during `state_transition`.
pub fn NextState(comptime T: type) type {
    return struct {
        state: T,
    };
}

/// Returns a system function that processes NextState(T) events and
/// runs `on_exit_<old>` / `on_enter_<new>` scheduler stages.
/// Registered during `.state_transition` by `App.addStatePlugin`.
pub fn transitionSystem(comptime T: type) fn (*ecs.World) void {
    const S = struct {
        fn run(world: *ecs.World) void {
            const state_res = world.getMutResource(State(T)) orelse return;

            if (world.getResource(ecs.EventChannel(NextState(T)))) |chan| {
                const view = chan.read();
                defer view.release();
                for (view.current) |ev| state_res.next = ev.state;
                for (view.previous) |ev| state_res.next = ev.state;
            }

            const target = state_res.next orelse return;
            state_res.next = null;

            const old_state = state_res.current;

            {
                const exit_name = std.fmt.allocPrint(world.allocator, "on_exit_{s}", .{@tagName(old_state)}) catch return;
                defer world.allocator.free(exit_name);
                world.scheduler.run(exit_name, world, world.io) catch {};
            }

            state_res.current = target;

            {
                const enter_name = std.fmt.allocPrint(world.allocator, "on_enter_{s}", .{@tagName(target)}) catch return;
                defer world.allocator.free(enter_name);
                world.scheduler.run(enter_name, world, world.io) catch {};
            }
        }
    };
    return S.run;
}
