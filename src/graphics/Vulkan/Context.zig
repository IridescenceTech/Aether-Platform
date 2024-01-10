const std = @import("std");
const t = @import("../../types.zig");
const vk = @import("vulkan");
const zwin = @import("zwin");
const Allocator = @import("../../allocator.zig");

const required_device_extensions = [_][*:0]const u8{vk.extension_info.khr_swapchain.name};

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

// GLFW Functions
extern fn glfwGetInstanceProcAddress(instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction;
extern fn glfwGetPhysicalDevicePresentationSupport(instance: vk.Instance, pdev: vk.PhysicalDevice, queuefamily: u32) c_int;
extern fn glfwCreateWindowSurface(instance: vk.Instance, window: ?*anyopaque, allocation_callbacks: ?*const vk.AllocationCallbacks, surface: *vk.SurfaceKHR) vk.Result;
extern fn glfwGetRequiredInstanceExtensions(count: *u32) ?[*][*:0]const u8;

pub var vkb: BaseDispatch = undefined;
pub var vki: InstanceDispatch = undefined;
pub var vkd: DeviceDispatch = undefined;

pub var instance: vk.Instance = undefined;
pub var surface: vk.SurfaceKHR = undefined;
pub var physical_device: vk.PhysicalDevice = undefined;
pub var physical_properties: vk.PhysicalDeviceProperties = undefined;
pub var memory_properties: vk.PhysicalDeviceMemoryProperties = undefined;
pub var device: vk.Device = undefined;
pub var graphics_queue: Queue = undefined;
pub var present_queue: Queue = undefined;

pub const Queue = struct {
    handle: vk.Queue,
    family: u32,

    fn init(family: u32) Queue {
        return .{
            .handle = vkd.getDeviceQueue(device, family, 0),
            .family = family,
        };
    }
};

pub fn init(name: [:0]const u8) !void {
    vkb = try BaseDispatch.load(glfwGetInstanceProcAddress);

    var exts_count: u32 = 0;
    const glfw_exts = glfwGetRequiredInstanceExtensions(&exts_count);

    const app_info = vk.ApplicationInfo{
        .p_application_name = name,
        .application_version = vk.makeApiVersion(0, 0, 0, 0),
        .p_engine_name = "Project Aether",
        .engine_version = vk.makeApiVersion(0, 0, 0, 0),
        .api_version = vk.API_VERSION_1_3,
    };

    instance = try vkb.createInstance(&.{
        .p_application_info = &app_info,
        .enabled_extension_count = exts_count,
        .pp_enabled_extension_names = @as([*]const [*:0]const u8, @ptrCast(glfw_exts)),
    }, null);

    vki = try InstanceDispatch.load(instance, vkb.dispatch.vkGetInstanceProcAddr);
    errdefer vki.destroyInstance(instance, null);

    try create_surface();

    const candidate = try pick_physical_device();
    physical_device = candidate.pdev;
    physical_properties = candidate.props;
    std.log.info("Picked device {s}", .{std.mem.sliceTo(&physical_properties.device_name, 0)});

    device = try initialize_candidate(candidate);
    vkd = try DeviceDispatch.load(device, vki.dispatch.vkGetDeviceProcAddr);
    errdefer vkd.destroyDevice(device, null);

    memory_properties = vki.getPhysicalDeviceMemoryProperties(physical_device);
    graphics_queue = Queue.init(candidate.queues.graphics_family);
    present_queue = Queue.init(candidate.queues.present_family);

    std.log.info("Vulkan Context Loaded!", .{});
}

pub fn deinit() void {}

pub fn create_surface() !void {
    if (glfwCreateWindowSurface(instance, zwin.get_api_window(), null, &surface) != .success) {
        return error.SurfaceInitFailed;
    }
}

const DeviceCandidate = struct {
    pdev: vk.PhysicalDevice,
    props: vk.PhysicalDeviceProperties,
    queues: QueueAllocation,
};

const QueueAllocation = struct {
    graphics_family: u32,
    present_family: u32,
};

pub fn pick_physical_device() !DeviceCandidate {
    var device_count: u32 = undefined;
    _ = try vki.enumeratePhysicalDevices(instance, &device_count, null);

    const alloc = try Allocator.allocator();
    const pdevs = try alloc.alloc(vk.PhysicalDevice, device_count);
    defer alloc.free(pdevs);

    _ = try vki.enumeratePhysicalDevices(instance, &device_count, pdevs.ptr);

    std.log.debug("Found {} physical devices", .{pdevs.len});

    for (pdevs) |pdev| {
        if (try check_suitable(pdev)) |candidate| {
            return candidate;
        }
    }

    return error.NoSuitableDevice;
}

pub fn check_surface_support(pdev: vk.PhysicalDevice) !bool {
    var count: u32 = undefined;
    _ = try vki.getPhysicalDeviceSurfaceFormatsKHR(pdev, surface, &count, null);

    var present_mode_count: u32 = undefined;
    _ = try vki.getPhysicalDeviceSurfacePresentModesKHR(pdev, surface, &present_mode_count, null);

    return count > 0 and present_mode_count > 0;
}

pub fn check_extension_support(pdev: vk.PhysicalDevice) !bool {
    var count: u32 = undefined;

    _ = try vki.enumerateDeviceExtensionProperties(pdev, null, &count, null);

    const alloc = try Allocator.allocator();
    const propsv = try alloc.alloc(vk.ExtensionProperties, count);
    defer alloc.free(propsv);

    _ = try vki.enumerateDeviceExtensionProperties(pdev, null, &count, propsv.ptr);

    for (required_device_extensions) |ext| {
        for (propsv) |props| {
            if (std.mem.eql(u8, std.mem.span(ext), std.mem.sliceTo(&props.extension_name, 0))) {
                break;
            }
        } else {
            return false;
        }
    }

    return true;
}

pub fn check_suitable(pdev: vk.PhysicalDevice) !?DeviceCandidate {
    const props = vki.getPhysicalDeviceProperties(pdev);

    if (!try check_extension_support(pdev)) {
        return null;
    }
    std.log.debug("Device has extensions!", .{});

    if (!try check_surface_support(pdev)) {
        return null;
    }
    std.log.debug("Device has surface!", .{});

    if (try allocate_queues(pdev)) |allocation| {
        return DeviceCandidate{
            .pdev = pdev,
            .props = props,
            .queues = allocation,
        };
    }

    return null;
}

pub fn allocate_queues(pdev: vk.PhysicalDevice) !?QueueAllocation {
    var family_count: u32 = undefined;

    vki.getPhysicalDeviceQueueFamilyProperties(pdev, &family_count, null);

    std.log.debug("Found {} queue families", .{family_count});

    const alloc = try Allocator.allocator();
    const families = try alloc.alloc(vk.QueueFamilyProperties, family_count);
    defer alloc.free(families);

    vki.getPhysicalDeviceQueueFamilyProperties(pdev, &family_count, families.ptr);

    var graphics_family: ?u32 = null;
    var present_family: ?u32 = null;

    for (families, 0..) |properties, i| {
        const family: u32 = @intCast(i);

        if (graphics_family == null and properties.queue_flags.graphics_bit) {
            graphics_family = family;
            std.log.debug("Found graphics family!", .{});
        }

        if (present_family == null and (try vki.getPhysicalDeviceSurfaceSupportKHR(pdev, family, surface)) == vk.TRUE) {
            present_family = family;

            std.log.debug("Found present family!", .{});
        }
    }

    if (graphics_family != null and present_family != null) {
        return QueueAllocation{
            .graphics_family = graphics_family.?,
            .present_family = present_family.?,
        };
    }

    return null;
}

pub fn initialize_candidate(candidate: DeviceCandidate) !vk.Device {
    const priority = [_]f32{1};
    const qci = [_]vk.DeviceQueueCreateInfo{ .{
        .queue_family_index = candidate.queues.graphics_family,
        .queue_count = 1,
        .p_queue_priorities = &priority,
    }, .{
        .queue_family_index = candidate.queues.present_family,
        .queue_count = 1,
        .p_queue_priorities = &priority,
    } };

    const queue_count: u32 = if (candidate.queues.graphics_family == candidate.queues.present_family) 1 else 2;

    return try vki.createDevice(candidate.pdev, &.{
        .queue_create_info_count = queue_count,
        .p_queue_create_infos = &qci,
        .enabled_extension_count = required_device_extensions.len,
        .pp_enabled_extension_names = @as([*]const [*:0]const u8, @ptrCast(&required_device_extensions)),
    }, null);
}
