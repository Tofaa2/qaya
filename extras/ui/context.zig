const std = @import("std");
const math = @import("math");
const renderer = @import("renderer");

pub const ROOTLIST_SIZE = 32;
pub const CONTAINERSTACK_SIZE = 32;
pub const CLIPSTACK_SIZE = 32;
pub const IDSTACK_SIZE = 32;
pub const LAYOUTSTACK_SIZE = 16;
pub const CONTAINERPOOL_SIZE = 48;
pub const TREENODEPOOL_SIZE = 48;
pub const MAX_WIDTHS = 16;
pub const MAX_FMT = 127;

pub const Id = u32;
pub const Real = f32;
pub const Font = *const renderer.Font;

pub const ColorId = enum(usize) {
    text = 0,
    border,
    window_bg,
    title_bg,
    title_text,
    panel_bg,
    button,
    button_hover,
    button_focus,
    base,
    base_hover,
    base_focus,
    scroll_base,
    scroll_thumb,

    pub const count = 14;
};

pub const IconId = enum(i32) {
    close = 1,
    check = 2,
    collapsed = 3,
    expanded = 4,
    _max = 5,
};

pub const Result = packed struct(u3) {
    active: bool = false,
    submit: bool = false,
    change: bool = false,

    pub fn isZero(self: @This()) bool {
        return @as(u3, @bitCast(self)) == 0;
    }
};

pub const Options = packed struct(u13) {
    align_center: bool = false,
    align_right: bool = false,
    no_interact: bool = false,
    no_frame: bool = false,
    no_resize: bool = false,
    no_scroll: bool = false,
    no_close: bool = false,
    no_title: bool = false,
    hold_focus: bool = false,
    auto_size: bool = false,
    popup: bool = false,
    closed: bool = false,
    expanded: bool = false,

    pub fn merge(self: @This(), other: @This()) @This() {
        return @bitCast(@as(u13, @bitCast(self)) | @as(u13, @bitCast(other)));
    }
};

pub const MouseButtons = packed struct(u3) {
    left: bool = false,
    right: bool = false,
    middle: bool = false,

    pub fn onlyLeft(self: @This()) bool {
        return self.left and !self.right and !self.middle;
    }
};

pub const Keys = packed struct(u5) {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    backspace: bool = false,
    enter: bool = false,
};

pub const ClipStatus = enum(i32) {
    inside = 0,
    partial = 1,
    outside = 2,
};

pub const Vec2 = math.Vec2;
pub const Rect = math.Rect(f32);
pub const Color = math.Color;

pub const PoolItem = struct {
    id: Id,
    last_update: i32,
};

pub const Command = union(enum) {
    clip: struct { rect: Rect },
    rect: struct { rect: Rect, color: Color },
    text: struct { font: Font, pos: Vec2, color: Color, str: []const u8 },
    icon: struct { id: IconId, rect: Rect, color: Color },
};

pub const Layout = struct {
    body: Rect,
    next: Rect,
    position: Vec2,
    size: Vec2,
    max: Vec2,
    widths: [MAX_WIDTHS]f32,
    items: i32,
    item_index: i32,
    next_row: f32,
    next_type: i32,
    indent: f32,
};

pub const Container = struct {
    rect: Rect,
    body: Rect,
    content_size: Vec2,
    scroll: Vec2,
    zindex: i32,
    open: i32,
};

pub const Style = struct {
    font: Font,
    size: Vec2,
    padding: i32,
    spacing: i32,
    indent: i32,
    title_height: i32,
    scrollbar_size: i32,
    thumb_size: i32,
    colors: [ColorId.count]Color,
};

const RELATIVE = 1;
const ABSOLUTE = 2;

const unclipped_rect = Rect{
    .x = 0,
    .y = 0,
    .width = 0x1000000,
    .height = 0x1000000,
};

const default_style = Style{
    .font = undefined,
    .size = Vec2{ .x = 68, .y = 10 },
    .padding = 5,
    .spacing = 4,
    .indent = 24,
    .title_height = 24,
    .scrollbar_size = 12,
    .thumb_size = 8,
    .colors = [_]Color{
        Color{ .r = 230, .g = 230, .b = 230, .a = 255 },
        Color{ .r = 25, .g = 25, .b = 25, .a = 255 },
        Color{ .r = 50, .g = 50, .b = 50, .a = 255 },
        Color{ .r = 25, .g = 25, .b = 25, .a = 255 },
        Color{ .r = 240, .g = 240, .b = 240, .a = 255 },
        Color{ .r = 0, .g = 0, .b = 0, .a = 0 },
        Color{ .r = 75, .g = 75, .b = 75, .a = 255 },
        Color{ .r = 95, .g = 95, .b = 95, .a = 255 },
        Color{ .r = 115, .g = 115, .b = 115, .a = 255 },
        Color{ .r = 30, .g = 30, .b = 30, .a = 255 },
        Color{ .r = 35, .g = 35, .b = 35, .a = 255 },
        Color{ .r = 40, .g = 40, .b = 40, .a = 255 },
        Color{ .r = 43, .g = 43, .b = 43, .a = 255 },
        Color{ .r = 30, .g = 30, .b = 30, .a = 255 },
    },
};

fn expect(ok: bool) void {
    if (!ok) @panic("ui assertion failed");
}

fn clamp(x: f32, a: f32, b: f32) f32 {
    return @min(b, @max(a, x));
}

fn textWidth(font: Font, str: [*:0]const u8, len: i32) i32 {
    const actual_len: usize = if (len < 0) std.mem.len(str) else @intCast(len);
    return @intFromFloat(renderer.Text.measureText(font, str[0..actual_len], font.size).width);
}

fn textHeight(font: Font) i32 {
    return @intFromFloat(font.ascent);
}

fn initVec2(x: i32, y: i32) Vec2 {
    return Vec2{ .x = @floatFromInt(x), .y = @floatFromInt(y) };
}
fn initRect(x: i32, y: i32, w: i32, h: i32) Rect {
    return Rect{ .x = @floatFromInt(x), .y = @floatFromInt(y), .width = @floatFromInt(w), .height = @floatFromInt(h) };
}
fn initColor(r: i32, g: i32, b: i32, a: i32) Color {
    return Color{ .r = @intCast(r), .g = @intCast(g), .b = @intCast(b), .a = @intCast(a) };
}

