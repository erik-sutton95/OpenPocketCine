cmake_minimum_required(VERSION 3.22)
project(opc_vulkan LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT ANDROID_NDK)
  message(FATAL_ERROR "ANDROID_NDK is required")
endif()

if(NOT DEFINED ANDROID_NDK_HOST_SYSTEM_NAME)
  if(APPLE)
    set(ANDROID_NDK_HOST_SYSTEM_NAME darwin-x86_64)
  elseif(UNIX)
    set(ANDROID_NDK_HOST_SYSTEM_NAME linux-x86_64)
  else()
    set(ANDROID_NDK_HOST_SYSTEM_NAME windows-x86_64)
  endif()
endif()

find_program(GLSLC glslc
  HINTS
    "${ANDROID_NDK}/shader-tools/${ANDROID_NDK_HOST_SYSTEM_NAME}"
    "${ANDROID_NDK}/shader-tools/darwin-x86_64"
    "${ANDROID_NDK}/shader-tools/darwin-arm64"
    "${ANDROID_NDK}/shader-tools/linux-x86_64"
    /opt/homebrew/bin
    /usr/local/bin
  REQUIRED)

macro(opc_embed_shader NAME STAGE SRC)
  set(spv "${CMAKE_CURRENT_BINARY_DIR}/spv/${NAME}.spv")
  set(hdr "${CMAKE_CURRENT_BINARY_DIR}/spv/${NAME}_spv.h")
  add_custom_command(
    OUTPUT "${hdr}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${CMAKE_CURRENT_BINARY_DIR}/spv"
    COMMAND "${GLSLC}" -fshader-stage=${STAGE} --target-env=vulkan1.1 -O
            "${CMAKE_CURRENT_SOURCE_DIR}/${SRC}" -o "${spv}"
    COMMAND "${CMAKE_COMMAND}"
            -Dspv=${spv} -Dhdr=${hdr} -Dsym=${NAME}_spv
            -P "${CMAKE_CURRENT_SOURCE_DIR}/embed_spv.cmake"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/${SRC}"
            "${CMAKE_CURRENT_SOURCE_DIR}/embed_spv.cmake"
    VERBATIM)
  list(APPEND OPC_SPV_HEADERS "${hdr}")
endmacro()

set(OPC_SPV_HEADERS "")
opc_embed_shader(fullscreen_vert vertex shaders/fullscreen.vert)
opc_embed_shader(feed_frag fragment shaders/feed.frag)
opc_embed_shader(blit_frag fragment shaders/blit.frag)
opc_embed_shader(kawase_frag fragment shaders/kawase.frag)
opc_embed_shader(glass_vert vertex shaders/glass.vert)
opc_embed_shader(glass_frag fragment shaders/glass.frag)
opc_embed_shader(scope_vert vertex shaders/scope.vert)
opc_embed_shader(scope_frag fragment shaders/scope.frag)
opc_embed_shader(vector_vert vertex shaders/vector.vert)
opc_embed_shader(vector_frag fragment shaders/vector.frag)
opc_embed_shader(histo_comp compute shaders/histo.comp)
opc_embed_shader(histo_remap_comp compute shaders/histo_remap.comp)
opc_embed_shader(histo_plot_frag fragment shaders/histo_plot.frag)

add_library(opc_vulkan SHARED
  opc_vulkan.cpp
  ${OPC_SPV_HEADERS})

target_include_directories(opc_vulkan PRIVATE
  "${CMAKE_CURRENT_BINARY_DIR}/spv")

target_compile_definitions(opc_vulkan PRIVATE
  VK_USE_PLATFORM_ANDROID_KHR
  VULKAN_HPP_NO_EXCEPTIONS)

find_library(VULKAN_LIB vulkan)
target_link_libraries(opc_vulkan
  android
  log
  nativewindow
  ${VULKAN_LIB})
