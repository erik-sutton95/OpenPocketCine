#version 450
layout(location = 0) out vec2 vLocal;
layout(location = 1) out vec2 vScreen;

layout(push_constant) uniform PC {
    vec4 rect;     // x, y, w, h in overlay pixels
    vec2 overlay;  // overlay size
    float radius;
    float pad;
    vec4 tint;
    vec4 feedRect; // x,y,w,h of the picture in overlay pixels
} pc;

void main() {
    vec2 corners[4] = vec2[](vec2(0, 0), vec2(1, 0), vec2(0, 1), vec2(1, 1));
    vec2 c = corners[gl_VertexIndex];
    vec2 px = pc.rect.xy + c * pc.rect.zw;
    // Vulkan NDC Y+ is down, same as window pixels. Do not invert or plates
    // land under the opposite chrome bar.
    vec2 ndc = vec2(px.x / pc.overlay.x, px.y / pc.overlay.y) * 2.0 - 1.0;
    gl_Position = vec4(ndc, 0.0, 1.0);
    vLocal = c;
    vScreen = px;
}
