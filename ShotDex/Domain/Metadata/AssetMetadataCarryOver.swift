import Foundation
import ShotDexKit

/// What a new asset made from a photo — Save Copy, Paste Edits as copies,
/// Resize — takes from the original asset, by level (FS-08.06 §3–4). The
/// library's own date and place sit on the asset, not in the file, so the
/// level has to reach the creation request as well as the file. Save Changes
/// makes no new asset and touches neither (AC-17).
struct AssetMetadataCarryOver: Equatable, Sendable {
    /// The new asset takes the original's capture date.
    let keepsDate: Bool
    /// The new asset takes the original's location.
    let keepsLocation: Bool
}

extension AssetMetadataCarryOver {
    init(level: MetadataLevel) {
        switch level {
        case .all:
            keepsDate = true
            keepsLocation = true
        case .noLocation:
            keepsDate = true
            keepsLocation = false
        case .noMetadata:
            // The capture date is metadata like any other: the copy is dated
            // the day it was made.
            keepsDate = false
            keepsLocation = false
        }
    }
}
