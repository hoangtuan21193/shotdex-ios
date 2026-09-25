// The video compositor's two qualifiers (FS-16 group 4). They are not the
// photo masks: the shoulders are shaped differently, on purpose.

#include <CoreImage/CoreImage.h>

extern "C" {
namespace coreimage {

// Everything whose luminance falls in the band, with a soft shoulder either side.
float4 luminanceKey(sample_t s, float low, float high, float soft) {
    float y = dot(s.rgb, float3(0.2126f, 0.7152f, 0.0722f));
    float m = smoothstep(low - soft, low + soft, y)
            * (1.0f - smoothstep(high - soft, high + soft, y));
    return float4(m, m, m, 1.0f);
}

// Distance from a sampled colour, inside a tolerance.
float4 colorKey(sample_t s, float3 target, float tolerance) {
    float d = distance(s.rgb, target);
    float m = 1.0f - smoothstep(tolerance * 0.5f, tolerance, d);
    return float4(m, m, m, 1.0f);
}

}
}
