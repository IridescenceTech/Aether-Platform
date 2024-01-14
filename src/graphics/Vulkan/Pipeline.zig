const std = @import("std");
const t = @import("../../types.zig");
const vk = @import("vulkan");
const zwin = @import("zwin");
const Allocator = @import("../../allocator.zig");
const Ctx = @import("Context.zig");
const Swapchain = @import("Swapchain.zig").Swapchain;
const shaders = @import("shaders");

pub var pipeline_layout: vk.PipelineLayout = undefined;
pub var render_pass: vk.RenderPass = undefined;
pub var pipeline: vk.Pipeline = undefined;
pub var framebuffers: []vk.Framebuffer = undefined;
pub var command_pool: vk.CommandPool = undefined;
pub var buffer: vk.Buffer = undefined;
pub var memory: vk.DeviceMemory = undefined;
pub var cmd_buffers: []vk.CommandBuffer = undefined;
pub var current_cmd_buffer: ?*vk.CommandBuffer = null;

const Vertex = struct {
    const binding_description = vk.VertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(Vertex),
        .input_rate = .vertex,
    };

    const attribute_description = [_]vk.VertexInputAttributeDescription{
        .{
            .binding = 0,
            .location = 0,
            .format = .r32g32_sfloat,
            .offset = @offsetOf(Vertex, "pos"),
        },
        .{
            .binding = 0,
            .location = 1,
            .format = .r32g32b32_sfloat,
            .offset = @offsetOf(Vertex, "color"),
        },
    };

    pos: [2]f32,
    color: [3]f32,
};

pub fn init(width: u16, height: u16, swapchain: Swapchain) !void {
    //TODO: Setup Push Constants!
    pipeline_layout = try Ctx.vkd.createPipelineLayout(Ctx.device, &.{
        .flags = .{},
        .set_layout_count = 0,
        .p_set_layouts = undefined,
        .push_constant_range_count = 0,
        .p_push_constant_ranges = undefined,
    }, null);

    render_pass = try create_render_pass(swapchain);
    try create_pipeline();

    framebuffers = try create_framebuffers(swapchain);

    command_pool = try Ctx.vkd.createCommandPool(Ctx.device, &.{
        .queue_family_index = Ctx.graphics_queue.family,
        .flags = .{ .reset_command_buffer_bit = true },
    }, null);

    cmd_buffers = try create_command_buffers(width, height);
}

pub fn deinit() void {
    destroy_command_buffers();
    Ctx.vkd.destroyCommandPool(Ctx.device, command_pool, null);

    destroy_framebuffers();

    Ctx.vkd.destroyPipeline(Ctx.device, pipeline, null);
    Ctx.vkd.destroyRenderPass(Ctx.device, render_pass, null);
    Ctx.vkd.destroyPipelineLayout(Ctx.device, pipeline_layout, null);
}

fn create_render_pass(swapchain: Swapchain) !vk.RenderPass {
    const color_attachment = vk.AttachmentDescription{
        .format = swapchain.surface_format.format,
        .samples = .{ .@"1_bit" = true },
        .load_op = .clear,
        .store_op = .store,
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        .initial_layout = .undefined,
        .final_layout = .present_src_khr,
    };

    const color_attachment_ref = vk.AttachmentReference{
        .attachment = 0,
        .layout = .color_attachment_optimal,
    };

    const subpass = vk.SubpassDescription{ .pipeline_bind_point = .graphics, .color_attachment_count = 1, .p_color_attachments = @ptrCast(
        (&color_attachment_ref),
    ) };

    return try Ctx.vkd.createRenderPass(Ctx.device, &.{
        .attachment_count = 1,
        .p_attachments = @as([*]const vk.AttachmentDescription, @ptrCast(&color_attachment)),
        .subpass_count = 1,
        .p_subpasses = @as([*]const vk.SubpassDescription, @ptrCast(&subpass)),
    }, null);
}

