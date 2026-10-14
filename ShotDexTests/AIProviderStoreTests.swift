import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-08.07 §4: provider rows hold no key; the key lives in the Keychain
/// under the provider id and goes with the provider.
@Suite @MainActor struct AIProviderStoreTests {
    /// FS-08.07 AC-2 (data half): the key is in the key store under the id;
    /// no column of any table holds it; the row shows only its last four.
    @Test func keyOnlyInKeychain() throws {
        let database = try AppDatabase.makeEmpty()
        let keys = InMemoryPasswordStore()
        let store = AIProviderStore(database: database, keys: keys)
        let claude = AIProvider(kind: .claude, name: "Claude", model: "claude-sonnet-5-5")
        let key = "sk-ant-test-0123456789abcdef7Qx2"

        try store.save(claude, key: key)

        #expect(keys.password(for: claude.id) == key)
        #expect(store.keySuffix(for: claude.id) == "7Qx2")
        let columns = try database.reader.read { db in try db.columns(in: "ai_providers").map(\.name) }
        #expect(!columns.contains { $0.lowercased().contains("key") })
        let dump = try database.reader.read { db -> String in
            var text = ""
            for table in try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'") {
                for row in try Row.fetchAll(db, sql: "SELECT * FROM \"\(table)\"") { text += row.description }
            }
            return text
        }
        #expect(!dump.contains("7Qx2"))
    }

    /// Editing without retyping keeps the key; an empty key removes it.
    @Test func nilKeepsEmptyRemoves() throws {
        let keys = InMemoryPasswordStore()
        let store = AIProviderStore(database: try AppDatabase.makeEmpty(), keys: keys)
        var home = AIProvider(kind: .homeServer, name: "Mac mini", address: "http://192.168.1.10:11434", model: "qwen3:8b")
        try store.save(home, key: "local-key")

        home.model = "gemma3:12b"
        try store.save(home, key: nil)
        #expect(try store.provider(id: home.id)?.model == "gemma3:12b")
        #expect(keys.password(for: home.id) == "local-key")

        try store.save(home, key: "  ")
        #expect(keys.password(for: home.id) == nil)
        #expect(store.keySuffix(for: home.id) == nil)
    }

    /// FS-08.07 AC-5 (data half): deleting the provider removes its key.
    @Test func deleteRemovesKey() throws {
        let keys = InMemoryPasswordStore()
        let store = AIProviderStore(database: try AppDatabase.makeEmpty(), keys: keys)
        let first = AIProvider(kind: .claude, name: "Claude", model: "m", createdAt: 1)
        let second = AIProvider(kind: .claude, name: "Claude (work)", model: "m", createdAt: 2)
        try store.save(first, key: "k1")
        try store.save(second, key: "k2")

        try store.delete(id: first.id)

        #expect(try store.providers().map(\.id) == [second.id])
        #expect(keys.password(for: first.id) == nil)
        #expect(keys.password(for: second.id) == "k2")
    }

    /// A pasted address keeps scheme, host, port and path — no user, key
    /// or query reaches the row.
    @Test func addressDropsSecrets() throws {
        let store = AIProviderStore(database: try AppDatabase.makeEmpty(), keys: InMemoryPasswordStore())
        let provider = AIProvider(kind: .openAICompatible, name: "Proxy", address: " https://me:sk-live-9@api.example.com:8443/v1?key=sk-9#x ", model: "m")
        try store.save(provider, key: nil)
        #expect(try store.provider(id: provider.id)?.address == "https://api.example.com:8443/v1")
        #expect(AIProviderStore.normalizedAddress("http://192.168.1.10:11434") == "http://192.168.1.10:11434")
    }

    /// AI Search never reaches the cloud (FS-08.07 §5).
    @Test func onlyHomeServerServesAISearch() {
        #expect(AIProvider.Kind.allCases.filter(\.servesAISearch) == [.homeServer])
    }
}
