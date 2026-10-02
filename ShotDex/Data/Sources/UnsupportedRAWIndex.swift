import Foundation
import Observation

/// The photos whose RAW this iOS build can't read (FS-03.04b §3), as a set
/// the grid asks per cell without touching the database (NF-01): read once,
/// then again whenever a verdict changes — after the launch pass, after an
/// index run, after the editor is refused.
@MainActor
@Observable
final class UnsupportedRAWIndex {
    private(set) var assetIds: Set<String> = []
    /// Bumped on every change, so the grid can tell "new set" without
    /// comparing two large sets.
    private(set) var version = 0
    let store: RAWVerdictStore
    let release: OSRelease
    private let probe: any RAWDecoderProbing
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private var passTask: Task<Void, Never>?
    @ObservationIgnored private var passAgain = false

    init(store: RAWVerdictStore, probe: any RAWDecoderProbing = SystemRAWDecoderProbe(), release: OSRelease = .current) {
        self.store = store
        self.probe = probe
        self.release = release
    }

    func contains(_ assetId: String) -> Bool { assetIds.contains(assetId) }

    /// What to tell the user about this photo when it is one the decoder
    /// can't read — from the index alone, so Edit answers at once and
    /// downloads nothing (AC-3, AC-4). Nil for every other photo.
    func message(for assetId: String) -> UnsupportedRAWMessage? {
        guard assetIds.contains(assetId) else { return nil }
        let indexed = (try? store.cameraAndFilename(of: assetId)) ?? (camera: nil, filename: nil)
        return .make(cameraName: indexed.camera?.displayName, filename: indexed.filename, iOSVersion: release.version)
    }

    /// Whether this photo's camera is one this build can't read — for a
    /// RAW + JPEG pair, which is never in `assetIds`: its Edit RAW is dimmed
    /// (AC-5).
    func isCameraUnreadable(assetId: String) -> Bool {
        guard let camera = (try? store.cameraAndFilename(of: assetId))?.camera else { return false }
        return (try? store.verdict(for: camera, build: release.build)) == .unreadable
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        Task { await reload() }
    }

    func reload() async {
        let store = store, build = release.build
        let ids = await Task.detached(priority: .utility) { (try? store.unreadableAssetIds(build: build)) ?? [] }.value
        guard ids != assetIds else { return }
        assetIds = ids
        version += 1
    }

    /// Judges the cameras with no settled verdict for this build, then
    /// re-reads the set. One pass at a time; a request while one runs
    /// starts another when it ends (an index run may have added cameras).
    func runPass() {
        guard passTask == nil else {
            passAgain = true
            return
        }
        let pass = RAWVerdictPass(store: store, probe: probe, release: release)
        passTask = Task { [weak self] in
            repeat {
                self?.passAgain = false
                let changed = await Task.detached(priority: .utility) { (try? await pass.run()) ?? false }.value
                guard let self else { return }
                if changed || !self.hasLoaded {
                    self.hasLoaded = true
                    await self.reload()
                }
            } while self?.passAgain == true
            self?.passTask = nil
        }
    }

    /// What the editor's own attempt at a photo's RAW says about its camera
    /// (FS-03.04b §2): it settles an unknown camera either way, and marks
    /// its tiles at once when refused (AC-10). A readable camera stays
    /// readable when one odd file fails — only that file reports it.
    func recordEditorResult(assetId: String, decoded: Bool) async {
        let store = store, probe = probe, build = release.build
        let changed = await Task.detached(priority: .utility) { () -> Bool in
            guard let camera = (try? store.cameraAndFilename(of: assetId))?.camera else { return false }
            let stored = (try? store.verdict(for: camera, build: build)) ?? nil
            guard let verdict = RAWVerdictRules.afterEditor(stored, decoded: decoded) else { return false }
            if verdict == .unreadable, let candidates = try? store.rawAssetIds(of: camera) {
                _ = try? store.addPairs(await probe.renderedTwinIds(among: candidates))
            }
            return (try? store.record(verdict, source: .editor, for: camera, build: build)) != nil
        }.value
        if changed { await reload() }
    }

    /// Waits for the pass in flight — the tests' way to know it ended.
    func waitForPass() async {
        while let task = passTask { await task.value }
    }
}
