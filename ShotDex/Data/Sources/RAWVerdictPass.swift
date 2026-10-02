import Foundation

/// The launch-time pass of FS-03.04b §2: every camera with RAW-named photos
/// in the index and no settled verdict for this iOS build is judged —
/// decoder list, then up to two files on the device, else unknown.
struct RAWVerdictPass: Sendable {
    let store: RAWVerdictStore
    let probe: any RAWDecoderProbing
    let release: OSRelease

    /// Returns whether anything the grid shows changed: a verdict, or a pair
    /// newly found among a camera that is not readable.
    @discardableResult
    func run() async throws -> Bool {
        let matcher = RAWCameraMatcher(supportedModels: probe.supportedCameraModels())
        let stored = try store.verdicts(build: release.build)
        var changed = false
        for indexed in try store.indexedRAWCameras() {
            if Task.isCancelled { break }
            let previous = stored[indexed.camera.key]
            if previous == .readable { continue }
            let listed = matcher.isListed(make: indexed.exifMake, model: indexed.exifModel)
                || matcher.isListed(make: indexed.camera.manufacturer, model: indexed.camera.model)
            var verdict = previous
            var source: RAWVerdictSource?
            if listed {
                // Also re-reads a camera settled as unreadable: the decoder's
                // list grows without a new build (it ships as a downloadable
                // asset).
                (verdict, source) = (.readable, .list)
            } else if previous != .unreadable {
                var ids = try store.rawAssetIds(of: indexed.camera)[...]
                let judged = await RAWVerdictRules.judge(listed: false) {
                    while let id = ids.popFirst() {
                        if let decodes = await probe.localFileDecodes(assetId: id) { return decodes }
                    }
                    return nil
                }
                (verdict, source) = (judged.verdict, judged.source)
            }
            if verdict != .readable {
                // A pair kept with the RAW as its original looks RAW-only to
                // the index; it is never marked.
                let candidates = try store.rawAssetIds(of: indexed.camera)
                let twins = await probe.renderedTwinIds(among: candidates)
                if try store.addPairs(twins) > 0 { changed = true }
            }
            if let verdict, verdict != previous {
                try store.record(verdict, source: source, for: indexed.camera, build: release.build)
                changed = true
            }
        }
        return changed
    }
}
