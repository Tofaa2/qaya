const std = @import("std");
const math = @import("math");
const vertices = @import("../vertices.zig");

allocator: std.mem.Allocator,
path: []const u8,

positions: std.ArrayListUnmanaged(math.Vec3),
texcoords: std.ArrayListUnmanaged(math.Vec2),
normals: std.ArrayListUnmanaged(math.Vec3),
faces: std.ArrayListUnmanaged(Face),

pub const Face = struct {
    position_indices: [3]u32,
    texcoord_indices: [3]i32,
    normal_indices: [3]i32,
};

pub const Error = error{
    FileNotFound,
    InvalidFormat,
    UnsupportedFace,
    OutOfMemory,
};

pub fn init(allocator: std.mem.Allocator, path: []const u8) Error!Parser {
    var threaded = std.Io.Threaded.init(allocator, .{});
    const io = threaded.io();
    const dir = std.Io.Dir.cwd();
    const content = dir.readFileAlloc(io, path, allocator, @enumFromInt(100 * 1024 * 1024)) catch {
        return error.FileNotFound;
    };

    var parser = Parser{
        .allocator = allocator,
        .path = path,
        .positions = .empty,
        .texcoords = .empty,
        .normals = .empty,
        .faces = .empty,
    };

    parser.parse(content) catch |err| {
        allocator.free(content);
        parser.deinit();
        return err;
    };
    allocator.free(content);
    return parser;
}

fn parse(self: *Parser, content: []const u8) !void {
    var line_start: usize = 0;
    var line_number: usize = 0;

    while (line_start < content.len) {
        var line_end = line_start;
        while (line_end < content.len and content[line_end] != '\n') : (line_end += 1) {}
        defer {
            line_start = line_end + 1;
            line_number += 1;
        }

        const line = content[line_start..line_end];
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        if (std.mem.startsWith(u8, trimmed, "v ")) {
            try self.parseVertex(trimmed);
        } else if (std.mem.startsWith(u8, trimmed, "vt ")) {
            try self.parseTexcoord(trimmed);
        } else if (std.mem.startsWith(u8, trimmed, "vn ")) {
            try self.parseNormal(trimmed);
        } else if (trimmed[0] == 'f' and (trimmed.len == 1 or trimmed[1] == ' ')) {
            try self.parseFace(trimmed);
        }
    }
}

fn parseFloatToken(token: []const u8) !f32 {
    return std.fmt.parseFloat(f32, token) catch return error.InvalidFormat;
}

fn parseIntToken(token: []const u8) !i32 {
    return std.fmt.parseInt(i32, token, 10) catch return error.InvalidFormat;
}

fn parseVertex(self: *Parser, line: []const u8) !void {
    var tokens = std.mem.tokenizeScalar(u8, line[2..], ' ');
    const x = try parseFloatToken(tokens.next() orelse return error.InvalidFormat);
    const y = try parseFloatToken(tokens.next() orelse return error.InvalidFormat);
    const z = try parseFloatToken(tokens.next() orelse return error.InvalidFormat);
    try self.positions.append(self.allocator, math.Vec3.init(x, y, z));
}

fn parseTexcoord(self: *Parser, line: []const u8) !void {
    var tokens = std.mem.tokenizeScalar(u8, line[3..], ' ');
    const u = try parseFloatToken(tokens.next() orelse return error.InvalidFormat);
    const v = try parseFloatToken(tokens.next() orelse return error.InvalidFormat);
    try self.texcoords.append(self.allocator, math.Vec2.init(u, v));
}

fn parseNormal(self: *Parser, line: []const u8) !void {
    var tokens = std.mem.tokenizeScalar(u8, line[3..], ' ');
    const x = try parseFloatToken(tokens.next() orelse return error.InvalidFormat);
    const y = try parseFloatToken(tokens.next() orelse return error.InvalidFormat);
    const z = try parseFloatToken(tokens.next() orelse return error.InvalidFormat);
    try self.normals.append(self.allocator, math.Vec3.init(x, y, z));
}

fn parseFace(self: *Parser, line: []const u8) !void {
    var tokens = std.mem.tokenizeScalar(u8, line[2..], ' ');

    var raw_indices: [128][3]i32 = undefined;
    var count: usize = 0;

    while (tokens.next()) |token| {
        if (count >= raw_indices.len) return error.UnsupportedFace;
        raw_indices[count] = try parseFaceIndex(token);
        count += 1;
    }

    if (count < 3) return error.InvalidFormat;

    var i: usize = 1;
    while (i + 1 < count) : (i += 1) {
        try self.faces.append(self.allocator, .{
            .position_indices = .{
                @intCast(normalizeIndex(raw_indices[0][0], self.positions.items.len)),
                @intCast(normalizeIndex(raw_indices[i][0], self.positions.items.len)),
                @intCast(normalizeIndex(raw_indices[i + 1][0], self.positions.items.len)),
            },
            .texcoord_indices = .{
                if (raw_indices[0][1] >= 0) @intCast(normalizeIndex(raw_indices[0][1], self.texcoords.items.len)) else -1,
                if (raw_indices[i][1] >= 0) @intCast(normalizeIndex(raw_indices[i][1], self.texcoords.items.len)) else -1,
                if (raw_indices[i + 1][1] >= 0) @intCast(normalizeIndex(raw_indices[i + 1][1], self.texcoords.items.len)) else -1,
            },
            .normal_indices = .{
                if (raw_indices[0][2] >= 0) @intCast(normalizeIndex(raw_indices[0][2], self.normals.items.len)) else -1,
                if (raw_indices[i][2] >= 0) @intCast(normalizeIndex(raw_indices[i][2], self.normals.items.len)) else -1,
                if (raw_indices[i + 1][2] >= 0) @intCast(normalizeIndex(raw_indices[i + 1][2], self.normals.items.len)) else -1,
            },
        });
    }
}