fn expandRect(rect: Rect, n: i32) Rect {
    const fn_ = @as(f32, @floatFromInt(n));
    const fn2 = @as(f32, @floatFromInt(n * 2));
    return Rect{ .x = rect.x - fn_, .y = rect.y - fn_, .width = rect.width + fn2, .height = rect.height + fn2 };
}

fn intersectRects(r1: Rect, r2: Rect) Rect {
    const x1 = @max(r1.x, r2.x);
    const y1 = @max(r1.y, r2.y);
    var x2 = @min(r1.x + r1.width, r2.x + r2.width);
    var y2 = @min(r1.y + r1.height, r2.y + r2.height);
    if (x2 < x1) x2 = x1;
    if (y2 < y1) y2 = y1;
    return Rect{ .x = x1, .y = y1, .width = x2 - x1, .height = y2 - y1 };
}

fn rectOverlapsVec2(r: Rect, p: Vec2) bool {
    return p.x >= r.x and p.x < r.x + r.width and p.y >= r.y and p.y < r.y + r.height;
}

const HASH_INITIAL: Id = 2166136261;

fn hashId(h: *Id, data: [*]const u8, size: i32) void {
    var i: i32 = 0;
    while (i < size) {
        h.* = (h.* ^ @as(Id, data[@intCast(i)])) *% 16777619;
        i += 1;
    }
}

fn defaultDrawFrame(ctx: *Context, rect: Rect, colorid: ColorId) void {
    ctx.drawRect(rect, ctx.style.colors[@intFromEnum(colorid)]);
    if (colorid == .scroll_base or colorid == .scroll_thumb or colorid == .title_bg) return;
    if (ctx.style.colors[@intFromEnum(ColorId.border)].a != 0) {
        ctx.drawBox(expandRect(rect, 1), ctx.style.colors[@intFromEnum(ColorId.border)]);
    }
}

fn lessThanByZIndex(_: void, a: *Container, b: *Container) bool {
    return a.zindex < b.zindex;
}

