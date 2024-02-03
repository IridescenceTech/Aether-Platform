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

pub fn get_number_analogs() u32 {
    return 0;
}

pub fn get_analog_state(id: u8) t.AnalogResult {
    if (id > get_number_analogs()) {
        // TODO: Fallback
        return t.AnalogResult{ .x = 0, .y = 0 };
    }

    return t.AnalogResult{ .x = 0, .y = 0 };
}

pub fn get_key_state(id: t.Key) t.KeyState {
    _ = id; // autofix
    return t.KeyState.Released;
}
