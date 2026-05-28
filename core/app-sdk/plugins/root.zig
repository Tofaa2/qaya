pub const Window = @import("window.zig").Plugin;
pub const Renderer = @import("renderer.zig").Plugin;
pub const Time = @import("time.zig").Plugin;
pub const Hierarchy = @import("hierarchy.zig").Plugin;

pub const Defaults: []const type = &.{ Time, Window, Renderer, Hierarchy };
