const math = @import("math");
const ecs = @import("ecs");
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

/// Marks an entity as a child of another entity.
/// The transform will be computed relative to the parent.
pub const Parent = struct {
    entity: ecs.Entity,
};

/// Computed world-space transform matrix.
/// Updated by the HierarchyPlugin's propagateTransforms system.
pub const GlobalTransform = struct {
    value: math.Mat4,
};
