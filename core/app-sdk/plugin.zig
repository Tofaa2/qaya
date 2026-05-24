const App = @import("App.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const PluginVTable = struct {
    build_fn: *const fn (erased: *const anyopaque, app: *App) void,
    name_fn: *const fn (erased: *const anyopaque) []const u8,
    deinit_fn: *const fn (erased: *anyopaque, alloc: Allocator) void,
    storage: *anyopaque,

    pub fn build(self: *const PluginVTable, app: *App) void {
        self.build_fn(self.storage, app);
    }

    pub fn name(self: *const PluginVTable) []const u8 {
        return self.name_fn(self.storage);
    }

    pub fn deinit(self: *PluginVTable, alloc: Allocator) void {
        self.deinit_fn(self.storage, alloc);
    }
};

pub fn makePluginZeroes(comptime T: type, alloc: Allocator) !PluginVTable {
    return makePlugin(T, undefined, alloc);
}

/// Wrap any concrete plugin type into a heap-allocated PluginVTable.
pub fn makePlugin(comptime T: type, value: T, alloc: Allocator) !PluginVTable {
    if (!@hasDecl(T, "build")) {
        @compileError("Plugin type '" ++ @typeName(T) ++ "' must declare `pub fn build(self: @This(), app: *App) void`");
    }

    const ptr = try alloc.create(T);
    ptr.* = value;

    return PluginVTable{
        .storage = ptr,
        .build_fn = struct {
            fn f(erased: *const anyopaque, app: *App) void {
                const self: *const T = @ptrCast(@alignCast(erased));
                self.build(app);
            }
        }.f,
        .name_fn = struct {
            fn f(_: *const anyopaque) []const u8 {
                return @typeName(T);
            }
        }.f,
        .deinit_fn = struct {
            fn f(erased: *anyopaque, a: Allocator) void {
                const self: *T = @ptrCast(@alignCast(erased));
                a.destroy(self);
            }
        }.f,
    };
}
