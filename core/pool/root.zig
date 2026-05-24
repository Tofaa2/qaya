const std = @import("std");

// A generic resource pool with explicit ref-counting.
//
// Comptime parameters:
//   HandleBits   - bit width of the handle integer (e.g. 16, 32, 64)
//   StoredInfo   - the type stored in the pool per resource
//   LoadInfo     - the descriptor passed to Loader/Hasher to identify a resource
//   Error        - the error set Loader may return
//   Loader       - fn(*const LoadInfo) Error!StoredInfo
//   Unloader     - fn(*StoredInfo) void   (infallible, takes mutable ptr)
//   Hasher       - fn(*const LoadInfo) HandleInt  (infallible, deterministic)
//
// Design notes:
//   - Handles are derived by hashing LoadInfo, NOT the loaded value.
//     This means handles are stable and predictable before any I/O occurs,
//     and duplicate loads are detected cheaply.
//   - Ref-counting: load() on an already-resident handle just bumps refs.
//     unload() decrements; the resource is freed when refs hit zero.
//   - Allocator errors are surfaced through the return type of load().
//     errdefer ensures Unloader is called if the map insertion OOMs after
//     the resource has already been loaded.
//   - deinit() is infallible. Destructors must not fail.

pub fn PoolUnmanaged(
    comptime HandleBits: u16,
    comptime StoredInfo: type,
    comptime LoadInfo: type,
    comptime Error: type,
    comptime Loader: *const fn (*const LoadInfo) Error!StoredInfo,
    comptime Unloader: *const fn (*StoredInfo) void,
    comptime Hasher: *const fn (*const LoadInfo) @Int(.unsigned, HandleBits),
) type {
    return struct {
        const Self = @This();
        pub const HandleInt = @Int(.unsigned, HandleBits);
        pub const requires_allocator = blk: {
            const info = @typeInfo(StoredInfo);
            if (info != .@"struct") {
                break :blk false;
            }
            for (info.@"struct".fields) |field| {
                if (field.type == std.mem.Allocator and std.mem.eql(u8, field.name, "allocator")) {
                    break :blk true;
                }
            }
            break :blk false;
        };
        pub const Handle = struct {
            value: HandleInt,
        };

        const Entry = struct {
            info: LoadInfo,
            data: StoredInfo,
            refs: u32 = 1,
        };

        allocator: std.mem.Allocator,
        io: std.Io,
        map: std.AutoHashMapUnmanaged(Handle, Entry),
        next_copy_id: HandleInt,

        pub fn init(allocator: std.mem.Allocator, io: std.Io) Self {
            return .{
                .allocator = allocator,
                .io = io,
                .map = .{},
                .next_copy_id = 0,
            };
        }

        /// Load a resource, or bump its refcount if already resident.
        /// Returns the stable handle for the resource.
        pub fn load(
            self: *Self,
            info: *const LoadInfo,
        ) (Error || std.mem.Allocator.Error)!Handle {
            const handle_int = Hasher(info);
            const handle = Handle{ .value = handle_int };

            if (self.map.getPtr(handle)) |entry| {
                entry.refs += 1;
                return handle;
            }

            var data = try Loader(info);
            errdefer Unloader(&data);
            if (requires_allocator) {
                data.allocator = self.allocator;
            }
            try self.map.put(self.allocator, handle, .{ .info = info.*, .data = data });
            return handle;
        }

        /// Load using @load and then edit the created pool entry.
        pub fn loadEdit(self: *Self, info: *const LoadInfo, editor: *const fn (*StoredInfo) void) (Error || std.mem.Allocator.Error)!Handle {
            const handle = try self.load(info);
            const ptr = self.map.getPtr(handle).?;
            editor(ptr.data);
        }

        /// Load using std.Io and then edit the created pool entry.
        pub fn loadEditAsync(self: *Self, info: *const LoadInfo, editor: *const fn (*StoredInfo) void ) std.Io.Future((Error || std.mem.Allocator.Error)!Handle) {
            return self.io.call(loadEdit, .{ self, info, editor});
        }

        /// Async load via std.Io.
        pub fn loadAsync(
            self: *Self,
            info: *const LoadInfo,
        ) std.Io.Future((Error || std.mem.Allocator.Error)!Handle) {
            return self.io.call(load, .{ self, info });
        }

        /// Release one reference to a handle.
        /// The resource is unloaded when the refcount reaches zero.
        pub fn unload(self: *Self, handle: Handle) void {
            const entry = self.map.getPtr(handle) orelse return;
            entry.refs -= 1;
            if (entry.refs == 0) {
                Unloader(&entry.data);
                _ = self.map.remove(handle);
            }
        }

        /// Borrow a pointer to the stored resource. Null if not loaded.
        /// The pointer is invalidated by any subsequent load/unload call.
        pub fn get(self: *Self, handle: Handle) ?*StoredInfo {
            return if (self.map.getPtr(handle)) |e| &e.data else null;
        }

        /// Current reference count for a handle, or null if not loaded.
        pub fn refCount(self: *const Self, handle: Handle) ?u32 {
            return if (self.map.get(handle)) |e| e.refs else null;
        }

        /// Number of distinct resources currently resident in the pool.
        pub fn count(self: *const Self) usize {
            return self.map.count();
        }

        /// Create a new entry by bitwise-copying the source's data, then applying a
        /// copy function that receives (original, new_copy) to deep-copy any heap-
        /// allocated fields and make modifications. Returns a new unique handle
        /// (not derived from LoadInfo hashing).
        pub fn copyModify(
            self: *Self,
            src_handle: Handle,
            copy_fn: fn (*const StoredInfo, *StoredInfo) void,
        ) (Error || std.mem.Allocator.Error || error{NotFound})!Handle {
            const src = self.map.getPtr(src_handle) orelse return error.NotFound;

            var new_value = self.next_copy_id;
            self.next_copy_id += 1;
            while (self.map.contains(.{ .value = new_value })) : (new_value += 1) {}

            const new_handle = Handle{ .value = new_value };

            var new_data = src.data;
            copy_fn(&src.data, &new_data);

            try self.map.put(self.allocator, new_handle, .{
                .info = src.info,
                .data = new_data,
                .refs = 1,
            });
            return new_handle;
        }

        /// Force-unload all resources. Safe to call before deinit.
        pub fn clear(self: *Self) void {
            var iter = self.map.iterator();
            while (iter.next()) |entry| {
                Unloader(&entry.value_ptr.data);
            }
            self.map.clearRetainingCapacity();
        }

        /// Release all resources and free internal storage. Always infallible.
        pub fn deinit(self: *Self) void {
            self.clear();
            self.map.deinit(self.allocator);
        }
    };
}

