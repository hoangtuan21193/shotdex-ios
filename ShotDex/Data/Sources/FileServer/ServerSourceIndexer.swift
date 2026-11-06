import Foundation
import GRDB
import ImageIO

/// The read of a server connection added as a source (FS-19.03 §2): list
/// its Folder, pair RAW with its twin, and for each new or changed file read
/// only what the thumbnail ladder of FS-17.01 §3 asks for plus the three
/// 64 KB samples of the fast hash — never a whole original. One request to
/// the server at a time; nothing on the server is written.
struct ServerSourceIndexer: Sendable {
    let database: AppDatabase
    let composer: MetadataComposer
    let client: any RemoteFileClient
    /// Where grid thumbnails go; nil skips them.
    var thumbnails: FolderThumbnails? = nil
    /// Read and Write .xmp Sidecars: off, a sidecar on the share is not read.
    var readsSidecars = SidecarSetting.isOn()

    struct Summary: Equatable, Sendable {
        var photos = 0
        var unchanged = 0
        var previewsStoppedForSpace = false
        /// The server went away mid-read (FS-19.03 §6): what was read stays,
        /// the source is offline, nothing is missing.
        var disconnected = false
        /// What stopped the read — a password the server now refuses, a
        /// share that went away. Nothing asks for a password; the source row
        /// reports it.
        var stoppedBy: RemoteFileError?
    }

    /// `folder` is the connection's Folder, relative to the server's root.
    func index(sourceId: String, folder: String, pairsRawAndJpeg: Bool, now: Date = Date()) async throws -> Summary {
        let result: Result<Summary, Error>
        do {
            result = .success(try await run(sourceId: sourceId, folder: folder, pairsRawAndJpeg: pairsRawAndJpeg, now: now))
        } catch {
            result = .failure(error)
        }
        await client.disconnect()
        return try result.get()
    }

    private func run(sourceId: String, folder: String, pairsRawAndJpeg: Bool, now: Date) async throws -> Summary {
        var summary = Summary()
        let stamp = Int(now.timeIntervalSince1970)
        let listing: [FolderEnumeration.Entry]
        do {
            try await client.connect()
            listing = try await list(folder)
        } catch let error as RemoteFileError {
            try stop(&summary, error, sourceId: sourceId)
            return summary
        }
        // Listed: the server is there, whatever it was before.
        try SourceStore(database: database).setOnline(true, sourceId: sourceId)

        let files = listing.filter { !$0.isSidecar }
        let sidecars = Dictionary(listing.filter(\.isSidecar).map { (FolderSourceIndexer.pathKey($0.relativePath), $0) },
                                  uniquingKeysWith: { first, _ in first })
        let units = PairingRule.units(files, pairs: pairsRawAndJpeg,
                                      name: { ($0.relativePath as NSString).lastPathComponent },
                                      folder: { ($0.relativePath as NSString).deletingLastPathComponent })
        let namesByFolder = Dictionary(grouping: files.map(\.relativePath)) { ($0 as NSString).deletingLastPathComponent }
            .mapValues { $0.map { ($0 as NSString).lastPathComponent } }
        let listed = Set(units.map { FolderSourceIndexer.pathKey($0.primary.relativePath) })
        var vanished = try await database.reader.read { db in
            try FileCopyWriter.vanished(db, sourceId: sourceId, kind: "server", listed: listed)
        }

        for unit in units {
            try Task.checkCancellation()
            let file = unit.primary
            let key = FolderSourceIndexer.pathKey(file.relativePath)
            let modified = file.modified.map { Int($0.timeIntervalSince1970) }
            let existing = try await database.reader.read { db in try FileCopyWriter.existing(db, sourceId: sourceId, key: key) }
            if let existing, FileCopyWriter.isUnchanged(existing, size: file.size, modified: modified) {
                // Same size, same date: not one byte read (FS-19.03 §3).
                let (copyId, files) = (existing.id, Self.listedFiles(unit))
                try await database.writer.write { db in
                    try FileCopyWriter.touch(db, existing: existing, at: stamp)
                    try CopyFileStore.saveServerFiles(db, copyId: copyId, files: files)
                }
                summary.unchanged += 1
                continue
            }

            let ranges = RemoteRangeReader(client: client)
            let read: Read
            do {
                read = try await self.read(unit, folder: folder, ranges: ranges, namesByFolder: namesByFolder, sidecars: sidecars)
            } catch let error as RemoteFileError where error.stopsBatch {
                try stop(&summary, error, sourceId: sourceId)
                return summary
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // This file alone: gone between the listing and the read, or
                // a layout that never settled. The next read tries again.
                continue
            }

            var photoId = existing?.photoId ?? UUID().uuidString
            var copyId = existing?.id ?? UUID().uuidString
            if existing == nil, let match = vanished.firstIndex(where: { $0.fast == read.hash.fast && $0.size == file.size }) {
                // Renamed or moved on the server: same copy, same photo.
                photoId = vanished[match].photoId
                copyId = vanished[match].copyId
                vanished.remove(at: match)
            }
            var splitFrom: String?
            let (matchedCopy, matchedPhoto, fast) = (copyId, photoId, read.hash.fast)
            if existing != nil, try await database.reader.read({ db in
                try FileCopyWriter.changedPictureWhileOthersKeepOld(db, copyId: matchedCopy, photoId: matchedPhoto, newFast: fast)
            }) {
                splitFrom = photoId
                photoId = UUID().uuidString
            }
            let record = metadata(photoId: photoId, file: file, read: read)
            let marks = SidecarReader.combined(embedded: read.embedded, sidecar: read.sidecar?.values)
            let marksAt = Int((read.sidecar?.modified ?? file.modified ?? now).timeIntervalSince1970)
            let copy = FileCopyWriter.Copy(photoId: photoId, copyId: copyId, sourceId: sourceId, kind: "server",
                                           relativePath: file.relativePath, key: key, size: file.size, modified: modified,
                                           pairedPath: unit.companion?.relativePath, sidecarStamp: read.sidecar?.stamp)
            let (hash, split, files) = (read.hash, splitFrom, Self.listedFiles(unit))
            try await database.writer.write { db in
                try FileCopyWriter.record(db, copy, hash: hash, metadata: record, marks: marks, marksAt: marksAt,
                                          splitFrom: split, at: stamp)
                try CopyFileStore.saveServerFiles(db, copyId: copy.copyId, files: files)
            }
            if let thumbnails, !summary.previewsStoppedForSpace, let image = read.thumbnail?.image,
               thumbnails.write(image, copyId: copyId) == .noSpace {
                summary.previewsStoppedForSpace = true
            }
            summary.photos += 1
        }
        let missing = vanished.map(\.copyId)
        try await database.writer.write { db in try FileCopyWriter.markMissing(db, missing, at: stamp) }
        return summary
    }

