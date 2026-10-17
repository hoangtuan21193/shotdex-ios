import Foundation

/// A named set of what every imported photo carries (FS-20 §6): written to
/// a `.xmp` beside each copy, never into the photo.
struct IngestMetadataPreset: Codable, Hashable, Sendable {
    var name = ""
    var creator = ""
    var copyright = ""
    var keywords: [String] = []

    var isEmpty: Bool { creator.isEmpty && copyright.isEmpty && keywords.isEmpty }

    /// The sidecar patch for one photo: the preset's fields that are filled,
    /// and the day it was taken (FS-20 §7.3).
    func patch(captureDate: Date?) -> XMPPatch {
        var patch = XMPPatch()
        if !creator.isEmpty { patch.creator = .set(creator) }
        if !copyright.isEmpty { patch.rights = .set(copyright) }
        if !keywords.isEmpty { patch.keywords = .set(keywords) }
        if let captureDate {
            patch.createDate = .set(captureDate.formatted(.iso8601))
        }
        return patch
    }
}

/// What a card import remembers for next time (FS-20 §6): where photos go,
/// the folders and names they get, the backup, the metadata, Eject.
struct IngestSettings: Codable, Equatable, Sendable {
    /// A folder source (FS-19).
    var destinationSourceId: String?
    var folders = IngestFolderTemplate.yearDate
    var backsUp = false
    /// The backup folder's bookmark, as Export remembers folders.
    var backupFolder: ExportFolder?
    var nameTemplate = IngestSettings.dateAndNumber.pattern
    var metadata = IngestMetadataPreset()
    var ejectsAfterImport = true

    /// The default (plan Q6): `{date}_{originalNumber}`.
    static let dateAndNumber = FileNameTemplate("{date}_{originalNumber}")
    static let namePresets: [FileNameTemplate] = [dateAndNumber, .originalName, .dateOriginal]

    init() {}

    /// Lossy, like Export's settings: a field that will not decode falls
    /// back to its default, the others survive.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = IngestSettings()
        destinationSourceId = try? container.decodeIfPresent(String.self, forKey: .destinationSourceId)
        folders = (try? container.decode(IngestFolderTemplate.self, forKey: .folders)) ?? defaults.folders
        backsUp = (try? container.decode(Bool.self, forKey: .backsUp)) ?? defaults.backsUp
        backupFolder = try? container.decodeIfPresent(ExportFolder.self, forKey: .backupFolder)
        nameTemplate = (try? container.decode(String.self, forKey: .nameTemplate)) ?? defaults.nameTemplate
        metadata = (try? container.decode(IngestMetadataPreset.self, forKey: .metadata)) ?? defaults.metadata
        ejectsAfterImport = (try? container.decode(Bool.self, forKey: .ejectsAfterImport)) ?? defaults.ejectsAfterImport
    }

    var template: FileNameTemplate { FileNameTemplate(nameTemplate) }
}
