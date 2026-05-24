const Window = @This();
const c = @import("c.zig").c;

const builtin = @import("builtin");
const std = @import("std");
const enums = @import("enums.zig");
const event = @import("event.zig");

handle: *c.RGFW_window = @ptrFromInt(1),
width: u32 = 0,
height: u32 = 0,
mouse_delta_x: f32 = 0.0,
mouse_delta_y: f32 = 0.0,
native_type: NativeType = .idk,
resized_last_frame: bool = false,

pub fn focus(self: *const Window) void {
    c.RGFW_window_focus(self.handle);
}

pub fn pollEvent(self: *Window) ?event.Event {
    var c_ev: c.RGFW_event = undefined;
    if (c.RGFW_window_checkEvent(self.handle, &c_ev) == 0) return null;

    const ev = event.fromRGFW(c_ev);

    // Internal housekeeping
    switch (ev) {
        .quit => {
            c.RGFW_window_setShouldClose(self.handle, @intFromBool(true));
        },

        .mouse_motion => |m| {
            self.mouse_delta_x += m.delta_x;
            self.mouse_delta_y += m.delta_y;
        },
        .window_resized => |s| {
            self.width = s[0];
            self.height = s[1];
            self.resized_last_frame = true;
        },
        else => {},
    }

    return ev;
}

pub const Error = error{
    RGFWInitFailed,
};

/// Assumes window is already allocated and initialized
pub fn init(self: *Window, title: [:0]const u8, width: u32, height: u32, env: *std.process.Environ.Map) Error!void {
    const handle = c.RGFW_createWindow(title.ptr, 0, 0, @intCast(width), @intCast(height), 0);
    if (handle == null) {
        return Error.RGFWInitFailed;
    }
    self.* = .{
        .handle = handle.?,
        .width = width,
        .height = height,
        .native_type = NativeType.fromEnv(env),
    };

    c.RGFW_window_setUserPtr(handle, self);
    c.RGFW_window_center(handle);
}

pub fn deinit(self: *Window) void {
    c.RGFW_window_close(self.handle);
}

pub fn getSize(self: *Window) [2]i32 {
    var width: i32 = undefined;
    var height: i32 = undefined;
    _ = c.RGFW_window_getSize(self.handle, &width, &height);
    return .{ width, height };
}

pub fn setExitKey(self: *Window, key: enums.Key) void {
    c.RGFW_window_setExitKey(self.handle, @intFromEnum(key));
}

pub fn isKeyReleased(self: *Window, key: enums.Key) bool {
    return c.RGFW_window_isKeyReleased(self.handle, @intFromEnum(key)) == 1;
}

pub fn isKeyDown(self: *Window, key: enums.Key) bool {
    return c.RGFW_window_isKeyDown(self.handle, @intFromEnum(key)) == 1;
}

pub fn isKeyPressed(self: *Window, key: enums.Key) bool {
    const res = c.RGFW_window_isKeyPressed(self.handle, @intFromEnum(key));
    return res == 1;
}

pub fn getWindowFromNative(handle: ?*c.RGFW_window) ?*Window {
    const native = c.RGFW_window_getUserPtr(handle);
    return @as(?*Window, @ptrCast(@alignCast(native)));
}

pub fn isMouseInside(self: *Window) bool {
    return c.RGFW_window_isMouseInside(self.handle) == 1;
}

pub fn didMouseEnter(self: *Window) bool {
    return c.RGFW_window_didMouseEnter(self.handle) == 1;
}

pub fn didMouseLeave(self: *Window) bool {
    return c.RGFW_window_didMouseLeave(self.handle) == 1;
}

pub fn isMousePressed(self: *Window, button: enums.MouseButton) bool {
    return c.RGFW_window_isMousePressed(self.handle, @intFromEnum(button)) == 1;
}

pub fn isMouseDown(self: *Window, button: enums.MouseButton) bool {
    return c.RGFW_window_isMouseDown(self.handle, @intFromEnum(button)) == 1;
}

pub fn isMouseReleased(self: *Window, button: enums.MouseButton) bool {
    return c.RGFW_window_isMouseReleased(self.handle, @intFromEnum(button)) == 1;
}

