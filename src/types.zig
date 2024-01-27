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
    title: []const u8 = "Aether Engine",
    width: u16 = 960,
    height: u16 = 544,
    graphics_api: GraphicsAPI = .OpenGL,
};

/// Texture object index
pub const Texture = packed struct {
    /// Index of the texture
    index: u32,

    /// Width of the texture
    width: u16,

    /// Height of the texture
    height: u16,
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

        /// Loads a texture from the given path
        load_texture: *const fn (ctx: *anyopaque, path: []const u8) Texture,

        /// Loads a texture from a buffer
        load_texture_from_buffer: *const fn (ctx: *anyopaque, buffer: []const u8) Texture,

        /// Set the texture to be used for rendering
        set_texture: *const fn (ctx: *anyopaque, texture: Texture) void,

        /// Destroys a texture
        destroy_texture: *const fn (ctx: *anyopaque, texture: Texture) void,
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

    /// Loads a texture from the given path
    pub fn load_texture(self: GraphicsEngine, path: []const u8) Texture {
        return self.tab.load_texture(self.ptr, path);
    }

    /// Loads a texture from a buffer
    pub fn load_texture_from_buffer(self: GraphicsEngine, buffer: []const u8) Texture {
        return self.tab.load_texture_from_buffer(self.ptr, buffer);
    }

    /// Set the texture to be used for rendering
    pub fn set_texture(self: GraphicsEngine, texture: Texture) void {
        self.tab.set_texture(self.ptr, texture);
    }

    /// Destroys a texture
    pub fn destroy_texture(self: GraphicsEngine, texture: Texture) void {
        self.tab.destroy_texture(self.ptr, texture);
    }
};

/// Coerces a pointer `ptr` from *anyopaque to type `*T` for a given `T`.
pub fn coerce_ptr(comptime T: type, ptr: *anyopaque) *T {
    return @as(*T, @ptrCast(@alignCast(ptr)));
}

/// Descriptor for a vertex layout
pub const VertexLayout = struct {
    /// Type of the vertex
    pub const Type = enum {
        Float,
        UByte,
        UShort,
    };

    /// Entry in the vertex layout
    pub const Entry = struct {
        /// Number of dimensions for the entry
        dimensions: usize,

        /// Type of the entry
        backing_type: Type,

        /// Offset of the entry in the vertex
        offset: usize,

        /// Normalize
        normalize: bool,
    };

    /// Total size of the vertex (stride)
    size: usize,

    /// Vertex attribute entry
    vertex: ?Entry = null,

    /// Texture coordinate entry
    texture: ?Entry = null,

    /// Color entry
    color: ?Entry = null,
};

/// Mesh Internal Interface
pub const MeshInternal = struct {
    /// Pointer to the internal mesh object
    ptr: *anyopaque,

    /// Mesh VTable Interface
    tab: MeshInterface,

    /// Size of the Mesh
    size: usize,

    /// Mesh Interface VTable
    pub const MeshInterface = struct {
        /// Creates or updates the mesh with the given vertices and indices
        update: *const fn (ctx: *anyopaque, vertices: *anyopaque, vert_count: usize, indices: *anyopaque, ind_count: usize, layout: *const VertexLayout) void,

        /// Draw the mesh
        draw: *const fn (ctx: *anyopaque) void,

        /// Deinitialize the mesh
        deinit: *const fn (ctx: *anyopaque) void,
    };

    /// Creates or updates the mesh with the given vertices and indices
    pub fn update(self: MeshInternal, vertices: *anyopaque, vert_count: usize, indices: *anyopaque, ind_count: usize, layout: *const VertexLayout) void {
        self.tab.update(self.ptr, vertices, vert_count, indices, ind_count, layout);
    }

    /// Draw the mesh
    pub fn draw(self: MeshInternal) void {
        self.tab.draw(self.ptr);
    }

    /// Deinitialize the mesh
    pub fn deinit(self: MeshInternal) void {
        self.tab.deinit(self.ptr);
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
            if (self.mesh_inst) |*mi| {
                mi.deinit();
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
