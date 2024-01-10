const std = @import("std");
const t = @import("../../types.zig");
const vk = @import("vulkan");
const zwin = @import("zwin");
const Allocator = @import("../../allocator.zig");
const Ctx = @import("Context.zig");

pub const Swapchain = struct {
    pub const PresentState = enum {
        optimal,
        suboptimal,
    };

    surface_format: vk.SurfaceFormatKHR,
    present_mode: vk.PresentModeKHR,
    extent: vk.Extent2D,
    handle: vk.SwapchainKHR,

    swap_images: []SwapImage,
    image_index: u32,
    next_image_acquired: vk.Semaphore,

    pub fn init(extent: vk.Extent2D) !Swapchain {
        return try init_recycle(extent, .null_handle);
    }

    pub fn init_recycle(extent: vk.Extent2D, old_handle: vk.SwapchainKHR) !Swapchain {
        const capabilities = try Ctx.vki.getPhysicalDeviceSurfaceCapabilitiesKHR(Ctx.physical_device, Ctx.surface);
        const actual_extent = find_actual_extent(capabilities, extent);

        if (actual_extent.width == 0 or actual_extent.height == 0) {
            return error.InvalidSurfaceDimensions;
        }

        const surface_format = try find_surface_format();
        const present_mode = try find_present_mode();

        var image_count = capabilities.min_image_count + 1;

        if (capabilities.max_image_count > 0) {
            image_count = @min(image_count, capabilities.max_image_count);
        }

        const qfi = [_]u32{ Ctx.graphics_queue.family, Ctx.present_queue.family };

        const sharing_mode: vk.SharingMode = if (Ctx.graphics_queue.family != Ctx.present_queue.family) .concurrent else .exclusive;

        const handle = try Ctx.vkd.createSwapchainKHR(Ctx.device, &.{
            .surface = Ctx.surface,
            .min_image_count = image_count,
            .image_format = surface_format.format,
            .image_color_space = surface_format.color_space,
            .image_extent = actual_extent,
            .image_array_layers = 1,
            .image_usage = .{ .color_attachment_bit = true, .transfer_dst_bit = true },
            .image_sharing_mode = sharing_mode,
            .queue_family_index_count = qfi.len,
            .p_queue_family_indices = &qfi,
            .pre_transform = capabilities.current_transform,
            .composite_alpha = .{ .opaque_bit_khr = true },
            .present_mode = present_mode,
            .clipped = vk.TRUE,
            .old_swapchain = old_handle,
        }, null);
        errdefer Ctx.vkd.destroySwapchainKHR(Ctx.device, handle, null);

        if (old_handle != .null_handle) {
            Ctx.vkd.destroySwapchainKHR(Ctx.device, old_handle, null);
        }

        const swap_images = try init_swapchain_images(handle, surface_format.format);
        const alloc = try Allocator.allocator();
        errdefer {
            for (swap_images) |si| si.deinit();
            alloc.free(swap_images);
        }

        var next_image_acquired = try Ctx.vkd.createSemaphore(Ctx.device, &.{}, null);
        errdefer Ctx.vkd.destroySemaphore(Ctx.device, next_image_acquired, null);

        const result = try Ctx.vkd.acquireNextImageKHR(Ctx.device, handle, std.math.maxInt(u64), next_image_acquired, .null_handle);
        if (result.result != .success) {
            return error.ImageAcquireFailed;
        }

        std.mem.swap(vk.Semaphore, &swap_images[result.image_index].image_acquired, &next_image_acquired);
        return Swapchain{
            .surface_format = surface_format,
            .present_mode = present_mode,
            .extent = actual_extent,
            .handle = handle,
            .swap_images = swap_images,
            .image_index = result.image_index,
            .next_image_acquired = next_image_acquired,
        };
    }

    fn deinitExceptSwapchain(self: Swapchain) void {
        for (self.swap_images) |si| si.deinit();
        const allocator = Allocator.allocator() catch unreachable;
        allocator.free(self.swap_images);
        Ctx.vkd.destroySemaphore(Ctx.device, self.next_image_acquired, null);
    }

    pub fn waitForAllFences(self: Swapchain) !void {
        for (self.swap_images) |si| si.waitForFence() catch {};
    }

    pub fn deinit(self: Swapchain) void {
        self.deinitExceptSwapchain();
        Ctx.vkd.destroySwapchainKHR(Ctx.device, self.handle, null);
    }

    pub fn recreate(self: *Swapchain, new_extent: vk.Extent2D) !void {
        const old_handle = self.handle;
        self.deinitExceptSwapchain();
        self.* = try init_recycle(new_extent, old_handle);
    }

    pub fn currentImage(self: Swapchain) vk.Image {
        return self.swap_images[self.image_index].image;
    }

    pub fn currentSwapImage(self: Swapchain) *const SwapImage {
        return &self.swap_images[self.image_index];
    }

    fn find_actual_extent(caps: vk.SurfaceCapabilitiesKHR, extent: vk.Extent2D) vk.Extent2D {
        if (caps.current_extent.width != 0xFFFF_FFFF) {
            return caps.current_extent;
        } else {
            return .{
                .width = std.math.clamp(extent.width, caps.min_image_extent.width, caps.max_image_extent.width),
                .height = std.math.clamp(extent.height, caps.min_image_extent.height, caps.max_image_extent.height),
            };
        }
    }

    fn find_present_mode() !vk.PresentModeKHR {
        var count: u32 = undefined;
        _ = try Ctx.vki.getPhysicalDeviceSurfacePresentModesKHR(Ctx.physical_device, Ctx.surface, &count, null);

        const alloc = try Allocator.allocator();
        const present_modes = try alloc.alloc(vk.PresentModeKHR, count);
        defer alloc.free(present_modes);

        _ = try Ctx.vki.getPhysicalDeviceSurfacePresentModesKHR(Ctx.physical_device, Ctx.surface, &count, present_modes.ptr);

        const preferred = [_]vk.PresentModeKHR{
            .mailbox_khr,
            .immediate_khr,
        };

        for (preferred) |mode| {
            if (std.mem.indexOfScalar(vk.PresentModeKHR, present_modes, mode) != null) {
                return mode;
            }
        }

        return .fifo_khr;
    }

    pub fn present(self: *Swapchain, cmdbuf: vk.CommandBuffer) !PresentState {
        // Step 1: Make sure the current frame has finished rendering
        const current = self.currentSwapImage();
        try current.waitForFence();
        try Ctx.vkd.resetFences(Ctx.device, 1, @ptrCast(&current.frame_fence));

        // Step 2: Submit the command buffer
        const wait_stage = [_]vk.PipelineStageFlags{.{ .top_of_pipe_bit = true }};
        try Ctx.vkd.queueSubmit(Ctx.graphics_queue.handle, 1, &[_]vk.SubmitInfo{.{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast(&current.image_acquired),
            .p_wait_dst_stage_mask = &wait_stage,
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&cmdbuf),
            .signal_semaphore_count = 1,
            .p_signal_semaphores = @ptrCast(&current.render_finished),
        }}, current.frame_fence);

        // Step 3: Present the current frame
        _ = try Ctx.vkd.queuePresentKHR(Ctx.present_queue.handle, &.{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @as([*]const vk.Semaphore, @ptrCast(&current.render_finished)),
            .swapchain_count = 1,
            .p_swapchains = @as([*]const vk.SwapchainKHR, @ptrCast(&self.handle)),
            .p_image_indices = @as([*]const u32, @ptrCast(&self.image_index)),
        });

        // Step 4: Acquire next frame
        const result = try Ctx.vkd.acquireNextImageKHR(
            Ctx.device,
            self.handle,
            std.math.maxInt(u64),
            self.next_image_acquired,
            .null_handle,
        );

        std.mem.swap(vk.Semaphore, &self.swap_images[result.image_index].image_acquired, &self.next_image_acquired);
        self.image_index = result.image_index;

        return switch (result.result) {
            .success => .optimal,
            .suboptimal_khr => .suboptimal,
            else => unreachable,
        };
    }

    fn find_surface_format() !vk.SurfaceFormatKHR {
        const preferred = vk.SurfaceFormatKHR{
            .format = .b8g8r8a8_srgb,
            .color_space = .srgb_nonlinear_khr,
        };

        var count: u32 = undefined;
        _ = try Ctx.vki.getPhysicalDeviceSurfaceFormatsKHR(Ctx.physical_device, Ctx.surface, &count, null);

        const alloc = try Allocator.allocator();
        const surface_formats = try alloc.alloc(vk.SurfaceFormatKHR, count);
        defer alloc.free(surface_formats);

        _ = try Ctx.vki.getPhysicalDeviceSurfaceFormatsKHR(Ctx.physical_device, Ctx.surface, &count, surface_formats.ptr);

        for (surface_formats) |sfmt| {
            if (std.meta.eql(sfmt, preferred)) {
                return preferred;
            }
        }

        return surface_formats[0];
    }
};

