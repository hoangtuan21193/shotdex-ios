import Foundation
import UIKit

/// What went wrong, in words a photographer can act on.
enum SupportError: LocalizedError {
    case attestationUnavailable
    case network
    case rateLimited
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .attestationUnavailable:
            String(localized: "This device cannot reach support.", comment: "Support error: App Attest is unavailable")
        case .network:
            String(localized: "No connection to support.", comment: "Support error: the request never reached the server")
        case .rateLimited:
            String(localized: "Too many messages for now.", comment: "Support error: rate limited")
        case .server:
            String(localized: "Support is not answering.", comment: "Support error: the server returned a failure")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .attestationUnavailable:
            String(localized: "Support needs a real iPhone or iPad. Email is the alternative for now.", comment: "Support error recovery")
        case .network:
            String(localized: "Check your connection and send it again. Nothing was lost.", comment: "Support error recovery")
        case .rateLimited:
            String(localized: "Try again in an hour.", comment: "Support error recovery")
        case .server:
            String(localized: "Try again in a few minutes.", comment: "Support error recovery")
        }
    }
}

enum SupportTicketKind: String, Codable, CaseIterable, Sendable {
    case bug
    case feature
}

/// Server-side lifecycle. Unknown values decode to `.open` so a newer backend
/// never breaks an older build.
enum SupportTicketStatus: String, Codable, Sendable {
    case open
    case triaged
    case planned
    case inProgress = "in_progress"
    case shipped
    case declined
    case duplicate

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SupportTicketStatus(rawValue: raw) ?? .open
    }
}

struct SupportMessage: Decodable, Identifiable, Sendable {
    enum Author: String, Decodable, Sendable {
        case user
        case team
    }

    let id: String
    let author: Author
    let body: String
    let createdAt: Date
}

struct SupportTicket: Decodable, Identifiable, Sendable {
    let id: String
    let kind: SupportTicketKind
    let title: String
    let body: String
    let status: SupportTicketStatus
    let votes: Int
    let createdAt: Date
    let updatedAt: Date
    let unread: Int
    let messages: [SupportMessage]
}

/// One public feature request, as the roadmap shows it. The reporter's own text
/// is never part of this — only the title they gave it.
struct SupportRoadmapItem: Decodable, Identifiable, Sendable {
    let id: String
    let kind: SupportTicketKind
    let title: String
    let status: SupportTicketStatus
    let votes: Int
}

/// What a bug report carries besides the words. Deliberately coarse: none of it
/// identifies a person or a photo.
struct SupportDiagnostics: Encodable, Sendable {
    let appVersion: String
    let buildNumber: String
    let osVersion: String
    let deviceModel: String
    let locale: String
    let libraryCount: Int?

    /// - Parameter libraryCount: blurred to two significant figures before it
    ///   is sent — 55,213 becomes 55,000 — because the exact size of someone's
    ///   library is a fingerprint, and "about 55,000" answers every question a
    ///   bug report needs it for. Small libraries keep their number: rounding
    ///   nine photos to the nearest thousand would report zero.
    @MainActor
    init(libraryCount: Int?) {
        let bundle = Bundle.main
        appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        osVersion = UIDevice.current.systemVersion
        deviceModel = Self.hardwareModel
        locale = Locale.current.identifier
        self.libraryCount = libraryCount.map(Self.blurred)
    }

    /// Two significant figures, so the count stays useful and stops being a
    /// way to recognise one particular library.
    static func blurred(_ count: Int) -> Int {
        guard count >= 100 else { return count }
        var magnitude = 1
        var remaining = count / 100
        while remaining > 0 {
            magnitude *= 10
            remaining /= 10
        }
        return (count + magnitude / 2) / magnitude * magnitude
    }

    /// `iPhone17,1` rather than "iPhone", which is all `UIDevice` will say. On a
    /// simulator `uname` answers the Mac's architecture, so the simulated model
    /// is read from the environment instead — otherwise every report from a
    /// development build claims to come from an "arm64".
    private static var hardwareModel: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) (Simulator)"
        }
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

