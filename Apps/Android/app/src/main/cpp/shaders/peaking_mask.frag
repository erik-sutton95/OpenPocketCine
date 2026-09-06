#version 450
// Pass 2 of 3: horizontal re-blur fold, Roberts ratio, ramps.
// Transcribed from peaking_mask_fragment_es2.glsl / Peaking.overlay.
// R = stroke opacity, G = hairline opacity.
layout(location = 0) in vec2 vUv;
layout(location = 0) out vec4 oColor;
layout(set = 0, binding = 0) uniform sampler2D uFeed;
layout(set = 0, binding = 1) uniform sampler2D uPeakingBlur;
layout(push_constant) uniform PC {
    vec2 sourceSize;
    float ratioThreshold;
    float noiseGate;
} pc;

const float PEAKING_EDGE_INSET = 6.0;
const float PEAKING_W0 = 0.382992;
const float PEAKING_W1 = 0.241798;
const float PEAKING_W2 = 0.060662;
const float PEAKING_W3 = 0.006044;
const float PEAKING_RATIO_CEILING = 4.0;
const float PEAKING_AA = 0.12;
const float PEAKING_UNDER_OFFSET = 0.5;
const float PEAKING_GATE_FLOOR = 0.7;

float sourceGrey(vec2 coordinate) {
    vec3 color = texture(uFeed, coordinate).rgb;
    return (color.r + color.g + color.b) / 3.0;
}

float peakingTapWeight(float offset) {
    float d = abs(offset);
    return d < 0.5 ? PEAKING_W0
        : d < 1.5 ? PEAKING_W1
        : d < 2.5 ? PEAKING_W2
        : d < 3.5 ? PEAKING_W3
        : 0.0;
}

float unpack16(vec2 pair) {
    return pair.x + pair.y / 255.0;
}

float peakingRoberts(float a, float b, float c, float d) {
    float d1 = d - a;
    float d2 = c - b;
    return d1 * d1 + d2 * d2;
}

void main() {
    vec2 sourceSize = max(pc.sourceSize, vec2(1.0));
    vec2 inset = vec2(PEAKING_EDGE_INSET) / sourceSize;
    if (vUv.x < inset.x || vUv.y < inset.y || vUv.x >= 1.0 - inset.x || vUv.y >= 1.0 - inset.y) {
        oColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }
    vec2 texel = 1.0 / sourceSize;
    vec2 centre = (floor(vUv * sourceSize) + 0.5) * texel;
    float b00 = 0.0;
    float b10 = 0.0;
    float b01 = 0.0;
    float b11 = 0.0;
    for (int col = 0; col < 8; col++) {
        float dx = float(col) - 3.0;
        vec4 rows = texture(uPeakingBlur, centre + vec2(dx, 0.0) * texel);
        float vp0 = unpack16(rows.xy);
        float vp1 = unpack16(rows.zw);
        float wx0 = peakingTapWeight(dx);
        float wx1 = peakingTapWeight(dx - 1.0);
        b00 += wx0 * vp0;
        b10 += wx1 * vp0;
        b01 += wx0 * vp1;
        b11 += wx1 * vp1;
    }
    float coarse = peakingRoberts(b00, b10, b01, b11);
    float fine = peakingRoberts(
        sourceGrey(centre),
        sourceGrey(centre + vec2(1.0, 0.0) * texel),
        sourceGrey(centre + vec2(0.0, 1.0) * texel),
        sourceGrey(centre + vec2(1.0, 1.0) * texel)
    );
    float ratio = min(fine / max(coarse, 1e-9), PEAKING_RATIO_CEILING);
    float gate = clamp(
        (coarse - pc.noiseGate * PEAKING_GATE_FLOOR)
            / max(pc.noiseGate * (1.0 - PEAKING_GATE_FLOOR), 1e-9),
        0.0,
        1.0
    );
    float stroke = clamp((ratio - pc.ratioThreshold) / PEAKING_AA, 0.0, 1.0) * gate;
    float under = clamp(
        (ratio - (pc.ratioThreshold - PEAKING_AA * PEAKING_UNDER_OFFSET)) / PEAKING_AA,
        0.0,
        1.0
    ) * gate;
    oColor = vec4(stroke, under, 0.0, 1.0);
}
