const std = @import("std");
const platform = @import("platform");

pub fn main() !void {
    try platform.base_init();

    try platform.init(.{
        .width = 800,
        .height = 600,
        .title = "Hello, World!",
        .graphics_api = .GLES,
    });

    defer platform.deinit();

    var g = platform.Graphics.get_interface();
    while (!g.should_close()) {
        platform.poll_events();
        g.start_frame();

        g.end_frame();
    }
}
