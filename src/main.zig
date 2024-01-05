const std = @import("std");
const platform = @import("platform");

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
    };

    pos: [3]f32,
    color: u32,
};

pub fn main() !void {
    try platform.base_init();

    try platform.init(.{
        .width = 800,
        .height = 600,
        .title = "Hello, World!",
        .graphics_api = .OpenGL,
    });

    defer platform.deinit();

    var g = platform.Graphics.get_interface();

    var mesh = try platform.Types.Mesh(Vertex, Vertex.Layout).init();
    try mesh.vertices.append(.{ .pos = [_]f32{ -0.5, -0.5, 0.5 }, .color = 0xFF0000FF });
    try mesh.vertices.append(.{ .pos = [_]f32{ 0.5, -0.5, 0.5 }, .color = 0xFFFF0000 });
    try mesh.vertices.append(.{ .pos = [_]f32{ 0.0, 0.5, 0.5 }, .color = 0xFF00FF00 });

    try mesh.indices.append(0);
    try mesh.indices.append(1);
    try mesh.indices.append(2);

    mesh.update();

    while (!g.should_close()) {
        platform.poll_events();
        g.start_frame();

        mesh.draw();

        g.end_frame();
    }
}
