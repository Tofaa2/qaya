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

// ── UI system ──

pub const UiDirection = enum { row, column };
pub const UiJustify = enum { start, center, end, space_between, space_around };
pub const UiAlign = enum { start, center, end, stretch };

pub const UiEdge = struct {
    top: f32 = 0,
    right: f32 = 0,
    bottom: f32 = 0,
    left: f32 = 0,
};

/// Flexbox-style layout properties for a UI node.
pub const UiNode = struct {
    width: f32 = 0,
    height: f32 = 0,
    min_width: f32 = 0,
    min_height: f32 = 0,
    flex_grow: f32 = 0,
    flex_shrink: f32 = 1,
    margin: UiEdge = .{},
    padding: UiEdge = .{},
    direction: UiDirection = .column,
    justify_content: UiJustify = .start,
    align_items: UiAlign = .stretch,
    gap: f32 = 0,
};

/// Output of the layout system – the resolved screen-space rectangle.
pub const ComputedLayout = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

/// Renders a colored rectangle behind the node.
pub const UiBackground = struct {
    color: math.Color,
};

/// Interaction state for a UI element (hit-tested each frame).
pub const UiInteraction = enum(u8) {
    none,
    hovered,
    pressed,
};
