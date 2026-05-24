const Self = @This();

r: u8,
g: u8,
b: u8,
a: u8,

// Basics
pub const white = Self.fromRGB(0xFFFFFF);
pub const red = Self.fromRGB(0xFF0000);
pub const green = Self.fromRGB(0x00FF00);
pub const blue = Self.fromRGB(0x0000FF);
pub const cyan = Self.fromRGB(0x00FFFF);
pub const magenta = Self.fromRGB(0xFF00FF);
pub const orange = Self.fromRGB(0xFF8000);
pub const purple = Self.fromRGB(0x800080);
pub const pink = Self.fromRGB(0xFF69B4);
pub const brown = Self.fromRGB(0x8B4513);

// Greys
pub const light_grey = Self.fromRGB(0xD3D3D3);
pub const grey = Self.fromRGB(0x808080);
pub const dark_grey = Self.fromRGB(0x404040);

// With alpha
pub const semi_transparent_black = Self{ .r = 0, .g = 0, .b = 0, .a = 128 };
pub const semi_transparent_white = Self{ .r = 255, .g = 255, .b = 255, .a = 128 };

pub fn lerp(self: Self, other: Self, t: f32) Self {
    const fr: f32 = @floatFromInt(self.r);
    const fg: f32 = @floatFromInt(self.g);
    const fb: f32 = @floatFromInt(self.b);
    const fa: f32 = @floatFromInt(self.a);

    const fr2: f32 = @floatFromInt(other.r);
    const fg2: f32 = @floatFromInt(other.g);
    const fb2: f32 = @floatFromInt(other.b);
    const fa2: f32 = @floatFromInt(other.a);

    return .{
        .r = @intFromFloat(fr + t * (fr2 - fr)),
        .g = @intFromFloat(fg + t * (fg2 - fg)),
        .b = @intFromFloat(fb + t * (fb2 - fb)),
        .a = @intFromFloat(fa + t * (fa2 - fa)),
    };
}

pub fn fromRGB(value: u32) Self {
    return .{
        .r = @truncate(value >> 16),
        .g = @truncate(value >> 8),
        .b = @truncate(value),
        .a = 255,
    };
}

pub fn fromHex(hex: u32) Self {
    return .{
        .r = @truncate(hex >> 24),
        .g = @truncate(hex >> 16),
        .b = @truncate(hex >> 8),
        .a = @truncate(hex),
    };
}

pub fn fromRGBA(value: u32) Self {
    return .{
        .r = @truncate(value >> 24),
        .g = @truncate(value >> 16),
        .b = @truncate(value >> 8),
        .a = @truncate(value),
    };
}

pub fn fromAGBR(value: u32) Self {
    return .{
        .a = @truncate(value >> 24),
        .b = @truncate(value >> 16),
        .g = @truncate(value >> 8),
        .r = @truncate(value),
    };
}

pub fn toABGR(self: Self) u32 {
    return (@as(u32, self.a) << 24) | (@as(u32, self.b) << 16) | (@as(u32, self.g) << 8) | @as(u32, self.r);
}

pub fn toRGBA(self: Self) u32 {
    return (@as(u32, self.r) << 24) | (@as(u32, self.g) << 16) | (@as(u32, self.b) << 8) | @as(u32, self.a);
}
