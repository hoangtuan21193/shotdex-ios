import Foundation
import ShotDexKit

/// What the share sheet says and offers for one share (FS-08.06 §4): the
/// line that names the metadata level in force, and the app's own rows that
/// switch this one share to another level. Pure, so the wording and the
/// choice of rows are tested without a share sheet.
struct ShareBatchPlan: Equatable, Sendable {
    /// The level this share is prepared at.
    let level: MetadataLevel
    /// Photos in the share (Live Photos count once: their still).
    let photoCount: Int
    /// Videos in the share; they go as they are at every level.
    let videoCount: Int

    /// The one-shot rows, in order: the two levels that are not in force.
    /// Choosing one changes this share only, never Settings.
    var rows: [MetadataLevel] {
        guard photoCount > 0 else { return [] }
        return MetadataLevel.allCases.filter { $0 != level }
    }

    /// The share sheet header's line for the level in force.
    var subtitle: Subtitle {
        switch level {
        case .all: .allMetadata
        case .noLocation: .locationRemoved
        case .noMetadata: .metadataRemoved
        }
    }

    /// Whether the header also says videos keep their metadata: only when
    /// the share has a video and the level removes something (spec §5).
    var notesVideosKeepMetadata: Bool { videoCount > 0 && level != .all }

    enum Subtitle: Equatable, Sendable {
        case allMetadata, locationRemoved, metadataRemoved
    }
}
