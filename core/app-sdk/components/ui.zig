const math = @import("math");
const ecs = @import("ecs");
const renderer = @import("renderer");

// ── Flexbox layout types ──

pub const UiDirection = enum { row, column };
pub const UiWrap = enum { no_wrap, wrap };
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
    wrap: UiWrap = .no_wrap,
    justify_content: UiJustify = .start,
    align_items: UiAlign = .stretch,
    gap: f32 = 0,
    z_index: i32 = 0,
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

/// Offset applied when syncing ComputedLayout → Transform for text entities.
pub const UiTextOffset = struct {
    x: f32 = 0,
    y: f32 = 0,
};

/// Interaction state for a UI element (hit-tested each frame).
pub const UiInteraction = enum(u8) {
    none,
    hovered,
    pressed,
};

/// Callback invoked when a UI element is clicked (UiInteraction == .pressed).
pub const ClickAction = struct {
    callback: *const fn (world: *ecs.World) void,
};

/// Scroll offset for a scrollable UI container.
pub const Scroll = struct {
    offset_x: f32 = 0,
    offset_y: f32 = 0,
    /// Total content height (for scrollbar thumb sizing).
    content_height: f32 = 0,
    /// Whether the user is currently dragging the scrollbar thumb.
    thumb_dragging: bool = false,
    /// Y-offset within the thumb where the drag started.
    thumb_drag_offset: f32 = 0,
};

/// Renders a textured quad (instead of a solid color) using the `textured` shader program.
pub const UiImage = struct {
    texture: renderer.Texture.Pool.Handle,
};

/// Input state for a text field. Requires `Text` + `ComputedLayout`.
pub const UiTextInput = struct {
    cursor: usize = 0,
    focused: bool = false,
    /// Set to true after the user first edits the field (clears placeholder).
    dirty: bool = false,
    /// Invoked when Enter is pressed while focused. Receives current text.
    on_submit: ?*const fn (world: *ecs.World, text: []const u8) void = null,
};

// ── New primitives ──

/// Draws a border (4 edge rects) around the element.
pub const UiBorder = struct {
    width: UiEdge = .{},
    color: math.Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
};

/// Rounded corners. Rendering requires a round-rect SDF shader (TODO).
pub const UiCornerRadius = struct {
    top_left: f32 = 0,
    top_right: f32 = 0,
    bottom_left: f32 = 0,
    bottom_right: f32 = 0,
};

/// How overflow content is handled.
pub const UiOverflow = enum { visible, hidden, scroll };

/// Whether the UI element is rendered at all.
pub const UiVisibility = struct {
    visible: bool = true,
};

/// Grid layout primitive. Layout algorithm is TODO; for now a placeholder.
pub const UiGrid = struct {
    columns: usize,
    column_gap: f32 = 0,
    row_gap: f32 = 0,
};
