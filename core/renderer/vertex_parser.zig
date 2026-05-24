const std = @import("std");
const bgfx = @import("bgfx").bgfx;
const math = @import("math");

const FieldOffset = struct {
    field: std.builtin.Type.StructField,
    offset: usize,
};

fn attribByteSize(num: u8, attrib_type: bgfx.AttribType) u16 {
    return switch (attrib_type) {
        .Int8, .Uint8 => num * 1,
        .Uint10 => 4,
        .Int16, .Uint16, .Half => num * 2,
        .Float => num * 4,
        .Count => unreachable,
    };
}

fn typeId(comptime T: type) usize {
    return comptime std.hash.Wyhash.hash(0, @typeName(T));
}

// Per-field override descriptor.
// All fields are optional — only set what you want to override.
pub const FieldInfo = struct {
    attrib: ?bgfx.Attrib = null,
    attrib_type: ?bgfx.AttribType = null,
    num: ?u8 = null,
    normalized: bool = false,
    as_int: bool = false,
};

// The info map you pass alongside your vertex type.
// Keys must match field names exactly.
// e.g.  &.{ .pos = .{ .attrib = .Position }, .uv = .{} }
pub fn VertexInfo(comptime Vertex: type) type {
    const fields = std.meta.fields(Vertex);

    var name_array: [fields.len][]const u8 = undefined;
    var type_array: [fields.len]type = undefined;
    var attrs_array: [fields.len]std.builtin.Type.StructField.Attributes = undefined;

    for (fields, 0..) |f, i| {
        name_array[i] = f.name;
        type_array[i] = FieldInfo;
        attrs_array[i] = .{
            .default_value_ptr = &FieldInfo{},
        };
    }

    return @Struct(.auto, null, &name_array, &type_array, &attrs_array);
}

// Comptime name → Attrib inference table.
// Exact match only — unknown names cause a compile error.
const AttribName = struct { name: []const u8, attrib: bgfx.Attrib };

const attrib_name_table = [_]AttribName{
    .{ .name = "position", .attrib = .Position },
    .{ .name = "normal", .attrib = .Normal },
    .{ .name = "tangent", .attrib = .Tangent },
    .{ .name = "bitangent", .attrib = .Bitangent },
    .{ .name = "color0", .attrib = .Color0 },
    .{ .name = "color1", .attrib = .Color1 },
    .{ .name = "color2", .attrib = .Color2 },
    .{ .name = "color3", .attrib = .Color3 },
    .{ .name = "indices", .attrib = .Indices },
    .{ .name = "weight", .attrib = .Weight },
    .{ .name = "texcoord0", .attrib = .TexCoord0 },
    .{ .name = "texcoord1", .attrib = .TexCoord1 },
    .{ .name = "texcoord2", .attrib = .TexCoord2 },
    .{ .name = "texcoord3", .attrib = .TexCoord3 },
    .{ .name = "texcoord4", .attrib = .TexCoord4 },
    .{ .name = "texcoord5", .attrib = .TexCoord5 },
    .{ .name = "texcoord6", .attrib = .TexCoord6 },
    .{ .name = "texcoord7", .attrib = .TexCoord7 },
};

fn inferAttrib(comptime name: []const u8) bgfx.Attrib {
    for (attrib_name_table) |entry| {
        if (std.mem.eql(u8, entry.name, name)) return entry.attrib;
    }
    @compileError("bgfx vertex layout: field '" ++ name ++
        "' does not match any known Attrib name. " ++
        "Provide an explicit FieldInfo override for this field.");
}

// Comptime Zig type → (AttribType, num) inference.
// Handles scalar and fixed-size array cases.
const TypeMapping = struct { attrib_type: bgfx.AttribType, num: u8, opt_normaized: ?bool = null };

