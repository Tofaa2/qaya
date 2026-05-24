const std = @import("std");
const bgfx = @import("bgfx_util.zig").bgfx;
const isValid = @import("bgfx_util.zig").isValid;
const pool = @import("pool");
const math = @import("math");
const vertex_parser = @import("vertex_parser.zig");
const vertices = @import("vertices.zig");

const Mesh = @This();

pub const Pool = pool.PoolManaged(32, Mesh, Info, Error);
pub const Handle = Pool.Handle;

vb: bgfx.VertexBufferHandle,
ib: bgfx.IndexBufferHandle,
vertex_count: u32,
index_count: u32,
buffer_type: BufferType,

pub const BufferType = enum { static, dynamic };

pub const Error = error{
    InvalidIndexBuffer,
    InvalidVertexBuffer,
    OutOfMemory,
};

pub const Info = union(enum) {
    cube: void,
    lit_cube: void,
    quad: struct { width: f32 = 1.0, height: f32 = 1.0 },
    sphere: struct { radius: f32 = 0.5, segments: u32 = 16 },
    plane: struct { width: f32 = 10.0, depth: f32 = 10.0 },
    lit_quad: struct { width: f32 = 1.0, height: f32 = 1.0 },
    lit_sphere: struct { radius: f32 = 0.5, segments: u32 = 16 },
    cylinder: struct { radius: f32 = 0.5, height: f32 = 1.0, segments: u32 = 16 },
};

pub const Vertex = vertices.PosColor;

pub fn init(info: *const Info) Error!Mesh {
    return switch (info.*) {
        .cube => generateCube(),
        .lit_cube => generateLitCube(),
        inline .quad => |q| generateQuad(q.width, q.height),
        inline .sphere => |s| generateSphere(s.radius, s.segments),
        inline .plane => |p| generatePlane(p.width, p.depth),
        inline .lit_quad => |q| generateLitQuad(q.width, q.height),
        inline .lit_sphere => |s| generateLitSphere(s.radius, s.segments),
        inline .cylinder => |c| generateCylinder(c.radius, c.height, c.segments),
    };
}

pub fn deinit(self: *Mesh) void {
    bgfx.destroyVertexBuffer(self.vb);
    bgfx.destroyIndexBuffer(self.ib);
}

fn createBuffers(comptime V: type, verts: []const V, indices: []const u16) Error!Mesh {
    const layout = vertex_parser.createLayout(V, .{}, bgfx.getRendererType());
    const vb_mem = bgfx.copy(@ptrCast(verts.ptr), @intCast(verts.len * @sizeOf(V)));
    const ib_mem = bgfx.copy(@ptrCast(indices.ptr), @intCast(indices.len * @sizeOf(u16)));
    const vb = bgfx.createVertexBuffer(vb_mem, &layout, 0);
    if (!isValid(vb)) return error.InvalidVertexBuffer;
    const ib = bgfx.createIndexBuffer(ib_mem, 0);
    if (!isValid(ib)) {
        bgfx.destroyVertexBuffer(vb);
        return error.InvalidIndexBuffer;
    }
    return .{
        .vb = vb,
        .ib = ib,
        .vertex_count = @intCast(verts.len),
        .index_count = @intCast(indices.len),
        .buffer_type = .static,
    };
}

