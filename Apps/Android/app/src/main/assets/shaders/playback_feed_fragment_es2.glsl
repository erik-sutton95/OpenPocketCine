#version 100

precision highp float;

uniform sampler2D uTexSampler;
uniform sampler2D uLut;
uniform sampler2D uLimitsPaintCube;
uniform sampler2D uLimitsWeightCube;
uniform float uFlipInputY;
// Horizontal flip for a camera pointed back at the operator: 1 mirrors, 0 does not. Folds the
// SAMPLING coordinate, so the picture and every effect read through it flip together.
uniform float uMirror;
uniform float uLutSize;
// 50/50 Log-vs-LUT comparison: 1 = on, and 1 = a vertical boundary (Log left, LUT right)
// against a horizontal one (Log top, LUT bottom). See `SplitComparison` in shared core.
uniform float uSplitOn;
uniform float uSplitVertical;
uniform float uLimitsPaintSize;
uniform float uLimitsWeightSize;
uniform float uLimitsOn;
uniform vec2 uSourceSize;
uniform vec2 uDisplaySize;

uniform float uPeakingOn;
uniform vec3 uPeakingColor;
// Pass 1's output: R = stroke opacity, G = the hairline's, at SOURCE resolution.
// The detector itself lives in `peaking_mask_fragment_es2.glsl`; see its header for why
// it is a separate pass and not an inline block here.
uniform sampler2D uPeakingMask;

uniform float uZebraHighlightOn;
uniform float uZebraHighlight;
uniform vec3 uZebraHighlightColor;
uniform float uZebraMidtoneOn;
uniform float uZebraMidtone;
uniform vec3 uZebraMidtoneColor;

varying vec2 vTexSamplingCoord;

const vec3 LUMA_709 = vec3(0.2126, 0.7152, 0.0722);
const float ATLAS_COLUMNS = 8.0;
// Focus peaking's hairline colour, from `Peaking.underColor`. Every other peaking
// constant belongs to the detector and lives with it, in the mask pass.
const vec3 PEAKING_UNDER_COLOR = vec3(0.04, 0.04, 0.05);
const float ZEBRA_GAIN = 40.0;
const float ZEBRA_HALF_WIDTH = 5.0 / 255.0;
const float STRIPE_PITCH = 14.14;

vec2 atlasCoordinate(float slice, vec2 redGreen, float cubeSize) {
    float tileX = mod(slice, ATLAS_COLUMNS);
    float tileY = floor(slice / ATLAS_COLUMNS);
    vec2 pixel = vec2(
        tileX * cubeSize + clamp(redGreen.x, 0.0, 1.0) * (cubeSize - 1.0) + 0.5,
        tileY * cubeSize + clamp(redGreen.y, 0.0, 1.0) * (cubeSize - 1.0) + 0.5
    );
    // GLUtils uploads Android bitmap row zero at v=0 for sampler coordinates.
    // Flipping here would address an unused atlas row instead of the selected
    // green row, which collapses the upper green axis to black on hardware.
    return pixel / (cubeSize * ATLAS_COLUMNS);
}

vec3 sampleLut(float cubeSize, vec3 color) {
    float blue = clamp(color.b, 0.0, 1.0) * (cubeSize - 1.0);
    float lowerSlice = floor(blue);
    float upperSlice = min(lowerSlice + 1.0, cubeSize - 1.0);
    vec3 lower = texture2D(
        uLut,
        atlasCoordinate(lowerSlice, color.rg, cubeSize)
    ).rgb;
    vec3 upper = texture2D(
        uLut,
        atlasCoordinate(upperSlice, color.rg, cubeSize)
    ).rgb;
    return mix(lower, upper, blue - lowerSlice);
}

vec3 grade(vec3 color) {
    if (uLutSize < 2.0) {
        return color;
    }
    return sampleLut(uLutSize, color);
}

vec3 sampleSource(vec2 coordinate) {
    float y = mix(coordinate.y, 1.0 - coordinate.y, uFlipInputY);
    return texture2D(uTexSampler, vec2(coordinate.x, y)).rgb;
}

// One bilinear fetch in source-pixel space, for the reconstruction below.
vec3 sampleSourceAt(vec2 pixel, vec2 sourceSize) {
    return sampleSource(pixel / sourceSize);
}

