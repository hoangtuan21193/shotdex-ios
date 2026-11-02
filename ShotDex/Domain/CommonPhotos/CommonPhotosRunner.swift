import Foundation

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
struct CommonPhotosRunner: Sendable {
    let client: any RemoteFileClient
    let store: CommonPhotosStore
    /// Where a photo sits on this Mac between download and upload — one at a
    /// time.
    let workDirectory: URL
    /// Free bytes on this Mac; nil = unknown.
    var freeBytes: @Sendable () -> Int64? = { nil }

    /// What the progress window shows (FS-19.08 §7).
    struct Progress: Equatable, Sendable {
        enum Step: Equatable, Sendable {
            case checking, downloading, uploading, readingBack, moving, removing
        }

        var doneCount = 0
        var totalCount = 0
        /// Bytes moved, the photo being worked on counted as it goes: its
        /// download, upload and read-back each a third.
        var doneBytes: Int64 = 0
        var totalBytes: Int64 = 0
        var currentName: String?
        var currentStep: Step?
    }

    /// Why a run stopped short; the run is left paused for Resume.
    enum Stop: Error, Equatable {
        /// This Mac lacks room for the next photo.
        case noRoom
        /// The run is stopped or finished; there is nothing to resume.
        case notResumable
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

    /// Runs every photo not done yet. Returns when all are done; throws when
    /// the server went away, the Mac ran out of room or the task was
    /// cancelled — the run is then paused, and done photos stay done.
    func run(_ runId: String, progress: @escaping @Sendable (Progress) -> Void = { _ in }) async throws {
        guard let run = try store.run(id: runId) else { throw CommonPhotosStore.RunMissing(runId: runId) }
        guard run.state == .running || run.state == .paused, run.canResume else { throw Stop.notResumable }
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
                try Task.checkCancellation()
                try await copy(&items[index], into: destination, state: state, progress: progress)
                state.doneCount += 1
                state.doneBytes += items[index].size
                state.currentName = nil
                state.currentStep = nil
                progress(state)
            }
        } catch {
            try? store.markState(.paused, runId: runId)
            throw error
        }
        try store.markState(.finishing, runId: runId)
    }

    /// One photo, Copy. A failure of this photo alone is logged on it and
    /// the run goes on; one every later photo would meet too — the server
    /// gone, the destination refusing writes, a cancel — is thrown, with the
    /// part removed first.
    private func copy(_ item: inout CommonPhotosItem, into destination: Destination, state: Progress,
                      progress: @escaping @Sendable (Progress) -> Void) async throws {
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
                try await placeSidecar(&item, besides: ServerUploadPath.lastComponent(of: placed), into: destination)
                try finish(&item, .copied, reason: item.failure?.reason)
                return
            }
            if item.partPath != nil, await !write.discardPart(for: placed) {
                throw RemoteFileError.permissionDenied(ServerUploadPath.partPath(for: placed))
            }
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
                try finish(&item, .skipped, reason: .alreadyThere)
                return
            }
        }
        let freeName = ServerUploadPath.nextFreeName(for: name, existing: destination.names)
        let target = ServerUploadPath.join(destination.folder, freeName)

        if let free = freeBytes(), free - item.size < BackupRunner.minimumFreeBytes { throw Stop.noRoom }
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
        var step = Progress.Step.downloading
        do {
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
            step = .readingBack
            let readBack = try await write.readBackSHA256(for: target, progress: { report(.readingBack, (2 + Double($0) / size) / 3) })
            guard readBack == item.sha256 else {
                destination.sizes[freeName.lowercased()] = nil
                try await discard(&item, target: target)
                try finish(&item, .failed, reason: .checksumMismatch)
                return
            }
            step = .moving
            try await write.moveIntoPlace(target, replacing: false)
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
        try finish(&item, .copied, reason: item.failure?.reason)
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
        let sidecarName = ServerUploadPath.lastComponent(of: path)
        let isFullName = sidecarName.lowercased() == ServerUploadPath.lastComponent(of: photoPath).lowercased() + ".xmp"
        let ext = (sidecarName as NSString).pathExtension
        let name = isFullName ? photoName + "." + ext : (photoName as NSString).deletingPathExtension + "." + ext
        let target = destination.path(of: name)
        let write = VerifiedRemoteWrite(client: client)
        let local = workDirectory.appendingPathComponent(UUID().uuidString + "-" + name)
        defer { try? FileManager.default.removeItem(at: local) }
        do {
            let downloaded = try await client.download(path, to: local, progress: { _ in })
            if let taken = destination.sizes[name.lowercased()] {
                // Ours from an earlier try, or the same sidecar: nothing to do.
                let sameSize = try taken == Int64(Data(contentsOf: local).count)
                var same = false
                if sameSize { same = try await client.sha256(of: target, progress: { _ in }) == downloaded }
                if !same { item.reason = CommonPhotosItem.reason(.sidecarNotCopied) }
                return
            }
            try await write.uploadPart(local, for: target, progress: { _ in })
            guard try await write.readBackSHA256(for: target, progress: { _ in }) == downloaded else {
                await write.discardPart(for: target)
                item.reason = CommonPhotosItem.reason(.sidecarNotCopied)
                return
            }
            try await write.moveIntoPlace(target, replacing: false)
            destination.sizes[name.lowercased()] = Int64(try Data(contentsOf: local).count)
        } catch {
            await write.discardPart(for: target)
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            if let remote = error as? RemoteFileError, remote.stopsBatch { throw error }
            item.reason = CommonPhotosItem.reason(.sidecarNotCopied)
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
