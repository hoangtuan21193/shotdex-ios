import Foundation

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
        let bookmark = try folder.bookmarkData()
        let isInternal = (try? folder.resourceValues(forKeys: [.volumeIsInternalKey]).volumeIsInternal) ?? true
        return try SourceStore(database: database).addFolder(name: folder.lastPathComponent, bookmark: bookmark,
                                                            includesSubfolders: includesSubfolders, pairsRawAndJpeg: pairsRawAndJpeg,
                                                            kind: isInternal ? "folder" : "drive", at: now)
    }

    /// Reads one source: what is new or changed, by path, size and date.
    @discardableResult
    func read(sourceId: String) throws -> FolderSourceIndexer.Summary? {
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
            .index(sourceId: sourceId, root: root, includesSubfolders: source.includesSubfolders, pairsRawAndJpeg: source.pairsRawAndJpeg)
        _ = try IdentityMergePass(database: database) { [root] id, path in id == sourceId ? root.appendingPathComponent(path) : nil }.run()
        return summary
    }

    /// Every folder and drive source, in the order they were added — at
    /// launch and on each return to the foreground (FS-19.01 §5). True when
    /// any of them changed what the library shows.
    @discardableResult
    func readAll() -> Bool {
        let ids = (try? SourceStore(database: database).sources().filter { $0.kind == "folder" || $0.kind == "drive" }.map(\.id)) ?? []
        var changed = false
        for id in ids {
            if let summary = try? read(sourceId: id), summary.changesLibrary { changed = true }
        }
        return changed
    }
}
