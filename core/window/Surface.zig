const std = @import("std");
const c = @import("c.zig").c;
const Window = @import("Window.zig");
const Surface = @This();
const Format = @import("enums.zig").Format;

handle: *c.RGFW_surface,

pub fn init(
    data: []u8,
    width: u32,
    height: u32,
    format: Format,
) !Surface {
    
    const s = c.RGFW_createSurface(
        data.ptr,
        @intCast(width),
        @intCast(height),
        @intFromEnum(format),
        );
    if (s == null) {
        return error.SurfaceCreationFailed;
    }
    return .{
        .handle = s.?,
    };
}

pub fn blit(self: *Surface, window: *Window) void {
    c.RGFW_window_blitSurface(window.handle, self.handle);
}

pub fn deinit(self: *const Surface) void {
    c.RGFW_surface_free(self.handle);
}

