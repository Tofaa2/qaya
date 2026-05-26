const App = @import("../App.zig");
const ecs = @import("ecs");
const math = @import("math");
const comp = @import("../components/root.zig");
const std = @import("std");

const log = std.log.scoped(.hierarchy);

pub const Plugin = struct {
    pub const api = struct {};

    pub fn build(_: *const Plugin, app: *App) void {
        app.world.registerComponent(comp.Parent);
        app.world.registerComponent(comp.GlobalTransform);

        app.world.insertResource(ecs.Hierarchy.init(app.world.allocator));
        app.world.insertResource(ecs.ComponentHooks.init(app.world.allocator));

        app.world.scheduler.add(.init, initHierarchy) catch unreachable;
        app.world.scheduler.add(.post_update, propagateTransforms) catch unreachable;
        app.world.scheduler.add(.post_update, cleanupOrphans) catch unreachable;

        log.info("Hierarchy plugin initialized", .{});
    }
};

fn initHierarchy(world: *ecs.World) void {
    const hooks = world.getMutResource(ecs.ComponentHooks).?;
    hooks.onAdd(comp.Parent, onParentAdded) catch unreachable;
    hooks.onRemove(comp.Parent, onParentRemoved) catch unreachable;
}

fn onParentAdded(world: *ecs.World, entity: ecs.Entity) void {
    const parent = (world.get(entity, comp.Parent) orelse return).entity;
    if (!world.isAlive(parent)) return;
    const hierarchy = world.getMutResource(ecs.Hierarchy) orelse return;
    hierarchy.addChild(parent, entity) catch {};
}

fn onParentRemoved(world: *ecs.World, entity: ecs.Entity) void {
    _ = world;
    _ = entity;
}

/// Removes children whose parent entity no longer exists.
fn cleanupOrphans(world: *ecs.World) void {
    var q = world.query(&.{ comp.Parent });
    while (q.next()) |hit| {
        const parent_entity = (world.get(hit.entity, comp.Parent) orelse continue).entity;
        if (!world.isAlive(parent_entity)) {
            // Parent is dead; remove Parent so the child becomes a root entity.
            // Despawning the child would be more aggressive — choose based on intent.
            world.removeComponent(hit.entity, comp.Parent) catch {};
        }
    }
}

/// Computes GlobalTransform for every entity with Transform.
/// Entities without a Parent get GlobalTransform = Transform.toMatrixMat4().
/// Entities with a Parent get GlobalTransform = parent.GlobalTransform * Transform.toMatrixMat4().
/// Runs every frame in post_update. Children inherit their parent's transform
/// with a one-frame delay (the parent must be processed first in the same pass).
fn propagateTransforms(world: *ecs.World) void {
    var q = world.query(&.{ comp.Transform, comp.GlobalTransform });
    while (q.next()) |hit| {
        const entity = hit.entity;
        const transform = world.get(entity, comp.Transform).?;
        const global = world.getMut(entity, comp.GlobalTransform).?;

        if (world.get(entity, comp.Parent)) |parent| {
            if (world.isAlive(parent.entity)) {
                if (world.get(parent.entity, comp.GlobalTransform)) |pg| {
                    global.value = math.Mat4.mul(pg.value, transform.toMatrixMat4());
                }
            }
        } else {
            global.value = transform.toMatrixMat4();
        }
    }
}
