#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
ndk_root="${ANDROID_NDK_HOME:-$sdk_root/ndk/28.2.13676358}"
vulkan_headers=""
for candidate in "$ndk_root"/toolchains/llvm/prebuilt/*/sysroot/usr/include; do
    if [[ -f "$candidate/vulkan/vulkan.h" ]]; then
        vulkan_headers="$candidate"
        break
    fi
done
if [[ -z "$vulkan_headers" ]]; then
    printf 'Android NDK Vulkan headers missing; set ANDROID_HOME or ANDROID_NDK_HOME.\n' >&2
    exit 1
fi
scratch="$(mktemp -d "${TMPDIR:-/tmp}/opc-vulkan-sync.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
# Use the host C/C++ standard library, falling back to NDK only for Vulkan
# declarations. This is a CPU regression, not an Android emulator/GPU test.
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Wno-missing-field-initializers \
    -idirafter "$vulkan_headers" \
    -I "$repo_root/Apps/Android/app/src/main/cpp" \
    "$repo_root/Tests/AndroidNative/VulkanPresentBatchTests.cpp" \
    -o "$scratch/present-sync-test"
"$scratch/present-sync-test"
printf 'Vulkan present synchronization regression passed.\n'
