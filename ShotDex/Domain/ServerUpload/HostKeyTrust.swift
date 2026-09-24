import CryptoKit
import Foundation

/// Trust-on-first-use for SFTP host keys (FS-15.01 §4).
enum HostKeyTrust {
    enum Verdict: Equatable, Sendable {
        case trusted
        /// Nothing saved yet: show the fingerprint and ask.
        case untrusted(fingerprint: String)
        /// Saved key and offered key differ: block, never ask to "trust
        /// anyway" in the same breath.
        case changed(fingerprint: String)
    }

    /// OpenSSH's form, the one `ssh-keygen -lf` prints: `SHA256:` and the
    /// unpadded base64 of the SHA-256 of the key's wire-format blob — so the
    /// user can compare it with what the server itself shows.
    static func fingerprint(ofKeyBlob blob: Data) -> String {
        let base64 = Data(SHA256.hash(data: blob)).base64EncodedString()
        return "SHA256:" + base64.trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    /// The same from an OpenSSH public key line (`ssh-ed25519 AAAA… comment`).
    static func fingerprint(ofOpenSSHKey line: String) -> String? {
        let parts = line.split(separator: " ")
        guard parts.count >= 2, let blob = Data(base64Encoded: String(parts[1])) else { return nil }
        return fingerprint(ofKeyBlob: blob)
    }

    static func evaluate(offered: String, saved: String?) -> Verdict {
        guard let saved else { return .untrusted(fingerprint: offered) }
        return saved == offered ? .trusted : .changed(fingerprint: offered)
    }
}