    /// Every photo and sidecar under `folder` (`ServerTreeListing`).
    func list(_ folder: String) async throws -> [FolderEnumeration.Entry] {
        try await ServerTreeListing.list(folder, client: client)
    }

    /// The unit's files for the on-server check (FS-19.07 §5): the primary,
    /// and the paired twin, whose bytes count as much.
    private static func listedFiles(_ unit: PairingRule.Unit<FolderEnumeration.Entry>) -> [CopyFileStore.ListedFile] {
        [("primary", unit.primary), unit.companion.map { ("companion", $0) }].compactMap { $0 }.map { key, entry in
            CopyFileStore.ListedFile(fileKey: key, relativePath: entry.relativePath, size: entry.size,
                                     modifiedAt: entry.modified.map { Int($0.timeIntervalSince1970) })
        }
    }

    /// What one photo's reads gave.
    private struct Read {
        typealias Sidecar = (values: SidecarValues?, stamp: String, modified: Date?)
        let hash: ContentHash
        let head: Data
        let thumbnail: EmbeddedPreview.Thumbnail?
        let captureDate: Date?
        let embedded: SidecarValues?
        let sidecar: Sidecar?
    }

    private func read(_ unit: PairingRule.Unit<FolderEnumeration.Entry>, folder: String, ranges: RemoteRangeReader,
                      namesByFolder: [String: [String]], sidecars: [String: FolderEnumeration.Entry]) async throws -> Read {
        let file = unit.primary
        let directory = (file.relativePath as NSString).deletingLastPathComponent
        let path = ServerUploadPath.join(folder, file.relativePath)
        let isVideo = FolderEnumeration.isMovie(URL(fileURLWithPath: file.relativePath))

        var thumbnail: RemoteThumbnailResult?
        if !isVideo {
            // Download order of a server photo: the rendered twin first. A
            // Live Photo's movie is not a picture of it.
            let twin = unit.companion.flatMap { FolderEnumeration.isMovie(URL(fileURLWithPath: $0.relativePath)) ? nil : $0 }
            let entries = ([twin].compactMap { $0 } + [file]).map {
                RemoteEntry(name: ($0.relativePath as NSString).lastPathComponent, isDirectory: false, size: $0.size, modified: $0.modified)
            }
            var thumbnailer = RemoteThumbnailer(client: client)
            thumbnailer.ranges = ranges
            thumbnail = try await thumbnailer.thumbnail(for: ServerPhoto(files: entries), in: ServerUploadPath.join(folder, directory))
        }
        let head = isVideo ? Data() : try await ranges.read(path, offset: 0, length: EmbeddedPreview.firstRead)
        let hash = try await ranges.fastHash(path, length: file.size)

        var sidecar: Read.Sidecar?
        if readsSidecars {
            let name = (file.relativePath as NSString).lastPathComponent
            let fullNameOnly = unit.companion == nil && PairingRule.usesFullNameSidecar(name, siblings: namesByFolder[directory] ?? [])
            if let entry = SidecarReader.sidecar(for: [file.relativePath] + [unit.companion?.relativePath].compactMap { $0 },
                                                 fullNameOnly: fullNameOnly, in: sidecars, modified: \.modified,
                                                 pathKey: FolderSourceIndexer.pathKey) {
                let data = try await ranges.read(ServerUploadPath.join(folder, entry.relativePath), offset: 0, length: Int(entry.size))
                let values = SidecarReader.values(xmp: data)
                sidecar = (values, SidecarReader.stamp(of: data, modified: entry.modified), values == nil ? nil : entry.modified)
            }
        }
        let source = head.isEmpty ? nil : Self.source(head, isWholeFile: Int64(head.count) >= file.size)
        return Read(hash: hash, head: head, thumbnail: thumbnail?.thumbnail,
                    captureDate: thumbnail?.captureDate ?? EmbeddedPreview.captureDate(from: head),
                    embedded: source.flatMap(SidecarReader.embedded(in:)), sidecar: sidecar)
    }

