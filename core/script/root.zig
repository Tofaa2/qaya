const std = @import("std");
const Lua = @import("lua").Lua;

const Self = @This();
pub const ScriptEngine = Self;

const Script = struct {
    path_owned: [:0]u8,
    mtime: i64,
};

lua: *Lua,
allocator: std.mem.Allocator,
io: std.Io,
scripts: std.ArrayListUnmanaged(Script),

pub fn init(allocator: std.mem.Allocator, io: std.Io) !Self {
    const lua = try Lua.init(allocator);
    lua.openBaseLib();
    lua.openStringLib();
    lua.openMathLib();
    lua.openTableLib();
    lua.openPackageLib();
    lua.openDebugLib();

    lua.newTable();
    lua.pushValue(-1);
    lua.setGlobal("qaya");
    _ = lua.getGlobal("package");
    _ = lua.getField(-1, "loaded");
    lua.pushValue(-3);
    lua.setField(-2, "qaya");
    lua.pop(2);
    lua.pop(1);

    try lua.doString(
        \\qaya._systems = {}
        \\qaya._scripts = {}
        \\qaya._current_script = nil
        \\
        \\function qaya.add_system(stage, fn)
        \\  if not qaya._systems[stage] then qaya._systems[stage] = {} end
        \\  table.insert(qaya._systems[stage], {fn = fn, script = qaya._current_script})
        \\end
        \\
        \\function qaya._load_script(path)
        \\  local info = qaya._scripts[path]
        \\  if not info then
        \\    info = {}
        \\    qaya._scripts[path] = info
        \\  end
        \\  qaya._current_script = info
        \\end
        \\
        \\function qaya._finish_load()
        \\  qaya._current_script = nil
        \\end
        \\
        \\function qaya._unload_script(path)
        \\  local info = qaya._scripts[path]
        \\  if not info then return end
        \\  local systems = qaya._systems
        \\  for stage, list in pairs(systems) do
        \\    local i = 1
        \\    while i <= #list do
        \\      if list[i].script == info then
        \\        table.remove(list, i)
        \\      else
        \\        i = i + 1
        \\      end
        \\    end
        \\  end
        \\  qaya._scripts[path] = nil
        \\end
        \\
        \\function qaya.run_systems(stage)
        \\  local list = qaya._systems[stage]
        \\  if not list then return end
        \\  for _, entry in ipairs(list) do
        \\    local ok, err = pcall(entry.fn)
        \\    if not ok then
        \\      print("Error: " .. tostring(err))
        \\      print(debug.traceback())
        \\    end
        \\  end
        \\end
    );

    return .{
        .lua = lua,
        .allocator = allocator,
        .io = io,
        .scripts = .{ .items = &.{}, .capacity = 0 },
    };
}

pub fn deinit(self: *Self) void {
    for (self.scripts.items) |s| self.allocator.free(s.path_owned);
    self.scripts.deinit(self.allocator);
    self.lua.deinit();
}

pub fn getLua(self: *Self) *Lua {
    return self.lua;
}

pub fn registerFunction(self: *Self, name: [:0]const u8, func: Lua.CFunction) void {
    _ = self.lua.getGlobal("qaya");
    self.lua.pushCFunction(func);
    self.lua.setField(-2, name);
    self.lua.pop(1);
}

pub fn doString(self: *Self, chunk: [:0]const u8) !void {
    try self.lua.doString(chunk);
}

fn statMtime(self: *Self, path: [:0]const u8) !i64 {
    const cwd = std.Io.Dir.cwd();
    const stat = try cwd.statFile(self.io, path, .{});
    return @as(i64, @intCast(stat.mtime.nanoseconds));
}

pub fn loadFile(self: *Self, path: [:0]const u8) !void {
    const mtime = try self.statMtime(path);
    const owned = try self.allocator.dupeZ(u8, path);

    const lua = self.lua;
    _ = lua.getGlobal("qaya");
    _ = lua.getField(-1, "_load_script");
    lua.pushString(path);
    try lua.callProtected(1, 0, 0);
    lua.pop(1);

    lua.doFile(path) catch |err| {
        self.allocator.free(owned);
        return err;
    };

    _ = lua.getGlobal("qaya");
    _ = lua.getField(-1, "_finish_load");
    try lua.callProtected(0, 0, 0);
    lua.pop(1);

    try self.scripts.append(self.allocator, .{
        .path_owned = owned,
        .mtime = mtime,
    });
}

pub fn doFile(self: *Self, path: [:0]const u8) !void {
    try self.loadFile(path);
}

pub fn unload(self: *Self, path: [:0]const u8) void {
    const lua = self.lua;
    _ = lua.getGlobal("qaya");
    _ = lua.getField(-1, "_unload_script");
    lua.pushString(path);
    lua.callProtected(1, 0, 0) catch {};
    lua.pop(1);

    for (self.scripts.items, 0..) |s, i| {
        if (std.mem.eql(u8, s.path_owned, path)) {
            self.allocator.free(s.path_owned);
            _ = self.scripts.swapRemove(i);
            break;
        }
    }
}

pub fn reload(self: *Self, path: [:0]const u8) !void {
    self.unload(path);
    try self.loadFile(path);
}

pub fn update(self: *Self) void {
    var changed: std.ArrayListUnmanaged([:0]u8) = .empty;
    defer {
        for (changed.items) |p| self.allocator.free(p);
        changed.deinit(self.allocator);
    }

    for (self.scripts.items) |s| {
        const new_mtime = self.statMtime(s.path_owned) catch continue;
        if (new_mtime != s.mtime) {
            const dup = self.allocator.dupeZ(u8, s.path_owned) catch continue;
            changed.append(self.allocator, dup) catch {
                self.allocator.free(dup);
                continue;
            };
        }
    }

    for (changed.items) |path| {
        self.reload(path) catch {};
    }
}

pub fn callStage(self: *Self, stage: [:0]const u8) !void {
    _ = self.lua.getGlobal("qaya");
    _ = self.lua.getField(-1, "run_systems");
    self.lua.pushString(stage);
    try self.lua.callProtected(1, 0, 0);
    self.lua.pop(1);
}
