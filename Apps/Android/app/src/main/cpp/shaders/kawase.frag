#version 450
layout(location = 0) in vec2 vUv;
layout(location = 0) out vec4 oColor;
layout(set = 0, binding = 0) uniform sampler2D uTex;
layout(push_constant) uniform PC {
    vec2 texel;
    float offset;
} pc;

void main() {
    vec2 o = pc.texel * pc.offset;
    vec3 c = texture(uTex, vUv + vec2( o.x,  o.y)).rgb;
    c += texture(uTex, vUv + vec2( o.x, -o.y)).rgb;
    c += texture(uTex, vUv + vec2(-o.x,  o.y)).rgb;
    c += texture(uTex, vUv + vec2(-o.x, -o.y)).rgb;
    oColor = vec4(c * 0.25, 1.0);
}