fn create_pipeline() !void {
    const vert = try Ctx.vkd.createShaderModule(Ctx.device, &.{
        .code_size = shaders.vert.len,
        .p_code = @as([*]const u32, @ptrCast(&shaders.vert)),
    }, null);
    defer Ctx.vkd.destroyShaderModule(Ctx.device, vert, null);

    const frag = try Ctx.vkd.createShaderModule(Ctx.device, &.{
        .code_size = shaders.frag.len,
        .p_code = @as([*]const u32, @ptrCast(&shaders.frag)),
    }, null);
    defer Ctx.vkd.destroyShaderModule(Ctx.device, frag, null);

    const pssci = [_]vk.PipelineShaderStageCreateInfo{
        .{
            .stage = .{ .vertex_bit = true },
            .module = vert,
            .p_name = "main",
        },
        .{
            .stage = .{ .fragment_bit = true },
            .module = frag,
            .p_name = "main",
        },
    };

    const pvisci = vk.PipelineVertexInputStateCreateInfo{
        .vertex_binding_description_count = 1,
        .p_vertex_binding_descriptions = @ptrCast(&Vertex.binding_description),
        .vertex_attribute_description_count = Vertex.attribute_description.len,
        .p_vertex_attribute_descriptions = &Vertex.attribute_description,
    };
    _ = pvisci; // autofix

    const piasci = vk.PipelineInputAssemblyStateCreateInfo{
        .topology = .triangle_list,
        .primitive_restart_enable = vk.FALSE,
    };

    // Set in createCommandBuffers
    const pvsci = vk.PipelineViewportStateCreateInfo{
        .viewport_count = 1,
        .p_viewports = undefined,
        .scissor_count = 1,
        .p_scissors = undefined,
    };

    const prsci = vk.PipelineRasterizationStateCreateInfo{
        .depth_clamp_enable = vk.FALSE,
        .rasterizer_discard_enable = vk.FALSE,
        .polygon_mode = .fill,
        .cull_mode = .{ .back_bit = true },
        .front_face = .clockwise,
        .depth_bias_enable = vk.FALSE,
        .depth_bias_constant_factor = 0,
        .depth_bias_clamp = 0,
        .depth_bias_slope_factor = 0,
        .line_width = 1,
    };

    const pmsci = vk.PipelineMultisampleStateCreateInfo{
        .rasterization_samples = .{ .@"1_bit" = true },
        .sample_shading_enable = vk.FALSE,
        .min_sample_shading = 1,
        .alpha_to_coverage_enable = vk.FALSE,
        .alpha_to_one_enable = vk.FALSE,
    };

    const pcbas = vk.PipelineColorBlendAttachmentState{
        .blend_enable = vk.FALSE,
        .src_color_blend_factor = .one,
        .dst_color_blend_factor = .zero,
        .color_blend_op = .add,
        .src_alpha_blend_factor = .one,
        .dst_alpha_blend_factor = .zero,
        .alpha_blend_op = .add,
        .color_write_mask = .{
            .r_bit = true,
            .g_bit = true,
            .b_bit = true,
            .a_bit = true,
        },
    };

    const pcbsci = vk.PipelineColorBlendStateCreateInfo{
        .logic_op_enable = vk.FALSE,
        .logic_op = .copy,
        .attachment_count = 1,
        .p_attachments = @ptrCast(&pcbas),
        .blend_constants = [_]f32{ 0, 0, 0, 0 },
    };

    const dynstate = [_]vk.DynamicState{ .viewport, .scissor, .vertex_input_ext };
    const pdsci = vk.PipelineDynamicStateCreateInfo{
        .flags = .{},
        .dynamic_state_count = dynstate.len,
        .p_dynamic_states = &dynstate,
    };

    const gpci = vk.GraphicsPipelineCreateInfo{
        .flags = .{},
        .stage_count = 2,
        .p_stages = &pssci,
        .p_vertex_input_state = null,
        .p_input_assembly_state = &piasci,
        .p_tessellation_state = null,
        .p_viewport_state = &pvsci,
        .p_rasterization_state = &prsci,
        .p_multisample_state = &pmsci,
        .p_depth_stencil_state = null,
        .p_color_blend_state = &pcbsci,
        .p_dynamic_state = &pdsci,
        .layout = pipeline_layout,
        .render_pass = render_pass,
        .subpass = 0,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    };

    _ = try Ctx.vkd.createGraphicsPipelines(
        Ctx.device,
        .null_handle,
        1,
        @ptrCast(&gpci),
        null,
        @ptrCast(&pipeline),
    );
}

fn create_framebuffers(swapchain: Swapchain) ![]vk.Framebuffer {
    const alloc = try Allocator.allocator();
    const fbs = try alloc.alloc(vk.Framebuffer, swapchain.swap_images.len);
    errdefer alloc.free(fbs);

    var i: usize = 0;
    errdefer for (fbs[0..i]) |fb| Ctx.vkd.destroyFramebuffer(Ctx.device, fb, null);

    for (fbs) |*fb| {
        fb.* = try Ctx.vkd.createFramebuffer(Ctx.device, &.{
            .render_pass = render_pass,
            .attachment_count = 1,
            .p_attachments = @as([*]const vk.ImageView, @ptrCast(&swapchain.swap_images[i].view)),
            .width = swapchain.extent.width,
            .height = swapchain.extent.height,
            .layers = 1,
        }, null);

        i += 1;
    }

    return fbs;
}

fn destroy_framebuffers() void {
    for (framebuffers) |fb| Ctx.vkd.destroyFramebuffer(Ctx.device, fb, null);

    const alloc = Allocator.allocator() catch unreachable;
    alloc.free(framebuffers);
}

const clear = [_]vk.ClearValue{
    .{ .color = .{ .float_32 = .{ 0, 0, 0, 1 } } },
};

var extent = vk.Extent2D{
    .width = 0,
    .height = 0,
};

var viewport = vk.Viewport{
    .x = 0,
    .y = 0,
    .width = 0.0,
    .height = 0.0,
    .min_depth = 0,
    .max_depth = 1,
};

var scissor = vk.Rect2D{
    .offset = .{ .x = 0, .y = 0 },
    .extent = .{ .width = 0, .height = 0 },
};

fn create_command_buffers(width: u16, height: u16) ![]vk.CommandBuffer {
    extent.width = width;
    extent.height = height;

    viewport.width = @floatFromInt(extent.width);
    viewport.height = @floatFromInt(extent.height);

    scissor.extent = extent;

    const allocator = try Allocator.allocator();

    const cmdbufs = try allocator.alloc(vk.CommandBuffer, framebuffers.len);
    errdefer allocator.free(cmdbufs);

    try Ctx.vkd.allocateCommandBuffers(Ctx.device, &.{
        .command_pool = command_pool,
        .level = .primary,
        .command_buffer_count = @as(u32, @truncate(cmdbufs.len)),
    }, cmdbufs.ptr);

    return cmdbufs;
}

fn destroy_command_buffers() void {
    Ctx.vkd.freeCommandBuffers(Ctx.device, command_pool, @truncate(cmd_buffers.len), cmd_buffers.ptr);

    const alloc = Allocator.allocator() catch unreachable;
    alloc.free(cmd_buffers);
}
