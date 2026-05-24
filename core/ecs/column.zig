const std = @import("std");

pub const Column = struct {
    data: []u8,
    ticks: []ComponentTicks,
    capacity: usize,
    len: usize,
    element_size: usize,
    element_align: u8,
    stride: usize,

    pub const ComponentTicks = struct {
        added: u32,
        changed: u32,
    };

    pub fn init(_: std.mem.Allocator, element_size: usize, element_align: u8) Column {
        return .{
            .data = &[_]u8{},
            .ticks = &[_]ComponentTicks{},
            .capacity = 0,
            .len = 0,
            .element_size = element_size,
            .element_align = element_align,
            .stride = @max(std.mem.alignForward(usize, element_size, element_align), 1),
        };
    }

    pub fn deinit(self: *Column, allocator: std.mem.Allocator) void {
        if (self.capacity == 0) return;
        const es = self.element_size;
        const ea = self.element_align;
        allocator.rawFree(self.data, .fromByteUnits(ea), @returnAddress());
        allocator.free(self.ticks);
        self.* = .init(allocator, es, ea);
    }

    pub fn rowPtr(self: *Column, row: usize) [*]align(1) u8 {
        std.debug.assert(row < self.len);
        return self.data[row * self.stride ..][0..self.stride].ptr;
    }

    /// Ensures at least `min_capacity` rows can be stored. Uses exponential growth so repeated
    /// `pushUninitialized` stays amortized O(1) per row (not O(n²) from growing by one each time).
    pub fn ensureTotalCapacity(self: *Column, allocator: std.mem.Allocator, min_capacity: usize) !void {
        if (min_capacity <= self.capacity) return;

        var new_cap: usize = @max(self.capacity, 8);
        while (new_cap < min_capacity) {
            new_cap *|= 2;
        }

        const new_bytes = self.stride * new_cap;
        const new_mem = allocator.rawAlloc(new_bytes, .fromByteUnits(self.element_align), @returnAddress()) orelse
            return error.OutOfMemory;
        const new_ticks = try allocator.alloc(ComponentTicks, new_cap);

        if (self.capacity > 0) {
            const copy_len = self.stride * self.len;
            @memcpy(new_mem[0..copy_len], self.data[0..copy_len]);
            @memcpy(new_ticks[0..self.len], self.ticks[0..self.len]);
            allocator.rawFree(self.data, .fromByteUnits(self.element_align), @returnAddress());
            allocator.free(self.ticks);
        }
        self.data = new_mem[0..new_bytes];
        self.ticks = new_ticks;
        self.capacity = new_cap;
    }

    pub fn pushUninitialized(self: *Column, allocator: std.mem.Allocator, tick: u32) !usize {
        try self.ensureTotalCapacity(allocator, self.len + 1);
        const row = self.len;
        self.ticks[row] = .{ .added = tick, .changed = tick };
        self.len += 1;
        return row;
    }

    pub fn swapRemove(self: *Column, row: usize) void {
        std.debug.assert(row < self.len);
        if (self.len == 1) {
            self.len = 0;
            return;
        }
        const last = self.len - 1;
        if (row != last) {
            const a = row * self.stride;
            const b = last * self.stride;
            @memcpy(self.data[a .. a + self.stride], self.data[b .. b + self.stride]);
            self.ticks[row] = self.ticks[last];
        }
        self.len -= 1;
    }

    pub fn copyRowFrom(self: *Column, dst_row: usize, src: *const Column, src_row: usize) void {
        std.debug.assert(dst_row < self.len);
        std.debug.assert(src_row < src.len);
        const copy_size = @min(self.element_size, src.element_size);
        const dst_offset = dst_row * self.stride;
        const src_offset = src_row * src.stride;
        @memcpy(self.data[dst_offset .. dst_offset + copy_size], src.data[src_offset .. src_offset + copy_size]);
        self.ticks[dst_row] = src.ticks[src_row];
    }
};
