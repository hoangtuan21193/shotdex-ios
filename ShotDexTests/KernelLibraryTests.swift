import CoreImage
import Foundation
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-16 AC-5, AC-6, AC-7 — the Metal kernels load, from the right bundle,
/// and a missing one leaves the picture alone.
struct KernelLibraryTests {

    /// AC-5. Every kernel the renderers use, by the property they read it
    /// from. A function renamed on one side and not the other is `nil` here.
    @Test func everyKernelLoads() {
        let kernels: [(String, CIKernel?)] = [
            ("addMask", PhotoRenderService.addMaskKernel),
            ("subtractMask", PhotoRenderService.subtractMaskKernel),
            ("invertMask", PhotoRenderService.invertMaskKernel),
            ("luminanceMask", PhotoRenderService.luminanceMaskKernel),
            ("colorMask", PhotoRenderService.colorMaskKernel),
            ("edgeMask", PhotoRenderService.edgeMaskKernel),
            ("hslMixer", PhotoRenderService.hslMixerKernel),
            ("pointColor", PhotoRenderService.pointColorKernel),
            ("colorGrade", PhotoRenderService.colorGradeKernel),
            ("vignette", PhotoRenderService.vignetteKernel),
            ("lensWarp", PhotoRenderService.lensWarpKernel),
            ("noiseResidual", PhotoRenderService.noiseResidualKernel),
            ("noiseDetail", PhotoRenderService.noiseDetailKernel),
            ("healRing", PhotoRenderService.healingRingKernel),
            ("healWeight", PhotoRenderService.healingWeightKernel),
            ("healBlend", PhotoRenderService.healingBlendKernel),
            ("focusDecision", PhotoStackRenderer.decisionKernel),
            ("focusPeak", PhotoStackRenderer.peakKernel),
            ("focusWeightedColour", PhotoStackRenderer.weightedColourKernel),
            ("focusWeightedTotal", PhotoStackRenderer.weightedTotalKernel),
            ("focusWeightedResolve", PhotoStackRenderer.weightedResolveKernel),
            ("focusLaplacian", PhotoStackRenderer.laplacianKernel),
            ("focusWeightedAccumulate", PhotoStackRenderer.weightedAccumulateKernel),
            ("focusWeightedAlphaResolve", PhotoStackRenderer.weightedAlphaResolveKernel),
            ("panoramaWarp", PanoramaCIBlender.warpKernel),
            ("panoramaRamp", PanoramaCIBlender.rampKernel),
            ("panoramaAccumulateColour", PanoramaCIBlender.accumulateColourKernel),
            ("panoramaAccumulateWeight", PanoramaCIBlender.accumulateWeightKernel),
            ("panoramaMaximum", PanoramaCIBlender.maximumKernel),
            ("panoramaMask", PanoramaCIBlender.maskKernel),
            ("panoramaDifference", PanoramaCIBlender.differenceKernel),
            ("panoramaGain", PanoramaCIBlender.gainKernel),
            ("panoramaBand", PanoramaCIBlender.bandKernel),
            ("panoramaBandWeight", PanoramaCIBlender.bandWeightKernel),
            ("panoramaSum", PanoramaCIBlender.sumKernel),
            ("panoramaCoverage", PanoramaCIBlender.coverageKernel),
            ("panoramaResolve", PanoramaCIBlender.resolveKernel),
            ("panoramaBoundaryWarp", PanoramaBoundaryWarp.warpKernel),
            ("luminanceKey", VideoMaskRenderer.luminanceKeyKernel),
            ("colorKey", VideoMaskRenderer.colorKeyKernel),
        ]
        #expect(kernels.count == 40)
        for (name, kernel) in kernels {
            #expect(kernel != nil, "\(name) did not load")
        }
    }

    /// AC-8. The point-color kernel has eight slots written into its
    /// signature; the model may not offer a ninth it cannot render.
    @Test func pointColorSlotsMatchTheModel() {
        #expect(PointColorAdjustment.maximumCount == 8)
    }

    /// AC-6. The kit's kernels ship inside the framework, and the app's own
    /// bundle cannot stand in for them.
    @Test func kitKernelsComeFromTheFrameworkBundle() throws {
        let framework = Bundle(for: PhotoStackRenderer.self)
        #expect(framework != Bundle.main)
        #expect(framework.bundleURL.pathExtension == "framework")
        #expect(framework.url(forResource: "default", withExtension: "metallib") != nil)

        var complaints: [String] = []
        let app = CoreImageKernelLibrary(bundle: .main)
        let fromApp = app.load("addMask", onMissing: { complaints.append($0) }) {
            try CIColorKernel(functionName: "addMask", fromMetalLibraryData: $0)
        }
        #expect(fromApp == nil)
        #expect(complaints.count == 1)
    }

    /// AC-7. What a release build does when a kernel is missing: no crash,
    /// `nil`, and the call sites hand the picture back untouched.
    @Test func aMissingKernelIsNilNotACrash() {
        var complaints: [String] = []
        let kernel = CoreImageKernelLibrary.kit.load("noSuchKernel", onMissing: { complaints.append($0) }) {
            try CIColorKernel(functionName: "noSuchKernel", fromMetalLibraryData: $0)
        }
        #expect(kernel == nil)
        #expect(complaints.count == 1)
        #expect(complaints.first?.contains("noSuchKernel") == true)
    }

    // MARK: AC-7 at the call sites

