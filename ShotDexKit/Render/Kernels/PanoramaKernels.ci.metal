// Panorama kernels (FS-16 group 3c): the projection warp, the blend's
// running totals and bands, and the boundary warp.

#include <CoreImage/CoreImage.h>

extern "C" {
namespace coreimage {

// Canvas pixel to source pixel: undo the projection, turn the ray into the
// frame's own view, put it back on the sensor. Anything the frame did not see
// goes far outside its extent, where Core Image samples transparent.
float2 panoramaWarp(float2 origin, float canvasHeight, float canvasFocal, float kind,
                    float3 m0, float3 m1, float3 m2,
                    float sourceFocal, float2 sourceCentre, float2 sourceSize,
                    float distortion, destination dest) {
    float2 d = dest.coord();
    float u = d.x + origin.x;
    float v = (canvasHeight - d.y) + origin.y;

    float3 dir;
    if (kind < 0.5f) {
        float theta = u / canvasFocal;
        float phi = v / canvasFocal;
        float c = cos(phi);
        dir = float3(c * sin(theta), sin(phi), c * cos(theta));
    } else if (kind < 1.5f) {
        float theta = u / canvasFocal;
        dir = float3(sin(theta), v / canvasFocal, cos(theta));
    } else {
        dir = float3(u / canvasFocal, v / canvasFocal, 1.0f);
    }

    float3 local = float3(dot(m0, dir), dot(m1, dir), dot(m2, dir));
    if (local.z <= 0.000000001f) {
        return float2(-100000.0f, -100000.0f);
    }
    float nx = local.x / local.z;
    float ny = local.y / local.z;
    float bend = 1.0f + distortion * (nx * nx + ny * ny);
    float sx = sourceCentre.x + sourceFocal * nx * bend;
    float sy = sourceCentre.y + sourceFocal * ny * bend;
    if (sx < 0.0f || sy < 0.0f || sx > sourceSize.x - 1.0f || sy > sourceSize.y - 1.0f) {
        return float2(-100000.0f, -100000.0f);
    }
    // Index space to Core Image's continuous, y-up space: half a pixel.
    return float2(sx + 0.5f, sourceSize.y - 0.5f - sy);
}

// 0 at the frame's border, 1 in the middle, in the reference's index space.
float4 panoramaRamp(float width, float height, destination dest) {
    float2 d = dest.coord();
    float x = d.x - 0.5f;
    float y = height - 0.5f - d.y;
    float dx = min(x, width - 1.0f - x) / (width * 0.5f);
    float dy = min(y, height - 1.0f - y) / (height * 0.5f);
    float w = max(0.0001f, min(dx, dy));
    return float4(w, w, w, 1.0f);
}

// Running colour total. A border sample comes back premultiplied by part of
// its coverage; undoing that lets the weight alone decide how much to take.
float4 panoramaAccumulateColour(sample_t total, sample_t colour, sample_t weight, float gain) {
    if (colour.a <= 0.0f) { return total; }
    float3 unpremultiplied = colour.rgb / colour.a;
    float w = weight.r * colour.a;
    return float4(total.rgb + unpremultiplied * gain * w, 1.0f);
}

float4 panoramaAccumulateWeight(sample_t total, sample_t colour, sample_t weight) {
    if (colour.a <= 0.0f) { return total; }
    float w = weight.r * colour.a;
    return float4(total.rgb + float3(w), 1.0f);
}

float4 panoramaMaximum(sample_t a, sample_t b) {
    float wa = a.r * a.a;
    float wb = b.r * b.a;
    float w = max(wa, wb);
    return float4(w, w, w, 1.0f);
}

// One frame's hard claim: it owns the pixel if its say is the largest there.
float4 panoramaMask(sample_t weight, sample_t maximum) {
    float w = weight.r * weight.a;
    float m = (w > 0.0f && w >= maximum.r - 0.000001f) ? 1.0f : 0.0f;
    return float4(m, m, m, 1.0f);
}

float4 panoramaDifference(sample_t fine, sample_t coarse) {
    return float4(fine.rgb - coarse.rgb, 1.0f);
}

float4 panoramaGain(sample_t colour, float gain) {
    if (colour.a <= 0.0f) { return float4(0.0f); }
    return float4(colour.rgb / colour.a * gain, colour.a);
}

float4 panoramaBand(sample_t total, sample_t detail, sample_t mask) {
    return float4(total.rgb + detail.rgb * mask.r, 1.0f);
}

float4 panoramaBandWeight(sample_t total, sample_t mask) {
    return float4(total.rgb + float3(mask.r), 1.0f);
}

float4 panoramaSum(sample_t a, sample_t b) {
    return float4(a.rgb + b.rgb, 1.0f);
}

// The draft's coverage put back on the banded result.
float4 panoramaCoverage(sample_t colour, sample_t reference) {
    if (reference.a <= 0.0f) { return float4(0.0f); }
    return float4(colour.rgb, 1.0f);
}

// Totals divided back out; transparent where nothing landed.
float4 panoramaResolve(sample_t colourTotal, sample_t weightTotal) {
    if (weightTotal.r <= 0.0f) { return float4(0.0f); }
    return float4(colourTotal.rgb / weightTotal.r, 1.0f);
}

// Reads the destination's place in the map, then the picture there. The map
// counts rows from the top; Core Image counts them from the bottom.
float4 panoramaBoundaryWarp(sampler picture, sampler map, float height, destination dest) {
    float2 d = dest.coord();
    float4 place = map.sample(map.transform(d));
    float2 source = float2(place.r + 0.5f, height - 0.5f - place.g);
    return picture.sample(picture.transform(source));
}

}
}
