const RenderDevice = @This();
const std = @import("std");
const bgfx = @import("bgfx").bgfx;

const bgfx_util = @import("bgfx_util.zig");

pub const deinit_priority: i32 = -128;

width: u32,
height: u32,
reset_flags: u32,
debug: bool,
allocator: std.mem.Allocator,

pub const GpuMem = [*c]const bgfx.Memory;

pub const AaMode = enum {
    none,
    msaa2x,
    msaa4x,
    msaa8x,
    msaa16x,
};

fn aaModeToFlags(mode: AaMode) u32 {
    return switch (mode) {
        .none => bgfx.ResetFlags_None,
        .msaa2x => bgfx.ResetFlags_MsaaX2,
        .msaa4x => bgfx.ResetFlags_MsaaX4,
        .msaa8x => bgfx.ResetFlags_MsaaX8,
        .msaa16x => bgfx.ResetFlags_MsaaX16,
    };
}

pub const Config = struct {
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    ndt: ?*anyopaque,
    nwh: ?*anyopaque,
    renderer: bgfx.RendererType = bgfx.RendererType.Count,
    debug: bool = false,
    aa_mode: AaMode = .none,
};

pub fn init(config: Config) !RenderDevice {
    const reset_flags = aaModeToFlags(config.aa_mode);
    var bx_init = std.mem.zeroes(bgfx.Init);
    bgfx.initCtor(&bx_init);
    bx_init.type = config.renderer;
    bx_init.platformData.ndt = config.ndt;
    bx_init.platformData.nwh = config.nwh;
    bx_init.debug = config.debug;
    bx_init.callback = &bgfx_util.bgfx_clbs;
    bx_init.resolution.width = config.width;
    bx_init.resolution.height = config.height;
    bx_init.resolution.reset = reset_flags;
    bx_init.limits.maxTransientIbSize = 4 * 1024 * 1024;
    bx_init.limits.maxTransientVbSize = 16 * 1024 * 1024;

    if (!bgfx.init(&bx_init)) return error.BgfxInitFailed;

    if (config.debug) {
        bgfx.setDebug(bgfx.DebugFlags_Stats);
        @import("bgfx").debugdraw.init();
    }

    return .{
        .width = config.width,
        .height = config.height,
        .reset_flags = reset_flags,
        .allocator = config.allocator,
        .debug = config.debug,
    };
}

pub fn deinit(self: *RenderDevice) void {
    if (self.debug) {
        @import("bgfx").debugdraw.deinit();
    }
    bgfx.shutdown();
}

pub fn frame(self: *const RenderDevice) void {
    _ = self;
    _ = bgfx.frame(bgfx.FrameFlags_None);
}

pub fn resize(self: *RenderDevice, width: u32, height: u32) void {
    self.width = width;
    self.height = height;
    bgfx.reset(width, height, self.reset_flags, bgfx.TextureFormat.BGRA8);
}

pub fn setAaMode(self: *RenderDevice, mode: AaMode) void {
    self.reset_flags = aaModeToFlags(mode);
    bgfx.reset(self.width, self.height, self.reset_flags, .BGRA8);
}

pub fn alloc(_: *const RenderDevice, count: usize, T: type) GpuMem {
    const size = count * @sizeOf(T);
    return bgfx.alloc(@intCast(size));
}

pub fn allocTransient(self: *const RenderDevice, comptime Vertex: type, vertices: []const Vertex, indices: []const u16) !@Tuple(&.{ bgfx.TransientVertexBuffer, bgfx.TransientIndexBuffer }) {
    const layout = @import("vertex_parser.zig").createLayout(Vertex, .{}, self.getRendererType());

    var tib: bgfx.TransientIndexBuffer = undefined;
    var tvb: bgfx.TransientVertexBuffer = undefined;

    if (!bgfx.allocTransientBuffers(&tvb, &layout, @intCast(vertices.len), &tib, @intCast(indices.len), false)) {
        return error.OutOfMemory;
    }

    @memcpy(tvb.data[0 .. @sizeOf(Vertex) * vertices.len], std.mem.sliceAsBytes(vertices));
    @memcpy(tib.data[0 .. @sizeOf(u16) * indices.len], std.mem.sliceAsBytes(indices));

    return .{ tvb, tib };
}

pub fn getRendererType(self: *const RenderDevice) bgfx.RendererType {
    _ = self;
    return bgfx.getRendererType();
}