fn parseFaceIndex(token: []const u8) ![3]i32 {
    var parts = std.mem.splitScalar(u8, token, '/');
    const v = try parseIntToken(parts.next() orelse return error.InvalidFormat);
    const vt = if (parts.next()) |t|
        if (t.len > 0) try parseIntToken(t) else -1
    else
        -1;
    const vn = if (parts.next()) |n|
        if (n.len > 0) try parseIntToken(n) else -1
    else
        -1;
    return .{ v, vt, vn };
}

fn normalizeIndex(index: i32, count: usize) usize {
    return if (index > 0)
        @as(usize, @intCast(index - 1))
    else
        @as(usize, @intCast(@as(i64, @intCast(count)) + @as(i64, index)));
}

fn generateNormals(self: *Parser) !void {
    if (self.normals.items.len > 0) return;

    try self.normals.resize(self.allocator, self.positions.items.len);
    for (self.normals.items) |*n| n.* = math.Vec3.zero();

    for (self.faces.items) |face| {
        const p0 = self.positions.items[face.position_indices[0]];
        const p1 = self.positions.items[face.position_indices[1]];
        const p2 = self.positions.items[face.position_indices[2]];
        const edge1 = math.Vec3.sub(p1, p0);
        const edge2 = math.Vec3.sub(p2, p0);
        const normal = math.Vec3.normalize(math.Vec3.cross(edge1, edge2));

        for (face.position_indices) |pi| {
            self.normals.items[pi] = math.Vec3.add(self.normals.items[pi], normal);
        }
    }

    for (self.normals.items) |*n| {
        const len = math.Vec3.length(n.*);
        if (len > 0.0001) {
            n.* = math.Vec3.scale(n.*, 1.0 / len);
        } else {
            n.* = math.Vec3.init(0, 1, 0);
        }
    }
}

pub fn toMesh(self: *Parser) !MeshData {
    try self.generateNormals();

    var verts: std.ArrayListUnmanaged(vertices.PosNormalTex) = .empty;
    var idx: std.ArrayListUnmanaged(u16) = .empty;
    errdefer verts.deinit(self.allocator);
    errdefer idx.deinit(self.allocator);

    var dedup = std.AutoHashMap(DedupKey, u16).init(self.allocator);
    defer dedup.deinit();

    for (self.faces.items) |face| {
        var tri_indices: [3]u16 = undefined;
        for (0..3) |j| {
            const key = DedupKey{
                .position = face.position_indices[j],
                .texcoord = if (face.texcoord_indices[j] >= 0) @intCast(face.texcoord_indices[j]) else 0,
                .normal = if (face.normal_indices[j] >= 0) @intCast(face.normal_indices[j]) else 0,
            };

            if (dedup.get(key)) |existing| {
                tri_indices[j] = existing;
            } else {
                const vi = @as(u16, @intCast(verts.items.len));
                const pos = self.positions.items[face.position_indices[j]];
                const nml = if (face.normal_indices[j] >= 0)
                    self.normals.items[@as(usize, @intCast(face.normal_indices[j]))]
                else
                    math.Vec3.init(0, 1, 0);
                const tex = if (face.texcoord_indices[j] >= 0 and @as(usize, @intCast(face.texcoord_indices[j])) < self.texcoords.items.len)
                    self.texcoords.items[@as(usize, @intCast(face.texcoord_indices[j]))]
                else
                    math.Vec2.init(0, 0);

                try verts.append(self.allocator, .{
                    .position = pos,
                    .normal = nml,
                    .texcoord0 = tex,
                    .color0 = math.Color.white,
                });
                try dedup.put(key, vi);
                tri_indices[j] = vi;
            }
        }

        try idx.append(self.allocator, tri_indices[0]);
        try idx.append(self.allocator, tri_indices[1]);
        try idx.append(self.allocator, tri_indices[2]);
    }

    return MeshData{
        .vertices = try verts.toOwnedSlice(self.allocator),
        .indices = try idx.toOwnedSlice(self.allocator),
    };
}

pub fn deinit(self: *Parser) void {
    self.positions.deinit(self.allocator);
    self.texcoords.deinit(self.allocator);
    self.normals.deinit(self.allocator);
    self.faces.deinit(self.allocator);
}

const DedupKey = packed struct {
    position: u32,
    texcoord: u32,
    normal: u32,
};

pub const MeshData = struct {
    vertices: []vertices.PosNormalTex,
    indices: []u16,

    pub fn deinit(md: *MeshData, allocator: std.mem.Allocator) void {
        allocator.free(md.vertices);
        allocator.free(md.indices);
    }
};

pub const Parser = @This();