    // The kernels load on the simulator, so the `nil` a release build would
    // get is handed in. Each check also runs the real kernel, to prove the
    // edit reaches the kernel at all and the untouched picture is the
    // fallback's doing, not an identity edit's.

    private static func input() throws -> CIImage {
        KernelGolden.image(try KernelGolden.photo(phase: 0))
    }

    private static func largestDifference(_ a: CIImage, _ b: CIImage) -> Float {
        zip(KernelGolden.pixels(of: a), KernelGolden.pixels(of: b)).map { abs($0 - $1) }.max() ?? 0
    }

    private func expectFallback(
        _ input: CIImage,
        withKernel: CIImage,
        withoutKernel: CIImage,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(Self.largestDifference(withKernel, input) > 4.0 / 255, sourceLocation: sourceLocation)
        #expect(Self.largestDifference(withoutKernel, input) == 0, sourceLocation: sourceLocation)
    }

    @Test func colorStagesLeaveThePictureAloneWithoutTheirKernels() throws {
        let input = try Self.input()

        var mixer = ColorMixerAdjustments()
        mixer.orange.saturation = 0.8
        mixer.blue.hue = -0.6
        expectFallback(
            input,
            withKernel: PhotoRenderService.applyMixer(mixer, to: input),
            withoutKernel: PhotoRenderService.applyMixer(mixer, to: input, kernel: nil)
        )

        let points = [
            PointColorAdjustment(
                referenceHue: 30, referenceSaturation: 0.6, referenceValue: 0.7,
                hueShift: -0.8, saturationShift: 0.4, range: 1
            ),
        ]
        expectFallback(
            input,
            withKernel: PhotoRenderService.applyPointColors(points, to: input),
            withoutKernel: PhotoRenderService.applyPointColors(points, to: input, kernel: nil)
        )

        var grading = ColorGradingAdjustments()
        grading.shadows.hue = 220
        grading.shadows.saturation = 0.8
        grading.global.luminance = 0.3
        expectFallback(
            input,
            withKernel: PhotoRenderService.applyGrading(grading, to: input),
            withoutKernel: PhotoRenderService.applyGrading(grading, to: input, kernel: nil)
        )
    }

    @Test func shapedVignetteLeavesThePictureAloneWithoutItsKernel() throws {
        let input = try Self.input()
        var adjustments = PhotoAdjustments()
        adjustments.vignette = -0.8
        adjustments.vignetteRoundness = 0.5
        adjustments.vignetteHighlights = 0.4
        expectFallback(
            input,
            withKernel: PhotoRenderService.applyVignette(adjustments, to: input),
            withoutKernel: PhotoRenderService.applyVignette(adjustments, to: input, kernel: nil)
        )
    }

    /// The spec's own wording: a picture with masks. A video mask whose key
    /// cannot run has no matte, so it is skipped rather than applied to the
    /// whole frame.
    @Test func videoMasksLeaveTheFrameAloneWithoutTheirKeys() throws {
        let input = try Self.input()
        let masks = KernelPipelineGoldenTests.videoMasks
        expectFallback(
            input,
            withKernel: VideoMaskRenderer.apply(masks, to: input),
            withoutKernel: VideoMaskRenderer.apply(
                masks,
                to: input,
                kernels: .init(luminanceKey: nil, colorKey: nil)
            )
        )
    }
}

/// Kernel branches the golden arguments never reach, checked against what
/// the branch must do rather than against a recording.
struct KernelBranchTests {

    /// `panoramaWarp` with the frame turned half a turn from the canvas:
    /// every canvas ray is behind the source camera, so every pixel must take
    /// the sentinel. The sentinel lands far outside the frame, where Core
    /// Image's sampler reads the frame's own border — so what it guarantees
    /// is no *weight*: the blender warps `panoramaRamp` alongside the colour,
    /// and the ramp is 0 at the border. Without the `local.z` check the
    /// division flips the ray back onto the sensor and the middle of the
    /// frame gets a say. Facing forward, the same frame does.
    @Test(arguments: [Float(0), 1, 2])
    func panoramaWarpGivesNoWeightBehindTheCamera(_ kind: Float) throws {
        let extent = KernelGolden.extent
        let ramp = try #require(PanoramaCIBlender.rampKernel?.apply(
            extent: extent,
            roiCallback: { _, rect in rect },
            arguments: [Float(48), Float(48)]
        ))
        func weights(_ m0: CIVector, _ m2: CIVector) throws -> [Float] {
            let output = try #require(PanoramaCIBlender.warpKernel?.apply(
                extent: extent,
                roiCallback: { _, _ in extent },
                image: ramp,
                arguments: [
                    CIVector(x: -24, y: -24), Float(48), Float(40), kind,
                    m0, CIVector(x: 0, y: 1, z: 0), m2,
                    Float(40), CIVector(x: 23.5, y: 23.5), CIVector(x: 48, y: 48), Float(0),
                ]
            ))
            let pixels = KernelGolden.pixels(of: output)
            return stride(from: 0, to: pixels.count, by: 4).map { pixels[$0] }
        }

        let behind = try weights(CIVector(x: -1, y: 0, z: 0), CIVector(x: 0, y: 0, z: -1))
        #expect(behind.max() ?? 1 < 0.001)

        let ahead = try weights(CIVector(x: 1, y: 0, z: 0), CIVector(x: 0, y: 0, z: 1))
        #expect(ahead[24 * KernelGolden.size + 24] > 0.5)
    }
}
