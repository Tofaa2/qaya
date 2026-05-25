const std = @import("std");
const Build = std.Build;
const Module = Build.Module;
const Optimize = std.builtin.OptimizeMode;
const Target = Build.ResolvedTarget;
const Step = Build.Step;
const Compile = Step.Compile;
const Import = Module.Import;

// TODO: Migrate old makeModule to createModule
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const docs_step = b.step("docs", "Generate API Documentation");
    const test_step = b.step("test", "Run unit tests");
    const run_step = b.step("run", "Run the sandbox application");

    const math = createModule(.{
        .b = b,
        .target = target,
        .optimize = optimize,
        .name = "math",
        .path = "core/math/root.zig",
        .test_step = test_step,
        .docs_step = docs_step,
    });
    const ecs = createModule(.{
        .b = b,
        .target = target,
        .optimize = optimize,
        .name = "ecs",
        .path = "core/ecs/root.zig",
        .test_step = test_step,
        .docs_step = docs_step,
    });
    const pool = createModule(.{
        .b = b,
        .target = target,
        .optimize = optimize,
        .name = "pool",
        .path = "core/pool/root.zig",
        .test_step = test_step,
        .docs_step = docs_step,
    });

    _ = createModule(.{
        .b = b,
        .target = target,
        .optimize = optimize,
        .name = "asset",
        .path = "core/asset/root.zig",
        .test_step = test_step,
        .docs_step = docs_step,
    });

    const stb = createLib(.{
        .includes = "core/stb/",
        .c_files = &.{"core/stb/stb_impl.c"},
        .module = .{
            .b = b,
            .target = target,
            .optimize = optimize,
            .name = "stb",
            .path = "core/stb/root.zig",
            .test_step = test_step,
            .docs_step = docs_step,
            .libc = true,
        },
    });
    const window = createLib(.{
        .includes = "core/window/",
        .c_files = &.{"core/window/rgfw_impl.c"},
        .module = .{
            .b = b,
            .name = "window",
            .path = "core/window/root.zig",
            .test_step = test_step,
            .docs_step = docs_step,
            .target = target,
            .optimize = optimize,
            .libc = true,
        },
        .externals = &.{
            .{ .type = .system, .name = "gdi32", .os = .windows },
            .{ .type = .system, .name = "X11", .os = .linux },
            .{ .type = .system, .name = "Xrandr", .os = .linux },
            .{ .type = .system, .name = "wayland-client", .os = .linux },
            .{ .type = .system, .name = "wayland-cursor", .os = .linux },
            .{ .type = .system, .name = "xkbcommon", .os = .linux },
            .{ .type = .framework, .name = "Cocoa", .os = .macos },
            .{ .type = .framework, .name = "CoreVideo", .os = .macos },
            .{ .type = .framework, .name = "IOKit", .os = .macos },
        },
    });

    const renderer = createModule(.{
        .b = b,
        .target = target,
        .optimize = optimize,
        .name = "renderer",
        .path = "core/renderer/root.zig",
        .test_step = test_step,
        .docs_step = docs_step,
    });
    linkBgfx(b, target, renderer) catch unreachable;
    renderer.addImport("math", math);
    renderer.addImport("pool", pool);
    renderer.addImport("stb", stb.root_module);
    renderer.linkLibrary(stb);

    const script = createModule(.{
        .b = b,
        .target = target,
        .optimize = optimize,
        .name = "script",
        .path = "core/script/root.zig",
        .test_step = test_step,
        .docs_step = docs_step,
    });
    script.addImport("lua", b.dependency("luajit", .{
        .target = target,
        .optimize = optimize,
    }).module("luajit"));

    const app_sdk = createModule(.{
        .b = b,
        .target = target,
        .optimize = optimize,
        .name = "app-sdk",
        .path = "core/app-sdk/root.zig",
        .test_step = test_step,
        .docs_step = docs_step,
        .outside = true,
    });
    app_sdk.addImport("lua", b.dependency("luajit", .{
        .target = target,
        .optimize = optimize,
    }).module("luajit"));
    app_sdk.addImport("script", script);
    app_sdk.linkLibrary(stb);
    app_sdk.addImport("stb", stb.root_module);
    app_sdk.linkLibrary(window);
    app_sdk.addImport("window", window.root_module);
    app_sdk.addImport("renderer", renderer);
    app_sdk.addImport("math", math);
    app_sdk.addImport("pool", pool);
    app_sdk.addImport("ecs", ecs);

    const sandbox = b.addExecutable(.{
        .name = "sandbox",
        .use_llvm = true,
        .root_module = b.createModule(.{ .root_source_file = b.path("sandbox/main.zig"), .target = target, .optimize = optimize, .imports = &.{
            .{ .name = "math", .module = math },
            .{ .name = "ecs", .module = ecs },
            .{ .name = "pool", .module = pool },
            .{ .name = "renderer", .module = renderer },
            .{ .name = "window", .module = window.root_module },
            .{ .name = "app-sdk", .module = app_sdk },
            .{ .name = "script", .module = script },
        } }),
    });
    sandbox.root_module.linkLibrary(window);

    b.installArtifact(sandbox);
    const run_sandbox = b.addRunArtifact(sandbox);
    if (b.args) |args| {
        run_sandbox.addArgs(args);
    }
    run_step.dependOn(&run_sandbox.step);
}

const LibCreateOptions = struct {
    module: ModuleCreateOptions,
    externals: []const External = &.{},
    includes: ?[]const u8,
    c_files: []const []const u8 = &.{},
    macros: []const []const u8 = &.{},
    const External = struct {
        type: enum {
            system,
            framework,
        },
        name: []const u8,
        os: std.Target.Os.Tag,
    };
};

