const math = @import("math");
const ecs = @import("ecs");
const renderer = @import("renderer");

pub const ui = @import("ui.zig");

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
pub const Parent = struct {
    entity: ecs.Entity,
};

/// Computed world-space transform matrix.
pub const GlobalTransform = struct {
    value: math.Mat4,
};

pub const Text = struct {
    value: [256]u8,
    len: usize,
    font: renderer.Font.Pool.Handle,
    size: f32,
    color: math.Color,
};
