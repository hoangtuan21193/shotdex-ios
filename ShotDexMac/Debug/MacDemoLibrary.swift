#if DEBUG
import ShotDexKit
import CoreGraphics
import Photos
import Foundation
import GRDB
import ServiceManagement
import ImageIO

/// `-ShotDexDemoLibrary`: the window over an in-memory library of landscape
/// pictures — the macOS desktop pictures — instead of the user's Photos.
/// What screenshots and the board comparison run on: no PhotoKit prompt,
/// the same days and EXIF every time, and never a photo of a person
/// (the user's own library has them; tests and screenshots must not).
enum MacDemoLibrary {
    static let argument = "-ShotDexDemoLibrary"

    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains(argument) }

    /// Days as on board `Main`: Monday Sep 28 (48), Sunday Sep 27 (112),
    /// then shorter days back through September.
    static let days: [(month: Int, day: Int, count: Int)] = [(9, 28, 48), (9, 27, 112), (9, 26, 21), (9, 24, 9), (9, 21, 36)]

    @MainActor
    static func dependencies() -> MacDependencies {
        // `-ShotDexDemoDatabase <name>`: the demo on a database file in the
        // app's temporary folder (the sandbox allows no other) that outlives
        // the run — what a Resume banner after a kill needs.
        let arguments = ProcessInfo.processInfo.arguments
        // `-ShotDexDemoDatabaseReset`: delete every demo database file in the
        // temporary folder first — the ones `-ShotDexDemoDatabase` left.
        if arguments.contains("-ShotDexDemoDatabaseReset") {
            let tmp = FileManager.default.temporaryDirectory
            for name in (try? FileManager.default.contentsOfDirectory(atPath: tmp.path)) ?? []
            where name.hasPrefix("resume") && name.contains(".sqlite") {
                try? FileManager.default.removeItem(at: tmp.appendingPathComponent(name))
                MacAgentProbe.log.notice("demo database removed: \(tmp.appendingPathComponent(name).path, privacy: .public)")
            }
        }
        let file = arguments.firstIndex(of: "-ShotDexDemoDatabase").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
            .map { FileManager.default.temporaryDirectory.appendingPathComponent($0).path }
        let isNewFile = file.map { !FileManager.default.fileExists(atPath: $0) } ?? true
        let database = file.flatMap { try? AppDatabase(DatabasePool(path: $0)) }
            ?? (try? AppDatabase.makeEmpty()) ?? { fatalError("Cannot create database") }()
        if isNewFile, let state = originalCheckState { seedOriginalCheck(database, state: state) }
        // The demo's albums are slices of its photos (no PhotoKit).
        LibraryPlace.albumAssetIds = { albumPhotoIds($0) }
        let dependencies = MacDependencies(database: database, photoLibrary: PhotoLibraryService(),
                                           originalCheck: originalCheckState.map { _ in originalCheckEnvironment(database) })
        // A database file kept from an earlier launch is seeded once.
        guard isNewFile else { return dependencies }
        // `emptyLibrary`: the first run has nothing — no rows, backups or
        // albums; Add Photos Library… calls seedRows.
        guard section != "emptyLibrary" else { return dependencies }
        try? dependencies.metadataStore.saveBatch(rows(), cursorAssetId: nil)
        if section == "onThisDay" { seedOnThisDay(dependencies) }
        // `deleteCopies` (board `MAC_DeleteCopies`): RAW photos also on a
        // drive (the copy they open from) and on the NAS — three copies each.
        if section == "deleteCopies" { seedDeleteCopies(dependencies) }
        if section == "onServer" { seedOnServer(dependencies) }
        if section == "activity" { seedActivity(dependencies) }
        // `viewer` (board `MAC_Viewer`): every fourth photo edited in ShotDex.
        if section == "viewer" {
            var recipe = PhotoEditRecipe.identity
            recipe.adjustments.exposure = 0.3
            recipe.adjustments.highlights = -0.4
            recipe.adjustments.contrast = 0.15
            let store = PhotoRecipeStore(database: dependencies.database)
            for row in rows().enumerated() where row.offset % 4 == 0 { try? store.save(recipe, photoId: row.element.assetId) }
        }
        // `hidden` (board `MAC_Hidden`): four photos of Sep 28, two of Sep 27.
        if section == "hidden" {
            try? HiddenCopyStore(database: dependencies.database)
                .hide(photoIds: ["demo-0-2", "demo-0-5", "demo-0-8", "demo-0-11", "demo-1-4", "demo-1-9"])
        }
        // The sidebar foot as on board `Main`: "Up to date · indexed 2 min ago".
        if var state = try? dependencies.metadataStore.indexState() {
            state.lastIndexedAt = Int(Date().timeIntervalSince1970) - 120
            try? dependencies.metadataStore.saveIndexState(state)
        }
        seedBackups(dependencies)
        // A smart album as on board `MAC_SmartAlbum`'s sidebar.
        try? dependencies.smartAlbums.upsert(SmartAlbum(
            id: "demo-night", name: "Night ISO 3200+",
            query: SmartAlbumQuery(rules: [SmartAlbumRule(field: .iso, op: .greaterThan, number: 3199)]),
            createdAt: 1))
        // One that matches nothing, for the empty state (`empty` tweak).
        try? dependencies.smartAlbums.upsert(SmartAlbum(
            id: "demo-empty", name: "ISO 100000+",
            query: SmartAlbumQuery(rules: [SmartAlbumRule(field: .iso, op: .greaterThan, number: 99_999)]),
            createdAt: 2))
        if originalCheckState != nil {
            // Board `MAC_SmartAlbum`'s `original` tweak (FS-06.10 §3).
            try? dependencies.smartAlbums.upsert(SmartAlbum(
                id: originalAlbumId, name: "Originals in iCloud",
                query: SmartAlbumQuery(rules: [SmartAlbumRule(field: .original, op: .isExactly, text: OriginalPresence.iCloudOnly.rawValue)]),
                createdAt: 3))
        }
        return dependencies
    }

    /// The board's edit (`MAC_Viewer` Edits): three sliders moved.
    static var viewerRecipe: PhotoEditRecipe {
        var recipe = PhotoEditRecipe.identity
        recipe.adjustments.exposure = 0.3
        recipe.adjustments.highlights = -0.4
        recipe.adjustments.contrast = 0.15
        return recipe
    }

    static let originalAlbumId = "demo-original"

    /// `-ShotDexSection smartAlbumEditor` (board `MAC_SmartAlbumEditor`): a
    /// line of each value shape and a nested "Any" group of two lenses.
    static var editorBoardQuery: SmartAlbumQuery {
        SmartAlbumQuery(matchMode: .all, rules: [
            SmartAlbumRule(field: .iso, op: .inRange, number: 100, numberUpper: 6400),
            SmartAlbumRule(field: .shutter, op: .lessThan, number: 1.0 / 125),
            SmartAlbumRule(field: .dateTaken, op: .inLastDays, number: 365),
            SmartAlbumRule(field: .rating, op: .atLeast, number: 0),
        ], groups: [
            SmartAlbumRuleGroup(matchMode: .any, rules: [
                SmartAlbumRule(field: .lens, op: .isExactly, text: "FE 85mm F1.8"),
                SmartAlbumRule(field: .lens, op: .isExactly, text: "XF56mmF1.2 R WR"),
            ]),
        ])
    }

    /// `-ShotDexOriginalCheck checking|checked`: the originals check part
    /// way through, or done 3 minutes ago, with every third photo in iCloud
    /// only — the demo's ids are not in Photos, so the real probe would
    /// only ever answer "can't tell".
    static var originalCheckState: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ShotDexOriginalCheck"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// Answers nothing, ever: the seeded state stays on screen.
    private static func originalCheckEnvironment(_ database: AppDatabase) -> OriginalPresenceCheck.Environment {
        OriginalPresenceCheck.Environment(store: OriginalPresenceStore(database: database), check: { _ in
            try? await Task.sleep(for: .seconds(3600))
            return [:]
        })
    }

    private static func seedOriginalCheck(_ database: AppDatabase, state: String) {
        let now = Int64(Date().timeIntervalSince1970)
        let isDone = state == "checked"
        let ids = rows().map(\.assetId)
        // 12,400 of 55,000 is 22.5 %, as the board draws it.
        let checked = isDone ? ids : Array(ids.prefix(ids.count * 225 / 1000))
        try? database.writer.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO original_presence_pass (id, startedAt, finishedAt) VALUES (1, ?, ?)",
                           arguments: [now - 600, isDone ? now - 180 : nil])
            for (index, id) in checked.enumerated() {
                try db.execute(sql: "INSERT OR REPLACE INTO original_presence (photoKitId, state, checkedAt) VALUES (?, ?, ?)",
                               arguments: [id, (index % 3 == 0 ? OriginalPresence.iCloudOnly : .onDevice).rawValue, now - 300])
            }
        }
    }

    /// Two jobs as on board `MAC_Backup`: one up to date, one whose server
    /// is out of reach. Nothing runs in the demo; the states are written.
    @MainActor
    private static func seedBackups(_ dependencies: MacDependencies) {
        let home = FileServer(name: "NAS Home", transferProtocol: .webdav, host: "nas.local", username: "demo")
        let studio = FileServer(name: "Studio SMB", transferProtocol: .smb, host: "studio.local", username: "demo")
        try? dependencies.fileServers.save(home, password: nil)
        try? dependencies.fileServers.save(studio, password: nil)
        var settings = BackupSettings()
        settings.onlyOnWiFi = false
        let first = BackupJob(sourceId: PhotoLibrarySource.id, connectionId: home.id, folder: "Backup/Mac", settings: settings)
        let second = BackupJob(sourceId: PhotoLibrarySource.id, connectionId: studio.id, folder: "Clients/2026", settings: settings, sortOrder: 1)
        try? dependencies.backups.add(first)
        try? dependencies.backups.add(second)
        var watching = BackupJobState(jobId: first.id)
        watching.lastCheckedAt = Int(Date().timeIntervalSince1970) - 120
        watching.hasFinishedFirstRun = true
        var stuck = BackupJobState(jobId: second.id)
        stuck.status = .unreachable
        stuck.statusTotal = 12
        stuck.statusDone = 0
        try? dependencies.backups.save(watching)
        try? dependencies.backups.save(stuck)
        dependencies.backupCoordinator.reload()
    }

    /// `-ShotDexSection serverBrowser`: a server source on the local
    /// impacket SMB server (127.0.0.1:4450, share `photos`, tester/secret;
    /// the share is the source), read once, then opened.
    /// The demo database is in memory, so nothing outlives the run but the
    /// connection's Keychain item, kept under one fixed id.
    @MainActor
    static func seedServerSource(_ dependencies: MacDependencies) async -> MacSidebarItem? {
        guard isOn else { return nil }
        let server = FileServer(id: "demo-smb-browse", name: "Test SMB", transferProtocol: .smb, host: "127.0.0.1", port: 4450,
                                username: "tester", folder: "photos")
        try? dependencies.fileServers.save(server, password: "secret")
        await dependencies.sourcesModel.setServerSource(true, connection: server)
        guard let sourceId = (try? SourceStore(database: dependencies.database).serverSourceId(connectionId: server.id)) ?? nil
        else { return nil }
        // Marks as on the board: stars on two photos, a pick on one.
        try? await dependencies.database.writer.write { db in
            let photos = try String.fetchAll(db, sql: """
                SELECT photoId FROM photo_copies WHERE sourceId = ? AND relativePathKey LIKE 'tuan/2025/06/%' ORDER BY relativePathKey LIMIT 3
                """, arguments: [sourceId])
            for (photoId, rating) in zip(photos, [3, 0, 5]) where rating > 0 {
                try db.execute(sql: "INSERT OR REPLACE INTO photo_user_marks (photoId, rating, ratingAt) VALUES (?, ?, 1)", arguments: [photoId, rating])
            }
            if photos.count > 1 {
                try db.execute(sql: "INSERT OR REPLACE INTO photo_flag (assetId, flag, flaggedAt) VALUES (?, ?, 1)",
                               arguments: [photos[1], PhotoFlag.pick.rawValue])
            }
        }
        return .source(sourceId)
    }

    /// `-ShotDexSection uploads` (board `MAC_ServerUpload`): upload history
    /// for the On Server place — 40 photos in three places on two servers,
    /// keyed like the demo's own upload files, so Free Up Space has photos.
    @MainActor
    static func seedUploads(_ dependencies: MacDependencies) {
        guard isOn else { return }
        seedUploadServer(dependencies)
        // The demo database's newest photos: the window's rows may not be read yet.
        let rows = (try? dependencies.database.reader.read { db in
            try Row.fetchAll(db, sql: "SELECT assetId, originalFilename FROM photo_metadata ORDER BY creationDate DESC LIMIT 40")
                .map { (assetId: $0["assetId"] as String, originalFilename: $0["originalFilename"] as String?) }
        }) ?? []
        // A place with no connection row: an upload whose connection was deleted (name kept).
        let places: [(String?, String, String)] = [("demo-smb-upload", "Test SMB", "photos/Uploads/2026-09-28"),
                      ("demo-smb-upload", "Test SMB", "photos/Uploads/2026-09-21"),
                      (nil, "NAS Home", "Photos/2026")]
        let now = Int(Date().timeIntervalSince1970)
        // Again on a kept demo database (-ShotDexDemoDatabase): the same 40, not 40 more.
        try? dependencies.database.writer.write { db in try db.execute(sql: "DELETE FROM server_uploads WHERE fileKey LIKE 'demo:%'") }
        for (index, row) in rows.enumerated() {
            let place = places[index % places.count]
            let name = ((row.originalFilename ?? "\(row.assetId).JPG") as NSString).deletingPathExtension + ".JPG"
            let record = ServerUploadRecord(assetId: row.assetId, fileKey: "demo:\(name)", serverId: place.0, serverName: place.1,
                                            remotePath: "\(place.2)/\(name)", byteCount: 400_000, sha256: "demo",
                                            uploadedAt: now - (index % places.count) * 86_400 * 7)
            try? dependencies.serverUploads.record(record)
        }
        dependencies.serverUploadIndex.reload()
    }

    /// `-ShotDexSection upload`: a connection to the local test SMB server,
    /// uploading into `photos/Uploads` — never a real server.
    @MainActor
    static func seedUploadServer(_ dependencies: MacDependencies) {
        guard isOn else { return }
        let server = FileServer(id: "demo-smb-upload", name: "Test SMB", transferProtocol: .smb, host: "127.0.0.1", port: 4450,
                                username: "tester", folder: "photos/Uploads")
        try? dependencies.fileServers.save(server, password: "secret")
        // The sheet opens on the last one used: this one, never the demo's NAS rows.
        try? dependencies.fileServers.markUsed(server.id, folder: "photos/Uploads", usesDateFolders: false)
    }

    /// `-ShotDexUploadFiles /a.jpg,/b.jpg`: Upload… in the server browser
    /// takes these files instead of asking with an open panel.
    static var uploadFiles: [URL]? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ShotDexUploadFiles"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1].split(separator: ",").map { URL(fileURLWithPath: String($0)) }
    }

    /// `-ShotDexServerPath Tuan/2025`: the folder the server browser opens
    /// on, relative to the source's root.
    static var serverPath: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ShotDexServerPath"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// `-ShotDexServerSelect "Tuan,Vo"`: folders of the opened folder picked
    /// once it is listed, as a ⌘-click would (FS-19.08 AC-130).
    static var serverSelect: [String]? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ShotDexServerSelect"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// The Find Common Photos sheet as a screenshot wants it (FS-19.08
    /// AC-130): `-ShotDexCommonPhotosDestination photos/Shared` (a server
    /// path), `-ShotDexCommonPhotosAddFolder photos/Tuan/2025`, `-ShotDexCommonPhotosAction move`, `-ShotDexCommonPhotosScan`
    /// (scan at once), `-ShotDexCommonPhotosSlow` (2 s before each read, to
    /// catch it half done); `-ShotDexCommonPhotosConfirm` asks the Move
    /// question once the scan is done.
    @MainActor
    static func prepareCommonPhotos(_ model: CommonPhotosScanModel) {
        let arguments = ProcessInfo.processInfo.arguments
        func value(_ name: String) -> String? {
            arguments.firstIndex(of: name).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
        }
        if let destination = value("-ShotDexCommonPhotosDestination") { model.destination = destination }
        if let folder = value("-ShotDexCommonPhotosAddFolder") { model.add(folder: folder) }
        if value("-ShotDexCommonPhotosAction") == "move" { model.action = .move }
        if arguments.contains("-ShotDexCommonPhotosSlow") { model.groupDelay = .seconds(2) }
        // `-ShotDexCommonPhotosNoDates`: the sheet as on a server that lost the dates last time (§6e).
        if arguments.contains("-ShotDexCommonPhotosNoDates") { model.serverKeepsNoDates = true }
        // `-ShotDexCommonPhotosQuick`: Quick check on (§6e).
        if arguments.contains("-ShotDexCommonPhotosQuick") { model.quickCheck = true }
        // `-ShotDexCommonPhotosOrganize yearMonthDay`: the set's Organize levels (§6e).
        if let levels = value("-ShotDexCommonPhotosOrganize").flatMap(BackupOrganize.Levels.init(rawValue:)) {
            var organize = model.organize
            organize.levels = levels
            model.organize = organize
        }
        if arguments.contains("-ShotDexCommonPhotosScan") { model.scan() }
    }

    /// A run's client as a screenshot wants it (FS-19.08 §7):
    /// `-ShotDexCommonPhotosRunSlow` waits 3 s before each upload and move, so
    /// the window can be caught mid-run; `-ShotDexCommonPhotosFailAfter N`
    /// drops the connection at the upload or move after the N-th.
    static func commonPhotosRunClient(_ client: any RemoteFileClient, forRestore: Bool = false) -> any RemoteFileClient {
        let arguments = ProcessInfo.processInfo.arguments
        let slow = arguments.contains("-ShotDexCommonPhotosRunSlow")
        let failAfter = arguments.firstIndex(of: "-ShotDexCommonPhotosFailAfter")
            .flatMap { $0 + 1 < arguments.count ? Int(arguments[$0 + 1]) : nil }
        // `-ShotDexCommonPhotosNoDateKeeping`: a server that sets no dates for
        // a run; `-ShotDexCommonPhotosRestoreRefuses`: nor for Restore File Info… (§6e).
        let keepsNoDates = arguments.contains(forRestore ? "-ShotDexCommonPhotosRestoreRefuses" : "-ShotDexCommonPhotosNoDateKeeping")
        guard slow || failAfter != nil || keepsNoDates else { return client }
        return MacDebugRunClient(base: client, delay: slow ? .seconds(3) : nil, failAfter: failAfter, keepsNoDates: keepsNoDates)
    }

    /// `-ShotDexServerLayout list`: the server browser's view mode.
    static var serverLayout: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ShotDexServerLayout"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// `-ShotDexSection backup`: the sidebar place the window opens on.
    static var section: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ShotDexSection"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// `-ShotDexAgentStatus requiresApproval|enabled`: the helper state
    /// Settings shows, without touching the real login item.
    static var agentStatus: SMAppService.Status? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ShotDexAgentStatus"), index + 1 < arguments.count else { return nil }
        switch arguments[index + 1] {
        case "requiresApproval": return .requiresApproval
        case "enabled": return .enabled
        case "notRegistered": return .notRegistered
        default: return nil
        }
    }

    /// `-ShotDexSection onThisDay` (board `MAC_OnThisDay`): 26 photos taken on
    /// today's month and day 5, 3 and 1 years ago, each year in one place.
    private static func seedOnThisDay(_ dependencies: MacDependencies) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = Date()
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        let years: [(ago: Int, count: Int, town: String, country: String)] = [
            (5, 5, "Hanoi", "Vietnam"), (3, 7, "Banff", "Canada"), (1, 14, "Kyoto", "Japan"),
        ]
        let shots = Self.rows()
        var rows: [PhotoMetadata] = []
        var places: [(String, String, String)] = []
        for year in years {
            guard let start = calendar.date(from: DateComponents(year: today.year! - year.ago, month: today.month, day: today.day, hour: 17)) else { continue }
            for n in 0..<year.count {
                var row = shots[(n * 7 + year.ago) % 200]
                row.assetId = "demo-otd-\(year.ago)-\(n)"
                row.creationDate = Int(start.timeIntervalSince1970) - n * 120
                row.isFavorite = false
                rows.append(row)
                places.append((row.assetId, year.town, year.country))
            }
        }
        try? dependencies.metadataStore.saveBatch(rows, cursorAssetId: nil)
        try? dependencies.database.writer.write { db in
            for (id, town, country) in places {
                try db.execute(sql: "UPDATE photo_metadata SET placeLocality = ?, placeCountry = ? WHERE assetId = ?",
                               arguments: [town, country, id])
            }
        }
    }

    private static func seedDeleteCopies(_ dependencies: MacDependencies) {
        let now = Int(Date().timeIntervalSince1970)
        try? dependencies.database.writer.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO sources (id, kind, name, pairsRawAndJpeg, createdAt) VALUES ('demo-t7', 'drive', 'T7 RAW Archive', 1, ?)",
                           arguments: [now])
            try db.execute(sql: "INSERT OR REPLACE INTO sources (id, kind, name, pairsRawAndJpeg, createdAt) VALUES ('demo-nas', 'server', 'NAS Home', 1, ?)",
                           arguments: [now])
            for (source, kind) in [("demo-t7", "file"), ("demo-nas", "server")] {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO photo_copies (id, photoId, sourceId, kind, relativePath, relativePathKey, isOnline, lastSeenAt)
                    SELECT ? || ':' || m.assetId, m.assetId, ?, ?, 'RAW/2026-09-27/' || m.originalFilename,
                           lower('RAW/2026-09-27/' || m.originalFilename) || m.assetId, 1, ?
                    FROM photo_metadata m
                    WHERE upper(m.originalFilename) LIKE '%.ARW' OR upper(m.originalFilename) LIKE '%.RAF' OR upper(m.originalFilename) LIKE '%.CR3'
                    """, arguments: [source, source, kind, now])
            }
        }
    }

    /// `-ShotDexSection activity` (board `MAC_Activity`): nine common-photos
    /// runs over, on a connection with no password and nothing to dial —
    /// eight finished, one stopped — so the popover's list scrolls and each
    /// row's buttons are there to press. Rows only, no network.
    @MainActor
    private static func seedActivity(_ dependencies: MacDependencies) {
        let now = Int(Date().timeIntervalSince1970)
        try? dependencies.database.writer.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO file_servers (id, name, transferProtocol, host, port, username, share, folder, createdAt)
                VALUES ('demo-activity-nas', 'NAS Home', 'smb', '127.0.0.1', 1, 'demo', 'photos', 'photos', ?)
                """, arguments: [now])
        }
        let store = CommonPhotosStore(database: dependencies.database)
        for index in 0..<9 {
            let run = CommonPhotosRun(id: "demo-activity-\(index)", connectionId: "demo-activity-nas",
                                      folders: ["Tuấn", "Vợ"], destination: "Shared", action: index == 4 ? .move : .copy,
                                      createdAt: now - index * 3600)
            try? store.start(run, items: [])
            try? store.markState(index == 0 ? .stopped : .finished, runId: run.id, now: now - index * 3600 - 600)
        }
        // `-ShotDexInterruptedRun`: one more run left going by a quit — the
        // sidebar foot's Resume / Stop (user 2026-11-08).
        if ProcessInfo.processInfo.arguments.contains("-ShotDexInterruptedRun") {
            let run = CommonPhotosRun(id: "demo-activity-interrupted", connectionId: "demo-activity-nas",
                                      folders: ["Tuấn", "Vợ"], destination: "Shared", action: .copy, createdAt: now - 60)
            try? store.start(run, items: [])
            dependencies.commonPhotos.storeChanged()
        }
    }

    /// `-ShotDexSection onServer` (board `MAC_SmartAlbum`): the smart album
    /// "On NAS — Shared" (Also on Server · Yes · NAS Home › Shared) over a
    /// server source with no connection — no network, only rows. Of the 60
    /// newest photos, 40 have every file hashed and the same bytes under
    /// Shared (on the server), 20 have a file of their size there still
    /// unhashed (being checked).
    static let onServerAlbumId = "demo-on-server"

    private static func seedOnServer(_ dependencies: MacDependencies) {
        let now = Int(Date().timeIntervalSince1970)
        try? dependencies.database.writer.write { db in
            // A connection id with no connection row: the album reads it as a
            // server source (its On Server line), nothing can dial it.
            try db.execute(sql: """
                INSERT OR REPLACE INTO sources (id, kind, name, pairsRawAndJpeg, connectionId, createdAt)
                VALUES ('demo-nas', 'server', 'NAS Home', 1, 'demo-nas-connection', ?)
                """, arguments: [now])
            let photos = try Row.fetchAll(db, sql: """
                SELECT assetId, originalFilename, modificationDate FROM photo_metadata ORDER BY creationDate DESC LIMIT 60
                """)
            for (index, photo) in photos.enumerated() {
                let assetId: String = photo["assetId"]
                let name: String = photo["originalFilename"] ?? "\(assetId).HEIC"
                let copyId = "demo-ph:" + assetId
                let size = 2_000_000 + index
                try db.execute(sql: """
                    INSERT OR REPLACE INTO photo_copies (id, photoId, sourceId, kind, photoKitId, isOnline, lastSeenAt)
                    VALUES (?, ?, ?, 'photos', ?, 1, ?)
                    """, arguments: [copyId, assetId, PhotoLibrarySource.id, assetId, now])
                try db.execute(sql: """
                    INSERT OR REPLACE INTO copy_files (copyId, fileKey, role, size, sha256, origin, hashedAt)
                    VALUES (?, ?, 'photo', ?, ?, 'hashed', ?)
                    """, arguments: [copyId, "photo:" + name, size, "demo-sha-" + assetId, now])
                try db.execute(sql: "INSERT OR REPLACE INTO copy_file_listings (copyId, stamp, listedAt) VALUES (?, ?, ?)",
                               arguments: [copyId, photo["modificationDate"] as DatabaseValue, now])
                // Demo names repeat; one folder a photo keeps every server path its own.
                let path = "Shared/2026/\(index)/" + name
                let serverId = "demo-srv:" + assetId
                try db.execute(sql: """
                    INSERT OR REPLACE INTO photo_copies (id, photoId, sourceId, kind, relativePath, relativePathKey, isOnline, lastSeenAt)
                    VALUES (?, ?, 'demo-nas', 'server', ?, ?, 1, ?)
                    """, arguments: [serverId, "demo-srv-photo:" + assetId, path, path.lowercased(), now])
                // On the server: the same bytes; being checked: its size there, no hash yet.
                let isOnServer = index < 40
                try db.execute(sql: """
                    INSERT OR REPLACE INTO copy_files (copyId, fileKey, role, size, sha256, origin, hashedAt)
                    VALUES (?, 'primary', 'photo', ?, ?, 'hashed', ?)
                    """, arguments: [serverId, size, isOnServer ? "demo-sha-" + assetId : nil, isOnServer ? now : nil])
            }
        }
        try? dependencies.smartAlbums.upsert(SmartAlbum(
            id: onServerAlbumId, name: "On NAS — Shared",
            query: SmartAlbumQuery(rules: [SmartAlbumRule(field: .alsoOnServer, text: "demo-nas", boolValue: true, folder: "Shared")]),
            createdAt: now))
    }

    /// The demo's albums (the photo menu's Add to Album list): each a slice
    /// of the demo photos, covers from them.
    static let albumNames = ["Kyoto Autumn", "Iceland 2026", "Portfolio", "Dolomites", "Street 2025", "Night Walks"]

    static func albumPhotoIds(_ albumId: String) -> [String]? {
        guard let index = albumNames.firstIndex(where: { "demo-album-\($0)" == albumId }) else { return nil }
        let ids = rows().map(\.assetId)
        return Array(ids.dropFirst(index * 11).prefix(8 + index * 3))
    }

    static func albumSummaries() -> [AlbumSummary] {
        albumNames.map { name in
            let ids = albumPhotoIds("demo-album-\(name)") ?? []
            return AlbumSummary(id: "demo-album-\(name)", title: name, count: ids.count, coverAssetId: ids.first)
        }
    }

    static func rows() -> [PhotoMetadata] {
        let lenses: [(camera: String, lens: String, focal: Double, aperture: Double, iso: Int)] = [
            ("ILCE-7M4", "FE 85mm F1.8", 85, 1.8, 400), ("EOS R6m2", "RF35mm F1.8 MACRO IS STM", 35, 1.4, 3200),
            ("X-T5", "XF16mmF2.8 R WR", 16, 11, 125), ("ILCE-7M4", "FE 24mm F1.4 GM", 24, 8, 100),
            ("X-T5", "XF56mmF1.2 R WR", 56, 1.2, 250), ("EOS R6m2", "RF70-200mm F2.8 L IS USM", 135, 1.8, 640),
            ("ILCE-7M4", "FE 50mm F1.2 GM", 50, 2, 800), ("X-T5", "XF23mmF1.4 R LM WR", 23, 2, 1600),
        ]
        let formats = ["HEIC", "RAF", "JPG", "ARW", "HEIC", "CR3", "JPG"]
        var rows: [PhotoMetadata] = []
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        for (dayIndex, day) in days.enumerated() {
            let start = calendar.date(from: DateComponents(year: 2026, month: day.month, day: day.day, hour: 18))!
            for n in 0..<day.count {
                let shot = lenses[(n + dayIndex) % lenses.count]
                let id = "demo-\(dayIndex)-\(n)"
                let ext = n % 17 == 5 ? "MOV" : formats[(n + dayIndex * 3) % formats.count]
                rows.append(PhotoMetadata(
                    assetId: id, creationDate: Int(start.timeIntervalSince1970) - n * 90, modificationDate: nil, mediaType: n % 17 == 5 ? 2 : 1,
                    cameraManufacturer: nil, cameraModel: shot.camera, normalizedCameraModel: shot.camera,
                    normalizedCameraManufacturer: nil, lensManufacturer: nil, lensModel: shot.lens, normalizedLensModel: shot.lens,
                    originalFilename: String(format: "DSC%05d.%@", 4100 + n, ext), iso: shot.iso, aperture: shot.aperture,
                    shutterSpeedSeconds: 1 / 250, shutterSpeedDisplay: "1/250", focalLength: shot.focal, focalLengthIn35mm: nil,
                    calculatedEquivalentFocalLength: nil, equivalentFocalLength: shot.focal, sensorFormat: nil, cropFactor: nil,
                    width: 6000, height: 4000, fileSize: 24_000_000, latitude: nil, longitude: nil, isFavorite: n % 11 == 3,
                    indexedAt: 1, exifStatus: ExifStatus.indexed.rawValue
                ))
            }
        }
        return rows
    }

    /// The demo's rows, written off the main actor (Add Photos Library… on
    /// the `emptyLibrary` demo).
    static func seedRows(_ dependencies: MacDependencies) async {
        let store = dependencies.metadataStore
        let rows = rows()
        await Task.detached(priority: .userInitiated) { try? store.saveBatch(rows, cursorAssetId: nil) }.value
    }

    /// `-ShotDexDemoScale N`: N − 1 more copies of the library, a week apart
    /// each, for measuring a click at the size of a real library (55k ≈ 200).
    /// Written on a background task after launch — the window must not wait
    /// for the seeding — then the grid reloads.
    static func seedScaleIfAsked(_ dependencies: MacDependencies, then done: @escaping @MainActor () -> Void) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let scale = arguments.firstIndex(of: "-ShotDexDemoScale").flatMap({ $0 + 1 < arguments.count ? Int(arguments[$0 + 1]) : nil }),
              scale > 1
        else { return }
        let store = dependencies.metadataStore
        let queries = dependencies.libraryQueries
        let base = rows()
        Task.detached(priority: .utility) {
            // A database file kept from an earlier run (`-ShotDexDemoDatabase`,
            // the way to run this: a pool reads while it writes) has them.
            if let count = try? queries.count(matching: FilterCriteria.empty), count >= base.count * scale {
                await MainActor.run { done() }
                return
            }
            for copy in 1..<scale {
                let batch = base.map { row in
                    var row = row
                    row.assetId += "-x\(copy)"
                    row.creationDate = row.creationDate.map { $0 - copy * 86_400 * 7 }
                    return row
                }
                try? store.saveBatch(batch, cursorAssetId: nil)
            }
            await MainActor.run { done() }
        }
    }

    /// Landscape desktop pictures, decoded once, cycled over the tiles.
    private static let pictures: [CGImage] = {
        let folder = URL(fileURLWithPath: "/System/Library/Desktop Pictures/.thumbnails", isDirectory: true)
        let names = ["Big Sur Coastline", "Catalina Rock", "Big Sur Mountains", "Catalina Coast", "Big Sur Waters Edge",
                     "Catalina Evening", "Big Sur Horizon", "Catalina Shoreline", "Big Sur Road", "Catalina Clouds",
                     "Big Sur Shore Rocks", "Catalina Sunset", "Big Sur Aerial", "Catalina Silhouette"]
        // `-ShotDexDemoLargePhotos`: four pictures blown up to 2400 px, so the
        // full-screen viewer has a photo bigger than the screen (its Navigator).
        let isLarge = ProcessInfo.processInfo.arguments.contains("-ShotDexDemoLargePhotos")
        return (isLarge ? Array(names.prefix(4)) : names).compactMap { name in
            let url = folder.appendingPathComponent(name + ".heic")
            // Decoded now, once: a lazy HEIC would decode on the main thread
            // at every display and show up as the app's own cost.
            let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
            let image = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, options) }
            return isLarge ? image.flatMap { scaled($0, side: 2400) } : image
        }
    }()

    private static func scaled(_ image: CGImage, side: Int) -> CGImage? {
        let height = side * image.height / max(1, image.width)
        guard let context = CGContext(data: nil, width: side, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: height))
        return context.makeImage()
    }

    /// `-ShotDexSection viewerCloud` (board `MAC_ViewerCloudDownload`): the
    /// photo whose file stands in for one only in iCloud Drive.
    static var cloudIds: Set<String> = []

    static func cloudFile(for assetId: String) -> MacPhotoFile? {
        guard cloudIds.contains(assetId) else { return nil }
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/2026 Japan/IMG_4120.JPG")
        return MacPhotoFile(url: url, isPlaceholder: true, size: 3_000_000, sourceName: "2026 Japan",
                            displayPath: MacPhotoFiles.displayPath(url), provider: MacPhotoFiles.provider(url))
    }

    static func picture(for assetId: String) -> CGImage? {
        guard !pictures.isEmpty else { return nil }
        let index = abs(assetId.hashValue == 0 ? 0 : Int(assetId.split(separator: "-").last.flatMap { Int($0) } ?? 0))
        let day = Int(assetId.split(separator: "-").dropFirst().first.flatMap { Int($0) } ?? 0)
        return pictures[(index + day * 5) % pictures.count]
    }

    /// The demo pictures as JPEG files (Quick Look, Share), one per id.
    static func pictureFiles(for ids: [String]) -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ShotDexDemo", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return ids.compactMap { id in
            let url = folder.appendingPathComponent("\(id).jpg")
            if FileManager.default.fileExists(atPath: url.path) { return url }
            guard let image = picture(for: id),
                  let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, image, nil)
            return CGImageDestinationFinalize(destination) ? url : nil
        }
    }
}
#endif

