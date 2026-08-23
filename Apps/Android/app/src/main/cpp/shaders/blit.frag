#version 450
layout(location = 0) in vec2 vUv;
layout(location = 0) out vec4 oColor;
layout(set = 0, binding = 0) uniform sampler2D uTex;
layout(push_constant) uniform PC {
    float opacity;
    float uvMode; // 0 identity, 1 rot 90 CW, 2 rot 90 CCW
} pc;
void main() {
    vec2 uv = vUv;
    if (pc.uvMode > 1.5) uv = vec2(1.0 - vUv.y, vUv.x);
    else if (pc.uvMode > 0.5) uv = vec2(vUv.y, 1.0 - vUv.x);
    oColor = texture(uTex, uv) * pc.opacity;
}
