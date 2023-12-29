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
        self.tab.start_frame(self.ptr);
    }

    /// Sets the vsync mode
    pub fn set_vsync(self: GraphicsEngine, vsync: bool) void {
        self.tab.set_vsync(self.ptr, vsync);
    }

    /// Check if the window or display should close
    pub fn should_close(self: GraphicsEngine) bool {
        return self.tab.should_close(self.ptr);
    }
};

/// Coerces a pointer `ptr` from *anyopaque to type `*T` for a given `T`.
pub fn coerce_ptr(comptime T: type, ptr: *anyopaque) *T {
    return @as(*T, @ptrCast(@alignCast(ptr)));
}
