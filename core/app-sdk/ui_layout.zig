const std = @import("std");
const ecs = @import("ecs");
const comp = @import("components/root.zig");

fn setOrAddLayout(world: *ecs.World, entity: ecs.Entity, layout: comp.ui.ComputedLayout) void {
    if (world.getMut(entity, comp.ui.ComputedLayout)) |existing| {
        existing.* = layout;
    } else {
        world.addComponent(entity, comp.ui.ComputedLayout, layout) catch {};
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
    const node = world.get(entity, comp.ui.UiNode) orelse return;

    const final_w = @max(width, node.min_width);
    const final_h = @max(height, node.min_height);

    setOrAddLayout(world, entity, .{
        .x = x,
        .y = y,
        .width = final_w,
        .height = final_h,
    });

    layoutChildren(world, hierarchy, entity, x, y, final_w, final_h);
}

const ChildInfo = struct {
    entity: ecs.Entity,
    node: *const comp.ui.UiNode,
    pref_main: f32,
    min_main: f32,
    pref_cross: f32,
    is_fixed: bool,
    margin_main_start: f32,
    margin_main_end: f32,
    margin_cross_start: f32,
    margin_cross_end: f32,
};

fn layoutChildren(
    world: *ecs.World,
    hierarchy: *ecs.Hierarchy,
    parent: ecs.Entity,
    parent_x: f32,
    parent_y: f32,
    parent_w: f32,
    parent_h: f32,
) void {
    const node = world.get(parent, comp.ui.UiNode) orelse return;
    const children = hierarchy.getChildren(parent) orelse return;

    var ui_count: usize = 0;
    for (children) |child| {
        if (world.get(child, comp.ui.UiNode) != null) ui_count += 1;
    }
    if (ui_count == 0) return;

    var ebuf: [64]ecs.Entity = undefined;
    const ents = ebuf[0..@min(ui_count, ebuf.len)];
    {
        var i: usize = 0;
        for (children) |child| {
            if (i >= ents.len) break;
            if (world.get(child, comp.ui.UiNode) != null) {
                ents[i] = child;
                i += 1;
            }
        }
    }

    const pad = node.padding;
    const content_x = parent_x + pad.left;
    const content_y = parent_y + pad.top;
    const content_w = parent_w - pad.left - pad.right;
    const content_h = parent_h - pad.top - pad.bottom;
    const gap = node.gap;
    const is_row = node.direction == .row;
    const avail_main = if (is_row) content_w else content_h;
    const avail_cross = if (is_row) content_h else content_w;

    // Gather child info in main/cross terms
    var ibuf: [64]ChildInfo = undefined;
    const infos = ibuf[0..ents.len];
    for (ents, infos) |e, *info| {
        const cn = world.get(e, comp.ui.UiNode).?;
            info.* = .{
                .entity = e,
                .node = cn,
                .pref_main = if (is_row) cn.width else cn.height,
                .min_main = if (is_row) cn.min_width else cn.min_height,
                .pref_cross = if (is_row) cn.height else cn.width,
                .is_fixed = if (is_row) cn.width > 0 else cn.height > 0,
                .margin_main_start = if (is_row) cn.margin.left else cn.margin.top,
                .margin_main_end = if (is_row) cn.margin.right else cn.margin.bottom,
                .margin_cross_start = if (is_row) cn.margin.top else cn.margin.left,
                .margin_cross_end = if (is_row) cn.margin.bottom else cn.margin.right,
            };
    }

    // ── Line builder ──────────────────────────────────────────
    var lstart: [8]usize = .{0} ** 8;
    var llen: [8]usize = .{0} ** 8;
    var lcross: [8]f32 = .{0} ** 8;
    var lmain: [8]f32 = .{0} ** 8;
    var line_count: usize = 0;

    {
        var i: usize = 0;
        while (i < infos.len) {
            const line_begin = i;
            var cursor: f32 = 0;
            var fixed: f32 = 0;
            var flex: f32 = 0;
            var cross_max: f32 = 0;

            while (i < infos.len) {
                const ci = &infos[i];
                const ms = ci.margin_main_start;
                const me = ci.margin_main_end;
                const child_main = if (ci.is_fixed) ci.pref_main else 0;
                const total = child_main + ms + me;

                const with_gap = cursor + (if (i > line_begin) gap else 0) + total;
                if (node.wrap == .wrap and i > line_begin and with_gap > avail_main) break;

                cursor += (if (i > line_begin) gap else 0) + total;
                cross_max = @max(cross_max, ci.pref_cross + ci.margin_cross_start + ci.margin_cross_end);

                if (ci.is_fixed) {
                    fixed += child_main + ms + me;
                } else {
                    flex += ci.node.flex_grow;
                }
                i += 1;
            }

            const count = i - line_begin;
            const ngap = gap * @max(0, @as(f32, @floatFromInt(count)) - 1);
            const free_space = avail_main - fixed - ngap;

            if (free_space >= 0) {
                const flex_unit = if (flex > 0) free_space / flex else 0;
                for (infos[line_begin..i]) |*ci| {
                    if (!ci.is_fixed) ci.pref_main = flex_unit * ci.node.flex_grow;
                }
            } else {
                const deficit = -free_space;
                var shrink_total: f32 = 0;
                for (infos[line_begin..i]) |ci| {
                    if (!ci.is_fixed) shrink_total += ci.node.flex_shrink;
                }
                if (shrink_total > 0) {
                    for (infos[line_begin..i]) |*ci| {
                        if (!ci.is_fixed) {
                            const reduction = (ci.node.flex_shrink / shrink_total) * deficit;
                            ci.pref_main = @max(ci.min_main, ci.pref_main - reduction);
                        }
                    }
                } else {
                    for (infos[line_begin..i]) |*ci| {
                        if (!ci.is_fixed) ci.pref_main = ci.min_main;
                    }
                }
            }

            var line_main: f32 = 0;
            for (infos[line_begin..i]) |*ci| {
                line_main += ci.pref_main + ci.margin_main_start + ci.margin_main_end;
            }
            line_main += ngap;

            lstart[line_count] = line_begin;
            llen[line_count] = count;
            lcross[line_count] = cross_max;
            lmain[line_count] = line_main;
            line_count += 1;
        }
    }

    // ── Position lines ────────────────────────────────────────
    var cross_cursor: f32 = 0;
    for (0..line_count) |li| {
        const line_begin = lstart[li];
        const count = llen[li];
        const line_cross = lcross[li];
        const line_main_total = lmain[li];
        const slice = infos[line_begin..][0..count];

        const leftover = avail_main - line_main_total;
        const justify_offset: f32 = switch (node.justify_content) {
            .start => 0,
            .center => @max(0, leftover / 2),
            .end => @max(0, leftover),
            .space_between, .space_around => 0,
        };

        const extra_between: f32 = if (leftover > 0 and count > 1 and node.justify_content == .space_between)
            leftover / @as(f32, @floatFromInt(count - 1)) else 0;
        const extra_around: f32 = if (leftover > 0 and count > 0 and node.justify_content == .space_around)
            leftover / @as(f32, @floatFromInt(count)) else 0;

        var main_cursor = if (is_row) content_x else content_y;
        main_cursor += justify_offset;
        if (node.justify_content == .space_around) main_cursor += extra_around / 2;

        for (slice, 0..) |*ci, ci_idx| {
            main_cursor += ci.margin_main_start;

            const child_main = ci.pref_main;

            // Cross-axis sizing
            const avail_c = avail_cross - ci.margin_cross_start - ci.margin_cross_end;
            const child_cross = if (node.align_items == .stretch) blk: {
                if (node.wrap == .wrap) {
                    break :blk @max(0, line_cross - ci.margin_cross_start - ci.margin_cross_end);
                }
                break :blk avail_c;
            } else if (ci.pref_cross > 0)
                @min(ci.pref_cross, avail_c)
            else
                avail_c;

            // Cross-axis alignment within the line
            const cross_offset: f32 = switch (node.align_items) {
                .start => 0,
                .center => (line_cross - ci.margin_cross_start - ci.margin_cross_end - child_cross) / 2,
                .end => line_cross - ci.margin_cross_start - ci.margin_cross_end - child_cross,
                .stretch => 0,
            };

            const child_x = if (is_row) main_cursor else content_x + ci.margin_cross_start + cross_offset + cross_cursor;
            const child_y = if (is_row) content_y + ci.margin_cross_start + cross_offset + cross_cursor else main_cursor;
            const child_w = if (is_row) child_main else child_cross;
            const child_h = if (is_row) child_cross else child_main;

            layoutNode(world, hierarchy, ci.entity, child_x, child_y, child_w, child_h);

            main_cursor += child_main + ci.margin_main_end;
            if (ci_idx + 1 < count) {
                main_cursor += gap;
                if (node.justify_content == .space_between and leftover > 0) {
                    main_cursor += extra_between;
                } else if (node.justify_content == .space_around and leftover > 0) {
                    main_cursor += extra_around;
                }
            }
        }

        cross_cursor += line_cross + gap;
    }
}

pub fn run(world: *ecs.World, screen_width: f32, screen_height: f32) void {
    const hierarchy = world.getMutResource(ecs.Hierarchy) orelse {
        std.log.warn("ui_layout: no Hierarchy resource", .{});
        return;
    };

    var roots: [128]ecs.Entity = undefined;
    var root_count: usize = 0;

    var q = world.query(&.{ comp.ui.UiNode });
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
