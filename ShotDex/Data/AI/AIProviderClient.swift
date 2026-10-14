import Foundation
import os

/// Talks to an AI provider the user added (FS-08.07 §2): Anthropic's
/// Messages API for Claude, the OpenAI chat API for everything else —
/// ChatGPT, OpenRouter, Grok, Gemini's OpenAI endpoint, a home server
/// (Ollama, LM Studio) or any compatible service. Requests go straight from
/// the device with the user's key; the key is never logged.
struct AIProviderClient: Sendable {
    var session: URLSession = .shared

    enum Failure: LocalizedError, Equatable {
        case rejectedKey
        /// 429: too many requests just now.
        case rateLimited
        case unreachable(String)
        /// The service's own words.
        case service(String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .rejectedKey:
                String(localized: "The service rejected the API key.", comment: "AI provider error: 401/403")
            case .rateLimited:
                String(localized: "The service is busy. Try again in a minute.", comment: "AI provider error: 429")
            case .unreachable(let name):
                String(localized: "ShotDex couldn't reach \(name).", comment: "AI provider error: no connection, e.g. ShotDex couldn't reach Mac Studio.")
            case .service(let message):
                message
            case .badResponse:
                String(localized: "The service sent an answer ShotDex can't read.", comment: "AI provider error: unexpected response")
            }
        }
    }

    private static let log = Logger(subsystem: "com.hoangtuan.shotdex", category: "ai")

    /// The model a new provider of this kind starts with; the list the
    /// service returns can change it.
    static func defaultModel(for kind: AIProvider.Kind) -> String {
        switch kind {
        case .claude: "claude-sonnet-5-5"
        case .chatGPT: "gpt-5-mini"
        case .openRouter: "anthropic/claude-sonnet-5.5"
        case .grok: "grok-4"
        case .gemini: "gemini-2.5-flash"
        case .homeServer, .openAICompatible: ""
        }
    }

    /// Where the service lives, ending before `/models`, `/messages`.
    static func baseURL(kind: AIProvider.Kind, address: String) -> URL? {
        switch kind {
        case .claude: return URL(string: "https://api.anthropic.com/v1")
        case .chatGPT: return URL(string: "https://api.openai.com/v1")
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1")
        case .grok: return URL(string: "https://api.x.ai/v1")
        case .gemini: return URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")
        case .homeServer, .openAICompatible:
            var trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
            while trimmed.hasSuffix("/") { trimmed.removeLast() }
            guard !trimmed.isEmpty else { return nil }
            if !trimmed.contains("://") { trimmed = (kind == .homeServer ? "http://" : "https://") + trimmed }
            return URL(string: trimmed.hasSuffix("/v1") ? trimmed : trimmed + "/v1")
        }
    }

    /// The models the service offers, sorted.
    func models(kind: AIProvider.Kind, address: String, key: String?, name: String) async throws -> [String] {
        guard let base = Self.baseURL(kind: kind, address: address) else { throw Failure.unreachable(name) }
        var request = URLRequest(url: base.appending(path: "models"))
        request.timeoutInterval = 15
        authorize(&request, kind: kind, key: key)
        let data = try await send(request, name: name)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = (object["data"] ?? object["models"]) as? [[String: Any]] else { throw Failure.badResponse }
        let ids = list.compactMap { ($0["id"] ?? $0["name"]) as? String }
        return Array(Set(ids)).sorted()
    }

    /// One answer to `prompt`, with `system` as the instructions.
    func complete(_ provider: AIProvider, key: String?, system: String, prompt: String, timeout: TimeInterval = 60) async throws -> String {
        guard let base = Self.baseURL(kind: provider.kind, address: provider.address) else { throw Failure.unreachable(provider.name) }
        var request: URLRequest
        let body: [String: Any]
        if provider.kind == .claude {
            request = URLRequest(url: base.appending(path: "messages"))
            body = [
                "model": provider.model, "max_tokens": 4_096, "system": system,
                "messages": [["role": "user", "content": prompt]],
            ]
        } else {
            request = URLRequest(url: base.appending(path: "chat/completions"))
            body = [
                "model": provider.model,
                "messages": [["role": "system", "content": system], ["role": "user", "content": prompt]],
                "temperature": 0.2,
            ]
        }
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        authorize(&request, kind: provider.kind, key: key)
        let data = try await send(request, name: provider.name)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.badResponse }
        if provider.kind == .claude {
            let parts = (object["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String } ?? []
            guard !parts.isEmpty else { throw Failure.badResponse }
            return parts.joined()
        }
        guard let choice = (object["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any],
              let content = message["content"] as? String else { throw Failure.badResponse }
        return content
    }

    /// Test (§3): "Hello" into the device language; how long it took.
    func test(_ provider: AIProvider, key: String?, language: String) async throws -> TimeInterval {
        let started = Date()
        _ = try await complete(
            provider, key: key,
            system: "Translate the user's text into \(language). Reply with the translation only.",
            prompt: "Hello", timeout: 20
        )
        return Date().timeIntervalSince(started)
    }

    private func authorize(_ request: inout URLRequest, kind: AIProvider.Kind, key: String?) {
        guard let key, !key.isEmpty else { return }
        if kind == .claude {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
    }

    private func send(_ request: URLRequest, name: String) async throws -> Data {
        Self.log.debug("\(Self.redacted(request), privacy: .public)")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw Failure.unreachable(name)
        }
        guard let http = response as? HTTPURLResponse else { throw Failure.badResponse }
        switch http.statusCode {
        case 200..<300: return data
        case 401, 403: throw Failure.rejectedKey
        case 429: throw Failure.rateLimited
        default: throw Failure.service(Self.serviceMessage(data) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode).capitalized)
        }
    }

    /// `{"error":{"message":"…"}}` (OpenAI, Anthropic) or `{"error":"…"}`
    /// (Ollama).
    static func serviceMessage(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String { return message }
        if let message = object["error"] as? String { return message }
        return object["message"] as? String
    }

    /// The request as it can be logged: method, address, headers — with the
    /// key headers blanked and no body (subtitle text is the user's).
    static func redacted(_ request: URLRequest) -> String {
        let secret: Set<String> = ["authorization", "x-api-key", "api-key", "x-goog-api-key"]
        let headers = (request.allHTTPHeaderFields ?? [:])
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \(secret.contains($0.key.lowercased()) ? "<redacted>" : $0.value)" }
            .joined(separator: ", ")
        return "\(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "") [\(headers)]"
    }
}
