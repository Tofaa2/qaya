const std = @import("std");
const bgfx = @import("bgfx").bgfx;
const math = @import("math");
const View = @This();

pub const Id = enum(u8) {
    @"3d" = 0,
    @"2d" = 1,
    skybox = 2,
    misc = 3,
};

id: Id,
clear_flags: u16 = bgfx.ClearFlags_Color | bgfx.ClearFlags_Depth,
/// Set to true for views that overlay atop other views (e.g. UI) so they don't clear the color buffer.
transparent: bool = false,
clear_color: math.Color = .white,
clear_depth: f32 = 1.0,
viewport: math.Rect(u16) = .zero(),
name: ?[]const u8 = null,
camera: math.Camera = .fps(.zero(), .init(1.0, 0.0, 0.0), 16.0 / 9.0),

/// TODO: implement
pub const ClearFlags = enum(u16) {
    color = bgfx.ClearFlags_Color,
    depth = bgfx.ClearFlags_Depth,
};

pub fn refresh(self: *const View) void {
    const id = @intFromEnum(self.id);

    bgfx.touch(id);
    const clear_flags = if (self.transparent)
        self.clear_flags & ~@as(u16, @intCast(bgfx.ClearFlags_Color))
    else
        self.clear_flags;
    bgfx.setViewClear(id, clear_flags, self.clear_color.toRGBA(), self.clear_depth, 0);
    if (self.name) |name| {
        bgfx.setViewName(id, @ptrCast(name.ptr), @intCast(name.len));
    }
    bgfx.setViewRect(id, self.viewport.x, self.viewport.y, self.viewport.width, self.viewport.height);
    bgfx.setViewTransform(id, &self.camera.viewMatrix().m, &self.camera.projMatrix().m);
}

pub fn reset(self: *View) void {
    self.clear_flags = bgfx.ClearFlags_Color | bgfx.ClearFlags_Depth;
    self.clear_color = .white;
    self.clear_depth = 1.0;
    self.camera = .fps(.zero(), .init(1.0, 0.0, 0.0), 16.0 / 9.0);
    self.name = null;
    self.viewport = .zero();

    bgfx.resetView(@intFromEnum(self.id));
    self.refresh();
}
