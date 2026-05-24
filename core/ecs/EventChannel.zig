/// Double-buffered, thread-safe typed event channel.
///
/// Each channel holds two ring buffers: one for the current frame's events
/// and one for the previous frame's events. Calling `tick()` once per frame
/// rotates the buffers so readers always see a stable, complete snapshot of
/// the last frame while new events accumulate for the next one.
///
/// Usage pattern:
///   1. Systems call `emit()` (or `World.emit()`) to enqueue events.
///   2. Systems call `read()` to get a shared-locked View.
///      - `view.current`  — events sent since the last tick (this frame).
///      - `view.previous` — events sent the frame before (last tick).
///   3. Call `view.release()` when done (e.g. with `defer`).
///   4. At the end of each frame call `tick()` to rotate buffers.
const std = @import("std");

pub fn EventChannel(comptime E: type) type {
    return struct {
        const Self = @This();

        buffers: [2]std.ArrayListUnmanaged(E),
        /// Index of the buffer currently being written to.
        write_idx: u1,
        allocator: std.mem.Allocator,
        io: std.Io,
        rwl: std.Io.RwLock,
        listeners: std.ArrayListUnmanaged(Listener) = .empty,

        pub const Listener = struct {
            ctx: ?*anyopaque,
            callback: *const fn (ctx: ?*anyopaque, event: E) void,
        };

        pub fn init(allocator: std.mem.Allocator, io: std.Io) Self {
            return .{
                .buffers = .{ .empty, .empty },
                .write_idx = 0,
                .allocator = allocator,
                .io = io,
                .rwl = .init,
            };
        }

        pub fn deinit(self: *Self) void {
            self.buffers[0].deinit(self.allocator);
            self.buffers[1].deinit(self.allocator);
            self.listeners.deinit(self.allocator);
        }

        /// Append an event to the current frame's buffer and notify listeners.
        /// Thread-safe. Note: listeners are called while holding the channel lock.
        pub fn send(self: *Self, event: E) !void {
            self.rwl.lockUncancelable(self.io);
            defer self.rwl.unlock(self.io);

            try self.buffers[self.write_idx].append(self.allocator, event);

            for (self.listeners.items) |l| {
                l.callback(l.ctx, event);
            }
        }

        /// Register a callback to be invoked immediately when an event is sent.
        /// Thread-safe.
        pub fn subscribe(self: *Self, ctx: ?*anyopaque, callback: *const fn (ctx: ?*anyopaque, event: E) void) !void {
            self.rwl.lockUncancelable(self.io);
            defer self.rwl.unlock(self.io);
            try self.listeners.append(self.allocator, .{ .ctx = ctx, .callback = callback });
        }

        /// Rotate buffers. Must be called once per frame (e.g. via `World.tickEvents()`).
        /// The old write buffer becomes the readable "previous" snapshot;
        /// the stale previous buffer is cleared and becomes the new write target.
        /// Thread-safe.
        pub fn tick(self: *Self) void {
            self.rwl.lockUncancelable(self.io);
            defer self.rwl.unlock(self.io);
            // Clear the buffer that is about to become the write target.
            const next_write: u1 = self.write_idx ^ 1;
            self.buffers[next_write].clearRetainingCapacity();
            self.write_idx = next_write;
        }

        /// A shared-locked, read-only view of both event buffers.
        ///
        /// The underlying shared lock is held for the lifetime of this value.
        /// You **must** call `release()` when done — typically with `defer`.
        ///
        /// Example:
        ///   const view = channel.read();
        ///   defer view.release();
        ///   for (view.current) |ev| { ... }
        pub const View = struct {
            /// Events sent since the last `tick()` call (this frame).
            current: []const E,
            /// Events sent during the frame before the last `tick()` call.
            previous: []const E,
            _rwl: *std.Io.RwLock,
            _io: std.Io,

            /// Release the shared read lock. Must be called exactly once.
            pub fn release(self: View) void {
                self._rwl.unlockShared(self._io);
            }
        };

        /// Acquire a shared read lock and return a `View` of both buffers.
        /// The caller **must** call `view.release()` when done.
        /// Thread-safe with concurrent `send()` and other `read()` calls;
        /// do NOT call while `tick()` may be running concurrently.
        pub fn read(self: *Self) View {
            self.rwl.lockSharedUncancelable(self.io);
            const wi = self.write_idx;
            return .{
                .current = self.buffers[wi].items,
                .previous = self.buffers[wi ^ 1].items,
                ._rwl = &self.rwl,
                ._io = self.io,
            };
        }
    };
}
