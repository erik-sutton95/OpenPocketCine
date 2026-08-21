#version 100

attribute vec4 aFramePosition;
varying vec2 vTexSamplingCoord;

void main() {
    gl_Position = aFramePosition;
    vTexSamplingCoord = vec2(
        aFramePosition.x * 0.5 + 0.5,
        aFramePosition.y * 0.5 + 0.5
    );
}
