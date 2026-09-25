// Photo Stack and Focus Stack kernels (FS-16 group 3b).

#include <CoreImage/CoreImage.h>

// The helpers below live outside Core Image's namespace.
using namespace metal;

// A frame's weight: its sharpness relative to the peak, to the eighth power.
// The floor keeps every term inside a half float's normal range — Core
// Image's working format — so the sums keep their precision.
static inline float focusWeight(float sharp, float peak) {
    float r = sharp / max(peak, 0.0000001f);
    float r2 = r * r;
    float r4 = r2 * r2;
    return r4 * r4 + 0.001f;
}

extern "C" {
namespace coreimage {

// "This frame is sharper here", 0 or 1 with a narrow ramp.
float4 focusDecision(sample_t candidate, sample_t best) {
    float m = clamp((candidate.r - best.r) * 200.0f, 0.0f, 1.0f);
    return float4(m, m, m, 1.0f);
}

float4 focusPeak(sample_t a, sample_t b) {
    float m = max(a.r, b.r);
    return float4(m, m, m, 1.0f);
}

float4 focusWeightedColour(sample_t total, sample_t frame, sample_t sharp, sample_t peak) {
    float w = focusWeight(sharp.r, peak.r);
    return float4(total.rgb + frame.rgb * w, 1.0f);
}

float4 focusWeightedTotal(sample_t total, sample_t sharp, sample_t peak) {
    float w = focusWeight(sharp.r, peak.r);
    return float4(total.rgb + float3(w), 1.0f);
}

float4 focusWeightedResolve(sample_t colour, sample_t weight) {
    return float4(colour.rgb / max(weight.r, 0.001f), 1.0f);
}

// Streamed Weighted: colour × weight in RGB, the weight itself in alpha.
float4 focusWeightedAccumulate(sample_t total, sample_t frame, sample_t sharp, sample_t peak) {
    float w = focusWeight(sharp.r, peak.r);
    return float4(total.rgb + frame.rgb * w, total.a + w);
}

float4 focusWeightedAlphaResolve(sample_t sums) {
    return float4(sums.rgb / max(sums.a, 0.001f), 1.0f);
}

// |Laplacian| of luminance, never negative, opaque.
float4 focusLaplacian(sampler image, destination dest) {
    float2 p = dest.coord();
    float3 luma = float3(0.299f, 0.587f, 0.114f);
    float c = dot(image.sample(image.transform(p)).rgb, luma);
    float n = dot(image.sample(image.transform(p + float2(0.0f, 1.0f))).rgb, luma);
    float s = dot(image.sample(image.transform(p - float2(0.0f, 1.0f))).rgb, luma);
    float e = dot(image.sample(image.transform(p + float2(1.0f, 0.0f))).rgb, luma);
    float w = dot(image.sample(image.transform(p - float2(1.0f, 0.0f))).rgb, luma);
    float m = abs(n + s + e + w - 4.0f * c);
    return float4(m, m, m, 1.0f);
}

}
}
