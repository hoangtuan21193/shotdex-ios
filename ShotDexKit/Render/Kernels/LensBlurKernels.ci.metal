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

}
}
