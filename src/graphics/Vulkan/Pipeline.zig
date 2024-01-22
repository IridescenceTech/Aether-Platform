const std = @import("std");
const t = @import("../../types.zig");
const vk = @import("vulkan");
const zwin = @import("zwin");
const Allocator = @import("../../allocator.zig");
const Ctx = @import("Context.zig");
const Swapchain = @import("Swapchain.zig").Swapchain;
const shaders = @import("shaders");
const Buffer = @import("Buffer.zig");
pub const PushConstants = struct {
    model: [16]f32 = [_]f32{
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    },
    flags: u32 = 0,
    texture: u32 = 0,
};

pub const UniformBufferObject = struct {
    proj: [16]f32 = [_]f32{
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    },
    view: [16]f32 = [_]f32{
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    },
};

pub var descriptor_set_layout: vk.DescriptorSetLayout = undefined;
pub var descriptor_pool: vk.DescriptorPool = undefined;
pub var descriptor_sets: [1]vk.DescriptorSet = undefined;
pub var uniform_buffer: vk.Buffer = undefined;
pub var uniform_buffer_memory: vk.DeviceMemory = undefined;
pub var uniform_mapped_memory: *UniformBufferObject = undefined;
pub var pipeline_layout: vk.PipelineLayout = undefined;
pub var render_pass: vk.RenderPass = undefined;
pub var pipeline: vk.Pipeline = undefined;
pub var framebuffers: []vk.Framebuffer = undefined;
pub var command_pool: vk.CommandPool = undefined;
pub var buffer: vk.Buffer = undefined;
pub var memory: vk.DeviceMemory = undefined;
pub var cmd_buffers: []vk.CommandBuffer = undefined;
pub var current_cmd_buffer: ?*vk.CommandBuffer = null;

pub fn init(swapchain: Swapchain) !void {
    try create_descriptor_set();

    const push_constants = [_]vk.PushConstantRange{
        .{
            .offset = 0,
            .size = @sizeOf(PushConstants),
            .stage_flags = .{ .vertex_bit = true },
        },
    };

    pipeline_layout = try Ctx.vkd.createPipelineLayout(Ctx.device, &.{
        .flags = .{},
        .set_layout_count = 1,
        .p_set_layouts = @ptrCast(&descriptor_set_layout),
        .push_constant_range_count = 1,
        .p_push_constant_ranges = &push_constants,
    }, null);

    render_pass = try create_render_pass(swapchain);

    try create_pipeline();

    framebuffers = try create_framebuffers(swapchain);

    command_pool = try Ctx.vkd.createCommandPool(Ctx.device, &.{
        .queue_family_index = Ctx.graphics_queue.family,
        .flags = .{ .reset_command_buffer_bit = true },
    }, null);

    cmd_buffers = try create_command_buffers();
}

pub fn deinit() void {
    destroy_command_buffers();
    Ctx.vkd.destroyCommandPool(Ctx.device, command_pool, null);

    destroy_framebuffers();

    Ctx.vkd.destroyPipeline(Ctx.device, pipeline, null);
    Ctx.vkd.destroyRenderPass(Ctx.device, render_pass, null);
    Ctx.vkd.destroyPipelineLayout(Ctx.device, pipeline_layout, null);
    Ctx.vkd.destroyDescriptorPool(Ctx.device, descriptor_pool, null);
    Ctx.vkd.destroyBuffer(Ctx.device, uniform_buffer, null);
    Ctx.vkd.freeMemory(Ctx.device, uniform_buffer_memory, null);
    Ctx.vkd.destroyDescriptorSetLayout(Ctx.device, descriptor_set_layout, null);
}

fn create_descriptor_set() !void {
    const bindings = [_]vk.DescriptorSetLayoutBinding{
        .{
            .binding = 0,
            .descriptor_type = .uniform_buffer,
            .descriptor_count = 1,
            .stage_flags = .{ .vertex_bit = true },
        },
        .{
            .binding = 1,
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = 128,
            .stage_flags = .{ .fragment_bit = true },
        },
    };

    const bindless_flags = [_]vk.DescriptorBindingFlags{
        .{},
        .{
            .partially_bound_bit = true,
            .variable_descriptor_count_bit = true,
            .update_after_bind_bit = true,
        },
    };

    const extended_info = vk.DescriptorSetLayoutBindingFlagsCreateInfo{
        .binding_count = bindings.len,
        .p_binding_flags = &bindless_flags,
    };

    descriptor_set_layout = try Ctx.vkd.createDescriptorSetLayout(Ctx.device, &.{
        .binding_count = bindings.len,
        .p_bindings = &bindings,
        .flags = .{ .update_after_bind_pool_bit = true },
        .p_next = &extended_info,
    }, null);

    try Buffer.create(
        @sizeOf(UniformBufferObject),
        .{ .uniform_buffer_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        &uniform_buffer,
        &uniform_buffer_memory,
    );
    const raw_ptr = try Ctx.vkd.mapMemory(Ctx.device, uniform_buffer_memory, 0, @sizeOf(UniformBufferObject), .{});
    uniform_mapped_memory = @ptrCast(@alignCast(raw_ptr));
    uniform_mapped_memory.* = UniformBufferObject{};

    const pool_sizes = [_]vk.DescriptorPoolSize{
        .{
            .descriptor_count = bindings[0].descriptor_count,
            .type = bindings[0].descriptor_type,
        },
        .{
            .descriptor_count = bindings[1].descriptor_count,
            .type = bindings[1].descriptor_type,
        },
    };

    descriptor_pool = try Ctx.vkd.createDescriptorPool(Ctx.device, &.{
        .pool_size_count = pool_sizes.len,
        .p_pool_sizes = &pool_sizes,
        .max_sets = 129,
        .flags = .{ .update_after_bind_bit = true },
    }, null);

    const max_binding = [_]u32{128};

    const count_info = vk.DescriptorSetVariableDescriptorCountAllocateInfo{
        .descriptor_set_count = 1,
        .p_descriptor_counts = &max_binding,
    };

    try Ctx.vkd.allocateDescriptorSets(Ctx.device, &.{
        .descriptor_pool = descriptor_pool,
        .descriptor_set_count = 1,
        .p_set_layouts = @as([*]vk.DescriptorSetLayout, @ptrCast(&descriptor_set_layout)),
        .p_next = &count_info,
    }, &descriptor_sets);

    const buffer_info = [_]vk.DescriptorBufferInfo{
        .{
            .buffer = uniform_buffer,
            .offset = 0,
            .range = @sizeOf(UniformBufferObject),
        },
    };

    @setRuntimeSafety(false);
    const write_sets = [_]vk.WriteDescriptorSet{
        .{
            .dst_set = descriptor_sets[0],
            .dst_binding = 0,
            .dst_array_element = 0,
            .descriptor_type = .uniform_buffer,
            .descriptor_count = 1,
            .p_buffer_info = &buffer_info,
            .p_image_info = undefined,
            .p_texel_buffer_view = undefined,
        },
    };

    Ctx.vkd.updateDescriptorSets(
        Ctx.device,
        1,
        &write_sets,
        0,
        null,
    );
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

fn create_command_buffers() ![]vk.CommandBuffer {
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