// A convenience wrapper over PoolUnmanaged for resource types that own their
// lifecycle via init/deinit methods.
//
// Required interface on Resource:
//   pub fn init(*const LoadInfo) Error!Resource
//   pub fn deinit(*Resource) void
//
// Hashing is handled automatically via Wyhash over the raw bytes of LoadInfo.
//
// Caveat: if LoadInfo contains pointers, Wyhash hashes the pointer *address*,
// not the pointed-to data. Use PoolManagedWithHasher for those cases.

pub fn PoolManaged(
    comptime HandleBits: u16,
    comptime Resource: type,
    comptime LoadInfo: type,
    comptime Error: type,
) type {
    comptime {
        if (!@hasDecl(Resource, "init"))
            @compileError(@typeName(Resource) ++ " must declare `pub fn init(*const " ++ @typeName(LoadInfo) ++ ") Error!@This()`");
        if (!@hasDecl(Resource, "deinit"))
            @compileError(@typeName(Resource) ++ " must declare `pub fn deinit(*@This()) void`");
    }

    const HandleInt = @Int(.unsigned, HandleBits);

    const DefaultHasher = struct {
        fn hash(info: *const LoadInfo) HandleInt {
            const bytes = std.mem.asBytes(info);
            const full = std.hash.Wyhash.hash(0, bytes);
            return @truncate(full);
        }
    }.hash;

    return PoolUnmanaged(
        HandleBits,
        Resource,
        LoadInfo,
        Error,
        &Resource.init,
        &Resource.deinit,
        DefaultHasher,
    );
}

