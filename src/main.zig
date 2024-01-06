const std = @import("std");
const platform = @import("platform");

pub const std_options = struct {
    pub const log_level = .info;
};

const Vertex = struct {
    pub const Layout = platform.Types.VertexLayout{
        .size = @sizeOf(Vertex),
        .vertex = .{
            .dimensions = 3,
            .backing_type = .Float,
            .offset = 0,
        },
        .color = .{
            .dimensions = 4,
            .backing_type = .UByte,
            .offset = 12,
        },
        .texture = .{
            .dimensions = 2,
            .backing_type = .Float,
            .offset = 16,
        },
    };

    pos: [3]f32,
    color: u32,
    texture: [2]f32,
};

pub fn main() !void {
    try platform.base_init();

    try platform.init(.{
        .width = 960,
        .height = 544,
        .title = "Hello, World!",
        .graphics_api = .OpenGL,
    });
    std.log.info("Hello, World!", .{});

    defer platform.deinit();

    var g = platform.Graphics.get_interface();

    var tex = g.load_texture("container.jpg");
    g.set_texture(tex);

    var mesh = try platform.Types.Mesh(Vertex, Vertex.Layout).init();
    defer mesh.deinit();

    try mesh.vertices.append(.{ .pos = [_]f32{ -0.5, -0.5, 0.5 }, .color = 0xFF0000FF, .texture = [_]f32{ 0.0, 0.0 } });
    try mesh.vertices.append(.{ .pos = [_]f32{ 0.5, -0.5, 0.5 }, .color = 0xFFFF0000, .texture = [_]f32{ 1.0, 0.0 } });
    try mesh.vertices.append(.{ .pos = [_]f32{ 0.5, 0.5, 0.5 }, .color = 0xFF00FF00, .texture = [_]f32{ 1.0, 1.0 } });
    try mesh.vertices.append(.{ .pos = [_]f32{ -0.5, 0.5, 0.5 }, .color = 0xFF0000FF, .texture = [_]f32{ 0.0, 1.0 } });

    try mesh.indices.append(0);
    try mesh.indices.append(1);
    try mesh.indices.append(2);
    try mesh.indices.append(2);
    try mesh.indices.append(3);
    try mesh.indices.append(0);

    mesh.update();

    var curr_time = std.time.milliTimestamp();

    while (!g.should_close()) {
        const new_time = std.time.milliTimestamp();
        if (new_time - curr_time > 1000 / 144) {
            platform.poll_events();
            curr_time = new_time;
        }

        g.start_frame();
        mesh.draw();
        g.end_frame();
    }
}
