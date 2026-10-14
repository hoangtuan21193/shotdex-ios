import Foundation
import Testing
@testable import ShotDex

/// Answers requests from a closure, so the client is tested without a
/// network: what it sends, and what it makes of each answer.
final class AIStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var request = request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            request.httpBody = data
        }
        Self.requests.append(request)
        let (status, body) = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIStubProtocol.self]
        return URLSession(configuration: configuration)
    }
}

/// FS-08.07: the AI provider client and the two AI choices.
@Suite(.serialized) @MainActor struct AIProviderClientTests {
    private func json(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }

    /// AC-3: a home server at 127.0.0.1:11434 lists its two models over
    /// `/v1/models`, and Test works.
    @Test func listsModelsFromLocalServer() async throws {
        AIStubProtocol.requests = []
        AIStubProtocol.handler = { request in
            switch request.url?.path {
            case "/v1/models": (200, self.json(["data": [["id": "qwen3:14b"], ["id": "llama3.2:3b"]]]))
            case "/v1/chat/completions": (200, self.json(["choices": [["message": ["content": "Xin chào"]]]]))
            default: (404, Data())
            }
        }
        let client = AIProviderClient(session: AIStubProtocol.session())
        let models = try await client.models(kind: .homeServer, address: "127.0.0.1:11434", key: nil, name: "Mac Studio")
        #expect(models == ["llama3.2:3b", "qwen3:14b"])
        #expect(AIStubProtocol.requests.last?.url?.absoluteString == "http://127.0.0.1:11434/v1/models")

        let provider = AIProvider(kind: .homeServer, name: "Mac Studio", address: "http://127.0.0.1:11434", model: "qwen3:14b")
        let seconds = try await client.test(provider, key: nil, language: "Vietnamese")
        #expect(seconds >= 0)
        let sent = try #require(AIStubProtocol.requests.last)
        #expect(sent.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try #require(try JSONSerialization.jsonObject(with: sent.httpBody ?? Data()) as? [String: Any])
        #expect(body["model"] as? String == "qwen3:14b")
    }

    /// AC-4: a 401 reads as the key being rejected.
    @Test func rejectedKeySaysSo() async {
        AIStubProtocol.handler = { _ in (401, self.json(["error": ["message": "invalid x-api-key"]])) }
        let client = AIProviderClient(session: AIStubProtocol.session())
        let provider = AIProvider(kind: .claude, name: "Claude", model: "claude-sonnet-5-5")
        await #expect(throws: AIProviderClient.Failure.rejectedKey) {
            _ = try await client.test(provider, key: "sk-ant-test-7Qx2", language: "Vietnamese")
        }
        #expect(AIProviderClient.Failure.rejectedKey.errorDescription == "The service rejected the API key.")

