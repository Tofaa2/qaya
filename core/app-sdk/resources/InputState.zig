const std = @import("std");
const enums = @import("window").enums;
const Event = @import("window").event.Event;
const InputState = @This();
const KeySet = std.StaticBitSet(256);
const MouseSet = std.StaticBitSet(@typeInfo(enums.MouseButton).@"enum".fields.len);

fn keyBit(key: enums.Key) usize {
    return @intFromEnum(key);
}

fn mouseBit(button: enums.MouseButton) usize {
    return @intFromEnum(button);
}

keys_pressed: KeySet = KeySet.initEmpty(),
keys_held: KeySet = KeySet.initEmpty(),
keys_released: KeySet = KeySet.initEmpty(),

mouse_buttons_pressed: MouseSet = MouseSet.initEmpty(),
mouse_buttons_held: MouseSet = MouseSet.initEmpty(),
mouse_buttons_released: MouseSet = MouseSet.initEmpty(),

left_just_pressed: bool = false,

mouse_x: i32 = 0,
mouse_y: i32 = 0,
mouse_delta_x: f32 = 0,
mouse_delta_y: f32 = 0,
scroll_x: f32 = 0,
scroll_y: f32 = 0,
text_input: [32]u8 = [_]u8{0} ** 32,
text_input_len: usize = 0,

pub fn isJustPressed(self: *const InputState, key: enums.Key) bool {
    return self.keys_pressed.isSet(keyBit(key));
}

pub fn isDown(self: *const InputState, key: enums.Key) bool {
    return self.keys_held.isSet(keyBit(key));
}

pub fn isJustReleased(self: *const InputState, key: enums.Key) bool {
    return self.keys_released.isSet(keyBit(key));
}

pub fn isMouseJustPressed(self: *const InputState, button: enums.MouseButton) bool {
    if (button == .left) return self.left_just_pressed;
    return self.mouse_buttons_pressed.isSet(mouseBit(button));
}

pub fn isMouseDown(self: *const InputState, button: enums.MouseButton) bool {
    return self.mouse_buttons_held.isSet(mouseBit(button));
}

pub fn isMouseJustReleased(self: *const InputState, button: enums.MouseButton) bool {
    return self.mouse_buttons_released.isSet(mouseBit(button));
}

pub fn getMouseDelta(self: *const InputState) [2]f32 {
    return .{ self.mouse_delta_x, self.mouse_delta_y };
}

pub fn getMousePos(self: *const InputState) [2]i32 {
    return .{ self.mouse_x, self.mouse_y };
}

pub fn getScrollDelta(self: *const InputState) [2]f32 {
    return .{ self.scroll_x, self.scroll_y };
}

pub fn handleEvent(self: *InputState, event: Event) void {
    switch (event) {
        .key_pressed => |ev| {
            self.keys_pressed.set(keyBit(ev.key));
            self.keys_held.set(keyBit(ev.key));
            self.keys_released.unset(keyBit(ev.key));
        },
        .key_released => |ev| {
            self.keys_held.unset(keyBit(ev.key));
            self.keys_released.set(keyBit(ev.key));
            self.keys_pressed.unset(keyBit(ev.key));
        },
        .mouse_button_pressed => |ev| {
            self.mouse_buttons_pressed.set(mouseBit(ev.button));
            self.mouse_buttons_held.set(mouseBit(ev.button));
            self.mouse_buttons_released.unset(mouseBit(ev.button));
            self.mouse_x = ev.x;
            self.mouse_y = ev.y;
            if (ev.button == .left) {
                self.left_just_pressed = true;
            }
        },
        .mouse_button_released => |ev| {
            self.mouse_buttons_held.unset(mouseBit(ev.button));
            self.mouse_buttons_released.set(mouseBit(ev.button));
            self.mouse_x = ev.x;
            self.mouse_y = ev.y;
        },
        .mouse_motion => |ev| {
            self.mouse_x = ev.x;
            self.mouse_y = ev.y;
            self.mouse_delta_x += ev.delta_x;
            self.mouse_delta_y += ev.delta_y;
        },
        .mouse_scroll => |ev| {
            self.scroll_x += ev.x;
            self.scroll_y += ev.y;
        },
        .key_char => |ch| {
            if (self.text_input_len < self.text_input.len) {
                const len = std.unicode.utf8Encode(@as(u21, @truncate(ch)), self.text_input[self.text_input_len..]) catch 0;
                self.text_input_len += len;
            }
        },
        else => {},
    }
}

pub fn frameEnd(self: *InputState) void {
    self.keys_pressed = KeySet.initEmpty();
    self.keys_released = KeySet.initEmpty();
    self.mouse_buttons_pressed = MouseSet.initEmpty();
    self.mouse_buttons_released = MouseSet.initEmpty();
    self.mouse_delta_x = 0;
    self.mouse_delta_y = 0;
    self.scroll_x = 0;
    self.scroll_y = 0;
    self.left_just_pressed = false;
    self.text_input = [_]u8{0} ** 32;
    self.text_input_len = 0;
}
