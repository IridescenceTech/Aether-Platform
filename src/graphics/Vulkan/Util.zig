const std = @import("std");
const t = @import("../../types.zig");
const vk = @import("vulkan");
const zwin = @import("zwin");
const Allocator = @import("../../allocator.zig");
const Ctx = @import("Context.zig");
const Pipeline = @import("Pipeline.zig");
const shaders = @import("shaders");

pub fn begin_cmdbuf_single() !vk.CommandBuffer {
    var cmdbuf: vk.CommandBuffer = undefined;
    try Ctx.vkd.allocateCommandBuffers(Ctx.device, &.{
        .command_pool = Pipeline.command_pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast(&cmdbuf));

    try Ctx.vkd.beginCommandBuffer(cmdbuf, &.{
        .flags = .{ .one_time_submit_bit = true },
    });

    return cmdbuf;
}

pub fn end_cmdbuf_single(cmdbuf: vk.CommandBuffer) !void {
    try Ctx.vkd.endCommandBuffer(cmdbuf);
    defer Ctx.vkd.freeCommandBuffers(Ctx.device, Pipeline.command_pool, 1, @ptrCast(&cmdbuf));

    const si = vk.SubmitInfo{
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&cmdbuf),
        .p_wait_dst_stage_mask = undefined,
    };

    try Ctx.vkd.queueSubmit(Ctx.graphics_queue.handle, 1, @ptrCast(&si), .null_handle);
    try Ctx.vkd.queueWaitIdle(Ctx.graphics_queue.handle);
}
