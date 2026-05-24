const Vec3 = @import("vec.zig").Vec3;
const Vec4 = @import("vec.zig").Vec4;
const Mat4 = @import("mat.zig").Mat4;

pub fn mul(a: Vec4, b: Vec4) Vec4 {
    return .{
        .x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        .y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
        .z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
        .w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
    };
}

pub fn fromAxisAngle(axis: Vec3, angle: f32) Vec4 {
    const half = angle * 0.5;
    const s = @sin(half);
    return .{
        .x = axis.x * s,
        .y = axis.y * s,
        .z = axis.z * s,
        .w = @cos(half),
    };
}

pub fn toMat4(q: Vec4) Mat4 {
    const x2 = q.x + q.x;
    const y2 = q.y + q.y;
    const z2 = q.z + q.z;
    const xx = q.x * x2;
    const xy = q.x * y2;
    const xz = q.x * z2;
    const yy = q.y * y2;
    const yz = q.y * z2;
    const zz = q.z * z2;
    const wx = q.w * x2;
    const wy = q.w * y2;
    const wz = q.w * z2;
    return Mat4{
        .m = .{
            1.0 - (yy + zz), xy + wz, xz - wy, 0.0,
            xy - wz, 1.0 - (xx + zz), yz + wx, 0.0,
            xz + wy, yz - wx, 1.0 - (xx + yy), 0.0,
            0.0, 0.0, 0.0, 1.0,
        },
    };
}

pub fn fromEuler(yaw: f32, pitch: f32, roll: f32) Vec4 {
    const cy = @cos(yaw * 0.5);
    const sy = @sin(yaw * 0.5);
    const cp = @cos(pitch * 0.5);
    const sp = @sin(pitch * 0.5);
    const cr = @cos(roll * 0.5);
    const sr = @sin(roll * 0.5);

    return .{
        .w = cr * cp * cy + sr * sp * sy,
        .x = sr * cp * cy - cr * sp * sy,
        .y = cr * sp * cy + sr * cp * sy,
        .z = cr * cp * sy - sr * sp * cy,
    };
}
