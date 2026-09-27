import Foundation

/// How much room the server has where the browser is (FS-17.01 §2b).
struct StorageSpace: Equatable, Sendable {
    /// Nil when the server tells only what is free.
    let total: Int64?
    let free: Int64

    /// The footer's second line: "1.2 TB free of 4 TB", or "1.2 TB free".
    var footerText: String {
        let free = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
        guard let total else {
            return String(localized: "\(free) free", comment: "Server browser footer: free space, total unknown")
        }
        let totalText = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        return String(localized: "\(free) free of \(totalText)", comment: "Server browser footer: free space of the total")
    }
}

/// Reads each protocol's answer into a `StorageSpace` — pure, so every
/// reply shape is tested without a server.
enum StorageSpaceReading {
    /// SMB `FileFsSizeInformation` (MS-FSCC 2.5.8): allocation units, of
    /// which the free count is what this account may use.
    static func smb(totalUnits: UInt64, freeUnits: UInt64, sectorsPerUnit: UInt32, bytesPerSector: UInt32) -> StorageSpace? {
        let unit = UInt64(sectorsPerUnit) * UInt64(bytesPerSector)
        guard unit > 0 else { return nil }
        let (total, overflow) = totalUnits.multipliedReportingOverflow(by: unit)
        let (free, freeOverflow) = freeUnits.multipliedReportingOverflow(by: unit)
        guard !overflow, !freeOverflow, total <= UInt64(Int64.max) else { return nil }
        return StorageSpace(total: Int64(total), free: Int64(free))
    }

    /// `df -Pk` over SSH: the last line's 1024-blocks and Available,
    /// counted from the end so a filesystem name with spaces still reads.
    static func diskFree(_ output: String) -> StorageSpace? {
        guard let line = output.split(whereSeparator: \.isNewline).last(where: { !$0.hasPrefix("Filesystem") }) else { return nil }
        let fields = line.split(whereSeparator: \.isWhitespace)
        guard fields.count >= 6, fields[fields.count - 2].hasSuffix("%"),
              let blocks = Int64(fields[fields.count - 5]),
              let available = Int64(fields[fields.count - 3]) else { return nil }
        return StorageSpace(total: blocks * 1024, free: available * 1024)
    }

    /// A PROPFIND reply with RFC 4331 `quota-available-bytes` and
    /// `quota-used-bytes`; nil when the server keeps no quota.
    static func webdavQuota(_ data: Data) -> StorageSpace? {
        let reader = QuotaReader()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = reader
        parser.parse()
        guard let available = reader.available, available >= 0 else { return nil }
        return StorageSpace(total: reader.used.map { $0 + available }, free: available)
    }

    private final class QuotaReader: NSObject, XMLParserDelegate {
        var available: Int64?
        var used: Int64?
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            let value = Int64(text.trimmingCharacters(in: .whitespacesAndNewlines))
            switch elementName.lowercased() {
            case "quota-available-bytes": if available == nil { available = value }
            case "quota-used-bytes": if used == nil { used = value }
            default: break
            }
            text = ""
        }
    }
}
