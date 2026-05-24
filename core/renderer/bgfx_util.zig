const std = @import("std");
const zbgfx = @import("bgfx");
const math = @import("math");
pub const bgfx = zbgfx.bgfx;

pub var bgfx_clbs = zbgfx.callbacks.CCallbackInterfaceT{
    .vtable = &zbgfx.callbacks.DefaultZigCallbackVTable.toVtbl(),
};

pub inline fn isValid(handle: anytype) bool {
    return handle.idx < std.math.maxInt(u16);
}

pub fn isValidInt(handle: anytype) bool {
    return handle < std.math.maxInt(u16);
}
