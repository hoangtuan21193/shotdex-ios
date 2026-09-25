import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// One kernel, called the way its call site calls it, on inputs `input(phase)`.
struct KernelGoldenCase: Sendable, CustomTestStringConvertible {
    let name: String
    /// The kernel this case exercises; several cases may share one.
    let kernel: String
    let render: @Sendable (_ input: (Int) -> CIImage) -> CIImage?

    var testDescription: String { name }
}

/// FS-16 AC-1, AC-2, AC-13 — every kernel against the output it had before
/// the move to Metal.
struct KernelGoldenTests {

    enum InputSet: String, CaseIterable {
        case patches, photo
    }

    @Test(arguments: KernelGoldenCase.all)
    func matchesItsGolden(_ kernelCase: KernelGoldenCase) throws {
        for set in InputSet.allCases {
            var inputs: [Int: CIImage] = [:]
            for phase in 0..<4 {
                let values = switch set {
                case .patches: KernelGolden.patches(phase: phase)
                case .photo: try KernelGolden.photo(phase: phase)
                }
                inputs[phase] = KernelGolden.image(values)
            }
            let output = try #require(
                kernelCase.render { inputs[$0 % 4]! },
                "\(kernelCase.name) did not render"
            )
            try KernelGolden.check(
                KernelGolden.pixels(of: output),
                named: "\(kernelCase.name)-\(set.rawValue)"
            )
        }
    }

    /// AC-2 counts forty kernels; every one of them has a case.
    @Test func everyKernelHasACase() {
        let kernels = Set(KernelGoldenCase.all.map(\.kernel))
        #expect(kernels.count == 40)
        #expect(Set(KernelGoldenCase.all.map(\.name)).count == KernelGoldenCase.all.count)
    }

    /// AC-13. A golden that is not there fails the test; it does not skip it.
    @Test func aMissingGoldenIsAFailure() {
        #expect(throws: (any Error).self) {
            try KernelGolden.expectedValues(named: "no-such-kernel-patches")
        }
    }

    @Test func goldensRoundTripUnderTheTolerance() throws {
        let values = KernelGolden.patches(phase: 1).map { $0 * 7.3 - 2 }
        let back = try KernelGolden.decode(KernelGolden.encode(values))
        #expect(zip(values, back).allSatisfy { KernelGolden.withinTolerance($1, $0) })
    }
}

// MARK: - The forty kernels

extension KernelGoldenCase {
    static var all: [KernelGoldenCase] {
        mask + colorOptics + healing + stack + panorama + video
    }

    private static let extent = CGRect(x: 0, y: 0, width: KernelGolden.size, height: KernelGolden.size)

    private static func color(
        _ name: String,
        _ kernel: @escaping @Sendable () -> CIColorKernel?,
        _ arguments: @escaping @Sendable (_ input: (Int) -> CIImage) -> [Any]
    ) -> KernelGoldenCase {
        KernelGoldenCase(name: name, kernel: name) { input in
            kernel()?.apply(extent: extent, arguments: arguments(input))
        }
    }

    // MARK: Group 1 — masks

    static let mask: [KernelGoldenCase] = [
        color("addMask", { PhotoRenderService.addMaskKernel }) { [$0(0), $0(1)] },
        color("subtractMask", { PhotoRenderService.subtractMaskKernel }) { [$0(0), $0(1)] },
        color("invertMask", { PhotoRenderService.invertMaskKernel }) { [$0(0)] },
        color("luminanceMask", { PhotoRenderService.luminanceMaskKernel }) {
            [$0(0), Float(0.3), Float(0.7), Float(0.1)]
        },
        color("colorMask", { PhotoRenderService.colorMaskKernel }) {
            [$0(0), CIVector(x: 1, y: 0.5, z: 0), Float(0.3), Float(0.1)]
        },
        color("edgeMask", { PhotoRenderService.edgeMaskKernel }) { [$0(0), Float(0.2), Float(0.28)] },
    ]

    // MARK: Group 2 — colour, optics, detail

