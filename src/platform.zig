pub const Allocator = @import("allocator.zig");
pub const Graphics = @import("graphics.zig");
const zwin = @import("zwin");
const t = @import("types.zig");
const std = @import("std");
pub const Types = t;

pub fn base_init() !void {
    Allocator.init();
    std.log.info("Base initialized", .{});
}

pub fn init(options: t.EngineOptions) !void {
    try Graphics.init(options);
    std.log.info("Graphics initialized", .{});
}

pub fn poll_events() void {
    zwin.update();
}

pub fn deinit() void {
    Graphics.deinit();
    Allocator.deinit();
}