fn inferTypeMapping(comptime T: type) TypeMapping {
    return switch (@typeInfo(T)) {
        .float => |f| switch (f.bits) {
            16 => .{ .attrib_type = .Half, .num = 1 },
            32 => .{ .attrib_type = .Float, .num = 1 },
            else => @compileError("bgfx vertex layout: unsupported float width " ++
                std.fmt.comptimePrint("{}", .{f.bits})),
        },
        .int => |i| switch (i.signedness) {
            .unsigned => switch (i.bits) {
                8 => .{ .attrib_type = .Uint8, .num = 1 },
                10 => .{ .attrib_type = .Uint10, .num = 1 },
                else => @compileError("bgfx vertex layout: unsupported unsigned int width"),
            },
            .signed => switch (i.bits) {
                16 => .{ .attrib_type = .Int16, .num = 1 },
                else => @compileError("bgfx vertex layout: unsupported signed int width"),
            },
        },
        .array => |arr| blk: {
            const child = inferTypeMapping(arr.child);
            break :blk .{ .attrib_type = child.attrib_type, .num = arr.len };
        },
        .@"struct" => |s| blk: {
            _ = s;
            if (T == math.Vec2) break :blk .{ .attrib_type = .Float, .num = 2 };
            if (T == math.Vec3) break :blk .{ .attrib_type = .Float, .num = 3 };
            if (T == math.Vec4) break :blk .{ .attrib_type = .Float, .num = 4 };
            if (T == math.Color) break :blk .{ .attrib_type = .Uint8, .num = 4, .opt_normaized = true };
            @compileError("bgfx vertex layout: cannot infer AttribType from struct " ++ @typeName(T));
        },
        else => @compileError("bgfx vertex layout: cannot infer AttribType from type " ++
            @typeName(T)),
    };
}

//   Vertex       — your vertex struct type
//   info         — optional VertexInfo(Vertex) with per-field overrides
//   renderer     — passed to bgfx.VertexLayout.begin()
pub fn createLayout(
    comptime Vertex: type,
    comptime info: VertexInfo(Vertex),
    renderer: bgfx.RendererType,
) bgfx.VertexLayout {
    comptime {
        switch (@typeInfo(Vertex)) {
            .@"struct" => {},
            else => @compileError("bgfx vertex layout: expected a struct type, got " ++
                @typeName(Vertex)),
        }
    }

    var layout: bgfx.VertexLayout = undefined;
    _ = layout.begin(renderer);

    const fields = std.meta.fields(Vertex);

    // Sort fields by their actual memory offset. Zig's auto layout may
    // reorder fields, so we cannot rely on declaration order matching
    // memory order. bgfx expects attributes in memory order.
    const sorted = comptime blk: {
        var result: [fields.len]FieldOffset = undefined;
        for (fields, 0..) |f, i| {
            result[i] = .{ .field = f, .offset = @offsetOf(Vertex, f.name) };
        }
        std.sort.block(FieldOffset, &result, {}, struct {
            fn lessThan(_: void, a: FieldOffset, b: FieldOffset) bool {
                return a.offset < b.offset;
            }
        }.lessThan);
        break :blk result;
    };

    var current_stride: u16 = 0;
    inline for (sorted) |entry| {
        const field = entry.field;
        const field_offset: u16 = @intCast(entry.offset);

        // Insert padding bytes if there's a gap before this field
        if (field_offset > current_stride) {
            _ = layout.skip(@intCast(field_offset - current_stride));
            current_stride = field_offset;
        }

        const override: FieldInfo = @field(info, field.name);
        const attrib: bgfx.Attrib = comptime if (override.attrib) |a| a else inferAttrib(field.name);
        const inferred = comptime inferTypeMapping(field.type);
        const attrib_type: bgfx.AttribType = comptime if (override.attrib_type) |t| t else inferred.attrib_type;
        const num: u8 = comptime if (override.num) |n| n else inferred.num;

        var normalized: bool = override.normalized;
        if (inferred.opt_normaized) |n| {
            normalized = n;
        }

        _ = layout.add(attrib, num, attrib_type, normalized, override.as_int);
        current_stride += attribByteSize(num, attrib_type);
    }

    // Account for any trailing padding in the struct
    const total_size: u16 = @sizeOf(Vertex);
    if (total_size > current_stride) {
        _ = layout.skip(@intCast(total_size - current_stride));
    }

    layout.end();
    return layout;
}
