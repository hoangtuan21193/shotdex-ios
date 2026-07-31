import CoreImage
import Foundation

/// The Color tab's render stage: HSL mixer, point color, and color grading as
/// three `CIColorKernel`s. All decision math mirrors `ColorRenderMath` exactly
/// — the band centers and weight formulas are interpolated into the kernel
/// source from the same constants the unit tests cover.
extension PhotoRenderService {
    /// GLSL HSV helpers shared by every color kernel. Hue is 0…1 here; the
    /// generated code converts the degree-based Swift constants.
    private static let hsvHelpersSource = """
        vec3 rgb2hsv(vec3 c) {
            vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
            vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
            vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
            float d = q.x - min(q.w, q.y);
            float e = 1.0e-10;
            return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
        }
        vec3 hsv2rgb(vec3 c) {
            vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
            vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
            return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
        }
        """

    /// Unrolled partition-of-unity band weights over the eight mixer bands,
    /// generated from `ColorMixerBand.centerDegrees` so the GPU can never
    /// drift from `ColorRenderMath.bandWeights`. Plain scalars, no arrays or
    /// loops — the classic CIKernel dialect is a narrow GLSL subset.
    private static var bandWeightsSource: String {
        let centers = ColorMixerBand.allCases.map(\.centerDegrees)
        var branches: [String] = []
        for index in centers.indices {
            let lower = centers[index]
            let nextIndex = (index + 1) % centers.count
            let upper = nextIndex == 0 ? 360.0 : centers[nextIndex]
            branches.append("""
                if (hueDegrees >= \(lower) && hueDegrees < \(upper)) {
                    float t = smoothstep(0.0, 1.0, (hueDegrees - \(lower)) / \(upper - lower));
                    w\(index) = 1.0 - t;
                    w\(nextIndex) = t;
                }
                """)
        }
        return branches.joined(separator: " else ")
    }

    static let hslMixerKernel = CIColorKernel(source: """
        \(hsvHelpersSource)
        kernel vec4 hslMixer(__sample s,
                             vec4 hueA, vec4 hueB,
                             vec4 satA, vec4 satB,
                             vec4 lumA, vec4 lumB) {
            vec4 color = unpremultiply(s);
            vec3 hsv = rgb2hsv(color.rgb);
            float hueDegrees = hsv.x * 360.0;
            float w0 = 0.0; float w1 = 0.0; float w2 = 0.0; float w3 = 0.0;
            float w4 = 0.0; float w5 = 0.0; float w6 = 0.0; float w7 = 0.0;
            \(bandWeightsSource)
            vec4 weightsA = vec4(w0, w1, w2, w3);
            vec4 weightsB = vec4(w4, w5, w6, w7);
            float hueDelta = dot(weightsA, hueA) + dot(weightsB, hueB);
            float satTotal = dot(weightsA, satA) + dot(weightsB, satB);
            float lumTotal = dot(weightsA, lumA) + dot(weightsB, lumB);
            float m = smoothstep(0.03, 0.12, hsv.y);
            hsv.x = fract(hsv.x + hueDelta * m * (30.0 / 360.0));
            hsv.y = clamp(hsv.y * (1.0 + satTotal * m), 0.0, 1.0);
            hsv.z = clamp(hsv.z + lumTotal * m * hsv.z * (1.0 - hsv.z) * 2.0, 0.0, 1.0);
            return premultiply(vec4(hsv2rgb(hsv), color.a));
        }
        """)

    /// One unrolled point-color slot. Every slot's weight is computed from the
    /// ORIGINAL pixel color and the shifts are accumulated before any is
    /// applied — sequential per-point passes would make later points match on
    /// already-shifted pixels, so the result would depend on point order.
    private static func pointColorSlotSource(_ index: Int) -> String {
        """
        {
            float dh = abs(hueDegrees - ref\(index).x);
            dh = min(dh, 360.0 - dh) / 180.0;
            float ds = abs(hsv.y - ref\(index).y);
            float dv = abs(hsv.z - ref\(index).z);
            float d = sqrt(6.25 * dh * dh + ds * ds + dv * dv);
            float radius = mix(0.10, 0.55, ref\(index).w);
            float weight = (1.0 - smoothstep(radius * 0.4, radius, d)) * shift\(index).w;
            hueDelta += weight * shift\(index).x;
            satDelta += weight * shift\(index).y;
            lumDelta += weight * shift\(index).z;
        }
        """
    }

    static let pointColorKernel: CIColorKernel? = {
        let slots = (0..<PointColorAdjustment.maximumCount)
        let parameters = slots
            .map { "vec4 ref\($0), vec4 shift\($0)" }
            .joined(separator: ",\n                             ")
        let body = slots.map(pointColorSlotSource).joined(separator: "\n")
        return CIColorKernel(source: """
            \(hsvHelpersSource)
            kernel vec4 pointColor(__sample s,
                                 \(parameters)) {
                vec4 color = unpremultiply(s);
                vec3 hsv = rgb2hsv(color.rgb);
                float hueDegrees = hsv.x * 360.0;
                float hueDelta = 0.0;
                float satDelta = 0.0;
                float lumDelta = 0.0;
                \(body)
                hsv.x = fract(hsv.x + hueDelta * (30.0 / 360.0));
                hsv.y = clamp(hsv.y + satDelta, 0.0, 1.0);
                hsv.z = clamp(hsv.z + lumDelta * hsv.z * (1.0 - hsv.z) * 2.0, 0.0, 1.0);
                return premultiply(vec4(hsv2rgb(hsv), color.a));
            }
            """)
    }()

