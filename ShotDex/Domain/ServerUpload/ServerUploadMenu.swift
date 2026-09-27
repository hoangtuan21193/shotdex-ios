import Foundation

/// Where an upload sheet should start: a connection picked by name, or the
/// form for a new one.
enum ServerUploadTarget: Hashable, Sendable {
    case connection(String)
    case addConnection

    var connectionId: String? {
        if case .connection(let id) = self { id } else { nil }
    }
}

/// The upload row of the selection ⋯ menu (FS-15.02 §1): its shape follows
/// how many connections there are.
enum ServerUploadMenu {
    struct Item: Equatable, Identifiable, Sendable {
        let id: String
        let name: String
        /// `SMB · host/share/folder` — tells two connections to one NAS apart.
        let detail: String
    }

    enum Row: Equatable, Sendable {
        /// No connection yet: "Upload to Server…" opens the Add form.
        case addFirst
        /// "Upload to <name>".
        case single(Item)
        /// "Upload to ▸" with every name, then Add Connection….
        case list([Item])
    }

    static func row(for servers: [FileServer]) -> Row {
        let items = servers
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { Item(id: $0.id, name: $0.name, detail: $0.folderDescription) }
        switch items.count {
        case 0: return .addFirst
        case 1: return .single(items[0])
        default: return .list(items)
        }
    }
}
