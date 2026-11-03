import Foundation

/// The random check on hashes another device sent (FS-19.07 §12.4): each
/// pass, for each sending device, this device reads again up to
/// `sampleSize` files whose hash from that device makes a photo match, and
/// one wrong hash is enough to stop trusting everything that device sent
/// until then.
enum SharedHashAudit {
    /// K, per sending device per pass (user 2026-11-03).
    static let sampleSize = 10

    /// The hash read here differs from the one the device sent. Hex in any
    /// case is one hash.
    static func isMismatch(sent: String, readHere: String) -> Bool {
        sent.lowercased() != readHere.lowercased()
    }
}
