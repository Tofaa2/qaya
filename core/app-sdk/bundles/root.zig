const comp = @import("../components/root.zig");

pub const PbrBundle = struct {
    pub const qaya_bundle = true;

    mesh_component: comp.MeshComponent,
    transform: comp.Transform,
    visible: comp.RenderVisible = .{},
};

pub const CameraBundle = struct {
    pub const qaya_bundle = true;

    camera: comp.Camera,
    main_camera: comp.MainCamera = .{},
};

pub const LightBundle = struct {
    pub const qaya_bundle = true;

    light: comp.Light,
};
