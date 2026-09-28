// Healing and clone kernels (FS-16 group 3a). Distance comes in as an image,
// not from the destination coordinate, so these stay position-free.

#include <CoreImage/CoreImage.h>

// The helpers below live outside Core Image's namespace.
using namespace metal;

// The ring just outside the spot where the colour match is measured. Starts
// a little past the radius so the dust's own soft tail stays out.
static inline float healRingWeight(float dist, float radius) {
    return smoothstep(radius * 1.05f, radius * 1.2f, dist)
        * (1.0f - smoothstep(radius * 1.5f, radius * 1.7f, dist));
}

extern "C" {
namespace coreimage {

float4 healRing(sample_t target, sample_t shifted, sample_t dist, float radius, float span) {
    float w = healRingWeight(dist.r * span, radius);
    return float4((target.rgb - shifted.rgb) * w, 1.0f);
}

float4 healWeight(sample_t dist, float radius, float span) {
    float w = healRingWeight(dist.r * span, radius);
    return float4(w, w, w, 1.0f);
}

// The copy, corrected when healing, as a premultiplied layer: colour times
// coverage, coverage in alpha.
float4 healBlend(sample_t shifted, sample_t numerator, sample_t denominator,
                 sample_t distanceMap, float radius, float span, float feather,
                 float opacity, float heals) {
    float dist = distanceMap.r * span;
    float3 correction = heals * numerator.rgb / max(denominator.r, 0.0001f);
    float3 repaired = shifted.rgb + correction;
    float inner = radius * (1.0f - 0.7f * feather);
    float amount = (1.0f - smoothstep(inner, radius, dist)) * opacity;
    return float4(repaired * amount, amount);
}

// Red Eye (FS-03.15c §4): inside the pupil (`pupil` of the spot's radius,
// distance 0…1 over that radius) a red-dominant pixel has its red pulled to
// the level of green and blue, then the lot darkened by `darken`. A pixel
// that is not red — a brown iris, a lash — is left out of the layer. A
// premultiplied layer with coverage in alpha, like healBlend.
float4 redEye(sample_t s, sample_t distanceMap, float pupil, float darken) {
    float dist = distanceMap.r;
    float inside = 1.0f - smoothstep(pupil * 0.85f, pupil, dist);
    float other = max(s.g, s.b);
    float red = smoothstep(0.06f, 0.16f, s.r - other);
    float amount = inside * red;
    float3 fixed = float3(other, s.g, s.b) * (1.0f - 0.8f * darken);
    return float4(fixed * amount, amount);
}

}
}
