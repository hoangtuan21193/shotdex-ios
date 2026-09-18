import Foundation

/// Whether an asset is a still photo or a video.
///
/// Backed by `photo_metadata.mediaType`, which stores `PHAssetMediaType.rawValue`
/// (1 = image, 2 = video). The raw value here is a string instead so the kind
/// round-trips readably through the smart-album JSON in `smart_albums.criteria`
/// and drops straight into `RuleField.choiceValues`; `storedValue` bridges to
/// the column.
enum MediaKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case photo
    case video

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .photo: "Photo"
        case .video: "Video"
        }
    }

    /// The value held by `photo_metadata.mediaType`.
    var storedValue: Int {
        switch self {
        case .photo: 1
        case .video: 2
        }
    }

    /// Nil for the media types the library never indexes (audio).
    init?(storedValue: Int) {
        switch storedValue {
        case 1: self = .photo
        case 2: self = .video
        default: return nil
        }
    }
}
