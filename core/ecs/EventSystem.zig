const std = @import("std");
const World = @import("world.zig").World;
const system = @import("system.zig");
const registry = @import("registry.zig");

/// An event handler registered as an ECS system.
/// Handlers are invoked once per event during tickEvents().
pub fn EventSystem(comptime E: type, comptime handler: anytype) type {
    const HandlerInfo = @typeInfo(@TypeOf(handler));
    if (HandlerInfo != .@"fn") @compileError("Event handler must be a function");

    const Args = std.meta.ArgsTuple(@TypeOf(handler));
    const ReturnsError = if (HandlerInfo.@"fn".return_type) |ret|
        @typeInfo(ret) == .error_union
    else false;

    return struct {
        pub fn run(world: *World, event: E) void {
            var args: Args = undefined;

            inline for (std.meta.fields(Args), 0..) |field, i| {
                const T = field.type;
                if (T == E) {
                    args[i] = event;
                } else if (T == *World) {
                    args[i] = world;
                } else if (@hasDecl(T, "qaya_system_param")) {
                    if (@hasField(T, "last_run_tick")) {
                        args[i] = T.init(world, 0);
                    } else {
                        args[i] = T.init(world);
                    }
                } else {
                    @compileError("Unsupported event handler parameter: " ++ @typeName(T));
                }
            }

            defer {
                inline for (std.meta.fields(Args), 0..) |field, i| {
                    const T = field.type;
                    if (T != E and T != *World and @hasDecl(T, "deinit")) {
                        args[i].deinit();
                    }
                }
            }

            if (ReturnsError) {
                @call(.auto, handler, args) catch |err| {
                    std.debug.panic("event handler failed: {s}", .{@errorName(err)});
                };
            } else {
                @call(.auto, handler, args);
            }
        }

        pub fn masks() [2]registry.Mask {
            var read: registry.Mask = 0;
            var write: registry.Mask = 0;
            inline for (HandlerInfo.@"fn".params) |p| {
                const T = p.type orelse continue;
                if (T == E) continue;
                if (T == *World) continue;
                if (@hasDecl(T, "qaya_system_param")) {
                    const m = T.masks();
                    read |= m[0];
                    write |= m[1];
                }
            }
            return .{ read, write };
        }
    };
}

/// Type-erased event handler entry
const HandlerEntry = struct {
    run_batch: *const fn (world: *World, events_ptr: [*]const u8, count: usize) void,
    read_mask: registry.Mask,
    write_mask: registry.Mask,
    type_name: []const u8,
};

/// Registry of event systems. Each event type has a list of handlers.
pub const EventSystemRegistry = struct {
    const Self = @This();

    const TypeEntry = struct {
        handlers: std.ArrayListUnmanaged(HandlerEntry),
        type_name: []const u8,
    };

    allocator: std.mem.Allocator,
    type_entries: std.ArrayListUnmanaged(TypeEntry),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .type_entries = .empty,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.type_entries.items) |*te| {
            te.handlers.deinit(self.allocator);
        }
        self.type_entries.deinit(self.allocator);
    }

    pub fn add(self: *Self, comptime E: type, comptime handler: anytype) void {
        const Sys = EventSystem(E, handler);
        const m = Sys.masks();

        const entry: HandlerEntry = .{
            .run_batch = struct {
                fn wrapper(world: *World, events_ptr: [*]const u8, count: usize) void {
                    const events: []const E = @as([*]const E, @ptrCast(@alignCast(events_ptr)))[0..count];
                    for (events) |event| {
                        Sys.run(world, event);
                    }
                }
            }.wrapper,
            .read_mask = m[0],
            .write_mask = m[1],
            .type_name = @typeName(E),
        };

        const type_name = comptime @typeName(E);

        for (self.type_entries.items) |*te| {
            if (std.mem.eql(u8, te.type_name, type_name)) {
                te.handlers.append(self.allocator, entry) catch @panic("OOM");
                return;
            }
        }

        var handlers: std.ArrayListUnmanaged(HandlerEntry) = .empty;
        handlers.append(self.allocator, entry) catch @panic("OOM");
        self.type_entries.append(self.allocator, .{
            .handlers = handlers,
            .type_name = type_name,
        }) catch @panic("OOM");
    }

    pub fn dispatch(self: *const Self, world: *World, comptime E: type, events: []const E) void {
        const type_name = comptime @typeName(E);

        for (self.type_entries.items) |*te| {
            if (std.mem.eql(u8, te.type_name, type_name)) {
                for (te.handlers.items) |*handler| {
                    handler.run_batch(world, @ptrCast(events.ptr), events.len);
                }
                return;
            }
        }
    }
};
