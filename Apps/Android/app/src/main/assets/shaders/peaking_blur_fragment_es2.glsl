#version 100

// Pass 1 of 3 of focus peaking: the VERTICAL half of the separable re-blur, once per
// source pixel. One texel carries both rows the operator's 2x2 quad needs —
// xy = the blur centred on this row, zw = the blur centred on the row below — each
// packed to 16 bits.
//
// Why this pass exists at all. The detector's re-blur is separable, but writing it fused
// costs a full 8x8 neighbourhood per pixel (64 taps) because the operator wants the
// blurred value at four positions, not one. Split, the vertical half is 8 taps here and
// the horizontal half is 8 reads in `peaking_mask_fragment_es2.glsl` — 20 taps against 68
// for an identical result. That is the difference between peaking running and not running
// on a floor device: a Mali-G52 at 1024x768 source needs ~2.7 GTexel/s for the fused form
// against roughly 1 available, which presents as a feed that flickers and stops updating.
//
// SPLIT, NOT APPROXIMATED. `Peaking.reblurWeights` sum to exactly 1, and the weight
// function is zero beyond |offset| >= 3.5, so the two vertical blurs this writes are the
// same `vp0`/`vp1` the fused loop accumulated — see the header of the mask pass for the
// algebra. No constant here is new; every one is transcribed from `Peaking` in shared core.
//
// 16-BIT PACKING IS LOAD-BEARING, not caution. The coarse operator takes DIFFERENCES of
// these blurred values, and a blurred field is smooth by construction, so the differences
// are small — an 8-bit intermediate quantises them at 1/255 and swamps the very gradient
// the ratio divides by. Packed, the error is ~1/65025 and lands far below the noise gate.
// A half-float target would be cleaner but throws on an ES2 context, and on the live
// surface that throw tears down the whole GPU path.

precision highp float;

uniform sampler2D uTexSampler;
uniform float uFlipInputY;
uniform vec2 uSourceSize;

varying vec2 vTexSamplingCoord;

const float PEAKING_W0 = 0.382992;
const float PEAKING_W1 = 0.241798;
const float PEAKING_W2 = 0.060662;
const float PEAKING_W3 = 0.006044;

vec3 sampleSource(vec2 coordinate) {
    float y = mix(coordinate.y, 1.0 - coordinate.y, uFlipInputY);
    return texture2D(uTexSampler, vec2(coordinate.x, y)).rgb;
}

// Measured on the RAW source, exactly as the fused detector was — see the mask pass.
float sourceGrey(vec2 coordinate) {
    vec3 color = sampleSource(coordinate);
    return (color.r + color.g + color.b) / 3.0;
}

// MEASURED off `CIGaussianBlur(radius: 1.0)` by impulse response (`Peaking.reblurWeights`);
// near but not equal to a sigma-1.04 Gaussian, which is why it is measured, not derived.
float peakingTapWeight(float offset) {
    float d = abs(offset);
    return d < 0.5 ? PEAKING_W0
        : d < 1.5 ? PEAKING_W1
        : d < 2.5 ? PEAKING_W2
        : d < 3.5 ? PEAKING_W3
        : 0.0;
}

// A weighted mean of greys in [0,1] over weights summing to 1, so the value is in [0,1]
// and needs no scaling before packing.
vec2 pack16(float value) {
    float scaled = clamp(value, 0.0, 1.0) * 255.0;
    float high = floor(scaled);
    return vec2(high, (scaled - high) * 255.0) / 255.0;
}

void main() {
    vec2 sourceSize = max(uSourceSize, vec2(1.0));
    vec2 texel = 1.0 / sourceSize;
    // Snap to the texel centre so each tap is provably one source pixel, whatever the
    // caller sizes this target at — the same snap the fused detector opened with.
    vec2 centre = (floor(vTexSamplingCoord * sourceSize) + 0.5) * texel;

    // Rows -3..+4 cover both blurs: the centred one reaches -3..+3, the shifted one -2..+4.
    float blurAtRow = 0.0;
    float blurAtRowBelow = 0.0;
    for (int row = 0; row < 8; row++) {
        float dy = float(row) - 3.0;
        float g = sourceGrey(centre + vec2(0.0, dy) * texel);
        blurAtRow += peakingTapWeight(dy) * g;
        blurAtRowBelow += peakingTapWeight(dy - 1.0) * g;
    }

    // No inset guard here. The mask pass still zeroes its own border at
    // PEAKING_EDGE_INSET, which is wider than the 4 rows this reaches, so every value it
    // actually consumes was computed from in-bounds taps and matches the fused result
    // exactly. Guarding here as well would only zero pixels the next pass discards.
    gl_FragColor = vec4(pack16(blurAtRow), pack16(blurAtRowBelow));
}
