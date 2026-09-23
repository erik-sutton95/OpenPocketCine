#version 100
#extension GL_OES_EGL_image_external : require

precision highp float;

uniform samplerExternalOES uTexSampler;
uniform mat4 uTexMatrix;
// Zero: one bilinear fetch. Otherwise four fetches at +/- this destination offset,
// averaged, so a 1.5x+ downsample into the working raster does not alias.
uniform vec2 uSpread;

varying vec2 vTexSamplingCoord;

vec4 fetch(vec2 coordinate) {
    return texture2D(uTexSampler, (uTexMatrix * vec4(coordinate, 0.0, 1.0)).xy);
}

void main() {
    if (uSpread.x > 0.0) {
        gl_FragColor = 0.25 * (
            fetch(vTexSamplingCoord + vec2(-uSpread.x, -uSpread.y)) +
            fetch(vTexSamplingCoord + vec2(uSpread.x, -uSpread.y)) +
            fetch(vTexSamplingCoord + vec2(-uSpread.x, uSpread.y)) +
            fetch(vTexSamplingCoord + vec2(uSpread.x, uSpread.y))
        );
    } else {
        gl_FragColor = fetch(vTexSamplingCoord);
    }
}
