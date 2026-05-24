const std = @import("std");
const bgfx = @import("bgfx_util.zig").bgfx;
const parser = @import("vertex_parser.zig");
const pool = @import("pool");

const VertexStore = @This();

pub const Layout = bgfx.VertexLayout;

map: std.StringHashMap(Layout),

pub fn getLayout(self: *VertexStore, comptime T: type) *Layout {
    const name = @typeName(T);
    return self.map.get(name) orelse {
        const layout = parser.createLayout(T, .{}, bgfx.getRendererType());
        self.map.put(name, layout) orelse unreachable;
        return &layout;
    };
}

pub fn init(allocator: std.mem.Allocator) VertexStore {
    return .{
        .map = std.StringHashMap(bgfx.VertexLayout).init(allocator),
    };
}

pub fn deinit(self: *VertexStore) void {
    self.map.deinit();
}
