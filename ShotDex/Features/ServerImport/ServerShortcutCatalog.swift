import Foundation
import Observation

/// The Network tiles as Collections and the browser read them (FS-17.04),
/// reloaded after every change.
@MainActor
@Observable
final class ServerShortcutCatalog {
    private(set) var shortcuts: [ServerShortcut] = []
    let store: ServerShortcutStore

    init(store: ServerShortcutStore) {
        self.store = store
    }

    func reload() {
        shortcuts = (try? store.fetchAll()) ?? []
    }

    func shortcut(serverId: String, path: String) -> ServerShortcut? {
        let path = ServerUploadPath.normalizedFolder(path)
        return shortcuts.first { $0.serverId == serverId && $0.path == path }
    }

    func add(serverId: String, path: String, name: String) {
        _ = try? store.add(serverId: serverId, path: path, name: name)
        reload()
    }

    func rename(_ id: String, to name: String) {
        try? store.rename(id, to: name)
        reload()
    }

    func remove(_ id: String) {
        try? store.remove(id)
        reload()
    }

    func setCover(_ jpeg: Data, for id: String) {
        try? store.setCover(jpeg, for: id)
        reload()
    }
}