fn createLib(opts: LibCreateOptions) *Compile {
    var b = opts.module.b;
    const lib = b.addLibrary(.{
        .name = opts.module.name,
        .root_module = b.createModule(opts.module.createOpts()),
    });

    if (opts.includes) |includes| {
        lib.root_module.addIncludePath(b.path(includes));
    }
    if (opts.c_files.len > 0) {
        lib.root_module.addCSourceFiles(.{
            .files = opts.c_files,
        });
    }
    if (opts.macros.len > 0) {
        for (opts.macros) |macro| {
            lib.root_module.addCMacro(macro, "1");
        }
    }
    if (opts.externals.len > 0) {
        for (opts.externals) |external| {
            if (external.os == opts.module.target.result.os.tag) {
                switch (external.type) {
                    .system => lib.root_module.linkSystemLibrary(external.name, .{}),
                    .framework => lib.root_module.linkFramework(external.name, .{}),
                }
            }
        }
    }

    if (opts.module.test_step) |ts| {
        const tests = b.addTest(.{
            .root_module = lib.root_module,
            .name = opts.module.name,
        });
        tests.use_llvm = true;
        const run = b.addRunArtifact(tests);
        ts.dependOn(&run.step);
    }

    if (opts.module.docs_step) |ds| {
        const bin = b.addObject(.{
            .name = opts.module.name,
            .root_module = lib.root_module,
        });
        const docs = b.addInstallDirectory(.{
            .source_dir = bin.getEmittedDocs(),
            .install_subdir = opts.module.name,
            .install_dir = .{ .custom = "docs" },
        });
        ds.dependOn(&docs.step);
    }

    b.installArtifact(lib);
    return lib;
}

const ModuleCreateOptions = struct {
    b: *Build,
    target: Target,
    optimize: Optimize,
    name: []const u8,
    path: []const u8,
    test_step: ?*Step,
    docs_step: ?*Step,
    outside: bool = true,
    imports: []const Import = &.{},
    libc: bool = false,
    libcpp: bool = false,
    fn createOpts(self: *const ModuleCreateOptions) Module.CreateOptions {
        return Module.CreateOptions{
            .optimize = self.optimize,
            .target = self.target,
            .root_source_file = self.b.path(self.path),
            .imports = self.imports,
            .link_libc = self.libc,
            .link_libcpp = self.libcpp,
        };
    }
};

fn createModule(opts: ModuleCreateOptions) *Module {
    const create_opts = opts.createOpts();
    const mod = if (opts.outside) opts.b.addModule(opts.name, create_opts) else opts.b.createModule(create_opts);
    if (opts.test_step) |test_step| {
        const tests = opts.b.addTest(.{
            .root_module = mod,
            .name = opts.name,
        });
        tests.use_llvm = true;
        const run_unit_tests = opts.b.addRunArtifact(tests);
        test_step.dependOn(&run_unit_tests.step);
    }
    if (opts.docs_step) |docs_step| {
        const bin = opts.b.addObject(.{
            .name = opts.name,
            .root_module = mod,
        });
        const docs = opts.b.addInstallDirectory(.{
            .source_dir = bin.getEmittedDocs(),
            .install_subdir = opts.name,
            .install_dir = .{ .custom = "docs" },
        });
        docs_step.dependOn(&docs.step);
    }
    return mod;
}

fn linkBgfx(b: *std.Build, target: std.Build.ResolvedTarget, runtime: *std.Build.Module) !void {
    const zbgfx = @import("zbgfx");
    const zbgfx_dep = b.dependency("zbgfx", .{
        .multithread = false,
    });
    runtime.addImport("bgfx", zbgfx_dep.module("zbgfx"));
    runtime.linkLibrary(zbgfx_dep.artifact("bgfx"));

    const install_shaderc_step = try zbgfx.build_step.installShaderc(b, zbgfx_dep);
    const shaders_includes = &.{ b.path("core/renderer/shaders"), zbgfx_dep.path("shaders") };
    const shaders_module = try zbgfx.build_step.compileShaders(
        b,
        target,
        install_shaderc_step,
        zbgfx_dep,
        shaders_includes,
        &.{
            .{ .name = "fs_basic", .shaderType = .fragment, .path = b.path("core/renderer/shaders/fs_basic.sc") },
            .{ .name = "vs_basic", .shaderType = .vertex, .path = b.path("core/renderer/shaders/vs_basic.sc") },
            .{ .name = "fs_textured", .shaderType = .fragment, .path = b.path("core/renderer/shaders/fs_textured.sc") },
            .{ .name = "vs_textured", .shaderType = .vertex, .path = b.path("core/renderer/shaders/vs_textured.sc") },
            .{ .name = "fs_text", .shaderType = .fragment, .path = b.path("core/renderer/shaders/fs_text.sc") },
            .{ .name = "vs_lit", .shaderType = .vertex, .path = b.path("core/renderer/shaders/vs_lit.sc") },
            .{ .name = "fs_lit", .shaderType = .fragment, .path = b.path("core/renderer/shaders/fs_lit.sc") },
            .{ .name = "vs_pbr", .shaderType = .vertex, .path = b.path("core/renderer/shaders/vs_pbr.sc") },
            .{ .name = "fs_pbr", .shaderType = .fragment, .path = b.path("core/renderer/shaders/fs_pbr.sc") },
            .{ .name = "vs_skybox", .shaderType = .vertex, .path = b.path("core/renderer/shaders/vs_skybox.sc") },
            .{ .name = "fs_skybox", .shaderType = .fragment, .path = b.path("core/renderer/shaders/fs_skybox.sc") },
        },
    );
    runtime.addImport("builtin_shaders", shaders_module);
}
