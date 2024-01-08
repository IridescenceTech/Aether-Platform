pub const Allocator = @import("allocator.zig");
pub const Graphics = @import("graphics.zig");
const zwin = @import("zwin");
const t = @import("types.zig");
const std = @import("std");
const tracy = @import("tracy");
pub const Types = t;

pub fn base_init() !void {
    const f = tracy.traceNamed(@src(), "Base init");
    defer f.end();

    Allocator.init();
    std.log.info("Base initialized", .{});
}

pub fn init(options: t.EngineOptions) !void {
    const f = tracy.trace(@src());
    defer f.end();

    try Graphics.init(options);
    std.log.info("Graphics initialized", .{});
}

pub fn poll_events() void {
    const f = tracy.traceNamed(@src(), "Poll events");
    defer f.end();

    zwin.update();
}

pub fn deinit() void {
    const f = tracy.traceNamed(@src(), "Engine deinit");
    defer f.end();

    Graphics.deinit();
    Allocator.deinit();
}
