#version 100

// Pass 2 of 3 of focus peaking: the HORIZONTAL half of the re-blur, the operator, and the
// ramps — evaluated ONCE PER SOURCE PIXEL into an offscreen mask.
// R = the painted stroke's opacity, G = the dark hairline's.
//
// The vertical half already ran in `peaking_blur_fragment_es2.glsl`, which is why this
// reads 8 texels instead of walking a 64-tap neighbourhood. The algebra of that split,
// once, because it is the reason two shaders exist:
//
//   the fused loop accumulated, per column dx,
//     vp0 = SUM over dy of w(dy)     * g(x+dx, y+dy)   -- blur centred on row y
//     vp1 = SUM over dy of w(dy - 1) * g(x+dx, y+dy)   -- blur centred on row y+1
//   then folded each into the four quad positions with the horizontal weights w(dx) and
//   w(dx-1). Those two sums depend on the COLUMN alone, so the blur pass computes them
//   per pixel and hands both over in one texel (xy and zw, 16 bits each). What is left
//   here is the horizontal fold, unchanged and exact — the same four `b**` values, from 8
//   reads rather than 64 taps.
//
// w(offset) is zero beyond |offset| >= 3.5, so vp1 at row y is identically the centred
// blur at row y+1; nothing is approximated by carrying it in the same texel.
//
// Split out of the composite shader for one reason. iOS closes the finished stroke
// (`Peaking.maskClosingRadius`), which rejoins the dashes a strict noise gate punches
// into edges that ARE sharp — measured, fragmentation 18.9% -> 1.6% at equal ink, and
// it is what makes the wide sensitivity ladder usable at all. Closing needs the mask at
// 13 neighbouring points (`Peaking.closingOffsets` is a five-point PLUS, so dilate then
// erode spans the |dx|+|dy| <= 2 diamond), and each of those points needs its own 8x8
// re-blur neighbourhood. Shared, that is a 12x12 grey grid and ~130 live floats against
// the ~25 one evaluation needs — a register-pressure cliff, not a tap-count problem, and
// a pass boundary in any renderer. Memoising the mask turns the closing into 13 cheap
// texture reads.
//
// It also moves the detector off the display grid. The composite pass runs per DISPLAY
// pixel; this runs per SOURCE pixel, which for a 1024x576 feed shown at 1920x1080 is
// about a third of the fragments — so two passes cost less than the one they replace.
//
// Every constant is from `Peaking` in shared core, where the derivation, the calibration
// tables and the measurements live. `Peaking.overlay` is the reference this transcribes,
// and `RunnerTests` checks that reference against the live iOS Core Image graph
// pixel-for-pixel, so the chain from here to what an iPhone renders is closed.

precision highp float;

uniform sampler2D uTexSampler;
// The vertical halves from pass 1, already on this pass's own grid — sampled straight,
// with no flip: `uFlipInputY` belongs to reads of the SOURCE, and pass 1 has applied it.
uniform sampler2D uPeakingBlur;
uniform float uFlipInputY;
uniform vec2 uSourceSize;
uniform float uPeakingRatioThreshold;
uniform float uPeakingNoiseGate;

varying vec2 vTexSamplingCoord;

const float PEAKING_EDGE_INSET = 6.0;
const float PEAKING_W0 = 0.382992;
const float PEAKING_W1 = 0.241798;
const float PEAKING_W2 = 0.060662;
const float PEAKING_W3 = 0.006044;
const float PEAKING_RATIO_CEILING = 4.0;
const float PEAKING_AA = 0.12;
const float PEAKING_UNDER_OFFSET = 0.5;
const float PEAKING_GATE_FLOOR = 0.7;

vec3 sampleSource(vec2 coordinate) {
    float y = mix(coordinate.y, 1.0 - coordinate.y, uFlipInputY);
    return texture2D(uTexSampler, vec2(coordinate.x, y)).rgb;
}

// Focus peaking measures BLUR RADIUS, not edge contrast. A gradient magnitude scales
// with amplitude as much as with focus, so a bright defocused highlight rim outranks
// genuinely sharp low-contrast detail. Running the operator on the source and again on a
// re-blurred copy, then dividing, cancels amplitude exactly and leaves a number that
// depends only on how blurred the edge is. Measured on the RAW source.
float sourceGrey(vec2 coordinate) {
    vec3 color = sampleSource(coordinate);
    return (color.r + color.g + color.b) / 3.0;
}