// Catmull-Rom reconstruction of the live-view frame, used only where the feed is MAGNIFIED.
//
// The camera bounds the frame at XGA, so on a panel taller than the frame every displayed pixel
// is an interpolation. GL_LINEAR reconstructs that with a 2x2 tent, which is what makes an
// upscaled feed look soft. Catmull-Rom is an interpolating cubic — it passes exactly through the
// source samples and carries a mild sharpening lobe — so edges resolve instead of ramping.
//
// This is the Android tier of the iOS present-time upscale, which runs MetalFX Spatial over an
// MPS Lanczos fallback. MetalFX has no Android equivalent; Catmull-Rom is the portable
// Lanczos-class filter, and unlike Lanczos-3 it fits the GLES2 floor device.
//
// Nine taps, not sixteen: each axis' inner pair is fetched as one bilinear sample placed at the
// pair's weighted centroid, which is exact for a separable filter and cuts the fetch count.
vec3 sampleSourceReconstructed(vec2 coordinate, vec2 sourceSize) {
    vec2 samplePosition = coordinate * sourceSize;
    vec2 centre = floor(samplePosition - 0.5) + 0.5;
    vec2 f = samplePosition - centre;

    // Catmull-Rom basis. These sum to exactly 1 for every f, so flat areas cannot shift level.
    vec2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
    vec2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
    vec2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
    vec2 w3 = f * f * (-0.5 + 0.5 * f);

    // The inner pair, collapsed to one bilinear fetch at its centroid. w1 + w2 is bounded away
    // from zero across the whole cell, so this division is safe.
    vec2 w12 = w1 + w2;
    vec2 centre12 = centre + w2 / w12;
    vec2 centre0 = centre - 1.0;
    vec2 centre3 = centre + 2.0;

    vec3 row0 = sampleSourceAt(vec2(centre0.x, centre0.y), sourceSize) * w0.x
        + sampleSourceAt(vec2(centre12.x, centre0.y), sourceSize) * w12.x
        + sampleSourceAt(vec2(centre3.x, centre0.y), sourceSize) * w3.x;
    vec3 row12 = sampleSourceAt(vec2(centre0.x, centre12.y), sourceSize) * w0.x
        + sampleSourceAt(vec2(centre12.x, centre12.y), sourceSize) * w12.x
        + sampleSourceAt(vec2(centre3.x, centre12.y), sourceSize) * w3.x;
    vec3 row3 = sampleSourceAt(vec2(centre0.x, centre3.y), sourceSize) * w0.x
        + sampleSourceAt(vec2(centre12.x, centre3.y), sourceSize) * w12.x
        + sampleSourceAt(vec2(centre3.x, centre3.y), sourceSize) * w3.x;

    vec3 reconstructed = row0 * w0.y + row12 * w12.y + row3 * w3.y;
    // The cubic overshoots at hard edges. Clamping the undershoot keeps a dark ring from going
    // negative and poisoning the luma the grade and scopes read downstream.
    return max(reconstructed, vec3(0.0));
}

// The displayed sample. Reconstruction is for magnification only: below 1:1 the feed is being
// minified, where an interpolating cubic is the wrong tool (it aliases without a prefilter) and
// GL_LINEAR is already correct. The A12-class 720p panel sits on this side of the gate, so the
// floor device pays nothing for this.
vec3 sampleSourceForDisplay(vec2 coordinate) {
    vec2 sourceSize = max(uSourceSize, vec2(1.0));
    if (uDisplaySize.x <= sourceSize.x && uDisplaySize.y <= sourceSize.y) {
        return sampleSource(coordinate);
    }
    return sampleSourceReconstructed(coordinate, sourceSize);
}

