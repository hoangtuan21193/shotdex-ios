// Lens Blur kernels (FS-03.15e, FS-16). The photo is cut into depth layers,
// each blurred with the bokeh's shape and laid over the ones behind it.

#include <CoreImage/CoreImage.h>

// The helpers below live outside Core Image's namespace.
using namespace metal;

// Samples per gather. The caller shrinks the layer until the radius is a few
// pixels, so this many points cover the disc densely.
constant int lensBlurSamples = 96;

// The weight of one gather sample, by bokeh shape. `q` is the sample's
// offset as a share of the radius (inside the unit disc); `toCentre` is how
// far and which way the frame's centre lies, as a share of the half diagonal.
//   0 Circle   an even disc
//   1 Bubble   a disc whose rim is brighter than its middle
//   2 5-Blade  a pentagon, five straight aperture blades
//   3 Ring     a bright rim with a dark core (a mirror lens)
//   4 Cat Eye  a disc clipped by a second one shifted toward the frame's
//              centre, more the nearer the frame's edge
static inline float bokehWeight(float2 q, float shape, float2 toCentre) {
    float r = length(q);
    if (shape < 0.5f) return 1.0f;
    if (shape < 1.5f) return 1.0f + smoothstep(0.65f, 0.95f, r);
    if (shape < 2.5f) {
        float sector = 2.0f * M_PI_F / 5.0f;
        float a = atan2(q.y, q.x) + M_PI_F / 2.0f;
        float local = a - sector * floor(a / sector) - sector / 2.0f;
        float edge = cos(sector / 2.0f) / cos(local);
        return 1.0f - smoothstep(edge - 0.04f, edge, r);
    }
    if (shape < 3.5f) return 0.2f + 1.8f * smoothstep(0.55f, 0.8f, r);
    float2 shifted = q - toCentre * 0.7f;
    return 1.0f - smoothstep(0.96f, 1.0f, length(shifted));
}

extern "C" {
namespace coreimage {

// One depth layer as a premultiplied image: the photo where the depth falls
// in [band.x, band.y), transparent elsewhere. Hard edges on purpose — the
// layers partition the picture, and each one's blur softens its own edge.
float4 lensBlurSlice(sample_t image, sample_t depth, float2 band) {
    float d = depth.r;
    float m = step(band.x, d) * (1.0f - step(band.y, d));
    return float4(image.rgb * m, m);
}

// The average of the premultiplied layer over the bokeh of `radius` pixels,
// sampled on a golden-angle spiral. `centre` and `halfDiagonal` place the
// frame, in the layer's own pixels, for Cat Eye.
float4 lensBlurGather(sampler layer, float radius, float shape, float2 centre, float halfDiagonal, destination dest) {
    float2 p = dest.coord();
    float2 toCentre = (centre - p) / max(halfDiagonal, 1.0f);
    float4 sum = float4(0.0f);
    float total = 0.0f;
    for (int i = 0; i < lensBlurSamples; i++) {
        float t = (float(i) + 0.5f) / float(lensBlurSamples);
        float r = sqrt(t);
        float a = float(i) * 2.39996323f;
        float2 q = float2(cos(a), sin(a)) * r;
        float w = bokehWeight(q, shape, toCentre);
        sum += layer.sample(layer.transform(p + q * radius)) * w;
        total += w;
    }
    return sum / max(total, 0.0001f);
}

// The preview's blend (FS-03.15e §2): eight copies of the whole photo blurred
// 0, 1/7 … 7/7 of the full radius, and each pixel mixing the two whose radius
// brackets its own. The pixel's radius follows the saved render's steps —
// seven per side of the focus band, each blurred by its middle — so the two
// land on the same numbers wherever the depth does not change.
float4 lensBlurLevels(sample_t l0, sample_t l1, sample_t l2, sample_t l3,
                      sample_t l4, sample_t l5, sample_t l6, sample_t l7,
                      sample_t depth, float amount, float2 band) {
    float d = depth.r;
    float t = 0.0f;
    if (d < band.x) t = (band.x - d) / max(band.x, 0.0001f);
    else if (d > band.y) t = (d - band.y) / max(1.0f - band.y, 0.0001f);
    float step = ceil(clamp(t, 0.0f, 1.0f) * 7.0f);
    float blur = step > 0.0f ? (step - 0.5f) / 7.0f : 0.0f;
    float level = clamp(amount * blur * 7.0f, 0.0f, 7.0f);
    float lower = floor(level);
    float f = level - lower;
    float4 a = l0, b = l1;
    if (lower >= 6.0f) { a = l6; b = l7; }
    else if (lower >= 5.0f) { a = l5; b = l6; }
    else if (lower >= 4.0f) { a = l4; b = l5; }
    else if (lower >= 3.0f) { a = l3; b = l4; }
    else if (lower >= 2.0f) { a = l2; b = l3; }
    else if (lower >= 1.0f) { a = l1; b = l2; }
    return mix(a, b, f);
}

}
}