// Weight of a tap `offset` pixels from the centre of the separable re-blur, zero beyond
// its reach. MEASURED off `CIGaussianBlur(radius: 1.0)` by impulse response — see
// `Peaking.reblurWeights`; it is near but not equal to a sigma-1.04 Gaussian, which is
// why the weights are measured and not derived. A function rather than an indexed array
// so the kernel needs no local array at all.
float peakingTapWeight(float offset) {
    float d = abs(offset);
    return d < 0.5 ? PEAKING_W0
        : d < 1.5 ? PEAKING_W1
        : d < 2.5 ? PEAKING_W2
        : d < 3.5 ? PEAKING_W3
        : 0.0;
}

// Inverse of `pack16` in the blur pass: the high byte plus the low byte's 1/255 share.
// NB `packed` is a reserved word in GLSL ES 1.00, so the pair cannot be named that.
float unpack16(vec2 pair) {
    return pair.x + pair.y / 255.0;
}

// The operator: a squared Roberts cross over the 2x2 quad anchored at the pixel,
// reproducing `CIEdges`. SQUARED — a 0.2 step gives 0.08, a 0.4 step 0.32 — which is the
// domain every threshold in `Peaking` lives in.
float peakingRoberts(float a, float b, float c, float d) {
    float d1 = d - a;
    float d2 = c - b;
    return d1 * d1 + d2 * d2;
}

void main() {
    vec2 sourceSize = max(uSourceSize, vec2(1.0));
    vec2 inset = vec2(PEAKING_EDGE_INSET) / sourceSize;
    if (
        vTexSamplingCoord.x < inset.x
        || vTexSamplingCoord.y < inset.y
        || vTexSamplingCoord.x >= 1.0 - inset.x
        || vTexSamplingCoord.y >= 1.0 - inset.y
    ) {
        // The border the kernels would sample outside of. Zero here is load-bearing: the
        // closing pass erodes against it, so the overlay stops exactly at the inset.
        gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    // This pass is already one fragment per source pixel, so the snap is an identity —
    // kept so the taps are provably on texel centres whatever the caller sizes us at.
    vec2 texel = 1.0 / sourceSize;
    vec2 centre = (floor(vTexSamplingCoord * sourceSize) + 0.5) * texel;

    // The horizontal fold. Columns -3..+4 are what the two horizontal weights between them
    // reach, and each read already carries both of the quad's rows, so the four `b**` come
    // out of 8 texels. Same values as the fused 8x8 loop, a third of the bandwidth.
    float b00 = 0.0;
    float b10 = 0.0;
    float b01 = 0.0;
    float b11 = 0.0;
    for (int col = 0; col < 8; col++) {
        float dx = float(col) - 3.0;
        vec4 rows = texture2D(uPeakingBlur, centre + vec2(dx, 0.0) * texel);
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
    // Noise is not lens-blurred, so it always reads as perfectly sharp; the ratio cannot
    // reject it and this gate is what keeps shadows from sparkling. It arrives already
    // scaled for the feed's encoding, so there is no mode policy here.
    float gate = clamp(
        (coarse - uPeakingNoiseGate * PEAKING_GATE_FLOOR)
            / max(uPeakingNoiseGate * (1.0 - PEAKING_GATE_FLOOR), 1e-9),
        0.0,
        1.0
    );
    // LINEAR ramps, deliberately not smoothstep: Core Image reaches these with a
    // scale-and-clamp pair, and on a ramp this narrow the Hermite curve is a visible
    // difference in stroke weight rather than a rounding one.
    float stroke = clamp((ratio - uPeakingRatioThreshold) / PEAKING_AA, 0.0, 1.0) * gate;
    float under = clamp(
        (ratio - (uPeakingRatioThreshold - PEAKING_AA * PEAKING_UNDER_OFFSET)) / PEAKING_AA,
        0.0,
        1.0
    ) * gate;

    gl_FragColor = vec4(stroke, under, 0.0, 1.0);
}
