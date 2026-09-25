// Optics and detail kernels (FS-16 group 2): the shaped vignette, the lens
// profile warp, and noise reduction's detail pass.

#include <CoreImage/CoreImage.h>

extern "C" {
namespace coreimage {

// Distance in half-extent units, super-ellipse by `roundExponent`, eased off
// the highlights. Works on the premultiplied colour; alpha is untouched.
float4 vignette(sample_t s, float2 center, float2 halfExtent, float inner, float outer,
                float amount, float roundExponent, float highlights, destination dest) {
    float2 d = (dest.coord() - center) / halfExtent;
    float dist = pow(pow(abs(d.x), roundExponent) + pow(abs(d.y), roundExponent), 1.0f / roundExponent);
    float w = smoothstep(inner, outer, dist);
    float luma = dot(s.rgb, float3(0.2126f, 0.7152f, 0.0722f));
    w *= mix(1.0f, 1.0f - luma, highlights);
    float factor = 1.0f - w * amount;
    return float4(s.rgb * factor, s.a);
}

// Lensfun's three distortion models: 0 poly3, 1 poly5, 2 ptlens.
float2 lensWarp(float2 center, float norm, float zoom, float model,
                float k1, float k2, float a, float b, float c, destination dest) {
    float2 d = (dest.coord() - center) / (norm * zoom);
    float r = length(d);
    float g;
    if (model < 0.5f) {
        g = 1.0f - k1 + k1 * r * r;
    } else if (model < 1.5f) {
        g = 1.0f + k1 * r * r + k2 * r * r * r * r;
    } else {
        g = a * r * r * r + b * r * r + c * r + 1.0f - a - b - c;
    }
    return center + d * g * norm;
}

// What noise reduction removed, kept signed.
float4 noiseResidual(sample_t original, sample_t denoised) {
    return float4(original.rgb - denoised.rgb, 1.0f);
}

// Denoised plus `amount` of the (blurred) residual.
float4 noiseDetail(sample_t denoised, sample_t texture, float amount) {
    return float4(denoised.rgb + amount * texture.rgb, denoised.a);
}

}
}
