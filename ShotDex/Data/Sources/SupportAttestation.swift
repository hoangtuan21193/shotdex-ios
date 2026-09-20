import CryptoKit
import DeviceCheck
import Foundation

/// Proves to the support backend that a request came from ShotDex running on a
/// real Apple device.
///
/// There is no account and no API key. A key shipped inside an app bundle is a
/// public key in every sense that matters, so the backend accepts only App
/// Attest assertions, and the attested key id doubles as the anonymous install
/// identity — enough to thread replies and hold a vote to one per install,
/// carrying no personal data at all. Deleting the app drops the key, which
/// unlinks every report that came before.
actor SupportAttestation {
    /// Every assertion advances a counter inside the Secure Enclave and the
    /// server rejects anything that does not move it forward, so two requests
    /// signed at once would arrive out of order and the second would fail.
    /// Being an actor is what serializes them; do not sign off-actor.
    private let service = DCAppAttestService.shared
    private let origin: URL
    private let session: URLSession
    private let defaults: UserDefaults
    private var cachedKeyID: String?

    private static let keyIDDefaultsKey = "support.attest.keyID"

    init(origin: URL, session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.origin = origin
        self.session = session
        self.defaults = defaults
    }

    /// True where App Attest cannot run at all — the simulator, and any device
    /// Apple has not enabled it on. Callers fall back to the debug bypass.
    nonisolated var isSupported: Bool { DCAppAttestService.shared.isSupported }

    /// Adds the three headers the backend checks. The canonical string is the
    /// contract with the Worker: method, path, timestamp and the hash of the
    /// exact body bytes, joined by pipes. One byte of drift here and every
    /// request comes back 401.
    func sign(_ request: inout URLRequest) async throws {
        let keyID = try await registeredKeyID()
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let body = request.httpBody ?? Data()
        let bodyHash = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        let path = request.url?.path ?? "/"
        let method = request.httpMethod?.uppercased() ?? "GET"
        let clientData = "v1|\(method)|\(path)|\(timestamp)|\(bodyHash)"

        let assertion = try await service.generateAssertion(
            keyID,
            clientDataHash: Data(SHA256.hash(data: Data(clientData.utf8)))
        )

        request.setValue(keyID, forHTTPHeaderField: "X-Attest-Key-Id")
        request.setValue(assertion.base64EncodedString(), forHTTPHeaderField: "X-Attest-Assertion")
        request.setValue(timestamp, forHTTPHeaderField: "X-Attest-Timestamp")
    }

    /// The attested key, generating and registering one the first time.
    private func registeredKeyID() async throws -> String {
        if let cachedKeyID { return cachedKeyID }
        if let stored = defaults.string(forKey: Self.keyIDDefaultsKey) {
            cachedKeyID = stored
            return stored
        }
        guard service.isSupported else { throw SupportError.attestationUnavailable }

        let keyID = try await service.generateKey()
        let challenge = try await fetchChallenge()
        let attestation = try await service.attestKey(
            keyID,
            clientDataHash: Data(SHA256.hash(data: Data(challenge.utf8)))
        )
        try await register(keyID: keyID, attestation: attestation, challenge: challenge)

        // Stored only after the server accepted it: a key the backend never saw
        // would fail every assertion, with nothing to retry from.
        defaults.set(keyID, forKey: Self.keyIDDefaultsKey)
        cachedKeyID = keyID
        return keyID
    }

    private func fetchChallenge() async throws -> String {
        var request = URLRequest(url: origin.appending(path: "/v1/attest/challenge"))
        request.httpMethod = "POST"
        let (data, response) = try await session.data(for: request)
        try Self.checkStatus(response)
        struct Payload: Decodable { let challenge: String }
        return try JSONDecoder().decode(Payload.self, from: data).challenge
    }

    private func register(keyID: String, attestation: Data, challenge: String) async throws {
        struct Body: Encodable {
            let keyId: String
            let attestation: String
            let challenge: String
        }
        var request = URLRequest(url: origin.appending(path: "/v1/attest/register"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            Body(keyId: keyID, attestation: attestation.base64EncodedString(), challenge: challenge)
        )
        let (_, response) = try await session.data(for: request)
        try Self.checkStatus(response)
    }

    private static func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw SupportError.network }
        guard (200..<300).contains(http.statusCode) else {
            throw http.statusCode == 429 ? SupportError.rateLimited : SupportError.server(http.statusCode)
        }
    }
}