    private static func source(_ head: Data, isWholeFile: Bool) -> CGImageSource {
        let source = CGImageSourceCreateIncremental([kCGImageSourceShouldCache: false] as CFDictionary)
        CGImageSourceUpdateData(source, head as CFData, isWholeFile)
        return source
    }

    /// The metadata row from the head of the file — the same composer as a
    /// folder photo, fed from 256 KB instead of the file.
    private func metadata(photoId: String, file: FolderEnumeration.Entry, read: Read) -> PhotoMetadata {
        let isVideo = FolderEnumeration.isMovie(URL(fileURLWithPath: file.relativePath))
        var exif = RawExif.empty
        var status = ExifStatus.noExif
        var width: Int?, height: Int?
        if !read.head.isEmpty {
            let source = Self.source(read.head, isWholeFile: Int64(read.head.count) >= file.size)
            let options = [kCGImageSourceShouldCache: false] as CFDictionary
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any] {
                if properties[kCGImagePropertyExifDictionary] != nil || properties[kCGImagePropertyTIFFDictionary] != nil {
                    exif = ExifReader.parse(properties: properties, source: source)
                    status = .indexed
                }
                width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
                height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
            }
        }
        let asset = AssetInfo(
            assetId: photoId,
            creationDate: isVideo ? file.modified : (read.captureDate ?? file.modified),
            modificationDate: file.modified,
            mediaType: (isVideo ? MediaKind.video : MediaKind.photo).storedValue,
            width: width, height: height,
            fileSize: Int(file.size),
            isFavorite: false,
            originalFilename: (file.relativePath as NSString).lastPathComponent
        )
        return composer.compose(asset: asset, exif: exif, exifStatus: status)
    }

    /// A batch-stopping error: an unreachable server or a lost connection
    /// makes the source offline (its photos stay); a refused password or a
    /// missing share is reported, never asked about (FS-19.03 §6).
    private func stop(_ summary: inout Summary, _ error: RemoteFileError, sourceId: String) throws {
        summary.stoppedBy = error
        switch error {
        case .unreachable, .connectionLost, .localNetworkDenied:
            try SourceStore(database: database).setOnline(false, sourceId: sourceId)
            summary.disconnected = true
        case .authenticationFailed:
            try SourceStore(database: database).setPasswordRejected(sourceId: sourceId)
        default:
            break
        }
    }
}
