#version 450
// Pass 1 of 3: vertical half of the separable re-blur, once per source pixel.
// Transcribed from peaking_blur_fragment_es2.glsl / Peaking.reblurWeights.
// xy = blur at this row, zw = blur at the row below, each packed 16-bit.
layout(location = 0) in vec2 vUv;
layout(location = 0) out vec4 oColor;
layout(set = 0, binding = 0) uniform sampler2D uFeed;
layout(push_constant) uniform PC {
    vec2 sourceSize;
} pc;

const float PEAKING_W0 = 0.382992;
const float PEAKING_W1 = 0.241798;
const float PEAKING_W2 = 0.060662;
const float PEAKING_W3 = 0.006044;

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

vec2 pack16(float value) {
    float scaled = clamp(value, 0.0, 1.0) * 255.0;
    float high = floor(scaled);
    return vec2(high, (scaled - high) * 255.0) / 255.0;
}

void main() {
    vec2 sourceSize = max(pc.sourceSize, vec2(1.0));
    vec2 texel = 1.0 / sourceSize;
    vec2 centre = (floor(vUv * sourceSize) + 0.5) * texel;
    float blurAtRow = 0.0;
    float blurAtRowBelow = 0.0;
    for (int row = 0; row < 8; row++) {
        float dy = float(row) - 3.0;
        float g = sourceGrey(centre + vec2(0.0, dy) * texel);
        blurAtRow += peakingTapWeight(dy) * g;
        blurAtRowBelow += peakingTapWeight(dy - 1.0) * g;
    }
    oColor = vec4(pack16(blurAtRow), pack16(blurAtRowBelow));
}
