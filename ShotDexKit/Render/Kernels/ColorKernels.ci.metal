// The Color tab's kernels (FS-16 group 2): HSL mixer, point color, color
// grading. The decision math mirrors `ColorRenderMath`, which the unit tests
// cover on the CPU.

#include <CoreImage/CoreImage.h>

// The helpers below live outside Core Image's namespace.
using namespace metal;

// Hue is 0…1 here; the kernels convert to degrees where the Swift constants are.
static inline float3 rgb2hsv(float3 c) {
    float4 K = float4(0.0f, -1.0f / 3.0f, 2.0f / 3.0f, -1.0f);
    float4 p = mix(float4(c.bg, K.wz), float4(c.gb, K.xy), float4(step(c.b, c.g)));
    float4 q = mix(float4(p.xyw, c.r), float4(c.r, p.yzx), float4(step(p.x, c.r)));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10f;
    return float3(abs(q.z + (q.w - q.y) / (6.0f * d + e)), d / (q.x + e), q.x);
}

static inline float3 hsv2rgb(float3 c) {
    float4 K = float4(1.0f, 2.0f / 3.0f, 1.0f / 3.0f, 3.0f);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0f - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, float3(0.0f), float3(1.0f)), float3(c.y));
}

// One point-color slot's pull on hue, saturation and value. Every slot is
// weighed against the ORIGINAL pixel and the pulls are summed before any is
// applied, so the result does not depend on the order of the points.
static inline float3 pointColorSlot(float hueDegrees, float3 hsv, float4 ref, float4 shift) {
    float dh = abs(hueDegrees - ref.x);
    dh = min(dh, 360.0f - dh) / 180.0f;
    float ds = abs(hsv.y - ref.y);
    float dv = abs(hsv.z - ref.z);
    float d = sqrt(6.25f * dh * dh + ds * ds + dv * dv);
    float radius = mix(0.10f, 0.55f, ref.w);
    float weight = (1.0f - smoothstep(radius * 0.4f, radius, d)) * shift.w;
    return weight * shift.xyz;
}

// One grading region: a luma-neutral chroma wash plus a self-limiting
// luminance lift, both scaled by the region's weight.
static inline float3 gradeRegion(float3 rgb, float4 wheel, float weight) {
    float3 lumaWeights = float3(0.2126f, 0.7152f, 0.0722f);
    float3 tint = hsv2rgb(float3(wheel.x, 1.0f, 1.0f));
    float3 wash = tint - float3(dot(tint, lumaWeights));
    rgb += wash * (wheel.y * weight * 0.35f);
    float lift = wheel.z * weight * 0.3f;
    rgb += lift * ((wheel.z > 0.0f) ? (float3(1.0f) - rgb) : rgb);
    return clamp(rgb, float3(0.0f), float3(1.0f));
}

extern "C" {
namespace coreimage {

// Partition-of-unity weights over the eight mixer bands. The band centres
// come in as arguments, from the same Swift constants `ColorRenderMath`
// uses, so the GPU cannot drift from the CPU.
float4 hslMixer(sample_t s,
                float4 hueA, float4 hueB,
                float4 satA, float4 satB,
                float4 lumA, float4 lumB,
                float4 centresA, float4 centresB) {
    float4 color = unpremultiply(s);
    float3 hsv = rgb2hsv(color.rgb);
    float hueDegrees = hsv.x * 360.0f;
    float centres[8] = {
        centresA.x, centresA.y, centresA.z, centresA.w,
        centresB.x, centresB.y, centresB.z, centresB.w,
    };
    float w[8] = { 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f };
    for (int index = 0; index < 8; index++) {
        int next = (index + 1) % 8;
        float lower = centres[index];
        float upper = next == 0 ? 360.0f : centres[next];
        if (hueDegrees >= lower && hueDegrees < upper) {
            float t = smoothstep(0.0f, 1.0f, (hueDegrees - lower) / (upper - lower));
            w[index] = 1.0f - t;
            w[next] = t;
            break;
        }
    }
    float4 weightsA = float4(w[0], w[1], w[2], w[3]);
    float4 weightsB = float4(w[4], w[5], w[6], w[7]);
    float hueDelta = dot(weightsA, hueA) + dot(weightsB, hueB);
    float satTotal = dot(weightsA, satA) + dot(weightsB, satB);
    float lumTotal = dot(weightsA, lumA) + dot(weightsB, lumB);
    float m = smoothstep(0.03f, 0.12f, hsv.y);
    hsv.x = fract(hsv.x + hueDelta * m * (30.0f / 360.0f));
    hsv.y = clamp(hsv.y * (1.0f + satTotal * m), 0.0f, 1.0f);
    hsv.z = clamp(hsv.z + lumTotal * m * hsv.z * (1.0f - hsv.z) * 2.0f, 0.0f, 1.0f);
    return premultiply(float4(hsv2rgb(hsv), color.a));
}

// Eight slots: `PointColorAdjustment.maximumCount`, which a test holds to 8.
float4 pointColor(sample_t s,
                  float4 ref0, float4 shift0, float4 ref1, float4 shift1,
                  float4 ref2, float4 shift2, float4 ref3, float4 shift3,
                  float4 ref4, float4 shift4, float4 ref5, float4 shift5,
                  float4 ref6, float4 shift6, float4 ref7, float4 shift7) {
    float4 color = unpremultiply(s);
    float3 hsv = rgb2hsv(color.rgb);
    float hueDegrees = hsv.x * 360.0f;
    float3 delta = float3(0.0f);
    delta += pointColorSlot(hueDegrees, hsv, ref0, shift0);
    delta += pointColorSlot(hueDegrees, hsv, ref1, shift1);
    delta += pointColorSlot(hueDegrees, hsv, ref2, shift2);
    delta += pointColorSlot(hueDegrees, hsv, ref3, shift3);
    delta += pointColorSlot(hueDegrees, hsv, ref4, shift4);
    delta += pointColorSlot(hueDegrees, hsv, ref5, shift5);
    delta += pointColorSlot(hueDegrees, hsv, ref6, shift6);
    delta += pointColorSlot(hueDegrees, hsv, ref7, shift7);
    hsv.x = fract(hsv.x + delta.x * (30.0f / 360.0f));
    hsv.y = clamp(hsv.y + delta.y, 0.0f, 1.0f);
    hsv.z = clamp(hsv.z + delta.z * hsv.z * (1.0f - hsv.z) * 2.0f, 0.0f, 1.0f);
    return premultiply(float4(hsv2rgb(hsv), color.a));
}

float4 colorGrade(sample_t s,
                  float4 shadowW, float4 midW, float4 highW, float4 globalW,
                  float2 mixControls) {
    float4 color = unpremultiply(s);
    float3 rgb = color.rgb;
    float luma = dot(rgb, float3(0.2126f, 0.7152f, 0.0722f));
    float feather = mix(0.08f, 0.35f, mixControls.x);
    float shadowPivot = 0.33f + 0.25f * mixControls.y;
    float highlightPivot = 0.67f + 0.25f * mixControls.y;
    float wS = 1.0f - smoothstep(shadowPivot - feather, shadowPivot + feather, luma);
    float wH = smoothstep(highlightPivot - feather, highlightPivot + feather, luma);
    float wM = clamp(1.0f - wS - wH, 0.0f, 1.0f);
    rgb = gradeRegion(rgb, shadowW, wS);
    rgb = gradeRegion(rgb, midW, wM);
    rgb = gradeRegion(rgb, highW, wH);
    rgb = gradeRegion(rgb, globalW, 1.0f);
    return premultiply(float4(rgb, color.a));
}

}
}
