#version 450
layout(location = 0) in vec2 vUv;
layout(location = 0) out vec4 oColor;

layout(std430, set = 0, binding = 0) readonly buffer Display {
    uint bins[1024];
};

layout(push_constant) uniform PC {
    int channel; // 0 luma 1 r 2 g 3 b
    int pad0;
    int pad1;
    int pad2;
    vec4 fill;
    vec4 stroke;
} pc;

void main() {
    float x = clamp(vUv.x, 0.0, 1.0);
    int i = int(x * 255.0);
    float peak = 1.0;
    // iOS HistogramScopePlot: one shared peak so RGBL heights stay comparable.
    for (int ch = 0; ch < 4; ++ch) {
        for (int b = 0; b < 256; ++b) peak = max(peak, float(bins[ch * 256 + b]));
    }
    int base = pc.channel * 256;
    float h = float(bins[base + i]) / peak;
    float y = 1.0 - vUv.y;
    if (y > h) discard;
    float edge = smoothstep(h - 0.02, h, y);
    oColor = mix(pc.fill, pc.stroke, edge);
}
