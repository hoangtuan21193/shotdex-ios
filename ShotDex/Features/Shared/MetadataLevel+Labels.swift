import Foundation
import ShotDexKit

extension MetadataLevel {
    /// The level's name, the same in Settings, Share, Save and Resize
    /// (FS-08.06 §6).
    var title: LocalizedStringResource {
        switch self {
        case .all: "All Metadata"
        case .noLocation: "No Location"
        case .noMetadata: "No Metadata"
        }
    }
}
