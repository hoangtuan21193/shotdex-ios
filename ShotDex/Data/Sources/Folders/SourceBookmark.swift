import Foundation

/// A folder source's bookmark (FS-19.01b §2). The sandboxed Mac app needs a
/// security-scoped bookmark to open the folder again after a relaunch — a
/// plain one resolves but cannot be read — so on macOS it is made and
/// resolved with `.withSecurityScope`. A bookmark kept before that is still
/// resolved the plain way; the next Grant Access… replaces it.
enum SourceBookmark {
    static func make(for url: URL) throws -> Data {
        #if os(macOS)
        try url.bookmarkData(options: .withSecurityScope)
        #else
        try url.bookmarkData()
        #endif
    }

    static func resolve(_ data: Data, isStale: inout Bool) throws -> URL {
        #if os(macOS)
        if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &isStale) {
            return url
        }
        #endif
        return try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale)
    }
}
