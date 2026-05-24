const math = @import("math");

pub const PosColor = struct {
    position: math.Vec3,
    color0: math.Color,
};

pub const PosColorTex = struct {
    position: math.Vec3,
    color0: math.Color,
    texcoord0: math.Vec2,
};

pub const PosTex = struct {
    position: math.Vec3,
    texcoord0: math.Vec2,
};

pub const PosNormalTex = struct {
    position: math.Vec3,
    normal: math.Vec3,
    texcoord0: math.Vec2,
    color0: math.Color,
};
