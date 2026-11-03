import Foundation
import os

/// One pass of Keep gathering for one set (FS-19.08 §6c): the helper's
/// rules first (on power, network not metered), then the folders still
/// there, then a scan of only the new photos. A pass that finds nothing
/// leaves no run, only the time it checked. What it finds goes to
/// `onFound`, which runs it; the scan's session closes after.
///
/// Stopping a set is for good until the user turns it on again, so a
/// folder counts as gone only when the server says so twice over: the
/// folder is not there, and its parent lists without it. Anything less is
/// the server away, tried again next pass.
@MainActor
struct CommonPhotosGatherPass {
    static let logger = Logger(subsystem: "com.hoangtuan.shotdex", category: "CommonPhotos")

    /// The connection's client — behind its lock, so Backup goes first —
    /// and its name for "isn't reachable"; nil when the connection is gone.
    typealias Connection = (client: any RemoteFileClient, name: String)

    let database: AppDatabase
    var connection: (_ connectionId: String) -> Connection?
    /// On a metered network; on external power.
    var conditions: () async -> (isExpensivePath: Bool, onPower: Bool)

    enum Outcome: Equatable {
        /// Not gathering (turned off, stopped before, or during this pass).
        case off
        case waiting(OnServerSchedule.Wait)
        case nothingNew
        /// New common photos, handed to `onFound`.
        case found(Int)
        /// Gathering stopped: a folder gone, the connection gone, not a set.
        case stopped(CommonPhotosWatch.Stop)
        /// The pass was cancelled (the helper quitting): nothing recorded.
        case cancelled
        /// The set's run the server cut off last time is to go on: no
        /// scan — its photos are listed already (FS-19.08 §6c).
        case resumes(String)
    }

    private var store: CommonPhotosWatchStore { CommonPhotosWatchStore(database: database) }

    func run(_ watch: CommonPhotosWatch, now: Date = Date(),
             onFound: (CommonPhotosScanModel) async -> Void = { _ in }) async -> Outcome {
        guard watch.isOn else { return .off }
        guard CommonPhotosSelection.problem(folders: watch.folders, destination: watch.destination) == nil else {
            record { try store.stop(id: watch.id, because: .cannotGather) }
            return .stopped(.cannotGather)
        }
        let (isExpensivePath, onPower) = await conditions()
        if let wait = CommonPhotosGatherRule.wait(isExpensivePath: isExpensivePath, onPower: onPower) {
            record { try store.waits(id: watch.id, for: wait) }
            return .waiting(wait)
        }
        guard let connection = connection(watch.connectionId) else {
            record { try store.stop(id: watch.id, because: .connectionGone) }
            return .stopped(.connectionGone)
        }
        let client = connection.client
        let unreachable = OnServerSchedule.Wait.unreachable(connection.name)

        // Every folder still there, before anything is read.
        do {
            try await client.connect()
            for folder in watch.folders + [watch.destination] where try await !client.directoryExists(folder) {
                if try await isGone(folder, client: client) {
                    await client.disconnect()
                    return stop(watch, .folderGone(folder))
                }
                throw RemoteFileError.other("“\(folder)” could not be checked")
            }
        } catch {
            await client.disconnect()
            if error is CancellationError || Task.isCancelled { return .cancelled }
            record { try store.waits(id: watch.id, for: unreachable) }
            return .waiting(unreachable)
        }

        // A run the server cut off goes on before anything new is looked
        // for: its photos would be found again, and wait behind it.
        // Read now, not from the pass's start: the user may have taken the
        // run over meanwhile.
        if let runId = ((try? self.store.watch(id: watch.id)) ?? nil)?.resumeRunId {
            let store = CommonPhotosStore(database: database)
            if let run = (try? store.run(id: runId)) ?? nil, run.canResume, run.watchId == watch.id, run.action == watch.action,
               !CommonPhotosRunner.isActive(runId: runId, in: database) {
                await client.disconnect()
                // Nothing was looked for: the last check and "isn't
                // reachable" stay until the run has gone on.
                guard (try? self.store.isOn(id: watch.id)) == true else { return .off }
                return .resumes(runId)
            }
            // Finished, stopped or gone meanwhile: nothing to carry on.
            record { try self.store.forgetResume(id: watch.id, runId: runId) }
        }

        // The same session for the scan: one login a pass.
        let scan = CommonPhotosScanModel(connectionId: watch.connectionId, sourceId: "", folders: watch.folders,
                                         client: client, database: database)
        scan.destination = watch.destination
        scan.action = watch.action
        scan.adoptConnection()
        defer { Task { await scan.close() } }
        await scan.scanToEnd()
        if Task.isCancelled { return .cancelled }

        guard scan.phase == .done else {
            if case .folderMissing(let folder) = scan.failureError, (try? await isGone(folder, client: client)) == true {
                return stop(watch, .folderGone(folder))
            }
            record { try store.waits(id: watch.id, for: unreachable) }
            return .waiting(unreachable)
        }
        // A client that lists a missing folder as empty: a source with no
        // file at all is checked once more.
        for folder in scan.folders where scan.fileCounts[folder] == 0 {
            if (try? await isGone(folder, client: client)) == true { return stop(watch, .folderGone(folder)) }
        }
        // Stopped by the user while it scanned: nothing more.
        guard (try? store.isOn(id: watch.id)) == true else { return .off }
        record { try store.checked(id: watch.id, at: now, waiting: nil) }
        guard !scan.photos.isEmpty else { return .nothingNew }
        let count = scan.photos.count
        await onFound(scan)
        return .found(count)
    }

    /// The folder is not on the server: it says so, and the folder above
    /// it lists without it. A parent that cannot be listed throws — not
    /// proof of anything.
    private func isGone(_ folder: String, client: any RemoteFileClient) async throws -> Bool {
        let name = ServerUploadPath.lastComponent(of: folder)
        let parent = ServerUploadPath.parent(of: folder)
        let siblings = try await client.folderNames(in: parent)
        return !siblings.contains(name) && !siblings.contains { $0.lowercased() == name.lowercased() }
    }

    private func stop(_ watch: CommonPhotosWatch, _ reason: CommonPhotosWatch.Stop) -> Outcome {
        record { try store.stop(id: watch.id, because: reason) }
        return .stopped(reason)
    }

    /// A store write the pass cannot do without: logged, so a database
    /// that refuses is seen, and the pass goes on to its outcome.
    private func record(_ write: () throws -> Void) {
        do { try write() } catch {
            Self.logger.error("gather pass: \(error.localizedDescription, privacy: .public)")
        }
    }
}
