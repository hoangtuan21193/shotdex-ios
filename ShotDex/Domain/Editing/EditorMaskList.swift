import Foundation
import ShotDexKit

/// The Mask tool's list (FS-03.13c §2), top to bottom: every mask, and under
/// the selected one its areas and the three ways to add one; New Mask last.
enum EditorMaskListRow: Hashable {
    case mask(UUID)
    case area(mask: UUID, component: UUID)
    case addArea(MaskBlendOperation)
    case newMask

    static func rows(masks: [PhotoMask], selected: UUID?) -> [EditorMaskListRow] {
        var rows: [EditorMaskListRow] = []
        for mask in masks {
            rows.append(.mask(mask.id))
            guard mask.id == selected else { continue }
            rows += mask.components.map { .area(mask: mask.id, component: $0.id) }
            rows += MaskBlendOperation.allCases.map { .addArea($0) }
        }
        rows.append(.newMask)
        return rows
    }

    /// "Add area" · "Subtract area" · "Intersect area".
    static func title(of operation: MaskBlendOperation) -> String {
        "\(operation.displayName) area"
    }

    /// The area grid's title: "Add to Mask 1", "Subtract from Mask 1",
    /// "Intersect with Mask 1".
    static func chooserTitle(for operation: MaskBlendOperation, maskName: String) -> String {
        switch operation {
        case .add: "Add to \(maskName)"
        case .subtract: "Subtract from \(maskName)"
        case .intersect: "Intersect with \(maskName)"
        }
    }
}
