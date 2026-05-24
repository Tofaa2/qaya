const std = @import("std");
const registry = @import("registry.zig");
const Column = @import("column.zig").Column;
pub const Entity = @import("entity.zig").Entity;

pub const ArchetypeId = u32;

pub const Archetype = struct {
    signature: registry.Mask,
    id: ArchetypeId,
    entities: std.ArrayListUnmanaged(Entity),
    
    /// The actual column data. Most archetypes have very few components.
    /// 64 is enough for almost any entity.
    columns: [64]Column = undefined,
    column_ids: [64]u16 = undefined,
    column_count: u8 = 0,

    /// O(1) lookup table: component_id -> index in `columns` array.
    /// 0xFFFF means the component is not present in this archetype.
    lookup: [registry.max_components]u16 = .{0xFFFF} ** registry.max_components,

    pub fn deinit(self: *Archetype, allocator: std.mem.Allocator) void {
        for (0..self.column_count) |i| {
            self.columns[i].deinit(allocator);
        }
        self.entities.deinit(allocator);
    }

    pub fn ensureColumn(self: *Archetype, allocator: std.mem.Allocator, cid: u32, comptime T: type) !void {
        try self.ensureColumnRaw(allocator, cid, @sizeOf(T), registry.elementAlign(T), registry.elementStride(T));
    }

    pub fn ensureColumnRaw(self: *Archetype, allocator: std.mem.Allocator, cid: u32, size: usize, align_val: u8, _: usize) !void {
        if (self.lookup[cid] != 0xFFFF) {
            const idx = self.lookup[cid];
            if (self.columns[idx].element_size >= size) return;
            self.columns[idx].deinit(allocator);
            self.columns[idx] = Column.init(allocator, size, align_val);
            return;
        }

        if (self.column_count >= 64) return error.TooManyComponentsInArchetype;
        
        const idx = self.column_count;
        self.columns[idx] = Column.init(allocator, size, align_val);
        self.column_ids[idx] = @intCast(cid);
        self.lookup[cid] = @intCast(idx);
        self.column_count += 1;
    }

    pub fn getColumn(self: *Archetype, cid: u32) ?*Column {
        const idx = self.lookup[cid];
        if (idx == 0xFFFF) return null;
        return &self.columns[idx];
    }

    pub fn swapRemoveRow(self: *Archetype, _: std.mem.Allocator, row: usize) !?Entity {
        const last = self.entities.items.len - 1;
        var moved: ?Entity = null;
        if (row != last) {
            moved = self.entities.items[last];
        }

        for (0..self.column_count) |i| {
            _ = self.columns[i].swapRemove(row);
        }
        _ = self.entities.swapRemove(row);

        return moved;
    }

    pub fn appendRow(
        self: *Archetype,
        allocator: std.mem.Allocator,
        e: Entity,
        _: registry.Mask,
        comptime types: []const type,
        values: anytype,
        tick: u32,
    ) !usize {
        const V = @TypeOf(values);
        const is_tuple = @typeInfo(V).@"struct".is_tuple;
        const fields = std.meta.fields(V);

        try self.entities.append(allocator, e);
        const row = self.entities.items.len - 1;

        inline for (types, 0..) |T, i| {
            const cid = registry.id(T);
            try self.ensureColumn(allocator, cid, T);
            const col = self.getColumn(cid).?;
            _ = try col.pushUninitialized(allocator, tick);
            @as(*T, @ptrCast(@alignCast(col.rowPtr(row)))).* = if (is_tuple) values[i] else @field(values, fields[i].name);
        }

        return row;
    }

    pub fn migrate(self: *Archetype, allocator: std.mem.Allocator, row: usize, dst: *Archetype) !?Entity {
        const e = self.entities.items[row];
        try dst.entities.append(allocator, e);
        const dst_row = dst.entities.items.len - 1;

        // Only migrate components that exist in both archetypes
        for (0..self.column_count) |i| {
            const cid = self.column_ids[i];
            if (dst.signature & (@as(registry.Mask, 1) << @intCast(cid)) != 0) {
                const src_col = &self.columns[i];
                // Ensure the column exists in the destination
                // Note: we don't know the stride here, but ensureColumnRaw handles it
                try dst.ensureColumnRaw(allocator, cid, src_col.element_size, src_col.element_align, src_col.element_size);
                const dst_col = dst.getColumn(cid).?;
                _ = try dst_col.pushUninitialized(allocator, 0); // Will be overwritten by copyRowFrom
                dst_col.copyRowFrom(dst_row, src_col, row);
            }
        }

        return self.swapRemoveRow(allocator, row);
    }
};

pub fn create(
    allocator: std.mem.Allocator,
    id: ArchetypeId,
    sig: registry.Mask,
) !Archetype {
    return .{
        .signature = sig,
        .id = id,
        .entities = try std.ArrayListUnmanaged(Entity).initCapacity(allocator, 64),
    };
}
