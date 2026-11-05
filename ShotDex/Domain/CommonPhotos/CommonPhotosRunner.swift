import CryptoKit
import Foundation
import os

/// Carries out a common-photos run (FS-19.08 §6): every Same photo into the
/// destination folder, one server command at a time, each step written to
/// the store before and after so a run stopped anywhere resumes from the
/// database alone. A struct, not an actor: a run is one sequential task, and
/// `ConnectionLock` keeps it to one command at a time on the connection.
///
/// Copy: download the first source (hashing on the way), check it is still
/// the scanned bytes, upload as a part file, read the part back, and only
/// then give it its real name. A name already taken in the destination is
/// never written over: the same bytes there make the photo Skipped, other
/// bytes give it the next free name (`IMG_1 (2).JPG`).
///
/// Move: rename the first source into the destination on the server (no
/// bytes travel), check the size there, then — each one asked again for its
/// size and write time first — remove every other copy. A server that will
/// not rename (another SMB share) gets a Copy, read back, before anything is
/// removed. No source is removed before the destination copy is checked.
struct CommonPhotosRunner: Sendable {
    let client: any RemoteFileClient
    let store: CommonPhotosStore
    /// Where a photo sits on this Mac between download and upload — one at a
    /// time.
    let workDirectory: URL
    /// Free bytes on this Mac; nil = unknown.
    var freeBytes: @Sendable () -> Int64? = { nil }
    /// After the last photo and the CSV (FS-19.08 §6): rescan the sources,
    /// let the upload history follow what moved. Thrown errors leave the run
    /// `finishing`, so Resume does it again.
    var afterRun: @Sendable (CommonPhotosRun, [CommonPhotosLog.HistoryChange]) async throws -> Void = { _, _ in }
    /// Now, and the zone it is told in, for the CSV's name.
    var now: @Sendable () -> Date = { Date() }
    var timeZone: TimeZone = .current

    /// What the progress window shows (FS-19.08 §7).
    struct Progress: Equatable, Sendable {
        enum Step: Equatable, Sendable {
            case checking, downloading, uploading, readingBack, moving, removing
        }

        var doneCount = 0
        var totalCount = 0
        /// Bytes of the photos done, whatever became of them, and of the one
        /// being worked on as it goes (its download, upload and read-back
        /// each a third) — so the bar ends full.
        var doneBytes: Int64 = 0
        var totalBytes: Int64 = 0
        var currentName: String?
        var currentStep: Step?
    }

    /// Why a run stopped short; the run is left paused for Resume.
    enum Stop: Error, Equatable, LocalizedError {
        /// This Mac lacks room for the next photo: `needed` more bytes free.
        case noRoom(needed: Int64)
        /// The run is stopped or finished; there is nothing to resume.
        case notResumable
        /// The folders chosen overlap, or the destination is one of them
        /// (FS-19.08 §4) — or, found while removing, is the same place as a
        /// source under another path.
        case destinationIsASource
        /// This run is already going in this app (Resume pressed twice).
        case alreadyRunning

        var errorDescription: String? {
            switch self {
            case .noRoom(let needed):
                String(localized: "This Mac needs \(needed.formatted(.byteCount(style: .file))) more free space to copy the next photo. Free some space, then resume.",
                       comment: "Common photos: no room on the Mac for the next photo")
            case .notResumable:
                String(localized: "This run was stopped or has finished; there is nothing to resume.",
                       comment: "Common photos: resume of a run that is over")
            case .destinationIsASource:
                String(localized: "The destination is one of the folders being compared, or inside one. Choose another destination.",
                       comment: "Common photos: destination overlaps a source folder")
            case .alreadyRunning:
                String(localized: "This run is already going.", comment: "Common photos: resume pressed while running")
            }
        }
    }

    /// The items of a new run, in the order they run: one per Same photo,
    /// every copy of it as a source, first folder first, each with its
    /// `.xmp` when it has one. `files` is the listing the photos came from:
    /// which sidecar is a photo's follows the folder source rule (FS-19.01
    /// §3) — `DSC0001.xmp` is the RAW's; a JPEG or HEIC beside that RAW owns
    /// only `DSC0001.JPG.xmp`.
    static func items(for photos: [CommonPhoto], runId: String, folders: [String],
                      files: [[CommonPhotosFile]] = [], sidecars: [[CommonPhotosFile]] = []) -> [CommonPhotosItem] {
        let sidecarPaths = Set(sidecars.joined().map { Self.lowercasedKey($0.folder, $0.relativePath) })
        let spelled = Dictionary(sidecars.joined().map { (Self.lowercasedKey($0.folder, $0.relativePath), $0.relativePath) },
                                 uniquingKeysWith: { first, _ in first })
        let namesByFolder = Dictionary(grouping: files.joined()) { Self.lowercasedKey($0.folder, $0.subfolder) }
            .mapValues { $0.map(\.name) }
        return photos.enumerated().map { position, photo in
            let sources = photo.files.joined().map { file in
                let siblings = namesByFolder[Self.lowercasedKey(file.folder, file.subfolder)] ?? []
                let stem = (file.relativePath as NSString).deletingPathExtension
                let candidates = PairingRule.usesFullNameSidecar(file.name, siblings: siblings)
                    ? [file.relativePath + ".xmp"]
                    : [stem + ".xmp", file.relativePath + ".xmp"]
                let sidecar = candidates.lazy
                    .map { Self.lowercasedKey(file.folder, $0) }
                    .first(where: sidecarPaths.contains)
                    .flatMap { spelled[$0] }
                return CommonPhotosItem.Source(
                    path: ServerUploadPath.join(folders[file.folder], file.relativePath),
                    size: file.size,
                    modifiedAt: file.modified.map { Int($0.timeIntervalSince1970) },
                    sidecar: sidecar.map { ServerUploadPath.join(folders[file.folder], $0) })
            }
            return CommonPhotosItem(runId: runId, position: position, sha256: photo.sha256, size: photo.size, sources: sources)
        }
    }

