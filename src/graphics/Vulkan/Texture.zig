const std = @import("std");

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

        // TODO: Load into Vulkan

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