    static let colorOptics: [KernelGoldenCase] = [
        color("hslMixer", { PhotoRenderService.hslMixerKernel }) {
            [
                $0(0),
                CIVector(x: 0.5, y: -0.3, z: 0.8, w: -1), CIVector(x: 0.2, y: 0.6, z: -0.4, w: 1),
                CIVector(x: 0.4, y: -0.5, z: 0.3, w: 0.9), CIVector(x: -0.8, y: 0.2, z: 0.5, w: -0.3),
                CIVector(x: 0.3, y: -0.2, z: 0.6, w: -0.7), CIVector(x: 0.1, y: 0.5, z: -0.4, w: 0.8),
            ]
        },
        color("pointColor", { PhotoRenderService.pointColorKernel }) {
            [$0(0)] + pointSlots(active: 0..<PointColorAdjustment.maximumCount)
        },
        // AC-8: only the last slot does anything, so a kernel that dropped it shows.
        KernelGoldenCase(name: "pointColorLastSlot", kernel: "pointColor") { input in
            PhotoRenderService.pointColorKernel?.apply(
                extent: extent,
                arguments: [input(0)] + pointSlots(active: (PointColorAdjustment.maximumCount - 1)..<PointColorAdjustment.maximumCount)
            )
        },
        color("colorGrade", { PhotoRenderService.colorGradeKernel }) {
            [
                $0(0),
                CIVector(x: 0.6, y: 0.5, z: 0.2, w: 0), CIVector(x: 0.1, y: 0.3, z: -0.2, w: 0),
                CIVector(x: 0.12, y: 0.4, z: -0.3, w: 0), CIVector(x: 0.8, y: 0.2, z: 0.1, w: 0),
                CIVector(x: 0.4, y: -0.3),
            ]
        },
        color("vignette", { PhotoRenderService.vignetteKernel }) {
            [
                $0(0), CIVector(x: 24, y: 24), CIVector(x: 24, y: 24),
                0.5, 1.1, 0.8, 3.5, 0.5,
            ]
        },
        lens("lensWarpPoly3", model: 0),
        lens("lensWarpPoly5", model: 1),
        lens("lensWarpPTLens", model: 2),
        color("noiseResidual", { PhotoRenderService.noiseResidualKernel }) { [$0(0), $0(1)] },
        color("noiseDetail", { PhotoRenderService.noiseDetailKernel }) { [$0(0), $0(1), 0.6] },
    ]

    /// `active` slots get a reference and a shift each; the rest are zero,
    /// as the call site pads them.
    private static func pointSlots(active: Range<Int>) -> [Any] {
        var arguments: [Any] = []
        for slot in 0..<PointColorAdjustment.maximumCount {
            if active.contains(slot) {
                let s = CGFloat(slot)
                arguments.append(CIVector(x: s * 45, y: 0.3 + s * 0.08, z: 0.4 + s * 0.07, w: 0.2 + s * 0.1))
                arguments.append(CIVector(x: s.truncatingRemainder(dividingBy: 2) == 0 ? 0.6 : -0.5, y: 0.3 - s * 0.05, z: 0.2, w: 1))
            } else {
                arguments.append(CIVector(x: 0, y: 0, z: 0, w: 0))
                arguments.append(CIVector(x: 0, y: 0, z: 0, w: 0))
            }
        }
        return arguments
    }

    private static func lens(_ name: String, model: Float) -> KernelGoldenCase {
        KernelGoldenCase(name: name, kernel: "lensWarp") { input in
            let extent = extent
            return PhotoRenderService.lensWarpKernel?.apply(
                extent: extent,
                roiCallback: { _, rect in rect.union(extent).insetBy(dx: -8, dy: -8) },
                image: input(0).clampedToExtent(),
                arguments: [
                    CIVector(x: 24, y: 24), Float(30), Float(1.05), model,
                    Float(-0.08), Float(0.03), Float(0.01), Float(-0.03), Float(0.02),
                ]
            )?.cropped(to: extent)
        }
    }

    // MARK: Group 3a — healing

    static let healing: [KernelGoldenCase] = [
        color("healRing", { PhotoRenderService.healingRingKernel }) {
            [$0(0), $0(1), $0(2), Float(8), Float(24)]
        },
        color("healWeight", { PhotoRenderService.healingWeightKernel }) { [$0(2), Float(8), Float(24)] },
        color("healBlend", { PhotoRenderService.healingBlendKernel }) {
            [$0(0), $0(1), $0(3), $0(2), Float(8), Float(24), Float(0.5), Float(0.9), Float(1)]
        },
    ]

    // MARK: Group 3b — photo stack and focus stack

