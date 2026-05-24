const ecs = @import("ecs");
const renderer = @import("renderer");

/// ECS system parameter that provides a unique bgfx Encoder per invocation.
/// Systems that submit draw calls take this parameter to stay thread-safe.
/// Destroyed when the system finishes — no manual cleanup needed.
pub fn RenderEncoder() type {
    return struct {
        pub const qaya_system_param = true;

        value: renderer.Encoder,

        pub fn init(_: *ecs.World) @This() {
            return .{ .value = renderer.Encoder.init() };
        }

        pub fn deinit(self: *@This()) void {
            self.value.deinit();
        }

        pub fn masks() [2]u64 {
            return .{ 0, 0 };
        }
    };
}
