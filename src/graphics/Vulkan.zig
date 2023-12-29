const std = @import("std");
const vk = @import("vulkan");
const Allocator = @import("../allocator.zig");
const t = @import("types");
const zwin = @import("zwin");
const Self = @This();

const BaseDispatch = vk.BaseWrapper(.{
    .createInstance = true,
    .getInstanceProcAddr = true,
});

const InstanceDispatch = vk.InstanceWrapper(.{
    .destroyInstance = true,
    .createDevice = true,
    .destroySurfaceKHR = true,
    .enumeratePhysicalDevices = true,
    .getPhysicalDeviceProperties = true,
    .enumerateDeviceExtensionProperties = true,
    .getPhysicalDeviceSurfaceFormatsKHR = true,
    .getPhysicalDeviceSurfacePresentModesKHR = true,
    .getPhysicalDeviceSurfaceCapabilitiesKHR = true,
    .getPhysicalDeviceQueueFamilyProperties = true,
    .getPhysicalDeviceSurfaceSupportKHR = true,
    .getPhysicalDeviceMemoryProperties = true,
    .getDeviceProcAddr = true,
});

const DeviceDispatch = vk.DeviceWrapper(.{
    .destroyDevice = true,
    .getDeviceQueue = true,
    .createSemaphore = true,
    .createFence = true,
    .createImageView = true,
    .destroyImageView = true,
    .destroySemaphore = true,
    .destroyFence = true,
    .getSwapchainImagesKHR = true,
    .createSwapchainKHR = true,
    .destroySwapchainKHR = true,
    .acquireNextImageKHR = true,
    .deviceWaitIdle = true,
    .waitForFences = true,
    .resetFences = true,
    .queueSubmit = true,
    .queuePresentKHR = true,
    .createCommandPool = true,
    .destroyCommandPool = true,
    .allocateCommandBuffers = true,
    .freeCommandBuffers = true,
    .queueWaitIdle = true,
    .createShaderModule = true,
    .destroyShaderModule = true,
    .createPipelineLayout = true,
    .destroyPipelineLayout = true,
    .createRenderPass = true,
    .destroyRenderPass = true,
    .createGraphicsPipelines = true,
    .destroyPipeline = true,
    .createFramebuffer = true,
    .destroyFramebuffer = true,
    .beginCommandBuffer = true,
    .endCommandBuffer = true,
    .allocateMemory = true,
    .freeMemory = true,
    .createBuffer = true,
    .destroyBuffer = true,
    .getBufferMemoryRequirements = true,
    .mapMemory = true,
    .unmapMemory = true,
    .bindBufferMemory = true,
    .cmdBeginRenderPass = true,
    .cmdEndRenderPass = true,
    .cmdBindPipeline = true,
    .cmdDraw = true,
    .cmdSetViewport = true,
    .cmdSetScissor = true,
    .cmdBindVertexBuffers = true,
    .cmdCopyBuffer = true,
});

vk_base: BaseDispatch = undefined,
vk_instance: InstanceDispatch = undefined,
vk_device: DeviceDispatch = undefined,

instance: vk.Instance = undefined,
surface: vk.SurfaceKHR = undefined,

pub fn init(ctx: *anyopaque, width: u16, height: u16, title: []const u8) anyerror!void {
    var self = t.coerce_ptr(Self, ctx);
    try zwin.init(.Vulkan, 1, 3);

    const alloc = try Allocator.allocator();
    var copy = try alloc.dupeZ(u8, title);
    defer alloc.free(copy);

    try zwin.createWindow(width, height, copy, false);

    self.vk_base = try BaseDispatch.load(@as(*const fn (vk.Instance, [*:0]const u8) ?*const fn () callconv(.C) void, @ptrCast(&zwin.getVKProcAddr)));

    var glfw_exts_count: u32 = 0;
    const glfw_exts = zwin.getRequiredInstanceExtensions(&glfw_exts_count);

    const app_info = vk.ApplicationInfo{
        .p_application_name = copy,
        .application_version = vk.makeApiVersion(0, 0, 0, 0),
        .p_engine_name = "Project Aether",
        .engine_version = vk.makeApiVersion(0, 0, 0, 0),
        .api_version = vk.API_VERSION_1_3,
    };

    self.instance = try self.vk_base.createInstance(&.{
        .p_application_info = &app_info,
        .enabled_extension_count = glfw_exts_count,
        .pp_enabled_extension_names = @as([*]const [*:0]const u8, @ptrCast(glfw_exts)),
    }, null);

    self.vk_instance = try InstanceDispatch.load(self.instance, self.vk_base.dispatch.vkGetInstanceProcAddr);
    errdefer self.vk_instance.destroyInstance(self.instance, null);

    self.surface = try self.create_surface();
    errdefer self.vk_instance.destroySurfaceKHR(self.instance, self.surface, null);

    //TODO: START HERE
    const candidate = try pick_physical_device(self.vk_instance, self.instance, allocator, self.surface);
    self.pdev = candidate.pdev;
    self.props = candidate.props;
    self.dev = try initializeCandidate(self.vk_instance, candidate);
    self.vk_device = try DeviceDispatch.load(self.dev, self.vk_instance.dispatch.vkGetDeviceProcAddr);
    errdefer self.vk_device.destroyDevice(self.dev, null);

    self.graphics_queue = Queue.init(self.vk_device, self.dev, candidate.queues.graphics_family);
    self.present_queue = Queue.init(self.vk_device, self.dev, candidate.queues.present_family);

    self.mem_props = self.vki.getPhysicalDeviceMemoryProperties(self.pdev);
}

pub fn deinit(ctx: *anyopaque) void {
    _ = ctx;

    zwin.deinit();
}

pub fn start_frame(ctx: *anyopaque) void {
    _ = ctx;
}

pub fn end_frame(ctx: *anyopaque) void {
    _ = ctx;
}

pub fn set_vsync(ctx: *anyopaque, vsync: bool) void {
    _ = ctx;
    zwin.setVsync(vsync);
}

pub fn should_close(ctx: *anyopaque) bool {
    _ = ctx;
    return zwin.shouldClose();
}

pub fn interface(self: *Self) t.GraphicsEngine {
    return .{
        .ptr = self,
        .tab = .{
            .init = init,
            .deinit = deinit,
            .start_frame = start_frame,
            .end_frame = end_frame,
            .set_vsync = set_vsync,
            .should_close = should_close,
        },
    };
}

fn create_surface(self: *Self) !vk.SurfaceKHR {
    var surface: vk.SurfaceKHR = undefined;

    var cws: *const fn (vk.Instance, allocation_callbacks: ?*const vk.AllocationCallbacks, surface: *vk.SurfaceKHR) vk.Result = @ptrCast(&zwin.createWindowSurface);

    if (cws(self.instance, null, &surface) != .success) {
        return error.SurfaceCreationFailed;
    }

    return surface;
}