const SwapImage = struct {
    image: vk.Image,
    view: vk.ImageView,
    image_acquired: vk.Semaphore,
    render_finished: vk.Semaphore,
    frame_fence: vk.Fence,

    fn init(image: vk.Image, format: vk.Format) !SwapImage {
        const view = try Ctx.vkd.createImageView(Ctx.device, &.{
            .image = image,
            .view_type = .@"2d",
            .format = format,
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }, null);
        errdefer Ctx.vkd.destroyImageView(Ctx.device, view, null);

        const image_acquired = try Ctx.vkd.createSemaphore(Ctx.device, &.{}, null);
        errdefer Ctx.vkd.destroySemaphore(Ctx.device, image_acquired, null);

        const render_finished = try Ctx.vkd.createSemaphore(Ctx.device, &.{}, null);
        errdefer Ctx.vkd.destroySemaphore(Ctx.device, render_finished, null);

        const frame_fence = try Ctx.vkd.createFence(Ctx.device, &.{ .flags = .{ .signaled_bit = true } }, null);
        errdefer Ctx.vkd.destroyFence(Ctx.device, frame_fence, null);

        return SwapImage{
            .image = image,
            .view = view,
            .image_acquired = image_acquired,
            .render_finished = render_finished,
            .frame_fence = frame_fence,
        };
    }

    fn deinit(self: SwapImage) void {
        self.waitForFence() catch return;
        Ctx.vkd.destroyImageView(Ctx.device, self.view, null);
        Ctx.vkd.destroySemaphore(Ctx.device, self.image_acquired, null);
        Ctx.vkd.destroySemaphore(Ctx.device, self.render_finished, null);
        Ctx.vkd.destroyFence(Ctx.device, self.frame_fence, null);
    }

    fn waitForFence(self: SwapImage) !void {
        _ = try Ctx.vkd.waitForFences(Ctx.device, 1, @ptrCast(&self.frame_fence), vk.TRUE, std.math.maxInt(u64));
    }
};

fn init_swapchain_images(swapchain: vk.SwapchainKHR, format: vk.Format) ![]SwapImage {
    var count: u32 = undefined;
    _ = try Ctx.vkd.getSwapchainImagesKHR(Ctx.device, swapchain, &count, null);
    const allocator = try Allocator.allocator();
    const images = try allocator.alloc(vk.Image, count);
    defer allocator.free(images);
    _ = try Ctx.vkd.getSwapchainImagesKHR(Ctx.device, swapchain, &count, images.ptr);

    const swap_images = try allocator.alloc(SwapImage, count);
    errdefer allocator.free(swap_images);

    var i: usize = 0;
    errdefer for (swap_images[0..i]) |si| si.deinit();

    for (images) |image| {
        swap_images[i] = try SwapImage.init(image, format);
        i += 1;
    }

    return swap_images;
}