/// The support portal's client: bug reports, feature requests, the replies that
/// come back, and the public roadmap.
///
/// Every write is signed by `SupportAttestation`, which is what lets the backend
/// stay anonymous — no account, no email, no password to lose.
actor SupportService {
    private let origin: URL
    private let attestation: SupportAttestation
    private let session: URLSession
    private let decoder: JSONDecoder

    /// Set in a Debug build to reach the API from the simulator, where App
    /// Attest does not exist. The header only works where the server has the
    /// matching secret, so it cannot be turned on from outside.
    private let developmentBypassToken: String?

    init(origin: URL = SupportService.defaultOrigin, session: URLSession = .shared) {
        self.origin = origin
        self.attestation = SupportAttestation(origin: origin, session: session)
        self.session = session
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        #if DEBUG
        // Read from the environment, never from the bundle: a token compiled
        // into Info.plist ships to everyone. Xcode schemes set it directly;
        // `simctl launch` passes it as SIMCTL_CHILD_SUPPORT_DEV_BYPASS_TOKEN.
        self.developmentBypassToken = ProcessInfo.processInfo.environment["SUPPORT_DEV_BYPASS_TOKEN"]
        #else
        self.developmentBypassToken = nil
        #endif
    }

    /// The live API, or whatever `SUPPORT_API_ORIGIN` points at in a Debug run,
    /// which is how a simulator talks to a local `wrangler dev`.
    static var defaultOrigin: URL {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["SUPPORT_API_ORIGIN"],
           let url = URL(string: override) {
            return url
        }
        #endif
        return URL(string: "https://api.shotdex.app")!
    }

    // MARK: Reading

    func tickets() async throws -> [SupportTicket] {
        struct Payload: Decodable { let tickets: [SupportTicket] }
        let data = try await send(makeRequest("/v1/tickets/mine", method: "GET"), signed: true)
        return try decoder.decode(Payload.self, from: data).tickets
    }

    /// Public and unsigned: the roadmap is the one thing here a browser can also
    /// read, and asking the Secure Enclave to sign a public GET buys nothing.
    func roadmap() async throws -> [SupportRoadmapItem] {
        struct Payload: Decodable { let items: [SupportRoadmapItem] }
        let data = try await send(makeRequest("/v1/public/roadmap", method: "GET"), signed: false)
        return try decoder.decode(Payload.self, from: data).items
    }

    // MARK: Writing

    @discardableResult
    func createTicket(
        kind: SupportTicketKind,
        title: String,
        body: String,
        diagnostics: SupportDiagnostics,
        logs: String?
    ) async throws -> String {
        struct Body: Encodable {
            let kind: SupportTicketKind
            let title: String
            let body: String
            let diagnostics: SupportDiagnostics
            let logs: String?
        }
        struct Created: Decodable { let id: String }

        var request = makeRequest("/v1/tickets", method: "POST")
        request.httpBody = try JSONEncoder().encode(
            Body(kind: kind, title: title, body: body, diagnostics: diagnostics, logs: logs)
        )
        let data = try await send(request, signed: true)
        return try decoder.decode(Created.self, from: data).id
    }

    func reply(to ticketID: String, body: String) async throws {
        struct Body: Encodable { let body: String }
        var request = makeRequest("/v1/tickets/\(ticketID)/messages", method: "POST")
        request.httpBody = try JSONEncoder().encode(Body(body: body))
        _ = try await send(request, signed: true)
    }

    func markRead(ticketID: String) async throws {
        _ = try await send(makeRequest("/v1/tickets/\(ticketID)/read", method: "POST"), signed: true)
    }

    /// One vote per install, enforced by the backend's primary key rather than
    /// by trusting the app.
    @discardableResult
    func setVote(_ isVoted: Bool, ticketID: String) async throws -> Int {
        struct Payload: Decodable { let votes: Int }
        let request = makeRequest("/v1/tickets/\(ticketID)/vote", method: isVoted ? "POST" : "DELETE")
        let data = try await send(request, signed: true)
        return try decoder.decode(Payload.self, from: data).votes
    }

    // MARK: Plumbing

    private func makeRequest(_ path: String, method: String) -> URLRequest {
        var request = URLRequest(url: origin.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func send(_ request: URLRequest, signed: Bool) async throws -> Data {
        var request = request
        if signed {
            if let developmentBypassToken, !attestation.isSupported {
                request.setValue(developmentBypassToken, forHTTPHeaderField: "X-Dev-Bypass")
                request.setValue(Self.simulatorInstallID, forHTTPHeaderField: "X-Dev-Install")
            } else {
                try await attestation.sign(&request)
            }
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SupportError.network
        }
        guard let http = response as? HTTPURLResponse else { throw SupportError.network }
        guard (200..<300).contains(http.statusCode) else {
            throw http.statusCode == 429 ? SupportError.rateLimited : SupportError.server(http.statusCode)
        }
        return data
    }

    /// Stable for the life of an install, like the attested key it stands in for.
    private static let simulatorInstallID: String = {
        let key = "support.dev.installID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }()
}