// Like PoolManaged but accepts a custom Hasher — useful when LoadInfo contains
// pointers or needs domain-specific identity logic (e.g. case-insensitive
// string paths).

pub fn PoolManagedWithHasher(
    comptime HandleBits: u16,
    comptime Resource: type,
    comptime LoadInfo: type,
    comptime Error: type,
    comptime Hasher: *const fn (*const LoadInfo) @Int(.unsigned, HandleBits),
) type {
    comptime {
        if (!@hasDecl(Resource, "init"))
            @compileError(@typeName(Resource) ++ " must declare `pub fn init(*const " ++ @typeName(LoadInfo) ++ ") Error!@This()`");
        if (!@hasDecl(Resource, "deinit"))
            @compileError(@typeName(Resource) ++ " must declare `pub fn deinit(*@This()) void`");
    }

    return PoolUnmanaged(
        HandleBits,
        Resource,
        LoadInfo,
        Error,
        &Resource.init,
        &Resource.deinit,
        Hasher,
    );
}
/// Sequential-handle asset storage
/// Stores items contiguously, assigns incrementing u32 handles.
/// Each `Assets(T)` instantiation gets its own distinct Handle type.
///
/// T must have `pub fn deinit(*T) void` (or no deinit — skipped if absent).
pub fn Assets(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const Handle = struct { value: u32 };

        allocator: std.mem.Allocator,
        items: std.ArrayListUnmanaged(T) = .empty,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .allocator = allocator };
        }

        pub fn add(self: *Self, item: T) !Handle {
            const index = @as(u32, @intCast(self.items.items.len));
            try self.items.append(self.allocator, item);
            return .{ .value = index };
        }

        pub fn get(self: *Self, handle: Handle) ?*T {
            if (handle.value >= self.items.items.len) return null;
            return &self.items.items[handle.value];
        }

        pub fn deinit(self: *Self) void {
            for (self.items.items) |*item| {
                if (@hasDecl(T, "deinit")) {
                    T.deinit(item);
                }
            }
            self.items.deinit(self.allocator);
        }
    };
}

const testing = std.testing;

// Test fixture: a simple counted resource that tracks live instances globally
// so tests can assert it was actually freed.

const TestError = error{LoadFailed};

var live_count: usize = 0; // incremented on load, decremented on unload

const TestResource = struct {
    value: u32,

    pub fn init(info: *const u32) TestError!TestResource {
        live_count += 1;
        return .{ .value = info.* };
    }

    pub fn deinit(self: *TestResource) void {
        live_count -= 1;
        self.value = 0xDEAD; // poison to catch use-after-free in tests
    }
};

// A PoolManaged over TestResource with 32-bit handles.
const TestPool = PoolManaged(32, TestResource, u32, TestError);

fn makePool() TestPool {
    return TestPool.init(testing.allocator, undefined); // io unused in sync tests
}

test "load creates a resource and returns a stable handle" {
    var pool = makePool();
    defer pool.deinit();

    live_count = 0;
    const info: u32 = 42;
    const h = try pool.load(&info);

    try testing.expectEqual(@as(usize, 1), live_count);
    try testing.expectEqual(@as(usize, 1), pool.count());
    try testing.expectEqual(@as(?u32, 1), pool.refCount(h));

    const res = pool.get(h).?;
    try testing.expectEqual(@as(u32, 42), res.value);
}

test "loading the same info twice bumps refcount, not resource count" {
    var pool = makePool();
    defer pool.deinit();

    live_count = 0;
    const info: u32 = 7;
    const h1 = try pool.load(&info);
    const h2 = try pool.load(&info);

    try testing.expectEqual(h1, h2); // same handle
    try testing.expectEqual(@as(usize, 1), live_count); // only one resource created
    try testing.expectEqual(@as(?u32, 2), pool.refCount(h1)); // refs == 2
    try testing.expectEqual(@as(usize, 1), pool.count());
}

