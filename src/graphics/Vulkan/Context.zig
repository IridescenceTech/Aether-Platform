const std = @import("std");
const vk = @import("vulkan");
const zwin = @import("zwin");

const Allocator = @import("../../allocator.zig");
const Self = @This();

const required_extensions = [_][*:0]const u8{vk.extension_info.khr_swapchain.name};

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

const DeviceCandidate = struct {
    pdev: vk.PhysicalDevice,
    props: vk.PhysicalDeviceProperties,
    queues: QueueAllocation,
};

const QueueAllocation = struct {
    graphics_family: u32,
    present_family: u32,
};

pub const Queue = struct {
    handle: vk.Queue,
    family: u32,

    fn init(vkd: DeviceDispatch, dev: vk.Device, family: u32) Queue {
        return .{
            .handle = vkd.getDeviceQueue(dev, family, 0),
            .family = family,
        };
    }
};

vk_base: BaseDispatch = undefined,
vk_instance: InstanceDispatch = undefined,
vk_device: DeviceDispatch = undefined,

instance: vk.Instance = undefined,
surface: vk.SurfaceKHR = undefined,
physical_device: vk.PhysicalDevice = undefined,
properties: vk.PhysicalDeviceProperties = undefined,
memory_properties: vk.PhysicalDeviceMemoryProperties = undefined,
device: vk.Device = undefined,

graphics_queue: Queue = undefined,
present_queue: Queue = undefined,

pub fn init(self: *Self, app_name: [:0]const u8) !void {
    self.vk_base = try BaseDispatch.load(@as(*const fn (vk.Instance, [*:0]const u8) ?*const fn () callconv(.C) void, @ptrCast(&zwin.getVKProcAddr)));

    var glfw_exts_count: u32 = 0;
    const glfw_exts = zwin.getRequiredInstanceExtensions(&glfw_exts_count);

    const app_info = vk.ApplicationInfo{
        .p_application_name = app_name,
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

    const candidate = try self.pick_physical_device();
    self.physical_device = candidate.pdev;
    self.properties = candidate.props;

    self.device = try self.initialize_candidate(candidate);
    self.vk_device = try DeviceDispatch.load(self.device, self.vk_instance.dispatch.vkGetDeviceProcAddr);
    errdefer self.vk_device.destroyDevice(self.dev, null);

    self.graphics_queue = Queue.init(self.vk_device, self.device, candidate.queues.graphics_family);
    self.present_queue = Queue.init(self.vk_device, self.device, candidate.queues.present_family);

    self.memory_properties = self.vk_instance.getPhysicalDeviceMemoryProperties(self.physical_device);
    std.debug.print("Using device: {s}\n", .{std.mem.sliceTo(&self.properties.device_name, 0)});
}

fn create_surface(self: *Self) !vk.SurfaceKHR {
    var surface: vk.SurfaceKHR = undefined;

    var cws: *const fn (vk.Instance, allocation_callbacks: ?*const vk.AllocationCallbacks, surface: *vk.SurfaceKHR) vk.Result = @ptrCast(&zwin.createWindowSurface);

    if (cws(self.instance, null, &surface) != .success) {
        return error.SurfaceCreationFailed;
    }

    return surface;
}

fn pick_physical_device(self: *Self) !DeviceCandidate {
    var device_count: u32 = undefined;

    _ = try self.vk_instance.enumeratePhysicalDevices(self.instance, &device_count, null);

    if (device_count == 0) {
        return error.NoSuitableDevice;
    }

    const alloc = try Allocator.allocator();
    const pdevs = try alloc.alloc(vk.PhysicalDevice, device_count);
    defer alloc.free(pdevs);

    _ = try self.vk_instance.enumeratePhysicalDevices(self.instance, &device_count, pdevs.ptr);

    for (pdevs) |pdev| {
        if (try self.check_device(pdev)) |candidate| {
            return candidate;
        }
    }

    return error.NoSuitableDevice;
}

fn check_device(self: *Self, pdev: vk.PhysicalDevice) !?DeviceCandidate {
    const props = self.vk_instance.getPhysicalDeviceProperties(pdev);

    if (!try self.check_extension_support(pdev)) {
        return null;
    }

    if (!try self.check_surface_support(pdev)) {
        return null;
    }

    if (try self.allocate_queues(pdev)) |allocation| {
        return DeviceCandidate{
            .pdev = pdev,
            .props = props,
            .queues = allocation,
        };
    }

    return null;
}

fn check_surface_support(self: *Self, pdev: vk.PhysicalDevice) !bool {
    var format_count: u32 = undefined;
    var present_mode_count: u32 = undefined;

    _ = try self.vk_instance.getPhysicalDeviceSurfaceFormatsKHR(pdev, self.surface, &format_count, null);
    _ = try self.vk_instance.getPhysicalDeviceSurfacePresentModesKHR(pdev, self.surface, &present_mode_count, null);

    return format_count > 0 and present_mode_count > 0;
}

fn check_extension_support(self: *Self, pdev: vk.PhysicalDevice) !bool {
    var count: u32 = undefined;
    _ = try self.vk_instance.enumerateDeviceExtensionProperties(pdev, null, &count, null);

    const alloc = try Allocator.allocator();
    const propsv = try alloc.alloc(vk.ExtensionProperties, count);
    defer alloc.free(propsv);

    _ = try self.vk_instance.enumerateDeviceExtensionProperties(pdev, null, &count, propsv.ptr);

    for (required_extensions) |ext| {
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

fn allocate_queues(self: *Self, pdev: vk.PhysicalDevice) !?QueueAllocation {
    var family_count: u32 = undefined;
    self.vk_instance.getPhysicalDeviceQueueFamilyProperties(pdev, &family_count, null);

    const alloc = try Allocator.allocator();
    const families = try alloc.alloc(vk.QueueFamilyProperties, family_count);
    defer alloc.free(families);

    self.vk_instance.getPhysicalDeviceQueueFamilyProperties(pdev, &family_count, families.ptr);

    var graphics_family: ?u32 = null;
    var present_family: ?u32 = null;

    for (families, 0..) |properties, i| {
        const family: u32 = @intCast(i);

        if (graphics_family == null and properties.queue_flags.graphics_bit) {
            graphics_family = family;
        }

        if (present_family == null and (try self.vk_instance.getPhysicalDeviceSurfaceSupportKHR(pdev, family, self.surface)) == vk.TRUE) {
            present_family = family;
        }
    }

    if (graphics_family == null or present_family == null) {
        return null;
    }

    return QueueAllocation{
        .graphics_family = graphics_family.?,
        .present_family = present_family.?,
    };
}

fn initialize_candidate(self: *Self, candidate: DeviceCandidate) !vk.Device {
    const priority = [_]f32{1};
    const qci = [_]vk.DeviceQueueCreateInfo{
        .{
            .queue_family_index = candidate.queues.graphics_family,
            .queue_count = 1,
            .p_queue_priorities = &priority,
        },
        .{
            .queue_family_index = candidate.queues.present_family,
            .queue_count = 1,
            .p_queue_priorities = &priority,
        },
    };

    const queue_count: u32 = if (candidate.queues.graphics_family == candidate.queues.present_family)
        1
    else
        2;

    return try self.vk_instance.createDevice(candidate.pdev, &.{
        .queue_create_info_count = queue_count,
        .p_queue_create_infos = &qci,
        .enabled_extension_count = required_extensions.len,
        .pp_enabled_extension_names = @as([*]const [*:0]const u8, @ptrCast(&required_extensions)),
    }, null);
}