// Whether this fragment belongs to the graded half of a 50/50 comparison — always true when the
// comparison is off, so the LUT stays one predicate rather than two code paths. A branch inside an
// existing kernel is close to free; a second pass would not be.
//
// `vTexSamplingCoord` spans exactly the visible image rectangle: the caller sets the viewport to
// `liveFeedContentRect` before drawing, so 0.5 is the middle of the IMAGE and letterbox, pillarbox
// and chrome are all outside the quad entirely.
//
// Top/bottom uses the same display convention as the zebra block below — GL fragments count up, so
// the top of the display is `coordinate.y == 1`, not 0. NOT the `uFlipInputY` sampling fold: that
// one is about where a texel lives in the input texture, and the operator's "top" is where the
// pixel lands on screen.
bool splitIsGradedSide(vec2 coordinate) {
    if (uSplitOn < 0.5) {
        return true;
    }
    return uSplitVertical > 0.5 ? coordinate.x >= 0.5 : coordinate.y < 0.5;
}

vec3 limitsPaint(vec3 color) {
    if (uLimitsPaintSize < 2.0) {
        return color;
    }
    float blue = clamp(color.b, 0.0, 1.0) * (uLimitsPaintSize - 1.0);
    float lowerSlice = floor(blue);
    float upperSlice = min(lowerSlice + 1.0, uLimitsPaintSize - 1.0);
    vec3 lower = texture2D(
        uLimitsPaintCube,
        atlasCoordinate(lowerSlice, color.rg, uLimitsPaintSize)
    ).rgb;
    vec3 upper = texture2D(
        uLimitsPaintCube,
        atlasCoordinate(upperSlice, color.rg, uLimitsPaintSize)
    ).rgb;
    return mix(lower, upper, blue - lowerSlice);
}

float limitsWeight(vec3 color) {
    if (uLimitsWeightSize < 2.0) {
        return 0.0;
    }
    float blue = clamp(color.b, 0.0, 1.0) * (uLimitsWeightSize - 1.0);
    float lowerSlice = floor(blue);
    float upperSlice = min(lowerSlice + 1.0, uLimitsWeightSize - 1.0);
    float lower = texture2D(
        uLimitsWeightCube,
        atlasCoordinate(lowerSlice, color.rg, uLimitsWeightSize)
    ).r;
    float upper = texture2D(
        uLimitsWeightCube,
        atlasCoordinate(upperSlice, color.rg, uLimitsWeightSize)
    ).r;
    return clamp(mix(lower, upper, blue - lowerSlice), 0.0, 1.0);
}

// Morphological closing of the finished stroke, over the element `Peaking.closingOffsets`
// measures: `CIMorphologyMaximum` at radius 1 is a five-point PLUS, not the 3x3 square the
// filter name suggests. Dilate then erode therefore spans the |dx| + |dy| <= 2 diamond, so
// 13 distinct mask reads answer all 25 min-of-max terms.
//
// This is what rejoins the dashes a strict noise gate punches into edges that ARE sharp; a
// line broken into dashes reads as MORE noise than a continuous one even with less ink on
// screen, which is how a stricter setting can look worse. Closing and not opening: the
// strokes are about a pixel wide, so eroding first would delete them along with the specks.
float peakingClosedStroke(vec2 centre, vec2 texel) {
    float m00 = texture2D(uPeakingMask, centre).r;
    float mR = texture2D(uPeakingMask, centre + vec2(texel.x, 0.0)).r;
    float mL = texture2D(uPeakingMask, centre - vec2(texel.x, 0.0)).r;
    float mD = texture2D(uPeakingMask, centre + vec2(0.0, texel.y)).r;
    float mU = texture2D(uPeakingMask, centre - vec2(0.0, texel.y)).r;
    float mRR = texture2D(uPeakingMask, centre + vec2(2.0 * texel.x, 0.0)).r;
    float mLL = texture2D(uPeakingMask, centre - vec2(2.0 * texel.x, 0.0)).r;
    float mDD = texture2D(uPeakingMask, centre + vec2(0.0, 2.0 * texel.y)).r;
    float mUU = texture2D(uPeakingMask, centre - vec2(0.0, 2.0 * texel.y)).r;
    float mRD = texture2D(uPeakingMask, centre + vec2(texel.x, texel.y)).r;
    float mRU = texture2D(uPeakingMask, centre + vec2(texel.x, -texel.y)).r;
    float mLD = texture2D(uPeakingMask, centre + vec2(-texel.x, texel.y)).r;
    float mLU = texture2D(uPeakingMask, centre + vec2(-texel.x, -texel.y)).r;

    // Dilation at each of the element's five offsets...
    float dC = max(max(max(m00, mR), max(mL, mD)), mU);
    float dR = max(max(max(mR, mRR), max(m00, mRD)), mRU);
    float dL = max(max(max(mL, m00), max(mLL, mLD)), mLU);
    float dD = max(max(max(mD, mRD), max(mLD, mDD)), m00);
    float dU = max(max(max(mU, mRU), max(mLU, m00)), mUU);
    // ...then erosion over the same element.
    return min(min(min(dC, dR), min(dL, dD)), dU);
}

