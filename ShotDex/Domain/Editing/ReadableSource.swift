import Foundation
import ShotDexKit

/// Which file of a photo to work from when the system RAW decoder may not
/// read it (FS-03.04b §4). Generic over the option and what loading gives,
/// so the rule is tested without PhotoKit.
enum ReadableSource {
    /// Loads `preferred`. When that is the RAW of a RAW+JPEG pair and the
    /// decoder can't read it, loads the pair's rendered twin instead — Resize
    /// makes the copy from the JPEG rather than failing the photo (Q6). A
    /// RAW-only photo has no twin, so its error stands; any other error is
    /// not a decoder problem and stands too.
    static func load<Option, Loaded>(
        preferred: Option,
        among options: [Option],
        isRAW: (Option) -> Bool,
        load: (Option) async throws -> Loaded
    ) async throws -> Loaded {
        do {
            return try await load(preferred)
        } catch PhotoEditingError.unsupportedRAW where isRAW(preferred) {
            guard let twin = options.first(where: { !isRAW($0) }) else {
                throw PhotoEditingError.unsupportedRAW
            }
            return try await load(twin)
        }
    }

    /// The first item, in order, that loads — Resize's preview is the first
    /// photo of the batch it can read, not an error because the first one is
    /// a RAW the decoder can't open. Throws the last error when none loads.
    static func firstLoadable<Item, Loaded>(
        _ items: [Item],
        load: (Item) async throws -> Loaded
    ) async throws -> (item: Item, loaded: Loaded) {
        var lastError: Error = PhotoEditingError.missingSource
        for item in items {
            do {
                return (item, try await load(item))
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}
