import Foundation

/// The launch-time pass of FS-03.04b §2: every camera with RAW-named photos
/// in the index and no settled verdict for this iOS build is judged —
/// decoder list, then up to two files on the device, else unknown.
struct RAWVerdictPass: Sendable {
    let store: RAWVerdictStore
    let probe: any RAWDecoderProbing
    let release: OSRelease

    /// Returns whether any verdict changed.
    @discardableResult
    func run() async throws -> Bool {
        let matcher = RAWCameraMatcher(supportedModels: probe.supportedCameraModels())
        let stored = try store.verdicts(build: release.build)
        var changed = false
        for indexed in try store.indexedRAWCameras() {
            if Task.isCancelled { break }
            let previous = stored[indexed.camera.key]
            let listed = matcher.isListed(make: indexed.exifMake, model: indexed.exifModel)
                || matcher.isListed(make: indexed.camera.manufacturer, model: indexed.camera.model)
            switch previous {
            case .readable:
                continue
            case .unreadable:
                // Settled by files, but the decoder's list can grow without
                // a new build (it ships as a downloadable asset).
                guard listed else { continue }
            case .unknown, nil:
                break
            }
            var ids = try (listed ? [] : store.rawAssetIds(of: indexed.camera))[...]
            let (verdict, source) = await RAWVerdictRules.judge(listed: listed) {
                while let id = ids.popFirst() {
                    if let decodes = await probe.localFileDecodes(assetId: id) { return decodes }
                }
                return nil
            }
            guard verdict != previous else { continue }
            try store.record(verdict, source: source, for: indexed.camera, build: release.build)
            changed = true
        }
        return changed
    }
}