#if DEBUG
import os
import ServiceManagement

/// `-ShotDexAgentProbe seed|remove`: a test job for the helper on the real
/// database — Photos → a WebDAV server at 127.0.0.1:1 that is never there,
/// so the helper runs, writes Can't Reach and copies nothing. `remove`
/// deletes it and unregisters the helper.
enum MacAgentProbe {
    static let serverName = "Agent Probe"
    static let log = Logger(subsystem: "com.hoangtuan.shotdex", category: "agent")

    static var mode: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ShotDexAgentProbe"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    @MainActor
    static func runIfAsked(_ dependencies: MacDependencies) {
        switch mode {
        case "seed":
            let existing = ((try? dependencies.fileServers.fetchAll()) ?? []).first { $0.name == serverName }
            let server = existing ?? FileServer(name: serverName, transferProtocol: .webdav, host: "127.0.0.1", port: 1,
                                                username: "probe", usesTLS: false)
            if existing == nil { try? dependencies.fileServers.save(server, password: nil) }
            var settings = BackupSettings()
            settings.onlyOnWiFi = false
            let job = BackupJob(sourceId: PhotoLibrarySource.id, connectionId: server.id, folder: "Probe", settings: settings)
            if (try? dependencies.backups.existingJob(sourceId: job.sourceId, connectionId: server.id, folder: "Probe")) == nil {
                try? dependencies.backups.add(job)
                dependencies.backupControl.jobsChanged(start: job.id)
            }
            log.notice("probe seeded; agent status \(MacAgentLink.service.status.rawValue)")
        case "remove":
            for server in ((try? dependencies.fileServers.fetchAll()) ?? []) where server.name == serverName {
                for job in ((try? dependencies.backups.jobs()) ?? []) where job.connectionId == server.id {
                    try? dependencies.backups.delete(id: job.id)
                }
                try? dependencies.fileServers.delete(id: server.id)
            }
            dependencies.backupControl.jobsChanged()
            Task {
                try? await MacAgentLink.service.unregister()
                log.notice("probe removed; agent status \(MacAgentLink.service.status.rawValue)")
                exit(0)
            }
        default:
            break
        }
    }
}
#endif