    static let stack: [KernelGoldenCase] = [
        color("focusDecision", { PhotoStackRenderer.decisionKernel }) { [$0(0), $0(1)] },
        color("focusPeak", { PhotoStackRenderer.peakKernel }) { [$0(0), $0(1)] },
        color("focusWeightedColour", { PhotoStackRenderer.weightedColourKernel }) {
            [$0(0), $0(1), $0(2), peak($0)]
        },
        color("focusWeightedTotal", { PhotoStackRenderer.weightedTotalKernel }) { [$0(0), $0(2), peak($0)] },
        color("focusWeightedResolve", { PhotoStackRenderer.weightedResolveKernel }) { [$0(0), $0(1)] },
        KernelGoldenCase(name: "focusLaplacian", kernel: "focusLaplacian") { input in
            PhotoStackRenderer.laplacianKernel?.apply(
                extent: extent,
                roiCallback: { _, rect in rect.insetBy(dx: -1, dy: -1) },
                arguments: [input(0).clampedToExtent()]
            )
        },
        color("focusWeightedAccumulate", { PhotoStackRenderer.weightedAccumulateKernel }) {
            [$0(0), $0(1), $0(2), peak($0)]
        },
        color("focusWeightedAlphaResolve", { PhotoStackRenderer.weightedAlphaResolveKernel }) { [$0(1)] },
    ]

    /// The sharpness peak is the largest of the maps, as the call site builds
    /// it; a peak below the sharpness sends r⁸ past a half float.
    private static func peak(_ input: (Int) -> CIImage) -> CIImage {
        input(2).applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: input(3)])
    }

    // MARK: Group 3c — panorama

    static let panorama: [KernelGoldenCase] = [
        panoramaWarp("panoramaWarpSpherical", kind: 0),
        panoramaWarp("panoramaWarpCylindrical", kind: 1),
        panoramaWarp("panoramaWarpPlanar", kind: 2),
        KernelGoldenCase(name: "panoramaRamp", kernel: "panoramaRamp") { _ in
            PanoramaCIBlender.rampKernel?.apply(
                extent: CGRect(x: 0, y: 0, width: 40, height: 30),
                roiCallback: { _, rect in rect },
                arguments: [Float(40), Float(30)]
            )
        },
        color("panoramaAccumulateColour", { PanoramaCIBlender.accumulateColourKernel }) {
            [$0(1), $0(0), $0(2), Float(1.2)]
        },
        color("panoramaAccumulateWeight", { PanoramaCIBlender.accumulateWeightKernel }) {
            [$0(1), $0(0), $0(2)]
        },
        color("panoramaMaximum", { PanoramaCIBlender.maximumKernel }) { [$0(0), $0(1)] },
        color("panoramaMask", { PanoramaCIBlender.maskKernel }) { [$0(0), $0(1)] },
        color("panoramaDifference", { PanoramaCIBlender.differenceKernel }) { [$0(0), $0(1)] },
        color("panoramaGain", { PanoramaCIBlender.gainKernel }) { [$0(0), Float(1.3)] },
        color("panoramaBand", { PanoramaCIBlender.bandKernel }) { [$0(0), $0(1), $0(2)] },
        color("panoramaBandWeight", { PanoramaCIBlender.bandWeightKernel }) { [$0(0), $0(1)] },
        color("panoramaSum", { PanoramaCIBlender.sumKernel }) { [$0(0), $0(1)] },
        color("panoramaCoverage", { PanoramaCIBlender.coverageKernel }) { [$0(0), $0(1)] },
        color("panoramaResolve", { PanoramaCIBlender.resolveKernel }) { [$0(0), $0(1)] },
        KernelGoldenCase(name: "panoramaBoundaryWarp", kernel: "panoramaBoundaryWarp") { input in
            let side = KernelGolden.size
            let columns = 6
            var map = [Float](repeating: 0, count: columns * columns * 4)
            for row in 0..<columns {
                for column in 0..<columns {
                    let offset = (row * columns + column) * 4
                    let step = Float(side - 1) / Float(columns - 1)
                    map[offset] = Float(column) * step + 2.5 * sin(Float(row + 2 * column))
                    map[offset + 1] = Float(row) * step + 2.5 * cos(Float(3 * row + column))
                    map[offset + 3] = 1
                }
            }
            let stretched = KernelGolden.image(map, width: columns, height: columns)
                .transformed(by: CGAffineTransform(
                    scaleX: CGFloat(side) / CGFloat(columns),
                    y: CGFloat(side) / CGFloat(columns)
                ))
                .clampedToExtent()
            return PanoramaBoundaryWarp.warpKernel?.apply(
                extent: extent,
                roiCallback: { _, rect in rect.insetBy(dx: -2, dy: -2) },
                arguments: [input(0).clampedToExtent(), stretched, Float(side)]
            )
        },
    ]

    private static func panoramaWarp(_ name: String, kind: Float) -> KernelGoldenCase {
        KernelGoldenCase(name: name, kernel: "panoramaWarp") { input in
            let extent = extent
            return PanoramaCIBlender.warpKernel?.apply(
                extent: extent,
                roiCallback: { _, _ in extent },
                image: input(0),
                arguments: [
                    CIVector(x: -24, y: -24), Float(48), Float(40), kind,
                    CIVector(x: 0.995, y: 0, z: 0.0998),
                    CIVector(x: 0, y: 1, z: 0),
                    CIVector(x: -0.0998, y: 0, z: 0.995),
                    Float(40), CIVector(x: 23.5, y: 23.5), CIVector(x: 48, y: 48), Float(0.04),
                ]
            )
        }
    }

    // MARK: Group 4 — video

    static let video: [KernelGoldenCase] = [
        color("videoLuminanceKey", { VideoMaskRenderer.luminanceKeyKernel }) {
            [$0(0), Float(0.25), Float(0.75), Float(0.1)]
        },
        color("videoColorKey", { VideoMaskRenderer.colorKeyKernel }) {
            [$0(0), CIVector(x: 0.2, y: 0.4, z: 0.9), Float(0.4)]
        },
    ]
}

