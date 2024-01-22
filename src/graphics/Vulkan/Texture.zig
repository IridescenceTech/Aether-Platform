const std = @import("std");
const vk = @import("vulkan");

const Ctx = @import("Context.zig");
const Image = @import("Image.zig");
const Allocator = @import("../../allocator.zig");
const Pipeline = @import("Pipeline.zig");
const t = @import("../../types.zig");

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
    bound: u32 = 1337,

    pub fn init(self: *TextureManager) !void {
        self.list = std.ArrayList(Texture).init(try Allocator.allocator());

        // TODO: Create undefined texture
    }

    pub fn deinit(self: *TextureManager) void {
        for (self.list.items) |tex| {
            _ = tex; // autofix
            // TODO: delete
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

        const descriptor = [_]vk.WriteDescriptorSet{
            .{
                .descriptor_count = 1,
                .dst_set = Pipeline.descriptor_sets[0],
                .dst_binding = 1,
                .descriptor_type = .combined_image_sampler,
                .dst_array_element = 0, // TODO
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

        try self.list.append(tex);
        return tex;
    }

    pub fn bind(self: *TextureManager, texture: t.Texture) void {
        _ = self; // autofix
        _ = texture; // autofix
        //TODO: Bind
    }

    pub fn delete(self: *TextureManager, texture: t.Texture) void {
        var remove_index: usize = 65535;
        for (self.list.items, 0..) |*tex, i| {
            if (tex.id == texture.index) {
                tex.ref_count -= 1;
                if (tex.ref_count == 0) {
                    //TODO: Delete
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