void main() {
    // `source` stays the raw fetch: zebra, false colour and the limits paint MEASURE it, and a
    // measurement must describe the frame the camera sent, not a reconstruction of it. iOS keeps
    // the same separation by upscaling at present time, after the bake the scopes read.
    // Folded ONCE, here, and used for every read in SOURCE space — the picture and the peaking
    // mask alike. Folding inside `sampleSource` instead would flip the picture while the mask
    // stayed put, and the strokes would land on the wrong side of the frame.
    //
    // Display-space questions keep the raw coordinate: the split boundary is about where a pixel
    // lands for the operator, and the zebra stripe is screen geometry.
    vec2 sourceCoordinate = vec2(
        mix(vTexSamplingCoord.x, 1.0 - vTexSamplingCoord.x, uMirror),
        vTexSamplingCoord.y
    );
    vec3 source = sampleSource(sourceCoordinate);
    vec3 displaySource = sampleSourceForDisplay(sourceCoordinate);
    vec3 color =
        splitIsGradedSide(vTexSamplingCoord) ? grade(displaySource) : displaySource;

    if (uLimitsOn > 0.5) {
        color = mix(color, limitsPaint(source), limitsWeight(source));
    }

    if (uPeakingOn > 0.5) {
        // Snap to the source pixel grid: the mask has one texel per source pixel, and the
        // closing's offsets are source pixels, so every read has to land on a texel centre.
        // Sampling from a fractional position would bilinear-blend four mask texels and
        // soften the very thing the closing exists to keep continuous.
        vec2 sourceSize = max(uSourceSize, vec2(1.0));
        vec2 texel = 1.0 / sourceSize;
        vec2 centre = (floor(sourceCoordinate * sourceSize) + 0.5) * texel;
        float stroke = peakingClosedStroke(centre, texel);
        // The hairline is NOT closed, matching iOS: morphology is two more passes, and a
        // hairline drawn under the stroke gains almost nothing from being continuous.
        float under = texture2D(uPeakingMask, centre).g;
        // Hairline first at its full ramp opacity, then the stroke over the top of it —
        // `ImageEffectsCompositor.composite`'s two blends, in that order. The hairline is
        // what stops a bright stroke from vanishing into a bright subject.
        color = mix(color, PEAKING_UNDER_COLOR, under);
        color = mix(color, uPeakingColor, stroke);
    }

    if (uZebraHighlightOn > 0.5 || uZebraMidtoneOn > 0.5) {
        float luma = dot(source, LUMA_709);
        // Match Android/Skia's top-down display coordinates even though GL fragments count up.
        vec2 displayCoordinate = vec2(
            vTexSamplingCoord.x * uDisplaySize.x,
            (1.0 - vTexSamplingCoord.y) * uDisplaySize.y
        );
        float stripe = step(
            0.5,
            fract((displayCoordinate.x + displayCoordinate.y) / STRIPE_PITCH)
        );
        if (uZebraHighlightOn > 0.5) {
            float highlightMask = clamp(
                (luma - uZebraHighlight) * ZEBRA_GAIN,
                0.0,
                1.0
            );
            color = mix(color, uZebraHighlightColor, highlightMask * stripe);
        }
        if (uZebraMidtoneOn > 0.5) {
            float midtoneMask =
                clamp(
                    (luma - (uZebraMidtone - ZEBRA_HALF_WIDTH)) * ZEBRA_GAIN,
                    0.0,
                    1.0
                )
                * clamp(
                    ((uZebraMidtone + ZEBRA_HALF_WIDTH) - luma) * ZEBRA_GAIN,
                    0.0,
                    1.0
                );
            color = mix(color, uZebraMidtoneColor, midtoneMask * stripe);
        }
    }

    gl_FragColor = vec4(color, 1.0);
}
