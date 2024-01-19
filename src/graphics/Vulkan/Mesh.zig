const std = @import("std");
const t = @import("../../types.zig");
const vk = @import("vulkan");
const zwin = @import("zwin");
const Allocator = @import("../../allocator.zig");
const Ctx = @import("Context.zig");
const Pipeline = @import("Pipeline.zig");
const shaders = @import("shaders");
const Buffer = @import("Buffer.zig");

pub const POSITION_ATTRIBUTE = 0;
pub const COLOR_ATTRIBUTE = 1;
pub const TEXTURE_ATTRIBUTE = 2;

pub const Mesh = struct {
    pub const Flags = packed struct {
        texture_enabled: u1,
        color_enabled: u1,
        fixed_point5: u1,
        reserved: u29,
    };

    vert_buffer: vk.Buffer = undefined,
    vert_memory: vk.DeviceMemory = undefined,
    idx_buffer: vk.Buffer = undefined,
    idx_memory: vk.DeviceMemory = undefined,
    initialized: bool = false,
    idx_count: usize = 0,
    dead: bool = false,
    flags: Flags = undefined,
    constants: Pipeline.PushConstants = Pipeline.PushConstants{},

    bindings: std.ArrayList(vk.VertexInputBindingDescription2EXT) = undefined,
    attributes: std.ArrayList(vk.VertexInputAttributeDescription2EXT) = undefined,

    fn get_format(dimensions: usize, normalized: bool, backing: t.VertexLayout.Type) vk.Format {
        if (backing == .Float) {
            return switch (dimensions) {
                1 => .r32_sfloat,
                2 => .r32g32_sfloat,
                3 => .r32g32b32_sfloat,
                4 => .r32g32b32a32_sfloat,
                else => unreachable,
            };
        } else if (backing == .UByte) {
            return switch (dimensions) {
                1 => if (normalized) .r8_unorm else .r8_uint,
                2 => if (normalized) .r8g8_unorm else .r8g8_uint,
                3 => if (normalized) .r8g8b8_unorm else .r8g8b8_uint,
                4 => if (normalized) .r8g8b8a8_unorm else .r8g8b8a8_uint,
                else => unreachable,
            };
        }

        return .r32g32b32_sfloat;
    }

    pub fn update(ctx: *anyopaque, vertices: *anyopaque, vert_count: usize, indices: *anyopaque, ind_count: usize, layout: *const t.VertexLayout) void {
        const self = t.coerce_ptr(Mesh, ctx);
        const alloc = Allocator.allocator() catch unreachable;

        if (!self.initialized) {
            self.bindings = std.ArrayList(vk.VertexInputBindingDescription2EXT).init(alloc);
            self.bindings.append(.{
                .binding = 0,
                .stride = @intCast(layout.size),
                .input_rate = .vertex,
                .divisor = 1,
            }) catch unreachable;

            self.attributes = std.ArrayList(vk.VertexInputAttributeDescription2EXT).init(alloc);

            if (layout.vertex) |entry| {
                self.attributes.append(vk.VertexInputAttributeDescription2EXT{
                    .binding = 0,
                    .location = POSITION_ATTRIBUTE,
                    .offset = @intCast(entry.offset),
                    .format = get_format(entry.dimensions, entry.normalize, entry.backing_type),
                }) catch unreachable;

                if (entry.backing_type == t.VertexLayout.Type.UShort) {
                    self.flags.fixed_point5 = 1;
                } else {
                    self.flags.fixed_point5 = 0;
                }
            } else {
                self.flags.fixed_point5 = 0;
            }

            if (layout.color) |entry| {
                self.attributes.append(vk.VertexInputAttributeDescription2EXT{
                    .binding = 0,
                    .location = COLOR_ATTRIBUTE,
                    .offset = @intCast(entry.offset),
                    .format = get_format(entry.dimensions, entry.normalize, entry.backing_type),
                }) catch unreachable;

                self.flags.color_enabled = 1;
            } else {
                self.flags.color_enabled = 0;
            }

            if (layout.texture) |entry| {
                self.attributes.append(vk.VertexInputAttributeDescription2EXT{
                    .binding = 0,
                    .location = TEXTURE_ATTRIBUTE,
                    .offset = @intCast(entry.offset),
                    .format = get_format(entry.dimensions, entry.normalize, entry.backing_type),
                }) catch unreachable;

                self.flags.texture_enabled = 1;
            } else {
                self.flags.texture_enabled = 0;
            }
        }

        const vert_size = layout.size * vert_count;
        const idx_size = @sizeOf(u16) * ind_count;

        {
            // Create staging buffer
            var staging_buffer: vk.Buffer = undefined;
            var staging_buffer_memory: vk.DeviceMemory = undefined;
            Buffer.create(
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
            Buffer.create(
                vert_size,
                .{ .transfer_dst_bit = true, .vertex_buffer_bit = true },
                .{ .device_local_bit = true },
                &self.vert_buffer,
                &self.vert_memory,
            ) catch unreachable;

            Buffer.copy(staging_buffer, self.vert_buffer, vert_size) catch unreachable;
        }

        {
            // Create staging buffer
            var staging_buffer: vk.Buffer = undefined;
            var staging_buffer_memory: vk.DeviceMemory = undefined;
            Buffer.create(
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
            Buffer.create(
                idx_size,
                .{ .transfer_dst_bit = true, .index_buffer_bit = true },
                .{ .device_local_bit = true },
                &self.idx_buffer,
                &self.idx_memory,
            ) catch unreachable;

            Buffer.copy(staging_buffer, self.idx_buffer, idx_size) catch unreachable;
            self.idx_count = ind_count;
        }
    }

    pub fn draw(ctx: *anyopaque) void {
        const self = t.coerce_ptr(Mesh, ctx);

        const cmdbuf = Pipeline.current_cmd_buffer.?.*;
        const offsets = [_]vk.DeviceSize{0};

        Ctx.vkd.cmdSetVertexInputEXT(
            cmdbuf,
            @intCast(self.bindings.items.len),
            self.bindings.items.ptr,
            @intCast(self.attributes.items.len),
            self.attributes.items.ptr,
        );

        Ctx.vkd.cmdBindVertexBuffers(
            cmdbuf,
            0,
            1,
            @ptrCast(&self.vert_buffer),
            &offsets,
        );

        Ctx.vkd.cmdBindIndexBuffer(
            cmdbuf,
            self.idx_buffer,
            0,
            .uint16,
        );

        self.constants.flags = @as(*u32, @ptrCast(&self.flags)).*;
        Ctx.vkd.cmdPushConstants(
            cmdbuf,
            Pipeline.pipeline_layout,
            .{ .vertex_bit = true },
            0,
            @sizeOf(Pipeline.PushConstants),
            &self.constants,
        );

        Ctx.vkd.cmdDrawIndexed(
            cmdbuf,
            @intCast(self.idx_count),
            1,
            0,
            0,
            0,
        );
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

            self.bindings.clearAndFree();
            self.attributes.clearAndFree();
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