    /// One grading region: a luma-neutral chroma wash plus a self-limiting
    /// luminance lift, both scaled by the region weight.
    private static func gradingRegionSource(wheel: String, weight: String) -> String {
        """
        {
            vec3 tint = hsv2rgb(vec3(\(wheel).x, 1.0, 1.0));
            vec3 wash = tint - vec3(dot(tint, lumaWeights));
            rgb += wash * (\(wheel).y * \(weight) * 0.35);
            float lift = \(wheel).z * \(weight) * 0.3;
            rgb += lift * ((\(wheel).z > 0.0) ? (vec3(1.0) - rgb) : rgb);
            rgb = clamp(rgb, 0.0, 1.0);
        }
        """
    }

    static let colorGradeKernel = CIColorKernel(source: """
        \(hsvHelpersSource)
        kernel vec4 colorGrade(__sample s,
                               vec4 shadowW, vec4 midW, vec4 highW, vec4 globalW,
                               vec2 mixControls) {
            vec4 color = unpremultiply(s);
            vec3 rgb = color.rgb;
            vec3 lumaWeights = vec3(0.2126, 0.7152, 0.0722);
            float luma = dot(rgb, lumaWeights);
            float feather = mix(0.08, 0.35, mixControls.x);
            float shadowPivot = 0.33 + 0.25 * mixControls.y;
            float highlightPivot = 0.67 + 0.25 * mixControls.y;
            float wS = 1.0 - smoothstep(shadowPivot - feather, shadowPivot + feather, luma);
            float wH = smoothstep(highlightPivot - feather, highlightPivot + feather, luma);
            float wM = clamp(1.0 - wS - wH, 0.0, 1.0);
            \(gradingRegionSource(wheel: "shadowW", weight: "wS"))
            \(gradingRegionSource(wheel: "midW", weight: "wM"))
            \(gradingRegionSource(wheel: "highW", weight: "wH"))
            \(gradingRegionSource(wheel: "globalW", weight: "1.0"))
            return premultiply(vec4(rgb, color.a));
        }
        """)

    // MARK: - Application

    private static func mixerVectors(
        _ mixer: ColorMixerAdjustments,
        property: ColorMixerProperty
    ) -> (a: CIVector, b: CIVector) {
        let values = ColorMixerBand.allCases.map { CGFloat(mixer[$0][property]) }
        return (
            CIVector(x: values[0], y: values[1], z: values[2], w: values[3]),
            CIVector(x: values[4], y: values[5], z: values[6], w: values[7])
        )
    }

    private static func applyMixer(
        _ mixer: ColorMixerAdjustments,
        to input: CIImage
    ) -> CIImage {
        guard !mixer.isIdentity, let kernel = hslMixerKernel else { return input }
        let hue = mixerVectors(mixer, property: .hue)
        let sat = mixerVectors(mixer, property: .saturation)
        let lum = mixerVectors(mixer, property: .luminance)
        return kernel.apply(
            extent: input.extent,
            arguments: [input, hue.a, hue.b, sat.a, sat.b, lum.a, lum.b]
        ) ?? input
    }

    private static func applyPointColors(
        _ points: [PointColorAdjustment],
        to input: CIImage
    ) -> CIImage {
        let active = points.filter(\.hasVisibleEffect)
        guard !active.isEmpty, let kernel = pointColorKernel else { return input }
        var arguments: [Any] = [input]
        for index in 0..<PointColorAdjustment.maximumCount {
            if index < active.count {
                let point = active[index]
                arguments.append(CIVector(
                    x: CGFloat(point.referenceHue),
                    y: CGFloat(point.referenceSaturation),
                    z: CGFloat(point.referenceValue),
                    w: CGFloat(point.range)
                ))
                arguments.append(CIVector(
                    x: CGFloat(point.hueShift),
                    y: CGFloat(point.saturationShift),
                    z: CGFloat(point.luminanceShift),
                    w: 1
                ))
            } else {
                arguments.append(CIVector(x: 0, y: 0, z: 0, w: 0))
                arguments.append(CIVector(x: 0, y: 0, z: 0, w: 0))
            }
        }
        return kernel.apply(extent: input.extent, arguments: arguments) ?? input
    }

    private static func gradingVector(_ wheel: ColorGradingAdjustments.Wheel) -> CIVector {
        CIVector(
            x: CGFloat(wheel.hue / 360),
            y: CGFloat(wheel.saturation),
            z: CGFloat(wheel.luminance),
            w: 0
        )
    }

    private static func applyGrading(
        _ grading: ColorGradingAdjustments,
        to input: CIImage
    ) -> CIImage {
        guard !grading.isIdentity, let kernel = colorGradeKernel else { return input }
        return kernel.apply(
            extent: input.extent,
            arguments: [
                input,
                gradingVector(grading.shadows),
                gradingVector(grading.midtones),
                gradingVector(grading.highlights),
                gradingVector(grading.global),
                CIVector(x: CGFloat(grading.blending), y: CGFloat(grading.balance)),
            ]
        ) ?? input
    }

    /// Mixer → point colors → grading, matching Lightroom's stage order.
    /// Global-only by construction: only the whole-image call sites invoke it,
    /// never the per-mask adjustment pass.
    static func applyColor(_ color: PhotoColorRecipe, to input: CIImage) -> CIImage {
        guard !color.isIdentity else { return input }
        var image = applyMixer(color.mixer, to: input)
        image = applyPointColors(color.points, to: image)
        image = applyGrading(color.grading, to: image)
        return image.cropped(to: input.extent)
    }
}