test "unload decrements refcount; resource freed at zero" {
    var pool = makePool();
    defer pool.deinit();

    live_count = 0;
    const info: u32 = 99;
    const h = try pool.load(&info);
    _ = try pool.load(&info); // refs -> 2

    pool.unload(h); // refs -> 1
    try testing.expectEqual(@as(usize, 1), live_count);
    try testing.expectEqual(@as(?u32, 1), pool.refCount(h));

    pool.unload(h); // refs -> 0, resource freed
    try testing.expectEqual(@as(usize, 0), live_count);
    try testing.expectEqual(@as(?u32, null), pool.refCount(h));
    try testing.expectEqual(@as(usize, 0), pool.count());
}

test "unload on unknown handle is a no-op" {
    var pool = makePool();
    defer pool.deinit();

    pool.unload(TestPool.Handle{ .value = 0xDEADBEEF }); // must not crash or assert
}

test "get returns null for unloaded handle" {
    var pool = makePool();
    defer pool.deinit();

    try testing.expectEqual(@as(?*TestResource, null), pool.get(TestPool.Handle{ .value = 0 }));
}

test "get returns a valid pointer to the stored resource" {
    var pool = makePool();
    defer pool.deinit();

    const info: u32 = 123;
    const h = try pool.load(&info);
    const ptr = pool.get(h).?;
    try testing.expectEqual(@as(u32, 123), ptr.value);
}

test "clear unloads all resources" {
    var pool = makePool();
    defer pool.deinit();

    live_count = 0;
    var i: u32 = 0;
    while (i < 5) : (i += 1) _ = try pool.load(&i);

    try testing.expectEqual(@as(usize, 5), live_count);
    pool.clear();
    try testing.expectEqual(@as(usize, 0), live_count);
    try testing.expectEqual(@as(usize, 0), pool.count());
}

test "deinit cleans up all resources" {
    live_count = 0;
    {
        var pool = makePool();
        var i: u32 = 0;
        while (i < 3) : (i += 1) _ = try pool.load(&i);
        try testing.expectEqual(@as(usize, 3), live_count);
        pool.deinit();
    }
    try testing.expectEqual(@as(usize, 0), live_count);
}

test "different LoadInfo values produce different handles" {
    var pool = makePool();
    defer pool.deinit();

    const a: u32 = 1;
    const b: u32 = 2;
    const ha = try pool.load(&a);
    const hb = try pool.load(&b);

    try testing.expect(ha.value != hb.value);
    try testing.expectEqual(@as(usize, 2), pool.count());
}

test "multiple resources interleaved refcounts are independent" {
    var pool = makePool();
    defer pool.deinit();

    live_count = 0;
    const a: u32 = 10;
    const b: u32 = 20;

    const ha = try pool.load(&a);
    _ = try pool.load(&a); // refs(a) = 2
    const hb = try pool.load(&b); // refs(b) = 1

    pool.unload(ha); // refs(a) = 1
    try testing.expectEqual(@as(usize, 2), live_count);

    pool.unload(hb); // refs(b) = 0, b freed
    try testing.expectEqual(@as(usize, 1), live_count);

    pool.unload(ha); // refs(a) = 0, a freed
    try testing.expectEqual(@as(usize, 0), live_count);
}

// PoolUnmanaged with custom loader/unloader/hasher
// A resource that wraps a heap-allocated string to verify custom unloader runs.
const StringResource = struct { ptr: []u8 };
var string_live: usize = 0;

fn stringLoader(path: *const []const u8) std.mem.Allocator.Error!StringResource {
    const copy = try testing.allocator.dupe(u8, path.*);
    string_live += 1;
    return .{ .ptr = copy };
}

fn stringUnloader(res: *StringResource) void {
    testing.allocator.free(res.ptr);
    string_live -= 1;
}