        AIStubProtocol.handler = { _ in (400, self.json(["error": ["message": "model not found"]])) }
        await #expect(throws: AIProviderClient.Failure.service("model not found")) {
            _ = try await client.test(provider, key: "sk-ant-test-7Qx2", language: "Vietnamese")
        }
    }

    /// Claude goes to Anthropic's Messages API with its own headers.
    @Test func claudeUsesMessagesAPI() async throws {
        AIStubProtocol.requests = []
        AIStubProtocol.handler = { _ in (200, self.json(["content": [["type": "text", "text": "Xin chào"]]])) }
        let client = AIProviderClient(session: AIStubProtocol.session())
        let provider = AIProvider(kind: .claude, name: "Claude", model: "claude-sonnet-5-5")
        let answer = try await client.complete(provider, key: "sk-ant-test-7Qx2", system: "Translate.", prompt: "Hello")
        #expect(answer == "Xin chào")
        let sent = try #require(AIStubProtocol.requests.last)
        #expect(sent.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(sent.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test-7Qx2")
        #expect(sent.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == nil)
    }

    /// Every other kind speaks the OpenAI chat API at its own address.
    @Test func openAIKindsShareOneAPI() {
        #expect(AIProviderClient.baseURL(kind: .chatGPT, address: "")?.absoluteString == "https://api.openai.com/v1")
        #expect(AIProviderClient.baseURL(kind: .gemini, address: "")?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/openai")
        #expect(AIProviderClient.baseURL(kind: .homeServer, address: "192.168.1.10:1234/")?.absoluteString == "http://192.168.1.10:1234/v1")
        #expect(AIProviderClient.baseURL(kind: .openAICompatible, address: "https://llm.example.com/v1")?.absoluteString == "https://llm.example.com/v1")
        #expect(AIProviderClient.baseURL(kind: .homeServer, address: " ") == nil)
    }

    /// The key never reaches a log line.
    @Test func redactsAuthorization() {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer sk-live-secret", forHTTPHeaderField: "Authorization")
        request.setValue("sk-ant-secret", forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("subtitle text".utf8)
        let line = AIProviderClient.redacted(request)
        #expect(!line.contains("secret"))
        #expect(!line.contains("subtitle text"))
        #expect(line.contains("Authorization: <redacted>"))
        #expect(line.contains("POST https://api.openai.com/v1/chat/completions"))
    }

    /// AC-1, AC-5, AC-7 (logic): defaults, a deleted provider's row going
    /// back to its default, and AI Search never offering a cloud service.
    @Test func choices() {
        let claude = AIProvider(id: "c1", kind: .claude, name: "Claude", model: "m")
        let home = AIProvider(id: "h1", kind: .homeServer, name: "Mac Studio", address: "http://10.0.0.2:11434", model: "m")
        let simulator = AIChoice.OnDevice(appleTranslation: true, appleIntelligence: false)
        #expect(AIChoice.translation(stored: nil, providers: [], onDevice: simulator) == .askEachTime)
        #expect(AIChoice.search(stored: nil, providers: [], onDevice: simulator) == .off)
        #expect(AIChoice.search(stored: nil, providers: [], onDevice: .init(appleTranslation: true, appleIntelligence: true)) == .appleIntelligence)

        #expect(AIChoice.searchOptions(providers: [claude, home], onDevice: .init(appleTranslation: true, appleIntelligence: true))
            == [.appleIntelligence, .provider("h1"), .off])
        #expect(AIChoice.translationOptions(providers: [claude, home], onDevice: simulator)
            == [.askEachTime, .appleTranslation, .provider("c1"), .provider("h1")])

        #expect(AIChoice.translation(stored: "provider:c1", providers: [claude], onDevice: simulator) == .provider("c1"))
        #expect(AIChoice.translation(stored: "provider:c1", providers: [], onDevice: simulator) == .askEachTime)
        #expect(AIChoice.search(stored: "provider:c1", providers: [claude], onDevice: simulator) == .off)
        #expect(SettingsSummary.ai(translation: "Claude", search: "Apple Intelligence") == "Claude · Apple Intelligence")
        #expect(SettingsSummary.ai(translation: nil, search: nil) == "Not set up")
    }

    /// AI Search (FS-08.07 §5): a home server's JSON answer becomes the same rules Apple
    /// Intelligence's would.
    @Test func homeServerAnswerBecomesRules() async throws {
        AIStubProtocol.handler = { _ in
            let content = "```json\n{\"conditions\":[{\"field\":\"focal\",\"comparison\":\"is\",\"text\":\"\",\"value\":85,\"upperValue\":0}]}\n```"
            return (200, try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]]))
        }
        let home = AIProvider(kind: .homeServer, name: "Mac Studio", address: "http://127.0.0.1:11434", model: "qwen3:14b")
        let model = HomeServerSearchModel(provider: home, key: nil, client: AIProviderClient(session: AIStubProtocol.session()))
        let rules = try #require(await model.translate("sunset at 85mm", vocabulary: FilterSuggestionCatalog()))
        #expect(rules.count == 1)
        #expect(SearchModelPrompt.conditions(fromJSON: "no json here") == nil)
    }
}