fn generateCube() Error!Mesh {
    const V = vertices.PosColorTex;
    const white = math.Color.white;

    const vs = [_]V{
        // +Z face
        .{ .position = .{ .x = -1, .y = -1, .z =  1 }, .color0 = white, .texcoord0 = .{ .x = 0, .y = 1 } },
        .{ .position = .{ .x =  1, .y = -1, .z =  1 }, .color0 = white, .texcoord0 = .{ .x = 1, .y = 1 } },
        .{ .position = .{ .x =  1, .y =  1, .z =  1 }, .color0 = white, .texcoord0 = .{ .x = 1, .y = 0 } },
        .{ .position = .{ .x = -1, .y =  1, .z =  1 }, .color0 = white, .texcoord0 = .{ .x = 0, .y = 0 } },
        // -Z face
        .{ .position = .{ .x = -1, .y = -1, .z = -1 }, .color0 = white, .texcoord0 = .{ .x = 0, .y = 1 } },
        .{ .position = .{ .x =  1, .y = -1, .z = -1 }, .color0 = white, .texcoord0 = .{ .x = 1, .y = 1 } },
        .{ .position = .{ .x =  1, .y =  1, .z = -1 }, .color0 = white, .texcoord0 = .{ .x = 1, .y = 0 } },
        .{ .position = .{ .x = -1, .y =  1, .z = -1 }, .color0 = white, .texcoord0 = .{ .x = 0, .y = 0 } },
        // +Y face
        .{ .position = .{ .x = -1, .y =  1, .z =  1 }, .color0 = white, .texcoord0 = .{ .x = 0, .y = 1 } },
        .{ .position = .{ .x =  1, .y =  1, .z =  1 }, .color0 = white, .texcoord0 = .{ .x = 1, .y = 1 } },
        .{ .position = .{ .x =  1, .y =  1, .z = -1 }, .color0 = white, .texcoord0 = .{ .x = 1, .y = 0 } },
        .{ .position = .{ .x = -1, .y =  1, .z = -1 }, .color0 = white, .texcoord0 = .{ .x = 0, .y = 0 } },
        // -Y face
        .{ .position = .{ .x = -1, .y = -1, .z = -1 }, .color0 = white, .texcoord0 = .{ .x = 0, .y = 1 } },
        .{ .position = .{ .x =  1, .y = -1, .z = -1 }, .color0 = white, .texcoord0 = .{ .x = 1, .y = 1 } },
        .{ .position = .{ .x =  1, .y = -1, .z =  1 }, .color0 = white, .texcoord0 = .{ .x = 1, .y = 0 } },
        .{ .position = .{ .x = -1, .y = -1, .z =  1 }, .color0 = white, .texcoord0 = .{ .x = 0, .y = 0 } },
        // +X face
        .{ .position = .{ .x =  1, .y = -1, .z =  1 }, .color0 = white, .texcoord0 = .{ .x = 0, .y = 1 } },
        .{ .position = .{ .x =  1, .y = -1, .z = -1 }, .color0 = white, .texcoord0 = .{ .x = 1, .y = 1 } },
        .{ .position = .{ .x =  1, .y =  1, .z = -1 }, .color0 = white, .texcoord0 = .{ .x = 1, .y = 0 } },
        .{ .position = .{ .x =  1, .y =  1, .z =  1 }, .color0 = white, .texcoord0 = .{ .x = 0, .y = 0 } },
        // -X face
        .{ .position = .{ .x = -1, .y = -1, .z = -1 }, .color0 = white, .texcoord0 = .{ .x = 0, .y = 1 } },
        .{ .position = .{ .x = -1, .y = -1, .z =  1 }, .color0 = white, .texcoord0 = .{ .x = 1, .y = 1 } },
        .{ .position = .{ .x = -1, .y =  1, .z =  1 }, .color0 = white, .texcoord0 = .{ .x = 1, .y = 0 } },
        .{ .position = .{ .x = -1, .y =  1, .z = -1 }, .color0 = white, .texcoord0 = .{ .x = 0, .y = 0 } },
    };

    const idx = [_]u16{
         0,  1,  2,  0,  2,  3,
         4,  6,  5,  4,  7,  6,
         8,  9, 10,  8, 10, 11,
        12, 13, 14, 12, 14, 15,
        16, 17, 18, 16, 18, 19,
        20, 21, 22, 20, 22, 23,
    };

    return createBuffers(V, &vs, &idx);
}

