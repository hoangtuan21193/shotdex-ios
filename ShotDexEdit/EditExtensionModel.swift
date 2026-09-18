import CoreImage
import Photos
import ShotDexKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// State of one editing session inside Photos: the photo, the recipe being
/// built, and the preview that follows it.
@MainActor
@Observable
final class EditExtensionModel {
    /// Preview edge. Big enough to judge a look on a phone screen, small enough
    /// that a slider stays live in an extension's memory budget.
    private static let previewEdge: CGFloat = 1_200

    private(set) var preview: UIImage?
    private(set) var isRendering = false
    private(set) var isReady = false
    var recipe = PhotoEditRecipe.identity {
        didSet { scheduleRender() }
    }

    private let renderer = PhotoRenderService()
    private var source: PhotoRenderSourceInfo?
    private var renderTask: Task<Void, Never>?

    /// The looks offered, in the order the app's Filters tab shows them.
    let looks = PhotoFilter.allCases

    func begin(with input: PHContentEditingInput, placeholder: UIImage) {
        preview = placeholder
        // An edit already on the photo is continued, not discarded: Photos only
        // hands this over after `canHandle` said the format is ours.
        if let data = input.adjustmentData?.data,
           let decoded = try? JSONDecoder().decode(PhotoEditRecipe.self, from: data) {
            recipe = decoded
        }
        guard let url = input.fullSizeImageURL else { return }
        source = PhotoRenderSourceInfo(
            url: url,
            type: UTType(filenameExtension: url.pathExtension) ?? .jpeg,
            pixelWidth: Int(input.displaySizeImage?.size.width ?? 0),
            pixelHeight: Int(input.displaySizeImage?.size.height ?? 0),
            orientation: CGImagePropertyOrientation(rawValue: UInt32(input.fullSizeImageOrientation)) ?? .up,
            isRAW: input.uniformTypeIdentifier.map { UTType($0)?.conforms(to: .rawImage) ?? false } ?? false,
            properties: [:]
        )
        isReady = true
        scheduleRender()
    }

    // MARK: Preview

    /// Coalesced: a slider drag asks for a render on every frame, and the
    /// renderer is slower than the finger.
    private func scheduleRender() {
        guard isReady, let source else { return }
        renderTask?.cancel()
        let recipe = recipe
        let renderer = renderer
        renderTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.isRendering = true }
            let image = await Self.renderImage(
                renderer: renderer,
                source: source,
                recipe: recipe,
                maximumDimension: Self.previewEdge
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.isRendering = false
                if let image { self?.preview = image }
            }
        }
    }

    private static func renderImage(
        renderer: PhotoRenderService,
        source: PhotoRenderSourceInfo,
        recipe: PhotoEditRecipe,
        maximumDimension: CGFloat?
    ) async -> UIImage? {
        guard let result = try? await renderer.render(
            source: source,
            recipe: recipe,
            maximumDimension: maximumDimension
        ) else { return nil }
        let context = CIContext()
        guard let cgImage = context.createCGImage(result.image, from: result.image.extent)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: Save

    /// Renders at full size and hands Photos the result plus the recipe that
    /// produced it, so the edit stays reversible and re-openable.
    nonisolated func renderOutput(for input: PHContentEditingInput) async -> PHContentEditingOutput? {
        let (source, recipe) = await MainActor.run { (self.source, self.recipe) }
        guard let source else { return nil }
        let output = PHContentEditingOutput(contentEditingInput: input)
        output.adjustmentData = PHAdjustmentData(
            formatIdentifier: PhotoEditRecipe.formatIdentifier,
            formatVersion: PhotoEditRecipe.formatVersion,
            data: (try? JSONEncoder().encode(recipe)) ?? Data()
        )
        guard let result = try? await renderer.render(source: source, recipe: recipe),
              let data = Self.encodeJPEG(result)
        else { return nil }
        do {
            try data.write(to: output.renderedContentURL, options: .atomic)
            return output
        } catch {
            return nil
        }
    }

    private nonisolated static func encodeJPEG(_ result: PhotoRenderResult) -> Data? {
        let context = CIContext()
        return context.jpegRepresentation(
            of: result.image,
            colorSpace: result.colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95]
        )
    }
}
