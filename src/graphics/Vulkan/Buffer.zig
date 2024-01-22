const std = @import("std");
const t = @import("../../types.zig");
const vk = @import("vulkan");
const zwin = @import("zwin");
const Allocator = @import("../../allocator.zig");
const Ctx = @import("Context.zig");
const Pipeline = @import("Pipeline.zig");
const shaders = @import("shaders");
const Util = @import("Util.zig");

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
    const cmdbuf = try Util.begin_cmdbuf_single();

    const region = vk.BufferCopy{
        .src_offset = 0,
        .dst_offset = 0,
        .size = size,
    };
    Ctx.vkd.cmdCopyBuffer(cmdbuf, src, dst, 1, @ptrCast(&region));

    try Util.end_cmdbuf_single(cmdbuf);
}
