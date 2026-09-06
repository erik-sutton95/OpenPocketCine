#version 450
layout(location = 0) out vec4 vColor;

layout(set = 0, binding = 0) uniform sampler2D uFeed;
layout(set = 0, binding = 1) uniform sampler3D uLut;

layout(push_constant) uniform PC {
    vec2 tapSize;
    int stride;
    float gain;
    float intensity;
    float lutSize;
    vec3 lumaW;
} pc;

vec3 mapLook(vec3 color) {
    if (pc.lutSize < 2.0) return color;
    vec3 coord = (clamp(color, 0.0, 1.0) * (pc.lutSize - 1.0) + 0.5) / pc.lutSize;
    return texture(uLut, coord).rgb;
}

void main() {
    int cols = max(int(pc.tapSize.x) / max(pc.stride, 1), 1);
    int id = int(gl_VertexIndex);
    int ix = (id % cols) * pc.stride;
    int iy = (id / cols) * pc.stride;
    if (ix >= int(pc.tapSize.x) || iy >= int(pc.tapSize.y)) {
        gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
        gl_PointSize = 1.0;
        vColor = vec4(0.0);
        return;
    }
    vec3 rgb = mapLook(texelFetch(uFeed, ivec2(ix, iy), 0).rgb);
    float y = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
    float cb = (rgb.b - y) / 1.8556;
    float cr = (rgb.r - y) / 1.5748;
    vec2 pos = vec2(cb, cr) * pc.gain + 0.5;
    vec2 ndc = pos * 2.0 - 1.0;
    ndc.y = -ndc.y;
    gl_Position = vec4(ndc, 0.0, 1.0);
    gl_PointSize = 1.0;
    float low = min(rgb.r, min(rgb.g, rgb.b));
    float high = max(rgb.r, max(rgb.g, rgb.b));
    float span = max(high - low, 1e-6);
    float sat = clamp(span / max(high, 1e-6), 0.0, 1.0);
    vec3 tint = mix(vec3(1.0), (rgb - low) / span, sat);
    vColor = vec4(tint * pc.intensity, pc.intensity);
}
