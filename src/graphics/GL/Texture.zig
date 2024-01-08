const std = @import("std");
const glad = @import("glad");

const Allocator = @import("../../allocator.zig");
const t = @import("../../types.zig");

const stbi = @import("stbi");

pub const Texture = struct {
    id: u32 = 0,
    width: u16 = 0,
    height: u16 = 0,

    path_hash: u32 = 0,
    hash: u32 = 0,
    ref_count: u32 = 0,
};

pub const TextureManager = struct {
    list: std.ArrayList(Texture) = undefined,
    undefined_texture: Texture = undefined,
    bound: u32 = 1337,

    pub fn init(self: *TextureManager) !void {
        self.list = std.ArrayList(Texture).init(try Allocator.allocator());

        self.undefined_texture = Texture{
            .id = 0,
            .width = 8,
            .height = 8,
            .path_hash = 0,
            .hash = 0,
            .ref_count = 0,
        };

        glad.glGenTextures(1, &self.undefined_texture.id);
        glad.glBindTexture(glad.GL_TEXTURE_2D, self.undefined_texture.id);

        glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_WRAP_S, glad.GL_CLAMP_TO_EDGE);
        glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_WRAP_T, glad.GL_CLAMP_TO_EDGE);
        glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_MIN_FILTER, glad.GL_NEAREST);
        glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_MAG_FILTER, glad.GL_NEAREST);

        glad.glPixelStorei(glad.GL_UNPACK_ALIGNMENT, 1);

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

        glad.glTexImage2D(
            glad.GL_TEXTURE_2D,
            0,
            glad.GL_RGBA,
            @intCast(self.undefined_texture.width),
            @intCast(self.undefined_texture.height),
            0,
            glad.GL_RGBA,
            glad.GL_UNSIGNED_BYTE,
            &data,
        );

        glad.glGenerateMipmap(glad.GL_TEXTURE_2D);
        glad.glBindTexture(glad.GL_TEXTURE_2D, 0);
    }

    pub fn deinit(self: *TextureManager) void {
        for (self.list.items) |tex| {
            glad.glDeleteTextures(1, &tex.id);
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

        var buffer = try alloc.alloc(u8, try file.getEndPos());
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
        var data = stbi.stbi_load_from_memory(buffer.ptr, @intCast(len), &width, &height, &channels, stbi.STBI_rgb_alpha);
        defer stbi.stbi_image_free(data);

        if (data == null) {
            return error.TextureLoadError;
        }

        tex.width = @intCast(width);
        tex.height = @intCast(height);

        // Load the texture into OpenGL

        glad.glGenTextures(1, &tex.id);
        glad.glBindTexture(glad.GL_TEXTURE_2D, tex.id);

        glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_WRAP_S, glad.GL_CLAMP_TO_EDGE);
        glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_WRAP_T, glad.GL_CLAMP_TO_EDGE);
        glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_MIN_FILTER, glad.GL_NEAREST);
        glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_MAG_FILTER, glad.GL_NEAREST);

        glad.glPixelStorei(glad.GL_UNPACK_ALIGNMENT, 1);

        glad.glTexImage2D(
            glad.GL_TEXTURE_2D,
            0,
            glad.GL_RGBA,
            @intCast(width),
            @intCast(height),
            0,
            glad.GL_RGBA,
            glad.GL_UNSIGNED_BYTE,
            data,
        );

        glad.glGenerateMipmap(glad.GL_TEXTURE_2D);

        try self.list.append(tex);
        return tex;
    }

    pub fn bind(self: *TextureManager, texture: t.Texture) void {
        if (self.bound == texture.index) {
            return;
        }

        glad.glActiveTexture(glad.GL_TEXTURE0);
        glad.glBindTexture(glad.GL_TEXTURE_2D, texture.index);
        self.bound = texture.index;
    }

    pub fn delete(self: *TextureManager, texture: t.Texture) void {
        var remove_index: usize = 65535;
        for (self.list.items, 0..) |*tex, i| {
            _ = i;
            if (tex.id == texture.index) {
                tex.ref_count -= 1;
                if (tex.ref_count == 0) {
                    glad.glDeleteTextures(1, &tex.id);
                    tex.id = 0;
                }
            }
        }

        if (remove_index != 65535) {
            _ = self.list.swapRemove(remove_index);
        }
    }
};
