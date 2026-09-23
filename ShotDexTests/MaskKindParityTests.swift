import CoreImage
import Foundation
import Photos
import Testing
@testable import ShotDexKit
@testable import ShotDex

/// FS-03.11 AC-10 and AC-11 — Background and Depth Range masks.
struct MaskKindParityTests {

    /// AC-10. Background is Subject inverted, not a new kind: the renderer
    /// already knows how to invert, so the sheet row only has to ask for it.
    @Test func backgroundIsSubjectInverted() {
        let option = EditorNewMaskOption.background
        #expect(option.componentKind == .subject)
        #expect(option.startsInverted)
        #expect(option.title == "Background")
        for other in EditorNewMaskOption.allCases where other != .background {
            #expect(!other.startsInverted, "\(other) must not start inverted")
        }
    }

    /// AC-10. Choosing Background leaves an inverted Subject mask named for it.
    @MainActor @Test func addingBackgroundMaskInvertsSubject() throws {
        let controller = PhotoEditorController(
            asset: PHAsset(),
            sourceAlbum: nil,
            service: PhotoEditingService()
        )
        controller.addMask(option: .background)
        let mask = try #require(controller.recipe.masks.last)
        #expect(mask.isInverted)
        #expect(mask.components.map(\.kind) == [.subject])
        #expect(mask.name.hasPrefix("Background"))

        controller.addMask(option: .subject)
        #expect(controller.recipe.masks.last?.isInverted == false)
    }

    /// AC-10. The inverted mask and the one it inverts cover the frame
    /// exactly once between them — Background is the complement of Subject.
    @Test func invertedMaskIsTheComplement() throws {
        let extent = CGRect(x: 0, y: 0, width: 64, height: 1)
        let subject = CIFilter(
            name: "CILinearGradient",
            parameters: [
                "inputPoint0": CIVector(x: 0, y: 0),
                "inputPoint1": CIVector(x: 64, y: 0),
                "inputColor0": CIColor(red: 0, green: 0, blue: 0),
                "inputColor1": CIColor(red: 1, green: 1, blue: 1),
            ]
        )!.outputImage!.cropped(to: extent)
        let kernel = try #require(PhotoRenderService.invertMaskKernel)
        let background = try #require(kernel.apply(extent: extent, arguments: [subject]))

        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        func row(_ image: CIImage) -> [Float] {
            var pixels = [Float](repeating: 0, count: 64 * 4)
            context.render(
                image,
                toBitmap: &pixels,
                rowBytes: 64 * 4 * MemoryLayout<Float>.size,
                bounds: extent,
                format: .RGBAf,
                colorSpace: nil
            )
            return stride(from: 0, to: pixels.count, by: 4).map { pixels[$0] }
        }
        for (a, b) in zip(row(subject), row(background)) {
            #expect(abs(a + b - 1) < 0.01)
        }
    }

    /// AC-11. Every mask kind is reachable from the sheet — a kind added to the
    /// model and forgotten in the chooser is a feature nobody can find.
    @Test func everyComponentKindHasASheetRow() {
        let reachable = Set(EditorNewMaskOption.allCases.map(\.componentKind))
        #expect(reachable == Set(PhotoMaskComponentKind.allCases))
    }

    /// AC-11. Depth Range is offered only when the photo has a depth map, and
    /// says why when it is not.
    @Test func depthRangeIsGatedOnDepth() {
        #expect(EditorNewMaskOption.depthRange.unavailableReason(hasDepth: true) == nil)
        #expect(EditorNewMaskOption.depthRange.unavailableReason(hasDepth: false) != nil)
        for option in EditorNewMaskOption.allCases where option != .depthRange {
            #expect(option.unavailableReason(hasDepth: false) == nil, "\(option)")
        }
    }

    /// AC-11. The raw map is stretched to 0…1 by its own range first: a map
    /// that only spans 0.3…0.8 still has its nearest point at 1.
    @Test func disparityIsStretchedToItsOwnRange() throws {
        let extent = CGRect(x: 0, y: 0, width: 100, height: 1)
        let raw = CIFilter(
            name: "CILinearGradient",
            parameters: [
                "inputPoint0": CIVector(x: 0, y: 0),
                "inputPoint1": CIVector(x: 100, y: 0),
                "inputColor0": CIColor(red: 0.3, green: 0.3, blue: 0.3),
                "inputColor1": CIColor(red: 0.8, green: 0.8, blue: 0.8),
            ]
        )!.outputImage!.cropped(to: extent)
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        let normalized = PhotoRenderService.normalizedDisparity(raw, context: context)
        var pixels = [Float](repeating: 0, count: 100 * 4)
        context.render(normalized, toBitmap: &pixels, rowBytes: 100 * 16, bounds: extent, format: .RGBAf, colorSpace: nil)
        #expect(pixels[0] < 0.03, "far end at 0: \(pixels[0])")
        #expect(pixels[99 * 4] > 0.97, "near end at 1: \(pixels[99 * 4])")
    }

    /// AC-11. The band selects what lies inside Near…Far on the normalized map
    /// and nothing outside it.
    @Test func depthRangeSelectsTheBand() throws {
        let extent = CGRect(x: 0, y: 0, width: 100, height: 1)
        // Left edge far (0), right edge near (1).
        let disparity = CIFilter(
            name: "CILinearGradient",
            parameters: [
                "inputPoint0": CIVector(x: 0, y: 0),
                "inputPoint1": CIVector(x: 100, y: 0),
                "inputColor0": CIColor(red: 0, green: 0, blue: 0),
                "inputColor1": CIColor(red: 1, green: 1, blue: 1),
            ]
        )!.outputImage!.cropped(to: extent)

        var component = PhotoMaskComponent(kind: .depthRange)
        component.depthMinimum = 0.5
        component.depthMaximum = 1.0
        component.feather = 0
        let mask = try #require(
            PhotoRenderService.depthRangeMask(component, disparity: disparity, extent: extent)
        )

        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        var pixels = [Float](repeating: 0, count: 100 * 4)
        context.render(
            mask,
            toBitmap: &pixels,
            rowBytes: 100 * 4 * MemoryLayout<Float>.size,
            bounds: extent,
            format: .RGBAf,
            colorSpace: nil
        )
        func value(at x: Int) -> Float { pixels[x * 4] }
        #expect(value(at: 90) > 0.95, "near subject is in the band")
        #expect(value(at: 10) < 0.05, "far background is outside it")
    }
}
