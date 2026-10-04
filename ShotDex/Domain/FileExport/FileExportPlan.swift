import Foundation

/// One file an asset is made of, as Export… sees it — nothing PhotoKit-shaped,
/// so the plan and the runner run in a unit test without a library.
struct FileExportSourceFile: Sendable, Hashable {
    enum Role: String, Sendable, Hashable {
        case photo
        /// The other half of a RAW+JPEG pair.
        case alternatePhoto
        case video
        /// The movie of a Live Photo.
        case pairedVideo
        case audio
        /// Renders of an edit made in Photos.
        case editedPhoto
        case editedVideo
        case editedPairedVideo

        /// What the camera or the import wrote — what Unmodified Original copies.
        var isOriginal: Bool {
            switch self {
            case .photo, .alternatePhoto, .video, .pairedVideo, .audio: true
            case .editedPhoto, .editedVideo, .editedPairedVideo: false
            }
        }
    }

    /// How the source finds it again (PhotoKit: the resource's type and name).
    let key: String
    /// The name it carries in Photos: `DSCF1000.RAF`, `FullSizeRender.jpg`.
    let filename: String
    let role: Role
    var isRAW = false
    var byteCount: Int64 = 0

    var fileExtension: String { (filename as NSString).pathExtension }
}

/// One picked asset, with what its file names are built from.
struct FileExportItem: Sendable, Hashable, Identifiable {
    enum Kind: String, Sendable, Hashable { case photo, livePhoto, video }

    /// The asset's local identifier.
    let id: String
    /// The original file name: `DSCF1000.RAF`.
    let filename: String
    let captureDate: Date
    var camera: String?
    var lens: String?
    let kind: Kind
    let files: [FileExportSourceFile]
    var pixelWidth = 0
    var pixelHeight = 0

    var originals: [FileExportSourceFile] { files.filter(\.role.isOriginal) }
    var hasEdit: Bool { files.contains { $0.role == .editedPhoto || $0.role == .editedVideo } }
    var originalBytes: Int64 { originals.reduce(0) { $0 + $1.byteCount } }

    var nameValues: FileNameValues {
        FileNameValues(original: (filename as NSString).deletingPathExtension, captureDate: captureDate, camera: camera, lens: lens)
    }
}

/// Every name of a batch, worked out before the first byte (FS-03.07b §5–6):
/// the order, `{seq}`, Date Folders, and what clashes with what is already in
/// the folder — read once, compared case-insensitively. Kept for the whole
/// run, so Export Remaining writes exactly the names planned.
struct FileExportPlan: Sendable, Equatable {
    struct Output: Sendable, Hashable {
        /// The file copied; nil for the one file a render makes.
        let source: FileExportSourceFile?
        /// The final name, extension included.
        let name: String
        /// Replace: an older file of this name goes once this one is written.
        let replaces: Bool
    }

    struct Entry: Sendable, Hashable, Identifiable {
        let item: FileExportItem
        /// 1-based, per asset, in export order.
        let sequence: Int
        /// Relative to the export folder: `""`, or `2026/2026-09-20`.
        let folder: String
        let outputs: [Output]
        /// Skip: a file of this name is already in the folder.
        let isSkipped: Bool

        var id: String { item.id }
    }

    let entries: [Entry]

    /// Files an existing one of the same name will be replaced by.
    var replaceCount: Int { entries.reduce(0) { $0 + $1.outputs.filter(\.replaces).count } }
    /// Assets left out because their name is taken (Skip).
    var skipCount: Int { entries.filter(\.isSkipped).count }
    var writtenEntries: [Entry] { entries.filter { !$0.isSkipped } }

    /// Export order: capture date, then original name.
    static func ordered(_ items: [FileExportItem]) -> [FileExportItem] {
        items.sorted { lhs, rhs in
            lhs.captureDate == rhs.captureDate
                ? lhs.filename.localizedStandardCompare(rhs.filename) == .orderedAscending
                : lhs.captureDate < rhs.captureDate
        }
    }

    /// The folders a batch writes into, relative to the export folder — the
    /// ones whose names have to be read before planning.
    static func folders(for items: [FileExportItem], dateFolders: Bool, timeZone: TimeZone = .current) -> [String] {
        guard dateFolders else { return [""] }
        return Array(Set(items.map { folder(for: $0, dateFolders: true, timeZone: timeZone) })).sorted()
    }

