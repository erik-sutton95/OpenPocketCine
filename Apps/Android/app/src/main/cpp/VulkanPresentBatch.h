#pragma once

#include <vulkan/vulkan.h>

// Own pointer storage until both Vulkan calls return. Binary render-finished
// semaphores belong to swapchain images, not to the CPU frame/fence slot.
struct VulkanPresentBatch {
    VkCommandBuffer command;
    VkSwapchainKHR swapchain;
    uint32_t imageIndex;
    VkSemaphore renderFinished;
    VkSubmitInfo submit{VK_STRUCTURE_TYPE_SUBMIT_INFO};
    VkPresentInfoKHR present{VK_STRUCTURE_TYPE_PRESENT_INFO_KHR};

    VulkanPresentBatch(VkCommandBuffer command, VkSwapchainKHR swapchain,
                       uint32_t imageIndex, VkSemaphore renderFinished)
        : command(command), swapchain(swapchain), imageIndex(imageIndex), renderFinished(renderFinished) {
        submit.commandBufferCount = 1;
        submit.pCommandBuffers = &this->command;
        submit.signalSemaphoreCount = 1;
        submit.pSignalSemaphores = &this->renderFinished;
        present.waitSemaphoreCount = 1;
        present.pWaitSemaphores = &this->renderFinished;
        present.swapchainCount = 1;
        present.pSwapchains = &this->swapchain;
        present.pImageIndices = &this->imageIndex;
    }
    VulkanPresentBatch(const VulkanPresentBatch&) = delete;
    VulkanPresentBatch& operator=(const VulkanPresentBatch&) = delete;
};

// A successful WSI acquisition may signal after vkAcquireNextImageKHR returns.
// Device queue idle does not establish ownership of that acquisition fence.
struct VulkanAcquireLifetime {
    bool pending = false;

    void acquired() { pending = true; }
    void signaled() { pending = false; }

    template <class Wait>
    bool prepareToRetire(Wait wait) {
        if (!pending) return true;
        if (!wait()) return false;
        pending = false;
        return true;
    }
};
