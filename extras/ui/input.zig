const ctx_mod = @import("context.zig");
const enums = @import("window").enums;
const app_sdk = @import("app-sdk");
const ecs = app_sdk.ecs;
const res = app_sdk.resources;

pub fn system(
    ctx_res: ecs.ResMut(ctx_mod.Context),
    input_res: ecs.Res(res.InputState),
) void {
    const ctx = ctx_res.value;
    const input = input_res.value;

    const pos = input.getMousePos();
    ctx.inputMouseMove(pos[0], pos[1]);

    if (input.isMouseJustPressed(.left)) ctx.inputMouseDown(pos[0], pos[1], ctx_mod.MouseButtons{ .left = true });
    if (input.isMouseJustReleased(.left)) ctx.inputMouseUp(pos[0], pos[1], ctx_mod.MouseButtons{ .left = true });
    if (input.isMouseJustPressed(.right)) ctx.inputMouseDown(pos[0], pos[1], ctx_mod.MouseButtons{ .right = true });
    if (input.isMouseJustReleased(.right)) ctx.inputMouseUp(pos[0], pos[1], ctx_mod.MouseButtons{ .right = true });
    if (input.isMouseJustPressed(.middle)) ctx.inputMouseDown(pos[0], pos[1], ctx_mod.MouseButtons{ .middle = true });
    if (input.isMouseJustReleased(.middle)) ctx.inputMouseUp(pos[0], pos[1], ctx_mod.MouseButtons{ .middle = true });

    const scroll = input.getScrollDelta();
    if (scroll[0] != 0 or scroll[1] != 0) {
        ctx.inputScroll(@intFromFloat(scroll[0]), @intFromFloat(scroll[1]));
    }

    if (input.isDown(.shiftL) or input.isDown(.shiftR)) {
        ctx.inputKeyDown(ctx_mod.Keys{ .shift = true });
    } else {
        ctx.inputKeyUp(ctx_mod.Keys{ .shift = true });
    }
    if (input.isDown(.controlL) or input.isDown(.controlR)) {
        ctx.inputKeyDown(ctx_mod.Keys{ .ctrl = true });
    } else {
        ctx.inputKeyUp(ctx_mod.Keys{ .ctrl = true });
    }
    if (input.isDown(.altL) or input.isDown(.altR)) {
        ctx.inputKeyDown(ctx_mod.Keys{ .alt = true });
    } else {
        ctx.inputKeyUp(ctx_mod.Keys{ .alt = true });
    }
    if (input.isJustPressed(.backSpace)) ctx.inputKeyDown(ctx_mod.Keys{ .backspace = true });
    if (input.isJustReleased(.backSpace)) ctx.inputKeyUp(ctx_mod.Keys{ .backspace = true });
    if (input.isJustPressed(.@"return") or input.isJustPressed(.kpReturn)) ctx.inputKeyDown(ctx_mod.Keys{ .enter = true });
    if (input.isJustReleased(.@"return") or input.isJustReleased(.kpReturn)) ctx.inputKeyUp(ctx_mod.Keys{ .enter = true });

    if (input.text_input_len > 0) {
        ctx.inputText(@ptrCast(&input.text_input));
    }
}