    private static func lowercasedKey(_ folder: Int, _ relativePath: String) -> String {
        "\(folder)/" + relativePath.lowercased()
    }

    /// The sidecar that goes with the photo: the copied source's, else the
    /// first other source's.
    private static func sidecar(of item: CommonPhotosItem) -> (path: String, photo: String)? {
        let source = item.sources.first(where: { $0.sidecar != nil })
        return source.flatMap { source in source.sidecar.map { ($0, source.path) } }
    }

    /// The destination folder as this run sees it: lowercased name → size,
    /// listed once, kept up to date as photos land; and each listed name as
    /// the server spells it, since WebDAV and SFTP paths are case-sensitive.
    private final class Destination: @unchecked Sendable {
        let folder: String
        var sizes: [String: Int64]
        var spelled: [String: String]
        /// Whether the server copies files itself (§6d): nil until the first
        /// photo asks, then the answer for the rest of the run, so a server
        /// that refuses is asked once.
        var copiesOnServer: Bool?

        init(folder: String, entries: [RemoteEntry]) {
            self.folder = folder
            sizes = Dictionary(entries.map { ($0.name.lowercased(), $0.size) }, uniquingKeysWith: { first, _ in first })
            spelled = Dictionary(entries.map { ($0.name.lowercased(), $0.name) }, uniquingKeysWith: { first, _ in first })
        }

        var names: Set<String> { Set(sizes.keys) }

        func path(of name: String) -> String {
            ServerUploadPath.join(folder, spelled[name.lowercased()] ?? name)
        }
    }

    /// Runs going in this process, by database and run: one runner per run,
    /// whoever starts it. In-process only — the app and the Mac app each open
    /// one shared database, and no extension runs this.
    private struct RunKey: Hashable { let database: ObjectIdentifier; let runId: String }
    private static let active = OSAllocatedUnfairLock(initialState: Set<RunKey>())

    /// Renewing the database claim of each run going here.
    private static let renewals = OSAllocatedUnfairLock(initialState: [RunKey: Task<Void, Never>]())
    /// Runs whose claim another process took while they ran (a sleep past
    /// the expiry): they stop before the next photo.
    private static let lostClaims = OSAllocatedUnfairLock(initialState: Set<RunKey>())

    /// The claim went to the other process: this runner must not go on.
    static func hasLostClaim(runId: String, in database: AppDatabase) -> Bool {
        lostClaims.withLock { $0.contains(RunKey(database: ObjectIdentifier(database), runId: runId)) }
    }

