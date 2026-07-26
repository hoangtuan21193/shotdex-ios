import Foundation
import ImageIO
import Photos
import os

/// Outcome of trying to read EXIF for one asset.
enum ExifReadResult: Sendable {
    case success(RawExif)
    /// The original is in iCloud and couldn't be read (yet), or the network
    /// failed / stalled before the bytes arrived — **retryable, indefinitely**.
    /// This is the "couldn't download" case: never counts as a permanent
    /// failure, so a flaky link never ends with a photo wrongly marked
    /// no-metadata. It resolves once the file downloads.
    case pendingICloud
    /// The bytes **were obtained** (local file present, or the iCloud download
    /// completed) but ImageIO could not parse EXIF/TIFF from them — a genuinely
    /// unreadable original (corrupt / truncated / unsupported). Deterministic,
    /// so after a few attempts the row is treated as having no EXIF. Distinct
    /// from `pendingICloud`: "downloaded but unreadable", not "couldn't
    /// download".
    case unreadable
    /// Could not obtain the bytes for a **non-network** reason: no photo
    /// resource, or a hard local read error (a local original PhotoKit can't
    /// serve). Guaranteed local — network transport failures return
    /// `pendingICloud`, never this — so, like `unreadable`, it counts toward
    /// the give-up cap: a permanently unreadable local original eventually
    /// resolves to no-EXIF instead of retrying every run forever.
    case failure
}

/// Reads EXIF from asset originals via ImageIO without decoding pixels.
/// Every read *streams* the original — from disk for local files, from the
/// network for iCloud-only originals — and stops as soon as the leading bytes
/// holding the metadata sections have been parsed. Nothing is written to disk.
struct ExifReader: Sendable {
    private static let logger = Logger(subsystem: "com.hoangtuan.shotdex", category: "exif")

    /// Caps concurrent iCloud streaming reads below the pipeline's total
    /// fan-out (12 readers). That many parallel network streams divide the bandwidth
    /// until individual reads starve through their 8 s stall window — false
    /// stalls that feed (and eventually trip) the circuit breaker even on a
    /// healthy link. Four streams keep the pipe full without starving any one
    /// read, and — as important — halve the request+cancel churn against
    /// cloudphotod: sustained bursts of cancelled downloads wedge the daemon
    /// into serving zero bytes until it gets a rest (observed on device).
    /// Static so the cap holds process-wide, covering the pipeline and the
    /// detail viewer's `indexSingle` alike. Local reads are not limited.
    private static let networkStreamLimiter = AsyncLimiter(limit: 4)

    /// Receives the size of every chunk streamed from iCloud, feeding the
    /// indexing UI's downloaded-bytes / speed display. Disk reads don't count.
    var trafficMonitor: IndexTrafficMonitor? = nil

    /// Picks the resource holding the original photo bytes.
    static func photoResource(among resources: [PHAssetResource]) -> PHAssetResource? {
        resources.first {
            $0.type == .photo || $0.type == .fullSizePhoto || $0.type == .alternatePhoto
        } ?? resources.first
    }

