const std = @import("std");
const ecs = @import("ecs");
const comp = @import("components/root.zig");

fn setOrAddLayout(world: *ecs.World, entity: ecs.Entity, layout: comp.ComputedLayout) void {
    if (world.getMut(entity, comp.ComputedLayout)) |existing| {
        existing.* = layout;
    } else {
        world.addComponent(entity, comp.ComputedLayout, layout) catch {};
    }
}

fn layoutNode(
    world: *ecs.World,
    hierarchy: *ecs.Hierarchy,
    entity: ecs.Entity,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
) void {
    const node = world.get(entity, comp.UiNode) orelse return;

    const final_w = @max(width, node.min_width);
    const final_h = @max(height, node.min_height);

    setOrAddLayout(world, entity, .{
        .x = x,
        .y = y,
        .width = final_w,
        .height = final_h,
    });

    layoutChildren(world, hierarchy, entity, final_w, final_h);
}

fn layoutChildren(
    world: *ecs.World,
    hierarchy: *ecs.Hierarchy,
    parent: ecs.Entity,
    parent_w: f32,
    parent_h: f32,
) void {
    const node = world.get(parent, comp.UiNode) orelse return;
    const children = hierarchy.getChildren(parent) orelse return;

    var ui_count: usize = 0;
    for (children) |child| {
        if (world.get(child, comp.UiNode) != null) ui_count += 1;
    }
    if (ui_count == 0) return;

    // Collect UiNode children into a stack array (up to 64)
    var buffer: [64]ecs.Entity = undefined;
    const ui_children = buffer[0..@min(ui_count, buffer.len)];
    {
        var i: usize = 0;
        for (children) |child| {
            if (i >= ui_children.len) break;
            if (world.get(child, comp.UiNode) != null) {
                ui_children[i] = child;
                i += 1;
            }
        }
    }

    const pad = node.padding;
    const content_x = pad.left;
    const content_y = pad.top;
    const content_w = parent_w - pad.left - pad.right;
    const content_h = parent_h - pad.top - pad.bottom;

    const gap = node.gap;
    const child_count: f32 = @floatFromInt(ui_children.len);
    const total_gap = gap * @max(0, child_count - 1);

    switch (node.direction) {
        .column => {
            var fixed_total: f32 = 0;
            var flex_total: f32 = 0;

            for (ui_children) |child| {
                const cn = world.get(child, comp.UiNode).?;
                const ch = if (cn.height > 0) cn.height else 0;
                if (ch > 0) {
                    fixed_total += ch + cn.margin.top + cn.margin.bottom;
                } else {
                    flex_total += cn.flex_grow;
                }
            }

            const remaining = @max(0, content_h - fixed_total - total_gap);
            const flex_unit = if (flex_total > 0) remaining / flex_total else 0;

            var cursor_y: f32 = content_y;
            for (ui_children) |child| {
                const cn = world.get(child, comp.UiNode).?;
                const ml = cn.margin.left;
                const mr = cn.margin.right;
                const mt = cn.margin.top;
                const mb = cn.margin.bottom;

                cursor_y += mt;

                const ch: f32 = if (cn.height > 0) cn.height else flex_unit * cn.flex_grow;
                const avail_w = @max(0, content_w - ml - mr);
                const child_w = if (node.align_items == .stretch) avail_w else blk: {
                    break :blk if (cn.width > 0) @min(cn.width, avail_w) else avail_w;
                };
                const child_x = content_x + ml + switch (node.align_items) {
                    .start => 0,
                    .center => (content_w - ml - mr - child_w) / 2,
                    .end => content_w - mr - child_w,
                    .stretch => 0,
                };

                layoutNode(world, hierarchy, child, child_x, cursor_y, child_w, ch);
                cursor_y += ch + mb + gap;
            }
        },
        .row => {
            var fixed_total: f32 = 0;
            var flex_total: f32 = 0;

            for (ui_children) |child| {
                const cn = world.get(child, comp.UiNode).?;
                const cw = if (cn.width > 0) cn.width else 0;
                if (cw > 0) {
                    fixed_total += cw + cn.margin.left + cn.margin.right;
                } else {
                    flex_total += cn.flex_grow;
                }
            }

            const remaining = @max(0, content_w - fixed_total - total_gap);
            const flex_unit = if (flex_total > 0) remaining / flex_total else 0;

            var cursor_x: f32 = content_x;
            for (ui_children) |child| {
                const cn = world.get(child, comp.UiNode).?;
                const ml = cn.margin.left;
                const mr = cn.margin.right;
                const mt = cn.margin.top;
                const mb = cn.margin.bottom;

                cursor_x += ml;

                const cw: f32 = if (cn.width > 0) cn.width else flex_unit * cn.flex_grow;
                const avail_h = @max(0, content_h - mt - mb);
                const child_h = if (node.align_items == .stretch) avail_h else blk: {
                    break :blk if (cn.height > 0) @min(cn.height, avail_h) else avail_h;
                };
                const child_y = content_y + mt + switch (node.align_items) {
                    .start => 0,
                    .center => (content_h - mt - mb - child_h) / 2,
                    .end => content_h - mb - child_h,
                    .stretch => 0,
                };

                layoutNode(world, hierarchy, child, cursor_x, child_y, cw, child_h);
                cursor_x += cw + mr + gap;
            }
        },
    }
}

pub fn run(world: *ecs.World, screen_width: f32, screen_height: f32) void {
    const hierarchy = world.getMutResource(ecs.Hierarchy) orelse return;

    var roots: [128]ecs.Entity = undefined;
    var root_count: usize = 0;

    var q = world.query(&.{ comp.UiNode });
    while (q.next()) |hit| {
        if (root_count >= roots.len) break;
        if (world.get(hit.entity, comp.Parent) == null) {
            roots[root_count] = hit.entity;
            root_count += 1;
        }
    }

    for (roots[0..root_count]) |root| {
        layoutNode(world, hierarchy, root, 0, 0, screen_width, screen_height);
    }
}
