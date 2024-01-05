const std = @import("std");
const allocator = @import("allocator.zig");
const graphics = @import("graphics.zig");

/// Graphics APIs
pub const GraphicsAPI = enum {
    DirectX,
    GLES,
    OpenGL,
    Vulkan,
};

/// Options for the game engine
pub const EngineOptions = struct {
    title: []const u8,
    width: u16,
    height: u16,
    graphics_api: GraphicsAPI,
};

/// GraphicsEngine is an interface to an underlying Graphics API (Vulkan, OpenGL, etc.)
/// This interface includes the window/screen surface
pub const GraphicsEngine = struct {
    ptr: *anyopaque,
    tab: GraphicsVTable,

    /// Graphics Interface
    pub const GraphicsVTable = struct {
        /// Creates the graphics context with requested window width, height, and title
        /// Some platforms may not support width, height, and title -- these will then have no effect.
        /// This method may return an error for window or context failures.
        init: *const fn (ctx: *anyopaque, width: u16, height: u16, title: []const u8) anyerror!void,

        /// Destroy the graphics context and window
        deinit: *const fn (ctx: *anyopaque) void,

        /// Starts a frame, begins recording commands
        start_frame: *const fn (ctx: *anyopaque) void,

        /// Ends a frame, sends commands to GPU
        end_frame: *const fn (ctx: *anyopaque) void,

        /// Sets the vsync mode
        set_vsync: *const fn (ctx: *anyopaque, vsync: bool) void,

        /// Check if the window or display should close
        should_close: *const fn (ctx: *anyopaque) bool,

        /// Creates an internal mesh object
        create_mesh_internal: *const fn (ctx: *anyopaque) MeshInternal,
    };

    /// Initializes the graphics engine with the given options
    pub fn init(self: GraphicsEngine, width: u16, height: u16, title: []const u8) anyerror!void {
        try self.tab.init(self.ptr, width, height, title);
    }

    /// Deinitializes the graphics engine
    pub fn deinit(self: GraphicsEngine) void {
        self.tab.deinit(self.ptr);
    }

    /// Starts a frame, begins recording commands
    pub fn start_frame(self: GraphicsEngine) void {
        self.tab.start_frame(self.ptr);
    }

    /// Ends a frame, sends commands to GPU
    pub fn end_frame(self: GraphicsEngine) void {
        self.tab.end_frame(self.ptr);
    }

    /// Sets the vsync mode
    pub fn set_vsync(self: GraphicsEngine, vsync: bool) void {
        self.tab.set_vsync(self.ptr, vsync);
    }

    /// Check if the window or display should close
    pub fn should_close(self: GraphicsEngine) bool {
        return self.tab.should_close(self.ptr);
    }

    /// Creates an internal mesh object
    pub fn create_mesh_internal(self: GraphicsEngine) MeshInternal {
        return self.tab.create_mesh_internal(self.ptr);
    }
};

/// Coerces a pointer `ptr` from *anyopaque to type `*T` for a given `T`.
pub fn coerce_ptr(comptime T: type, ptr: *anyopaque) *T {
    return @as(*T, @ptrCast(@alignCast(ptr)));
}

pub const VertexLayout = struct {
    pub const Type = enum {
        Float,
        UByte,
        UShort,
    };

    pub const Entry = struct {
        dimensions: usize,
        backing_type: Type,
        offset: usize,
    };

    size: usize,
    vertex: ?Entry = null,
    texture: ?Entry = null,
    color: ?Entry = null,
};

pub const MeshInternal = struct {
    ptr: *anyopaque,
    tab: MeshInterface,
    size: usize,
    dead: bool = false,

    pub const MeshInterface = struct {
        update: *const fn (ctx: *anyopaque, vertices: *anyopaque, vert_count: usize, indices: *anyopaque, ind_count: usize, layout: *const VertexLayout) void,
        draw: *const fn (ctx: *anyopaque) void,
    };

    pub fn update(self: MeshInternal, vertices: *anyopaque, vert_count: usize, indices: *anyopaque, ind_count: usize, layout: *const VertexLayout) void {
        self.tab.update(self.ptr, vertices, vert_count, indices, ind_count, layout);
    }

    pub fn draw(self: MeshInternal) void {
        self.tab.draw(self.ptr);
    }
};

/// Mesh Object
pub fn Mesh(comptime T: type, comptime V: VertexLayout) type {
    return struct {
        vertices: std.ArrayList(T),
        indices: std.ArrayList(u16),
        mesh_inst: ?MeshInternal = null,

        const Self = @This();

        /// Create the mesh
        pub fn init() !Self {
            const alloc = try allocator.allocator();
            return Self{
                .vertices = std.ArrayList(T).init(alloc),
                .indices = std.ArrayList(u16).init(alloc),
                .mesh_inst = null,
            };
        }

        /// Destroy the mesh
        pub fn deinit(self: *Self) void {
            if (self.mesh_inst) |mi| {
                mi.dead = true;
            }

            self.vertices.clearAndFree();
            self.indices.clearAndFree();

            self.vertices.deinit();
            self.indices.deinit();
        }

        /// Update the mesh to the new state
        pub fn update(self: *Self) void {
            if (self.mesh_inst == null) {
                const interface = graphics.get_interface();
                self.mesh_inst = interface.create_mesh_internal();

                std.log.info("{}", .{self.mesh_inst.?.size});
            }

            if (self.mesh_inst) |mi| {
                mi.update(self.vertices.items.ptr, self.vertices.items.len, self.indices.items.ptr, self.indices.items.len, &V);
            }
        }

        /// Draw the mesh
        pub fn draw(self: *Self) void {
            if (self.mesh_inst) |mi| {
                mi.draw();
            }
        }
    };
}
