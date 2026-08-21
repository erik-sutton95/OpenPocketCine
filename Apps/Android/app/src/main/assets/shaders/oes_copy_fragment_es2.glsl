#version 100
#extension GL_OES_EGL_image_external : require

precision highp float;

uniform samplerExternalOES uTexSampler;
uniform mat4 uTexMatrix;

varying vec2 vTexSamplingCoord;

void main() {
    vec2 uv = (uTexMatrix * vec4(vTexSamplingCoord, 0.0, 1.0)).xy;
    gl_FragColor = texture2D(uTexSampler, uv);
}
