const std = @import("std");
const glad = @import("glad");

const Allocator = @import("../../allocator.zig");
const t = @import("../../types.zig");

pub const Mesh = struct {
    vao: u32 = 0,
    vbo: u32 = 0,
    ebo: u32 = 0,
    index_count: usize = 0,
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
            glad.glEnableVertexAttribArray(0);

            const dims = entry.dimensions;
            const size = layout.size;
            const offset = entry.offset;
            glad.glVertexAttribPointer(
                0,
                @intCast(dims),
                get_gltype(entry.backing_type),
                glad.GL_FALSE,
                @intCast(size),
                @ptrFromInt(offset),
            );
        }

        if (layout.color) |entry| {
            glad.glEnableVertexAttribArray(1);

            const dims = entry.dimensions;
            const size = layout.size;
            const offset = entry.offset;
            glad.glVertexAttribPointer(
                1,
                @intCast(dims),
                get_gltype(entry.backing_type),
                glad.GL_TRUE,
                @intCast(size),
                @ptrFromInt(offset),
            );
        }

        if (layout.texture) |entry| {
            glad.glEnableVertexAttribArray(2);

            const dims = entry.dimensions;
            const size = layout.size;
            const offset = entry.offset;
            glad.glVertexAttribPointer(
                2,
                @intCast(dims),
                get_gltype(entry.backing_type),
                glad.GL_FALSE,
                @intCast(size),
                @ptrFromInt(offset),
            );
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
