#include "VulkanPresentBatch.h"

#include <array>
#include <cassert>
#include <cstdint>
#include <type_traits>

int main() {
    const auto command = reinterpret_cast<VkCommandBuffer>(uintptr_t{0x10});
    const auto swapchain = reinterpret_cast<VkSwapchainKHR>(uintptr_t{0x20});
    const std::array<VkSemaphore, 3> finished = {
        reinterpret_cast<VkSemaphore>(uintptr_t{0x30}),
        reinterpret_cast<VkSemaphore>(uintptr_t{0x31}),
        reinterpret_cast<VkSemaphore>(uintptr_t{0x32}),
    };
    // The acquired image order can differ from frame order. The real batch
    // shared by identity and graded presentation must use that image's signal.
    for (const uint32_t image : {2u, 0u, 1u, 2u}) {
        VulkanPresentBatch batch(command, swapchain, image, finished[image]);
        assert(batch.submit.commandBufferCount == 1);
        assert(*batch.submit.pCommandBuffers == command);
        assert(batch.submit.signalSemaphoreCount == 1);
        assert(batch.submit.pSignalSemaphores != nullptr);
        assert(*batch.submit.pSignalSemaphores == finished[image]);
        assert(batch.present.waitSemaphoreCount == 1);
        assert(batch.present.pWaitSemaphores != nullptr);
        assert(*batch.present.pWaitSemaphores == *batch.submit.pSignalSemaphores);
        assert(batch.present.swapchainCount == 1);
        assert(*batch.present.pSwapchains == swapchain);
        assert(*batch.present.pImageIndices == image);
    }
    VulkanAcquireLifetime acquire;
    int waits = 0;
    assert(acquire.prepareToRetire([&] { ++waits; return false; }));
    assert(waits == 0);
    acquire.acquired();
    assert(!acquire.prepareToRetire([&] { ++waits; return false; }));
    assert(acquire.pending); // Timeout retains the WSI-owned fence and image.
    assert(waits == 1);
    assert(acquire.prepareToRetire([&] { ++waits; return true; }));
    assert(!acquire.pending);
    assert(waits == 2);
    assert(acquire.prepareToRetire([&] { ++waits; return false; }));
    assert(waits == 2);
    static_assert(!std::is_copy_constructible_v<VulkanPresentBatch>, "batch pointers must retain owned storage");
}
