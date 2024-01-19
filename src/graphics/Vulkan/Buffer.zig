const std = @import("std");
const t = @import("../../types.zig");
const vk = @import("vulkan");
const zwin = @import("zwin");
const Allocator = @import("../../allocator.zig");
const Ctx = @import("Context.zig");
const Pipeline = @import("Pipeline.zig");
const shaders = @import("shaders");

pub fn create(size: usize, usage: vk.BufferUsageFlags, memory_property: vk.MemoryPropertyFlags, buffer: *vk.Buffer, memory: *vk.DeviceMemory) !void {
    buffer.* = try Ctx.vkd.createBuffer(Ctx.device, &.{
        .size = @intCast(size),
        .usage = usage,
        .sharing_mode = .exclusive,
    }, null);

    const mem_reqs = Ctx.vkd.getBufferMemoryRequirements(Ctx.device, buffer.*);
    memory.* = try Ctx.allocate(mem_reqs, memory_property);

    try Ctx.vkd.bindBufferMemory(Ctx.device, buffer.*, memory.*, 0);
}

pub fn copy(src: vk.Buffer, dst: vk.Buffer, size: vk.DeviceSize) !void {
    var cmdbuf: vk.CommandBuffer = undefined;
    try Ctx.vkd.allocateCommandBuffers(Ctx.device, &.{
        .command_pool = Pipeline.command_pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast(&cmdbuf));
    defer Ctx.vkd.freeCommandBuffers(Ctx.device, Pipeline.command_pool, 1, @ptrCast(&cmdbuf));

    try Ctx.vkd.beginCommandBuffer(cmdbuf, &.{
        .flags = .{ .one_time_submit_bit = true },
    });

    const region = vk.BufferCopy{
        .src_offset = 0,
        .dst_offset = 0,
        .size = size,
    };
    Ctx.vkd.cmdCopyBuffer(cmdbuf, src, dst, 1, @ptrCast(&region));

    try Ctx.vkd.endCommandBuffer(cmdbuf);

    const si = vk.SubmitInfo{
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&cmdbuf),
        .p_wait_dst_stage_mask = undefined,
    };
    try Ctx.vkd.queueSubmit(Ctx.graphics_queue.handle, 1, @ptrCast(&si), .null_handle);
    try Ctx.vkd.queueWaitIdle(Ctx.graphics_queue.handle);
}
