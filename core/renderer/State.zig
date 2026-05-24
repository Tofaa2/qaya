const std = @import("std");
const bgfx = @import("bgfx_util.zig").bgfx;
const View = @import("View.zig");
const State = @This();
const math = @import("math");

allocator: std.mem.Allocator,
views: std.EnumMap(View.Id, View),
active_views: std.EnumSet(View.Id) = .{},

pub fn getView(self: *State, id: View.Id) *View {
    if (self.views.getPtr(id)) |ptr| {
        return ptr;
    }
    self.views.put(id, View{ .id = id });
    return self.views.getPtr(id).?;
}

pub fn refreshViews(self: *State) void {
    var it = self.views.iterator();
    while (it.next()) |entry| {
        entry.value.refresh();
    }
}

pub fn enableView(self: *State, id: View.Id) void {
    self.active_views.insert(id);
}

pub fn refreshActiveViews(self: *State) void {
    var it = self.active_views.iterator();
    while (it.next()) |id| {
        self.getView(id).refresh();
    }
}

pub fn clearActiveViews(self: *State) void {
    self.active_views = .{};
}

pub fn refreshViewports(self: *State, viewport: math.Rect(u16)) void {
    inline for (std.meta.tags(View.Id)) |id| {
        const view = self.getView(id);
        view.viewport = viewport;
        bgfx.setViewRect(@intFromEnum(view.id), viewport.x, viewport.y, viewport.width, viewport.height);
    }
}

pub fn init(
    allocator: std.mem.Allocator,
) State {
    return .{
        .allocator = allocator,
        .views = std.EnumMap(View.Id, View).init(.{
            .@"3d" = View{ .id = .@"3d" },
            .@"2d" = View{ .id = .@"2d", .transparent = true },
        }),
    };
}

pub fn deinit(_: *State) void {}
