const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

pub fn Asset(comptime T: type, comptime LoadInfo: type) type {
    return struct {
        const Self = @This();

        pub const Handle = struct {
            idx: usize,
        };

        allocator: Allocator,
        io: Io,
        data: std.ArrayList(T) = .empty,
        rw_lock: Io.RwLock = .init,

        pub fn load(self: *Self, info: LoadInfo) Handle {
            const i = @typeInfo(T);
            if (i != .@"struct") @compileError("T must be a struct");
            const data = self.allocator.create(T) catch @panic("out of memory");

            if (@hasDecl(T, "load")) {
                data.* = T.load(self.allocator, self.io, info);
            } else {
                @memset(data, 0);
            }
            const idx = self.data.items.len;
            self.data.append(data) catch @panic("out of memory");
            return .{ .idx = idx };
        }

        pub fn unload(self: *Self, handle: Handle) void {
            if (@hasDecl(T, "unload")) {
                T.unload(self.allocator, self.io, self.data.items[handle.idx]);
            }
            self.data.items[handle.idx] = undefined;
        }

        pub fn get(self: *Self, handle: Handle) T {
            return self.data.items[handle.idx];
        }

        pub fn getPtr(self: *Self, handle: Handle) *T {
            return &self.data.items[handle.idx];
        }

        pub fn init(allocator: Allocator, io: Io) Self {
            return .{
                .allocator = allocator,
                .io = io,
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.data.items) |*item| {
                if (@hasDecl(T, "unload")) {
                    T.unload(self.allocator, self.io, item.*);
                }
            }
            self.data.deinit(self.allocator);
        }
    };
}