    /// Reads EXIF for an asset. `resource` comes from the caller so the
    /// per-asset `assetResources` XPC round-trip happens exactly once.
    ///
    /// Local-first: stream from disk (no network); if the original is
    /// iCloud-only and `allowNetwork`, stream the file header from iCloud.
    func readExif(for asset: PHAsset, resource: PHAssetResource?, allowNetwork: Bool) async -> ExifReadResult {
        guard let resource else {
            Self.logger.info("readExif \(asset.localIdentifier, privacy: .public): no photo resource — failure")
            return .failure
        }
        // Per-asset decision trace. A resumed run only reaches this read for
        // the still-incomplete rows (needsReindex skips everything done), so
        // this stays quiet — it lights up exactly for the assets that keep
        // getting stuck, showing which branch bails and why.
        let name = resource.originalFilename

        func networkAttempt() async -> ExifReadResult {
            guard allowNetwork else {
                Self.logger.info("readExif \(name, privacy: .public): network disallowed — pendingICloud")
                return .pendingICloud
            }
            // Circuit breaker: once the network has stalled out too many
            // times (iCloud can't serve originals, or the link died), stop
            // even trying — return pendingICloud instantly instead of burning
            // a stall window per asset. Half-open: after the cooldown the
            // check passes again and reads probe the network on their own.
            if trafficMonitor?.isNetworkTripped == true {
                Self.logger.info("readExif \(name, privacy: .public): circuit breaker tripped — pendingICloud")
                return .pendingICloud
            }
            // Queue for a streaming slot, then re-check the breaker: it may
            // have tripped while this read waited behind the other streams.
            return await Self.networkStreamLimiter.withPermit {
                if trafficMonitor?.isNetworkTripped == true {
                    Self.logger.info("readExif \(name, privacy: .public): breaker tripped while queued — pendingICloud")
                    return .pendingICloud
                }
                // Post-stall breather: sleeping *while holding the permit* is
                // deliberate — it throttles the whole network lane, giving
                // cloudphotod room to drain before the next request lands.
                while let rest = trafficMonitor?.networkRestRemaining {
                    try? await Task.sleep(for: rest)
                }
                // Final gate: the window may have tripped while this read
                // slept, and at half-open only one read wins the probe slot —
                // the rest skip instead of burning a stall window each.
                if trafficMonitor?.shouldSkipNetworkRead() == true {
                    Self.logger.info("readExif \(name, privacy: .public): half-open probe lost — pendingICloud")
                    return .pendingICloud
                }
                Self.logger.info("readExif \(name, privacy: .public): starting 8s network stream")
                trafficMonitor?.beginNetworkRead()
                defer { trafficMonitor?.endNetworkRead() }
                let before = trafficMonitor?.totalBytes ?? 0
                let clock = ContinuousClock()
                let start = clock.now
                // 8 s *stall* window (no-progress), not an absolute cap: a real
                // download delivers the small metadata header well within one
                // window, while an unreachable original bails after ~8 s instead
                // of 30 s.
                let result = await streamExif(resource: resource, useNetwork: true, timeout: .seconds(8))
                let elapsedMs = Int((clock.now - start) / .milliseconds(1))
                let bytes = (trafficMonitor?.totalBytes ?? 0) - before
                if bytes > 0 { trafficMonitor?.recordNetworkProgress() }
                switch result {
                case .success(let exif):
                    Self.logger.info("readExif \(name, privacy: .public): network stream success, \(bytes) B in \(elapsedMs) ms")
                    return .success(exif)
                case .needsNetwork:
                    // Zero-byte stall feeds the breaker (which logs stall and
                    // trip events itself); a partial-then-dropped transfer
                    // already reset it via `recordNetworkProgress`.
                    Self.logger.info("readExif \(name, privacy: .public): network needsNetwork (\(bytes) B in \(elapsedMs) ms, stall=\(bytes == 0)) — pendingICloud")
                    if bytes == 0 {
                        trafficMonitor?.recordNetworkStall(
                            filename: resource.originalFilename, elapsedMs: elapsedMs
                        )
                    }
                    return .pendingICloud
                case .overBudget:
                    Self.logger.info("readExif \(name, privacy: .public): network overBudget (\(bytes) B, metadata past stream budget) — pendingICloud")
                    return .pendingICloud
                case .unreadable:
                    // Download completed but the bytes don't parse — genuinely
                    // unreadable, NOT a network problem. This is the only iCloud
                    // path that may lead to noExif.
                    Self.logger.log("read \(resource.originalFilename, privacy: .public): downloaded \(bytes) B but unparseable — unreadable")
                    return .unreadable
                case .failure:
                    // Now unreachable on the network path (a completion error
                    // maps to `.needsNetwork`, a completed-but-unparseable read
                    // to `.unreadable`). Kept defensive: treat any unexpected
                    // network failure as retryable, never a permanent give-up —
                    // so `.failure` at the top level is guaranteed non-network.
                    Self.logger.log("read \(resource.originalFilename, privacy: .public): unexpected iCloud read failure, \(bytes) B in \(elapsedMs) ms — pendingICloud")
                    return .pendingICloud
                }
            }
        }

        // When the original isn't on disk, try the on-device optimized
        // derivative before touching the network. Under "Optimize iPhone
        // Storage" the derivative is the only local copy, and it keeps the
        // full EXIF/TIFF metadata block (only the pixels are downscaled), so
        // this resolves most assets without an iCloud download — and without
        // the account-auth failures (`com.apple.accounts` errors) that pulling
        // the original triggers when iCloud can't serve it.
        func localDerivativeThenNetwork() async -> ExifReadResult {
            let local = await readExifFromLocalDerivative(for: asset)
            switch local {
            case .success:
                Self.logger.info("readExif \(name, privacy: .public): resolved via local derivative")
                return local
            case .unreadable:
                Self.logger.info("readExif \(name, privacy: .public): local derivative bytes unparseable — unreadable")
                return local
            case .failure:
                Self.logger.info("readExif \(name, privacy: .public): local derivative failed — failure")
                return local
            case .pendingICloud:
                // No usable local derivative (never opened / freshly synced) —
                // the original genuinely has to come from iCloud.
                Self.logger.info("readExif \(name, privacy: .public): no local derivative, going to network (allowNetwork=\(allowNetwork))")
                return await networkAttempt()
            }
        }

        switch await streamExif(resource: resource, useNetwork: false, timeout: .seconds(10)) {
        case .success(let exif):
            return .success(exif)
        case .unreadable:
            // Full local buffer arrived (no error) but doesn't parse — a broken
            // local original. Trustworthy: an offloaded original would error or
            // deliver nothing, not a complete unparseable buffer.
            Self.logger.info("readExif \(name, privacy: .public): local bytes unparseable — unreadable")
            return .unreadable
        case .failure:
            // iCloud-offloaded originals don't reliably fail the local read
            // with `.networkAccessRequired` — the error domain varies across
            // Photos versions — so every local failure gets one derivative-then-
            // network retry. A genuinely broken local file fails there too.
            Self.logger.info("readExif \(name, privacy: .public): local stream failed — derivative+network fallback")
            return await localDerivativeThenNetwork()
        case .overBudget:
            // Metadata sits beyond the streaming budget (rare container
            // layout, e.g. media data before the meta box). The file is
            // local — fall back to a file-URL read that can seek anywhere.
            Self.logger.info("readExif \(name, privacy: .public): local stream over budget — editing-input fallback")
            return await readExifViaEditingInput(for: asset)
        case .needsNetwork:
            Self.logger.info("readExif \(name, privacy: .public): local stream needsNetwork — derivative+network fallback")
            return await localDerivativeThenNetwork()
        }
    }

