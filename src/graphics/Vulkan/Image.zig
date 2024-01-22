const std = @import("std");
const t = @import("../../types.zig");
const vk = @import("vulkan");
const zwin = @import("zwin");
const Allocator = @import("../../allocator.zig");
const Ctx = @import("Context.zig");
const Pipeline = @import("Pipeline.zig");
const shaders = @import("shaders");
const Buffer = @import("Buffer.zig");
const Util = @import("Util.zig");

pub fn create(
    width: u32,
    height: u32,
    format: vk.Format,
    tiling: vk.ImageTiling,
    usage: vk.ImageUsageFlags,
    properties: vk.MemoryPropertyFlags,
    image: *vk.Image,
    memory: *vk.DeviceMemory,
) !void {
    image.* = try Ctx.vkd.createImage(
        Ctx.device,
        &.{
            .image_type = .@"2d",
            .mip_levels = 1,
            .array_layers = 1,
            .format = format,
            .extent = .{
                .width = width,
                .height = height,
                .depth = 1,
            },
            .samples = .{ .@"1_bit" = true },
            .tiling = tiling,
            .usage = usage,
            .sharing_mode = .exclusive,
            .initial_layout = .undefined,
        },
        null,
    );

    const requirements = Ctx.vkd.getImageMemoryRequirements(Ctx.device, image.*);
    memory.* = try Ctx.allocate(requirements, properties);

    try Ctx.vkd.bindImageMemory(Ctx.device, image.*, memory.*, 0);
}

fn copy_buffer_to_image(buffer: vk.Buffer, image: vk.Image, width: u32, height: u32) !void {
    const cmdbuf = try Util.begin_cmdbuf_single();

    const region = [_]vk.BufferImageCopy{
        .{
            .buffer_offset = 0,
            .buffer_row_length = 0,
            .buffer_image_height = 0,
            .image_subresource = .{ .aspect_mask = .{ .color_bit = true }, .mip_level = 0, .base_array_layer = 0, .layer_count = 1 },
            .image_offset = .{
                .x = 0,
                .y = 0,
                .z = 0,
            },
            .image_extent = .{
                .width = width,
                .height = height,
                .depth = 1,
            },
        },
    };
    Ctx.vkd.cmdCopyBufferToImage(cmdbuf, buffer, image, .transfer_dst_optimal, region.len, &region);

    try Util.end_cmdbuf_single(cmdbuf);
}

pub fn create_image_view(image: vk.Image, format: vk.Format) !vk.ImageView {
    return try Ctx.vkd.createImageView(Ctx.device, &.{
        .image = image,
        .view_type = .@"2d",
        .format = format,
        .components = .{
            .r = .r,
            .g = .g,
            .b = .b,
            .a = .a,
        },
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    }, null);
}

pub fn create_texture_sampler(mag: vk.Filter, min: vk.Filter) !vk.Sampler {
    return try Ctx.vkd.createSampler(Ctx.device, &.{
        .mag_filter = mag,
        .min_filter = min,
        .mipmap_mode = if (mag == .linear or min == .linear) .linear else .nearest,
        .address_mode_u = .repeat,
        .address_mode_v = .repeat,
        .address_mode_w = .repeat,
        .mip_lod_bias = 0.0,
        .min_lod = 0.0,
        .max_lod = 0.0,
        .compare_enable = vk.FALSE,
        .compare_op = undefined,
        .unnormalized_coordinates = vk.FALSE,
        .border_color = .int_opaque_black,
        .anisotropy_enable = vk.FALSE,
        .max_anisotropy = undefined,
    }, null);
}

fn transition_image_layout(image: vk.Image, format: vk.Format, old_layout: vk.ImageLayout, new_layout: vk.ImageLayout) !void {
    _ = format; // TODO: Depth buffers
    const cmdbuf = try Util.begin_cmdbuf_single();

    var barrier = [_]vk.ImageMemoryBarrier{
        .{
            .old_layout = old_layout,
            .new_layout = new_layout,
            .src_queue_family_index = 0, // Ignore
            .dst_queue_family_index = 0, // Ignore
            .image = image,
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
            .src_access_mask = undefined,
            .dst_access_mask = undefined,
        },
    };

    var source_stage: vk.PipelineStageFlags = undefined;
    var destination_stage: vk.PipelineStageFlags = undefined;

    if (old_layout == .undefined and new_layout == .transfer_dst_optimal) {
        barrier[0].src_access_mask = .{};
        barrier[0].dst_access_mask = .{ .transfer_write_bit = true };

        source_stage = .{ .top_of_pipe_bit = true };
        destination_stage = .{ .transfer_bit = true };
    } else if (old_layout == .transfer_dst_optimal and new_layout == .shader_read_only_optimal) {
        barrier[0].src_access_mask = .{ .transfer_write_bit = true };
        barrier[0].dst_access_mask = .{ .shader_read_bit = true };

        source_stage = .{ .transfer_bit = true };
        destination_stage = .{ .fragment_shader_bit = true };
    } else {
        return error.InvalidTransition;
    }

    Ctx.vkd.cmdPipelineBarrier(
        cmdbuf,
        source_stage,
        destination_stage,
        .{},
        0,
        null,
        0,
        null,
        barrier.len,
        &barrier,
    );

    try Util.end_cmdbuf_single(cmdbuf);
}

pub fn create_tex_image(width: u32, height: u32, buf: []const u8, image: *vk.Image, memory: *vk.DeviceMemory, format: vk.Format) !void {
    var staging_buffer: vk.Buffer = undefined;
    var staging_memory: vk.DeviceMemory = undefined;

    try Buffer.create(
        buf.len,
        .{ .transfer_src_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        &staging_buffer,
        &staging_memory,
    );
    defer Ctx.vkd.destroyBuffer(Ctx.device, staging_buffer, null);
    defer Ctx.vkd.freeMemory(Ctx.device, staging_memory, null);

    {
        const data = try Ctx.vkd.mapMemory(Ctx.device, staging_memory, 0, buf.len, .{});
        defer Ctx.vkd.unmapMemory(Ctx.device, staging_memory);
        const pixels: [*]u8 = @ptrCast(@alignCast(data));

        var i: usize = 0;
        while (i < buf.len) : (i += 1) {
            pixels[i] = buf[i];
        }
    }

    try create(
        width,
        height,
        format,
        .optimal,
        .{ .transfer_dst_bit = true, .sampled_bit = true },
        .{ .device_local_bit = true },
        image,
        memory,
    );

    try transition_image_layout(image.*, format, .undefined, .transfer_dst_optimal);

    try copy_buffer_to_image(staging_buffer, image.*, width, height);

    try transition_image_layout(image.*, format, .transfer_dst_optimal, .shader_read_only_optimal);
}
