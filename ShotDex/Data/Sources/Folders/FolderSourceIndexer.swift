import Foundation
import GRDB
import ImageIO

/// The read of a folder or drive source (FS-19.01 §4): list what is there,
/// pair RAW with its twin, read EXIF and the fast hash of each new or
/// changed file, and record a photo, its copy and its metadata row. The
/// source folder is only ever read — nothing is written into it.
struct FolderSourceIndexer: Sendable {
    let database: AppDatabase
    let composer: MetadataComposer
    /// Where grid thumbnails go; nil skips them (tests that only count rows).
    var thumbnails: FolderThumbnails? = nil

    struct Summary: Equatable, Sendable {
        var photos = 0
        var unchanged = 0
        /// Cloud-only files recorded without a byte read (FS-19.01b §4).
        var placeholders = 0
        /// Pause stopped the read before the end (FS-19.01 §4).
        var paused = false
        /// The cache volume ran out of room: thumbnails stopped, metadata did
        /// not ("Not enough space for previews", FS-19.01b §5).
        var previewsStoppedForSpace = false
        /// The folder went away mid-read — a drive unplugged (FS-19.01b §1).
        /// What was read stays; the source is offline, nothing is missing.
        var disconnected = false
    }

    /// `shouldContinue` is asked before each file; false pauses the read.
    /// Every file is recorded in its own transaction, so a pause, a quit or a
    /// crash keeps what was read, and the next read skips it by path, size
    /// and date — Resume, even after a relaunch, reads only what is left.
    func index(sourceId: String, root: URL, includesSubfolders: Bool, pairsRawAndJpeg: Bool,
               now: Date = Date(), shouldContinue: () -> Bool = { true }) throws -> Summary {
        let listing = FolderEnumeration.entries(in: root, includeSubfolders: includesSubfolders)
        let files = listing.filter { !$0.isSidecar }
        let sidecars = Dictionary(listing.filter(\.isSidecar).map { (Self.pathKey($0.relativePath), $0) },
                                  uniquingKeysWith: { first, _ in first })
        // Placeholders never pair: their twin may not exist yet either.
        let units = PairingRule.units(files.filter { !$0.isCloudPlaceholder }, pairs: pairsRawAndJpeg,
                                      name: { ($0.relativePath as NSString).lastPathComponent },
                                      folder: { ($0.relativePath as NSString).deletingLastPathComponent })
            + files.filter(\.isCloudPlaceholder).map { PairingRule.Unit(primary: $0, companion: nil) }
        // File names by folder, for telling a JPEG beside an unpaired RAW
        // to read its own `.JPG.xmp`.
        let namesByFolder = Dictionary(grouping: files.map { $0.relativePath }) { ($0 as NSString).deletingLastPathComponent }
            .mapValues { $0.map { ($0 as NSString).lastPathComponent } }
        var summary = Summary()
        let stamp = Int(now.timeIntervalSince1970)
        // Copies this source knew that are not at their path any more: a
        // renamed or moved file is matched back to one of these by its fast
        // hash and size (FS-19.02 §2); what is left over went missing.
        let listed = Set(units.map { Self.pathKey($0.primary.relativePath) })
        var vanished = try database.reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT c.id, c.photoId, c.relativePathKey, c.size, h.fastHash FROM photo_copies c
                LEFT JOIN content_hashes h ON h.copyId = c.id
                WHERE c.sourceId = ? AND c.kind = 'file'
                """, arguments: [sourceId])
                .filter { !listed.contains($0["relativePathKey"] as String) }
                .map { (copyId: $0["id"] as String, photoId: $0["photoId"] as String, size: $0["size"] as Int64?, fast: $0["fastHash"] as String?) }
        }
        for unit in units {
            try Task.checkCancellation()
            guard shouldContinue() else {
                summary.paused = true
                return summary
            }
            let file = unit.primary
            let key = Self.pathKey(file.relativePath)
            let modified = file.modified.map { Int($0.timeIntervalSince1970) }
            let existing = try database.reader.read { db in
                try Row.fetchOne(db, sql: "SELECT id, photoId, size, modifiedAt, isCloudPlaceholder FROM photo_copies WHERE sourceId = ? AND relativePathKey = ?",
                                 arguments: [sourceId, key])
            }
            if file.isCloudPlaceholder {
                // Listed, never opened: a photo and a copy so the grid can show
                // it, no hash, no metadata row — nothing counts it yet.
                try database.writer.write { db in
                    let photoId: String = existing?["photoId"] ?? UUID().uuidString
                    try db.execute(sql: "INSERT OR IGNORE INTO photos (id, createdAt) VALUES (?, ?)", arguments: [photoId, stamp])
                    try db.execute(sql: """
                        INSERT INTO photo_copies (id, photoId, sourceId, kind, relativePath, relativePathKey, modifiedAt, isOnline, isCloudPlaceholder, lastSeenAt)
                        VALUES (?, ?, ?, 'file', ?, ?, ?, 1, 1, ?)
                        ON CONFLICT(id) DO UPDATE SET missingSince = NULL, lastSeenAt = excluded.lastSeenAt
                        """, arguments: [existing?["id"] ?? UUID().uuidString, photoId, sourceId, file.relativePath, key, modified, stamp])
                }
                summary.placeholders += 1
                continue
            }
            if let existing, existing["size"] as Int64? == file.size, existing["modifiedAt"] as Int? == modified {
                try database.writer.write { db in
                    try db.execute(sql: "UPDATE photo_copies SET lastSeenAt = ?, isOnline = 1, missingSince = NULL WHERE id = ?",
                                   arguments: [stamp, existing["id"] as String])
                    // Put Back: the file is where it was — the photo is no
                    // orphan any more, its data never left.
                    try db.execute(sql: "UPDATE photos SET orphanedAt = NULL WHERE id = ? AND orphanedAt IS NOT NULL",
                                   arguments: [existing["photoId"] as String])
                }
                summary.unchanged += 1
                continue
            }

            let url = root.appendingPathComponent(file.relativePath)
            let hash: ContentHash
            do {
                hash = try ContentHasher.hash(FileBytes(url: url), full: false)
            } catch {
                guard Self.isReachable(root) else {
                    try SourceStore(database: database).setOnline(false, sourceId: sourceId)
                    summary.disconnected = true
                    return summary
                }
                continue
            }
            var photoId: String = existing?["photoId"] ?? UUID().uuidString
            var copyId: String = existing?["id"] ?? UUID().uuidString
            if existing == nil, let match = vanished.firstIndex(where: { $0.fast == hash.fast && $0.size == file.size }) {
                // Renamed or moved inside the source: same copy, same photo.
                photoId = vanished[match].photoId
                copyId = vanished[match].copyId
                vanished.remove(at: match)
            }
            var splitFrom: String?
            if existing != nil, try changedPictureWhileOthersKeepOld(copyId: copyId, photoId: photoId, newFast: hash.fast) {
                // Overwritten with another picture while another copy keeps
                // the old one: this copy becomes a photo of its own.
                splitFrom = photoId
                photoId = UUID().uuidString
            }
            let (record, embedded) = metadata(photoId: photoId, url: url, file: file)
            let name = (file.relativePath as NSString).lastPathComponent
            let fullNameOnly = unit.companion == nil && PairingRule.usesFullNameSidecar(
                name, siblings: namesByFolder[(file.relativePath as NSString).deletingLastPathComponent] ?? [])
            let sidecar = SidecarReader.sidecar(for: [file.relativePath] + [unit.companion?.relativePath].compactMap { $0 },
                                                fullNameOnly: fullNameOnly, in: sidecars, modified: \.modified, pathKey: Self.pathKey)
            let sidecarValues = sidecar.flatMap { SidecarReader.read(sidecarAt: root.appendingPathComponent($0.relativePath)) }
            let marks = SidecarReader.combined(embedded: embedded, sidecar: sidecarValues)
            // A sidecar's values date from when it was written; the file's own
            // from when the file was.
            let marksAt = Int(((sidecarValues != nil ? sidecar?.modified : nil) ?? file.modified ?? now).timeIntervalSince1970)

            try database.writer.write { db in
                if splitFrom != nil {
                    try PhotoIdentityStore.split(db, copyId: copyId, into: photoId, now: stamp)
                }
                try db.execute(sql: "INSERT OR IGNORE INTO photos (id, createdAt) VALUES (?, ?)", arguments: [photoId, stamp])
                try db.execute(sql: "UPDATE photos SET orphanedAt = NULL WHERE id = ?", arguments: [photoId])
                try db.execute(sql: """
                    INSERT INTO photo_copies (id, photoId, sourceId, kind, relativePath, relativePathKey, size, modifiedAt, pairedPath, isOnline, lastSeenAt)
                    VALUES (?, ?, ?, 'file', ?, ?, ?, ?, ?, 1, ?)
                    ON CONFLICT(id) DO UPDATE SET relativePath = excluded.relativePath, relativePathKey = excluded.relativePathKey,
                        size = excluded.size, modifiedAt = excluded.modifiedAt, pairedPath = excluded.pairedPath,
                        isOnline = 1, missingSince = NULL, isCloudPlaceholder = 0, lastSeenAt = excluded.lastSeenAt
                    """, arguments: [copyId, photoId, sourceId, file.relativePath, key, file.size, modified,
                                     unit.companion?.relativePath, stamp])
                try db.execute(sql: """
                    INSERT INTO content_hashes (copyId, algorithm, algorithmVersion, fastHash, fullHash, hashedAt)
                    VALUES (?, ?, ?, ?, NULL, ?)
                    ON CONFLICT(copyId) DO UPDATE SET algorithm = excluded.algorithm, algorithmVersion = excluded.algorithmVersion,
                        fastHash = excluded.fastHash, fullHash = NULL, hashedAt = excluded.hashedAt
                    """, arguments: [copyId, hash.algorithm, hash.version, hash.fast, stamp])
                try record.upsert(db)
                if let marks {
                    try PhotoUserMarksStore.applySidecar(db, values: marks, photoId: photoId, at: marksAt)
                }
            }
            if let thumbnails, !summary.previewsStoppedForSpace,
               thumbnails.write(from: url, copyId: copyId) == .noSpace {
                summary.previewsStoppedForSpace = true
            }
            summary.photos += 1
        }
        // A folder that is gone as a whole is unplugged, not emptied.
        guard Self.isReachable(root) else {
            try SourceStore(database: database).setOnline(false, sourceId: sourceId)
            summary.disconnected = true
            return summary
        }
        try markMissing(vanished.map(\.copyId), at: stamp)
        return summary
    }

    /// True when this copy's new fast hash differs from its old one and
    /// another present copy of the same photo still carries the old one
    /// (FS-19.02 §2). A photo with only this copy keeps its id: same source,
    /// same path, new bytes is the same photo edited elsewhere.
    private func changedPictureWhileOthersKeepOld(copyId: String, photoId: String, newFast: String) throws -> Bool {
        try database.reader.read { db in
            guard let old = try String.fetchOne(db, sql: "SELECT fastHash FROM content_hashes WHERE copyId = ?", arguments: [copyId]),
                  old != newFast else { return false }
            return try Bool.fetchOne(db, sql: """
                SELECT EXISTS(SELECT 1 FROM photo_copies c JOIN content_hashes h ON h.copyId = c.id
                              WHERE c.photoId = ? AND c.id != ? AND c.missingSince IS NULL AND h.fastHash = ?)
                """, arguments: [photoId, copyId, old]) == true
        }
    }

    /// Files a complete read no longer finds: the copy stays (its hash is
    /// what joins the file back when it returns) and is marked missing; a
    /// photo left with no present copy becomes an orphan (FS-19.05 §5).
    private func markMissing(_ copyIds: [String], at stamp: Int) throws {
        guard !copyIds.isEmpty else { return }
        try database.writer.write { db in
            let marks = databaseQuestionMarks(count: copyIds.count)
            try db.execute(sql: "UPDATE photo_copies SET missingSince = ? WHERE id IN (\(marks)) AND missingSince IS NULL",
                           arguments: StatementArguments([stamp] + copyIds))
            try db.execute(sql: """
                UPDATE photos SET orphanedAt = ?
                WHERE orphanedAt IS NULL AND id IN (SELECT photoId FROM photo_copies WHERE id IN (\(marks)))
                  AND NOT EXISTS (SELECT 1 FROM photo_copies c WHERE c.photoId = photos.id AND c.missingSince IS NULL)
                """, arguments: StatementArguments([stamp] + copyIds))
        }
    }

    /// The metadata row of a file photo — the same composer as Photos assets,
    /// fed from the file instead of the asset — and what the file's own XMP
    /// says about it.
    private func metadata(photoId: String, url: URL, file: FolderEnumeration.Entry) -> (PhotoMetadata, SidecarValues?) {
        let isVideo = FolderEnumeration.isMovie(url)
        var exif = RawExif.empty
        var status = ExifStatus.noExif
        var width: Int?, height: Int?
        var embedded: SidecarValues?
        if !isVideo {
            if case .success(let read) = ExifReader.readExif(fromImageAt: url) {
                exif = read
                status = .indexed
            }
            if let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) {
                if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                    width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
                    height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
                }
                embedded = SidecarReader.embedded(in: source)
            }
        }
        let asset = AssetInfo(
            assetId: photoId,
            creationDate: isVideo ? file.modified : (PhotoOriginFile.captureDate(at: url) ?? file.modified),
            modificationDate: file.modified,
            mediaType: (isVideo ? MediaKind.video : MediaKind.photo).storedValue,
            width: width, height: height,
            fileSize: Int(file.size),
            isFavorite: false,
            originalFilename: url.lastPathComponent
        )
        return (composer.compose(asset: asset, exif: exif, exifStatus: status), embedded)
    }

    static func isReachable(_ root: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// What makes two paths one file: NFC, case folded.
    static func pathKey(_ relativePath: String) -> String {
        relativePath.precomposedStringWithCanonicalMapping.lowercased()
    }
}
