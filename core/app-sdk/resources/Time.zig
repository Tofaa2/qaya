const std = @import("std");
const Time = @This();

io: std.Io,
last: std.Io.Timestamp,
delta: f32,
elapsed: f32,

pub fn init(io: std.Io) Time {
    return .{
        .io = io,
        .last = std.Io.Timestamp.now(io, .awake),
        .delta = 0,
        .elapsed = 0,
    };
}

pub fn tick(self: *Time) void {
    const now = std.Io.Timestamp.now(self.io, .awake);
    const elapsed_ns = now.nanoseconds - self.last.nanoseconds;
    self.last = now;
    self.delta = @as(f32, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
    self.elapsed += self.delta;
}
