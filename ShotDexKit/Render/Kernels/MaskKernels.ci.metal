// Mask kernels (FS-16 group 1). Every output is a grey mask, opaque.

#include <CoreImage/CoreImage.h>

extern "C" {
namespace coreimage {

float4 addMask(sample_t current, sample_t incoming) {
    float value = max(current.r, incoming.r * incoming.a);
    return float4(value, value, value, 1.0f);
}

// Subtract multiplies by the complement (FS-03.15d §1, E10): a soft 0.8 edge
// minus 0.5 is 0.4, not 0.3 — plain subtraction bit deeper into soft edges
// than Lightroom and Photoshop do.
float4 subtractMask(sample_t current, sample_t incoming) {
    float value = current.r * (1.0f - clamp(incoming.r * incoming.a, 0.0f, 1.0f));
    return float4(value, value, value, 1.0f);
}

// Intersect: the mask so far times the new area, softened by the area's
// opacity — at opacity 0 the mask is untouched, not emptied.
float4 intersectMask(sample_t current, sample_t incoming, float opacity) {
    float value = current.r * mix(1.0f, incoming.r, opacity);
    return float4(value, value, value, 1.0f);
}

float4 invertMask(sample_t value) {
    float result = 1.0f - value.r;
    return float4(result, result, result, 1.0f);
}

float4 luminanceMask(sample_t color, float lower, float upper, float feather) {
    float luminance = dot(color.rgb, float3(0.2126f, 0.7152f, 0.0722f));
    float edge = max(0.001f, feather);
    float low = smoothstep(lower - edge, lower + edge, luminance);
    float high = 1.0f - smoothstep(upper - edge, upper + edge, luminance);
    float value = clamp(low * high, 0.0f, 1.0f);
    return float4(value, value, value, 1.0f);
}

float4 colorMask(sample_t color, float3 target, float tolerance, float feather) {
    float distance = length(color.rgb - target);
    float edge = max(0.001f, feather);
    float value = 1.0f - smoothstep(tolerance - edge, tolerance + edge, distance);
    return float4(value, value, value, 1.0f);
}

/// The sharpen's edge mask: the strongest channel of an edge image, ramped.
float4 edgeMask(sample_t s, float lo, float hi) {
    float e = max(s.r, max(s.g, s.b));
    float m = smoothstep(lo, hi, e);
    return float4(m, m, m, 1.0f);
}

}
}
