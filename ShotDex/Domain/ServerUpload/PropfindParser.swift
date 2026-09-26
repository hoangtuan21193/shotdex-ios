import CryptoKit
import Foundation

/// Reads a WebDAV `PROPFIND` multistatus body (RFC 4918 §9.1) into listing
/// entries (FS-15.05 §2). Namespace prefixes vary by server (`d:`, `D:`,
/// none), so elements are matched by local name.
enum PropfindParser {
    struct Item: Equatable, Sendable {
        /// The decoded path from `href`, without a trailing slash.
        let path: String
        let isCollection: Bool
        let size: Int64
        let modified: Date?
    }

    static func parse(_ data: Data) -> [Item] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }

    /// The entries of the folder at `folderPath` (a path as it appears in
    /// the hrefs, decoded): everything but the folder itself, by name.
    static func entries(_ items: [Item], inFolder folderPath: String) -> [RemoteEntry] {
        let folder = normalized(folderPath)
        return items.compactMap { item in
            let path = normalized(item.path)
            guard path != folder, let name = path.split(separator: "/").last.map(String.init) else { return nil }
            return RemoteEntry(name: name, isDirectory: item.isCollection, size: item.size, modified: item.modified)
        }
    }

    /// `href`s may be absolute URLs or paths, percent-encoded, with or
    /// without a trailing slash.
    static func normalized(_ href: String) -> String {
        var path = href
        if let url = URL(string: href), url.scheme != nil { path = url.path(percentEncoded: true) }
        path = path.removingPercentEncoding ?? path
        return path.split(separator: "/", omittingEmptySubsequences: true).joined(separator: "/")
    }

    static let httpDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    private final class Delegate: NSObject, XMLParserDelegate {
        var items: [Item] = []
        private var text = ""
        private var href: String?
        private var isCollection = false
        private var size: Int64 = 0
        private var modified: Date?
        private var inResponse = false

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            text = ""
            switch elementName.lowercased() {
            case "response":
                inResponse = true
                href = nil
                isCollection = false
                size = 0
                modified = nil
            case "collection":
                if inResponse { isCollection = true }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch elementName.lowercased() {
            case "href":
                if href == nil { href = value }
            case "getcontentlength":
                size = Int64(value) ?? 0
            case "getlastmodified":
                modified = PropfindParser.httpDate.date(from: value)
            case "response":
                if let href { items.append(Item(path: href, isCollection: isCollection, size: size, modified: modified)) }
                inResponse = false
            default:
                break
            }
            text = ""
        }
    }
}

/// Trust-on-first-use for a TLS certificate the system does not trust
/// (a NAS's self-signed one, FS-15.05 §4) — the same rule as SSH host keys.
enum TLSCertificateTrust {
    /// SHA-256 of the certificate's DER, in the colon-separated hex that
    /// `openssl x509 -fingerprint -sha256` and NAS admin pages print.
    static func fingerprint(ofCertificate der: Data) -> String {
        "SHA-256 " + SHA256.hash(data: der).map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}