fn stringHasher(path: *const []const u8) u32 {
    const full = std.hash.Wyhash.hash(0, path.*);
    return @truncate(full);
}

const StringPool = PoolUnmanaged(
    32,
    StringResource,
    []const u8,
    std.mem.Allocator.Error,
    &stringLoader,
    &stringUnloader,
    &stringHasher,
);

test "PoolUnmanaged with custom loader/unloader/hasher" {
    var pool = StringPool.init(testing.allocator, undefined);
    defer pool.deinit();

    string_live = 0;
    const path: []const u8 = "assets/texture.png";
    const h = try pool.load(&path);
    try testing.expectEqual(@as(usize, 1), string_live);

    const res = pool.get(h).?;
    try testing.expectEqualStrings("assets/texture.png", res.ptr);

    pool.unload(h);
    try testing.expectEqual(@as(usize, 0), string_live);
}

// PoolManagedWithHasher — custom hasher, lifecycle from Resource methods
fn upperHasher(info: *const u32) u16 {
    // Deliberately trivial: use the value itself mod max u16, for test predictability.
    return @truncate(info.* % std.math.maxInt(u16));
}

const NarrowPool = PoolManagedWithHasher(16, TestResource, u32, TestError, &upperHasher);

test "copyModify creates a new entry with unique handle" {
    var pool = makePool();
    defer pool.deinit();

    live_count = 0;
    const info: u32 = 42;
    const src = try pool.load(&info);
    try testing.expectEqual(@as(usize, 1), live_count);

    const copy = try pool.copyModify(src, struct {
        fn f(orig: *const TestResource, new: *TestResource) void {
            new.value = orig.value * 2;
            live_count += 1; // match the init-side effect for lifecycle tracking
        }
    }.f);
    try testing.expectEqual(@as(usize, 2), live_count);
    try testing.expect(copy.value != src.value);
    try testing.expectEqual(@as(usize, 2), pool.count());
    try testing.expectEqual(@as(?u32, 1), pool.refCount(src));
    try testing.expectEqual(@as(?u32, 1), pool.refCount(copy));

    const orig_data = pool.get(src).?;
    const copy_data = pool.get(copy).?;
    try testing.expectEqual(@as(u32, 42), orig_data.value);
    try testing.expectEqual(@as(u32, 84), copy_data.value);
}

test "copyModify with heap-allocated data deep-copies correctly" {
    var pool = StringPool.init(testing.allocator, undefined);
    defer pool.deinit();

    string_live = 0;
    const path: []const u8 = "hello.txt";
    const src = try pool.load(&path);
    try testing.expectEqual(@as(usize, 1), string_live);

    const copy = try pool.copyModify(src, struct {
        fn f(orig: *const StringResource, new: *StringResource) void {
            new.ptr = testing.allocator.dupe(u8, orig.ptr) catch @panic("OOM");
            string_live += 1; // match the loader-side effect for lifecycle tracking
        }
    }.f);
    try testing.expectEqual(@as(usize, 2), string_live);

    const orig_str = pool.get(src).?;
    const copy_str = pool.get(copy).?;

    // Modify the copy -- original must be unaffected
    copy_str.ptr[0] = 'X';
    try testing.expectEqualStrings("hello.txt", orig_str.ptr);
    try testing.expectEqualStrings("Xello.txt", copy_str.ptr);

    pool.unload(src);
    pool.unload(copy);
    try testing.expectEqual(@as(usize, 0), string_live);
}

test "PoolManagedWithHasher uses provided hasher" {
    live_count = 0;
    {
        var pool = NarrowPool.init(testing.allocator, undefined);
        defer pool.deinit();

        const info: u32 = 5;
        const h = try pool.load(&info);

        // With our trivial hasher, handle should equal 5 % maxInt(u16)
        try testing.expectEqual(@as(u16, 5), h.value);
        try testing.expectEqual(@as(usize, 1), live_count);
    }
    // Now assert the resource was freed by deinit
    try testing.expectEqual(@as(usize, 0), live_count);
}
