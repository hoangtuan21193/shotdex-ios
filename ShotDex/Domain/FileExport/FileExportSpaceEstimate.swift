import Foundation
import ShotDexKit

/// Room needed before the first byte (FS-03.07b §9): Unmodified Original is
/// the originals' size; Current Version is the original's size times the
/// preset's share of its pixels. A destination that does not say how much is
/// free (some cloud providers) is not checked.
enum FileExportSpaceEstimate {
    static func neededBytes(_ plan: FileExportPlan, preset: ResizePreset, ids: Set<String>? = nil) -> Int64 {
        plan.writtenEntries
            .filter { ids?.contains($0.id) ?? true }
            .reduce(0) { total, entry in
                total + entry.outputs.reduce(0) { sum, output in
                    if let source = output.source { return sum + source.byteCount }
                    return sum + renderedBytes(entry.item, preset: preset)
                }
            }
    }

    /// A render's size: the original photo's bytes scaled by how many of its
    /// pixels the preset keeps — never more than all of them.
    static func renderedBytes(_ item: FileExportItem, preset: ResizePreset) -> Int64 {
        let photo = item.files.first { $0.role == .photo } ?? item.files.first
        let bytes = photo?.byteCount ?? 0
        guard item.pixelWidth > 0, item.pixelHeight > 0 else { return bytes }
        let target = preset.targetPixelSize(sourceWidth: item.pixelWidth, sourceHeight: item.pixelHeight)
        let ratio = min(1, Double(target.width * target.height) / Double(item.pixelWidth * item.pixelHeight))
        return Int64((Double(bytes) * ratio).rounded(.up))
    }

    /// Nil when it fits, or when the destination doesn't report free space.
    static func check(needed: Int64, free: Int64?) -> FileExportFailure? {
        guard let free, needed > free else { return nil }
        return .notEnoughSpace(needed: needed, free: free)
    }
}
