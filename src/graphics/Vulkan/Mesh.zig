const std = @import("std");
const t = @import("../../types.zig");
const vk = @import("vulkan");
const zwin = @import("zwin");
const Allocator = @import("../../allocator.zig");
const Ctx = @import("Context.zig");
const Pipeline = @import("Pipeline.zig");
const shaders = @import("shaders");

pub const Mesh = struct {
    vert_buffer: vk.Buffer = undefined,
    vert_memory: vk.DeviceMemory = undefined,
    idx_buffer: vk.Buffer = undefined,
    idx_memory: vk.DeviceMemory = undefined,
    initialized: bool = false,
    idx_count: usize = 0,
    dead: bool = false,

    fn create_buffer(size: usize, usage: vk.BufferUsageFlags, memory_property: vk.MemoryPropertyFlags, buffer: *vk.Buffer, memory: *vk.DeviceMemory) !void {
        buffer.* = try Ctx.vkd.createBuffer(Ctx.device, &.{
            .size = @intCast(size),
            .usage = usage,
            .sharing_mode = .exclusive,
        }, null);

        const mem_reqs = Ctx.vkd.getBufferMemoryRequirements(Ctx.device, buffer.*);
        memory.* = try Ctx.allocate(mem_reqs, memory_property);

        try Ctx.vkd.bindBufferMemory(Ctx.device, buffer.*, memory.*, 0);
    }

    fn copy_buffer(src: vk.Buffer, dst: vk.Buffer, size: vk.DeviceSize) !void {
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

    pub fn update(ctx: *anyopaque, vertices: *anyopaque, vert_count: usize, indices: *anyopaque, ind_count: usize, layout: *const t.VertexLayout) void {
        const vert_size = layout.size * vert_count;
        const idx_size = @sizeOf(u16) * ind_count;

        {
            // Create staging buffer
            var staging_buffer: vk.Buffer = undefined;
            var staging_buffer_memory: vk.DeviceMemory = undefined;
            create_buffer(
                vert_size,
                .{ .transfer_src_bit = true },
                .{ .host_visible_bit = true, .host_coherent_bit = true },
                &staging_buffer,
                &staging_buffer_memory,
            ) catch unreachable;
            defer Ctx.vkd.freeMemory(Ctx.device, staging_buffer_memory, null);
            defer Ctx.vkd.destroyBuffer(Ctx.device, staging_buffer, null);

            // Transfer data from RAM to staging buffer
            {
                const data = Ctx.vkd.mapMemory(Ctx.device, staging_buffer_memory, 0, vk.WHOLE_SIZE, .{}) catch unreachable;
                defer Ctx.vkd.unmapMemory(Ctx.device, staging_buffer_memory);
                const gpu_buffer: [*]u8 = @ptrCast(@alignCast(data));
                const vert_buffer: [*]const u8 = @ptrCast(@alignCast(vertices));

                var i: usize = 0;
                while (i < vert_size) : (i += 1) {
                    gpu_buffer[i] = vert_buffer[i];
                }
            }

            // Create vertex buffer
            const self = t.coerce_ptr(Mesh, ctx);
            create_buffer(
                vert_size,
                .{ .transfer_dst_bit = true, .vertex_buffer_bit = true },
                .{ .device_local_bit = true },
                &self.vert_buffer,
                &self.vert_memory,
            ) catch unreachable;

            copy_buffer(staging_buffer, self.vert_buffer, vert_size) catch unreachable;
        }

        {
            // Create staging buffer
            var staging_buffer: vk.Buffer = undefined;
            var staging_buffer_memory: vk.DeviceMemory = undefined;
            create_buffer(
                idx_size,
                .{ .transfer_src_bit = true },
                .{ .host_visible_bit = true, .host_coherent_bit = true },
                &staging_buffer,
                &staging_buffer_memory,
            ) catch unreachable;
            defer Ctx.vkd.freeMemory(Ctx.device, staging_buffer_memory, null);
            defer Ctx.vkd.destroyBuffer(Ctx.device, staging_buffer, null);

            // Transfer data from RAM to staging buffer
            {
                const data = Ctx.vkd.mapMemory(Ctx.device, staging_buffer_memory, 0, vk.WHOLE_SIZE, .{}) catch unreachable;
                defer Ctx.vkd.unmapMemory(Ctx.device, staging_buffer_memory);
                const gpu_buffer: [*]u8 = @ptrCast(@alignCast(data));
                const idx_buffer: [*]const u8 = @ptrCast(@alignCast(indices));

                var i: usize = 0;
                while (i < idx_size) : (i += 1) {
                    gpu_buffer[i] = idx_buffer[i];
                }
            }

            // Create index buffer
            const self = t.coerce_ptr(Mesh, ctx);
            create_buffer(
                idx_size,
                .{ .transfer_dst_bit = true, .index_buffer_bit = true },
                .{ .device_local_bit = true },
                &self.idx_buffer,
                &self.idx_memory,
            ) catch unreachable;

            copy_buffer(staging_buffer, self.idx_buffer, idx_size) catch unreachable;
            self.idx_count = ind_count;
        }
    }

    pub fn draw(ctx: *anyopaque) void {
        const self = t.coerce_ptr(Mesh, ctx);

        const cmdbuf = Pipeline.current_cmd_buffer.?.*;
        const offsets = [_]vk.DeviceSize{0};
        Ctx.vkd.cmdBindVertexBuffers(cmdbuf, 0, 1, @ptrCast(&self.vert_buffer), &offsets);
        Ctx.vkd.cmdBindIndexBuffer(cmdbuf, self.idx_buffer, 0, .uint16);

        Ctx.vkd.cmdDrawIndexed(cmdbuf, @intCast(self.idx_count), 1, 0, 0, 0);
    }

    pub fn deinit(ctx: *anyopaque) void {
        var self = t.coerce_ptr(Mesh, ctx);
        self.dead = true;
    }

    pub fn gc(self: *Mesh) void {
        if (self.dead) {
            Ctx.vkd.destroyBuffer(Ctx.device, self.idx_buffer, null);
            Ctx.vkd.freeMemory(Ctx.device, self.idx_memory, null);

            Ctx.vkd.destroyBuffer(Ctx.device, self.vert_buffer, null);
            Ctx.vkd.freeMemory(Ctx.device, self.vert_memory, null);
        }
    }

    pub fn interface(self: *Mesh) t.MeshInternal {
        return .{
            .ptr = self,
            .size = @sizeOf(Mesh),
            .tab = .{
                .update = update,
                .draw = draw,
                .deinit = Mesh.deinit,
            },
        };
    }
};

pub const MeshManager = struct {
    list: std.ArrayList(*Mesh) = undefined,

    pub fn init(self: *MeshManager) !void {
        self.list = std.ArrayList(*Mesh).init(try Allocator.allocator());
    }

    pub fn gc(self: *MeshManager) void {
        const alloc = Allocator.allocator() catch unreachable;
        var new_list = std.ArrayList(*Mesh).init(alloc);

        for (self.list.items) |mesh| {
            if (mesh.dead) {
                mesh.gc();
                alloc.destroy(mesh);
            } else {
                new_list.append(mesh) catch unreachable;
            }
        }

        self.list.clearAndFree();
        self.list = new_list;
    }

    pub fn deinit(self: *MeshManager) void {
        const alloc = Allocator.allocator() catch unreachable;

        for (self.list.items) |mesh| {
            mesh.dead = true;
            mesh.gc();
            alloc.destroy(mesh);
        }

        self.list.clearAndFree();
        self.list.deinit();
    }
};
