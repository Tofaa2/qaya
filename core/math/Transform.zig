const Self = @This();
const vec = @import("vec.zig");
const mat = @import("mat.zig");

position: vec.Vec3 = vec.Vec3.zero(),
rotation: vec.Vec4 = vec.Vec4{ .x = 0, .y = 0, .z = 0, .w = 1 },
scale: vec.Vec3 = vec.Vec3.one(),

pub fn toMatrixMat4(self: Self) mat.Mat4 {
    const mtx = self.toMatrix();
    return mat.Mat4.fromArray(mtx);
}

pub fn toMatrix(self: Self) [16]f32 {
    const p = self.position;
    const r = self.rotation;
    const s = self.scale;

    // Pre-calculate rotation components for efficiency
    const x2 = r.x + r.x;
    const y2 = r.y + r.y;
    const z2 = r.z + r.z;
    const xx = r.x * x2;
    const xy = r.x * y2;
    const xz = r.x * z2;
    const yy = r.y * y2;
    const yz = r.y * z2;
    const zz = r.z * z2;
    const wx = r.w * x2;
    const wy = r.w * y2;
    const wz = r.w * z2;

    return [16]f32{
        // Row 0: Right vector * scale.x
        (1.0 - (yy + zz)) * s.x,
        (xy + wz) * s.x,
        (xz - wy) * s.x,
        0.0,

        // Row 1: Up vector * scale.y
        (xy - wz) * s.y,
        (1.0 - (xx + zz)) * s.y,
        (yz + wx) * s.y,
        0.0,

        // Row 2: Forward vector * scale.z
        (xz + wy) * s.z,
        (yz - wx) * s.z,
        (1.0 - (xx + yy)) * s.z,
        0.0,

        // Row 3: Translation
        p.x,
        p.y,
        p.z,
        1.0,
    };
}
