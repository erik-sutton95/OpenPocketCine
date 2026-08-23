#include <android/hardware_buffer.h>
#include <android/hardware_buffer_jni.h>
#include <android/log.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <jni.h>
#include <vulkan/vulkan.h>
#include <vulkan/vulkan_android.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include "fullscreen_vert_spv.h"
#include "feed_frag_spv.h"
#include "blit_frag_spv.h"
#include "kawase_frag_spv.h"
#include "glass_vert_spv.h"
#include "glass_frag_spv.h"
#include "scope_vert_spv.h"
#include "scope_frag_spv.h"
#include "vector_vert_spv.h"
#include "vector_frag_spv.h"
#include "histo_comp_spv.h"
#include "histo_remap_comp_spv.h"
#include "histo_plot_frag_spv.h"

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "OpcVulkan", __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "OpcVulkan", __VA_ARGS__)

namespace {

// Native Pocket HEVC is 1280×720. Scopes tap that grid (encoded codes).
// The picture samples YCbCr at the feed well (one linear chroma upsample,
// same as iOS VT at view size), LUTs there, then 1:1 blits into the slot.
constexpr uint32_t kSourceW = 1280;
constexpr uint32_t kSourceH = 720;
constexpr uint32_t kVectorN = 128;
constexpr uint32_t kMaxPlates = 24;
constexpr uint32_t kSlotCount = 4;
// Match LiveDesign.scopePlate / GpuLiveLayout.PANEL_FILL_* — DJI black 72%.
constexpr float kScopePlateR = 20.f / 255.f;
constexpr float kScopePlateG = 20.f / 255.f;
constexpr float kScopePlateB = 20.f / 255.f;
constexpr float kScopePlateA = 0.72f;
// PocketScopeSampler.tapSize(1280, 720)
constexpr uint32_t kTapW = 213;
constexpr uint32_t kTapH = 120;
constexpr uint32_t kHistoInts = 1024;
constexpr int kStride = 2;

#ifndef VK_QUEUE_FAMILY_FOREIGN_EXT
#define VK_QUEUE_FAMILY_FOREIGN_EXT 0xFFFFFFFE
#endif

struct Slot {
    int visible = 0;
    float x = 0, y = 0, w = 0, h = 0;
    int mode = 0;
    float intensity = 1;
    float gain = 1;
};

struct Plate {
    float x = 0, y = 0, w = 0, h = 0, radius = 16;
    float r = 0, g = 0, b = 0, a = 0.52f;
};

struct ImageMem {
    VkImage image = VK_NULL_HANDLE;
    VkDeviceMemory memory = VK_NULL_HANDLE;
    VkImageView view = VK_NULL_HANDLE;
    uint32_t width = 0;
    uint32_t height = 0;
};

struct ImportedAhb {
    AHardwareBuffer* hb = nullptr;
    VkImage image = VK_NULL_HANDLE;
    VkDeviceMemory memory = VK_NULL_HANDLE;
    VkImageView view = VK_NULL_HANDLE;
    VkSampler sampler = VK_NULL_HANDLE;
    VkSamplerYcbcrConversion conversion = VK_NULL_HANDLE;
    VkDescriptorSet set = VK_NULL_HANDLE;
    uint32_t width = 0;
    uint32_t height = 0;
};

constexpr int kAhbCache = 8;

struct AhbSlot {
    AHardwareBuffer* hb = nullptr;
    VkImage image = VK_NULL_HANDLE;
    VkDeviceMemory memory = VK_NULL_HANDLE;
    VkImageView view = VK_NULL_HANDLE;
    uint32_t width = 0;
    uint32_t height = 0;
};

struct BufferMem {
    VkBuffer buffer = VK_NULL_HANDLE;
    VkDeviceMemory memory = VK_NULL_HANDLE;
    void* mapped = nullptr;
    VkDeviceSize size = 0;
};

uint32_t findMemory(VkPhysicalDevice gpu, uint32_t bits, VkMemoryPropertyFlags want) {
    VkPhysicalDeviceMemoryProperties props{};
    vkGetPhysicalDeviceMemoryProperties(gpu, &props);
    for (uint32_t i = 0; i < props.memoryTypeCount; ++i) {
        if ((bits & (1u << i)) && (props.memoryTypes[i].propertyFlags & want) == want) {
            return i;
        }
    }
    return 0;
}

VkShaderModule makeShader(VkDevice device, const uint32_t* words, uint32_t count) {
    VkShaderModuleCreateInfo ci{VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO};
    ci.codeSize = count * 4u;
    ci.pCode = words;
    VkShaderModule m = VK_NULL_HANDLE;
    vkCreateShaderModule(device, &ci, nullptr, &m);
    return m;
}

}  // namespace

struct OpcVk {
    std::mutex lock;
    VkInstance instance = VK_NULL_HANDLE;
    VkPhysicalDevice gpu = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    VkQueue queue = VK_NULL_HANDLE;
    uint32_t queueFamily = 0;
    VkCommandPool cmdPool = VK_NULL_HANDLE;
    VkCommandBuffer cmd = VK_NULL_HANDLE;
    VkFence fence = VK_NULL_HANDLE;
    VkDescriptorPool descPool = VK_NULL_HANDLE;
    VkPipelineCache cache = VK_NULL_HANDLE;

    ANativeWindow* window = nullptr;
    VkSurfaceKHR surface = VK_NULL_HANDLE;
    VkSwapchainKHR swapchain = VK_NULL_HANDLE;
    VkFormat swapFormat = VK_FORMAT_B8G8R8A8_UNORM;
    VkExtent2D swapExtent{1, 1};
    std::vector<VkImage> swapImages;
    std::vector<VkImageView> swapViews;
    std::vector<VkFramebuffer> swapFbs;
    VkRenderPass swapPass = VK_NULL_HANDLE;
    VkRenderPass offscreenPass = VK_NULL_HANDLE;
    VkRenderPass loadPass = VK_NULL_HANDLE;

    ImageMem source{};
    ImageMem tap{};
    ImageMem well{};
    ImageMem graded{};
    ImageMem vectorTarget{};
    ImageMem kawase[3]{};
    VkFramebuffer sourceFb = VK_NULL_HANDLE;
    VkFramebuffer wellFb = VK_NULL_HANDLE;
    VkFramebuffer gradedFb = VK_NULL_HANDLE;
    VkFramebuffer vectorFb = VK_NULL_HANDLE;
    VkFramebuffer kawaseFb[3]{};

    struct CubeUpload {
        std::vector<uint8_t> rgba;
        uint32_t w = 8;
        uint32_t h = 8;
        float cubeSize = 0;
        bool dirty = false;
        bool shaderReady = false;
    } cube[3];

    BufferMem histo{};
    BufferMem display{};
    BufferMem ire{};
    BufferMem staging{};

    VkSampler linearSampler = VK_NULL_HANDLE;
    ImageMem lut{};
    ImageMem limitsPaint{};
    ImageMem limitsWeight{};

    VkDescriptorSetLayout blitSetLayout = VK_NULL_HANDLE;
    VkDescriptorSetLayout feedSetLayout = VK_NULL_HANDLE;
    VkDescriptorSetLayout scopeSetLayout = VK_NULL_HANDLE;
    VkDescriptorSetLayout histoSetLayout = VK_NULL_HANDLE;
    VkDescriptorSetLayout remapSetLayout = VK_NULL_HANDLE;
    VkDescriptorSetLayout histoPlotSetLayout = VK_NULL_HANDLE;
    VkDescriptorSetLayout glassSetLayout = VK_NULL_HANDLE;
    VkDescriptorSetLayout copySetLayout = VK_NULL_HANDLE;

    VkPipelineLayout blitLayout = VK_NULL_HANDLE;
    VkPipelineLayout feedLayout = VK_NULL_HANDLE;
    VkPipelineLayout scopeLayout = VK_NULL_HANDLE;
    VkPipelineLayout histoLayout = VK_NULL_HANDLE;
    VkPipelineLayout remapLayout = VK_NULL_HANDLE;
    VkPipelineLayout histoPlotLayout = VK_NULL_HANDLE;
    VkPipelineLayout glassLayout = VK_NULL_HANDLE;
    VkPipelineLayout copyLayout = VK_NULL_HANDLE;
    VkPipelineLayout vectorLayout = VK_NULL_HANDLE;

    VkPipeline blitPipe = VK_NULL_HANDLE;
    VkPipeline blitAlphaPipe = VK_NULL_HANDLE;
    VkPipeline feedPipe = VK_NULL_HANDLE;
    VkPipeline scopePipe = VK_NULL_HANDLE;
    VkPipeline histoPipe = VK_NULL_HANDLE;
    VkPipeline remapPipe = VK_NULL_HANDLE;
    VkPipeline histoPlotPipe = VK_NULL_HANDLE;
    VkPipeline glassPipe = VK_NULL_HANDLE;
    VkPipeline copyPipe = VK_NULL_HANDLE;
    VkPipeline kawasePipe = VK_NULL_HANDLE;
    VkPipeline vectorPipe = VK_NULL_HANDLE;
    VkPipeline decayPipe = VK_NULL_HANDLE;

    VkDescriptorSet blitSets[8]{};
    VkDescriptorSet feedSet = VK_NULL_HANDLE;
    VkDescriptorSet scopeSet = VK_NULL_HANDLE;
    VkDescriptorSet histoSet = VK_NULL_HANDLE;
    VkDescriptorSet remapSet = VK_NULL_HANDLE;
    VkDescriptorSet histoPlotSet = VK_NULL_HANDLE;
    VkDescriptorSet glassSet = VK_NULL_HANDLE;
    VkDescriptorSet copySet = VK_NULL_HANDLE;
    VkDescriptorSet vectorSet = VK_NULL_HANDLE;

    ImportedAhb imported{};
    AhbSlot ahbCache[kAhbCache]{};
    VkDescriptorPool copyPool = VK_NULL_HANDLE;
    VkFormat ycbcrVkFormat = VK_FORMAT_MAX_ENUM;
    uint64_t ycbcrExternal = 0;
    float copyUvMode = 0;
    VkSurfaceTransformFlagBitsKHR preTransform = VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR;
    uint32_t windowW = 1;
    uint32_t windowH = 1;
    bool gpuBusy = false;

    Slot slots[kSlotCount]{};
    int stackOrder[4] = {0, 1, 3, 0};
    int stackCount = 3;
    int needTap = 0;
    Plate plates[kMaxPlates]{};
    uint32_t plateCount = 0;
    float uiScale = 1.f;
    float feedRect[4]{0, 0, 1, 1};
    float lutSize = 0;
    float limitsPaintSize = 0;
    float limitsWeightSize = 0;
    float limitsOn = 0;
    float splitOn = 0;
    float splitVertical = 1;
    float zebraHiOn = 0, zebraHi = 1, zebraMidOn = 0, zebraMid = 0.5f, zebraMidHalf = 0.02f;
    float feedUpscale = 0, mirror = 0;
    float zebraHiColor[3]{1, 1, 1};
    float zebraMidColor[3]{1, 0.72f, 0.2f};
    float lumaW[3]{0.2126f, 0.7152f, 0.0722f};
    int stride = kStride;
    bool ready = false;
};