#if DEBUG
/// `-ShotDexSMBProbe seed|remove`: the Mac path end to end against the local
/// impacket server (127.0.0.1:4450, share `photos`, tester/secret) — the
/// connection, Test Connection, a folder listing, the server source and its
/// index, a smart album on `Source is SMB Test · Shared`, one On Server pass.
/// Every step goes to the `agent` log. `remove` takes it all away again.
enum MacSMBProbe {
    static let name = "SMB Test"
    static let albumId = "probe-smb-shared"

    static var mode: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ShotDexSMBProbe"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    @MainActor
    static func runIfAsked(_ dependencies: MacDependencies, open: @escaping (MacSidebarItem) -> Void) {
        let log = MacAgentProbe.log
        switch mode {
        case "seed":
            Task { @MainActor in
                let servers = dependencies.fileServers
                let server = ((try? servers.fetchAll()) ?? []).first { $0.name == name }
                    ?? FileServer(name: name, transferProtocol: .smb, host: "127.0.0.1", port: 4450,
                                  username: "tester", folder: "photos/Photos")
                try? servers.save(server, password: "secret")
                let client = RemoteFileClientFactory.make(for: server, password: "secret")
                let outcome = await FileServerConnectionCheck.run(client: client, folder: server.folder)
                log.notice("smb test connection: \(String(describing: outcome), privacy: .public)")
                // As the Mac folder picker does: its own client, connected, then listed.
                let browser = RemoteFileClientFactory.make(for: server, password: "secret")
                do {
                    try await browser.connect()
                    let folders = try await browser.folderNames(in: server.folder)
                    log.notice("smb folders in photos/Photos: \(folders.sorted().joined(separator: ", "), privacy: .public)")
                } catch {
                    log.error("smb folder listing failed: \(String(describing: error), privacy: .public)")
                }
                await browser.disconnect()
                await dependencies.sourcesModel.setServerSource(true, connection: server)
                let store = SourceStore(database: dependencies.database)
                guard let sourceId = (try? store.serverSourceId(connectionId: server.id)) ?? nil else {
                    log.error("smb source not created")
                    return
                }
                let count = (try? store.photoCounts())?[sourceId] ?? 0
                log.notice("smb source \(sourceId, privacy: .public) indexed \(count) photos")
                let album = SmartAlbum(id: albumId, name: "On SMB — Shared",
                                       query: SmartAlbumQuery(rules: [SmartAlbumRule(field: .source, text: sourceId, folder: "Shared")]),
                                       createdAt: Int(Date().timeIntervalSince1970))
                try? dependencies.smartAlbums.upsert(album)
                let matching = (try? await dependencies.libraryQueries.count(matching: album.query)) ?? -1
                log.notice("smart album Source is SMB Test · Shared matches \(matching)")
                // Through the control: the helper runs the pass when it is on.
                dependencies.backupControl.sourcesChanged()
                try? await Task.sleep(for: .seconds(20))
                let progress = try? OnServerProgressQueries(database: dependencies.database).progress(sourceId: sourceId, folder: "Shared")
                log.notice("on server progress: \(String(describing: progress), privacy: .public); waits \(String(describing: dependencies.onServerCheck.waits), privacy: .public)")
                open(.smartAlbum(albumId))
            }
        case "addPhotos":
            // The share's pictures into Photos, byte for byte, so the check
            // has something to match. Their ids are kept for `removePhotos`.
            Task { @MainActor in
                let folder = URL(fileURLWithPath: "/private/tmp/shotdex-mac/import")
                let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                    .filter { $0.pathExtension.lowercased() == "heic" }
                var ids: [String] = []
                for file in files {
                    var placeholder: String?
                    do {
                        try await PHPhotoLibrary.shared().performChanges {
                            let request = PHAssetCreationRequest.forAsset()
                            let options = PHAssetResourceCreationOptions()
                            options.originalFilename = file.lastPathComponent
                            request.addResource(with: .photo, fileURL: file, options: options)
                            placeholder = request.placeholderForCreatedAsset?.localIdentifier
                        }
                        if let placeholder { ids.append(placeholder) }
                    } catch {
                        log.error("import \(file.lastPathComponent, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                    }
                }
                MacAgentLink.defaults.set(ids, forKey: "smbProbeAssets")
                log.notice("imported \(ids.count) of \(files.count) pictures into Photos")
                exit(0)
            }
        case "gateCheck":
            // What Delete would be told for the album's photos — asks the
            // server, deletes nothing.
            Task { @MainActor in
                let ids = MacAgentLink.defaults.stringArray(forKey: "smbProbeAssets") ?? []
                log.notice("gate: \(PhotoLibraryService.fetchAssets(ids: ids).count) of \(ids.count) probe pictures still in Photos")
                let outcome = await dependencies.photoDeletionGate.check(photoIds: ids)
                log.notice("gate: deletable \(outcome.deletable.count), verified \(outcome.verified.count), unreachable \(outcome.unreachable.keys.sorted(), privacy: .public), not on server \(outcome.notOnServer.keys.sorted(), privacy: .public)")
                exit(0)
            }
        case "diagnose":
            // Why a probe picture does or does not match: PhotoKit's size and
            // bytes against the file it came from, and the check's rows.
            Task { @MainActor in
                let ids = MacAgentLink.defaults.stringArray(forKey: "smbProbeAssets") ?? []
                let folder = URL(fileURLWithPath: "/private/tmp/shotdex-mac/import")
                let work = FileManager.default.temporaryDirectory.appendingPathComponent("probe-diagnose", isDirectory: true)
                try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                for asset in PhotoLibraryService.fetchAssets(ids: ids) {
                    for file in PhotoKitOriginalExporter.uploadFiles(for: asset) {
                        let source = folder.appendingPathComponent(file.filename)
                        let sourceSize = (try? FileManager.default.attributesOfItem(atPath: source.path)[.size] as? NSNumber)?.int64Value ?? -1
                        let sourceSHA = (try? FileChecksum.sha256(of: source)) ?? "-"
                        var exportedSize: Int64 = -1
                        var exportedSHA = "-"
                        if let url = try? await PhotoKitOriginalExporter().export(assetId: asset.localIdentifier, file: file, into: work) {
                            exportedSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? -1
                            exportedSHA = (try? FileChecksum.sha256(of: url)) ?? "-"
                            try? FileManager.default.removeItem(at: url)
                        }
                        log.notice("diag \(file.filename, privacy: .public) key \(file.key, privacy: .public): photos size \(file.estimatedBytes) exported \(exportedSize) source \(sourceSize); sha equal \(exportedSHA == sourceSHA)")
                    }
                    let assetId = asset.localIdentifier
                    let rows: [String] = (try? await dependencies.database.reader.read { db in
                        try Row.fetchAll(db, sql: """
                            SELECT f.fileKey, f.size, f.sha256 IS NOT NULL AS hashed, f.lastError
                            FROM photo_copies c JOIN copy_files f ON f.copyId = c.id WHERE c.photoKitId = ?
                            """, arguments: [assetId]).map { row -> String in
                            let key: String = row["fileKey"] ?? "?"
                            let size: Int64 = row["size"] ?? -1
                            let hashed: Bool = row["hashed"] ?? false
                            let error: String = row["lastError"] ?? "-"
                            return "\(key) size \(size) hashed \(hashed) err \(error)"
                        }
                    }) ?? []
                    let copies: Int = (try? await dependencies.database.reader.read { db in
                        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_copies WHERE photoKitId = ?", arguments: [assetId]) ?? 0
                    }) ?? 0
                    log.notice("diag rows for \(assetId, privacy: .public): copies \(copies), files \(rows.joined(separator: " | "), privacy: .public)")
                }
                let server: [String] = (try? await dependencies.database.reader.read { db in
                    try Row.fetchAll(db, sql: """
                        SELECT c.relativePath, f.size, f.sha256 IS NOT NULL AS hashed FROM photo_copies c
                        JOIN copy_files f ON f.copyId = c.id WHERE c.kind = 'server'
                        """).map { row -> String in
                        let path: String = row["relativePath"] ?? "?"
                        let size: Int64 = row["size"] ?? -1
                        let hashed: Bool = row["hashed"] ?? false
                        return "\(path) \(size) hashed \(hashed)"
                    }
                }) ?? []
                log.notice("diag server files: \(server.joined(separator: " | "), privacy: .public)")
                exit(0)
            }
        case "staleCheck":
            // Rows for Photos items that are no longer in Photos, after the
            // index has had its say: what a smart album could still show.
            Task { @MainActor in
                let database = dependencies.database
                let ids: [String] = (try? await database.reader.read { db in
                    try String.fetchAll(db, sql: "SELECT DISTINCT photoKitId FROM photo_copies WHERE kind = 'photos' AND photoKitId IS NOT NULL")
                }) ?? []
                var present = Set<String>()
                for chunk in stride(from: 0, to: ids.count, by: 2_000) {
                    let slice = Array(ids[chunk..<min(chunk + 2_000, ids.count)])
                    let options = PHFetchOptions()
                    options.includeHiddenAssets = true
                    options.includeAllBurstAssets = true
                    let found = PHAsset.fetchAssets(withLocalIdentifiers: slice, options: options)
                    found.enumerateObjects { asset, _, _ in present.insert(asset.localIdentifier) }
                }
                let stale = ids.filter { !present.contains($0) }
                let orphanFiles: Int = (try? await database.reader.read { db in
                    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM copy_files WHERE copyId NOT IN (SELECT id FROM photo_copies)") ?? 0
                }) ?? 0
                let hiddenOrBurst = present.subtracting(PhotoLibraryService.fetchAssets(ids: Array(present)).map(\.localIdentifier)).count
                log.notice("stale: hidden or burst \(hiddenOrBurst)")
                log.notice("stale: \(stale.count) of \(ids.count) Photos copies point at items gone from Photos; \(orphanFiles) copy_files rows have no copy")
                exit(0)
            }
        case "removePhotos":
            Task { @MainActor in
                let ids = MacAgentLink.defaults.stringArray(forKey: "smbProbeAssets") ?? []
                let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
                do {
                    try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(assets) }
                    MacAgentLink.defaults.removeObject(forKey: "smbProbeAssets")
                    log.notice("removed \(assets.count) probe pictures from Photos")
                } catch {
                    log.error("remove probe pictures failed: \(String(describing: error), privacy: .public)")
                }
                exit(0)
            }
        case "remove":
            Task { @MainActor in
                try? dependencies.smartAlbums.delete(id: albumId)
                for server in ((try? dependencies.fileServers.fetchAll()) ?? []) where server.name == name {
                    await dependencies.sourcesModel.setServerSource(false, connection: server)
                    try? dependencies.fileServers.delete(id: server.id)
                }
                dependencies.backupControl.sourcesChanged()
                log.notice("smb probe removed")
                try? await Task.sleep(for: .seconds(1))
                exit(0)
            }
        default:
            break
        }
    }
}
#endif

#if DEBUG
/// A run's client that waits and fails on cue (`commonPhotosRunClient`).
private final class MacDebugRunClient: RemoteFileClient, @unchecked Sendable {
    let base: any RemoteFileClient
    let delay: Duration?
    let failAfter: Int?
    let keepsNoDates: Bool
    private let writes = OSAllocatedUnfairLock(initialState: 0)