    static func folder(for item: FileExportItem, dateFolders: Bool, timeZone: TimeZone = .current) -> String {
        dateFolders ? ServerUploadPath.dayFolder(folder: "", captureDate: item.captureDate, timeZone: timeZone) : ""
    }

    /// The files an asset becomes. Unmodified Original: every original
    /// file, the Live Photo movie only when asked. Current Version: one
    /// render for a photo (a Live Photo is a still), the video itself for
    /// a video.
    static func sources(of item: FileExportItem, mode: FileExportMode, includesLivePhotoVideo: Bool) -> [FileExportSourceFile?] {
        switch mode {
        case .unmodifiedOriginal:
            return item.originals.filter { includesLivePhotoVideo || $0.role != .pairedVideo }
        case .currentVersion:
            guard item.kind == .video else { return [nil] }
            let current = item.files.first { $0.role == .editedVideo } ?? item.files.first { $0.role == .video }
            return [current]
        }
    }

    /// - Parameters:
    ///   - renderExtension: `jpg` or `heic` for the render of a photo.
    ///   - existing: the names already in each folder, read once.
    static func make(
        items: [FileExportItem],
        mode: FileExportMode,
        template: FileNameTemplate,
        policy: FileExportConflictPolicy,
        dateFolders: Bool,
        includesLivePhotoVideo: Bool,
        renderExtension: (FileExportItem) -> String,
        existing: [String: Set<String>],
        timeZone: TimeZone = .current
    ) -> FileExportPlan {
        let ordered = ordered(items)
        let width = FileNameTemplate.sequenceWidth(count: ordered.count)
        let inFolder: [String: Set<String>] = existing.mapValues { Set($0.map { $0.lowercased() }) }
        var assigned: [String: Set<String>] = [:]
        var entries: [Entry] = []
        for (index, item) in ordered.enumerated() {
            let sequence = index + 1
            let folder = folder(for: item, dateFolders: dateFolders, timeZone: timeZone)
            let base = template.baseName(for: item.nameValues, sequence: sequence, sequenceWidth: width, timeZone: timeZone)
            let sources = sources(of: item, mode: mode, includesLivePhotoVideo: includesLivePhotoVideo)
            // A video keeps the extension of its original, whichever version
            // of the movie goes; a render takes `jpg` or `heic`.
            let videoExtension = item.files.first { $0.role == .video }?.fileExtension
            let extensions = sources.map { source in
                guard let source else { return renderExtension(item) }
                return mode == .currentVersion ? (videoExtension ?? source.fileExtension) : source.fileExtension
            }
            let there = inFolder[folder, default: []]
            let mine = assigned[folder, default: []]
            func names(_ number: Int?) -> [String] {
                extensions.map { ext in
                    let stem = number.map { "\(base) (\($0))" } ?? base
                    return ext.isEmpty ? stem : "\(stem).\(ext)"
                }
            }
            var chosen = names(nil)
            let clashesInBatch = chosen.contains { mine.contains($0.lowercased()) }
            let clashesInFolder = chosen.contains { there.contains($0.lowercased()) }
            var isSkipped = false
            var replaces = Array(repeating: false, count: chosen.count)
            // Two photos of the batch never share a name, whatever the
            // policy: a run never writes over a file it has just written.
            if clashesInBatch || (clashesInFolder && policy == .keepBoth) {
                var number = 2
                while names(number).contains(where: { there.contains($0.lowercased()) || mine.contains($0.lowercased()) }) {
                    number += 1
                }
                chosen = names(number)
            } else if clashesInFolder {
                switch policy {
                case .replace: replaces = chosen.map { there.contains($0.lowercased()) }
                case .skip: isSkipped = true
                case .keepBoth: break
                }
            }
            if !isSkipped {
                for name in chosen { assigned[folder, default: []].insert(name.lowercased()) }
            }
            entries.append(Entry(
                item: item, sequence: sequence, folder: folder,
                outputs: zip(sources, zip(chosen, replaces)).map { Output(source: $0, name: $1.0, replaces: $1.1) },
                isSkipped: isSkipped
            ))
        }
        return FileExportPlan(entries: entries)
    }
}
