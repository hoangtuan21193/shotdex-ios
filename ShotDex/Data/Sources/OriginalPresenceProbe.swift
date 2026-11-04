import Foundation
import Photos
import os

/// Asks PhotoKit whether every original of a Photos item is on this device
/// (FS-06.10 §4, way (a)): each required resource is read with the network
/// off and the read stops at the first chunk. Nothing is downloaded and no
/// image is decoded.
enum OriginalPresenceProbe {
    /// Resource reads at once per batch. PhotoKit serves them from disk;
    /// more than this only queues inside `assetsd`.
    static let concurrency = 4

    /// What every read uses: never the network (AC-5).
    static func requestOptions() -> PHAssetResourceRequestOptions {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = false
        return options
    }

    static func resource(_ type: PHAssetResourceType) -> OriginalPresence.Resource {
        switch type {
        case .photo: .photo
        case .alternatePhoto: .alternatePhoto
        case .pairedVideo: .pairedVideo
        case .video: .video
        case .fullSizePhoto: .fullSizePhoto
        case .fullSizePairedVideo: .fullSizePairedVideo
        case .fullSizeVideo: .fullSizeVideo
        default: .other
        }
    }

    /// A read that has not answered by then cannot tell; the batch moves on.
    static let timeout: Duration = .seconds(10)

    /// The verdict for each id; an id PhotoKit no longer has, or no longer
    /// shares under `.limited`, is left out — the check leaves it unchecked.
    /// Call it off the main actor: the fetch and the resource lists are
    /// synchronous PhotoKit calls.
    static func check(_ ids: [String]) async -> [String: OriginalPresence?] {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var work: [(id: String, resources: [PHAssetResource])] = []
        assets.enumerateObjects { asset, _, _ in
            let all = PHAssetResource.assetResources(for: asset)
            let required = Set(OriginalPresence.required(among: all.map { resource($0.type) }))
            work.append((asset.localIdentifier, all.filter { required.contains(resource($0.type)) }))
        }
        return await withTaskGroup(of: (String, OriginalPresence?).self) { group in
            var results: [String: OriginalPresence?] = [:]
            var next = work.makeIterator()
            func addNext() -> Bool {
                guard !Task.isCancelled, let item = next.next() else { return false }
                // Read-only PhotoKit objects, handed to one child task.
                nonisolated(unsafe) let resources = item.resources
                group.addTask {
                    var answers: [OriginalAvailability] = []
                    for resource in resources {
                        if Task.isCancelled { return (item.id, nil) }
                        let answer = await isLocal(resource)
                        answers.append(answer)
                        if answer == .inCloud { break }
                    }
                    return (item.id, OriginalPresence.judge(answers))
                }
                return true
            }
            for _ in 0..<concurrency where addNext() {}
            while let (id, presence) = await group.next() {
                results[id] = .some(presence)
                _ = addNext()
            }
            return results
        }
    }

    /// One resource, network off: bytes back mean it is here; "network
    /// access required" means it is in iCloud; anything else — another
    /// error, an empty resource, no answer within `timeout`, a cancelled
    /// task — cannot tell. The read stops at the first chunk.
    static func isLocal(_ resource: PHAssetResource) async -> OriginalAvailability {
        let manager = PHAssetResourceManager.default()
        let read = ResourceRead(manager: manager)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                read.begin(continuation)
                let id = manager.requestData(for: resource, options: requestOptions()) { chunk in
                    guard !chunk.isEmpty else { return }
                    read.finish(.local)
                } completionHandler: { error in
                    guard let error = error as NSError? else { return read.finish(read.sawBytes ? .local : .unknown) }
                    if error.domain == PHPhotosErrorDomain, error.code == PHPhotosError.Code.networkAccessRequired.rawValue {
                        return read.finish(.inCloud)
                    }
                    OriginalPresenceCheck.logger.debug("resource read failed: \(error.domain, privacy: .public) \(error.code)")
                    read.finish(.unknown)
                }
                read.setRequest(id)
                read.setTimer(Task {
                    try? await Task.sleep(for: timeout)
                    if !Task.isCancelled { read.finish(.unknown) }
                })
            }
        } onCancel: {
            read.finish(.unknown)
        }
    }
}

/// One resource read's state, shared by PhotoKit's callbacks, the timeout
/// and cancellation: the first answer wins, and the request is cancelled
/// exactly once — also when the answer came before PhotoKit returned the
/// request's id.
private final class ResourceRead: Sendable {
    private struct State {
        var continuation: CheckedContinuation<OriginalAvailability, Never>?
        var request: PHAssetResourceDataRequestID?
        var isDone = false
        var isCancelled = false
        var sawBytes = false
        var timer: Task<Void, Never>?
    }

    private let manager: PHAssetResourceManager
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(manager: PHAssetResourceManager) { self.manager = manager }

    var sawBytes: Bool { state.withLock { $0.sawBytes } }

    func begin(_ continuation: CheckedContinuation<OriginalAvailability, Never>) {
        let finishedEarly = state.withLock { state -> Bool in
            state.continuation = continuation
            return state.isDone
        }
        // Cancelled before the read began.
        if finishedEarly { state.withLock { $0.continuation = nil }; continuation.resume(returning: .unknown) }
    }

    func setRequest(_ id: PHAssetResourceDataRequestID) {
        let cancelNow = state.withLock { state -> Bool in
            state.request = id
            guard state.isDone, !state.isCancelled else { return false }
            state.isCancelled = true
            return true
        }
        if cancelNow { manager.cancelDataRequest(id) }
    }

    /// Cancelled with the answer, so a fast read leaves no sleeping task.
    func setTimer(_ timer: Task<Void, Never>) {
        let isDone = state.withLock { state -> Bool in
            if !state.isDone { state.timer = timer }
            return state.isDone
        }
        if isDone { timer.cancel() }
    }

    func finish(_ value: OriginalAvailability) {
        let (continuation, cancel, timer) = state.withLock { state -> (CheckedContinuation<OriginalAvailability, Never>?, PHAssetResourceDataRequestID?, Task<Void, Never>?) in
            if value == .local { state.sawBytes = true }
            guard !state.isDone else { return (nil, nil, nil) }
            state.isDone = true
            let timer = state.timer
            state.timer = nil
            let continuation = state.continuation
            state.continuation = nil
            var cancel: PHAssetResourceDataRequestID?
            if let request = state.request, !state.isCancelled {
                state.isCancelled = true
                cancel = request
            }
            return (continuation, cancel, timer)
        }
        timer?.cancel()
        if let cancel { manager.cancelDataRequest(cancel) }
        continuation?.resume(returning: value)
    }
}
