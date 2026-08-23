#version 450
layout(location = 0) in vec2 vLocal;
layout(location = 1) in vec2 vScreen;
layout(location = 0) out vec4 oColor;

layout(set = 0, binding = 0) uniform sampler2D uBlur;
layout(set = 0, binding = 1) uniform sampler2D uGrab;

layout(push_constant) uniform PC {
    vec4 rect;
    vec2 overlay;
    float radius;
    float pad;
    vec4 tint;
    vec4 feedRect;
} pc;

float sdRoundBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main() {
    vec2 halfSize = pc.rect.zw * 0.5;
    vec2 p = (vLocal - 0.5) * pc.rect.zw;
    float rad = min(pc.radius, min(halfSize.x, halfSize.y));
    float sd = sdRoundBox(p, halfSize, rad);
    float aa = 1.0 - smoothstep(-1.0, 0.6, sd);
    if (aa <= 0.0) discard;

    // pad > 0.5: iOS ScopeMiniChrome panelFill — 72% rounded plate, no kawase.
    if (pc.pad > 0.5) {
        oColor = vec4(pc.tint.rgb, pc.tint.a * aa);
        return;
    }

    // Light refraction only on the rim — iOS liquidGlass lens, not a 12px white halo.
    float edge = 1.0 - smoothstep(-8.0, 0.0, sd);
    vec2 grad = vec2(dFdx(sd), dFdy(sd));
    vec2 n = grad / max(length(grad), 1e-5);
    vec2 samplePx = vScreen + n * edge * 8.0;

    vec2 grabUv = (samplePx - pc.feedRect.xy) / max(pc.feedRect.zw, vec2(1.0));
    bool inside = grabUv.x >= 0.0 && grabUv.x <= 1.0 && grabUv.y >= 0.0 && grabUv.y <= 1.0;
    vec3 frost = inside ? texture(uBlur, grabUv).rgb : vec3(0.04);
    vec3 sharp = inside ? texture(uGrab, grabUv).rgb : vec3(0.04);
    vec3 scene = mix(frost, sharp, 0.06);
    // Highlights in the feed must not bleach the HUD (iOS chromePlate 52% black
    // sits *behind* liquidGlass). Crush the grab, then lay the dark plate + titan.
    scene *= 0.20;
    float plateA = clamp(pc.tint.a, 0.55, 0.88);
    vec3 plate = mix(scene, pc.tint.rgb, plateA);
    plate = mix(plate, vec3(0.369, 0.384, 0.384), 0.16);

    float rim = pow(1.0 - smoothstep(-2.2, 0.4, sd), 2.0) * 0.12;
    plate += vec3(rim);
    oColor = vec4(plate, aa * 0.90);
}