    init(base: any RemoteFileClient, delay: Duration?, failAfter: Int?, keepsNoDates: Bool = false) {
        self.base = base
        self.delay = delay
        self.failAfter = failAfter
        self.keepsNoDates = keepsNoDates
    }

    /// Before each write: wait, and past the cue, lose the connection.
    private func write() async throws {
        if let delay { try await Task.sleep(for: delay) }
        let count = writes.withLock { value in
            value += 1
            return value
        }
        if let failAfter, count > failAfter { throw RemoteFileError.connectionLost }
    }

    func connect() async throws { try await base.connect() }
    func disconnect() async { await base.disconnect() }
    func fileSize(at path: String) async throws -> Int64? { try await base.fileSize(at: path) }
    func directoryExists(_ path: String) async throws -> Bool { try await base.directoryExists(path) }
    func fileNames(in directory: String) async throws -> Set<String> { try await base.fileNames(in: directory) }
    func folderNames(in directory: String) async throws -> Set<String> { try await base.folderNames(in: directory) }
    func createDirectory(_ path: String) async throws { try await base.createDirectory(path) }
    func upload(_ localURL: URL, to path: String, progress: @escaping @Sendable (Int64) -> Void) async throws {
        // The CSV at the end is a write too; the cue counts photos only.
        if !path.hasSuffix(".csv") && !path.contains(".csv.") { try await write() }
        try await base.upload(localURL, to: path, progress: progress)
    }
    func sha256(of path: String, progress: @escaping @Sendable (Int64) -> Void) async throws -> String {
        try await base.sha256(of: path, progress: progress)
    }
    func entries(in directory: String) async throws -> [RemoteEntry] { try await base.entries(in: directory) }
    func readRange(_ path: String, offset: Int64, length: Int) async throws -> Data {
        try await base.readRange(path, offset: offset, length: length)
    }
    func download(_ path: String, to localURL: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> String {
        try await base.download(path, to: localURL, progress: progress)
    }
    func move(_ source: String, to destination: String) async throws {
        if !destination.hasSuffix(".csv") { try await write() }
        try await base.move(source, to: destination)
    }

    func copyOnServer(_ source: String, to destination: String) async throws -> Bool {
        try await write()
        return try await base.copyOnServer(source, to: destination)
    }
    func remove(_ path: String) async throws { try await base.remove(path) }
    func removeEmptyDirectory(_ path: String) async throws { try await base.removeEmptyDirectory(path) }
    func storageSpace(at path: String) async throws -> StorageSpace? { try await base.storageSpace(at: path) }
    func fileInfo(at path: String) async throws -> RemoteFileInfo? { try await base.fileInfo(at: path) }
    func sourceInfo(at path: String) async throws -> RemoteFileInfo? { try await base.sourceInfo(at: path) }
    func setFileInfo(_ info: RemoteFileInfo, at path: String) async throws -> FileInfoSupport {
        if keepsNoDates { return .unsupported }
        return try await base.setFileInfo(info, at: path)
    }
}
#endif
