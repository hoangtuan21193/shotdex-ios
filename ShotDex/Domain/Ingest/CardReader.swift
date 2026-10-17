import Foundation

/// A memory card as an import reads it (FS-20 §4–5): the files it lists and
/// their bytes, in chunks of at most 1 MB so a 2 GB clip never sits in
/// memory. A card reader in Files and a camera on the cable both read this
/// way; a test reads a `DCIM` folder in a temporary directory.
protocol CardReader: Sendable {
    /// The card's volume name: `EOS_DIGITAL`.
    var name: String { get }
    func list() async throws -> [CardFile]
    /// Hands `body` the file's bytes in order. Throws
    /// `IngestFailure.cardDisconnected` once the card is gone, and
    /// `IngestFailure.unreadable` when only this file fails.
    func read(_ path: String, chunkSize: Int, _ body: (Data) throws -> Void) async throws
}

/// Where an import writes a file and proves it (FS-20 §7.2): under
/// `<name>.shotdex-part`, read back and compared with the card's SHA-256,
/// only then given its real name — never over an existing file.
protocol IngestDestination: Sendable {
    func existingNames(in folder: String) async throws -> Set<String>
    func freeBytes() async -> Int64?
    func sweepLeftoverParts(in folder: String) async
    /// `produce` fills the part file and returns the SHA-256 of what it
    /// wrote; a different one read back throws `IngestFailure.checksumMismatch`.
    func writeVerified(name: String, in folder: String,
                       produce: @Sendable (URL) async throws -> String) async throws -> ExportWrittenFile
    /// Takes back a file this import wrote, when the rest of its photo
    /// failed: a photo is in the destination whole or not at all.
    func remove(_ path: String) async
}
