const math = @import("math");
const renderer = @import("renderer");

pub const MainCamera = struct {};
pub const Camera = math.Camera;
pub const Transform = math.Transform;
pub const RenderVisible = struct {};
pub const MeshComponent = struct {
    value: renderer.Mesh.Handle,
    material: renderer.Material.Pool.Handle,
};
pub const Light = struct {
    direction: math.Vec3,
    color: math.Color,
    intensity: f32,
};
