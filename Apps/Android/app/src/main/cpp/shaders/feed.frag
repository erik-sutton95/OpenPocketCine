#version 450
layout(location = 0) in vec2 vUv;
layout(location = 0) out vec4 oColor;

layout(set = 0, binding = 0) uniform sampler2D uFeed;
layout(set = 0, binding = 1) uniform sampler2D uLut;
layout(set = 0, binding = 2) uniform sampler2D uLimitsPaint;
layout(set = 0, binding = 3) uniform sampler2D uLimitsWeight;

layout(push_constant) uniform PC {
    vec2 sourceSize;
    vec2 displaySize;
    float lutSize;
    float limitsPaintSize;
    float limitsWeightSize;
    float limitsOn;
    float splitOn;
    float splitVertical;
    float zebraHighlightOn;
    float zebraHighlight;
    float zebraMidtoneOn;
    float zebraMidtone;
    float zebraMidtoneHalf;
    float feedUpscale;
    float mirror;
    vec3 zebraHighlightColor;
    vec3 zebraMidtoneColor;
} pc;

const vec3 LUMA_709 = vec3(0.2126, 0.7152, 0.0722);
const float ATLAS_COLUMNS = 8.0;
const float ZEBRA_GAIN = 40.0;
const float STRIPE_PITCH = 14.14;

vec2 atlasCoordinate(float slice, vec2 redGreen, float cubeSize) {
    float tileX = mod(slice, ATLAS_COLUMNS);
    float tileY = floor(slice / ATLAS_COLUMNS);
    vec2 pixel = vec2(
        tileX * cubeSize + clamp(redGreen.x, 0.0, 1.0) * (cubeSize - 1.0) + 0.5,
        tileY * cubeSize + clamp(redGreen.y, 0.0, 1.0) * (cubeSize - 1.0) + 0.5);
    return pixel / (cubeSize * ATLAS_COLUMNS);
}

vec3 sampleLut(sampler2D cube, float cubeSize, vec3 color) {
    if (cubeSize < 2.0) return color;
    float blue = clamp(color.b, 0.0, 1.0) * (cubeSize - 1.0);
    float lowerSlice = floor(blue);
    float upperSlice = min(lowerSlice + 1.0, cubeSize - 1.0);
    vec3 lower = texture(cube, atlasCoordinate(lowerSlice, color.rg, cubeSize)).rgb;
    vec3 upper = texture(cube, atlasCoordinate(upperSlice, color.rg, cubeSize)).rgb;
    return mix(lower, upper, blue - lowerSlice);
}

vec3 sampleSource(vec2 uv) {
    return texture(uFeed, vec2(mix(uv.x, 1.0 - uv.x, pc.mirror), uv.y)).rgb;
}

vec3 sampleSourceAt(vec2 pixel, vec2 sourceSize) {
    return sampleSource(pixel / sourceSize);
}

vec3 sampleSourceReconstructed(vec2 coordinate, vec2 sourceSize) {
    vec2 samplePosition = coordinate * sourceSize;
    vec2 centre = floor(samplePosition - 0.5) + 0.5;
    vec2 f = samplePosition - centre;
    vec2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
    vec2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
    vec2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
    vec2 w3 = f * f * (-0.5 + 0.5 * f);
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
    return clamp(row0 * w0.y + row12 * w12.y + row3 * w3.y, 0.0, 1.0);
}

void main() {
    vec2 uv = vUv;
    vec3 source = sampleSource(uv);
    vec3 displaySource = pc.feedUpscale > 0.5
        ? sampleSourceReconstructed(uv, max(pc.sourceSize, vec2(1.0)))
        : source;
    bool graded = pc.splitOn < 0.5
        || (pc.splitVertical > 0.5 ? uv.x >= 0.5 : uv.y < 0.5);
    vec3 color = graded ? sampleLut(uLut, pc.lutSize, displaySource) : displaySource;
    if (pc.limitsOn > 0.5) {
        vec3 paint = sampleLut(uLimitsPaint, pc.limitsPaintSize, source);
        float weight = sampleLut(uLimitsWeight, pc.limitsWeightSize, source).r;
        color = mix(color, paint, clamp(weight, 0.0, 1.0));
    }
    if (pc.zebraHighlightOn > 0.5 || pc.zebraMidtoneOn > 0.5) {
        float luma = dot(source, LUMA_709);
        vec2 displayCoordinate = vec2(uv.x * pc.displaySize.x, (1.0 - uv.y) * pc.displaySize.y);
        float stripe = step(0.5, fract((displayCoordinate.x + displayCoordinate.y) / STRIPE_PITCH));
        if (pc.zebraHighlightOn > 0.5) {
            float highlightMask = clamp((luma - pc.zebraHighlight) * ZEBRA_GAIN + 1.0, 0.0, 1.0);
            color = mix(color, pc.zebraHighlightColor, highlightMask * stripe);
        }
        if (pc.zebraMidtoneOn > 0.5) {
            float halfWidth = max(pc.zebraMidtoneHalf, 1e-6);
            float midtoneMask =
                clamp((luma - (pc.zebraMidtone - halfWidth)) * ZEBRA_GAIN + 1.0, 0.0, 1.0)
                * clamp(((pc.zebraMidtone + halfWidth) - luma) * ZEBRA_GAIN + 1.0, 0.0, 1.0);
            color = mix(color, pc.zebraMidtoneColor, midtoneMask * stripe);
        }
    }
    oColor = vec4(color, 1.0);
}
