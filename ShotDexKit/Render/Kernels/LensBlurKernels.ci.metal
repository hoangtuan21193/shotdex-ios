// Lens Blur kernels (FS-03.15e, FS-16). The photo is cut into depth layers,
// each blurred with the bokeh's shape and laid over the ones behind it.

#include <CoreImage/CoreImage.h>

// The helpers below live outside Core Image's namespace.
using namespace metal;

// Samples per gather. The caller shrinks the layer until the radius is a few
// pixels, so this many points cover the disc densely.
constant int lensBlurSamples = 96;

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

// The average of the premultiplied layer over a disc of `radius` pixels,
// sampled on a golden-angle spiral. `shape` picks the bokeh; 0 is an even
// disc.
float4 lensBlurGather(sampler layer, float radius, float shape, destination dest) {
    float2 p = dest.coord();
    float4 sum = float4(0.0f);
    float total = 0.0f;
    for (int i = 0; i < lensBlurSamples; i++) {
        float t = (float(i) + 0.5f) / float(lensBlurSamples);
        float r = sqrt(t);
        float a = float(i) * 2.39996323f;
        float2 offset = float2(cos(a), sin(a)) * r * radius;
        float w = 1.0f;
        sum += layer.sample(layer.transform(p + offset)) * w;
        total += w;
    }
    return sum / max(total, 0.0001f);
}

}
}
