import Foundation
import ShotDexKit

/// Save as Copy for a file photo (FS-18 03 §5): the edit rendered once and
/// written as `‹name› (edited).jpg` beside the original, which is never
/// touched. Written under a hidden part name and moved into place, so a
/// failure never leaves half a JPEG in the user's folder.
struct EditedCopyWriter: Sendable {
    let renderer: PhotoRenderService

    init(renderer: PhotoRenderService = PhotoRenderService()) {
        self.renderer = renderer
    }

    /// - Returns: the new file.
    func write(_ recipe: PhotoEditRecipe, of original: URL, format: PhotoOutputFormat,
               quality: Double = FileExportQuality.defaultValue) async throws -> URL {
        let folder = original.deletingLastPathComponent()
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let fileExtension = OutputNaming.copyExtension(of: original.lastPathComponent, format: format,
                                                       encodesHEIC: KitExportRenderer.supportsHEICEncoding)
        let name = OutputNaming.editedCopy(of: original.lastPathComponent, fileExtension: fileExtension, existing: existing)
        let target = folder.appendingPathComponent(name)
        let part = folder.appendingPathComponent(".\(name).shotdex-part")
        let source = try await renderer.inspectSource(at: original)
        let result = try await renderer.render(source: source, recipe: recipe)
        try Task.checkCancellation()
        do {
            try await renderer.write(result, to: part, format: fileExtension == "heic" ? .heic : .jpeg,
                               quality: quality, metadata: .all)
            try FileManager.default.moveItem(at: part, to: target)
        } catch {
            try? FileManager.default.removeItem(at: part)
            throw error
        }
        return target
    }
}
