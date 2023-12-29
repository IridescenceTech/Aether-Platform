const std = @import("std");
var initialized: bool = false;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;
var allocator_inst: std.mem.Allocator = undefined;

/// Initialize a global allocator
pub fn init() void {
    initialized = true;
    gpa = std.heap.GeneralPurposeAllocator(.{}){};
    allocator_inst = gpa.allocator();
}

/// Deinitialize the global allocator
pub fn deinit() void {
    initialized = false;
    _ = gpa.deinit();
    gpa = undefined;
    allocator_inst = undefined;
}

/// Gets the global allocator
pub fn allocator() !std.mem.Allocator {
    if (!initialized) {
        return error.UtilNotInitialized;
    }

    return allocator_inst;
}
