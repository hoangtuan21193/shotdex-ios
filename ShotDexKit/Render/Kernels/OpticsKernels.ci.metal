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

// Lensfun's three distortion models: 0 poly3, 1 poly5, 2 ptlens — then the
// manual Distortion on top, in the same warp so the frame is resampled once:
// 1 − manual·ρ², ρ the output radius over the half-diagonal (FS-03.15b §3).
float2 lensWarp(float2 center, float norm, float zoom, float model,
                float k1, float k2, float a, float b, float c,
                float manual, float halfDiagonal, destination dest) {
    float2 p = dest.coord() - center;
    float2 d = p / (norm * zoom);
    float r = length(d);
    float g;
    if (model < 0.5f) {
        g = 1.0f - k1 + k1 * r * r;
    } else if (model < 1.5f) {
        g = 1.0f + k1 * r * r + k2 * r * r * r * r;
    } else {
        g = a * r * r * r + b * r * r + c * r + 1.0f - a - b - c;
    }
    float rho = length(p) / (halfDiagonal * zoom);
    float manualScale = 1.0f - manual * rho * rho;
    return center + d * g * manualScale * norm;
}

// What noise reduction removed, kept signed.
float4 noiseResidual(sample_t original, sample_t denoised) {
    return float4(original.rgb - denoised.rgb, 1.0f);
}

// Denoised plus `amount` of the (blurred) residual.
float4 noiseDetail(sample_t denoised, sample_t texture, float amount) {
    return float4(denoised.rgb + amount * texture.rgb, denoised.a);
}

// Colour noise reduction: the original's luminance with the blurred frame's
// chroma, except where the chroma changes by more than noise does — a fine
// red edge — where `detail` of the original chroma is kept. Chroma is the
// colour minus its luminance, so luminance never moves.
float4 chromaDenoise(sample_t original, sample_t blurred, float detail) {
    float3 w = float3(0.2126f, 0.7152f, 0.0722f);
    float y = dot(original.rgb, w);
    float3 sharpChroma = original.rgb - y;
    float3 softChroma = blurred.rgb - dot(blurred.rgb, w);
    float edge = smoothstep(0.06f, 0.16f, length(sharpChroma - softChroma));
    return float4(y + mix(softChroma, sharpChroma, detail * edge), original.a);
}

// Hue in degrees, 0…360.
static float hueDegrees(float3 c) {
    float high = max(c.r, max(c.g, c.b));
    float low = min(c.r, min(c.g, c.b));
    float d = high - low;
    if (d <= 0.0f) return 0.0f;
    float h;
    if (high == c.r) {
        h = (c.g - c.b) / d;
        if (h < 0.0f) h += 6.0f;
    } else if (high == c.g) {
        h = (c.b - c.r) / d + 2.0f;
    } else {
        h = (c.r - c.g) / d + 4.0f;
    }
    return h * 60.0f;
}

// Soft membership of `h` in [lo, hi], 8° ramps outside.
static float hueBand(float h, float lo, float hi) {
    return smoothstep(lo - 8.0f, lo, h) * (1.0f - smoothstep(hi, hi + 8.0f, h));
}

// Defringe: pixels near an edge (`edge`, 0…1) whose hue falls in the purple
// or green band are pulled toward grey. Each band is (strength, lo°, hi°);
// neither band crosses 0°. Near-greys are left alone.
float4 defringe(sample_t s, sample_t edge, float3 purple, float3 green) {
    float3 c = s.rgb;
    float spread = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
    float h = hueDegrees(c);
    float band = purple.x * hueBand(h, purple.y, purple.z) + green.x * hueBand(h, green.y, green.z);
    float pull = clamp(band, 0.0f, 1.0f) * edge.r * smoothstep(0.02f, 0.06f, spread);
    float y = dot(c, float3(0.2126f, 0.7152f, 0.0722f));
    return float4(mix(c, float3(y), pull), s.a);
}

// The image's luminance with its chroma moved `amount` of the way to the
// source's chroma. Colour Smoothness feeds it a wide blur; the Moiré brush
// will feed it the same.
float4 chromaBlend(sample_t image, sample_t source, float amount) {
    float3 w = float3(0.2126f, 0.7152f, 0.0722f);
    float y = dot(image.rgb, w);
    float3 chroma = image.rgb - y;
    float3 sourceChroma = source.rgb - dot(source.rgb, w);
    return float4(y + mix(chroma, sourceChroma, amount), image.a);
}

}
}