    /// Marks `runId` as going in this process; false when it already is —
    /// here, or in the other process on the same database file (the Mac
    /// app and its helper, FS-19.08 §6c), whose claim is renewed while it
    /// runs. The undo runner takes the same claim, so Activity and the
    /// banner see either kind of run as busy.
    static func claim(runId: String, in database: AppDatabase) -> Bool {
        let key = RunKey(database: ObjectIdentifier(database), runId: runId)
        guard active.withLock({ $0.insert(key).inserted }) else { return false }
        let claims = CommonPhotosClaims(database: database)
        guard claims.claim(.run, id: runId) else {
            _ = active.withLock { $0.remove(key) }
            return false
        }
        let renewal = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                try? await Task.sleep(for: CommonPhotosClaims.renewEvery)
                if !Task.isCancelled, !claims.renew(.run, id: runId) {
                    _ = lostClaims.withLock { $0.insert(key) }
                    return
                }
            }
        }
        renewals.withLock { $0[key] = renewal }
        return true
    }

    static func release(runId: String, in database: AppDatabase) {
        let key = RunKey(database: ObjectIdentifier(database), runId: runId)
        renewals.withLock { $0.removeValue(forKey: key) }?.cancel()
        // A claim lost is not ours to release.
        if lostClaims.withLock({ $0.remove(key) }) == nil { CommonPhotosClaims(database: database).release(.run, id: runId) }
        _ = active.withLock { $0.remove(key) }
    }

    /// Whether a runner is going on this run now, in this process or the
    /// other one — the banner then shows it in progress, never Resume ·
    /// Discard.
    static func isActive(runId: String, in database: AppDatabase) -> Bool {
        active.withLock { $0.contains(RunKey(database: ObjectIdentifier(database), runId: runId)) }
            || CommonPhotosClaims(database: database).isClaimedElsewhere(.run, id: runId)
    }

    private static let log = Logger(subsystem: "com.hoangtuan.shotdex", category: "commonPhotos")

    /// Runs every photo not done yet. Returns when all are done; throws when
    /// the server went away, the Mac ran out of room or the task was
    /// cancelled — the run is then paused, and done photos stay done.
    func run(_ runId: String, progress: @escaping @Sendable (Progress) -> Void = { _ in }) async throws {
        guard Self.claim(runId: runId, in: store.database) else { throw Stop.alreadyRunning }
        defer { Self.release(runId: runId, in: store.database) }
        guard let run = try store.run(id: runId) else { throw CommonPhotosStore.RunMissing(runId: runId) }
        guard run.canResume else { throw Stop.notResumable }
        // An undo is taken back by the undo runner, never gathered again.
        guard !run.isUndo else { throw Stop.notResumable }
        guard CommonPhotosSelection.problem(folders: run.folders, destination: run.destination) == nil else {
            throw Stop.destinationIsASource
        }
        try store.markState(.running, runId: runId)
        var items = try store.items(runId: runId)
        var state = Progress(doneCount: items.filter(\.isDone).count, totalCount: items.count,
                             doneBytes: items.filter(\.isDone).reduce(0) { $0 + $1.size },
                             totalBytes: items.reduce(0) { $0 + $1.size })
        progress(state)
        do {
            try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
            try await client.createDirectory(run.destination)
            let listing = try await client.entries(in: run.destination).filter { !$0.isDirectory }
            let destination = Destination(folder: run.destination, entries: listing)
            for index in items.indices where !items[index].isDone {
                // The other process took the run over (FS-19.08 §6c).
                if Self.hasLostClaim(runId: runId, in: store.database) { throw Stop.alreadyRunning }
                try Task.checkCancellation()
                switch run.action {
                case .copy: try await copy(&items[index], into: destination, state: state, progress: progress)
                case .move:
                    // A sidecar two photos share (IMG_1.JPG and IMG_1.MOV)
                    // stays until the last of them is done.
                    let claimed = Set(items[(index + 1)...].filter { !$0.isDone }.flatMap { $0.sources.compactMap(\.sidecar) })
                    try await move(&items[index], into: destination, claimedSidecars: claimed, state: state, progress: progress)
                }
                state.doneCount += 1
                state.doneBytes += items[index].size
                state.currentName = nil
                state.currentStep = nil
                progress(state)
            }
            // What the server did with the dates, for the next run's sheet (§6e).
            if let keeps = ServerFileInfoSupport.keepsDates(from: items.compactMap(\.fileInfo)) {
                try? ServerFileInfoSupport.record(connectionId: run.connectionId, keepsDates: keeps, in: store.database)
            }
            try store.markState(.finishing, runId: runId)
            let csvPath = try await writeLog(items, run: run, into: destination)
            try await afterRun(run, CommonPhotosLog.historyChanges(items))
            try store.markState(.finished, runId: runId, csvPath: csvPath)
        } catch {
            // Stopped after the last photo, it stays finishing: Resume writes
            // what is left. A state that cannot be read is left alone.
            if let state = try? store.run(id: runId)?.state, state != .finishing { try? store.markState(.paused, runId: runId) }
            throw error
        }
    }

    /// The CSV of the run beside the photos, through the same verified
    /// write; written once — a Resume of a finishing run that has one keeps it.
    private func writeLog(_ items: [CommonPhotosItem], run: CommonPhotosRun, into destination: Destination) async throws -> String {
        // The name is recorded before the upload: a quit mid-write resumes
        // into the same file rather than leaving a second one beside it.
        let recorded = try store.run(id: run.id)?.csvPath
        // A day of Keep gathering (FS-19.08 §6c) writes its one log again
        // after every pass, with every photo of the day.
        let isDay = run.day != nil
        if !isDay, let recorded, try await client.fileSize(at: recorded) != nil { return recorded }
        let fresh = run.day.map(CommonPhotosLog.dayCSVName) ?? CommonPhotosLog.csvName(at: now(), timeZone: timeZone)
        // The day's log keeps its one name: it is replaced, never doubled.
        // Lost halfway (removed, not yet moved in), it is written again from
        // the database by the next pass or a Resume.
        let target = recorded ?? (isDay ? ServerUploadPath.join(destination.folder, fresh)
            : ServerUploadPath.join(destination.folder, ServerUploadPath.nextFreeName(for: fresh, existing: destination.names)))
        let name = ServerUploadPath.lastComponent(of: target)
        try store.markState(.finishing, runId: run.id, csvPath: target)
        let local = workDirectory.appendingPathComponent(UUID().uuidString + ".csv")
        defer { try? FileManager.default.removeItem(at: local) }
        let data = Data(CommonPhotosLog.csv(items).utf8)
        try data.write(to: local)
        let write = VerifiedRemoteWrite(client: client)
        do {
            try await write.uploadPart(local, for: target, progress: { _ in })
            guard try await write.readBackSHA256(for: target, progress: { _ in }) == FileChecksum.hex(SHA256.hash(data: data)) else {
                await write.discardPart(for: target)
                throw RemoteFileError.other("checksum mismatch")
            }
            try await write.moveIntoPlace(target, replacing: isDay)
        } catch {
            await write.discardPart(for: target)
            throw error
        }
        destination.sizes[name.lowercased()] = Int64(data.count)
        return target
    }

    /// One photo, Copy. A failure of this photo alone is logged on it and
    /// the run goes on; one every later photo would meet too — the server
    /// gone, the destination refusing writes, a cancel — is thrown, with the
    /// part removed first.
    /// `copied` and `skipped` are what the photo becomes; a Move passes
    /// `placed` for both and removes the sources after.
    private func copy(_ item: inout CommonPhotosItem, into destination: Destination, state: Progress,
                      progress: @escaping @Sendable (Progress) -> Void,
                      copied: CommonPhotosItem.Status = .copied, skipped: CommonPhotosItem.Status = .skipped) async throws {
        guard let source = item.sources.first else {
            try finish(&item, .failed, reason: .noSource)
            return
        }
        let write = VerifiedRemoteWrite(client: client)
        let name = ServerUploadPath.lastComponent(of: source.path)
        let itemSize = item.size
        let report = { @Sendable (step: Progress.Step, fraction: Double) in
            var moving = state
            moving.currentName = name
            moving.currentStep = step
            moving.doneBytes += Int64(Double(itemSize) * min(1, max(0, fraction)))
            progress(moving)
        }

        // A photo a stopped run left mid-copy: in place with the scanned
        // bytes means the rename went through before the reply was lost.
        if item.status == .copying, let placed = item.destinationPath {
            report(.checking, 0)
            if destination.sizes[ServerUploadPath.lastComponent(of: placed).lowercased()] == item.size,
               try await client.sha256(of: placed, progress: { _ in }) == item.sha256 {
                try Task.checkCancellation()
                if item.fileInfo == nil, let info = try? await client.fileInfo(at: source.path) {
                    item.fileInfo = await write.applyInfo(info, to: placed)
                }
                try await placeSidecar(&item, besides: ServerUploadPath.lastComponent(of: placed), into: destination)
                try finish(&item, copied, reason: item.failure?.reason)
                return
            }
            // The part goes before anything else; a server still away says so.
            if item.partPath != nil { try await client.remove(ServerUploadPath.partPath(for: placed)) }
            item.partPath = nil
        }

        // The name in the destination: Skipped when the same bytes are there.
        let taken = destination.sizes[name.lowercased()]
        if taken == item.size {
            report(.checking, 0)
            let there = destination.path(of: name)
            if try await client.sha256(of: there, progress: { _ in }) == item.sha256 {
                item.destinationPath = there
                try await placeSidecar(&item, besides: ServerUploadPath.lastComponent(of: there), into: destination)
                item.destinationWasThere = true
                try finish(&item, skipped, reason: .alreadyThere)
                return
            }
        }
        let freeName = ServerUploadPath.nextFreeName(for: name, existing: destination.names)
        let target = ServerUploadPath.join(destination.folder, freeName)

        if let free = freeBytes(), free - item.size < BackupRunner.minimumFreeBytes {
            throw Stop.noRoom(needed: item.size + BackupRunner.minimumFreeBytes - free)
        }
        item.status = .copying
        item.destinationPath = target
        item.partPath = ServerUploadPath.partPath(for: target)
        try store.update(item)
        // Claimed now, so a later photo of the same name in this run takes
        // the next one, part file included.
        destination.sizes[freeName.lowercased()] = item.size

        let local = workDirectory.appendingPathComponent(UUID().uuidString + "-" + name)
        defer { try? FileManager.default.removeItem(at: local) }
        let size = Double(max(1, item.size))
        var step = Progress.Step.uploading
        do {
            // The server copies it itself when it can (WebDAV COPY, §6d): the
            // read-back below is then the only time the bytes cross the
            // network. Refused, it goes the long way. A server known to copy
            // shows the step while it does; one that has not answered yet
            // shows nothing for the ask, so a refusal leaves the steps as before.
            var copiedOnServer = false
            if destination.copiesOnServer != false {
                if destination.copiesOnServer == true { report(.uploading, 0) }
                do {
                    copiedOnServer = try await client.copyOnServer(source.path, to: ServerUploadPath.partPath(for: target))
                    destination.copiesOnServer = copiedOnServer
                } catch let error as RemoteFileError where Self.leavesTheLongWayOpen(error) {
                    // Missing (404 the source, 409 a parent) or an answer the
                    // server gives to COPY alone: the long way says which.
                    copiedOnServer = false
                }
            }
            if copiedOnServer {
                report(.uploading, 2.0 / 3)
            } else {
                step = .downloading
                report(.downloading, 0)
                let downloaded = try await client.download(source.path, to: local, progress: { report(.downloading, Double($0) / size / 3) })
                guard downloaded == item.sha256 else {
                    destination.sizes[freeName.lowercased()] = nil
                    try finish(&item, .failed, reason: .changedOnServer)
                    return
                }
                try Task.checkCancellation()
                step = .uploading
                try await write.uploadPart(local, for: target, progress: { report(.uploading, (1 + Double($0) / size) / 3) })
            }
            Self.log.info("common photos \(copiedOnServer ? "copied on the server" : "downloaded and uploaded", privacy: .public): \(name, privacy: .private)")
            step = .readingBack
            let readBack = try await write.readBackSHA256(for: target, progress: { report(.readingBack, (2 + Double($0) / size) / 3) })
            guard readBack == item.sha256 else {
                destination.sizes[freeName.lowercased()] = nil
                try await discard(&item, target: target)
                // The server copied what the source holds now: a source
                // rewritten since the scan is said as such, as the long way
                // says it.
                let changed = copiedOnServer
                    ? try await client.sha256(of: source.path, progress: { _ in }) != item.sha256 : false
                try finish(&item, .failed, reason: changed ? .changedOnServer : .checksumMismatch)
                return
            }
            step = .moving
            // The first folder's dates and flags (FS-19.08 §6e): the copy is
            // that file, down to what Finder sorts by.
            let sourceInfo = try? await client.fileInfo(at: source.path)
            let outcome = try await write.moveIntoPlace(target, replacing: false, info: sourceInfo)
            // Cancelled after the rename: no verdict, so Resume sets them. A
            // source whose info could not be read has none either — that
            // is not the server losing dates.
            item.fileInfo = Task.isCancelled ? nil : outcome
        } catch {
            try await discard(&item, target: target)
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            guard let remote = error as? RemoteFileError, !remote.stopsBatch else { throw error }
            // The destination refusing a write will refuse every photo: stop.
            if step != .downloading, Self.refusesEveryWrite(remote) { throw error }
            destination.sizes[freeName.lowercased()] = nil
            try finish(&item, .failed, reason: .serverError, detail: remote.localizedDescription)
            return
        }
        // In place and recorded, still `copying`, before the sidecar is
        // touched: a stop during the sidecar resumes through the in-place
        // check above, which finds the photo there and tries the sidecar again.
        item.partPath = nil
        try store.update(item)
        try await placeSidecar(&item, besides: freeName, into: destination)
        try finish(&item, copied, reason: item.failure?.reason)
    }

    /// One photo, Move. A state machine over what the store says, each state
    /// checked against the server before anything is removed:
    /// - pending: the first source asked again; renamed into the destination
    ///   on the server, or — refused — copied and read back;
    /// - moving: a rename a stop interrupted, settled by looking at both ends;
    /// - copying: the Copy fallback, resumed by `copy`;
    /// - placed: the destination proved to hold the scanned bytes, then every
    ///   other copy removed.
    private func move(_ item: inout CommonPhotosItem, into destination: Destination, claimedSidecars: Set<String>,
                      state: Progress, progress: @escaping @Sendable (Progress) -> Void) async throws {
        guard let source = item.sources.first else {
            try finish(&item, .failed, reason: .noSource)
            return
        }
        let name = ServerUploadPath.lastComponent(of: source.path)
        let report = { @Sendable (step: Progress.Step) in
            var moving = state
            moving.currentName = name
            moving.currentStep = step
            progress(moving)
        }
        var provedThisRun = false

        switch item.status {
        case .moving:
            guard let target = item.destinationPath, let from = item.movedFrom else {
                try reset(&item)
                break
            }
            report(.checking)
            let targetSize = try await client.fileSize(at: target)
            let fromSize = try await client.fileSize(at: from)
            if fromSize == nil, targetSize == item.size,
               try await client.sha256(of: target, progress: { _ in }) == item.sha256 {
                await checkRenameKeptInfo(&item, target: target)
                try markMoved(&item, from: from, target: target)
                provedThisRun = true
            } else if fromSize != nil, targetSize == nil {
                try reset(&item)
            } else {
                // Neither end is what a rename leaves: nothing is removed.
                try finish(&item, .failed, reason: .changedOnServer)
                return
            }
        case .placed, .pending, .copying:
            break
        default:
            try finish(&item, .failed, reason: .unreadableRecord)
            return
        }

        if item.status == .pending {
            guard !item.sources.contains(where: \.isRemoved) else {
                // A source is gone but the photo is not placed: never guess.
                try finish(&item, .failed, reason: .unreadableRecord)
                return
            }
            report(.checking)
            guard try await isUnchanged(source, sha256: item.sha256) else {
                try finish(&item, .failed, reason: .changedOnServer)
                return
            }
            // Every copy's dates and flags, recorded before anything is
            // renamed or removed (FS-19.08 §6e, AC-224): Undo puts each back
            // as it was, even where the server keeps no dates.
            for index in item.sources.indices where item.sources[index].info == nil {
                item.sources[index].info = try? await client.fileInfo(at: item.sources[index].path)
                if let sidecar = item.sources[index].sidecar, item.sources[index].sidecarInfo == nil {
                    item.sources[index].sidecarInfo = try? await client.fileInfo(at: sidecar)
                }
            }
            // A Stop during those reads stops here, before any rename.
            try Task.checkCancellation()
            try store.update(item)
            let taken = destination.sizes[name.lowercased()]
            var alreadyThere = false
            if taken == item.size {
                alreadyThere = try await client.sha256(of: destination.path(of: name), progress: { _ in }) == item.sha256
            }
            if alreadyThere {
                item.destinationPath = destination.path(of: name)
                item.destinationWasThere = true
                try finish(&item, .placed, reason: .alreadyThere)
                provedThisRun = true
            } else {
                let freeName = ServerUploadPath.nextFreeName(for: name, existing: destination.names)
                let target = ServerUploadPath.join(destination.folder, freeName)
                item.status = .moving
                item.destinationPath = target
                item.movedFrom = source.path
                try store.update(item)
                destination.sizes[freeName.lowercased()] = item.size
                report(.moving)
                var renamed = true
                do {
                    try await client.move(source.path, to: target)
                } catch let error as RemoteFileError where !error.stopsBatch {
                    // The reply can be an error after the server did it.
                    let sourceGone = try await client.fileSize(at: source.path) == nil
                    let targetSize = try await client.fileSize(at: target)
                    renamed = sourceGone && targetSize == item.size
                }
                if renamed {
                    guard try await isTheScannedBytes(at: target, renamedFrom: source, sha256: item.sha256) else {
                        // Moved, but not what the scan saw: kept where it is,
                        // no other copy is touched, and the history follows
                        // the file to where it now is.
                        if let index = item.sources.firstIndex(where: { $0.path == source.path }) { item.sources[index].isRemoved = true }
                        try finish(&item, .failed, reason: .changedOnServer)
                        return
                    }
                    await checkRenameKeptInfo(&item, target: target)
                    try markMoved(&item, from: source.path, target: target)
                    provedThisRun = true
                } else {
                    // Refused (another share): Copy and read back instead.
                    destination.sizes[freeName.lowercased()] = nil
                    try reset(&item)
                }
            }
        }

        if item.status == .pending || item.status == .copying {
            try await copy(&item, into: destination, state: state, progress: progress, copied: .placed, skipped: .placed)
            guard item.status == .placed else { return }
            provedThisRun = true
        }
        guard item.status == .placed, let placed = item.destinationPath else {
            try finish(&item, .failed, reason: .unreadableRecord)
            return
        }
        try await removeSources(&item, placed: placed, provedThisRun: provedThisRun, destination: destination,
                                claimedSidecars: claimedSidecars, report: report)
    }

    private func reset(_ item: inout CommonPhotosItem) throws {
        item.status = .pending
        item.destinationPath = nil
        item.movedFrom = nil
        item.partPath = nil
        try store.update(item)
    }

    /// A rename keeps a file's dates: checked against the first copy's info
    /// recorded before it, not set (FS-19.08 §6e). Either read missing, no
    /// verdict — an unread date is not a lost one.
    private func checkRenameKeptInfo(_ item: inout CommonPhotosItem, target: String) async {
        guard let before = item.sources.first?.info, let after = try? await client.fileInfo(at: target) else { return }
        item.fileInfo = after.hasSameModified(as: before) ? .kept : .datesNotKept
    }

    /// The rename went through: the moved source is gone, the photo placed.
    private func markMoved(_ item: inout CommonPhotosItem, from: String, target: String) throws {
        if let index = item.sources.firstIndex(where: { $0.path == from }) { item.sources[index].isRemoved = true }
        item.status = .placed
        item.destinationPath = target
        try store.update(item)
    }

    /// After a rename: the target has the source's size and the write time
    /// a rename keeps; when the server gave no write time, or the two differ
    /// (a WebDAV MOVE across mounts copies on the server), the SHA-256.
    private func isTheScannedBytes(at target: String, renamedFrom source: CommonPhotosItem.Source, sha256: String) async throws -> Bool {
        let name = ServerUploadPath.lastComponent(of: target)
        let entry = try await client.entries(in: ServerUploadPath.parent(of: target)).first { $0.name == name && !$0.isDirectory }
        guard let entry, entry.size == source.size else { return false }
        if let modifiedAt = source.modifiedAt, entry.modified.map({ Int($0.timeIntervalSince1970) }) == modifiedAt { return true }
        return try await client.sha256(of: target, progress: { _ in }) == sha256
    }

    /// Every copy not removed yet. First the destination is proved again —
    /// its size, and its SHA-256 when a resume finds it placed by an earlier
    /// run — and no source that is the destination, or sits in its folder, is
    /// ever touched. Each copy is asked again for its size and write time; a
    /// changed one is kept and fails the photo. Removing goes by renaming the
    /// copy aside, checking the destination still answers — two paths to one
    /// file (two shares over one volume) would make it vanish — and only then
    /// deleting it. A source's sidecar goes the same way, and only when the
    /// destination holds the same bytes and no photo still to run claims it.
    private func removeSources(_ item: inout CommonPhotosItem, placed: String, provedThisRun: Bool, destination: Destination,
                               claimedSidecars: Set<String>, report: @Sendable (Progress.Step) -> Void) async throws {
        report(.checking)
        var isProved = try await client.fileSize(at: placed) == item.size
        if isProved, !provedThisRun { isProved = try await client.sha256(of: placed, progress: { _ in }) == item.sha256 }
        guard isProved else {
            try finish(&item, .failed, reason: .changedOnServer)
            return
        }
        let wasThere = item.failure?.reason == .alreadyThere
        var placedSidecar = try await sidecarHash(besides: placed, item: item)
        if placedSidecar == nil, Self.sidecar(of: item) != nil {
            try await placeSidecar(&item, besides: ServerUploadPath.lastComponent(of: placed), into: destination)
            placedSidecar = try await sidecarHash(besides: placed, item: item)
        }
        report(.removing)
        let destinationFolder = Self.comparable(destination.folder)
        var changed = false
        var keptSidecar = false
        for index in item.sources.indices {
            try Task.checkCancellation()
            let source = item.sources[index]
            guard Self.comparable(source.path) != Self.comparable(placed),
                  Self.comparable(ServerUploadPath.parent(of: source.path)) != destinationFolder else {
                // The destination itself: never removed, never reported so.
                continue
            }
            if !source.isRemoved {
                let aside = source.path + Self.removingSuffix
                if try await client.fileSize(at: source.path) == nil {
                    // Gone: removed by a stop before it was recorded, or set
                    // aside and not yet deleted.
                    if try await client.fileSize(at: aside) != nil {
                        try await removeAside(aside, restoring: source.path, placed: placed, size: item.size)
                    }
                } else {
                    guard try await isUnchanged(source, sha256: item.sha256) else {
                        changed = true
                        continue
                    }
                    try await client.move(source.path, to: aside)
                    try await removeAside(aside, restoring: source.path, placed: placed, size: item.size)
                }
                item.sources[index].isRemoved = true
                try store.update(item)
            }
            if let sidecar = source.sidecar, !claimedSidecars.contains(sidecar),
               let target = Self.sidecar(of: item).map({ Self.sidecarTarget($0.path, photoPath: $0.photo,
                                                                         photoName: ServerUploadPath.lastComponent(of: placed),
                                                                         folder: ServerUploadPath.parent(of: placed)) }),
               try await client.fileSize(at: sidecar) == nil,
               try await client.fileSize(at: sidecar + Self.removingSuffix) != nil,
               let size = try await client.fileSize(at: target) {
                // Set aside by a stop before it was deleted.
                try await removeAside(sidecar + Self.removingSuffix, restoring: sidecar, placed: target, size: size)
            } else if let sidecar = source.sidecar, !claimedSidecars.contains(sidecar), try await client.fileSize(at: sidecar) != nil {
                if let placedSidecar, try await client.sha256(of: sidecar, progress: { _ in }) == placedSidecar,
                   let target = Self.sidecar(of: item).map({ Self.sidecarTarget($0.path, photoPath: $0.photo,
                                                                                 photoName: ServerUploadPath.lastComponent(of: placed),
                                                                                 folder: ServerUploadPath.parent(of: placed)) }),
                   let size = try await client.fileSize(at: target) {
                    let aside = sidecar + Self.removingSuffix
                    try await client.move(sidecar, to: aside)
                    try await removeAside(aside, restoring: sidecar, placed: target, size: size)
                } else {
                    keptSidecar = true
                }
            }
        }
        if changed {
            try finish(&item, .failed, reason: .changedOnServer)
        } else {
            try finish(&item, .moved, reason: keptSidecar ? .sidecarNotCopied : wasThere ? .alreadyThere : nil)
        }
    }

    /// What a copy is renamed to while it is being removed. Not a photo
    /// extension, so no scan ever lists it.
    static let removingSuffix = ".shotdex-removing"

    /// Deletes a copy set aside — after checking the destination still has
    /// its size. If it vanished with the rename, the two were one file: the
    /// copy goes back where it was and the run stops.
    private func removeAside(_ aside: String, restoring original: String, placed: String, size: Int64) async throws {
        guard try await client.fileSize(at: placed) == size else {
            // Put back even while the task is being cancelled.
            let client = client
            try? await Task.detached { try await client.move(aside, to: original) }.value
            throw Stop.destinationIsASource
        }
        try await client.remove(aside)
    }

    private static func comparable(_ path: String) -> String {
        CommonPhotosServerChecks.comparable(path)
    }

    /// The SHA-256 of the sidecar beside `photo` in the destination, if one.
    private func sidecarHash(besides photo: String, item: CommonPhotosItem) async throws -> String? {
        guard let (path, photoPath) = Self.sidecar(of: item) else { return nil }
        let target = Self.sidecarTarget(path, photoPath: photoPath, photoName: ServerUploadPath.lastComponent(of: photo),
                                        folder: ServerUploadPath.parent(of: photo))
        guard try await client.fileSize(at: target) != nil else { return nil }
        return try await client.sha256(of: target, progress: { _ in })
    }

    /// Asked again right before it is moved or removed: the same size and
    /// write time as at the scan, or — with no write time to go by — the same
    /// SHA-256.
    private func isUnchanged(_ source: CommonPhotosItem.Source, sha256: String) async throws -> Bool {
        try await CommonPhotosServerChecks(client: client).isUnchanged(source, sha256: sha256)
    }

    /// The photo's `.xmp` beside it in the destination, named after the
    /// photo's final name the way the source named it — `IMG_2 (2).xmp` for
    /// `IMG_2 (2).JPG`, or `IMG_2 (2).JPG.xmp` for a full-name sidecar —
    /// through the same verified write. A name already taken by other bytes
    /// is left alone and noted on the photo (`sidecarNotCopied`); a sidecar
    /// that will not copy never fails its photo. A stop is thrown, with the
    /// sidecar's part removed first.
    private func placeSidecar(_ item: inout CommonPhotosItem, besides photoName: String, into destination: Destination) async throws {
        guard let (path, photoPath) = Self.sidecar(of: item) else { return }
        let name = ServerUploadPath.lastComponent(of: Self.sidecarTarget(path, photoPath: photoPath, photoName: photoName, folder: ""))
        let target = destination.path(of: name)
        let write = VerifiedRemoteWrite(client: client)
        let local = workDirectory.appendingPathComponent(UUID().uuidString + "-" + name)
        defer { try? FileManager.default.removeItem(at: local) }
        var downloaded: String?
        do {
            let sha256 = try await client.download(path, to: local, progress: { _ in })
            downloaded = sha256
            if let taken = destination.sizes[name.lowercased()] {
                // Ours from an earlier try (still recorded as placed), or
                // the same sidecar already there: nothing to do.
                let sameSize = try taken == Int64(Data(contentsOf: local).count)
                var same = false
                if sameSize { same = try await client.sha256(of: target, progress: { _ in }) == sha256 }
                if !same {
                    item.reason = CommonPhotosItem.reason(.sidecarNotCopied)
                    try clearPlacedSidecar(&item, target: target)
                }
                return
            }
            // Recorded before the write, as the photo's part is: a stop
            // between the rename and the record must not leave undo
            // believing someone else put it there.
            item.sidecarPlaced = target
            item.sidecarSHA256 = sha256
            try record(item)
            try await write.uploadPart(local, for: target, progress: { _ in })
            guard try await write.readBackSHA256(for: target, progress: { _ in }) == sha256 else {
                await write.discardPart(for: target)
                item.reason = CommonPhotosItem.reason(.sidecarNotCopied)
                try clearPlacedSidecar(&item, target: target)
                return
            }
            // The sidecar's own dates, as the photo gets its own (§6e).
            let sidecarInfo = try? await client.fileInfo(at: path)
            try await write.moveIntoPlace(target, replacing: false, info: sidecarInfo)
            destination.sizes[name.lowercased()] = Int64(try Data(contentsOf: local).count)
        } catch {
            await write.discardPart(for: target)
            // The record could not be written: that is not the sidecar's
            // failure, and the run must hear it.
            if let failure = error as? RecordFailure { throw failure.underlying }
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            if let remote = error as? RemoteFileError, remote.stopsBatch { throw error }
            // The server still answers: keep the claim only on our bytes.
            // (A stop above keeps it as recorded — undo removes a sidecar
            // only while it holds the bytes recorded.)
            if item.sidecarPlaced == target {
                // Nil when the server could not say; .some(nil) when the
                // name is free.
                let size: Int64??
                do { size = .some(try await client.fileSize(at: target)) } catch { size = nil }
                var ours = false
                if let known = size, known != nil, let downloaded {
                    ours = (try? await client.sha256(of: target, progress: { _ in })) == downloaded
                }
                if !ours, size != nil { try? clearPlacedSidecar(&item, target: target) }
            }
            item.reason = CommonPhotosItem.reason(.sidecarNotCopied)
        }
    }

    /// The sidecar at `target` is not this run's: undo must leave it.
    private func clearPlacedSidecar(_ item: inout CommonPhotosItem, target: String) throws {
        guard item.sidecarPlaced == target else { return }
        item.sidecarPlaced = nil
        item.sidecarSHA256 = nil
        try record(item)
    }

    /// A store write inside `placeSidecar`, told apart from the server's
    /// errors there: a sidecar that will not copy is noted on the photo, a
    /// record that will not write stops the run.
    private struct RecordFailure: Error { let underlying: Error }

    private func record(_ item: CommonPhotosItem) throws {
        do { try store.update(item) } catch { throw RecordFailure(underlying: error) }
    }

    /// Where a photo's sidecar goes beside `photoName` in `folder`: the
    /// photo's final name with the sidecar's own form — `IMG_2 (2).xmp`, or
    /// `IMG_2 (2).JPG.xmp` for a full-name sidecar.
    private static func sidecarTarget(_ sidecar: String, photoPath: String, photoName: String, folder: String) -> String {
        CommonPhotosServerChecks.sidecarTarget(sidecar, photoPath: photoPath, photoName: photoName, folder: folder)
    }

    /// A COPY failure the long way may still get past.
    private static func leavesTheLongWayOpen(_ error: RemoteFileError) -> Bool {
        switch error {
        case .folderMissing, .other: true
        default: false
        }
    }

    private static func refusesEveryWrite(_ error: RemoteFileError) -> Bool {
        switch error {
        case .permissionDenied, .folderMissing: true
        default: false
        }
    }

    /// Removes the part of a copy that will not finish. The item goes back to
    /// pending when it is gone; when the server kept it, the item keeps
    /// pointing at it so Resume removes it.
    private func discard(_ item: inout CommonPhotosItem, target: String) async throws {
        if await VerifiedRemoteWrite(client: client).discardPart(for: target) {
            item.status = .pending
            item.destinationPath = nil
            item.partPath = nil
        }
        try store.update(item)
    }

    private func finish(_ item: inout CommonPhotosItem, _ status: CommonPhotosItem.Status,
                        reason: CommonPhotosItem.Reason? = nil, detail: String? = nil) throws {
        item.status = status
        item.partPath = nil
        item.reason = reason.map { CommonPhotosItem.reason($0, detail) }
        try store.update(item)
    }
}