pub fn setFullscreen(self: *Window, fullscreen: bool) void {
    c.RGFW_window_setFullscreen(self.handle, @intFromBool(fullscreen));
}

pub fn setName(self: *Window, title: []const u8) void {
    c.RGFW_window_setName(self.handle, @ptrCast(title.ptr));
}

pub fn resize(self: *Window, nw: u32, nh: u32) void {
    c.RGFW_window_resize(self.handle, @intCast(nw), @intCast(nh));
}

pub fn setIcon(self: *Window, data: [*c]const u8, width: u32, height: u32, format: enums.Format) void {
    _ = c.RGFW_window_setIcon(self.handle, data, width, height, format);
}

pub fn getMouse(self: *Window) [2]i32 {
    var x: i32 = undefined;
    var y: i32 = undefined;
    _ = c.RGFW_window_getMouse(self.handle, &x, &y);
    return .{ x, y };
}

pub fn setFlagsRaw(self: *Window, flags: u32) void {
    c.RGFW_window_setFlags(self.handle, flags);
}

pub fn setFlags(self: *Window, flags: []const enums.WindowFlags) void {
    var result: u32 = 0;
    for (flags) |flag| {
        result |= @intFromEnum(flag);
    }
    c.RGFW_window_setFlags(self.handle, result);
}

pub fn getFlags(self: *Window) u32 {
    return c.RGFW_window_getFlags(self.handle);
}

pub fn shouldClose(self: *Window) bool {
    return c.RGFW_window_shouldClose(self.handle) == c.RGFW_TRUE;
}

pub fn getMouseCaptured(self: *Window) bool {
    return (self.getFlags() & @intFromEnum(enums.WindowFlags.capture_mouse)) != 0;
}

pub fn setMouseCaptured(self: *Window, captured: bool) void {
    const current = self.getFlags();
    const flags = @intFromEnum(enums.WindowFlags.capture_mouse) |
        @intFromEnum(enums.WindowFlags.hide_mouse) |
        @intFromEnum(enums.WindowFlags.raw_mouse);
    if (captured) {
        c.RGFW_window_setFlags(self.handle, current | flags);
    } else {
        c.RGFW_window_setFlags(self.handle, current & ~flags);
    }
}

pub fn getMouseDelta(self: *Window) [2]f32 {
    return .{ self.mouse_delta_x, self.mouse_delta_y };
}

pub fn resetMouseDelta(self: *Window) void {
    self.mouse_delta_x = 0.0;
    self.mouse_delta_y = 0.0;
}

pub fn getNativePtr(self: *Window) ?*anyopaque {
    return switch (self.native_type) {
        .win32 => c.RGFW_window_getHWND(self.handle),
        .macos => c.RGFW_window_getWindow_OSX(self.handle),
        .wayland => c.RGFW_window_getWindow_Wayland(self.handle),
        .x11 => @ptrFromInt(c.RGFW_window_getWindow_X11(self.handle)),
        .idk => @panic("Your os is not supported by the custom Window struct"),
    };
}

pub fn getNativeNdt(self: *Window) ?*anyopaque {
    return switch (self.native_type) {
        .win32 => c.RGFW_window_getHDC(self.handle),
        .macos => null,
        .x11 => c.RGFW_getDisplay_X11(),
        .wayland => c.RGFW_getDisplay_Wayland(),
        .idk => @panic("Idk  what your window manager is bruh"),
    };
}

pub const NativeType = enum {
    win32,
    x11,
    macos,
    wayland,
    idk,

    pub fn fromEnv(map: *std.process.Environ.Map) NativeType {
        return switch (builtin.os.tag) {
            .macos => .macos,
            .windows => .win32,
            .linux => {
                if (map.contains("DISPLAY") or map.contains("XDG_SESSION_TYPE")) {
                    return .x11;
                } else if (map.contains("WAYLAND_DISPLAY")) {
                    return .wayland;
                } else {
                    return .idk;
                }
            },
            else => .idk,
        };
    }
};
