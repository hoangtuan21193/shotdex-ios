import Foundation
import Observation

/// Every asset with at least one verified file on a server, as a set the
/// grid can ask per cell without touching the database (FS-15 §5): one read
/// at launch, then updated as uploads finish.
@MainActor
@Observable
final class ServerUploadIndex {
    private(set) var assetIds: Set<String> = []
    /// Photos items on a server source now, byte for byte (FS-19.07 §8):
    /// what the grid's "on server" glyph shows. The upload history above
    /// still feeds Uploaded to Server and Photo Info.
    private(set) var presentIds: Set<String> = []
    private(set) var presentVersion = 0
    /// Bumped on every change, so the grid can tell "new set" without
    /// comparing two sets of 55k ids.
    private(set) var version = 0
    private let store: ServerUploadStore
    private var hasLoaded = false

    init(store: ServerUploadStore) {
        self.store = store
    }

    func contains(_ assetId: String) -> Bool { assetIds.contains(assetId) }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        reload()
    }

    func reload() {
        let store = store
        Task {
            let ids = await Task.detached(priority: .utility) { (try? store.uploadedAssetIds()) ?? [] }.value
            self.assetIds = ids
            self.version += 1
        }
    }

    /// Reads which Photos items are on a server again — after each batch
    /// of the on-server check.
    func reloadPresence(_ load: @escaping @Sendable () throws -> Set<String>) {
        Task {
            let ids = await Task.detached(priority: .utility) { (try? load()) ?? [] }.value
            guard ids != self.presentIds else { return }
            self.presentIds = ids
            self.presentVersion += 1
        }
    }

    /// One photo's history, newest first — the Photo Info section.
    func uploads(assetId: String) -> [ServerUploadRecord] {
        guard assetIds.contains(assetId) else { return [] }
        return (try? store.uploads(assetId: assetId)) ?? []
    }

    /// A batch just verified these — no need to go back to the database.
    func insert(_ ids: some Sequence<String>) {
        let before = assetIds.count
        assetIds.formUnion(ids)
        if assetIds.count != before { version += 1 }
    }
}
