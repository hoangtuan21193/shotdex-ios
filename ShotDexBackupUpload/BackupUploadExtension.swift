import ExtensionFoundation
import Foundation
import os
import Photos
import UniformTypeIdentifiers

/// Photos wakes this extension when new photos arrive, even with ShotDex
/// closed (FS-22.02 §3c). For every Photos → WebDAV backup it asks Photos to
/// PUT each new original to its `.shotdex-part` name; the app reads the file
/// back, checks it and gives it its real name on its next run. It never
/// writes the real name and never opens the database.
@main
struct BackupUploadExtension: PHBackgroundResourceUploadExtension {
    init() {}

    func process() -> PHBackgroundResourceUploadProcessingResult {
        acknowledgeFinishedJobs()
        let config = BackupUploadShared.readConfig()
        guard !config.jobs.isEmpty else { return .completed }

        var tokens = BackupUploadShared.readTokens()
        let library = PHPhotoLibrary.shared()
        let current = try? NSKeyedArchiver.archivedData(withRootObject: library.currentChangeToken, requiringSecureCoding: true)
        var room = PHAssetResourceUploadJob.jobLimit
        var finishedEverything = true

        for job in config.jobs {
            // First wake for a job: start from now — the app copies what
            // was already there.
            guard let archived = tokens[job.jobId],
                  let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: PHPersistentChangeToken.self, from: archived),
                  let changes = try? library.fetchPersistentChanges(since: token) else {
                tokens[job.jobId] = current
                continue
            }
            var inserted: [String] = []
            for change in changes {
                if let details = try? change.changeDetails(for: .asset) { inserted += details.insertedLocalIdentifiers }
            }
            let authorization = BackupUploadShared.authorization(account: job.account)
            let planner = BackupPathPlanner(organize: job.settings.organize, names: BackupDateName())
            var created = Set<String>()
            var completedAll = true
            PHAsset.fetchAssets(withLocalIdentifiers: inserted, options: nil).enumerateObjects { asset, _, stop in
                let isVideo = asset.mediaType == .video
                switch job.settings.content {
                case .photosOnly where isVideo, .videosOnly where !isVideo: return
                default: break
                }
                for resource in PHAssetResource.assetResources(for: asset) where Self.isOriginal(resource.type) {
                    guard room > 0, !Self.isTerminating.withLock({ $0 }) else {
                        completedAll = false
                        stop.pointee = true
                        return
                    }
                    let input = BackupPlacementInput(
                        date: asset.creationDate ?? Date(), isVideo: isVideo, originalFilename: resource.originalFilename,
                        isRAW: UTType(resource.uniformTypeIdentifier)?.conforms(to: .rawImage) ?? false
                    )
                    let relative = planner.relativePath(for: input)
                    for folder in BackupUploadRequests.folders(for: relative, job: job) where !created.contains(folder) {
                        Self.makeFolder(folder, job: job, authorization: authorization)
                        created.insert(folder)
                    }
                    guard let request = BackupUploadRequests.put(relativePath: relative, job: job, authorization: authorization) else { continue }
                    do {
                        try library.performChangesAndWait {
                            if #available(iOS 26.4, *) {
                                _ = PHAssetResourceUploadJobChangeRequest.creationRequestForJob(destination: request, resource: resource)
                            } else {
                                PHAssetResourceUploadJobChangeRequest.createJob(destination: request, resource: resource)
                            }
                        }
                        room -= 1
                    } catch {
                        completedAll = false
                    }
                }
            }
            // The token always moves on, so a later wake never queues the same
            // files twice; what did not fit is copied by the app's next run.
            tokens[job.jobId] = current
            if !completedAll { finishedEverything = false }
        }
        BackupUploadShared.writeTokens(tokens)
        return finishedEverything ? .completed : .processing
    }

    func notifyTermination() {
        Self.isTerminating.withLock { $0 = true }
    }

    /// Set when iOS is about to end the extension; `process()` stops queuing.
    private static let isTerminating = OSAllocatedUnfairLock(initialState: false)

    private static func isOriginal(_ type: PHAssetResourceType) -> Bool {
        [.photo, .alternatePhoto, .video, .pairedVideo].contains(type)
    }

    /// Jobs that ended (either way) are acknowledged so the limit frees up;
    /// a failed one is copied by the app's normal path on its next run.
    private func acknowledgeFinishedJobs() {
        let finished = PHAssetResourceUploadJob.fetchJobs(action: .acknowledge, options: nil)
        guard finished.count > 0 else { return }
        try? PHPhotoLibrary.shared().performChangesAndWait {
            finished.enumerateObjects { job, _, _ in
                PHAssetResourceUploadJobChangeRequest(for: job)?.acknowledge()
            }
        }
    }

    /// WebDAV refuses a PUT into a folder that is not there, and Photos only
    /// sends the PUT — so the folders are made here, on the LAN, first.
    private static func makeFolder(_ folder: String, job: BackupUploadConfig.Job, authorization: String?) {
        guard let request = BackupUploadRequests.mkcol(folder, job: job, authorization: authorization) else { return }
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in done.signal() }.resume()
        _ = done.wait(timeout: .now() + 10)
    }
}
