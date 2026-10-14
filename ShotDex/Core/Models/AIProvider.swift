import Foundation
import GRDB

/// A translation or AI Search service the user added (FS-08.07 §2). Apple
/// Translation and Apple Intelligence are built in and have no row. The key
/// lives in the Keychain under `id`, never in this row.
struct AIProvider: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        /// An OpenAI-style server on the home network (Ollama, LM Studio).
        case homeServer
        case claude
        case chatGPT
        case openRouter
        case grok
        case gemini
        /// Any other OpenAI-compatible `https://` service.
        case openAICompatible

        /// AI Search never goes to the cloud (FS-08.07 §5).
        var servesAISearch: Bool { self == .homeServer }
    }

    var id: String
    var kind: Kind
    var name: String
    /// Home server and OpenAI-compatible: the address typed in. Cloud
    /// services: empty (the client knows their address).
    var address: String
    var model: String
    var createdAt: Int

    init(
        id: String = UUID().uuidString,
        kind: Kind,
        name: String,
        address: String = "",
        model: String,
        createdAt: Int = Int(Date().timeIntervalSince1970)
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.address = address
        self.model = model
        self.createdAt = createdAt
    }
}

extension AIProvider: FetchableRecord, PersistableRecord {
    static let databaseTableName = "ai_providers"
}