static VkResult makeBuffer(OpcVk* r, VkDeviceSize size, VkBufferUsageFlags usage,
                           VkMemoryPropertyFlags props, BufferMem* out) {
    VkBufferCreateInfo bi{VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
    bi.size = size;
    bi.usage = usage;
    VkResult err = vkCreateBuffer(r->device, &bi, nullptr, &out->buffer);
    if (err) return err;
    VkMemoryRequirements req{};
    vkGetBufferMemoryRequirements(r->device, out->buffer, &req);
    VkMemoryAllocateInfo ai{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    ai.allocationSize = req.size;
    ai.memoryTypeIndex = findMemory(r->gpu, req.memoryTypeBits, props);
    err = vkAllocateMemory(r->device, &ai, nullptr, &out->memory);
    if (err) return err;
    vkBindBufferMemory(r->device, out->buffer, out->memory, 0);
    out->size = size;
    if (props & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) {
        vkMapMemory(r->device, out->memory, 0, size, 0, &out->mapped);
    }
    return VK_SUCCESS;
}

static VkResult makeImage(OpcVk* r, uint32_t w, uint32_t h, VkFormat format,
                          VkImageUsageFlags usage, ImageMem* out) {
    out->width = w;
    out->height = h;
    VkImageCreateInfo ii{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    ii.imageType = VK_IMAGE_TYPE_2D;
    ii.format = format;
    ii.extent = {w, h, 1};
    ii.mipLevels = 1;
    ii.arrayLayers = 1;
    ii.samples = VK_SAMPLE_COUNT_1_BIT;
    ii.tiling = VK_IMAGE_TILING_OPTIMAL;
    ii.usage = usage;
    ii.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    VkResult err = vkCreateImage(r->device, &ii, nullptr, &out->image);
    if (err) return err;
    VkMemoryRequirements req{};
    vkGetImageMemoryRequirements(r->device, out->image, &req);
    VkMemoryAllocateInfo ai{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    ai.allocationSize = req.size;
    ai.memoryTypeIndex =
        findMemory(r->gpu, req.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    err = vkAllocateMemory(r->device, &ai, nullptr, &out->memory);
    if (err) return err;
    vkBindImageMemory(r->device, out->image, out->memory, 0);
    VkImageViewCreateInfo vi{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
    vi.image = out->image;
    vi.viewType = VK_IMAGE_VIEW_TYPE_2D;
    vi.format = format;
    vi.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    return vkCreateImageView(r->device, &vi, nullptr, &out->view);
}

static void destroyImage(VkDevice d, ImageMem* im) {
    if (im->view) vkDestroyImageView(d, im->view, nullptr);
    if (im->image) vkDestroyImage(d, im->image, nullptr);
    if (im->memory) vkFreeMemory(d, im->memory, nullptr);
    *im = {};
}

static void destroyBuffer(VkDevice d, BufferMem* b) {
    if (b->mapped && b->memory) vkUnmapMemory(d, b->memory);
    if (b->buffer) vkDestroyBuffer(d, b->buffer, nullptr);
    if (b->memory) vkFreeMemory(d, b->memory, nullptr);
    *b = {};
}

static VkPipeline makeGfx(OpcVk* r, VkPipelineLayout layout, VkRenderPass pass,
                          VkShaderModule vs, VkShaderModule fs, bool points, bool additive,
                          uint32_t pcSize, bool srcAlpha = false) {
    VkPipelineShaderStageCreateInfo stages[2]{};
    stages[0].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[0].stage = VK_SHADER_STAGE_VERTEX_BIT;
    stages[0].module = vs;
    stages[0].pName = "main";
    stages[1].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[1].stage = VK_SHADER_STAGE_FRAGMENT_BIT;
    stages[1].module = fs;
    stages[1].pName = "main";
    VkPipelineVertexInputStateCreateInfo vi{VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
    VkPipelineInputAssemblyStateCreateInfo ia{VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO};
    ia.topology = points ? VK_PRIMITIVE_TOPOLOGY_POINT_LIST : VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP;
    VkPipelineViewportStateCreateInfo vp{VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO};
    vp.viewportCount = 1;
    vp.scissorCount = 1;
    VkPipelineRasterizationStateCreateInfo rs{VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO};
    rs.polygonMode = VK_POLYGON_MODE_FILL;
    rs.cullMode = VK_CULL_MODE_NONE;
    rs.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE;
    rs.lineWidth = 1.f;
    VkPipelineMultisampleStateCreateInfo ms{VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO};
    ms.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;
    VkPipelineColorBlendAttachmentState att{};
    att.colorWriteMask = 0xF;
    if (additive) {
        att.blendEnable = VK_TRUE;
        att.srcColorBlendFactor = VK_BLEND_FACTOR_ONE;
        att.dstColorBlendFactor = VK_BLEND_FACTOR_ONE;
        att.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE;
        att.dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE;
    } else if (points || srcAlpha) {
        att.blendEnable = VK_TRUE;
        att.srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA;
        att.dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
        att.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE;
        att.dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    }
    VkPipelineColorBlendStateCreateInfo cb{VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO};
    cb.attachmentCount = 1;
    cb.pAttachments = &att;
    VkDynamicState dyns[] = {VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR};
    VkPipelineDynamicStateCreateInfo dyn{VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO};
    dyn.dynamicStateCount = 2;
    dyn.pDynamicStates = dyns;
    VkGraphicsPipelineCreateInfo gi{VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO};
    gi.stageCount = 2;
    gi.pStages = stages;
    gi.pVertexInputState = &vi;
    gi.pInputAssemblyState = &ia;
    gi.pViewportState = &vp;
    gi.pRasterizationState = &rs;
    gi.pMultisampleState = &ms;
    gi.pColorBlendState = &cb;
    gi.pDynamicState = &dyn;
    gi.layout = layout;
    gi.renderPass = pass;
    VkPipeline p = VK_NULL_HANDLE;
    vkCreateGraphicsPipelines(r->device, r->cache, 1, &gi, nullptr, &p);
    (void)pcSize;
    return p;
}

static VkDescriptorSetLayout makeSetLayout(VkDevice d, const std::vector<VkDescriptorSetLayoutBinding>& b) {
    VkDescriptorSetLayoutCreateInfo ci{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
    ci.bindingCount = (uint32_t)b.size();
    ci.pBindings = b.data();
    VkDescriptorSetLayout l = VK_NULL_HANDLE;
    vkCreateDescriptorSetLayout(d, &ci, nullptr, &l);
    return l;
}

static VkPipelineLayout makeLayout(VkDevice d, VkDescriptorSetLayout set, VkShaderStageFlags stages,
                                   uint32_t pcSize) {
    VkPushConstantRange pc{};
    pc.stageFlags = stages;
    pc.size = pcSize;
    VkPipelineLayoutCreateInfo ci{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
    ci.setLayoutCount = 1;
    ci.pSetLayouts = &set;
    if (pcSize) {
        ci.pushConstantRangeCount = 1;
        ci.pPushConstantRanges = &pc;
    }
    VkPipelineLayout l = VK_NULL_HANDLE;
    vkCreatePipelineLayout(d, &ci, nullptr, &l);
    return l;
}

static VkRenderPass makePass(VkDevice d, VkFormat format, VkImageLayout finalLayout, bool load) {
    VkAttachmentDescription att{};
    att.format = format;
    att.samples = VK_SAMPLE_COUNT_1_BIT;
    att.loadOp = load ? VK_ATTACHMENT_LOAD_OP_LOAD : VK_ATTACHMENT_LOAD_OP_CLEAR;
    att.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    att.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    att.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    att.initialLayout = load ? VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL : VK_IMAGE_LAYOUT_UNDEFINED;
    att.finalLayout = finalLayout;
    VkAttachmentReference ref{0, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL};
    VkSubpassDescription sub{};
    sub.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
    sub.colorAttachmentCount = 1;
    sub.pColorAttachments = &ref;
    VkSubpassDependency dep{};
    dep.srcSubpass = VK_SUBPASS_EXTERNAL;
    dep.dstSubpass = 0;
    dep.srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dep.dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dep.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
    VkRenderPassCreateInfo ci{VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO};
    ci.attachmentCount = 1;
    ci.pAttachments = &att;
    ci.subpassCount = 1;
    ci.pSubpasses = &sub;
    ci.dependencyCount = 1;
    ci.pDependencies = &dep;
    VkRenderPass p = VK_NULL_HANDLE;
    vkCreateRenderPass(d, &ci, nullptr, &p);
    return p;
}

static VkFramebuffer makeFb(VkDevice d, VkRenderPass pass, VkImageView view, uint32_t w, uint32_t h) {
    VkFramebufferCreateInfo ci{VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO};
    ci.renderPass = pass;
    ci.attachmentCount = 1;
    ci.pAttachments = &view;
    ci.width = w;
    ci.height = h;
    ci.layers = 1;
    VkFramebuffer fb = VK_NULL_HANDLE;
    vkCreateFramebuffer(d, &ci, nullptr, &fb);
    return fb;
}

static void writeCombined(VkDevice d, VkDescriptorSet set, uint32_t binding, VkImageView view,
                          VkSampler sampler) {
    VkDescriptorImageInfo ii{};
    ii.sampler = sampler;
    ii.imageView = view;
    ii.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    VkWriteDescriptorSet w{VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET};
    w.dstSet = set;
    w.dstBinding = binding;
    w.descriptorCount = 1;
    w.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    w.pImageInfo = &ii;
    vkUpdateDescriptorSets(d, 1, &w, 0, nullptr);
}

static bool rebuildCopyLayout(OpcVk* r, VkSampler immutable) {
    vkDeviceWaitIdle(r->device);
    if (r->copyPipe) {
        vkDestroyPipeline(r->device, r->copyPipe, nullptr);
        r->copyPipe = VK_NULL_HANDLE;
    }
    if (r->copyLayout) {
        vkDestroyPipelineLayout(r->device, r->copyLayout, nullptr);
        r->copyLayout = VK_NULL_HANDLE;
    }
    if (r->copySetLayout) {
        vkDestroyDescriptorSetLayout(r->device, r->copySetLayout, nullptr);
        r->copySetLayout = VK_NULL_HANDLE;
    }
    if (r->copyPool) {
        vkDestroyDescriptorPool(r->device, r->copyPool, nullptr);
        r->copyPool = VK_NULL_HANDLE;
        r->copySet = VK_NULL_HANDLE;
    }
    VkDescriptorSetLayoutBinding b{};
    b.binding = 0;
    b.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    b.descriptorCount = 1;
    b.stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT;
    b.pImmutableSamplers = immutable ? &immutable : nullptr;
    r->copySetLayout = makeSetLayout(r->device, {b});
    r->copyLayout = makeLayout(r->device, r->copySetLayout, VK_SHADER_STAGE_FRAGMENT_BIT, 16);
    auto vs = makeShader(r->device, fullscreen_vert_spv, fullscreen_vert_spv_count);
    auto fs = makeShader(r->device, blit_frag_spv, blit_frag_spv_count);
    r->copyPipe = makeGfx(r, r->copyLayout, r->offscreenPass, vs, fs, false, false, 16);
    vkDestroyShaderModule(r->device, vs, nullptr);
    vkDestroyShaderModule(r->device, fs, nullptr);
    VkDescriptorPoolSize sz{VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 4};
    VkDescriptorPoolCreateInfo dpi{VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO};
    dpi.maxSets = 4;
    dpi.poolSizeCount = 1;
    dpi.pPoolSizes = &sz;
    if (vkCreateDescriptorPool(r->device, &dpi, nullptr, &r->copyPool)) return false;
    VkDescriptorSetAllocateInfo ai{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
    ai.descriptorPool = r->copyPool;
    ai.descriptorSetCount = 1;
    ai.pSetLayouts = &r->copySetLayout;
    return vkAllocateDescriptorSets(r->device, &ai, &r->copySet) == VK_SUCCESS && r->copyPipe;
}

static void destroyFb(VkDevice d, VkFramebuffer* fb) {
    if (fb && *fb) {
        vkDestroyFramebuffer(d, *fb, nullptr);
        *fb = VK_NULL_HANDLE;
    }
}

static void destroyWellChain(OpcVk* r) {
    destroyFb(r->device, &r->wellFb);
    destroyFb(r->device, &r->gradedFb);
    for (auto& fb : r->kawaseFb) destroyFb(r->device, &fb);
    destroyImage(r->device, &r->well);
    destroyImage(r->device, &r->graded);
    for (auto& k : r->kawase) destroyImage(r->device, &k);
}

static void bindWellChain(OpcVk* r) {
    if (r->feedSet && r->well.view) {
        writeCombined(r->device, r->feedSet, 0, r->well.view, r->linearSampler);
    }
    if (r->glassSet && r->kawase[2].view && r->graded.view) {
        writeCombined(r->device, r->glassSet, 0, r->kawase[2].view, r->linearSampler);
        writeCombined(r->device, r->glassSet, 1, r->graded.view, r->linearSampler);
    }
    if (r->blitSets[0] && r->graded.view && r->kawase[0].view) {
        writeCombined(r->device, r->blitSets[0], 0, r->graded.view, r->linearSampler);
        writeCombined(r->device, r->blitSets[1], 0, r->kawase[0].view, r->linearSampler);
        writeCombined(r->device, r->blitSets[2], 0, r->kawase[1].view, r->linearSampler);
        writeCombined(r->device, r->blitSets[3], 0, r->kawase[2].view, r->linearSampler);
    }
}

static bool allocWellChain(OpcVk* r, uint32_t w, uint32_t h) {
    w = std::max(1u, w);
    h = std::max(1u, h);
    destroyWellChain(r);
    auto usage =
        VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    if (makeImage(r, w, h, VK_FORMAT_R8G8B8A8_UNORM, usage, &r->well)) return false;
    if (makeImage(r, w, h, VK_FORMAT_R8G8B8A8_UNORM, usage, &r->graded)) return false;
    uint32_t bw = std::max(1u, w / 2), bh = std::max(1u, h / 2);
    for (int i = 0; i < 3; ++i) {
        if (makeImage(r, bw, bh, VK_FORMAT_R8G8B8A8_UNORM, usage, &r->kawase[i])) return false;
        bw = std::max(1u, bw / 2);
        bh = std::max(1u, bh / 2);
    }
    r->wellFb = makeFb(r->device, r->offscreenPass, r->well.view, w, h);
    r->gradedFb = makeFb(r->device, r->offscreenPass, r->graded.view, w, h);
    for (int i = 0; i < 3; ++i) {
        r->kawaseFb[i] =
            makeFb(r->device, r->offscreenPass, r->kawase[i].view, r->kawase[i].width, r->kawase[i].height);
    }
    bindWellChain(r);
    LOGI("well yuv %ux%u (scopes stay %ux%u)", w, h, kSourceW, kSourceH);
    return r->wellFb && r->gradedFb;
}

static bool ensureWell(OpcVk* r) {
    uint32_t w = (uint32_t)std::lround(std::max(r->feedRect[2], 1.f));
    uint32_t h = (uint32_t)std::lround(std::max(r->feedRect[3], 1.f));
    if (w < 64 || h < 64) {
        w = kSourceW;
        h = kSourceH;
    }
    if (r->windowW > 0) w = std::min(w, r->windowW);
    if (r->windowH > 0) h = std::min(h, r->windowH);
    if (r->well.width == w && r->well.height == h && r->wellFb) return true;
    vkDeviceWaitIdle(r->device);
    return allocWellChain(r, w, h);
}

static bool ensureCubeImages(OpcVk* r) {
    ImageMem* imgs[3] = {&r->lut, &r->limitsPaint, &r->limitsWeight};
    bool rebound = false;
    for (int i = 0; i < 3; ++i) {
        if (!r->cube[i].dirty) continue;
        uint32_t w = std::max(1u, r->cube[i].w);
        uint32_t h = std::max(1u, r->cube[i].h);
        if (imgs[i]->width == w && imgs[i]->height == h && imgs[i]->image) continue;
        vkDeviceWaitIdle(r->device);
        destroyImage(r->device, imgs[i]);
        if (makeImage(r, w, h, VK_FORMAT_R8G8B8A8_UNORM,
                      VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT, imgs[i])) {
            return false;
        }
        r->cube[i].shaderReady = false;
        rebound = true;
    }
    if (rebound && r->feedSet) {
        writeCombined(r->device, r->feedSet, 1, r->lut.view, r->linearSampler);
        writeCombined(r->device, r->feedSet, 2, r->limitsPaint.view, r->linearSampler);
        writeCombined(r->device, r->feedSet, 3, r->limitsWeight.view, r->linearSampler);
    }
    return true;
}

static void imageBarrier(VkCommandBuffer cmd, VkImage img, VkImageLayout oldL, VkImageLayout newL,
                         VkAccessFlags srcA, VkAccessFlags dstA, VkPipelineStageFlags srcS,
                         VkPipelineStageFlags dstS) {
    VkImageMemoryBarrier b{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};
    b.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    b.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    b.oldLayout = oldL;
    b.newLayout = newL;
    b.srcAccessMask = srcA;
    b.dstAccessMask = dstA;
    b.image = img;
    b.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    vkCmdPipelineBarrier(cmd, srcS, dstS, 0, 0, nullptr, 0, nullptr, 1, &b);
}

static void recordCubeUploads(OpcVk* r) {
    if (!r->staging.mapped || !r->staging.buffer) return;
    ImageMem* imgs[3] = {&r->lut, &r->limitsPaint, &r->limitsWeight};
    struct Item {
        int i;
        VkDeviceSize off;
        uint32_t w, h;
    };
    Item items[3];
    int n = 0;
    VkDeviceSize stagingOff = 0;
    for (int i = 0; i < 3; ++i) {
        if (!r->cube[i].dirty) continue;
        if (r->cube[i].rgba.empty()) {
            r->cube[i].dirty = false;
            continue;
        }
        VkDeviceSize bytes = r->cube[i].rgba.size();
        if (stagingOff + bytes > r->staging.size) break;
        memcpy(static_cast<uint8_t*>(r->staging.mapped) + stagingOff, r->cube[i].rgba.data(), (size_t)bytes);
        items[n++] = {i, stagingOff, r->cube[i].w, r->cube[i].h};
        stagingOff += bytes;
        r->cube[i].dirty = false;
    }
    for (int k = 0; k < n; ++k) {
        auto& it = items[k];
        ImageMem* im = imgs[it.i];
        VkImageLayout old = r->cube[it.i].shaderReady ? VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
                                                     : VK_IMAGE_LAYOUT_UNDEFINED;
        imageBarrier(r->cmd, im->image, old, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 0,
                     VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
                     VK_PIPELINE_STAGE_TRANSFER_BIT);
        VkBufferImageCopy c{};
        c.bufferOffset = it.off;
        c.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
        c.imageExtent = {it.w, it.h, 1};
        vkCmdCopyBufferToImage(r->cmd, r->staging.buffer, im->image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &c);
        imageBarrier(r->cmd, im->image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                     VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, VK_ACCESS_TRANSFER_WRITE_BIT,
                     VK_ACCESS_SHADER_READ_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
                     VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT | VK_PIPELINE_STAGE_VERTEX_SHADER_BIT);
        r->cube[it.i].shaderReady = true;
    }
}

static void writeBuffer(VkDevice d, VkDescriptorSet set, uint32_t binding, VkBuffer buffer,
                        VkDeviceSize size, VkDescriptorType type) {
    VkDescriptorBufferInfo bi{};
    bi.buffer = buffer;
    bi.range = size;
    VkWriteDescriptorSet w{VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET};
    w.dstSet = set;
    w.dstBinding = binding;
    w.descriptorCount = 1;
    w.descriptorType = type;
    w.pBufferInfo = &bi;
    vkUpdateDescriptorSets(d, 1, &w, 0, nullptr);
}

static bool createDevice(OpcVk* r) {
    const char* instExt[] = {
        VK_KHR_SURFACE_EXTENSION_NAME,
        VK_KHR_ANDROID_SURFACE_EXTENSION_NAME,
    };
    VkApplicationInfo app{VK_STRUCTURE_TYPE_APPLICATION_INFO};
    app.pApplicationName = "OpenPocketCine";
    app.apiVersion = VK_API_VERSION_1_1;
    VkInstanceCreateInfo ici{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    ici.pApplicationInfo = &app;
    ici.enabledExtensionCount = 2;
    ici.ppEnabledExtensionNames = instExt;
    if (vkCreateInstance(&ici, nullptr, &r->instance)) return false;

    uint32_t count = 0;
    vkEnumeratePhysicalDevices(r->instance, &count, nullptr);
    if (!count) return false;
    std::vector<VkPhysicalDevice> gpus(count);
    vkEnumeratePhysicalDevices(r->instance, &count, gpus.data());
    r->gpu = gpus[0];

    uint32_t qCount = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(r->gpu, &qCount, nullptr);
    std::vector<VkQueueFamilyProperties> qs(qCount);
    vkGetPhysicalDeviceQueueFamilyProperties(r->gpu, &qCount, qs.data());
    r->queueFamily = 0;
    for (uint32_t i = 0; i < qCount; ++i) {
        if (qs[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) {
            r->queueFamily = i;
            break;
        }
    }
    float prio = 1.f;
    VkDeviceQueueCreateInfo qci{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
    qci.queueFamilyIndex = r->queueFamily;
    qci.queueCount = 1;
    qci.pQueuePriorities = &prio;
    const char* devExt[] = {
        VK_KHR_SWAPCHAIN_EXTENSION_NAME,
        VK_ANDROID_EXTERNAL_MEMORY_ANDROID_HARDWARE_BUFFER_EXTENSION_NAME,
        VK_EXT_QUEUE_FAMILY_FOREIGN_EXTENSION_NAME,
    };
    VkPhysicalDeviceSamplerYcbcrConversionFeatures ycbcrFeat{
        VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SAMPLER_YCBCR_CONVERSION_FEATURES};
    ycbcrFeat.samplerYcbcrConversion = VK_TRUE;
    VkPhysicalDeviceFeatures2 feats2{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2};
    feats2.pNext = &ycbcrFeat;
    feats2.features.largePoints = VK_TRUE;
    VkDeviceCreateInfo dci{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
    dci.pNext = &feats2;
    dci.queueCreateInfoCount = 1;
    dci.pQueueCreateInfos = &qci;
    dci.enabledExtensionCount = 3;
    dci.ppEnabledExtensionNames = devExt;
    if (vkCreateDevice(r->gpu, &dci, nullptr, &r->device)) return false;
    vkGetDeviceQueue(r->device, r->queueFamily, 0, &r->queue);

    VkCommandPoolCreateInfo pci{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
    pci.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    pci.queueFamilyIndex = r->queueFamily;
    vkCreateCommandPool(r->device, &pci, nullptr, &r->cmdPool);
    VkCommandBufferAllocateInfo cai{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
    cai.commandPool = r->cmdPool;
    cai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cai.commandBufferCount = 1;
    vkAllocateCommandBuffers(r->device, &cai, &r->cmd);
    VkFenceCreateInfo fi{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
    fi.flags = VK_FENCE_CREATE_SIGNALED_BIT;
    vkCreateFence(r->device, &fi, nullptr, &r->fence);
    VkPipelineCacheCreateInfo cacheCi{VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO};
    vkCreatePipelineCache(r->device, &cacheCi, nullptr, &r->cache);
    return true;
}

static bool createResources(OpcVk* r) {
    auto usage =
        VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    if (makeImage(r, kSourceW, kSourceH, VK_FORMAT_R8G8B8A8_UNORM, usage, &r->source)) return false;
    if (makeImage(r, kTapW, kTapH, VK_FORMAT_R8G8B8A8_UNORM,
                  VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT, &r->tap))
        return false;
    if (makeImage(r, kVectorN, kVectorN, VK_FORMAT_R8G8B8A8_UNORM,
                  VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_SAMPLED_BIT, &r->vectorTarget))
        return false;
    if (makeImage(r, 8, 8, VK_FORMAT_R8G8B8A8_UNORM,
                  VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT, &r->lut))
        return false;
    if (makeImage(r, 8, 8, VK_FORMAT_R8G8B8A8_UNORM,
                  VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT, &r->limitsPaint))
        return false;
    if (makeImage(r, 8, 8, VK_FORMAT_R8G8B8A8_UNORM,
                  VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT, &r->limitsWeight))
        return false;

    makeBuffer(r, kHistoInts * 4, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
               VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, &r->histo);
    makeBuffer(r, kHistoInts * 4, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
               VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, &r->display);
    makeBuffer(r, 256 * 4, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
               VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, &r->ire);
    makeBuffer(r, 512 * 512 * 4, VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
               VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, &r->staging);

    VkSamplerCreateInfo si{VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO};
    si.magFilter = VK_FILTER_LINEAR;
    si.minFilter = VK_FILTER_LINEAR;
    si.addressModeU = si.addressModeV = si.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    vkCreateSampler(r->device, &si, nullptr, &r->linearSampler);

    r->offscreenPass = makePass(r->device, VK_FORMAT_R8G8B8A8_UNORM, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, false);
    r->loadPass = makePass(r->device, VK_FORMAT_R8G8B8A8_UNORM, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, true);
    if (!allocWellChain(r, kSourceW, kSourceH)) return false;
    r->sourceFb = makeFb(r->device, r->offscreenPass, r->source.view, kSourceW, kSourceH);
    r->vectorFb = makeFb(r->device, r->offscreenPass, r->vectorTarget.view, kVectorN, kVectorN);

    auto samp = [&](uint32_t b) {
        return VkDescriptorSetLayoutBinding{b, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1,
                                            VK_SHADER_STAGE_FRAGMENT_BIT | VK_SHADER_STAGE_VERTEX_BIT |
                                                VK_SHADER_STAGE_COMPUTE_BIT,
                                            nullptr};
    };
    auto buf = [&](uint32_t b, VkDescriptorType t, VkShaderStageFlags s) {
        return VkDescriptorSetLayoutBinding{b, t, 1, s, nullptr};
    };

    r->copySetLayout = makeSetLayout(r->device, {samp(0)});
    r->blitSetLayout = makeSetLayout(r->device, {samp(0)});
    r->feedSetLayout = makeSetLayout(r->device, {samp(0), samp(1), samp(2), samp(3)});
    r->scopeSetLayout = makeSetLayout(
        r->device, {samp(0), buf(1, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                                 VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_COMPUTE_BIT)});
    r->histoSetLayout = makeSetLayout(
        r->device, {samp(0), buf(1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_COMPUTE_BIT)});
    r->remapSetLayout = makeSetLayout(
        r->device, {buf(0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_COMPUTE_BIT),
                    buf(1, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_COMPUTE_BIT),
                    buf(2, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, VK_SHADER_STAGE_COMPUTE_BIT)});
    r->histoPlotSetLayout = makeSetLayout(
        r->device, {buf(0, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_FRAGMENT_BIT)});
    r->glassSetLayout = makeSetLayout(r->device, {samp(0), samp(1)});

    r->copyLayout = makeLayout(r->device, r->copySetLayout, VK_SHADER_STAGE_FRAGMENT_BIT, 16);
    r->blitLayout = makeLayout(r->device, r->blitSetLayout, VK_SHADER_STAGE_FRAGMENT_BIT, 16);
    r->feedLayout = makeLayout(r->device, r->feedSetLayout,
                               VK_SHADER_STAGE_FRAGMENT_BIT, 128);
    r->scopeLayout = makeLayout(r->device, r->scopeSetLayout,
                                VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, 128);
    r->vectorLayout = makeLayout(r->device, r->feedSetLayout,
                                 VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, 64);
    r->histoLayout = makeLayout(r->device, r->histoSetLayout, VK_SHADER_STAGE_COMPUTE_BIT, 32);
    r->remapLayout = makeLayout(r->device, r->remapSetLayout, VK_SHADER_STAGE_COMPUTE_BIT, 0);
    r->histoPlotLayout = makeLayout(r->device, r->histoPlotSetLayout, VK_SHADER_STAGE_FRAGMENT_BIT, 80);
    r->glassLayout = makeLayout(r->device, r->glassSetLayout,
                                VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, 80);

    auto vs = makeShader(r->device, fullscreen_vert_spv, fullscreen_vert_spv_count);
    auto fsBlit = makeShader(r->device, blit_frag_spv, blit_frag_spv_count);
    auto fsFeed = makeShader(r->device, feed_frag_spv, feed_frag_spv_count);
    auto fsKawase = makeShader(r->device, kawase_frag_spv, kawase_frag_spv_count);
    auto vsGlass = makeShader(r->device, glass_vert_spv, glass_vert_spv_count);
    auto fsGlass = makeShader(r->device, glass_frag_spv, glass_frag_spv_count);
    auto vsScope = makeShader(r->device, scope_vert_spv, scope_vert_spv_count);
    auto fsScope = makeShader(r->device, scope_frag_spv, scope_frag_spv_count);
    auto vsVec = makeShader(r->device, vector_vert_spv, vector_vert_spv_count);
    auto fsVec = makeShader(r->device, vector_frag_spv, vector_frag_spv_count);
    auto fsHisto = makeShader(r->device, histo_plot_frag_spv, histo_plot_frag_spv_count);
    auto csHisto = makeShader(r->device, histo_comp_spv, histo_comp_spv_count);
    auto csRemap = makeShader(r->device, histo_remap_comp_spv, histo_remap_comp_spv_count);

    r->copyPipe = makeGfx(r, r->copyLayout, r->offscreenPass, vs, fsBlit, false, false, 16);
    r->feedPipe = makeGfx(r, r->feedLayout, r->offscreenPass, vs, fsFeed, false, false, 128);
    r->kawasePipe = makeGfx(r, r->blitLayout, r->offscreenPass, vs, fsKawase, false, false, 16);
    r->blitPipe = makeGfx(r, r->blitLayout, r->swapPass ? r->swapPass : r->offscreenPass, vs, fsBlit, false, false, 16);
    r->blitAlphaPipe = makeGfx(r, r->blitLayout, r->swapPass ? r->swapPass : r->offscreenPass, vs, fsBlit, false, false, 16, true);
    r->glassPipe = makeGfx(r, r->glassLayout, r->swapPass ? r->swapPass : r->offscreenPass, vsGlass, fsGlass, false, false, 80, true);
    r->scopePipe = makeGfx(r, r->scopeLayout, r->swapPass ? r->swapPass : r->offscreenPass, vsScope, fsScope, true, true, 128);
    r->vectorPipe = makeGfx(r, r->vectorLayout, r->offscreenPass, vsVec, fsVec, true, true, 64);
    r->histoPlotPipe = makeGfx(r, r->histoPlotLayout, r->swapPass ? r->swapPass : r->offscreenPass, vs, fsHisto, false, true, 80);

    VkComputePipelineCreateInfo cci{VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO};
    cci.stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    cci.stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
    cci.stage.pName = "main";
    cci.stage.module = csHisto;
    cci.layout = r->histoLayout;
    vkCreateComputePipelines(r->device, r->cache, 1, &cci, nullptr, &r->histoPipe);
    cci.stage.module = csRemap;
    cci.layout = r->remapLayout;
    vkCreateComputePipelines(r->device, r->cache, 1, &cci, nullptr, &r->remapPipe);

    vkDestroyShaderModule(r->device, vs, nullptr);
    vkDestroyShaderModule(r->device, fsBlit, nullptr);
    vkDestroyShaderModule(r->device, fsFeed, nullptr);
    vkDestroyShaderModule(r->device, fsKawase, nullptr);
    vkDestroyShaderModule(r->device, vsGlass, nullptr);
    vkDestroyShaderModule(r->device, fsGlass, nullptr);
    vkDestroyShaderModule(r->device, vsScope, nullptr);
    vkDestroyShaderModule(r->device, fsScope, nullptr);
    vkDestroyShaderModule(r->device, vsVec, nullptr);
    vkDestroyShaderModule(r->device, fsVec, nullptr);
    vkDestroyShaderModule(r->device, fsHisto, nullptr);
    vkDestroyShaderModule(r->device, csHisto, nullptr);
    vkDestroyShaderModule(r->device, csRemap, nullptr);

    VkDescriptorPoolSize sizes[] = {
        {VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 64},
        {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 16},
        {VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 8},
    };
    VkDescriptorPoolCreateInfo dpi{VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO};
    dpi.maxSets = 32;
    dpi.poolSizeCount = 3;
    dpi.pPoolSizes = sizes;
    vkCreateDescriptorPool(r->device, &dpi, nullptr, &r->descPool);

    auto alloc = [&](VkDescriptorSetLayout layout, VkDescriptorSet* set) {
        VkDescriptorSetAllocateInfo ai{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
        ai.descriptorPool = r->descPool;
        ai.descriptorSetCount = 1;
        ai.pSetLayouts = &layout;
        vkAllocateDescriptorSets(r->device, &ai, set);
    };
    alloc(r->copySetLayout, &r->copySet);
    alloc(r->feedSetLayout, &r->feedSet);
    alloc(r->scopeSetLayout, &r->scopeSet);
    alloc(r->histoSetLayout, &r->histoSet);
    alloc(r->remapSetLayout, &r->remapSet);
    alloc(r->histoPlotSetLayout, &r->histoPlotSet);
    alloc(r->glassSetLayout, &r->glassSet);
    alloc(r->scopeSetLayout, &r->vectorSet);
    for (auto& set : r->blitSets) alloc(r->blitSetLayout, &set);

    bindWellChain(r);
    writeCombined(r->device, r->feedSet, 1, r->lut.view, r->linearSampler);
    writeCombined(r->device, r->feedSet, 2, r->limitsPaint.view, r->linearSampler);
    writeCombined(r->device, r->feedSet, 3, r->limitsWeight.view, r->linearSampler);
    writeCombined(r->device, r->scopeSet, 0, r->source.view, r->linearSampler);
    writeBuffer(r->device, r->scopeSet, 1, r->ire.buffer, r->ire.size, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
    writeCombined(r->device, r->vectorSet, 0, r->source.view, r->linearSampler);
    writeBuffer(r->device, r->vectorSet, 1, r->ire.buffer, r->ire.size, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
    writeCombined(r->device, r->histoSet, 0, r->source.view, r->linearSampler);
    writeBuffer(r->device, r->histoSet, 1, r->histo.buffer, r->histo.size, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER);
    writeBuffer(r->device, r->remapSet, 0, r->histo.buffer, r->histo.size, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER);
    writeBuffer(r->device, r->remapSet, 1, r->display.buffer, r->display.size, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER);
    writeBuffer(r->device, r->remapSet, 2, r->ire.buffer, r->ire.size, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
    writeBuffer(r->device, r->histoPlotSet, 0, r->display.buffer, r->display.size, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER);
    writeCombined(r->device, r->glassSet, 0, r->kawase[2].view, r->linearSampler);
    writeCombined(r->device, r->glassSet, 1, r->graded.view, r->linearSampler);
    writeCombined(r->device, r->blitSets[0], 0, r->graded.view, r->linearSampler);
    writeCombined(r->device, r->blitSets[1], 0, r->kawase[0].view, r->linearSampler);
    writeCombined(r->device, r->blitSets[2], 0, r->kawase[1].view, r->linearSampler);
    writeCombined(r->device, r->blitSets[3], 0, r->kawase[2].view, r->linearSampler);
    writeCombined(r->device, r->blitSets[4], 0, r->vectorTarget.view, r->linearSampler);
    writeCombined(r->device, r->copySet, 0, r->source.view, r->linearSampler);
    return true;
}

static void destroySwapchain(OpcVk* r) {
    for (auto fb : r->swapFbs) vkDestroyFramebuffer(r->device, fb, nullptr);
    for (auto v : r->swapViews) vkDestroyImageView(r->device, v, nullptr);
    r->swapFbs.clear();
    r->swapViews.clear();
    r->swapImages.clear();
    if (r->swapchain) vkDestroySwapchainKHR(r->device, r->swapchain, nullptr);
    r->swapchain = VK_NULL_HANDLE;
}

static bool createSwapchain(OpcVk* r, ANativeWindow* window, int w, int h) {
    destroySwapchain(r);
    if (r->surface) {
        vkDestroySurfaceKHR(r->instance, r->surface, nullptr);
        r->surface = VK_NULL_HANDLE;
    }
    if (r->window) {
        ANativeWindow_release(r->window);
        r->window = nullptr;
    }
    r->window = window;
    ANativeWindow_acquire(window);
    VkAndroidSurfaceCreateInfoKHR sci{VK_STRUCTURE_TYPE_ANDROID_SURFACE_CREATE_INFO_KHR};
    sci.window = window;
    if (vkCreateAndroidSurfaceKHR(r->instance, &sci, nullptr, &r->surface)) return false;

    VkSurfaceCapabilitiesKHR caps{};
    vkGetPhysicalDeviceSurfaceCapabilitiesKHR(r->gpu, r->surface, &caps);
    r->windowW = (uint32_t)std::max(1, w);
    r->windowH = (uint32_t)std::max(1, h);
    // Compose overlay is in window pixels. If we honor ROTATE_90 here, the
    // picture is -90 vs the HUD (S25 landscape: native 1080×2340, window 2340×1080).
    r->preTransform = (caps.supportedTransforms & VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR)
                          ? VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR
                          : caps.currentTransform;
    r->swapExtent = {r->windowW, r->windowH};
    if (caps.currentExtent.width != 0xFFFFFFFFu && r->preTransform == caps.currentTransform) {
        r->swapExtent = caps.currentExtent;
    }
    r->swapExtent.width = std::clamp(r->swapExtent.width, caps.minImageExtent.width, caps.maxImageExtent.width);
    r->swapExtent.height =
        std::clamp(r->swapExtent.height, caps.minImageExtent.height, caps.maxImageExtent.height);
    LOGI("swapchain win=%dx%d extent=%ux%u pre=0x%x current=0x%x supported=0x%x", w, h, r->swapExtent.width,
         r->swapExtent.height, r->preTransform, caps.currentTransform, caps.supportedTransforms);
    uint32_t fmtCount = 0;
    vkGetPhysicalDeviceSurfaceFormatsKHR(r->gpu, r->surface, &fmtCount, nullptr);
    std::vector<VkSurfaceFormatKHR> fmts(fmtCount);
    vkGetPhysicalDeviceSurfaceFormatsKHR(r->gpu, r->surface, &fmtCount, fmts.data());
    r->swapFormat = fmts.empty() ? VK_FORMAT_B8G8R8A8_UNORM : fmts[0].format;
    for (auto f : fmts) {
        if (f.format == VK_FORMAT_B8G8R8A8_UNORM || f.format == VK_FORMAT_R8G8B8A8_UNORM) {
            r->swapFormat = f.format;
            break;
        }
    }
    if (r->swapPass) vkDestroyRenderPass(r->device, r->swapPass, nullptr);
    r->swapPass = makePass(r->device, r->swapFormat, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, false);

    VkSwapchainCreateInfoKHR ci{VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR};
    ci.surface = r->surface;
    ci.minImageCount = std::max(2u, caps.minImageCount);
    ci.imageFormat = r->swapFormat;
    ci.imageColorSpace = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
    ci.imageExtent = r->swapExtent;
    ci.imageArrayLayers = 1;
    ci.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    ci.preTransform = r->preTransform;
    ci.compositeAlpha = VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR;
    if (caps.supportedCompositeAlpha & VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR)
        ci.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    ci.presentMode = VK_PRESENT_MODE_FIFO_KHR;
    ci.clipped = VK_TRUE;
    if (vkCreateSwapchainKHR(r->device, &ci, nullptr, &r->swapchain)) return false;
    uint32_t n = 0;
    vkGetSwapchainImagesKHR(r->device, r->swapchain, &n, nullptr);
    r->swapImages.resize(n);
    vkGetSwapchainImagesKHR(r->device, r->swapchain, &n, r->swapImages.data());
    r->swapViews.resize(n);
    r->swapFbs.resize(n);
    for (uint32_t i = 0; i < n; ++i) {
        VkImageViewCreateInfo vi{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
        vi.image = r->swapImages[i];
        vi.viewType = VK_IMAGE_VIEW_TYPE_2D;
        vi.format = r->swapFormat;
        vi.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        vkCreateImageView(r->device, &vi, nullptr, &r->swapViews[i]);
        r->swapFbs[i] = makeFb(r->device, r->swapPass, r->swapViews[i], r->swapExtent.width, r->swapExtent.height);
    }

    // Recreate swapchain-bound graphics pipes now that swapPass exists.
    auto vs = makeShader(r->device, fullscreen_vert_spv, fullscreen_vert_spv_count);
    auto fsBlit = makeShader(r->device, blit_frag_spv, blit_frag_spv_count);
    auto vsGlass = makeShader(r->device, glass_vert_spv, glass_vert_spv_count);
    auto fsGlass = makeShader(r->device, glass_frag_spv, glass_frag_spv_count);
    auto vsScope = makeShader(r->device, scope_vert_spv, scope_vert_spv_count);
    auto fsScope = makeShader(r->device, scope_frag_spv, scope_frag_spv_count);
    auto fsHisto = makeShader(r->device, histo_plot_frag_spv, histo_plot_frag_spv_count);
    if (r->blitPipe) vkDestroyPipeline(r->device, r->blitPipe, nullptr);
    if (r->blitAlphaPipe) vkDestroyPipeline(r->device, r->blitAlphaPipe, nullptr);
    if (r->glassPipe) vkDestroyPipeline(r->device, r->glassPipe, nullptr);
    if (r->scopePipe) vkDestroyPipeline(r->device, r->scopePipe, nullptr);
    if (r->histoPlotPipe) vkDestroyPipeline(r->device, r->histoPlotPipe, nullptr);
    r->blitPipe = makeGfx(r, r->blitLayout, r->swapPass, vs, fsBlit, false, false, 16);
    r->blitAlphaPipe = makeGfx(r, r->blitLayout, r->swapPass, vs, fsBlit, false, false, 16, true);
    r->glassPipe = makeGfx(r, r->glassLayout, r->swapPass, vsGlass, fsGlass, false, false, 80, true);
    r->scopePipe = makeGfx(r, r->scopeLayout, r->swapPass, vsScope, fsScope, true, true, 128);
    r->histoPlotPipe = makeGfx(r, r->histoPlotLayout, r->swapPass, vs, fsHisto, false, true, 80);
    vkDestroyShaderModule(r->device, vs, nullptr);
    vkDestroyShaderModule(r->device, fsBlit, nullptr);
    vkDestroyShaderModule(r->device, vsGlass, nullptr);
    vkDestroyShaderModule(r->device, fsGlass, nullptr);
    vkDestroyShaderModule(r->device, vsScope, nullptr);
    vkDestroyShaderModule(r->device, fsScope, nullptr);
    vkDestroyShaderModule(r->device, fsHisto, nullptr);
    return r->blitPipe && r->scopePipe;
}

static void destroyImportedImage(OpcVk* r) {
    auto& im = r->imported;
    if (im.view) vkDestroyImageView(r->device, im.view, nullptr);
    if (im.image) vkDestroyImage(r->device, im.image, nullptr);
    if (im.memory) vkFreeMemory(r->device, im.memory, nullptr);
    if (im.hb) AHardwareBuffer_release(im.hb);
    im.view = VK_NULL_HANDLE;
    im.image = VK_NULL_HANDLE;
    im.memory = VK_NULL_HANDLE;
    im.hb = nullptr;
    im.width = 0;
    im.height = 0;
}

static void destroyImportedConversion(OpcVk* r) {
    auto& im = r->imported;
    if (im.sampler) vkDestroySampler(r->device, im.sampler, nullptr);
    if (im.conversion) vkDestroySamplerYcbcrConversion(r->device, im.conversion, nullptr);
    im.sampler = VK_NULL_HANDLE;
    im.conversion = VK_NULL_HANDLE;
    r->ycbcrVkFormat = VK_FORMAT_MAX_ENUM;
    r->ycbcrExternal = 0;
}

static void destroyImported(OpcVk* r) {
    destroyImportedImage(r);
    destroyImportedConversion(r);
}

static void destroyAhbSlot(OpcVk* r, AhbSlot* s) {
    if (!s) return;
    if (s->view) vkDestroyImageView(r->device, s->view, nullptr);
    if (s->image) vkDestroyImage(r->device, s->image, nullptr);
    if (s->memory) vkFreeMemory(r->device, s->memory, nullptr);
    if (s->hb) AHardwareBuffer_release(s->hb);
    *s = {};
}

static void destroyAhbCache(OpcVk* r) {
    r->imported.hb = nullptr;
    r->imported.image = VK_NULL_HANDLE;
    r->imported.memory = VK_NULL_HANDLE;
    r->imported.view = VK_NULL_HANDLE;
    r->imported.width = 0;
    r->imported.height = 0;
    for (int i = 0; i < kAhbCache; i++) destroyAhbSlot(r, &r->ahbCache[i]);
}

static AhbSlot* findAhbSlot(OpcVk* r, AHardwareBuffer* hb) {
    for (int i = 0; i < kAhbCache; i++) {
        if (r->ahbCache[i].hb == hb) return &r->ahbCache[i];
    }
    return nullptr;
}

static AhbSlot* allocAhbSlot(OpcVk* r) {
    for (int i = 0; i < kAhbCache; i++) {
        if (!r->ahbCache[i].hb) return &r->ahbCache[i];
    }
    vkDeviceWaitIdle(r->device);
    destroyAhbSlot(r, &r->ahbCache[0]);
    return &r->ahbCache[0];
}

static void bindAhbSlot(OpcVk* r, AhbSlot* s) {
    r->imported.hb = s->hb;
    r->imported.image = s->image;
    r->imported.memory = s->memory;
    r->imported.view = s->view;
    r->imported.width = s->width;
    r->imported.height = s->height;
}

static void failAhbImport(OpcVk* r, AhbSlot* slot) {
    destroyAhbSlot(r, slot);
    r->imported.hb = nullptr;
    r->imported.image = VK_NULL_HANDLE;
    r->imported.memory = VK_NULL_HANDLE;
    r->imported.view = VK_NULL_HANDLE;
    r->imported.width = 0;
    r->imported.height = 0;
}

static bool isRgbAhbFormat(VkFormat format) {
    switch (format) {
        case VK_FORMAT_R8G8B8A8_UNORM:
        case VK_FORMAT_R8G8B8A8_SRGB:
        case VK_FORMAT_B8G8R8A8_UNORM:
        case VK_FORMAT_B8G8R8A8_SRGB:
        case VK_FORMAT_R5G6B5_UNORM_PACK16:
        case VK_FORMAT_A2B10G10R10_UNORM_PACK32:
            return true;
        default:
            return false;
    }
}

static bool importAhb(OpcVk* r, AHardwareBuffer* hb) {
    if (AhbSlot* hit = findAhbSlot(r, hb)) {
        if (r->imported.view != hit->view) {
            bindAhbSlot(r, hit);
            if (r->copySet && r->imported.sampler) {
                writeCombined(r->device, r->copySet, 0, r->imported.view, r->imported.sampler);
            }
        }
        return true;
    }

    AHardwareBuffer_Desc desc{};
    AHardwareBuffer_describe(hb, &desc);

    VkAndroidHardwareBufferFormatPropertiesANDROID fmt{
        VK_STRUCTURE_TYPE_ANDROID_HARDWARE_BUFFER_FORMAT_PROPERTIES_ANDROID};
    VkAndroidHardwareBufferPropertiesANDROID props{
        VK_STRUCTURE_TYPE_ANDROID_HARDWARE_BUFFER_PROPERTIES_ANDROID};
    props.pNext = &fmt;
    auto getProps = (PFN_vkGetAndroidHardwareBufferPropertiesANDROID)
        vkGetDeviceProcAddr(r->device, "vkGetAndroidHardwareBufferPropertiesANDROID");
    if (!getProps || getProps(r->device, hb, &props)) {
        LOGE("AHB properties failed");
        return false;
    }

    bool ycbcr = !isRgbAhbFormat(fmt.format);
    bool sameConversion =
        ycbcr && r->imported.conversion && r->ycbcrVkFormat == fmt.format &&
        r->ycbcrExternal == fmt.externalFormat;

    AhbSlot* slot = allocAhbSlot(r);
    AHardwareBuffer_acquire(hb);
    slot->hb = hb;
    slot->width = desc.width;
    slot->height = desc.height;
    bindAhbSlot(r, slot);

    VkExternalFormatANDROID extFmt{VK_STRUCTURE_TYPE_EXTERNAL_FORMAT_ANDROID};
    extFmt.externalFormat = fmt.externalFormat;
    VkExternalMemoryImageCreateInfo extImg{VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_IMAGE_CREATE_INFO};
    extImg.handleTypes = VK_EXTERNAL_MEMORY_HANDLE_TYPE_ANDROID_HARDWARE_BUFFER_BIT_ANDROID;
    VkImageCreateInfo ii{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    ii.pNext = &extImg;
    if (fmt.format == VK_FORMAT_UNDEFINED) {
        extImg.pNext = &extFmt;
        ii.format = VK_FORMAT_UNDEFINED;
    } else {
        ii.format = fmt.format;
    }
    ii.imageType = VK_IMAGE_TYPE_2D;
    ii.extent = {kSourceW, kSourceH, 1};
    if (desc.width && desc.height) {
        ii.extent = {desc.width, desc.height, 1};
    }
    ii.mipLevels = 1;
    ii.arrayLayers = 1;
    ii.samples = VK_SAMPLE_COUNT_1_BIT;
    ii.tiling = VK_IMAGE_TILING_OPTIMAL;
    ii.usage = VK_IMAGE_USAGE_SAMPLED_BIT;
    ii.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    ii.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    if (vkCreateImage(r->device, &ii, nullptr, &r->imported.image)) {
        LOGE("AHB vkCreateImage failed fmt=%u ext=%llu", fmt.format,
             (unsigned long long)fmt.externalFormat);
        failAhbImport(r, slot);
        return false;
    }
    slot->image = r->imported.image;

    if (props.allocationSize == 0 || props.memoryTypeBits == 0) {
        LOGE("AHB memory props empty size=%llu bits=%u", (unsigned long long)props.allocationSize,
             props.memoryTypeBits);
        failAhbImport(r, slot);
        return false;
    }

    VkImportAndroidHardwareBufferInfoANDROID importInfo{
        VK_STRUCTURE_TYPE_IMPORT_ANDROID_HARDWARE_BUFFER_INFO_ANDROID};
    importInfo.buffer = hb;
    VkMemoryDedicatedAllocateInfo ded{VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO};
    ded.pNext = &importInfo;
    ded.image = r->imported.image;
    VkMemoryAllocateInfo ai{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    ai.pNext = &ded;
    ai.allocationSize = props.allocationSize;
    ai.memoryTypeIndex = findMemory(r->gpu, props.memoryTypeBits, 0);
    if ((props.memoryTypeBits & (1u << ai.memoryTypeIndex)) == 0) {
        LOGE("AHB memory type %u not in bits %u", ai.memoryTypeIndex, props.memoryTypeBits);
        failAhbImport(r, slot);
        return false;
    }
    if (vkAllocateMemory(r->device, &ai, nullptr, &r->imported.memory) || !r->imported.memory) {
        LOGE("AHB vkAllocateMemory failed");
        failAhbImport(r, slot);
        return false;
    }
    slot->memory = r->imported.memory;
    VkBindImageMemoryInfo bind{VK_STRUCTURE_TYPE_BIND_IMAGE_MEMORY_INFO};
    bind.image = r->imported.image;
    bind.memory = r->imported.memory;
    if (vkBindImageMemory2(r->device, 1, &bind)) {
        LOGE("AHB vkBindImageMemory2 failed");
        failAhbImport(r, slot);
        return false;
    }

    if (ycbcr && !sameConversion) {
        vkDeviceWaitIdle(r->device);
        if (r->copyPipe) {
            vkDestroyPipeline(r->device, r->copyPipe, nullptr);
            r->copyPipe = VK_NULL_HANDLE;
        }
        if (r->copyLayout) {
            vkDestroyPipelineLayout(r->device, r->copyLayout, nullptr);
            r->copyLayout = VK_NULL_HANDLE;
        }
        if (r->copySetLayout) {
            vkDestroyDescriptorSetLayout(r->device, r->copySetLayout, nullptr);
            r->copySetLayout = VK_NULL_HANDLE;
        }
        if (r->copyPool) {
            vkDestroyDescriptorPool(r->device, r->copyPool, nullptr);
            r->copyPool = VK_NULL_HANDLE;
            r->copySet = VK_NULL_HANDLE;
        }
        destroyImportedConversion(r);
        VkSamplerYcbcrConversionCreateInfo yci{VK_STRUCTURE_TYPE_SAMPLER_YCBCR_CONVERSION_CREATE_INFO};
        yci.format = fmt.format;
        yci.ycbcrModel = fmt.suggestedYcbcrModel != VK_SAMPLER_YCBCR_MODEL_CONVERSION_RGB_IDENTITY
                             ? fmt.suggestedYcbcrModel
                             : VK_SAMPLER_YCBCR_MODEL_CONVERSION_YCBCR_709;
        yci.ycbcrRange = fmt.suggestedYcbcrRange;
        if (yci.ycbcrRange != VK_SAMPLER_YCBCR_RANGE_ITU_FULL &&
            yci.ycbcrRange != VK_SAMPLER_YCBCR_RANGE_ITU_NARROW) {
            yci.ycbcrRange = VK_SAMPLER_YCBCR_RANGE_ITU_NARROW;
        }
        yci.components = fmt.samplerYcbcrConversionComponents;
        yci.xChromaOffset = fmt.suggestedXChromaOffset;
        yci.yChromaOffset = fmt.suggestedYChromaOffset;
        bool linearYcbcr =
            (fmt.formatFeatures & VK_FORMAT_FEATURE_SAMPLED_IMAGE_YCBCR_CONVERSION_LINEAR_FILTER_BIT) != 0 ||
            fmt.format == VK_FORMAT_UNDEFINED;
        yci.chromaFilter = linearYcbcr ? VK_FILTER_LINEAR : VK_FILTER_NEAREST;
        if (fmt.format == VK_FORMAT_UNDEFINED) yci.pNext = &extFmt;
        if (vkCreateSamplerYcbcrConversion(r->device, &yci, nullptr, &r->imported.conversion)) {
            if (linearYcbcr) {
                yci.chromaFilter = VK_FILTER_NEAREST;
                linearYcbcr = false;
                if (vkCreateSamplerYcbcrConversion(r->device, &yci, nullptr, &r->imported.conversion)) {
                    LOGE("AHB ycbcr conversion failed fmt=%u model=%u", fmt.format, yci.ycbcrModel);
                    failAhbImport(r, slot);
                    return false;
                }
            } else {
                LOGE("AHB ycbcr conversion failed fmt=%u model=%u", fmt.format, yci.ycbcrModel);
                failAhbImport(r, slot);
                return false;
            }
        }
        VkSamplerYcbcrConversionInfo ybind{VK_STRUCTURE_TYPE_SAMPLER_YCBCR_CONVERSION_INFO};
        ybind.conversion = r->imported.conversion;
        VkSamplerCreateInfo si{VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO};
        si.pNext = &ybind;
        si.magFilter = yci.chromaFilter;
        si.minFilter = yci.chromaFilter;
        si.addressModeU = si.addressModeV = si.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
        if (vkCreateSampler(r->device, &si, nullptr, &r->imported.sampler)) {
            LOGE("AHB ycbcr sampler failed");
            failAhbImport(r, slot);
            return false;
        }
        if (!rebuildCopyLayout(r, r->imported.sampler)) {
            LOGE("AHB copy layout rebuild failed");
            failAhbImport(r, slot);
            return false;
        }
        r->ycbcrVkFormat = fmt.format;
        r->ycbcrExternal = fmt.externalFormat;
        LOGI("AHB ycbcr fmt=%u ext=%llu model=%u range=%u linear=%d feat=0x%x ahb=%ux%u tap=%ux%u well=%ux%u",
             fmt.format, (unsigned long long)fmt.externalFormat, yci.ycbcrModel, yci.ycbcrRange,
             linearYcbcr ? 1 : 0, fmt.formatFeatures, desc.width, desc.height, kSourceW, kSourceH,
             r->well.width, r->well.height);
    } else if (!ycbcr && !r->imported.sampler) {
        VkSamplerCreateInfo si{VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO};
        si.magFilter = VK_FILTER_LINEAR;
        si.minFilter = VK_FILTER_LINEAR;
        si.addressModeU = si.addressModeV = si.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
        vkCreateSampler(r->device, &si, nullptr, &r->imported.sampler);
    }

    VkSamplerYcbcrConversionInfo ybind{VK_STRUCTURE_TYPE_SAMPLER_YCBCR_CONVERSION_INFO};
    ybind.conversion = r->imported.conversion;
    VkImageViewCreateInfo vi{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
    if (r->imported.conversion) vi.pNext = &ybind;
    vi.image = r->imported.image;
    vi.viewType = VK_IMAGE_VIEW_TYPE_2D;
    vi.format = ii.format;
    vi.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    if (vkCreateImageView(r->device, &vi, nullptr, &r->imported.view)) {
        LOGE("AHB image view failed");
        failAhbImport(r, slot);
        return false;
    }
    slot->view = r->imported.view;

    writeCombined(r->device, r->copySet, 0, r->imported.view, r->imported.sampler);
    slot->image = r->imported.image;
    slot->memory = r->imported.memory;
    slot->view = r->imported.view;
    // Identity UVs: a 720×1280 Pocket screen flip is pillarboxed in the
    // cinema well (iOS `pictureFrame`). Do not rotate it back into 16:9.
    r->copyUvMode = 0.f;
    return true;
}

static void setViewport(VkCommandBuffer cmd, float x, float y, float w, float h) {
    VkViewport vp{x, y, w, h, 0.f, 1.f};
    VkRect2D sc{{(int32_t)x, (int32_t)y}, {(uint32_t)std::max(1.f, w), (uint32_t)std::max(1.f, h)}};
    vkCmdSetViewport(cmd, 0, 1, &vp);
    vkCmdSetScissor(cmd, 0, 1, &sc);
}

/** Aspect-fill [src] into dest, scissor-clipped to the dest rect ∩ framebuffer. */
static void setCoverViewportAt(VkCommandBuffer cmd, float srcW, float srcH, float dstX, float dstY,
                               float dstW, float dstH, uint32_t fbW, uint32_t fbH) {
    srcW = std::max(srcW, 1.f);
    srcH = std::max(srcH, 1.f);
    dstW = std::max(dstW, 1.f);
    dstH = std::max(dstH, 1.f);
    float scale = std::max(dstW / srcW, dstH / srcH);
    float cw = srcW * scale;
    float ch = srcH * scale;
    float x = dstX + (dstW - cw) * 0.5f;
    float y = dstY + (dstH - ch) * 0.5f;
    VkViewport vp{x, y, cw, ch, 0.f, 1.f};
    int sx = std::max(0, (int)std::lround(dstX));
    int sy = std::max(0, (int)std::lround(dstY));
    int sr = std::min((int)fbW, (int)std::lround(dstX + dstW));
    int sb = std::min((int)fbH, (int)std::lround(dstY + dstH));
    if (sr <= sx || sb <= sy) {
        sx = 0;
        sy = 0;
        sr = 1;
        sb = 1;
    }
    VkRect2D sc{{sx, sy}, {(uint32_t)(sr - sx), (uint32_t)(sb - sy)}};
    vkCmdSetViewport(cmd, 0, 1, &vp);
    vkCmdSetScissor(cmd, 0, 1, &sc);
}

static void setCoverViewport(VkCommandBuffer cmd, float srcW, float srcH, float dstW, float dstH) {
    setCoverViewportAt(cmd, srcW, srcH, 0.f, 0.f, dstW, dstH, (uint32_t)std::lround(dstW),
                       (uint32_t)std::lround(dstH));
}

static bool feedNeedsGrade(const OpcVk* r) {
    return r->lutSize >= 2.f || r->limitsOn > 0.5f || r->zebraHiOn > 0.5f || r->zebraMidOn > 0.5f ||
           r->splitOn > 0.5f || r->feedUpscale > 0.5f || r->mirror > 0.5f;
}

static void beginPass(VkCommandBuffer cmd, VkRenderPass pass, VkFramebuffer fb, uint32_t w, uint32_t h,
                      bool clear, float r = 0, float g = 0, float b = 0, float a = 1) {
    VkClearValue cv{};
    cv.color = {r, g, b, a};
    VkRenderPassBeginInfo bi{VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO};
    bi.renderPass = pass;
    bi.framebuffer = fb;
    bi.renderArea = {{0, 0}, {w, h}};
    bi.clearValueCount = clear ? 1 : 0;
    bi.pClearValues = &cv;
    vkCmdBeginRenderPass(cmd, &bi, VK_SUBPASS_CONTENTS_INLINE);
    setViewport(cmd, 0, 0, (float)w, (float)h);
}

static int pointCount(int w, int h, int stride) {
    int s = std::max(stride, 1);
    return std::max(w / s, 1) * std::max(h / s, 1);
}

static bool renderFrame(OpcVk* r) {
    if (!r->swapchain || !r->imported.view) return false;
    vkWaitForFences(r->device, 1, &r->fence, VK_TRUE, UINT64_MAX);
    const bool grade = feedNeedsGrade(r);
    const bool tap = r->needTap != 0;
    if ((grade || tap) && (!ensureWell(r) || !ensureCubeImages(r))) return false;
    vkResetFences(r->device, 1, &r->fence);
    uint32_t idx = 0;
    VkResult acq = vkAcquireNextImageKHR(r->device, r->swapchain, UINT64_MAX, VK_NULL_HANDLE, r->fence, &idx);
    if (acq == VK_ERROR_OUT_OF_DATE_KHR) return false;
    vkWaitForFences(r->device, 1, &r->fence, VK_TRUE, UINT64_MAX);
    vkResetFences(r->device, 1, &r->fence);
    vkResetCommandBuffer(r->cmd, 0);
    VkCommandBufferBeginInfo bi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    vkBeginCommandBuffer(r->cmd, &bi);
    if (grade) recordCubeUploads(r);

    VkImageMemoryBarrier barrier{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_FOREIGN_EXT;
    barrier.dstQueueFamilyIndex = r->queueFamily;
    barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    barrier.srcAccessMask = 0;
    barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
    barrier.image = r->imported.image;
    barrier.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    vkCmdPipelineBarrier(r->cmd, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0,
                         nullptr, 0, nullptr, 1, &barrier);

    float copyPc[2] = {1.f, r->copyUvMode};
    float ahbW = r->imported.width ? (float)r->imported.width : (float)kSourceW;
    float ahbH = r->imported.height ? (float)r->imported.height : (float)kSourceH;

    auto blitAhbToSwap = [&]() {
        beginPass(r->cmd, r->swapPass, r->swapFbs[idx], r->swapExtent.width, r->swapExtent.height, true, 0.078f,
                  0.078f, 0.078f, 1);
        vkCmdBindPipeline(r->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, r->copyPipe);
        vkCmdBindDescriptorSets(r->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, r->copyLayout, 0, 1, &r->copySet, 0, nullptr);
        vkCmdPushConstants(r->cmd, r->copyLayout, VK_SHADER_STAGE_FRAGMENT_BIT, 0, 8, copyPc);
        setCoverViewportAt(r->cmd, ahbW, ahbH, r->feedRect[0], r->feedRect[1], std::max(1.f, r->feedRect[2]),
                           std::max(1.f, r->feedRect[3]), r->swapExtent.width, r->swapExtent.height);
        vkCmdDraw(r->cmd, 3, 1, 0, 0);
        vkCmdEndRenderPass(r->cmd);
    };

    if (!grade && !tap) {
        blitAhbToSwap();
        vkEndCommandBuffer(r->cmd);
        VkSubmitInfo si{VK_STRUCTURE_TYPE_SUBMIT_INFO};
        si.commandBufferCount = 1;
        si.pCommandBuffers = &r->cmd;
        if (vkQueueSubmit(r->queue, 1, &si, r->fence)) return false;
        VkPresentInfoKHR pi{VK_STRUCTURE_TYPE_PRESENT_INFO_KHR};
        pi.swapchainCount = 1;
        pi.pSwapchains = &r->swapchain;
        pi.pImageIndices = &idx;
        vkQueuePresentKHR(r->queue, &pi);
        r->gpuBusy = false;
        return true;
    }

    if (tap) {
        vkCmdFillBuffer(r->cmd, r->histo.buffer, 0, r->histo.size, 0);
        vkCmdFillBuffer(r->cmd, r->display.buffer, 0, r->display.size, 0);
        beginPass(r->cmd, r->offscreenPass, r->sourceFb, kSourceW, kSourceH, true);
        vkCmdBindPipeline(r->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, r->copyPipe);
        vkCmdBindDescriptorSets(r->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, r->copyLayout, 0, 1, &r->copySet, 0, nullptr);
        vkCmdPushConstants(r->cmd, r->copyLayout, VK_SHADER_STAGE_FRAGMENT_BIT, 0, 8, copyPc);
        vkCmdDraw(r->cmd, 3, 1, 0, 0);
        vkCmdEndRenderPass(r->cmd);
    }

    beginPass(r->cmd, r->offscreenPass, r->wellFb, r->well.width, r->well.height, true);
    vkCmdBindPipeline(r->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, r->copyPipe);
    vkCmdBindDescriptorSets(r->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, r->copyLayout, 0, 1, &r->copySet, 0, nullptr);
    vkCmdPushConstants(r->cmd, r->copyLayout, VK_SHADER_STAGE_FRAGMENT_BIT, 0, 8, copyPc);
    // Portrait fill well is taller than 16:9. Cover (center-crop) so the
    // raster is not stretched — iOS `fillCrop` / `feed.height * 16/9`.
    setCoverViewport(r->cmd, ahbW, ahbH, (float)r->well.width, (float)r->well.height);
    vkCmdDraw(r->cmd, 3, 1, 0, 0);
    vkCmdEndRenderPass(r->cmd);

    VkMemoryBarrier mb{VK_STRUCTURE_TYPE_MEMORY_BARRIER};
    mb.srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
    mb.dstAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT;
    vkCmdPipelineBarrier(r->cmd, VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                         VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT | VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 1, &mb, 0,
                         nullptr, 0, nullptr);

    if (tap) {
        vkCmdBindPipeline(r->cmd, VK_PIPELINE_BIND_POINT_COMPUTE, r->histoPipe);
        vkCmdBindDescriptorSets(r->cmd, VK_PIPELINE_BIND_POINT_COMPUTE, r->histoLayout, 0, 1, &r->histoSet, 0, nullptr);
        struct HistoPC {
            int32_t tapW, tapH, stride;
            float pad;
            float lw, lg, lb, pad2;
        } hpc{(int)kSourceW, (int)kSourceH, r->stride, 0, r->lumaW[0], r->lumaW[1], r->lumaW[2], 0};
        vkCmdPushConstants(r->cmd, r->histoLayout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(hpc), &hpc);
        uint32_t gx = (kSourceW / std::max(r->stride, 1) + 7) / 8;
        uint32_t gy = (kSourceH / std::max(r->stride, 1) + 7) / 8;
        vkCmdDispatch(r->cmd, gx, gy, 1);
        VkMemoryBarrier c2{VK_STRUCTURE_TYPE_MEMORY_BARRIER};
        c2.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
        c2.dstAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT;
        vkCmdPipelineBarrier(r->cmd, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 1,
                             &c2, 0, nullptr, 0, nullptr);
        vkCmdBindPipeline(r->cmd, VK_PIPELINE_BIND_POINT_COMPUTE, r->remapPipe);
        vkCmdBindDescriptorSets(r->cmd, VK_PIPELINE_BIND_POINT_COMPUTE, r->remapLayout, 0, 1, &r->remapSet, 0, nullptr);
        vkCmdDispatch(r->cmd, 4, 1, 1);
        vkCmdPipelineBarrier(r->cmd, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                             VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT | VK_PIPELINE_STAGE_VERTEX_SHADER_BIT, 0, 1, &c2, 0,
                             nullptr, 0, nullptr);
    }

    beginPass(r->cmd, r->offscreenPass, r->gradedFb, r->well.width, r->well.height, true);
    vkCmdBindPipeline(r->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, r->feedPipe);
    vkCmdBindDescriptorSets(r->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, r->feedLayout, 0, 1, &r->feedSet, 0, nullptr);
    struct FeedPC {
        float sourceSize[2];
        float displaySize[2];
        float lutSize, limitsPaintSize, limitsWeightSize, limitsOn;
        float splitOn, splitVertical, zebraHiOn, zebraHi, zebraMidOn, zebraMid, zebraMidHalf, feedUpscale, mirror, pad;
        float zebraHiColor[4];
        float zebraMidColor[4];
    } fpc{};
    fpc.sourceSize[0] = (float)r->well.width;
    fpc.sourceSize[1] = (float)r->well.height;
    fpc.displaySize[0] = r->feedRect[2];
    fpc.displaySize[1] = r->feedRect[3];
    fpc.lutSize = r->lutSize;
    fpc.limitsPaintSize = r->limitsPaintSize;
    fpc.limitsWeightSize = r->limitsWeightSize;
    fpc.limitsOn = r->limitsOn;
    fpc.splitOn = r->splitOn;
    fpc.splitVertical = r->splitVertical;
    fpc.zebraHiOn = r->zebraHiOn;
    fpc.zebraHi = r->zebraHi;
    fpc.zebraMidOn = r->zebraMidOn;
    fpc.zebraMid = r->zebraMid;
    fpc.zebraMidHalf = r->zebraMidHalf;
    // YCbCr is already sampled at the well. Catmull-Rom on that RGB rings
    // around HEVC blocks. Keep the identity sample here.
    fpc.feedUpscale = 0.f;
    fpc.mirror = r->mirror;
    memcpy(fpc.zebraHiColor, r->zebraHiColor, 12);
    memcpy(fpc.zebraMidColor, r->zebraMidColor, 12);
    vkCmdPushConstants(r->cmd, r->feedLayout, VK_SHADER_STAGE_FRAGMENT_BIT, 0, sizeof(fpc), &fpc);
    vkCmdDraw(r->cmd, 3, 1, 0, 0);
    vkCmdEndRenderPass(r->cmd);

    if (r->plateCount) {
        ImageMem* prev = &r->graded;
        VkDescriptorSet prevSet = r->blitSets[0];
        for (int i = 0; i < 3; ++i) {
            beginPass(r->cmd, r->offscreenPass, r->kawaseFb[i], r->kawase[i].width, r->kawase[i].height, true);
            vkCmdBindPipeline(r->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, r->kawasePipe);
            vkCmdBindDescriptorSets(r->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, r->blitLayout, 0, 1, &prevSet, 0, nullptr);
            float kaw[4] = {1.f / prev->width, 1.f / prev->height, 1.5f, 0};
            vkCmdPushConstants(r->cmd, r->blitLayout, VK_SHADER_STAGE_FRAGMENT_BIT, 0, 16, kaw);
            vkCmdDraw(r->cmd, 3, 1, 0, 0);
            vkCmdEndRenderPass(r->cmd);
            prev = &r->kawase[i];
            prevSet = r->blitSets[i + 1];
            (void)prev;
        }
    }

    if (r->slots[3].visible) {
        beginPass(r->cmd, r->offscreenPass, r->vectorFb, kVectorN, kVectorN, true, 0, 0, 0, 0);
        vkCmdBindPipeline(r->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, r->vectorPipe);
        vkCmdBindDescriptorSets(r->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, r->vectorLayout, 0, 1, &r->feedSet, 0,
                                nullptr);
        struct VecPC {
            float tap[2];
            int stride;
            float gain;
            float intensity;
            float lutSize;
            float pad[2];
            float luma[4];
        } vpc{};
        vpc.tap[0] = kSourceW;
        vpc.tap[1] = kSourceH;
        vpc.stride = r->stride;
        vpc.gain = r->slots[3].gain;
        vpc.intensity = r->slots[3].intensity;
        vpc.lutSize = r->lutSize;
        memcpy(vpc.luma, r->lumaW, 12);
        vkCmdPushConstants(r->cmd, r->vectorLayout,
                           VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, 0, sizeof(vpc), &vpc);
        vkCmdDraw(r->cmd, pointCount(kSourceW, kSourceH, r->stride), 1, 0, 0);
        vkCmdEndRenderPass(r->cmd);
    }

    beginPass(r->cmd, r->swapPass, r->swapFbs[idx], r->swapExtent.width, r->swapExtent.height, true, 0.078f,
              0.078f, 0.078f, 1);
    setViewport(r->cmd, r->feedRect[0], r->feedRect[1], std::max(1.f, r->feedRect[2]), std::max(1.f, r->feedRect[3]));
    vkCmdBindPipeline(r->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, r->blitPipe);
    vkCmdBindDescriptorSets(r->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, r->blitLayout, 0, 1, &r->blitSets[0], 0, nullptr);
    float blitPc[2] = {1.f, 0.f};
    vkCmdPushConstants(r->cmd, r->blitLayout, VK_SHADER_STAGE_FRAGMENT_BIT, 0, 8, blitPc);
    vkCmdDraw(r->cmd, 3, 1, 0, 0);

    if (r->plateCount) {
        vkCmdBindPipeline(r->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, r->glassPipe);
        vkCmdBindDescriptorSets(r->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, r->glassLayout, 0, 1, &r->glassSet, 0,
                                nullptr);
        setViewport(r->cmd, 0, 0, (float)r->swapExtent.width, (float)r->swapExtent.height);
        for (uint32_t i = 0; i < r->plateCount; ++i) {
            struct GlassPC {
                float rect[4];
                float overlay[2];
                float radius, pad;
                float tint[4];
                float feed[4];
            } g{};
            auto& p = r->plates[i];
            g.rect[0] = p.x;
            g.rect[1] = p.y;
            g.rect[2] = p.w;
            g.rect[3] = p.h;
            g.overlay[0] = (float)r->swapExtent.width;
            g.overlay[1] = (float)r->swapExtent.height;
            g.radius = p.radius;
            g.tint[0] = p.r;
            g.tint[1] = p.g;
            g.tint[2] = p.b;
            g.tint[3] = p.a;
            memcpy(g.feed, r->feedRect, 16);
            vkCmdPushConstants(r->cmd, r->glassLayout,
                               VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, 0, sizeof(g), &g);
            vkCmdDraw(r->cmd, 4, 1, 0, 0);
        }
    }

    const float d = r->uiScale > 0.f ? r->uiScale : 1.f;

    // Compose punches a plot hole through the same DJI-black 72% plate.
    // Fill that hole with the identical RGBA (src-alpha) so the plot is not
    // a cutout onto the live picture, then draw traces on top.
    auto fillPlot = [&](const Slot& slot) {
        if (!r->glassPipe || !slot.visible || slot.w < 8.f || slot.h < 8.f) return;
        vkCmdBindPipeline(r->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, r->glassPipe);
        vkCmdBindDescriptorSets(r->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, r->glassLayout, 0, 1, &r->glassSet, 0,
                                nullptr);
        setViewport(r->cmd, 0, 0, (float)r->swapExtent.width, (float)r->swapExtent.height);
        struct GlassPC {
            float rect[4];
            float overlay[2];
            float radius, pad;
            float tint[4];
            float feed[4];
        } g{};
        g.rect[0] = slot.x;
        g.rect[1] = slot.y;
        g.rect[2] = slot.w;
        g.rect[3] = slot.h;
        g.overlay[0] = (float)r->swapExtent.width;
        g.overlay[1] = (float)r->swapExtent.height;
        g.radius = 0.f;
        g.pad = 1.f;
        g.tint[0] = kScopePlateR;
        g.tint[1] = kScopePlateG;
        g.tint[2] = kScopePlateB;
        g.tint[3] = kScopePlateA;
        memcpy(g.feed, r->feedRect, 16);
        vkCmdPushConstants(r->cmd, r->glassLayout,
                           VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, 0, sizeof(g), &g);
        vkCmdDraw(r->cmd, 4, 1, 0, 0);
    };

    auto drawWave = [&](const Slot& slot, int kind) {
        if (!slot.visible || slot.w < 8 || slot.h < 8) return;
        setViewport(r->cmd, slot.x, slot.y, slot.w, slot.h);
        {
            // iOS `scopeTraceClipRect` — 2pt past the 0 / 100 strokes.
            int sx = (int)std::floor(slot.x);
            int sy = (int)std::floor(slot.y - d * 2.f);
            int sw = (int)std::ceil(slot.w);
            int sh = (int)std::ceil(slot.h + d * 4.f);
            int fbW = (int)r->swapExtent.width;
            int fbH = (int)r->swapExtent.height;
            if (sx < 0) {
                sw += sx;
                sx = 0;
            }
            if (sy < 0) {
                sh += sy;
                sy = 0;
            }
            if (sx + sw > fbW) sw = fbW - sx;
            if (sy + sh > fbH) sh = fbH - sy;
            if (sw < 1 || sh < 1) return;
            VkRect2D clip{{sx, sy}, {(uint32_t)sw, (uint32_t)sh}};
            vkCmdSetScissor(r->cmd, 0, 1, &clip);
        }
        vkCmdBindPipeline(r->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, r->scopePipe);
        vkCmdBindDescriptorSets(r->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, r->scopeLayout, 0, 1, &r->scopeSet, 0,
                                nullptr);
        struct ScopePC {
            float plot[4];
            float panel[2];
            float tap[2];
            int stride, channel, lane, laneCount, kind, hotEvery;
            float pointSize, intensity;
            float color[4];
            float luma[4];
        } pc{};
        pc.plot[0] = 0.f;
        pc.plot[1] = 0.f;
        pc.plot[2] = slot.w;
        pc.plot[3] = slot.h;
        pc.panel[0] = slot.w;
        pc.panel[1] = slot.h;
        pc.tap[0] = kSourceW;
        pc.tap[1] = kSourceH;
        pc.stride = r->stride;
        pc.kind = kind;
        pc.intensity = slot.intensity;
        memcpy(pc.luma, r->lumaW, 12);
        int n = pointCount(kSourceW, kSourceH, r->stride);
        auto pass = [&](int channel, int lane, int lanes, float size, const float col[4]) {
            pc.channel = channel;
            pc.lane = lane;
            pc.laneCount = lanes;
            pc.pointSize = size;
            memcpy(pc.color, col, 16);
            vkCmdPushConstants(r->cmd, r->scopeLayout,
                               VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, 0, sizeof(pc), &pc);
            vkCmdDraw(r->cmd, n, 1, 0, 0);
        };
        if (kind == 0) {
            if (slot.mode == 0) {
                float ghost[] = {182 / 255.f, 190 / 255.f, 186 / 255.f, 0.08f};
                float core[] = {222 / 255.f, 230 / 255.f, 224 / 255.f, 1};
                float hot[] = {1, 1, 1, 1};
                pass(0, 0, 1, 2, ghost);
                pass(0, 0, 1, 1, core);
                pc.hotEvery = 4;
                pass(0, 0, 1, 1, hot);
                pc.hotEvery = 0;
            } else {
                float red[] = {1, 64 / 255.f, 54 / 255.f, 0.55f};
                float green[] = {70 / 255.f, 240 / 255.f, 110 / 255.f, 0.55f};
                float blue[] = {72 / 255.f, 148 / 255.f, 255 / 255.f, 0.62f};
                pass(1, 0, 1, 1, red);
                pass(2, 0, 1, 1, green);
                pass(3, 0, 1, 1, blue);
            }
        } else {
            int lanes = slot.mode == 1 ? 4 : 3;
            int lane = 0;
            if (lanes == 4) {
                float luma[] = {222 / 255.f, 230 / 255.f, 224 / 255.f, 1};
                pass(0, lane++, lanes, 1, luma);
            }
            float red[] = {1, 86 / 255.f, 78 / 255.f, 1};
            float green[] = {102 / 255.f, 232 / 255.f, 132 / 255.f, 1};
            float blue[] = {92 / 255.f, 156 / 255.f, 255 / 255.f, 1};
            pass(1, lane++, lanes, 1, red);
            pass(2, lane++, lanes, 1, green);
            pass(3, lane, lanes, 1, blue);
        }
    };
    auto blitVector = [&]() {
        if (!r->slots[3].visible || r->slots[3].w <= 8) return;
        setViewport(r->cmd, r->slots[3].x, r->slots[3].y, r->slots[3].w, r->slots[3].h);
        vkCmdBindPipeline(r->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, r->blitAlphaPipe ? r->blitAlphaPipe : r->blitPipe);
        vkCmdBindDescriptorSets(r->cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, r->blitLayout, 0, 1, &r->blitSets[4], 0,
                                nullptr);
        float vecPc[2] = {1.f, 0.f};
        vkCmdPushConstants(r->cmd, r->blitLayout, VK_SHADER_STAGE_FRAGMENT_BIT, 0, 8, vecPc);
        vkCmdDraw(r->cmd, 3, 1, 0, 0);
    };
    auto emitScope = [&](int idx) {
        if (idx == 0) {
            fillPlot(r->slots[0]);
            drawWave(r->slots[0], 0);
        } else if (idx == 1) {
            fillPlot(r->slots[1]);
            drawWave(r->slots[1], 1);
        } else if (idx == 3) {
            fillPlot(r->slots[3]);
            blitVector();
        }
    };
    if (r->stackCount <= 0) {
        emitScope(0);
        emitScope(1);
        emitScope(3);
    } else {
        for (int i = 0; i < r->stackCount; ++i) emitScope(r->stackOrder[i]);
    }

    vkCmdEndRenderPass(r->cmd);

    // Downsample the 1280×720 source to a CPU tap so Compose WAVE / PARADE /
    // VECTOR can paint on the plate. Armed only on the 10–15 Hz sample tick.
    if (r->needTap && r->tap.image && r->staging.mapped && r->source.image) {
        auto imgBar = [&](VkImage img, VkImageLayout oldL, VkImageLayout newL, VkAccessFlags srcA,
                          VkAccessFlags dstA, VkPipelineStageFlags srcS, VkPipelineStageFlags dstS) {
            VkImageMemoryBarrier b{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};
            b.oldLayout = oldL;
            b.newLayout = newL;
            b.srcAccessMask = srcA;
            b.dstAccessMask = dstA;
            b.image = img;
            b.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
            vkCmdPipelineBarrier(r->cmd, srcS, dstS, 0, 0, nullptr, 0, nullptr, 1, &b);
        };
        imgBar(r->source.image, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
               VK_ACCESS_SHADER_READ_BIT, VK_ACCESS_TRANSFER_READ_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
               VK_PIPELINE_STAGE_TRANSFER_BIT);
        imgBar(r->tap.image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 0,
               VK_ACCESS_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT);
        VkImageBlit blit{};
        blit.srcSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
        blit.srcOffsets[1] = {(int32_t)kSourceW, (int32_t)kSourceH, 1};
        blit.dstSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
        blit.dstOffsets[1] = {(int32_t)kTapW, (int32_t)kTapH, 1};
        vkCmdBlitImage(r->cmd, r->source.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, r->tap.image,
                       VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &blit, VK_FILTER_LINEAR);
        imgBar(r->tap.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
               VK_ACCESS_TRANSFER_WRITE_BIT, VK_ACCESS_TRANSFER_READ_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
               VK_PIPELINE_STAGE_TRANSFER_BIT);
        VkBufferImageCopy bic{};
        bic.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
        bic.imageExtent = {kTapW, kTapH, 1};
        vkCmdCopyImageToBuffer(r->cmd, r->tap.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, r->staging.buffer, 1,
                               &bic);
        VkBufferMemoryBarrier bb{VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER};
        bb.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        bb.dstAccessMask = VK_ACCESS_HOST_READ_BIT;
        bb.buffer = r->staging.buffer;
        bb.size = (VkDeviceSize)kTapW * kTapH * 4;
        vkCmdPipelineBarrier(r->cmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_HOST_BIT, 0, 0, nullptr, 1,
                             &bb, 0, nullptr);
    }

    vkEndCommandBuffer(r->cmd);

    VkSubmitInfo si{VK_STRUCTURE_TYPE_SUBMIT_INFO};
    si.commandBufferCount = 1;
    si.pCommandBuffers = &r->cmd;
    if (vkQueueSubmit(r->queue, 1, &si, r->fence)) return false;
    if (tap) vkWaitForFences(r->device, 1, &r->fence, VK_TRUE, UINT64_MAX);
    VkPresentInfoKHR pi{VK_STRUCTURE_TYPE_PRESENT_INFO_KHR};
    pi.swapchainCount = 1;
    pi.pSwapchains = &r->swapchain;
    pi.pImageIndices = &idx;
    vkQueuePresentKHR(r->queue, &pi);
    r->gpuBusy = false;
    return true;
}

static void destroyAll(OpcVk* r) {
    if (!r->device) {
        if (r->instance) vkDestroyInstance(r->instance, nullptr);
        return;
    }
    vkDeviceWaitIdle(r->device);
    destroyAhbCache(r);
    destroyImportedConversion(r);
    destroySwapchain(r);
    if (r->surface) vkDestroySurfaceKHR(r->instance, r->surface, nullptr);
    if (r->window) ANativeWindow_release(r->window);
    auto killPipe = [&](VkPipeline p) { if (p) vkDestroyPipeline(r->device, p, nullptr); };
    killPipe(r->blitPipe);
    killPipe(r->blitAlphaPipe);
    killPipe(r->feedPipe);
    killPipe(r->scopePipe);
    killPipe(r->histoPipe);
    killPipe(r->remapPipe);
    killPipe(r->histoPlotPipe);
    killPipe(r->glassPipe);
    killPipe(r->copyPipe);
    killPipe(r->kawasePipe);
    killPipe(r->vectorPipe);
    auto killLayout = [&](VkPipelineLayout p) { if (p) vkDestroyPipelineLayout(r->device, p, nullptr); };
    killLayout(r->blitLayout);
    killLayout(r->feedLayout);
    killLayout(r->scopeLayout);
    killLayout(r->histoLayout);
    killLayout(r->remapLayout);
    killLayout(r->histoPlotLayout);
    killLayout(r->glassLayout);
    killLayout(r->copyLayout);
    killLayout(r->vectorLayout);
    auto killSet = [&](VkDescriptorSetLayout p) { if (p) vkDestroyDescriptorSetLayout(r->device, p, nullptr); };
    killSet(r->blitSetLayout);
    killSet(r->feedSetLayout);
    killSet(r->scopeSetLayout);
    killSet(r->histoSetLayout);
    killSet(r->remapSetLayout);
    killSet(r->histoPlotSetLayout);
    killSet(r->glassSetLayout);
    killSet(r->copySetLayout);
    if (r->copyPool) vkDestroyDescriptorPool(r->device, r->copyPool, nullptr);
    if (r->descPool) vkDestroyDescriptorPool(r->device, r->descPool, nullptr);
    if (r->sourceFb) vkDestroyFramebuffer(r->device, r->sourceFb, nullptr);
    if (r->vectorFb) vkDestroyFramebuffer(r->device, r->vectorFb, nullptr);
    destroyWellChain(r);
    if (r->offscreenPass) vkDestroyRenderPass(r->device, r->offscreenPass, nullptr);
    if (r->loadPass) vkDestroyRenderPass(r->device, r->loadPass, nullptr);
    if (r->swapPass) vkDestroyRenderPass(r->device, r->swapPass, nullptr);
    if (r->linearSampler) vkDestroySampler(r->device, r->linearSampler, nullptr);
    destroyImage(r->device, &r->source);
    destroyImage(r->device, &r->tap);
    destroyImage(r->device, &r->vectorTarget);
    destroyImage(r->device, &r->lut);
    destroyImage(r->device, &r->limitsPaint);
    destroyImage(r->device, &r->limitsWeight);
    destroyBuffer(r->device, &r->histo);
    destroyBuffer(r->device, &r->display);
    destroyBuffer(r->device, &r->ire);
    destroyBuffer(r->device, &r->staging);
    if (r->cache) vkDestroyPipelineCache(r->device, r->cache, nullptr);
    if (r->fence) vkDestroyFence(r->device, r->fence, nullptr);
    if (r->cmdPool) vkDestroyCommandPool(r->device, r->cmdPool, nullptr);
    vkDestroyDevice(r->device, nullptr);
    vkDestroyInstance(r->instance, nullptr);
}

static OpcVk* fromHandle(jlong h) { return reinterpret_cast<OpcVk*>(h); }

// JNI
extern "C" JNIEXPORT jlong JNICALL
Java_com_opencapture_openpocketcine_feed_OpcVulkan_nativeCreate(JNIEnv*, jclass) {
    auto* r = new OpcVk();
    if (!createDevice(r) || !createResources(r)) {
        LOGE("vulkan init failed");
        destroyAll(r);
        delete r;
        return 0;
    }
    r->ready = true;
    LOGI("vulkan renderer ready");
    return reinterpret_cast<jlong>(r);
}

extern "C" JNIEXPORT void JNICALL
Java_com_opencapture_openpocketcine_feed_OpcVulkan_nativeDestroy(JNIEnv*, jclass, jlong h) {
    auto* r = fromHandle(h);
    if (!r) return;
    destroyAll(r);
    delete r;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_opencapture_openpocketcine_feed_OpcVulkan_nativeAttachWindow(JNIEnv* env, jclass, jlong h,
                                                                     jobject surface, jint w, jint height) {
    auto* r = fromHandle(h);
    if (!r || !surface) return JNI_FALSE;
    std::lock_guard<std::mutex> g(r->lock);
    ANativeWindow* win = ANativeWindow_fromSurface(env, surface);
    if (!win) return JNI_FALSE;
    bool ok = createSwapchain(r, win, w, height);
    ANativeWindow_release(win);
    return ok ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_opencapture_openpocketcine_feed_OpcVulkan_nativeResize(JNIEnv*, jclass, jlong h, jint w, jint height) {
    auto* r = fromHandle(h);
    if (!r || !r->window) return;
    std::lock_guard<std::mutex> g(r->lock);
    vkDeviceWaitIdle(r->device);
    ANativeWindow_acquire(r->window);
    createSwapchain(r, r->window, w, height);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_opencapture_openpocketcine_feed_OpcVulkan_nativeSubmit(JNIEnv* env, jclass, jlong h,
                                                               jobject buffer) {
    auto* r = fromHandle(h);
    if (!r || !buffer) return JNI_FALSE;
    std::lock_guard<std::mutex> g(r->lock);
    vkWaitForFences(r->device, 1, &r->fence, VK_TRUE, UINT64_MAX);
    AHardwareBuffer* hb = AHardwareBuffer_fromHardwareBuffer(env, buffer);
    if (!hb) return JNI_FALSE;
    if (!importAhb(r, hb)) return JNI_FALSE;
    bool ok = renderFrame(r);
    return ok ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_opencapture_openpocketcine_feed_OpcVulkan_nativeRedraw(JNIEnv*, jclass, jlong h) {
    auto* r = fromHandle(h);
    if (!r) return JNI_FALSE;
    std::lock_guard<std::mutex> g(r->lock);
    if (!r->imported.view) return JNI_FALSE;
    return renderFrame(r) ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_opencapture_openpocketcine_feed_OpcVulkan_nativeSetFeedRect(JNIEnv*, jclass, jlong h, jfloat x,
                                                                    jfloat y, jfloat w, jfloat ht) {
    auto* r = fromHandle(h);
    if (!r) return;
    std::lock_guard<std::mutex> g(r->lock);
    r->feedRect[0] = x;
    r->feedRect[1] = y;
    r->feedRect[2] = w;
    r->feedRect[3] = ht;
}

extern "C" JNIEXPORT void JNICALL
Java_com_opencapture_openpocketcine_feed_OpcVulkan_nativeSetUiScale(JNIEnv*, jclass, jlong h, jfloat scale) {
    auto* r = fromHandle(h);
    if (!r) return;
    std::lock_guard<std::mutex> g(r->lock);
    r->uiScale = scale > 0.f ? scale : 1.f;
}

extern "C" JNIEXPORT void JNICALL
Java_com_opencapture_openpocketcine_feed_OpcVulkan_nativeSetSlots(JNIEnv* env, jclass, jlong h,
                                                                 jfloatArray arr) {
    auto* r = fromHandle(h);
    if (!r || !arr) return;
    std::lock_guard<std::mutex> g(r->lock);
    jsize n = env->GetArrayLength(arr);
    jfloat* p = env->GetFloatArrayElements(arr, nullptr);
    for (int i = 0; i < 4 && (i * 8 + 7) < n; ++i) {
        auto& s = r->slots[i];
        s.visible = p[i * 8 + 0] > 0.5f;
        s.x = p[i * 8 + 1];
        s.y = p[i * 8 + 2];
        s.w = p[i * 8 + 3];
        s.h = p[i * 8 + 4];
        s.mode = (int)p[i * 8 + 5];
        s.intensity = p[i * 8 + 6];
        s.gain = p[i * 8 + 7];
    }
    env->ReleaseFloatArrayElements(arr, p, JNI_ABORT);
}

extern "C" JNIEXPORT void JNICALL
Java_com_opencapture_openpocketcine_feed_OpcVulkan_nativeSetStack(JNIEnv* env, jclass, jlong h,
                                                                 jintArray arr) {
    auto* r = fromHandle(h);
    if (!r || !arr) return;
    std::lock_guard<std::mutex> g(r->lock);
    jsize n = env->GetArrayLength(arr);
    jint* p = env->GetIntArrayElements(arr, nullptr);
    r->stackCount = 0;
    for (int i = 0; i < n && r->stackCount < 4; ++i) {
        int idx = p[i];
        if (idx == 0 || idx == 1 || idx == 3) r->stackOrder[r->stackCount++] = idx;
    }
    env->ReleaseIntArrayElements(arr, p, JNI_ABORT);
}

extern "C" JNIEXPORT void JNICALL
Java_com_opencapture_openpocketcine_feed_OpcVulkan_nativeSetPlates(JNIEnv* env, jclass, jlong h,
                                                                  jfloatArray arr) {
    auto* r = fromHandle(h);
    if (!r || !arr) return;
    std::lock_guard<std::mutex> g(r->lock);
    jsize n = env->GetArrayLength(arr);
    jfloat* p = env->GetFloatArrayElements(arr, nullptr);
    r->plateCount = std::min((uint32_t)(n / 9), kMaxPlates);
    for (uint32_t i = 0; i < r->plateCount; ++i) {
        auto& pl = r->plates[i];
        pl.x = p[i * 9 + 0];
        pl.y = p[i * 9 + 1];
        pl.w = p[i * 9 + 2];
        pl.h = p[i * 9 + 3];
        pl.radius = p[i * 9 + 4];
        pl.r = p[i * 9 + 5];
        pl.g = p[i * 9 + 6];
        pl.b = p[i * 9 + 7];
        pl.a = p[i * 9 + 8];
    }
    env->ReleaseFloatArrayElements(arr, p, JNI_ABORT);
}

extern "C" JNIEXPORT void JNICALL
Java_com_opencapture_openpocketcine_feed_OpcVulkan_nativeSetIre(JNIEnv* env, jclass, jlong h,
                                                               jfloatArray arr, jfloat lr, jfloat lg,
                                                               jfloat lb, jint stride) {
    auto* r = fromHandle(h);
    if (!r || !arr || !r->ire.mapped) return;
    std::lock_guard<std::mutex> g(r->lock);
    jsize n = std::min(256, env->GetArrayLength(arr));
    jfloat* p = env->GetFloatArrayElements(arr, nullptr);
    memcpy(r->ire.mapped, p, n * 4);
    env->ReleaseFloatArrayElements(arr, p, JNI_ABORT);
    r->lumaW[0] = lr;
    r->lumaW[1] = lg;
    r->lumaW[2] = lb;
    r->stride = stride > 0 ? stride : 2;
}

extern "C" JNIEXPORT void JNICALL
Java_com_opencapture_openpocketcine_feed_OpcVulkan_nativeSetCube(
    JNIEnv* env, jclass, jlong h, jint slot, jbyteArray rgba, jint width, jint height,
    jfloat cubeSize) {
    auto* r = fromHandle(h);
    if (!r || slot < 0 || slot > 2) return;
    std::lock_guard<std::mutex> g(r->lock);
    auto& c = r->cube[slot];
    if (!rgba || width < 2 || height < 2 || cubeSize < 2.f) {
        c.rgba.clear();
        c.w = 8;
        c.h = 8;
        c.cubeSize = 0;
        c.dirty = true;
    } else {
        jsize n = env->GetArrayLength(rgba);
        if (n != width * height * 4) return;
        c.rgba.resize((size_t)n);
        env->GetByteArrayRegion(rgba, 0, n, reinterpret_cast<jbyte*>(c.rgba.data()));
        c.w = (uint32_t)width;
        c.h = (uint32_t)height;
        c.cubeSize = cubeSize;
        c.dirty = true;
    }
    if (slot == 0) r->lutSize = c.cubeSize;
    if (slot == 1) r->limitsPaintSize = c.cubeSize;
    if (slot == 2) r->limitsWeightSize = c.cubeSize;
}

extern "C" JNIEXPORT void JNICALL
Java_com_opencapture_openpocketcine_feed_OpcVulkan_nativeSetFeedFlags(
    JNIEnv*, jclass, jlong h, jfloat lutSize, jfloat limitsOn, jfloat splitOn, jfloat splitVertical,
    jfloat zebraHiOn, jfloat zebraHi, jfloat zebraMidOn, jfloat zebraMid, jfloat zebraMidHalf,
    jfloat upscale, jfloat mirror) {
    auto* r = fromHandle(h);
    if (!r) return;
    std::lock_guard<std::mutex> g(r->lock);
    r->lutSize = lutSize;
    r->limitsOn = limitsOn;
    r->splitOn = splitOn;
    r->splitVertical = splitVertical;
    r->zebraHiOn = zebraHiOn;
    r->zebraHi = zebraHi;
    r->zebraMidOn = zebraMidOn;
    r->zebraMid = zebraMid;
    r->zebraMidHalf = zebraMidHalf;
    r->feedUpscale = upscale;
    r->mirror = mirror;
}

extern "C" JNIEXPORT void JNICALL
Java_com_opencapture_openpocketcine_feed_OpcVulkan_nativeCopyHisto(JNIEnv* env, jclass, jlong h,
                                                                  jintArray out) {
    auto* r = fromHandle(h);
    if (!r || !out || !r->histo.mapped) return;
    std::lock_guard<std::mutex> g(r->lock);
    jsize n = std::min(1024, env->GetArrayLength(out));
    env->SetIntArrayRegion(out, 0, n, reinterpret_cast<jint*>(r->histo.mapped));
}

extern "C" JNIEXPORT void JNICALL
Java_com_opencapture_openpocketcine_feed_OpcVulkan_nativeSetNeedTap(JNIEnv*, jclass, jlong h, jboolean on) {
    auto* r = fromHandle(h);
    if (!r) return;
    std::lock_guard<std::mutex> g(r->lock);
    r->needTap = on ? 1 : 0;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_opencapture_openpocketcine_feed_OpcVulkan_nativeCopyTap(JNIEnv* env, jclass, jlong h,
                                                               jbyteArray out) {
    auto* r = fromHandle(h);
    const jint need = (jint)(kTapW * kTapH * 4);
    if (!r || !out || !r->staging.mapped) return JNI_FALSE;
    std::lock_guard<std::mutex> g(r->lock);
    if (env->GetArrayLength(out) < need) return JNI_FALSE;
    env->SetByteArrayRegion(out, 0, need, reinterpret_cast<jbyte*>(r->staging.mapped));
    return JNI_TRUE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_opencapture_openpocketcine_feed_OpcVulkan_nativeProbe(JNIEnv*, jclass) {
    uint32_t n = 0;
    return vkEnumerateInstanceExtensionProperties(nullptr, &n, nullptr) == VK_SUCCESS ? JNI_TRUE : JNI_FALSE;
}
