#version 450
layout(location = 0) out vec4 vColor;

layout(set = 0, binding = 0) uniform sampler2D uFeed;
layout(std140, set = 0, binding = 1) uniform Ire {
    vec4 ire[64];
};

layout(push_constant) uniform PC {
    vec4 plot;      // minX, minY, width, height in panel pixels
    vec2 panel;     // panel pixel size
    vec2 tapSize;
    int stride;
    int channel;    // 0 luma 1 r 2 g 3 b
    int lane;       // parade lane index
    int laneCount;
    int kind;       // 0 wave 1 parade
    int hotEvery;
    float pointSize;
    float intensity;
    vec4 color;
    vec3 lumaW;
} pc;

float ireOf(int code) {
    int i = clamp(code, 0, 255);
    return ire[i >> 2][i & 3];
}

void main() {
    int cols = max(int(pc.tapSize.x) / max(pc.stride, 1), 1);
    int id = int(gl_VertexIndex);
    if (pc.hotEvery > 1 && (id % pc.hotEvery) != 0) {
        gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
        gl_PointSize = 1.0;
        vColor = vec4(0.0);
        return;
    }
    int ix = (id % cols) * pc.stride;
    int iy = (id / cols) * pc.stride;
    if (ix >= int(pc.tapSize.x) || iy >= int(pc.tapSize.y)) {
        gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
        gl_PointSize = 1.0;
        vColor = vec4(0.0);
        return;
    }
    vec3 rgb = texelFetch(uFeed, ivec2(ix, iy), 0).rgb;
    float luma = dot(rgb, pc.lumaW);
    float ch = luma;
    if (pc.channel == 1) ch = rgb.r;
    else if (pc.channel == 2) ch = rgb.g;
    else if (pc.channel == 3) ch = rgb.b;
    int code = int(clamp(ch * 255.0 + 0.5, 0.0, 255.0));
    float yIre = ireOf(code); // 0..100
    float xRatio = (float(ix) + 0.5) / max(pc.tapSize.x, 1.0);
    float px;
    if (pc.kind == 1) {
        float laneW = pc.plot.z / float(max(pc.laneCount, 1));
        float originX = pc.plot.x + float(pc.lane) * laneW;
        px = originX + xRatio * (laneW - 1.0);
    } else {
        px = pc.plot.x + xRatio * pc.plot.z;
    }
    float span = pc.plot.w - 2.0;
    float py = pc.plot.y + pc.plot.w - 1.0 - (yIre / 100.0) * span;
    vec2 ndc = vec2(px / pc.panel.x, py / pc.panel.y) * 2.0 - 1.0;
    gl_Position = vec4(ndc, 0.0, 1.0);
    gl_PointSize = max(pc.pointSize, 1.0);
    vColor = vec4(pc.color.rgb * pc.color.a * pc.intensity, pc.color.a * pc.intensity);
}