// MARK: - Whole pictures

/// FS-16 AC-3, AC-9, AC-10 — the kernels as the renderers use them.
@Suite(.serialized)
struct KernelPipelineGoldenTests {

    /// Every kernel of groups 1 and 2 at once: two masks (luminance and colour
    /// ranges, added, subtracted and inverted), noise reduction with Detail,
    /// masked sharpening, the shaped vignette, and all three colour stages.
    static var groupsOneAndTwo: PhotoEditRecipe {
        var recipe = PhotoEditRecipe()
        recipe.adjustments.noiseReduction = 0.5
        recipe.adjustments.noiseDetail = 0.6
        recipe.adjustments.sharpness = 0.8
        recipe.adjustments.sharpenMasking = 0.4
        recipe.adjustments.vignette = 0.6
        recipe.adjustments.vignetteRoundness = 0.5
        recipe.adjustments.vignetteHighlights = 0.4
        recipe.color.mixer.orange.saturation = 0.5
        recipe.color.mixer.orange.hue = 0.3
        recipe.color.mixer.blue.hue = -0.3
        recipe.color.mixer.blue.luminance = 0.2
        recipe.color.points = [
            PointColorAdjustment(
                referenceHue: 30, referenceSaturation: 0.8, referenceValue: 0.9,
                hueShift: -0.4, saturationShift: 0.2, luminanceShift: 0.1
            ),
        ]
        recipe.color.grading.shadows.hue = 220
        recipe.color.grading.shadows.saturation = 0.4
        recipe.color.grading.highlights.hue = 40
        recipe.color.grading.highlights.saturation = 0.3
        recipe.color.grading.highlights.luminance = 0.1

        var bright = PhotoMaskComponent(kind: .luminanceRange)
        bright.luminanceMinimum = 0.5
        bright.luminanceMaximum = 1
        var sky = PhotoMaskComponent(kind: .colorRange, operation: .subtract)
        sky.sampledRed = 0.35
        sky.sampledGreen = 0.5
        sky.sampledBlue = 0.8
        sky.colorTolerance = 0.3
        var first = PhotoMask(name: "Bright", component: bright)
        first.components.append(sky)
        first.adjustments.exposure = 0.7

        var orange = PhotoMaskComponent(kind: .colorRange)
        orange.sampledRed = 1
        orange.sampledGreen = 0.55
        orange.sampledBlue = 0.1
        var second = PhotoMask(name: "Not orange", component: orange)
        second.isInverted = true
        second.adjustments.saturation = -0.5
        recipe.masks = [first, second]
        return recipe
    }

    private func render(_ recipe: PhotoEditRecipe, size: CGFloat) async throws -> CGImage {
        let service = PhotoRenderService()
        let source = try await service.inspectSource(at: KernelGolden.referencePhoto)
        return try await service.renderPreview(source: source, recipe: recipe, maximumDimension: size)
    }

    /// AC-9.
    @Test func groupsOneAndTwoMatchTheirGolden() async throws {
        let picture = try await render(Self.groupsOneAndTwo, size: 512)
        try KernelGolden.checkPicture(picture, named: "pipeline-groups-1-2")
    }

