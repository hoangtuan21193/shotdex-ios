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
}