    /// Reads EXIF from the on-device optimized derivative with **no network**.
    /// Even under "Optimize iPhone Storage" — where the original lives only in
    /// iCloud — Photos keeps a downscaled local rendition whose EXIF/TIFF
    /// metadata block is intact, which is all `parse` needs. Because network is
    /// disallowed this never starts an iCloud download and never provokes the
    /// account-auth failure that reading the original does.
    ///
    /// Returns `.pendingICloud` only when there is no local rendition at all,
    /// signalling the caller to fall back to a networked original read.
    func readExifFromLocalDerivative(for asset: PHAsset, timeout: Duration = .seconds(5)) async -> ExifReadResult {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false   // local rendition only, never download
        // `.fastFormat`, not `.highQualityFormat`: we want only the metadata
        // block, so any local rendition will do. `.highQualityFormat` insists on
        // the high-quality version — which under "Optimize iPhone Storage" lives
        // only in iCloud — and returns nil data locally, forcing a needless
        // network read. `.fastFormat` hands back whatever downscaled rendition is
        // already on device (its EXIF/TIFF block is intact).
        options.deliveryMode = .fastFormat
        options.isSynchronous = false

        return await withCheckedContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            // Un-cancelled timeout tasks would pile up across a large library —
            // cancel on completion.
            let timeoutTask = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)
            let requestId = PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                guard resumed.claim() else { return }
                timeoutTask.withLock { $0?.cancel() }
                let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
                if let data {
                    // Got rendition bytes. If ImageIO can't parse them the
                    // original is unreadable (not a download problem).
                    if let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
                       let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions) as? [CFString: Any] {
                        continuation.resume(returning: .success(Self.parse(properties: properties)))
                    } else {
                        continuation.resume(returning: .unreadable)
                    }
                    return
                }
                // No local rendition → the caller must go to the network.
                let isInCloud = (info?[PHImageResultIsInCloudKey] as? NSNumber)?.boolValue ?? false
                continuation.resume(returning: isInCloud ? .pendingICloud : .failure)
            }
            let task = Task {
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled, resumed.claim() else { return }
                PHImageManager.default().cancelImageRequest(requestId)
                continuation.resume(returning: .pendingICloud)
            }
            timeoutTask.withLock { $0 = task }
        }
    }

    /// Internal outcome of one streaming attempt.
    private enum StreamResult: Sendable {
        case success(RawExif)
        /// Original not on device / transient network error / timeout.
        case needsNetwork
        /// Metadata not found within `maxBytes`.
        case overBudget
        /// The full buffer arrived (no error) but ImageIO could not parse it —
        /// an unreadable original, not a transport problem.
        case unreadable
        /// Hard error obtaining the bytes for a non-network reason.
        case failure
    }

    /// Streams the original just far enough to parse its metadata sections
    /// (typically 64–300 KB), then cancels the request. The buffer stays in
    /// memory; the original is never persisted locally.
    /// `timeout` is a **no-progress (stall) window**, not an absolute cap: the
    /// read is aborted only after a full window passes with zero new bytes.
    private func streamExif(
        resource: PHAssetResource,
        useNetwork: Bool,
        maxBytes: Int = 8_388_608,
        timeout: Duration
    ) async -> StreamResult {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = useNetwork
        let manager = PHAssetResourceManager.default()

        return await withCheckedContinuation { continuation in
            let state = OSAllocatedUnfairLock(initialState: StreamState())
            // With a dozen concurrent reads over a large library, un-cancelled
            // timeout tasks would pile up by the thousands — cancel on resume.
            let timeoutTask = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

            // Requests a cancel: directly when the request id is already
            // known, otherwise flags it for the post-`requestData` check.
            func cancelDownload() {
                let id = state.withLock { s -> PHAssetResourceDataRequestID? in
                    if let id = s.requestId { return id }
                    s.cancelPending = true
                    return nil
                }
                if let id { manager.cancelDataRequest(id) }
            }

            let requestId = manager.requestData(for: resource, options: options) { chunk in
                // Chunks can still arrive between resume and cancel taking
                // effect — they were downloaded either way, so count them all.
                if useNetwork { trafficMonitor?.add(chunk.count) }
                let outcome = state.withLock { s -> StreamResult? in
                    guard !s.resumed else { return nil }
                    s.buffer.append(chunk)
                    s.progressed = true
                    // Incremental parse (early-stop) only for network reads,
                    // where cutting the download short after the metadata box
                    // saves real bandwidth. For local reads the whole file
                    // arrives from disk in milliseconds anyway, and feeding a
                    // growing partial buffer to `CGImageSourceCopyPropertiesAtIndex`
                    // makes ImageIO try to init the HEVC decoder on incomplete
                    // HEIC on *every* chunk — repeated failures (err -39/-12894)
                    // that spam the log and burn CPU. Local reads parse once in
                    // the completion handler on the complete buffer instead.
                    if useNetwork, let properties = Self.metadataProperties(fromPartial: s.buffer) {
                        s.resumed = true
                        return .success(Self.parse(properties: properties))
                    }
                    if s.buffer.count >= maxBytes {
                        s.resumed = true
                        // Local reads skip the per-chunk incremental parse
                        // above (HEIC decode spam), so a local original larger
                        // than the streaming budget reaches the cap unparsed.
                        // JPEG and most containers carry the metadata block at
                        // the front — well inside the buffer — so try one parse
                        // of the accumulated prefix before giving up. Recovers a
                        // big local original here instead of dropping to the
                        // slower editing-input fallback (which can itself fail,
                        // e.g. PHPhotosError 3164).
                        if !useNetwork, let properties = Self.metadataProperties(fromPartial: s.buffer) {
                            return .success(Self.parse(properties: properties))
                        }
                        return .overBudget
                    }
                    return nil
                }
                guard let outcome else { return }
                timeoutTask.withLock { $0?.cancel() }
                cancelDownload()
                continuation.resume(returning: outcome)
            } completionHandler: { error in
                let buffer = state.withLock { s -> Data? in
                    guard !s.resumed else { return nil }
                    s.resumed = true
                    return s.buffer
                }
                guard let buffer else { return }
                timeoutTask.withLock { $0?.cancel() }
                if let error {
                    if useNetwork {
                        // Surface the error identity on the health stream: a
                        // wedged cloudphotod usually *hangs* (stall watchdog
                        // fires, no error), so an actual returned error — e.g.
                        // com.apple.accounts Code=7 — is diagnostic gold.
                        let nsError = error as NSError
                        IndexTrafficMonitor.healthLogger.log("iCloud read error: \(resource.originalFilename, privacy: .public) — \(nsError.domain, privacy: .public) code \(nsError.code)")
                        // Network hiccup or user-cancelled download — retryable.
                        continuation.resume(returning: .needsNetwork)
                    } else {
                        // Offloaded original is the expected local failure;
                        // anything else is a real read error.
                        let inCloud = (error as? PHPhotosError)?.code == .networkAccessRequired
                        continuation.resume(returning: inCloud ? .needsNetwork : .failure)
                    }
                    return
                }
                // Whole (small) file arrived before the incremental parse
                // succeeded — parse it as a complete image.
                let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
                if let source = CGImageSourceCreateWithData(buffer as CFData, sourceOptions),
                   let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions) as? [CFString: Any] {
                    continuation.resume(returning: .success(Self.parse(properties: properties)))
                } else {
                    // Bytes fully arrived (no error) but unparseable — the
                    // original is unreadable, not a transport failure.
                    continuation.resume(returning: .unreadable)
                }
            }

            // The data handler can win the race before the id is stored;
            // honor its pending cancel here.
            let cancelWasPending = state.withLock { s in
                s.requestId = requestId
                return s.cancelPending
            }
            if cancelWasPending {
                manager.cancelDataRequest(requestId)
            }

            // No-progress watchdog: `timeout` is now a *stall* window, not an
            // absolute deadline. As long as bytes keep arriving each interval
            // the read continues; a window with zero new bytes aborts it. An
            // unreachable iCloud original (0 B for the whole request) used to
            // block a full 30 s absolute timeout — now it bails after one
            // stall window, so a library full of offloaded assets doesn't
            // serialise 30 s per asset.
            let task = Task {
                while true {
                    try? await Task.sleep(for: timeout)
                    if Task.isCancelled { return }
                    let decision = state.withLock { s -> Int in
                        if s.resumed { return 0 }          // already finished
                        if s.progressed { s.progressed = false; return 1 }  // still moving
                        s.resumed = true; return 2         // stalled
                    }
                    switch decision {
                    case 0: return
                    case 1: continue
                    default:
                        cancelDownload()
                        continuation.resume(returning: .needsNetwork)
                        return
                    }
                }
            }
            timeoutTask.withLock { $0 = task }
            // Fast local reads can resume before the task was stored —
            // their cancel was a no-op, so re-check here.
            if state.withLock({ $0.resumed }) {
                task.cancel()
            }
        }
    }

    private struct StreamState: Sendable {
        var buffer = Data()
        var resumed = false
        var requestId: PHAssetResourceDataRequestID?
        var cancelPending = false
        /// Set on every chunk; the watchdog resets it each interval to detect
        /// a stalled transfer (no bytes arriving) and bail out early.
        var progressed = false
    }

    /// Slow-path fallback for local originals whose metadata lies beyond the
    /// streaming budget: `PHContentEditingInput` grants a direct file URL that
    /// ImageIO can seek anywhere in. `canHandleAdjustmentData = true` keeps
    /// Photos from rendering edited assets — the URL points at the original.
    func readExifViaEditingInput(for asset: PHAsset, timeout: Duration = .seconds(10)) async -> ExifReadResult {
        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = false
        options.canHandleAdjustmentData = { _ in true }

        return await withCheckedContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            // Un-cancelled timeout tasks would pile up across a large
            // library — cancel on completion.
            let timeoutTask = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)
            let requestId = asset.requestContentEditingInput(with: options) { input, info in
                guard resumed.claim() else { return }
                timeoutTask.withLock { $0?.cancel() }
                if let url = input?.fullSizeImageURL {
                    continuation.resume(returning: Self.readExif(fromImageAt: url))
                    return
                }
                let isInCloud = (info[PHContentEditingInputResultIsInCloudKey] as? NSNumber)?.boolValue ?? false
                continuation.resume(returning: isInCloud ? .pendingICloud : .failure)
            }
            let task = Task {
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled, resumed.claim() else { return }
                asset.cancelContentEditingInputRequest(requestId)
                continuation.resume(returning: .pendingICloud)
            }
            timeoutTask.withLock { $0 = task }
        }
    }

    /// Attempts to parse metadata from a file prefix. Only accepts the result
    /// once an EXIF or TIFF section is present — partial data can yield a
    /// dictionary before the metadata sections have arrived.
    private static func metadataProperties(fromPartial data: Data) -> [CFString: Any]? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        let source = CGImageSourceCreateIncremental(sourceOptions)
        CGImageSourceUpdateData(source, data as CFData, false)
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions) as? [CFString: Any],
              properties[kCGImagePropertyExifDictionary] != nil
                || properties[kCGImagePropertyTIFFDictionary] != nil
        else { return nil }
        return properties
    }

    /// Reads EXIF from an image file URL. Never decodes the image
    /// (`kCGImageSourceShouldCache = false`, properties only).
    static func readExif(fromImageAt url: URL) -> ExifReadResult {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions) as? [CFString: Any]
        else {
            // The file URL resolved but ImageIO can't parse it — the original
            // is unreadable, not a download problem.
            return .unreadable
        }
        return .success(parse(properties: properties))
    }

    /// Extracts the standard tags from the ImageIO properties dictionary
    /// ({Exif}, {TIFF}, {ExifAux}). Maker notes are out of scope for MVP.
    static func parse(properties: [CFString: Any]) -> RawExif {
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exifAux = properties[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]

        let isoValue: Int? = {
            if let ratings = exif[kCGImagePropertyExifISOSpeedRatings] as? [Any],
               let first = ratings.first as? NSNumber {
                return first.intValue
            }
            return (exif[kCGImagePropertyExifISOSpeedRatings] as? NSNumber)?.intValue
        }()

        return RawExif(
            make: tiff[kCGImagePropertyTIFFMake] as? String,
            model: tiff[kCGImagePropertyTIFFModel] as? String,
            lensMake: exif[kCGImagePropertyExifLensMake] as? String,
            lensModel: (exif[kCGImagePropertyExifLensModel] as? String)
                ?? (exifAux[kCGImagePropertyExifAuxLensModel] as? String),
            iso: isoValue,
            fNumber: positiveDouble(exif[kCGImagePropertyExifFNumber]),
            exposureTimeSeconds: positiveDouble(exif[kCGImagePropertyExifExposureTime]),
            focalLength: positiveDouble(exif[kCGImagePropertyExifFocalLength]),
            focalLengthIn35mm: positiveDouble(exif[kCGImagePropertyExifFocalLenIn35mmFilm])
        )
    }

    private static func positiveDouble(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        let double = number.doubleValue
        return double > 0 && double.isFinite ? double : nil
    }
}

private extension OSAllocatedUnfairLock where State == Bool {
    /// Atomically flips false → true; returns whether this caller won.
    func claim() -> Bool {
        withLock { resumed in
            if resumed { return false }
            resumed = true
            return true
        }
    }
}
