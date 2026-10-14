import Foundation
import GRDB

/// The AI providers the user added (FS-08.07 §4). The row has no key; the
/// key goes to the Keychain under the provider id and is removed with it.
struct AIProviderStore: Sendable {
    let database: AppDatabase
    let keys: any ServerPasswordStoring

    /// In the order they were added — the Providers group's order.
    func providers() throws -> [AIProvider] {
        try database.reader.read { db in
            try AIProvider.order(Column("createdAt"), Column("name")).fetchAll(db)
        }
    }

    func provider(id: String) throws -> AIProvider? {
        try database.reader.read { db in try AIProvider.fetchOne(db, key: id) }
    }

    /// Saves the row and, when given, the key. A nil key leaves the stored
    /// one alone (the form never shows it again); an empty one removes it —
    /// a home server may need none.
    func save(_ provider: AIProvider, key: String?) throws {
        var provider = provider
        provider.address = Self.normalizedAddress(provider.address)
        try database.writer.write { db in try provider.upsert(db) }
        guard let key else { return }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            keys.removePassword(for: provider.id)
        } else {
            try keys.setPassword(trimmed, for: provider.id)
        }
    }

    /// Scheme, host, port and path only: a pasted `https://user:key@host/…`
    /// or `?key=…` must not carry a secret into the row.
    static func normalizedAddress(_ typed: String) -> String {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed), components.host != nil else {
            return SecretRedaction.redact(trimmed)
        }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string ?? trimmed
    }

    func delete(id: String) throws {
        _ = try database.writer.write { db in try AIProvider.deleteOne(db, key: id) }
        keys.removePassword(for: id)
    }

    func key(for providerId: String) -> String? {
        keys.password(for: providerId)
    }

    /// `Key ends in 7Qx2` (FS-08.07 §3): the last four characters, nil when
    /// there is no key.
    func keySuffix(for providerId: String) -> String? {
        guard let key = keys.password(for: providerId), !key.isEmpty else { return nil }
        return String(key.suffix(4))
    }
}
