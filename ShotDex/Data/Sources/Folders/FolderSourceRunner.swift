import Foundation
import GRDB

/// Adds folder and drive sources and reads them (FS-19.01 §1, §4): one read
/// at a time, off the main actor, inside the folder's security scope. After
/// each read, identical files across sources are merged into one photo.
actor FolderSourceRunner {
    let database: AppDatabase
    let metadataStore: MetadataStore
    let thumbnails: FolderThumbnails?
    /// The read currently running, by source id.
    private(set) var reading: String?

    init(database: AppDatabase, metadataStore: MetadataStore, thumbnails: FolderThumbnails? = .standard) {
        self.database = database
        self.metadataStore = metadataStore
        self.thumbnails = thumbnails
    }

    /// Add Folder or Drive: keeps a bookmark of `folder` (picked in Files,
    /// so already inside its scope) and returns the new source's id. A folder
    /// on a volume that is not the device's own is a drive — unplugged, its
    /// photos stay, offline.
    func add(folder: URL, includesSubfolders: Bool, pairsRawAndJpeg: Bool, at now: Date = Date()) throws -> String {
        let isAccessing = folder.startAccessingSecurityScopedResource()
        defer { if isAccessing { folder.stopAccessingSecurityScopedResource() } }
        let bookmark = try SourceBookmark.make(for: folder)
        let isInternal = (try? folder.resourceValues(forKeys: [.volumeIsInternalKey]).volumeIsInternal) ?? true
        return try SourceStore(database: database).addFolder(name: folder.lastPathComponent, bookmark: bookmark,
                                                            includesSubfolders: includesSubfolders, pairsRawAndJpeg: pairsRawAndJpeg,
                                                            kind: isInternal ? "folder" : "drive", at: now)
    }

    /// Reads one source: what is new or changed, by path, size and date.
    /// `progress` and `shouldContinue` come from the caller's thread-safe
    /// state: the read runs on this actor, the banner on the main one.
    @discardableResult
    func read(sourceId: String,
              shouldContinue: @escaping @Sendable () -> Bool = { true },
              progress: @escaping @Sendable (_ done: Int, _ total: Int) -> Void = { _, _ in }) throws -> FolderSourceIndexer.Summary? {
        guard reading == nil else { return nil }
        reading = sourceId
        defer { reading = nil }
        guard let source = try SourceStore(database: database).sources().first(where: { $0.id == sourceId }),
              case .available(let root) = try FolderSourceAccess(database: database).open(sourceId: sourceId)
        else { return nil }
        let isAccessing = root.startAccessingSecurityScopedResource()
        defer { if isAccessing { root.stopAccessingSecurityScopedResource() } }
        let composer = MetadataComposer(sensorLookup: SensorLookup(
            records: (try? SensorDatabaseLoader().loadRecords()) ?? [],
            customMappings: (try? metadataStore.customMappings()) ?? []
        ))
        let summary = try FolderSourceIndexer(database: database, composer: composer, thumbnails: thumbnails)
            .index(sourceId: sourceId, root: root, includesSubfolders: source.includesSubfolders, pairsRawAndJpeg: source.pairsRawAndJpeg,
                   shouldContinue: shouldContinue, progress: progress)
        _ = try IdentityMergePass(database: database) { [root] id, path in id == sourceId ? root.appendingPathComponent(path) : nil }.run()
        return summary
    }

    /// A photo the grid shows with the cloud glyph: the file its placeholder
    /// stands for, and how big it is when that is known without a download.
    struct CloudFile: Equatable, Sendable {
        let sourceId: String
        let relativePath: String
        let size: Int64?
        var filename: String { (relativePath as NSString).lastPathComponent }
    }

    enum DownloadOutcome: Equatable, Sendable {
        /// On the device and read: the photo has its EXIF, hash and tile.
        case downloaded
        /// The source cannot be opened (unplugged, access lost).
        case unavailable
        /// Not started: the file and 1 GB of headroom do not fit.
        case notEnoughSpace(short: Int64)
    }

    /// The placeholder copy of `photoId`, or nil when it has none — a photo
    /// with any downloaded copy opens from that one.
    func cloudFile(photoId: String) throws -> CloudFile? {
        let row = try database.reader.read { db in
            try Row.fetchOne(db, sql: """
                SELECT c.sourceId, c.relativePath FROM photo_copies c
                WHERE c.photoId = ? AND c.isCloudPlaceholder = 1 AND c.missingSince IS NULL AND c.relativePath IS NOT NULL
                  AND NOT EXISTS (SELECT 1 FROM photo_copies o WHERE o.photoId = c.photoId AND o.isCloudPlaceholder = 0 AND o.missingSince IS NULL)
                LIMIT 1
                """, arguments: [photoId])
        }
        guard let row else { return nil }
        let sourceId: String = row["sourceId"]
        let relativePath: String = row["relativePath"]
        var size: Int64?
        if case .available(let root) = try FolderSourceAccess(database: database).open(sourceId: sourceId) {
            let isAccessing = root.startAccessingSecurityScopedResource()
            defer { if isAccessing { root.stopAccessingSecurityScopedResource() } }
            size = CloudPlaceholder.size(of: root.appendingPathComponent(relativePath))
        }
        return CloudFile(sourceId: sourceId, relativePath: relativePath, size: size)
    }

    /// Opening a cloud placeholder (FS-19.01b §4): the user asked for this
    /// one file, so exactly it is downloaded — space checked first — and its
    /// source read again, which turns the placeholder into a full photo with
    /// the same id. Cancelling the task stops the download.
    func download(
        _ file: CloudFile,
        with downloader: any CloudFileDownloading,
        freeBytes: @Sendable (URL) -> Int64? = { DiskSpace.availableBytes(for: $0) },
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> DownloadOutcome {
        guard case .available(let root) = try FolderSourceAccess(database: database).open(sourceId: file.sourceId) else {
            return .unavailable
        }
        let isAccessing = root.startAccessingSecurityScopedResource()
        defer { if isAccessing { root.stopAccessingSecurityScopedResource() } }
        if let size = file.size, let short = DeviceSpaceCheck.shortfall(for: size, free: freeBytes(root)) {
            return .notEnoughSpace(short: short)
        }
        try await downloader.download(root.appendingPathComponent(file.relativePath), progress: progress)
        // A read already running would skip this one and leave the glyph.
        while reading != nil { try await Task.sleep(for: .milliseconds(200)) }
        // Cancel during the read after it stops the read too.
        _ = try read(sourceId: file.sourceId, shouldContinue: { !Task.isCancelled })
        return .downloaded
    }

    /// Every folder and drive source, in the order they were added — at
    /// launch and on each return to the foreground (FS-19.01 §5). True when
    /// any of them changed what the library shows.
    @discardableResult
    /// `skipping`: a read the user paused, left for Resume.
    func readAll(skipping: Set<String> = []) -> Bool {
        let ids = (try? SourceStore(database: database).sources()
            .filter { ($0.kind == "folder" || $0.kind == "drive") && !skipping.contains($0.id) }.map(\.id)) ?? []
        var changed = false
        for id in ids {
            if let summary = try? read(sourceId: id), summary.changesLibrary { changed = true }
        }
        return changed
    }
}
