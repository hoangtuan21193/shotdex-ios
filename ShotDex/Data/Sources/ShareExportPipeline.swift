import Foundation
import ShotDexKit

/// One photo or video on its way out of the app (FS-08.06): what the share
/// pipeline needs to know about it, and nothing PhotoKit-shaped, so the
/// pipeline runs in a unit test without a library.
struct ShareSource: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        /// A still — including a Live Photo, which shares its still only
        /// (spec §5): the motion file is never handed over.
        case photo
        /// Shared as it is at every level (spec §2).
        case video
        /// A RAW original, which ImageIO cannot rewrite: below All Metadata
        /// the share asks what to do with it (spec §5).
        case raw
    }

    let id: String
    let kind: Kind
    /// The name the shared file gets, e.g. `IMG_1234.HEIC`.
    let filename: String
    /// Whether the library asset still has a location. One the user removed
    /// in the app may still sit in the file's GPS, and it must not leave with
    /// the file at any level, All Metadata included (spec §3).
    var hasLocation = true
    /// For a RAW: whether this device can decode it at all (FS-03.04b).
    var isReadable = true
}

/// Where the share pipeline reads the bytes it hands over. `PhotoKitShareReader`
/// in the app; a fake over fixture files in the tests.
protocol ShareAssetReader: Sendable {
    /// Writes the photo's current version — the edited one if it was edited,
    /// like the share sheet always handed over — to `url`, downloading it from
    /// iCloud when the device only has a preview.
    func writePhoto(_ source: ShareSource, to url: URL) async throws
    /// The video file, shared as it is.
    func videoURL(for source: ShareSource) async throws -> URL
}

/// What a share run produced: the files for the share sheet, in order, and
/// the names of the items that could not be prepared.
struct ShareExportResult: Sendable, Equatable {
    var files: [URL] = []
    /// Every item left out, by name.
    var failed: [String] = []
    /// The part of `failed` that never arrived from the library — not on the
    /// device, or a download that did not finish — as opposed to a photo
    /// whose metadata could not be removed.
    var unread: [String] = []
    /// RAW files left out because the user chose Skip — not failures.
    var skipped: [String] = []
    /// RAW files handed over as they are because the user said so.
    var rawSharedAsIs = 0
}

/// Gathers a share one item at a time into a scratch folder of its own
/// (`ShotDexShare-<uuid>`), so a twenty-photo share holds one file in memory
/// at a time rather than twenty (spec §5). The caller removes the folder when
/// the share sheet closes; `TemporaryWorkspace` sweeps any the app never came
/// back for.
struct ShareExportPipeline: Sendable {
    let reader: any ShareAssetReader
    let folder: URL
    /// What goes with each photo. Videos go as they are at every level.
    let level: MetadataLevel
    /// What happens to RAW files below All Metadata — the share's one answer
    /// to the RAW question. Skip unless asked: a RAW never leaves carrying
    /// what the level removes without the user having said so.
    var rawChoice: RAWChoice = .skip

    static let prefix = "ShotDexShare-"

    /// A new, empty folder under the temporary directory.
    static func makeFolder(in directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let folder = directory.appendingPathComponent(prefix + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Prepares one item. Each lands in a numbered subfolder, so two photos
    /// both called `IMG_0001.JPG` (two cameras, one counter) keep their names.
    func export(_ source: ShareSource, index: Int) async throws -> URL {
        switch source.kind {
        case .video:
            return try await reader.videoURL(for: source)
        case .raw where level != .all:
            switch rawChoice {
            case .skip:
                throw Skipped()
            case .shareRAWWithLocation:
                // The user's answer: the RAW as it is, byte for byte.
                let file = try slotFile(for: source, index: index)
                try await reader.writePhoto(source, to: file)
                return file
            case .shareAsJPEG:
                // A full-size JPEG of the RAW at the share's level, under the
                // RAW's own name; the RAW itself is gone once it is made.
                let slot = try slotFile(for: source, index: index).deletingLastPathComponent()
                let original = slot.appendingPathComponent("original-" + source.filename)
                defer { try? FileManager.default.removeItem(at: original) }
                try await reader.writePhoto(source, to: original)
                let name = (source.filename as NSString).deletingPathExtension + ".jpg"
                let file = slot.appendingPathComponent(name)
                try ShareRAWRenderer.renderJPEG(from: original, to: file, level: level)
                return file
            }
        case .photo, .raw:
            let file = try slotFile(for: source, index: index)
            let slot = file.deletingLastPathComponent()
            if level == .all && source.hasLocation {
                try await reader.writePhoto(source, to: file)
                return file
            }
            // The original lands under a name of its own and is gone once the
            // rewrite is done, whichever way it went: a photo whose metadata
            // cannot be removed is left out, never handed over as it was.
            let original = slot.appendingPathComponent("original-" + source.filename)
            defer { try? FileManager.default.removeItem(at: original) }
            try await reader.writePhoto(source, to: original)
            try MetadataRewriter.rewrite(original, to: file, level: effectiveLevel(for: source, file: original))
            return file
        }
    }

    /// Where item `index` lands: a numbered subfolder of its own, so two
    /// photos with one name both arrive.
    private func slotFile(for source: ShareSource, index: Int) throws -> URL {
        let slot = folder.appendingPathComponent(String(index), isDirectory: true)
        try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
        return slot.appendingPathComponent(source.filename)
    }

    /// The level a photo is actually written at. All Metadata is the file as
    /// it is — unless the asset's location was removed in the app and the
    /// file still carries one: then only the place goes (spec §3, AC-3). A
    /// location the user *changed* is not covered: All still hands over the
    /// file's own.
    func effectiveLevel(for source: ShareSource, file: URL) -> MetadataLevel {
        guard level == .all, !source.hasLocation else { return level }
        return MetadataRewriter.carriesLocation(file) ? .noLocation : .all
    }

    /// Prepares every item in order. One that fails — a download that did not
    /// finish, a photo whose metadata could not be removed — is named in
    /// `failed` and left out, rather than ending the whole share.
    func export(_ sources: [ShareSource]) async -> ShareExportResult {
        var result = ShareExportResult()
        for (index, source) in sources.enumerated() {
            do {
                result.files.append(try await export(source, index: index))
                if source.kind == .raw, level != .all, rawChoice == .shareRAWWithLocation {
                    result.rawSharedAsIs += 1
                }
            } catch is Skipped {
                result.skipped.append(source.filename)
            } catch is MetadataRewriter.Failure, is ShareRAWRenderer.Failure {
                result.failed.append(source.filename)
            } catch {
                result.failed.append(source.filename)
                result.unread.append(source.filename)
            }
        }
        return result
    }

    /// A RAW left out at the user's word.
    struct Skipped: Error {}

    /// Removes the folder and everything gathered into it.
    func removeFolder() {
        try? FileManager.default.removeItem(at: folder)
    }
}

extension ShareBatchPlan {
    /// The plan for a share of these items at `level`.
    init(sources: [ShareSource], level: MetadataLevel) {
        let raws = sources.filter { $0.kind == .raw }
        self.init(
            level: level,
            photoCount: sources.filter { $0.kind == .photo }.count,
            videoCount: sources.filter { $0.kind == .video }.count,
            rawCount: raws.count,
            unreadableRAWCount: raws.filter { !$0.isReadable }.count
        )
    }
}
