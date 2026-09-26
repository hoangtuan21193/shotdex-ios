import Foundation
import Observation

/// The saved connections, in memory, for the selection ⋯ menu to list by
/// name (FS-15.02 §1) without a database read each time it draws. Reloaded
/// by whatever adds, edits or deletes one.
@MainActor
@Observable
final class FileServerCatalog {
    private(set) var servers: [FileServer] = []
    private let store: FileServerStore

    init(store: FileServerStore) {
        self.store = store
    }

    func reload() {
        servers = (try? store.fetchAll()) ?? []
    }
}
