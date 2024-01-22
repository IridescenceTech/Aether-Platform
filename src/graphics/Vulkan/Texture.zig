const std = @import("std");
const vk = @import("vulkan");

const Ctx = @import("Context.zig");
const Image = @import("Image.zig");
const Allocator = @import("../../allocator.zig");
const Pipeline = @import("Pipeline.zig");
const t = @import("../../types.zig");
const Mesh = @import("Mesh.zig");

const stbi = @import("stbi");

pub const Texture = struct {
    id: u32 = 0,
    width: u16 = 0,
    height: u16 = 0,

    path_hash: u32 = 0,
    hash: u32 = 0,
    ref_count: u32 = 0,

    image: vk.Image,
    view: vk.ImageView,
    memory: vk.DeviceMemory,
    sampler: vk.Sampler,
};

pub const TextureManager = struct {
    list: std.ArrayList(Texture) = undefined,
    undefined_texture: Texture = undefined,
    latest_id: u8 = 0,
    ids: [128]bool = undefined,
    bound: u32 = 1337,

    pub fn init(self: *TextureManager) !void {
        self.list = std.ArrayList(Texture).init(try Allocator.allocator());

        for (&self.ids) |*v| {
            v.* = false;
        }

        self.latest_id = 0;

        const PURPLE = 0xFFFF00FF;
        const BLACK = 0xFF000000;

        const data: [8 * 8]u32 = [_]u32{
            PURPLE, PURPLE, PURPLE, PURPLE, BLACK,  BLACK,  BLACK,  BLACK,
            PURPLE, PURPLE, PURPLE, PURPLE, BLACK,  BLACK,  BLACK,  BLACK,
            PURPLE, PURPLE, PURPLE, PURPLE, BLACK,  BLACK,  BLACK,  BLACK,
            PURPLE, PURPLE, PURPLE, PURPLE, BLACK,  BLACK,  BLACK,  BLACK,
            BLACK,  BLACK,  BLACK,  BLACK,  PURPLE, PURPLE, PURPLE, PURPLE,
            BLACK,  BLACK,  BLACK,  BLACK,  PURPLE, PURPLE, PURPLE, PURPLE,
            BLACK,  BLACK,  BLACK,  BLACK,  PURPLE, PURPLE, PURPLE, PURPLE,
            BLACK,  BLACK,  BLACK,  BLACK,  PURPLE, PURPLE, PURPLE, PURPLE,
        };

        self.undefined_texture.id = 0;
        self.undefined_texture.width = 8;
        self.undefined_texture.height = 8;
        try Image.create_tex_image(8, 8, std.mem.asBytes(&data), &self.undefined_texture.image, &self.undefined_texture.memory, .r8g8b8a8_srgb);
        self.undefined_texture.view = try Image.create_image_view(self.undefined_texture.image, .r8g8b8a8_srgb);
        self.undefined_texture.sampler = try Image.create_texture_sampler(.nearest, .nearest);

        const image_info = [_]vk.DescriptorImageInfo{
            .{
                .image_layout = .shader_read_only_optimal,
                .image_view = self.undefined_texture.view,
                .sampler = self.undefined_texture.sampler,
            },
        };

        var available_slot: u8 = self.latest_id;
        var iters: u8 = 0;
        while (self.ids[available_slot] and iters < 128) : (iters += 1) {
            if (available_slot == 127) {
                available_slot = 0;
            }
            available_slot += 1;
        }

        if (iters == 128) {
            return error.TextureLoadError;
        }

        const descriptor = [_]vk.WriteDescriptorSet{
            .{
                .descriptor_count = 1,
                .dst_set = Pipeline.descriptor_sets[0],
                .dst_binding = 1,
                .descriptor_type = .combined_image_sampler,
                .dst_array_element = available_slot,
                .p_image_info = &image_info,
                .p_buffer_info = undefined,
                .p_texel_buffer_view = undefined,
            },
        };

        Ctx.vkd.updateDescriptorSets(
            Ctx.device,
            descriptor.len,
            &descriptor,
            0,
            null,
        );

        self.ids[available_slot] = true;
        self.latest_id = available_slot;

        std.log.debug("Added undefined texture to slot {}", .{available_slot});
        self.undefined_texture.id = available_slot;
    }

    pub fn deinit(self: *TextureManager) void {
        Ctx.vkd.destroySampler(Ctx.device, self.undefined_texture.sampler, null);
        Ctx.vkd.destroyImageView(Ctx.device, self.undefined_texture.view, null);
        Ctx.vkd.destroyImage(Ctx.device, self.undefined_texture.image, null);
        Ctx.vkd.freeMemory(Ctx.device, self.undefined_texture.memory, null);

        for (self.list.items) |tex| {
            Ctx.vkd.destroySampler(Ctx.device, tex.sampler, null);
            Ctx.vkd.destroyImageView(Ctx.device, tex.view, null);
            Ctx.vkd.destroyImage(Ctx.device, tex.image, null);
            Ctx.vkd.freeMemory(Ctx.device, tex.memory, null);
        }

        self.list.clearAndFree();
        self.list.deinit();
    }

    fn hash_bytes(path: []const u8) u32 {
        var hash: u32 = 5381;
        for (path) |c| {
            @setRuntimeSafety(false);
            hash = ((hash << 5) + hash) + c;
        }

        return hash;
    }

    pub fn load_texture(self: *TextureManager, path: []const u8) !Texture {
        // Check if the texture is already loaded
        for (self.list.items) |*tex| {
            if (tex.path_hash == 0) {
                continue;
            }

            if (tex.path_hash == hash_bytes(path)) {
                tex.ref_count += 1;
                return tex.*;
            }
        }

        // Otherwise load the file into a buffer.
        const alloc = try Allocator.allocator();

        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const buffer = try alloc.alloc(u8, try file.getEndPos());
        defer alloc.free(buffer);

        _ = try file.read(buffer);

        // Load the texture via the buffer method
        return self.load_texture_from_buffer(buffer, hash_bytes(path));
    }

    pub fn load_texture_from_buffer(self: *TextureManager, buffer: []const u8, phash: ?u32) !Texture {
        var tex: Texture = undefined;
        if (phash) |hash| {
            tex.path_hash = hash;
        }
        tex.hash = hash_bytes(buffer);

        for (self.list.items) |*t_other| {
            if (t_other.hash == tex.hash) {
                t_other.ref_count += 1;
                return t_other.*;
            }
        }

        tex.ref_count = 1;

        var width: i32 = 0;
        var height: i32 = 0;
        var channels: i32 = 0;
        const len = buffer.len;
        const data = stbi.stbi_load_from_memory(buffer.ptr, @intCast(len), &width, &height, &channels, stbi.STBI_rgb_alpha);
        defer stbi.stbi_image_free(data);

        if (data == null) {
            return error.TextureLoadError;
        }

        tex.width = @intCast(width);
        tex.height = @intCast(height);

        var buf: []const u8 = undefined;
        buf.ptr = @ptrCast(data.?);
        buf.len = @intCast(width * height * 4);

        std.log.info("Creating Buffer {}", .{buf.len});

        try Image.create_tex_image(tex.width, tex.height, buf, &tex.image, &tex.memory, .r8g8b8a8_srgb);
        tex.view = try Image.create_image_view(tex.image, .r8g8b8a8_srgb);
        tex.sampler = try Image.create_texture_sampler(.linear, .nearest);

        const image_info = [_]vk.DescriptorImageInfo{
            .{
                .image_layout = .shader_read_only_optimal,
                .image_view = tex.view,
                .sampler = tex.sampler,
            },
        };

        var available_slot: u8 = self.latest_id;
        var iters: u8 = 0;
        while (self.ids[available_slot] and iters < 128) : (iters += 1) {
            if (available_slot == 127) {
                available_slot = 0;
            }
            available_slot += 1;
        }

        if (iters == 128) {
            return error.TextureLoadError;
        }

        const descriptor = [_]vk.WriteDescriptorSet{
            .{
                .descriptor_count = 1,
                .dst_set = Pipeline.descriptor_sets[0],
                .dst_binding = 1,
                .descriptor_type = .combined_image_sampler,
                .dst_array_element = available_slot,
                .p_image_info = &image_info,
                .p_buffer_info = undefined,
                .p_texel_buffer_view = undefined,
            },
        };
        std.log.debug("Added texture to slot {}", .{available_slot});

        Ctx.vkd.updateDescriptorSets(
            Ctx.device,
            descriptor.len,
            &descriptor,
            0,
            null,
        );

        self.ids[available_slot] = true;
        self.latest_id = available_slot;
        tex.id = available_slot;
        try self.list.append(tex);
        return tex;
    }

    pub fn bind(self: *TextureManager, texture: t.Texture) void {
        _ = self; // autofix
        std.log.debug("Binding texture {}", .{texture.index});
        Mesh.ActiveMeshContext.texture = texture.index;
    }

    pub fn delete(self: *TextureManager, texture: t.Texture) void {
        var remove_index: usize = 65535;
        for (self.list.items, 0..) |*tex, i| {
            if (tex.id == texture.index) {
                tex.ref_count -= 1;
                if (tex.ref_count == 0) {
                    Ctx.vkd.destroySampler(Ctx.device, tex.sampler, null);
                    Ctx.vkd.destroyImageView(Ctx.device, tex.view, null);
                    Ctx.vkd.destroyImage(Ctx.device, tex.image, null);
                    Ctx.vkd.freeMemory(Ctx.device, tex.memory, null);

                    tex.id = 0;
                    remove_index = i;
                }
            }
        }

        if (remove_index != 65535) {
            _ = self.list.swapRemove(remove_index);
        }
    }
};