pub const Context = struct {
    allocator: std.mem.Allocator,
    style: Style,
    hover: Id,
    focus: Id,
    last_id: Id,
    last_rect: Rect,
    last_zindex: i32,
    updated_focus: i32,
    frame: i32,
    hover_root: ?*Container,
    next_hover_root: ?*Container,
    scroll_target: ?*Container,
    number_edit_buf: [MAX_FMT]u8,
    number_edit: Id,
    command_list: std.ArrayList(Command),
    string_data: std.ArrayList(u8),
    root_list: std.ArrayList(*Container),
    container_stack: std.ArrayList(*Container),
    clip_stack: std.ArrayList(Rect),
    id_stack: std.ArrayList(Id),
    layout_stack: std.ArrayList(Layout),
    container_pool: [CONTAINERPOOL_SIZE]PoolItem,
    containers: [CONTAINERPOOL_SIZE]Container,
    treenode_pool: [TREENODEPOOL_SIZE]PoolItem,
    mouse_pos: Vec2,
    last_mouse_pos: Vec2,
    mouse_delta: Vec2,
    scroll_delta: Vec2,
    mouse_down: MouseButtons,
    mouse_pressed: MouseButtons,
    key_down: Keys,
    key_pressed: Keys,
    input_text: [32]u8,

    pub fn init(self: *Context) void {
        self.* = .{
            .allocator = self.allocator,
            .style = default_style,
            .hover = 0,
            .focus = 0,
            .last_id = 0,
            .last_rect = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 },
            .last_zindex = 0,
            .updated_focus = 0,
            .frame = 0,
            .hover_root = null,
            .next_hover_root = null,
            .scroll_target = null,
            .number_edit_buf = [_]u8{0} ** MAX_FMT,
            .number_edit = 0,
            .command_list = .empty,
            .string_data = .empty,
            .root_list = .empty,
            .container_stack = .empty,
            .clip_stack = .empty,
            .id_stack = .empty,
            .layout_stack = .empty,
            .container_pool = [_]PoolItem{PoolItem{ .id = 0, .last_update = 0 }} ** CONTAINERPOOL_SIZE,
            .containers = [_]Container{undefined} ** CONTAINERPOOL_SIZE,
            .treenode_pool = [_]PoolItem{PoolItem{ .id = 0, .last_update = 0 }} ** TREENODEPOOL_SIZE,
            .mouse_pos = Vec2{ .x = 0, .y = 0 },
            .last_mouse_pos = Vec2{ .x = 0, .y = 0 },
            .mouse_delta = Vec2{ .x = 0, .y = 0 },
            .scroll_delta = Vec2{ .x = 0, .y = 0 },
            .mouse_down = .{},
            .mouse_pressed = .{},
            .key_down = .{},
            .key_pressed = .{},
            .input_text = [_]u8{0} ** 32,
        };
    }

    pub fn deinit(self: *Context) void {
        self.command_list.deinit(self.allocator);
        self.string_data.deinit(self.allocator);
        self.root_list.deinit(self.allocator);
        self.container_stack.deinit(self.allocator);
        self.clip_stack.deinit(self.allocator);
        self.id_stack.deinit(self.allocator);
        self.layout_stack.deinit(self.allocator);
    }

    pub fn begin(self: *Context) void {
        self.command_list.clearRetainingCapacity();
        self.string_data.clearRetainingCapacity();
        self.root_list.clearRetainingCapacity();
        self.scroll_target = null;
        self.hover_root = self.next_hover_root;
        self.next_hover_root = null;
        self.mouse_delta.x = self.mouse_pos.x - self.last_mouse_pos.x;
        self.mouse_delta.y = self.mouse_pos.y - self.last_mouse_pos.y;
        self.frame += 1;
    }

    pub fn end(self: *Context) void {
        expect(self.container_stack.items.len == 0);
        expect(self.clip_stack.items.len == 0);
        expect(self.id_stack.items.len == 0);
        expect(self.layout_stack.items.len == 0);
        if (self.scroll_target) |st| {
            st.scroll.x += self.scroll_delta.x;
            st.scroll.y += self.scroll_delta.y;
        }
        if (self.updated_focus == 0) self.focus = 0;
        self.updated_focus = 0;
        if (@as(u3, @bitCast(self.mouse_pressed)) != 0 and self.next_hover_root != null and
            self.next_hover_root.?.zindex < self.last_zindex and
            self.next_hover_root.?.zindex >= 0)
        {
            self.bringToFront(self.next_hover_root.?);
        }
        self.key_pressed = .{};
        self.input_text[0] = 0;
        self.mouse_pressed = .{};
        self.scroll_delta = Vec2{ .x = 0, .y = 0 };
        self.last_mouse_pos = self.mouse_pos;
        std.sort.block(*Container, self.root_list.items, {}, lessThanByZIndex);
    }

    pub fn setFocus(self: *Context, id: Id) void {
        self.focus = id;
        self.updated_focus = 1;
    }

    pub fn getId(self: *Context, data: [*]const u8, size: i32) Id {
        const idx = self.id_stack.items.len;
        var res: Id = if (idx > 0) self.id_stack.items[idx - 1] else HASH_INITIAL;
        hashId(&res, data, size);
        self.last_id = res;
        return res;
    }

    pub fn pushId(self: *Context, data: [*]const u8, size: i32) void {
        self.id_stack.append(self.allocator, self.getId(data, size)) catch unreachable;
    }

    pub fn popId(self: *Context) void {
        _ = self.id_stack.pop();
    }

    pub fn pushClipRect(self: *Context, rect: Rect) void {
        const last = self.getClipRect();
        self.clip_stack.append(self.allocator, intersectRects(rect, last)) catch unreachable;
    }

    pub fn popClipRect(self: *Context) void {
        _ = self.clip_stack.pop();
    }

    pub fn getClipRect(self: *Context) Rect {
        expect(self.clip_stack.items.len > 0);
        return self.clip_stack.getLast();
    }

    pub fn checkClip(self: *Context, r: Rect) ClipStatus {
        const cr = self.getClipRect();
        if (r.x > cr.x + cr.width or r.x + r.width < cr.x or
            r.y > cr.y + cr.height or r.y + r.height < cr.y) return .outside;
        if (r.x >= cr.x and r.x + r.width <= cr.x + cr.width and
            r.y >= cr.y and r.y + r.height <= cr.y + cr.height) return .inside;
        return .partial;
    }

    pub fn getCurrentContainer(self: *Context) *Container {
        expect(self.container_stack.items.len > 0);
        return self.container_stack.getLast();
    }

    pub fn getContainer(self: *Context, name: [:0]const u8) ?*Container {
        const id = self.getId(name.ptr, @intCast(name.len));
        return self.getContainerById(id, .{});
    }

    pub fn bringToFront(self: *Context, cnt: *Container) void {
        self.last_zindex += 1;
        cnt.zindex = self.last_zindex;
    }

    pub fn poolInit(self: *Context, items: []PoolItem, len: usize, id: Id) i32 {
        _ = len;
        var n: i32 = -1;
        var f = self.frame;
        for (items, 0..) |item, i| {
            if (item.last_update < f) {
                f = item.last_update;
                n = @intCast(i);
            }
        }
        expect(n > -1);
        items[@intCast(n)].id = id;
        self.poolUpdate(items, n);
        return n;
    }

    pub fn poolGet(self: *Context, items: []PoolItem, len: usize, id: Id) i32 {
        _ = self;
        _ = len;
        for (items, 0..) |item, i| {
            if (item.id == id) return @intCast(i);
        }
        return -1;
    }

    pub fn poolUpdate(self: *Context, items: []PoolItem, idx: i32) void {
        items[@intCast(idx)].last_update = self.frame;
    }

    pub fn inputMouseMove(self: *Context, x: i32, y: i32) void {
        self.mouse_pos = initVec2(x, y);
    }

    pub fn inputMouseDown(self: *Context, x: i32, y: i32, btn: MouseButtons) void {
        self.inputMouseMove(x, y);
        self.mouse_down = @bitCast(@as(u3, @bitCast(self.mouse_down)) | @as(u3, @bitCast(btn)));
        self.mouse_pressed = @bitCast(@as(u3, @bitCast(self.mouse_pressed)) | @as(u3, @bitCast(btn)));
    }

    pub fn inputMouseUp(self: *Context, x: i32, y: i32, btn: MouseButtons) void {
        self.inputMouseMove(x, y);
        self.mouse_down = @bitCast(@as(u3, @bitCast(self.mouse_down)) & ~@as(u3, @bitCast(btn)));
    }

    pub fn inputScroll(self: *Context, x: i32, y: i32) void {
        self.scroll_delta.x += @floatFromInt(x);
        self.scroll_delta.y += @floatFromInt(y);
    }

    pub fn inputKeyDown(self: *Context, key: Keys) void {
        self.key_pressed = @bitCast(@as(u5, @bitCast(self.key_pressed)) | @as(u5, @bitCast(key)));
        self.key_down = @bitCast(@as(u5, @bitCast(self.key_down)) | @as(u5, @bitCast(key)));
    }

    pub fn inputKeyUp(self: *Context, key: Keys) void {
        self.key_down = @bitCast(@as(u5, @bitCast(self.key_down)) & ~@as(u5, @bitCast(key)));
    }

    pub fn inputText(self: *Context, txt: [*:0]const u8) void {
        var len: usize = 0;
        while (len < self.input_text.len and self.input_text[len] != 0) len += 1;
        const text_len = std.mem.len(txt);
        const size = text_len + 1;
        expect(len + size <= self.input_text.len);
        @memcpy(self.input_text[len..][0..text_len], txt[0..text_len]);
        self.input_text[len + text_len] = 0;
    }

    pub fn setClip(self: *Context, rect: Rect) void {
        self.command_list.append(self.allocator, .{ .clip = .{ .rect = rect } }) catch unreachable;
    }

    pub fn drawRect(self: *Context, rect: Rect, color: Color) void {
        const r = intersectRects(rect, self.getClipRect());
        if (r.width > 0 and r.height > 0) {
            self.command_list.append(self.allocator, .{ .rect = .{ .rect = r, .color = color } }) catch unreachable;
        }
    }

    pub fn drawBox(self: *Context, rect: Rect, color: Color) void {
        self.drawRect(Rect{ .x = rect.x + 1, .y = rect.y, .width = rect.width - 2, .height = 1 }, color);
        self.drawRect(Rect{ .x = rect.x + 1, .y = rect.y + rect.height - 1, .width = rect.width - 2, .height = 1 }, color);
        self.drawRect(Rect{ .x = rect.x, .y = rect.y, .width = 1, .height = rect.height }, color);
        self.drawRect(Rect{ .x = rect.x + rect.width - 1, .y = rect.y, .width = 1, .height = rect.height }, color);
    }

    pub fn drawText(self: *Context, font: Font, str: [*:0]const u8, len: i32, pos: Vec2, color: Color) void {
        const tw = textWidth(font, str, len);
        const th = textHeight(font);
        const rect = Rect{ .x = pos.x, .y = pos.y, .width = @floatFromInt(tw), .height = @floatFromInt(th) };
        const clipped = self.checkClip(rect);
        if (clipped == .outside) return;
        if (clipped == .partial) self.setClip(self.getClipRect());
        var actual_len = len;
        if (actual_len < 0) actual_len = @intCast(std.mem.len(str));
        const start = self.string_data.items.len;
        self.string_data.appendSlice(self.allocator, str[0..@as(usize, @intCast(actual_len))]) catch unreachable;
        self.string_data.append(self.allocator, 0) catch unreachable;
        self.command_list.append(self.allocator, .{
            .text = .{ .font = font, .pos = pos, .color = color, .str = self.string_data.items[start .. start + @as(usize, @intCast(actual_len))] },
        }) catch unreachable;
        if (clipped != .inside) self.setClip(unclipped_rect);
    }

    pub fn drawIcon(self: *Context, id: IconId, rect: Rect, color: Color) void {
        const clipped = self.checkClip(rect);
        if (clipped == .outside) return;
        if (clipped == .partial) self.setClip(self.getClipRect());
        self.command_list.append(self.allocator, .{ .icon = .{ .id = id, .rect = rect, .color = color } }) catch unreachable;
        if (clipped != .inside) self.setClip(unclipped_rect);
    }

    pub fn layoutRow(self: *Context, items: i32, widths: ?[*]const f32, height: f32) void {
        const layout = self.getLayout();
        if (widths) |w| {
            expect(items <= MAX_WIDTHS);
            @memcpy(layout.widths[0..@intCast(items)], w[0..@intCast(items)]);
        }
        layout.items = items;
        layout.position = Vec2{ .x = layout.indent, .y = layout.next_row };
        layout.size.y = height;
        layout.item_index = 0;
    }

    pub fn layoutWidth(self: *Context, width: f32) void {
        self.getLayout().size.x = width;
    }

    pub fn layoutHeight(self: *Context, height: f32) void {
        self.getLayout().size.y = height;
    }

    pub fn layoutBeginColumn(self: *Context) void {
        self.pushLayout(self.layoutNext(), Vec2{ .x = 0, .y = 0 });
    }

    pub fn layoutEndColumn(self: *Context) void {
        const b = self.getLayout();
        _ = self.layout_stack.pop();
        const a = self.getLayout();
        a.position.x = @max(a.position.x, b.position.x + b.body.x - a.body.x);
        a.next_row = @max(a.next_row, b.next_row + b.body.y - a.body.y);
        a.max.x = @max(a.max.x, b.max.x);
        a.max.y = @max(a.max.y, b.max.y);
    }

    pub fn layoutSetNext(self: *Context, r: Rect, relative: i32) void {
        const layout = self.getLayout();
        layout.next = r;
        layout.next_type = if (relative != 0) RELATIVE else ABSOLUTE;
    }

    pub fn layoutNext(self: *Context) Rect {
        const layout = self.getLayout();
        const style = self.style;
        var res: Rect = undefined;

        if (layout.next_type != 0) {
            const typ = layout.next_type;
            layout.next_type = 0;
            res = layout.next;
            if (typ == ABSOLUTE) {
                self.last_rect = res;
                return res;
            }
        } else {
            if (layout.item_index == layout.items) {
                self.layoutRow(layout.items, null, layout.size.y);
            }
            res.x = layout.position.x;
            res.y = layout.position.y;
            res.width = if (layout.items > 0) layout.widths[@intCast(layout.item_index)] else layout.size.x;
            res.height = layout.size.y;
            if (res.width == 0) res.width = style.size.x + @as(f32, @floatFromInt(style.padding * 2));
            if (res.height == 0) res.height = style.size.y + @as(f32, @floatFromInt(style.padding * 2));
            if (res.width < 0) res.width += layout.body.width - res.x + 1;
            if (res.height < 0) res.height += layout.body.height - res.y + 1;
            layout.item_index += 1;
        }

        layout.position.x += res.width + @as(f32, @floatFromInt(style.spacing));
        layout.next_row = @max(layout.next_row, res.y + res.height + @as(f32, @floatFromInt(style.spacing)));

        res.x += layout.body.x;
        res.y += layout.body.y;

        layout.max.x = @max(layout.max.x, res.x + res.width);
        layout.max.y = @max(layout.max.y, res.y + res.height);

        self.last_rect = res;
        return res;
    }

    pub fn drawControlFrame(self: *Context, id: Id, rect: Rect, colorid: ColorId, opt: Options) void {
        if (opt.no_frame) return;
        const offset: usize = if (self.focus == id) 2 else if (self.hover == id) 1 else 0;
        defaultDrawFrame(self, rect, @enumFromInt(@intFromEnum(colorid) + offset));
    }

    pub fn drawControlText(self: *Context, str: [:0]const u8, rect: Rect, colorid: ColorId, opt: Options) void {
        const font = self.style.font;
        const tw = textWidth(font, str.ptr, -1);
        const th = textHeight(font);
        self.pushClipRect(rect);
        var pos: Vec2 = undefined;
        pos.y = rect.y + (rect.height - @as(f32, @floatFromInt(th))) / 2;
        if (opt.align_center) {
            pos.x = rect.x + (rect.width - @as(f32, @floatFromInt(tw))) / 2;
        } else if (opt.align_right) {
            pos.x = rect.x + rect.width - @as(f32, @floatFromInt(tw)) - @as(f32, @floatFromInt(self.style.padding));
        } else {
            pos.x = rect.x + @as(f32, @floatFromInt(self.style.padding));
        }
        self.drawText(font, str.ptr, -1, pos, self.style.colors[@intFromEnum(colorid)]);
        self.popClipRect();
    }

    pub fn mouseOver(self: *Context, rect: Rect) bool {
        return rectOverlapsVec2(rect, self.mouse_pos) and
            rectOverlapsVec2(self.getClipRect(), self.mouse_pos) and
            self.inHoverRoot();
    }

    pub fn updateControl(self: *Context, id: Id, rect: Rect, opt: Options) void {
        const mouseover = self.mouseOver(rect);
        if (self.focus == id) self.updated_focus = 1;
        if (opt.no_interact) return;
        if (mouseover and @as(u3, @bitCast(self.mouse_down)) == 0) self.hover = id;
        if (self.focus == id) {
            if (@as(u3, @bitCast(self.mouse_pressed)) != 0 and !mouseover) self.setFocus(0);
            if (@as(u3, @bitCast(self.mouse_down)) == 0 and !opt.hold_focus) self.setFocus(0);
        }
        if (self.hover == id) {
            if (@as(u3, @bitCast(self.mouse_pressed)) != 0) {
                self.setFocus(id);
            } else if (!mouseover) {
                self.hover = 0;
            }
        }
    }

    pub fn text(self: *Context, txt: [:0]const u8) void {
        const font = self.style.font;
        const color = self.style.colors[@intFromEnum(ColorId.text)];
        const width: f32 = -1;
        self.layoutBeginColumn();
        self.layoutRow(1, @ptrCast(&width), @floatFromInt(textHeight(font)));
        var p: [*:0]const u8 = txt.ptr;
        while (true) {
            const r = self.layoutNext();
            var w: f32 = 0;
            const start = p;
            var end_ptr = p;
            while (true) {
                const word = p;
                while (p[0] != 0 and p[0] != ' ' and p[0] != '\n') p += 1;
                w += @floatFromInt(textWidth(font, word, @intCast(@intFromPtr(p) - @intFromPtr(word))));
                if (w > r.width and end_ptr != start) break;
                w += @floatFromInt(textWidth(font, p, 1));
                end_ptr = p;
                p += 1;
                if (end_ptr[0] == 0 or end_ptr[0] == '\n') break;
            }
            self.drawText(font, start, @intCast(@intFromPtr(end_ptr) - @intFromPtr(start)), Vec2{ .x = r.x, .y = r.y }, color);
            p = end_ptr + 1;
            if (end_ptr[0] == 0) break;
        }
        self.layoutEndColumn();
    }

    pub fn label(self: *Context, txt: [:0]const u8) void {
        self.drawControlText(txt, self.layoutNext(), .text, .{});
    }

    pub fn buttonEx(self: *Context, lbl: ?[:0]const u8, icon: ?IconId, opt: Options) Result {
        var res = Result{};
        const id = if (lbl) |l|
            self.getId(l.ptr, @intCast(l.len))
        else
            self.getId(@as([*]const u8, @ptrCast(&icon)), @sizeOf(?IconId));
        const r = self.layoutNext();
        self.updateControl(id, r, opt);
        if (self.mouse_pressed.onlyLeft() and self.focus == id) {
            res.submit = true;
        }
        self.drawControlFrame(id, r, .button, opt);
        if (lbl) |l| self.drawControlText(l, r, .text, opt);
        if (icon) |ic| self.drawIcon(ic, r, self.style.colors[@intFromEnum(ColorId.text)]);
        return res;
    }

    pub fn button(self: *Context, lbl: ?[:0]const u8) Result {
        return self.buttonEx(lbl, null, .{ .align_center = true });
    }

    pub fn checkbox(self: *Context, lbl: [:0]const u8, state: *i32) Result {
        var res = Result{};
        const id = self.getId(@as([*]const u8, @ptrCast(&state)), @sizeOf(*i32));
        const r = self.layoutNext();
        const box = Rect{ .x = r.x, .y = r.y, .width = r.height, .height = r.height };
        self.updateControl(id, r, .{});
        if (self.mouse_pressed.onlyLeft() and self.focus == id) {
            res.change = true;
            state.* = if (state.* != 0) 0 else 1;
        }
        self.drawControlFrame(id, box, .base, .{});
        if (state.* != 0) {
            self.drawIcon(.check, box, self.style.colors[@intFromEnum(ColorId.text)]);
        }
        const tr = Rect{ .x = r.x + box.width, .y = r.y, .width = r.width - box.width, .height = r.height };
        self.drawControlText(lbl, tr, .text, .{});
        return res;
    }

    pub fn textboxRaw(self: *Context, buf: []u8, bufsz: i32, id: Id, r: Rect, opt: Options) Result {
        var res = Result{};
        self.updateControl(id, r, opt.merge(.{ .hold_focus = true }));
        if (self.focus == id) {
            var len: usize = 0;
            while (len < buf.len and buf[len] != 0) len += 1;
            var input_len: usize = 0;
            while (input_len < self.input_text.len and self.input_text[input_len] != 0) input_len += 1;
            const n = @min(@as(i32, @intCast(@as(usize, @intCast(bufsz)) -% len -% 1)), @as(i32, @intCast(input_len)));
            if (n > 0) {
                @memcpy(buf[len..][0..@intCast(n)], self.input_text[0..@intCast(n)]);
                len += @intCast(n);
                buf[len] = 0;
                res.change = true;
            }
            if (self.key_pressed.backspace and len > 0) {
                len -= 1;
                while ((buf[len] & 0xc0) == 0x80 and len > 0) len -= 1;
                buf[len] = 0;
                res.change = true;
            }
            if (self.key_pressed.enter) {
                self.setFocus(0);
                res.submit = true;
            }
        }
        self.drawControlFrame(id, r, .base, opt);
        if (self.focus == id) {
            const color = self.style.colors[@intFromEnum(ColorId.text)];
            const font = self.style.font;
            var text_len: usize = 0;
            while (text_len < buf.len and buf[text_len] != 0) text_len += 1;
            const textw = textWidth(font, @ptrCast(&buf[0]), -1);
            const texth = textHeight(font);
            const ofx = r.width - @as(f32, @floatFromInt(self.style.padding)) - @as(f32, @floatFromInt(textw)) - 1;
            const textx = r.x + @min(@as(f32, @floatFromInt(ofx)), @as(f32, @floatFromInt(self.style.padding)));
            const texty = r.y + (r.height - @as(f32, @floatFromInt(texth))) / 2;
            self.pushClipRect(r);
            self.drawText(font, @ptrCast(&buf[0]), -1, Vec2{ .x = textx, .y = texty }, color);
            self.drawRect(Rect{ .x = textx + @as(f32, @floatFromInt(textw)), .y = texty, .width = 1, .height = @as(f32, @floatFromInt(texth)) }, color);
            self.popClipRect();
        } else {
            self.drawControlText(@ptrCast(&buf[0]), r, .text, opt);
        }
        return res;
    }

    pub fn textboxEx(self: *Context, buf: []u8, bufsz: i32, opt: Options) Result {
        const id = self.getId(@as([*]const u8, @ptrCast(&buf)), @sizeOf([]u8));
        const r = self.layoutNext();
        return self.textboxRaw(buf, bufsz, id, r, opt);
    }

    pub fn textbox(self: *Context, buf: []u8, bufsz: i32) Result {
        return self.textboxEx(buf, bufsz, .{});
    }

    pub fn sliderEx(self: *Context, value: *Real, low: Real, high: Real, step: Real, fmt: [:0]const u8, opt: Options) Result {
        var res = Result{};
        const last = value.*;
        var v = last;
        const id = self.getId(@as([*]const u8, @ptrCast(&value)), @sizeOf(*Real));
        const base = self.layoutNext();

        if (!self.numberTextbox(&v, base, id).isZero()) return res;

        self.updateControl(id, base, opt);

        if (self.focus == id and blk: {
            const combined = MouseButtons{
                .left = self.mouse_down.left or self.mouse_pressed.left,
                .right = self.mouse_down.right or self.mouse_pressed.right,
                .middle = self.mouse_down.middle or self.mouse_pressed.middle,
            };
            break :blk combined.onlyLeft();
        }) {
            v = low + (self.mouse_pos.x - base.x) * (high - low) / base.width;
            if (step != 0) {
                v = @as(Real, @floatFromInt(@as(i64, @intFromFloat((v + step / 2) / step)))) * step;
            }
        }
        v = @max(low, @min(high, v));
        value.* = v;
        if (last != v) res.change = true;

        self.drawControlFrame(id, base, .base, opt);
        const w = @as(f32, @floatFromInt(self.style.thumb_size));
        const x = (v - low) * (base.width - w) / (high - low);
        const thumb = Rect{ .x = base.x + x, .y = base.y, .width = w, .height = base.height };
        self.drawControlFrame(id, thumb, .button, opt);
        const buf = std.fmt.bufPrint(&[_]u8{undefined} ** MAX_FMT, fmt, .{v}) catch "?";
        self.drawControlText(@ptrCast(buf.ptr), base, .text, opt);

        return res;
    }

    pub fn slider(self: *Context, value: *Real, low: Real, high: Real) Result {
        return self.sliderEx(value, low, high, 0, "{d:.2}", .{ .align_center = true });
    }

    pub fn numberEx(self: *Context, value: *Real, step: Real, fmt: [:0]const u8, opt: Options) Result {
        var res = Result{};
        const id = self.getId(@as([*]const u8, @ptrCast(&value)), @sizeOf(*Real));
        const base = self.layoutNext();
        const last = value.*;

        if (!self.numberTextbox(value, base, id).isZero()) return res;

        self.updateControl(id, base, opt);

        if (self.focus == id and self.mouse_down.onlyLeft()) {
            value.* += self.mouse_delta.x * step;
        }
        if (value.* != last) res.change = true;

        self.drawControlFrame(id, base, .base, opt);
        const buf = std.fmt.bufPrint(&[_]u8{undefined} ** MAX_FMT, fmt, .{value.*}) catch "?";
        self.drawControlText(@ptrCast(buf.ptr), base, .text, opt);

        return res;
    }

    pub fn number(self: *Context, value: *Real, step: Real) Result {
        return self.numberEx(value, step, "{d:.2}", .{ .align_center = true });
    }

    pub fn headerEx(self: *Context, lbl: [:0]const u8, opt: Options) Result {
        return self.doHeader(lbl, 0, opt);
    }

    pub fn header(self: *Context, lbl: [:0]const u8) Result {
        return self.headerEx(lbl, .{});
    }

    pub fn beginTreenodeEx(self: *Context, lbl: [:0]const u8, opt: Options) Result {
        const res = self.doHeader(lbl, 1, opt);
        if (res.active) {
            self.getLayout().indent += @as(f32, @floatFromInt(self.style.indent));
            self.id_stack.append(self.allocator, self.last_id) catch unreachable;
        }
        return res;
    }

    pub fn beginTreenode(self: *Context, lbl: [:0]const u8) Result {
        return self.beginTreenodeEx(lbl, .{});
    }

    pub fn endTreenode(self: *Context) void {
        self.getLayout().indent -= @as(f32, @floatFromInt(self.style.indent));
        _ = self.id_stack.pop();
    }

    pub fn beginWindowEx(self: *Context, title: [:0]const u8, rect: Rect, opt: Options) Result {
        const id = self.getId(title.ptr, @intCast(title.len));
        const cnt = self.getContainerById(id, opt) orelse return .{};
        if (cnt.open == 0) return .{};
        self.id_stack.append(self.allocator, id) catch unreachable;

        if (cnt.rect.width == 0) cnt.rect = rect;
        self.container_stack.append(self.allocator, cnt) catch unreachable;
        self.root_list.append(self.allocator, cnt) catch unreachable;
        if (rectOverlapsVec2(cnt.rect, self.mouse_pos) and
            (self.next_hover_root == null or cnt.zindex > self.next_hover_root.?.zindex))
        {
            self.next_hover_root = cnt;
        }
        self.clip_stack.append(self.allocator, unclipped_rect) catch unreachable;

        const r = cnt.rect;
        const body = r;

        if (!opt.no_frame) {
            defaultDrawFrame(self, r, .window_bg);
        }

        var body_mut = body;

        if (!opt.no_title) {
            var tr = r;
            tr.height = @as(f32, @floatFromInt(self.style.title_height));
            defaultDrawFrame(self, tr, .title_bg);

            if (!opt.no_title) {
                const tid = self.getId("!title", 6);
                self.updateControl(tid, tr, opt);
                self.drawControlText(title, tr, .title_text, opt);
                if (tid == self.focus and self.mouse_down.onlyLeft()) {
                    cnt.rect.x += self.mouse_delta.x;
                    cnt.rect.y += self.mouse_delta.y;
                }
                body_mut.y += tr.height;
                body_mut.height -= tr.height;
            }

            if (!opt.no_close) {
                const cid = self.getId("!close", 6);
                const cr = Rect{ .x = tr.x + tr.width - tr.height, .y = tr.y, .width = tr.height, .height = tr.height };
                tr.width -= cr.width;
                self.drawIcon(.close, cr, self.style.colors[@intFromEnum(ColorId.title_text)]);
                self.updateControl(cid, cr, opt);
                if (self.mouse_pressed.onlyLeft() and cid == self.focus) {
                    cnt.open = 0;
                }
            }
        }

        self.pushContainerBody(cnt, body_mut, opt);

        if (!opt.no_resize) {
            const sz = @as(f32, @floatFromInt(self.style.title_height));
            const rid = self.getId("!resize", 7);
            const rr = Rect{ .x = r.x + r.width - sz, .y = r.y + r.height - sz, .width = sz, .height = sz };
            self.updateControl(rid, rr, opt);
            if (rid == self.focus and self.mouse_down.onlyLeft()) {
                cnt.rect.width = @max(96, cnt.rect.width + self.mouse_delta.x);
                cnt.rect.height = @max(64, cnt.rect.height + self.mouse_delta.y);
            }
        }

        if (opt.auto_size) {
            const layout_r = self.getLayout().body;
            cnt.rect.width = cnt.content_size.x + (cnt.rect.width - layout_r.width);
            cnt.rect.height = cnt.content_size.y + (cnt.rect.height - layout_r.height);
        }

        if (opt.popup and @as(u3, @bitCast(self.mouse_pressed)) != 0 and self.hover_root != cnt) {
            cnt.open = 0;
        }

        self.pushClipRect(cnt.body);
        return Result{ .active = true };
    }

    pub fn beginWindow(self: *Context, title: [:0]const u8, rect: Rect) Result {
        return self.beginWindowEx(title, rect, .{});
    }

    pub fn endWindow(self: *Context) void {
        self.popClipRect();
        _ = self.clip_stack.pop();
        self.popContainer();
    }

    pub fn beginRoot(self: *Context) void {
        const id = self.getId("!root", 5);
        const cnt = self.getContainerById(id, .{}) orelse return;
        if (cnt.rect.width == 0) cnt.rect = unclipped_rect;
        self.id_stack.append(self.allocator, id) catch unreachable;
        self.root_list.append(self.allocator, cnt) catch unreachable;
        if (rectOverlapsVec2(cnt.rect, self.mouse_pos) and
            (self.next_hover_root == null or cnt.zindex > self.next_hover_root.?.zindex))
        {
            self.next_hover_root = cnt;
        }
        self.clip_stack.append(self.allocator, unclipped_rect) catch unreachable;
        self.container_stack.append(self.allocator, cnt) catch unreachable;
        self.pushContainerBody(cnt, cnt.rect, .{ .no_scroll = true });
        self.pushClipRect(cnt.body);
    }

    pub fn endRoot(self: *Context) void {
        self.popClipRect();
        _ = self.clip_stack.pop();
        self.popContainer();
    }

    pub fn openPopup(self: *Context, name: [:0]const u8) void {
        const cnt = self.getContainer(name) orelse return;
        self.hover_root = cnt;
        self.next_hover_root = cnt;
        cnt.rect = Rect{ .x = self.mouse_pos.x, .y = self.mouse_pos.y, .width = 1, .height = 1 };
        cnt.open = 1;
        self.bringToFront(cnt);
    }

    pub fn beginPopup(self: *Context, name: [:0]const u8) Result {
        const opt = Options{
            .popup = true,
            .auto_size = true,
            .no_resize = true,
            .no_scroll = true,
            .no_title = true,
            .closed = true,
        };
        return self.beginWindowEx(name, Rect{ .x = 0, .y = 0, .width = 0, .height = 0 }, opt);
    }

    pub fn endPopup(self: *Context) void {
        self.endWindow();
    }

    pub fn beginPanelEx(self: *Context, name: [:0]const u8, opt: Options) void {
        self.pushId(name.ptr, @intCast(name.len));
        const cnt = self.getContainerById(self.last_id, opt) orelse return;
        cnt.rect = self.layoutNext();
        if (!opt.no_frame) {
            defaultDrawFrame(self, cnt.rect, .panel_bg);
        }
        self.container_stack.append(self.allocator, cnt) catch unreachable;
        self.pushContainerBody(cnt, cnt.rect, opt);
        self.pushClipRect(cnt.body);
    }

    pub fn beginPanel(self: *Context, name: [:0]const u8) void {
        self.beginPanelEx(name, .{});
    }

    pub fn endPanel(self: *Context) void {
        self.popClipRect();
        self.popContainer();
    }

    fn getLayout(self: *Context) *Layout {
        return &self.layout_stack.items[self.layout_stack.items.len - 1];
    }

    fn pushLayout(self: *Context, body: Rect, scroll: Vec2) void {
        const layout = Layout{
            .body = Rect{ .x = body.x - scroll.x, .y = body.y - scroll.y, .width = body.width, .height = body.height },
            .next = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 },
            .position = Vec2{ .x = 0, .y = 0 },
            .size = Vec2{ .x = 0, .y = 0 },
            .max = Vec2{ .x = -0x1000000, .y = -0x1000000 },
            .widths = [_]f32{0} ** MAX_WIDTHS,
            .items = 0,
            .item_index = 0,
            .next_row = 0,
            .next_type = 0,
            .indent = 0,
        };
        self.layout_stack.append(self.allocator, layout) catch unreachable;
        const w: f32 = 0;
        self.layoutRow(1, @ptrCast(&w), 0);
    }

    fn popContainer(self: *Context) void {
        const cnt = self.getCurrentContainer();
        const layout = self.getLayout();
        cnt.content_size.x = layout.max.x - layout.body.x;
        cnt.content_size.y = layout.max.y - layout.body.y;
        _ = self.container_stack.pop();
        _ = self.layout_stack.pop();
        self.popId();
    }

    fn getContainerById(self: *Context, id: Id, opt: Options) ?*Container {
        const idx = self.poolGet(&self.container_pool, CONTAINERPOOL_SIZE, id);
        if (idx >= 0) {
            const idx_u = @as(usize, @intCast(idx));
            if (self.containers[idx_u].open != 0 or !opt.closed) {
                self.poolUpdate(&self.container_pool, idx);
            }
            return &self.containers[idx_u];
        }
        if (opt.closed) return null;
        const new_idx = self.poolInit(&self.container_pool, CONTAINERPOOL_SIZE, id);
        const cnt = &self.containers[@as(usize, @intCast(new_idx))];
        cnt.* = std.mem.zeroes(Container);
        cnt.open = 1;
        self.bringToFront(cnt);
        return cnt;
    }

    fn inHoverRoot(self: *Context) bool {
        const hr = self.hover_root orelse return false;
        for (self.container_stack.items) |cnt| {
            if (cnt == hr) return true;
        }
        return false;
    }

    fn numberTextbox(self: *Context, value: *Real, r: Rect, id: Id) Result {
        if (self.mouse_pressed.onlyLeft() and self.key_down.shift and self.hover == id) {
            self.number_edit = id;
            _ = std.fmt.bufPrint(&self.number_edit_buf, "{d:.3}", .{value.*}) catch unreachable;
            self.number_edit_buf[self.number_edit_buf.len - 1] = 0;
        }
        if (self.number_edit == id) {
            var text_len: usize = 0;
            while (text_len < self.number_edit_buf.len and self.number_edit_buf[text_len] != 0) text_len += 1;
            const res = self.textboxRaw(self.number_edit_buf[0..], @intCast(self.number_edit_buf.len), id, r, .{});
            if (res.submit or self.focus != id) {
                value.* = std.fmt.parseFloat(Real, @as([:0]const u8, @ptrCast(&self.number_edit_buf[0]))) catch 0;
                self.number_edit = 0;
            } else {
                return Result{ .active = true };
            }
        }
        return Result{};
    }

    fn doHeader(self: *Context, lbl: [:0]const u8, istreenode: i32, opt: Options) Result {
        const id = self.getId(lbl.ptr, @intCast(lbl.len));
        const idx = self.poolGet(&self.treenode_pool, TREENODEPOOL_SIZE, id);
        const w: f32 = -1;
        self.layoutRow(1, @ptrCast(&w), 0);

        const active = (idx >= 0);
        const expanded = if (opt.expanded) !active else active;
        const r = self.layoutNext();
        self.updateControl(id, r, .{});

        const new_active = active ^ (self.mouse_pressed.onlyLeft() and self.focus == id);

        if (idx >= 0) {
            if (new_active) {
                self.poolUpdate(&self.treenode_pool, idx);
            } else {
                self.treenode_pool[@intCast(idx)] = PoolItem{ .id = 0, .last_update = 0 };
            }
        } else if (new_active) {
            self.poolInit(&self.treenode_pool, TREENODEPOOL_SIZE, id);
        }

        if (istreenode != 0) {
            if (self.hover == id) defaultDrawFrame(self, r, .button_hover);
        } else {
            self.drawControlFrame(id, r, .button, .{});
        }
        self.drawIcon(
            if (expanded) IconId.expanded else IconId.collapsed,
            Rect{ .x = r.x, .y = r.y, .width = r.height, .height = r.height },
            self.style.colors[@intFromEnum(ColorId.text)],
        );
        var tr = r;
        tr.x += r.height - @as(f32, @floatFromInt(self.style.padding));
        tr.width -= r.height - @as(f32, @floatFromInt(self.style.padding));
        self.drawControlText(lbl, tr, .text, .{});

        return Result{ .active = expanded };
    }

    fn doScrollbar(self: *Context, cnt: *Container, b: *Rect, cs: Vec2, vertical: bool) void {
        const maxscroll = if (vertical) cs.y - b.height else cs.x - b.width;

        if (maxscroll > 0 and (if (vertical) b.height else b.width) > 0) {
            var base = b.*;
            if (vertical) {
                base.x = b.x + b.width;
                base.width = @as(f32, @floatFromInt(self.style.scrollbar_size));
            } else {
                base.y = b.y + b.height;
                base.height = @as(f32, @floatFromInt(self.style.scrollbar_size));
            }

            const id_str = if (vertical) "!scrollbary" else "!scrollbarx";
            const id = self.getId(id_str, 11);
            self.updateControl(id, base, .{});

            if (self.focus == id and self.mouse_down.onlyLeft()) {
                if (vertical) {
                    cnt.scroll.y += self.mouse_delta.y * cs.y / base.height;
                } else {
                    cnt.scroll.x += self.mouse_delta.x * cs.x / base.width;
                }
            }

            if (vertical) {
                cnt.scroll.y = clamp(cnt.scroll.y, 0, maxscroll);
            } else {
                cnt.scroll.x = clamp(cnt.scroll.x, 0, maxscroll);
            }

            defaultDrawFrame(self, base, .scroll_base);
            var thumb = base;
            if (vertical) {
                thumb.height = @max(@as(f32, @floatFromInt(self.style.thumb_size)), base.height * b.height / cs.y);
                thumb.y += cnt.scroll.y * (base.height - thumb.height) / maxscroll;
            } else {
                thumb.width = @max(@as(f32, @floatFromInt(self.style.thumb_size)), base.width * b.width / cs.x);
                thumb.x += cnt.scroll.x * (base.width - thumb.width) / maxscroll;
            }
            defaultDrawFrame(self, thumb, .scroll_thumb);

            if (self.mouseOver(b.*)) self.scroll_target = cnt;
        } else {
            if (vertical) cnt.scroll.y = 0 else cnt.scroll.x = 0;
        }
    }

    fn scrollbars(self: *Context, cnt: *Container, body: *Rect) void {
        const sz = @as(f32, @floatFromInt(self.style.scrollbar_size));
        var cs = cnt.content_size;
        cs.x += @as(f32, @floatFromInt(self.style.padding * 2));
        cs.y += @as(f32, @floatFromInt(self.style.padding * 2));
        self.pushClipRect(body.*);
        if (cs.y > cnt.body.height) body.width -= sz;
        if (cs.x > cnt.body.width) body.height -= sz;
        self.doScrollbar(cnt, body, cs, true);
        self.doScrollbar(cnt, body, cs, false);
        self.popClipRect();
    }

    fn pushContainerBody(self: *Context, cnt: *Container, body: Rect, opt: Options) void {
        var b = body;
        if (!opt.no_scroll) self.scrollbars(cnt, &b);
        self.pushLayout(expandRect(b, -self.style.padding), cnt.scroll);
        cnt.body = b;
    }
};
