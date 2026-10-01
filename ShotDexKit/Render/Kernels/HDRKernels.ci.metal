// HDR merge kernels (FS-01.11 §5).

#include <CoreImage/CoreImage.h>

using namespace metal;

// A frame's samples count fully below 0.90 and not at all from 0.98 up:
// a hard cut at the clip point turns sensor noise into speckle along every
// highlight edge.
static inline float hdrUnclipped(float3 v) {
    float m = max(v.r, max(v.g, v.b));
    return clamp((0.98f - m) / 0.08f, 0.0f, 1.0f);
}

static inline float hdrLuma(float3 v) {
    return dot(v, float3(0.2126f, 0.7152f, 0.0722f));
}

extern "C" {
namespace coreimage {

// Radiance in RGB, its total weight in alpha. A frame `gain` times the
// reference's exposure reads gain × radiance, so it adds its value to the
// numerator and its gain to the weight: Σv ÷ Σg over the unclipped frames,
// the estimate that weights each frame by its signal under shot noise.
// `keep` is 0 where deghosting left this frame out.
float4 hdrAccumulate(sample_t total, sample_t frame, sample_t keep, float gain) {
    float w = gain * hdrUnclipped(frame.rgb) * keep.r;
    return float4(total.rgb + frame.rgb * (w / gain), total.a + w);
}

// The merged radiance, or `fallback` where no frame was left to say — the
// darkest frame clipped too, or deghosting left every frame out.
float4 hdrResolve(sample_t sums, sample_t fallback) {
    if (sums.a < 0.0001f) { return float4(fallback.rgb, 1.0f); }
    return float4(sums.rgb / sums.a, 1.0f);
}

// One step of the anchor: the frame nearest the reference, from below, that
// is still readable here. Walked darkest first up to the reference, so the
// last readable frame wins. Radiance in RGB, its noise σ in alpha (a σ,
// not a variance: a variance of 1e-6 is below a half float's normal range).
// `noise` is the sensor model in frame units: shot gain, read variance,
// quantisation variance. `first` takes the frame whatever it reads.
float4 hdrAnchor(sample_t anchor, sample_t frame, float gain, float3 noise, float first) {
    if (first < 0.5f && max(frame.r, max(frame.g, frame.b)) >= 0.90f) { return anchor; }
    float l = max(hdrLuma(frame.rgb), 0.0f);
    float sigma = sqrt(l * noise.x + noise.y + noise.z) / gain;
    return float4(frame.rgb / gain, sigma);
}

// 1 where this frame disagrees with the anchor by more than `z` standard
// deviations of the two frames' noise together. A clipped frame is already
// out of the merge; rejecting it too would only spread, through the
// dilation, into the edge of every highlight.
float4 hdrReject(sample_t frame, sample_t anchor, float gain, float3 noise, float z) {
    if (hdrUnclipped(frame.rgb) <= 0.0f) { return float4(0.0f, 0.0f, 0.0f, 1.0f); }
    float l = max(hdrLuma(frame.rgb), 0.0f);
    float sigma = sqrt(l * noise.x + noise.y + noise.z) / gain;
    float d = abs(hdrLuma(frame.rgb) / gain - hdrLuma(anchor.rgb));
    float r = d > z * sqrt(sigma * sigma + anchor.a * anchor.a) ? 1.0f : 0.0f;
    return float4(r, r, r, 1.0f);
}

}
}
