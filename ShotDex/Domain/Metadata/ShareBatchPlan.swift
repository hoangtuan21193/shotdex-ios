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
    /// RAW files in the share — originals ImageIO cannot write, so their
    /// metadata cannot be removed (spec §5).
    var rawCount = 0
    /// Of those, the ones iOS on this device cannot decode at all
    /// (FS-03.04b): there is no JPEG to make of them.
    var unreadableRAWCount = 0
    /// RAW files the user chose to share as they are, location and all.
    var rawSharedAsIsCount = 0
    /// HEIC photos going out as JPEG because the level is No Metadata.
    var heicAsJPEGCount = 0
    /// The watermark this share stamps, by name (FS-05.04 §4); nil for none.
    var watermarkName: String?

    /// The one-shot rows, in order: the two levels that are not in force.
    /// Choosing one changes this share only, never Settings.
    var rows: [MetadataLevel] {
        guard photoCount + rawCount > 0 else { return [] }
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

    /// The header's second line, when something in the share keeps what
    /// the level names as removed: videos always do, RAW files do when the
    /// user chose Share RAW with Location. Without it the header would say
    /// "Location removed" over a RAW that still carries one.
    var keepsNote: KeepsNote? {
        guard level != .all else { return nil }
        switch (videoCount > 0, rawSharedAsIsCount > 0) {
        case (true, true): return .videosAndRAW
        case (true, false): return .videos
        case (false, true): return .raw
        case (false, false): return nil
        }
    }

    enum KeepsNote: Equatable, Sendable { case videos, raw, videosAndRAW }

    /// Whether the header's second line also says HEIC photos went as JPEG,
    /// so the change of format is never silent.
    var notesHEICAsJPEG: Bool { heicAsJPEGCount > 0 }

    /// Whether the share stops once, before anything is gathered, to ask
    /// what to do with its RAW files: only below All Metadata, where a RAW
    /// would otherwise leave with what the level promised to remove.
    var asksAboutRAW: Bool { rawCount > 0 && level != .all }

    /// The second line's watermark segment, first among the notes:
    /// "Watermark: Credit".
    var watermarkNote: String? {
        guard let watermarkName, photoCount + rawCount > 0 else { return nil }
        return WatermarkCopy.watermarkNote(watermarkName)
    }

    /// Whether Share as JPEG can be offered: not when a RAW in the share
    /// cannot be decoded on this device.
    var offersJPEG: Bool { unreadableRAWCount == 0 }

    /// What the RAW question asks, by level and count.
    var rawQuestion: RAWQuestion {
        RAWQuestion(count: rawCount, removes: level == .noMetadata ? .metadata : .location)
    }

    struct RAWQuestion: Equatable, Sendable {
        let count: Int
        let removes: Removed
        enum Removed: Equatable, Sendable { case location, metadata }
    }

    enum Subtitle: Equatable, Sendable {
        case allMetadata, locationRemoved, metadataRemoved
    }
}

/// The answer to the RAW question, for the whole share at once (spec §5).
enum RAWChoice: Equatable, Sendable {
    /// A full-size JPEG rendered from each RAW, at the share's level.
    case shareAsJPEG
    /// The RAW files as they are, location and all.
    case shareRAWWithLocation
    /// Leave the RAW files out; share the rest.
    case skip
}

