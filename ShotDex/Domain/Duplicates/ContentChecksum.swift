import CryptoKit
import Foundation

/// Byte-identical copies (FS-06.06 §14.2, after Immich's SHA-1 on upload):
/// which photos are worth reading in full, and the streaming digest.
enum ContentChecksum {
    /// Photos that share their perceptual hash, pixel size **and** exact byte
    /// count with another — the only ones that can be the same bytes. Edited
    /// and Live photos never: their original is not what the user keeps.
    /// `missingOnly` leaves out photos already read; `retryingFailed` puts
    /// back the ones a read failed for (when the network may be used).
    static func candidates(_ photos: [HashedPhoto], missingOnly: Bool = false, retryingFailed: Bool = false) -> [HashedPhoto] {
        struct Key: Hashable { var hash: UInt64; var width: Int?; var height: Int?; var size: Int }
        var byKey: [Key: [HashedPhoto]] = [:]
        for photo in photos where !photo.isEditedOrLive {
            guard let size = photo.fileSize, size > 0 else { continue }
            byKey[Key(hash: photo.hash.bits, width: photo.width, height: photo.height, size: size), default: []].append(photo)
        }
        return byKey.values.filter { $0.count > 1 }.flatMap { $0 }
            .filter { photo in
                guard missingOnly, photo.contentChecksum == nil else { return !missingOnly }
                return !photo.checksumTried || retryingFailed
            }
    }

    /// SHA-256 fed one chunk at a time, so a 100 MB RAW is never held whole.
    struct Hasher {
        private var digest = SHA256()

        mutating func update(_ chunk: Data) { digest.update(data: chunk) }

        func finalize() -> String {
            digest.finalize().map { String(format: "%02x", $0) }.joined()
        }
    }
}