fn generateLitCube() Error!Mesh {
    const V = vertices.PosNormalTex;
    const white = math.Color.white;

    const vs = [_]V{
        // +Z face (normal: 0, 0, 1)
        .{ .position = .{ .x = -1, .y = -1, .z =  1 }, .normal = .{ .x = 0, .y = 0, .z =  1 }, .texcoord0 = .{ .x = 0, .y = 1 }, .color0 = white },
        .{ .position = .{ .x =  1, .y = -1, .z =  1 }, .normal = .{ .x = 0, .y = 0, .z =  1 }, .texcoord0 = .{ .x = 1, .y = 1 }, .color0 = white },
        .{ .position = .{ .x =  1, .y =  1, .z =  1 }, .normal = .{ .x = 0, .y = 0, .z =  1 }, .texcoord0 = .{ .x = 1, .y = 0 }, .color0 = white },
        .{ .position = .{ .x = -1, .y =  1, .z =  1 }, .normal = .{ .x = 0, .y = 0, .z =  1 }, .texcoord0 = .{ .x = 0, .y = 0 }, .color0 = white },
        // -Z face (normal: 0, 0, -1)
        .{ .position = .{ .x = -1, .y = -1, .z = -1 }, .normal = .{ .x = 0, .y = 0, .z = -1 }, .texcoord0 = .{ .x = 0, .y = 1 }, .color0 = white },
        .{ .position = .{ .x =  1, .y = -1, .z = -1 }, .normal = .{ .x = 0, .y = 0, .z = -1 }, .texcoord0 = .{ .x = 1, .y = 1 }, .color0 = white },
        .{ .position = .{ .x =  1, .y =  1, .z = -1 }, .normal = .{ .x = 0, .y = 0, .z = -1 }, .texcoord0 = .{ .x = 1, .y = 0 }, .color0 = white },
        .{ .position = .{ .x = -1, .y =  1, .z = -1 }, .normal = .{ .x = 0, .y = 0, .z = -1 }, .texcoord0 = .{ .x = 0, .y = 0 }, .color0 = white },
        // +Y face (normal: 0, 1, 0)
        .{ .position = .{ .x = -1, .y =  1, .z =  1 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .texcoord0 = .{ .x = 0, .y = 1 }, .color0 = white },
        .{ .position = .{ .x =  1, .y =  1, .z =  1 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .texcoord0 = .{ .x = 1, .y = 1 }, .color0 = white },
        .{ .position = .{ .x =  1, .y =  1, .z = -1 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .texcoord0 = .{ .x = 1, .y = 0 }, .color0 = white },
        .{ .position = .{ .x = -1, .y =  1, .z = -1 }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .texcoord0 = .{ .x = 0, .y = 0 }, .color0 = white },
        // -Y face (normal: 0, -1, 0)
        .{ .position = .{ .x = -1, .y = -1, .z = -1 }, .normal = .{ .x = 0, .y = -1, .z = 0 }, .texcoord0 = .{ .x = 0, .y = 1 }, .color0 = white },
        .{ .position = .{ .x =  1, .y = -1, .z = -1 }, .normal = .{ .x = 0, .y = -1, .z = 0 }, .texcoord0 = .{ .x = 1, .y = 1 }, .color0 = white },
        .{ .position = .{ .x =  1, .y = -1, .z =  1 }, .normal = .{ .x = 0, .y = -1, .z = 0 }, .texcoord0 = .{ .x = 1, .y = 0 }, .color0 = white },
        .{ .position = .{ .x = -1, .y = -1, .z =  1 }, .normal = .{ .x = 0, .y = -1, .z = 0 }, .texcoord0 = .{ .x = 0, .y = 0 }, .color0 = white },
        // +X face (normal: 1, 0, 0)
        .{ .position = .{ .x =  1, .y = -1, .z =  1 }, .normal = .{ .x = 1, .y = 0, .z = 0 }, .texcoord0 = .{ .x = 0, .y = 1 }, .color0 = white },
        .{ .position = .{ .x =  1, .y = -1, .z = -1 }, .normal = .{ .x = 1, .y = 0, .z = 0 }, .texcoord0 = .{ .x = 1, .y = 1 }, .color0 = white },
        .{ .position = .{ .x =  1, .y =  1, .z = -1 }, .normal = .{ .x = 1, .y = 0, .z = 0 }, .texcoord0 = .{ .x = 1, .y = 0 }, .color0 = white },
        .{ .position = .{ .x =  1, .y =  1, .z =  1 }, .normal = .{ .x = 1, .y = 0, .z = 0 }, .texcoord0 = .{ .x = 0, .y = 0 }, .color0 = white },
        // -X face (normal: -1, 0, 0)
        .{ .position = .{ .x = -1, .y = -1, .z = -1 }, .normal = .{ .x = -1, .y = 0, .z = 0 }, .texcoord0 = .{ .x = 0, .y = 1 }, .color0 = white },
        .{ .position = .{ .x = -1, .y = -1, .z =  1 }, .normal = .{ .x = -1, .y = 0, .z = 0 }, .texcoord0 = .{ .x = 1, .y = 1 }, .color0 = white },
        .{ .position = .{ .x = -1, .y =  1, .z =  1 }, .normal = .{ .x = -1, .y = 0, .z = 0 }, .texcoord0 = .{ .x = 1, .y = 0 }, .color0 = white },
        .{ .position = .{ .x = -1, .y =  1, .z = -1 }, .normal = .{ .x = -1, .y = 0, .z = 0 }, .texcoord0 = .{ .x = 0, .y = 0 }, .color0 = white },
    };

    const idx = [_]u16{
         0,  1,  2,  0,  2,  3,
         4,  6,  5,  4,  7,  6,
         8,  9, 10,  8, 10, 11,
        12, 13, 14, 12, 14, 15,
        16, 17, 18, 16, 18, 19,
        20, 21, 22, 20, 22, 23,
    };

    return createBuffers(V, &vs, &idx);
}

fn generateQuad(width: f32, height: f32) Error!Mesh {
    const hw = width / 2;
    const hh = height / 2;
    const white = math.Color.white;

    const vs = [_]Vertex{
        .{ .position = math.Vec3{ .x = -hw, .y = -hh, .z = 0 }, .color0 = white },
        .{ .position = math.Vec3{ .x =  hw, .y = -hh, .z = 0 }, .color0 = white },
        .{ .position = math.Vec3{ .x =  hw, .y =  hh, .z = 0 }, .color0 = white },
        .{ .position = math.Vec3{ .x = -hw, .y =  hh, .z = 0 }, .color0 = white },
    };

    const idx = [_]u16{ 0, 1, 2, 0, 2, 3 };

    return createBuffers(Vertex, &vs, &idx);
}

fn generateSphere(radius: f32, segments: u32) Error!Mesh {
    const allocator = std.heap.page_allocator;
    const lat_steps = segments;
    const lon_steps = segments * 2;
    const vert_count = (lat_steps + 1) * (lon_steps + 1);
    const idx_count = lat_steps * lon_steps * 6;

    const verts = try allocator.alloc(Vertex, vert_count);
    defer allocator.free(verts);
    const indices = try allocator.alloc(u16, idx_count);
    defer allocator.free(indices);

    var vi: usize = 0;
    for (0..lat_steps + 1) |lat| {
        const theta = std.math.pi * @as(f32, @floatFromInt(lat)) / @as(f32, @floatFromInt(lat_steps));
        const sin_theta = @sin(theta);
        const cos_theta = @cos(theta);
        for (0..lon_steps + 1) |lon| {
            const phi = 2.0 * std.math.pi * @as(f32, @floatFromInt(lon)) / @as(f32, @floatFromInt(lon_steps));
            verts[vi] = .{
                .position = .{ .x = radius * @cos(phi) * sin_theta, .y = radius * cos_theta, .z = radius * @sin(phi) * sin_theta },
                .color0 = math.Color.white,
            };
            vi += 1;
        }
    }

    var ii: usize = 0;
    for (0..lat_steps) |lat| {
        for (0..lon_steps) |lon| {
            const first = lat * (lon_steps + 1) + lon;
            const second = first + lon_steps + 1;
            indices[ii] = @intCast(first); ii += 1;
            indices[ii] = @intCast(second); ii += 1;
            indices[ii] = @intCast(first + 1); ii += 1;
            indices[ii] = @intCast(second); ii += 1;
            indices[ii] = @intCast(second + 1); ii += 1;
            indices[ii] = @intCast(first + 1); ii += 1;
        }
    }

    return createBuffers(Vertex, verts, indices);
}

fn generatePlane(width: f32, depth: f32) Error!Mesh {
    const V = vertices.PosNormalTex;
    const hw = width / 2;
    const hd = depth / 2;
    const white = math.Color.white;

    const vs = [_]V{
        .{ .position = .{ .x = -hw, .y = 0, .z = -hd }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .texcoord0 = .{ .x = 0, .y = 0 }, .color0 = white },
        .{ .position = .{ .x =  hw, .y = 0, .z = -hd }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .texcoord0 = .{ .x = 1, .y = 0 }, .color0 = white },
        .{ .position = .{ .x =  hw, .y = 0, .z =  hd }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .texcoord0 = .{ .x = 1, .y = 1 }, .color0 = white },
        .{ .position = .{ .x = -hw, .y = 0, .z =  hd }, .normal = .{ .x = 0, .y = 1, .z = 0 }, .texcoord0 = .{ .x = 0, .y = 1 }, .color0 = white },
    };

    const idx = [_]u16{ 2, 1, 0, 3, 2, 0 };
    return createBuffers(V, &vs, &idx);
}

fn generateLitQuad(width: f32, height: f32) Error!Mesh {
    const V = vertices.PosNormalTex;
    const hw = width / 2;
    const hh = height / 2;
    const white = math.Color.white;

    const vs = [_]V{
        .{ .position = .{ .x = -hw, .y = -hh, .z = 0 }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .texcoord0 = .{ .x = 0, .y = 1 }, .color0 = white },
        .{ .position = .{ .x =  hw, .y = -hh, .z = 0 }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .texcoord0 = .{ .x = 1, .y = 1 }, .color0 = white },
        .{ .position = .{ .x =  hw, .y =  hh, .z = 0 }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .texcoord0 = .{ .x = 1, .y = 0 }, .color0 = white },
        .{ .position = .{ .x = -hw, .y =  hh, .z = 0 }, .normal = .{ .x = 0, .y = 0, .z = 1 }, .texcoord0 = .{ .x = 0, .y = 0 }, .color0 = white },
    };

    const idx = [_]u16{ 0, 1, 2, 0, 2, 3 };
    return createBuffers(V, &vs, &idx);
}

fn generateLitSphere(radius: f32, segments: u32) Error!Mesh {
    const V = vertices.PosNormalTex;
    const allocator = std.heap.page_allocator;
    const lat_steps = segments;
    const lon_steps = segments * 2;
    const vert_count = (lat_steps + 1) * (lon_steps + 1);
    const idx_count = lat_steps * lon_steps * 6;

    const verts = try allocator.alloc(V, vert_count);
    defer allocator.free(verts);
    const indices = try allocator.alloc(u16, idx_count);
    defer allocator.free(indices);

    var vi: usize = 0;
    for (0..lat_steps + 1) |lat| {
        const theta = std.math.pi * @as(f32, @floatFromInt(lat)) / @as(f32, @floatFromInt(lat_steps));
        const sin_theta = @sin(theta);
        const cos_theta = @cos(theta);
        for (0..lon_steps + 1) |lon| {
            const phi = 2.0 * std.math.pi * @as(f32, @floatFromInt(lon)) / @as(f32, @floatFromInt(lon_steps));
            const x = radius * @cos(phi) * sin_theta;
            const y = radius * cos_theta;
            const z = radius * @sin(phi) * sin_theta;
            const n = @sqrt(x * x + y * y + z * z);
            verts[vi] = .{
                .position = .{ .x = x, .y = y, .z = z },
                .normal = .{ .x = x / n, .y = y / n, .z = z / n },
                .texcoord0 = .{ .x = @as(f32, @floatFromInt(lon)) / @as(f32, @floatFromInt(lon_steps)), .y = @as(f32, @floatFromInt(lat)) / @as(f32, @floatFromInt(lat_steps)) },
                .color0 = math.Color.white,
            };
            vi += 1;
        }
    }

    var ii: usize = 0;
    for (0..lat_steps) |lat| {
        for (0..lon_steps) |lon| {
            const first = lat * (lon_steps + 1) + lon;
            const second = first + lon_steps + 1;
            indices[ii] = @intCast(first); ii += 1;
            indices[ii] = @intCast(second); ii += 1;
            indices[ii] = @intCast(first + 1); ii += 1;
            indices[ii] = @intCast(second); ii += 1;
            indices[ii] = @intCast(second + 1); ii += 1;
            indices[ii] = @intCast(first + 1); ii += 1;
        }
    }

    return createBuffers(V, verts, indices);
}

fn generateCylinder(radius: f32, height: f32, segments: u32) Error!Mesh {
    const V = vertices.PosNormalTex;
    const allocator = std.heap.page_allocator;
    const hh = height / 2;
    const ring_verts = segments + 1;
    const vert_count = ring_verts * 2 + 2;
    const idx_count = segments * 12;

    const verts = try allocator.alloc(V, vert_count);
    defer allocator.free(verts);
    const indices = try allocator.alloc(u16, idx_count);
    defer allocator.free(indices);

    const white = math.Color.white;
    var vi: usize = 0;

    for (0..ring_verts) |i| {
        const a = 2.0 * std.math.pi * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segments));
        const ca = @cos(a);
        const sa = @sin(a);
        verts[vi] = .{
            .position = .{ .x = radius * ca, .y = -hh, .z = radius * sa },
            .normal = .{ .x = ca, .y = 0, .z = sa },
            .texcoord0 = .{ .x = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segments)), .y = 0 },
            .color0 = white,
        };
        vi += 1;
    }
    for (0..ring_verts) |i| {
        const a = 2.0 * std.math.pi * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segments));
        const ca = @cos(a);
        const sa = @sin(a);
        verts[vi] = .{
            .position = .{ .x = radius * ca, .y = hh, .z = radius * sa },
            .normal = .{ .x = ca, .y = 0, .z = sa },
            .texcoord0 = .{ .x = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segments)), .y = 1 },
            .color0 = white,
        };
        vi += 1;
    }

    const center_bot = vi;
    verts[vi] = .{
        .position = .{ .x = 0, .y = -hh, .z = 0 },
        .normal = .{ .x = 0, .y = -1, .z = 0 },
        .texcoord0 = .{ .x = 0.5, .y = 0.5 },
        .color0 = white,
    };
    vi += 1;
    const center_top = vi;
    verts[vi] = .{
        .position = .{ .x = 0, .y = hh, .z = 0 },
        .normal = .{ .x = 0, .y = 1, .z = 0 },
        .texcoord0 = .{ .x = 0.5, .y = 0.5 },
        .color0 = white,
    };
    vi += 1;

    var ii: usize = 0;
    for (0..segments) |i| {
        const a = i;
        const b = i + 1;
        indices[ii] = @intCast(a); ii += 1;
        indices[ii] = @intCast(b); ii += 1;
        indices[ii] = @intCast(a + ring_verts); ii += 1;
        indices[ii] = @intCast(b); ii += 1;
        indices[ii] = @intCast(b + ring_verts); ii += 1;
        indices[ii] = @intCast(a + ring_verts); ii += 1;
    }

    for (0..segments) |i| {
        const a = i;
        const b = i + 1;
        indices[ii] = @intCast(center_bot); ii += 1;
        indices[ii] = @intCast(b); ii += 1;
        indices[ii] = @intCast(a); ii += 1;
    }
    for (0..segments) |i| {
        const a = i + ring_verts;
        const b = i + 1 + ring_verts;
        indices[ii] = @intCast(center_top); ii += 1;
        indices[ii] = @intCast(a); ii += 1;
        indices[ii] = @intCast(b); ii += 1;
    }

    return createBuffers(V, verts, indices);
}
