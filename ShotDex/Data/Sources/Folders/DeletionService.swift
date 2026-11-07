import Foundation
import Photos

/// Runs a deletion across sources in the order FS-19.04 §2 sets (board
/// mac-ipad-v2 A7): files to the Trash with their JPEG twin and `.xmp`,
/// the server copies hidden, then the Photos part behind the system's
/// dialog — Cancel there keeps only the Photos part. A file move that fails
/// stops the rest of the files: what moved stays moved.
struct DeletionService: Sendable {
    let database: AppDatabase
    /// PhotoKit's all-or-nothing deletion, with its own dialog.
    let deletePhotosAssets: @Sendable ([String]) async throws -> Void
    /// The folder of a file source, open for reading and writing; nil when
    /// it cannot be reached.
    let root: @Sendable (_ sourceId: String) -> URL?
    /// Moves one file to its volume's Trash.
    var trash: @Sendable (URL) throws -> Void = { url in try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
    /// Deletes one file for good — a volume with no Trash, after the red dialog.
    var remove: @Sendable (URL) throws -> Void = { url in try FileManager.default.removeItem(at: url) }


    struct Summary: Equatable, Sendable {
        var recentlyDeleted = 0
        /// Photos whose files went — a RAW, its twin and their sidecars count once.
        var trashedFiles = 0
        var removedFiles = 0
        var hidden: [String: Int] = [:]
        /// Files the Trash refused, and the first reason given.
        var failedFiles = 0
        var failure: String?
        /// The system's Photos dialog said Cancel: those items stayed, the
        /// rest ran.
        var photosCancelled = false
    }

    /// `alsoPhotos`: Photos assets with no copy row yet, deleted in the same
    /// system dialog as the Photos part.
    func run(_ targets: [[DeletionTarget]], alsoPhotos: [String] = [], now: Date = Date()) async throws -> Summary {
        let copies = targets.flatMap { $0 }
        var summary = Summary()

        var gone: [String] = []
        for copy in copies where copy.kind == "file" {
            guard summary.failure == nil else {
                summary.failedFiles += 1
                continue
            }
            let permanent: Bool = if case .permanent = copy.destination { true } else { false }
            do {
                guard let root = root(copy.sourceId), copy.relativePath != nil else { throw CocoaError(.fileNoSuchFile) }
                for url in Self.files(of: copy, in: root) {
                    try permanent ? remove(url) : trash(url)
                }
                if permanent { summary.removedFiles += 1 } else { summary.trashedFiles += 1 }
                gone.append(copy.copyId)
            } catch {
                summary.failedFiles += 1
                summary.failure = error.localizedDescription
            }
        }
        if !gone.isEmpty {
            // Missing, not forgotten: Put Back brings the file to the same
            // path and the next read clears the mark, stars and all.
            let (missing, stamp) = (gone, Int(now.timeIntervalSince1970))
            try await database.writer.write { db in try FileCopyWriter.markMissing(db, missing, at: stamp) }
        }

        let hidden = copies.filter { $0.kind == "server" }
        try HiddenCopyStore(database: database).hide(copyIds: hidden.map(\.copyId))
        for copy in hidden { summary.hidden[copy.sourceName, default: 0] += 1 }

        let assets = copies.filter { $0.kind == "photos" }.compactMap(\.photoKitId) + alsoPhotos
        if !assets.isEmpty {
            var deleted = assets
            do {
                try await deletePhotosAssets(assets)
            } catch let error as PHPhotosError where error.code == .userCancelled {
                summary.photosCancelled = true
                deleted = []
            } catch let kept as PhotoDeletionGate.Kept {
                // The gate deleted what it could check and kept the rest
                // (server unreachable, or the copy not there): the files
                // already moved stay moved, and the run still reports.
                let stayed = Set(kept.outcome.unreachable.values.joined()).union(kept.outcome.notOnServer.values.joined())
                deleted = assets.filter { !stayed.contains($0) }
                summary.failure = kept.localizedDescription
            }
            if !deleted.isEmpty {
                try MetadataStore(database: database).deleteAssets(ids: deleted)
                try PhotoOrphanStore(database: database).markGoneFromLibrary(ids: deleted, at: now)
                summary.recentlyDeleted = deleted.count
            }
        }
        return summary
    }

    /// A copy's file, its JPEG twin and the sidecars beside either — what
    /// Put Back has to bring back together (FS-19.04 §1).
    static func files(of copy: DeletionTarget, in root: URL) -> [URL] {
        let paths = [copy.relativePath, copy.pairedPath].compactMap { $0 }
        var urls = paths.map { root.appendingPathComponent($0) }
        for path in paths {
            for sidecar in [(path as NSString).deletingPathExtension + ".xmp", path + ".xmp"] {
                urls.append(root.appendingPathComponent(sidecar))
            }
        }
        var seen = Set<String>()
        return urls.filter { FileManager.default.fileExists(atPath: $0.path) && seen.insert($0.standardizedFileURL.path).inserted }
    }
}

extension DeletionService.Summary {
    /// "Moved 84 files to the Trash and 30 photos to Recently Deleted. Hid 6
    /// photos on NAS Home."
    func banner(trashName: String) -> String {
        var moved: [String] = []
        if trashedFiles > 0 {
            moved.append(Self.words(AttributedString(localized: "Moved ^[\(trashedFiles) file](inflect: true) to \(trashName)", comment: "Deletion banner: files sent to the Trash")))
        }
        if recentlyDeleted > 0 {
            moved.append(moved.isEmpty
                ? Self.words(AttributedString(localized: "Moved ^[\(recentlyDeleted) photo](inflect: true) to Recently Deleted", comment: "Deletion banner: Photos items, first part"))
                : Self.words(AttributedString(localized: "^[\(recentlyDeleted) photo](inflect: true) to Recently Deleted", comment: "Deletion banner: Photos items after files")))
        }
        var sentences: [String] = moved.isEmpty ? [] : [moved.joined(separator: String(localized: " and ", comment: "Deletion banner joiner")) + "."]
        if removedFiles > 0 {
            sentences.append(Self.words(AttributedString(localized: "Deleted ^[\(removedFiles) file](inflect: true) permanently.", comment: "Deletion banner: files on a volume with no Trash")))
        }
        for (name, n) in hidden.sorted(by: { $0.key < $1.key }) {
            sentences.append(Self.words(AttributedString(localized: "Hid ^[\(n) photo](inflect: true) on \(name).", comment: "Deletion banner: server photos hidden")))
        }
        if failedFiles > 0, let failure {
            sentences.append(Self.words(AttributedString(localized: "Couldn't move ^[\(failedFiles) file](inflect: true) to \(trashName): \(failure)", comment: "Deletion banner: some files stayed")))
        }
        return sentences.joined(separator: " ")
    }


    /// "1 file" / "2 files": grammar agreement on the counted noun.
    private static func words(_ text: AttributedString) -> String {
        String(text.inflected().characters)
    }
}