    /// AC-3. Two masks in the top-left corner and a colour edit in the middle
    /// leave the opposite corner exactly as the colour edit alone leaves it —
    /// a colour kernel applied to part of the frame must not reach the rest.
    @Test func editsInOneCornerLeaveTheFarCornerAlone() async throws {
        var middle = PhotoMaskComponent(kind: .radialGradient)
        middle.center = NormalizedPoint(x: 0.5, y: 0.5)
        middle.radiusX = 0.15
        middle.radiusY = 0.15
        var centreMask = PhotoMask(name: "Centre", component: middle)
        centreMask.adjustments.saturation = 0.8
        var base = PhotoEditRecipe()
        base.color.mixer.orange.hue = 0.4
        base.masks = [centreMask]

        var corner = base
        for (index, luminance) in [(0, 0.3), (1, 0.6)] {
            var window = PhotoMaskComponent(kind: .radialGradient)
            window.center = NormalizedPoint(x: 0.125, y: 0.125)
            window.radiusX = 0.1
            window.radiusY = 0.1
            var band = PhotoMaskComponent(kind: .luminanceRange, operation: .subtract)
            band.luminanceMinimum = luminance
            band.luminanceMaximum = 1
            var mask = PhotoMask(name: "Corner \(index)", component: window)
            mask.components.append(band)
            mask.adjustments.exposure = 1
            corner.masks.append(mask)
        }

        let edited = try await render(corner, size: 256)
        let reference = try await render(base, size: 256)
        let a = try KernelGolden.bytes(of: edited)
        let b = try KernelGolden.bytes(of: reference)
        let width = edited.width
        #expect(width == reference.width)
        // The 32×32 block around (0.875, 0.875), top row first.
        var worst = 0
        for y in 208..<240 {
            for x in 208..<240 {
                for channel in 0..<4 {
                    let index = (y * width + x) * 4 + channel
                    worst = max(worst, abs(Int(a[index]) - Int(b[index])))
                }
            }
        }
        #expect(worst <= 1, "far corner moved by \(worst)/255")
        // And the corner itself did change, so the masks are really there.
        var near = 0
        for y in 16..<48 {
            for x in 16..<48 {
                let index = (y * width + x) * 4
                near = max(near, abs(Int(a[index]) - Int(b[index])))
            }
        }
        #expect(near > 8, "the corner masks did nothing")
        try KernelGolden.checkPicture(edited, named: "pipeline-far-corner")
    }

    /// A synthetic 1080p frame: a hue sweep across, brightness down in 32
    /// steps (so the stored golden compresses), moving with `frame` so each
    /// frame keys differently.
    static func videoFrame(_ frame: Int) throws -> CIImage {
        let width = 1920, height = 1080
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let value = 0.15 + 0.85 * Float(y * 32 / height) / 31
            for x in 0..<width {
                let hue = (Float((x + frame * 12) % width) / Float(width))
                let h = hue * 6
                let f = h - h.rounded(.down)
                let rgb: (Float, Float, Float) = switch Int(h) % 6 {
                case 0: (1, f, 0)
                case 1: (1 - f, 1, 0)
                case 2: (0, 1, f)
                case 3: (0, 1 - f, 1)
                case 4: (f, 0, 1)
                default: (1, 0, 1 - f)
                }
                let saturation: Float = 0.7
                let offset = (y * width + x) * 4
                bytes[offset] = UInt8(((1 - saturation + saturation * rgb.0) * value * 255).rounded())
                bytes[offset + 1] = UInt8(((1 - saturation + saturation * rgb.1) * value * 255).rounded())
                bytes[offset + 2] = UInt8(((1 - saturation + saturation * rgb.2) * value * 255).rounded())
            }
        }
        return CIImage(
            bitmapData: Data(bytes),
            bytesPerRow: width * 4,
            size: CGSize(width: width, height: height),
            format: .RGBA8,
            colorSpace: nil
        )
    }

    static var videoMasks: [PhotoMask] {
        var tone = PhotoMaskComponent(kind: .luminanceRange)
        tone.luminanceMinimum = 0.35
        tone.luminanceMaximum = 0.8
        tone.feather = 0.4
        var lifted = PhotoMask(name: "Mids", component: tone)
        lifted.adjustments.exposure = 0.6
        var hue = PhotoMaskComponent(kind: .colorRange)
        hue.sampledRed = 0.3
        hue.sampledGreen = 0.5
        hue.sampledBlue = 0.95
        hue.colorTolerance = 0.35
        var blues = PhotoMask(name: "Blues", component: hue)
        blues.adjustments.saturation = -0.7
        return [lifted, blues]
    }

    /// AC-10. Frames 1, 60 and 120 of a 1080p clip through both video keys.
    @Test(arguments: [1, 60, 120])
    func videoMaskFrameMatchesItsGolden(_ frame: Int) throws {
        let input = try Self.videoFrame(frame)
        let output = VideoMaskRenderer.apply(Self.videoMasks, to: input)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let picture = try #require(
            KernelGolden.context.createCGImage(output, from: input.extent, format: .RGBA8, colorSpace: space)
        )
        try KernelGolden.checkPicture(picture, named: "video-frame-\(frame)")
    }
}
