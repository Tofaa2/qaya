const std = @import("std");
pub const vec = @import("vec.zig");
pub const mat = @import("mat.zig");
pub const shapes = @import("shapes.zig");

pub const Vec2 = vec.Vec2;
pub const Vec3 = vec.Vec3;
pub const Vec4 = vec.Vec4;

pub const Mat4 = mat.Mat4;
pub const Mat3 = mat.Mat3;
pub const Mat2 = mat.Mat2;

pub const Rect = shapes.Rect;
pub const RectI = shapes.Rect(i32);
pub const RectU = shapes.Rect(u32);
pub const Sphere = shapes.Sphere;
pub const AABB = shapes.AABB;
pub const Ray = shapes.Ray;
pub const Plane = shapes.Plane;
pub const Frustum = shapes.Frustum;
pub const Capsule = shapes.Capsule;
pub const Triangle = shapes.Triangle;
pub const Line = shapes.Line;
pub const Color = @import("Color.zig");
pub const Camera = @import("Camera.zig");
pub const Transform = @import("Transform.zig");
pub const quat = @import("quat.zig");

pub const lerp = vec.lerp;
pub const clamp = vec.clamp;
pub const smoothstep = vec.smoothstep;
pub const min = vec.min;
pub const max = vec.max;
pub const abs = vec.abs;
pub const floor = vec.floor;
pub const ceil = vec.ceil;
pub const round = vec.round;
pub const sign = vec.sign;
pub const fract = vec.fract;

pub fn toRad(deg: f32) f32 {
    return deg * (std.math.pi / 180.0);
}

pub fn toDeg(rad: f32) f32 {
    return rad * (180.0 / std.math.pi);
}
