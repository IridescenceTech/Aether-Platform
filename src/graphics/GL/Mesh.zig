const std = @import("std");
const glad = @import("glad");

const Allocator = @import("../../allocator.zig");
const Shader = @import("Shader.zig");
const t = @import("../../types.zig");

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

    vao: u32 = 0,
    vbo: u32 = 0,
    ebo: u32 = 0,
    index_count: usize = 0,
    flags: Flags = undefined,
    dead: bool = false,

    fn get_gltype(kind: t.VertexLayout.Type) u32 {
        return switch (kind) {
            .Float => glad.GL_FLOAT,
            .UByte => glad.GL_UNSIGNED_BYTE,
            .UShort => glad.GL_UNSIGNED_SHORT,
        };
    }

    pub fn update(ctx: *anyopaque, vertices: *anyopaque, vert_count: usize, indices: *anyopaque, ind_count: usize, layout: *const t.VertexLayout) void {
        var self = t.coerce_ptr(Mesh, ctx);

        if (self.vao == 0) {
            glad.glGenVertexArrays(1, &self.vao);
        }

        if (self.vbo == 0) {
            glad.glGenBuffers(1, &self.vbo);
        }

        if (self.ebo == 0) {
            glad.glGenBuffers(1, &self.ebo);
        }

        glad.glBindVertexArray(self.vao);

        glad.glBindBuffer(glad.GL_ARRAY_BUFFER, self.vbo);
        const vert_size = vert_count * layout.size;
        glad.glBufferData(glad.GL_ARRAY_BUFFER, @intCast(vert_size), vertices, glad.GL_STATIC_DRAW);

        if (layout.vertex) |entry| {
            glad.glEnableVertexAttribArray(POSITION_ATTRIBUTE);

            const dims = entry.dimensions;
            const size = layout.size;
            const offset = entry.offset;
            const normalize = if (entry.normalize) glad.GL_TRUE else glad.GL_FALSE;
            glad.glVertexAttribPointer(
                0,
                @intCast(dims),
                get_gltype(entry.backing_type),
                @intCast(normalize),
                @intCast(size),
                @ptrFromInt(offset),
            );

            if (entry.backing_type == t.VertexLayout.Type.UShort) {
                self.flags.fixed_point5 = 1;
            }
        } else {
            self.flags.fixed_point5 = 0;
        }

        if (layout.color) |entry| {
            glad.glEnableVertexAttribArray(COLOR_ATTRIBUTE);

            const dims = entry.dimensions;
            const size = layout.size;
            const offset = entry.offset;
            const normalize = if (entry.normalize) glad.GL_TRUE else glad.GL_FALSE;
            glad.glVertexAttribPointer(
                1,
                @intCast(dims),
                get_gltype(entry.backing_type),
                @intCast(normalize),
                @intCast(size),
                @ptrFromInt(offset),
            );

            self.flags.color_enabled = 1;
        } else {
            self.flags.color_enabled = 0;
        }

        if (layout.texture) |entry| {
            glad.glEnableVertexAttribArray(TEXTURE_ATTRIBUTE);

            const dims = entry.dimensions;
            const size = layout.size;
            const offset = entry.offset;
            const normalize = if (entry.normalize) glad.GL_TRUE else glad.GL_FALSE;
            glad.glVertexAttribPointer(
                2,
                @intCast(dims),
                get_gltype(entry.backing_type),
                @intCast(normalize),
                @intCast(size),
                @ptrFromInt(offset),
            );

            self.flags.texture_enabled = 1;
        } else {
            self.flags.texture_enabled = 0;
        }

        glad.glBindBuffer(glad.GL_ELEMENT_ARRAY_BUFFER, self.ebo);

        const ind_size = ind_count * @sizeOf(u16);
        self.index_count = ind_count;
        glad.glBufferData(glad.GL_ELEMENT_ARRAY_BUFFER, @intCast(ind_size), indices, glad.GL_STATIC_DRAW);

        glad.glBindVertexArray(0);
    }

    pub fn draw(ctx: *anyopaque) void {
        const self = t.coerce_ptr(Mesh, ctx);
        glad.glBindVertexArray(self.vao);

        Shader.set_flags(@ptrCast(&self.flags));

        const count = self.index_count;
        glad.glDrawElements(glad.GL_TRIANGLES, @intCast(count), glad.GL_UNSIGNED_SHORT, null);
    }

    pub fn deinit(ctx: *anyopaque) void {
        var self = t.coerce_ptr(Mesh, ctx);
        self.dead = true;
    }

    pub fn gc(self: *Mesh) void {
        if (self.dead) {
            glad.glDeleteVertexArrays(1, &self.vao);
            glad.glDeleteBuffers(1, &self.vbo);
            glad.glDeleteBuffers(1, &self.ebo);
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
        for (self.list.items) |mesh| {
            glad.glDeleteVertexArrays(1, &mesh.vao);
            glad.glDeleteBuffers(1, &mesh.vbo);
            glad.glDeleteBuffers(1, &mesh.ebo);

            const alloc = Allocator.allocator() catch unreachable;
            alloc.destroy(mesh);
        }

        self.list.clearAndFree();
        self.list.deinit();
    }
};
