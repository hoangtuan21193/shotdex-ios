import Foundation
import Observation

/// Every asset with at least one verified file on a server, as a set the
/// grid can ask per cell without touching the database (FS-15 §5): one read
/// at launch, then updated as uploads finish.
@MainActor
@Observable
final class ServerUploadIndex {
    private(set) var assetIds: Set<String> = []
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
        }
    }

    /// A batch just verified these — no need to go back to the database.
    func insert(_ ids: some Sequence<String>) {
        assetIds.formUnion(ids)
    }
}
