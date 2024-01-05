pub const Allocator = @import("allocator.zig");
pub const Graphics = @import("graphics.zig");
const zwin = @import("zwin");
const t = @import("types.zig");
pub const Types = t;

pub fn base_init() !void {
    Allocator.init();
}

pub fn init(options: t.EngineOptions) !void {
    try Graphics.init(options);
}

pub fn poll_events() void {
    zwin.update();
}

pub fn deinit() void {
    Graphics.deinit();
    Allocator.deinit();
}
