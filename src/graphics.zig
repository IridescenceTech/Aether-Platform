const Allocator = @import("allocator.zig");
const t = @import("types");

const OGL = @import("graphics/OpenGL.zig");
const VK = @import("graphics/Vulkan.zig");

var engine: t.GraphicsEngine = undefined;

pub fn init(options: t.EngineOptions) !void {
    var alloc = try Allocator.allocator();
    switch (options.graphics_api) {
        .OpenGL => {
            var g = try alloc.create(OGL);
            engine = g.interface();
        },
        .Vulkan => {
            var g = try alloc.create(VK);
            engine = g.interface();
        },
        else => {
            @panic("Unsupported Graphics API!");
        },
    }

    try engine.init(options.width, options.height, options.title);
}

pub fn deinit() void {
    engine.deinit();
}

pub fn get_interface() t.GraphicsEngine {
    return engine;
}
