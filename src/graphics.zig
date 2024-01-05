const Allocator = @import("allocator.zig");
const t = @import("types.zig");

const OGL = @import("graphics/OpenGL.zig");
const VK = @import("graphics/Vulkan.zig");
const GLES = @import("graphics/GLES.zig");

var engine: t.GraphicsEngine = undefined;
var type_size: usize = 0;

fn allocate_engine(comptime T: type) !*T {
    const size = @sizeOf(T);
    const alloc = try Allocator.allocator();
    var ptr = try alloc.alloc(u8, size);

    var data = @as(*T, @ptrCast(@alignCast(ptr.ptr)));
    data.* = T{};

    return data;
}

pub fn init(options: t.EngineOptions) !void {
    switch (options.graphics_api) {
        .OpenGL => {
            var g = try allocate_engine(OGL);
            engine = g.interface();
            type_size = @sizeOf(OGL);
        },
        .GLES => {
            var g = try allocate_engine(GLES);
            engine = g.interface();
            type_size = @sizeOf(GLES);
        },
        .Vulkan => {
            var g = try allocate_engine(VK);
            engine = g.interface();
            type_size = @sizeOf(VK);
        },
        else => {
            @panic("Unsupported Graphics API!");
        },
    }

    try engine.init(options.width, options.height, options.title);
}

pub fn deinit() void {
    var alloc = Allocator.allocator() catch return;
    var slice: []u8 = undefined;
    slice.len = type_size;
    slice.ptr = @as([*]u8, @ptrCast(engine.ptr));
    alloc.free(slice);
    engine.deinit();
}

pub fn get_interface() t.GraphicsEngine {
    return engine;
}
