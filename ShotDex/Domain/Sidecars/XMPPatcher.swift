import Foundation

/// What ShotDex changes in a sidecar (FS-19.02 §5): the standard rating,
/// keywords, title and caption, and its own namespace. Everything else in
/// the file is someone else's — Lightroom's develop settings, Photo
/// Mechanic's fields — and stays as it is, byte for byte.
struct XMPPatch: Equatable, Sendable {
    enum Field<Value: Equatable & Sendable>: Equatable, Sendable {
        case keep
        case set(Value)
        case remove
    }

    /// `xmp:Rating`: 0–5, or −1 for Reject.
    var rating: Field<Int> = .keep
    /// `dc:subject`. Setting an empty list removes it.
    var keywords: Field<[String]> = .keep
    /// `dc:title`, the default-language entry.
    var title: Field<String> = .keep
    /// `dc:description`, the default-language entry.
    var caption: Field<String> = .keep
    /// `dc:creator`, one name (card import presets, FS-20 §6).
    var creator: Field<String> = .keep
    /// `dc:rights`, the default-language entry.
    var rights: Field<String> = .keep
    /// `xmp:CreateDate`, ISO 8601.
    var createDate: Field<String> = .keep
    /// Simple properties in ShotDex's namespace, by local name (`Rating`,
    /// `Flag`, `Favorite`, `Recipe`) — fields other apps skip.
    var shotdex: [String: Field<String>] = [:]
}

/// Applies an `XMPPatch` to the text of a sidecar (K3). A text patch, not a
/// parse and re-serialize: a serializer reorders attributes, rewraps lines
/// and drops what it does not understand, and the file is shared with
/// apps that read it byte for byte. Only the spans of the properties being
/// changed are touched; a property that is not there yet goes into the
/// first `rdf:Description`.
enum XMPPatcher {
    static let xmpNamespace = "http://ns.adobe.com/xap/1.0/"
    static let dublinCoreNamespace = "http://purl.org/dc/elements/1.1/"
    static let shotdexNamespace = "https://shotdex.app/ns/xmp/1.0/"

    /// The sidecar written beside a photo that had none.
    static let emptyPacket = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="ShotDex">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about="">
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>

        """

    static func apply(_ patch: XMPPatch, to xmp: String?) -> String {
        var text = xmp ?? emptyPacket
        switch patch.rating {
        case .keep: break
        case .set(let stars): setSimple(&text, namespace: xmpNamespace, prefix: "xmp", name: "Rating", value: String(stars))
        case .remove: remove(&text, namespace: xmpNamespace, name: "Rating")
        }
        switch patch.keywords {
        case .keep: break
        case .set(let keywords) where !keywords.isEmpty:
            setElement(&text, namespace: dublinCoreNamespace, prefix: "dc", name: "subject") { prefix, indent in
                container("rdf:Bag", items: keywords.map { "<rdf:li>\(escaped($0))</rdf:li>" }, element: "\(prefix):subject", indent: indent)
            }
        case .set, .remove: remove(&text, namespace: dublinCoreNamespace, name: "subject")
        }
        switch patch.creator {
        case .keep: break
        case .set(let name):
            setElement(&text, namespace: dublinCoreNamespace, prefix: "dc", name: "creator") { prefix, indent in
                container("rdf:Seq", items: ["<rdf:li>\(escaped(name))</rdf:li>"], element: "\(prefix):creator", indent: indent)
            }
        case .remove: remove(&text, namespace: dublinCoreNamespace, name: "creator")
        }
        switch patch.createDate {
        case .keep: break
        case .set(let date): setSimple(&text, namespace: xmpNamespace, prefix: "xmp", name: "CreateDate", value: date)
        case .remove: remove(&text, namespace: xmpNamespace, name: "CreateDate")
        }
        for (name, field) in [("title", patch.title), ("description", patch.caption), ("rights", patch.rights)] {
            switch field {
            case .keep: break
            case .set(let value):
                setElement(&text, namespace: dublinCoreNamespace, prefix: "dc", name: name) { prefix, indent in
                    container("rdf:Alt", items: ["<rdf:li xml:lang=\"x-default\">\(escaped(value))</rdf:li>"],
                              element: "\(prefix):\(name)", indent: indent)
                }
            case .remove: remove(&text, namespace: dublinCoreNamespace, name: name)
            }
        }
        for (name, field) in patch.shotdex.sorted(by: { $0.key < $1.key }) {
            switch field {
            case .keep: break
            case .set(let value): setSimple(&text, namespace: shotdexNamespace, prefix: "shotdex", name: name, value: value)
            case .remove: remove(&text, namespace: shotdexNamespace, name: name)
            }
        }
        return text
    }

    // MARK: Properties

    /// A simple value, in whichever form the file already uses: the
    /// attribute's value or the element's text is replaced where it stands;
    /// a new one is an attribute of the first `rdf:Description`.
    private static func setSimple(_ text: inout String, namespace: String, prefix preferred: String, name: String, value: String) {
        let prefix = ensurePrefix(&text, namespace: namespace, preferred: preferred)
        let qualified = NSRegularExpression.escapedPattern(for: "\(prefix):\(name)")
        if let match = firstMatch(#"\s\#(qualified)\s*=\s*(["'])(.*?)\1"#, in: text) {
            replace(&text, range: match.range(at: 2), with: escaped(value))
        } else if let match = firstMatch(#"<\#(qualified)(?:\s[^>]*)?>(.*?)</\#(qualified)>"#, in: text, dotAll: true) {
            replace(&text, range: match.range(at: 1), with: escaped(value))
        } else if let tag = firstDescriptionTag(in: text) {
            let indent = attributeIndent(in: text, tag: tag.range)
            replace(&text, range: NSRange(location: tag.closeLocation, length: 0),
                    with: "\n\(indent)\(prefix):\(name)=\"\(escaped(value))\"")
        }
    }

    /// A structured value (a bag or an alternative) is always written as an
    /// element: the old element is replaced in place, or a new one goes in
    /// last in the first `rdf:Description`.
    private static func setElement(_ text: inout String, namespace: String, prefix preferred: String, name: String,
                                   element: (_ prefix: String, _ indent: String) -> String) {
        let prefix = ensurePrefix(&text, namespace: namespace, preferred: preferred)
        let qualified = NSRegularExpression.escapedPattern(for: "\(prefix):\(name)")
        if let match = firstMatch(#"<\#(qualified)(?:\s[^>]*)?(?:/>|>.*?</\#(qualified)>)"#, in: text, dotAll: true) {
            replace(&text, range: match.range, with: element(prefix, lineIndent(in: text, at: match.range.location)))
            return
        }
        guard let tag = firstDescriptionTag(in: text) else { return }
        if tag.isSelfClosing {
            // `<rdf:Description … />` opens up to hold an element.
            let indent = lineIndent(in: text, at: tag.range.location)
            let closing = NSRange(location: tag.closeLocation, length: tag.range.location + tag.range.length - tag.closeLocation)
            replace(&text, range: closing, with: ">\n\(indent) \(element(prefix, indent + " "))\n\(indent)</rdf:Description>")
            return
        }
        let ns = text as NSString
        let close = ns.range(of: "</rdf:Description>", range: NSRange(location: tag.range.location + tag.range.length,
                                                                      length: ns.length - tag.range.location - tag.range.length))
        guard close.location != NSNotFound else { return }
        let lineStart = ns.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: close.location)).location
        let start = lineStart == NSNotFound ? 0 : lineStart + 1
        let leading = ns.substring(with: NSRange(location: start, length: close.location - start))
        if leading.allSatisfy({ $0 == " " || $0 == "\t" }) {
            replace(&text, range: NSRange(location: start, length: 0), with: "\(leading) \(element(prefix, leading + " "))\n")
        } else {
            replace(&text, range: NSRange(location: close.location, length: 0), with: element(prefix, leading) + "\n")
        }
    }

    /// Takes a property out in either form, with the whitespace before it.
    private static func remove(_ text: inout String, namespace: String, name: String) {
        guard let prefix = declaredPrefix(of: namespace, in: text) else { return }
        let qualified = NSRegularExpression.escapedPattern(for: "\(prefix):\(name)")
        while let match = firstMatch(#"\s+\#(qualified)\s*=\s*(["']).*?\1"#, in: text) {
            replace(&text, range: match.range, with: "")
        }
        while let match = firstMatch(#"\n?[ \t]*<\#(qualified)(?:\s[^>]*)?(?:/>|>.*?</\#(qualified)>)"#, in: text, dotAll: true) {
            replace(&text, range: match.range, with: "")
        }
    }

    // MARK: Namespaces

    private static func declaredPrefix(of namespace: String, in text: String) -> String? {
        let uri = NSRegularExpression.escapedPattern(for: namespace)
        guard let match = firstMatch(#"xmlns:([A-Za-z_][\w.-]*)\s*=\s*["']\#(uri)["']"#, in: text) else { return nil }
        return (text as NSString).substring(with: match.range(at: 1))
    }

    /// The prefix the file binds `namespace` to, declaring `preferred` on the
    /// first `rdf:Description` when it binds none.
    private static func ensurePrefix(_ text: inout String, namespace: String, preferred: String) -> String {
        if let prefix = declaredPrefix(of: namespace, in: text) { return prefix }
        if let tag = firstDescriptionTag(in: text) {
            let indent = attributeIndent(in: text, tag: tag.range)
            replace(&text, range: NSRange(location: tag.closeLocation, length: 0),
                    with: "\n\(indent)xmlns:\(preferred)=\"\(namespace)\"")
        }
        return preferred
    }

    // MARK: Text

    private struct DescriptionTag {
        let range: NSRange
        /// Where `>` or `/>` begins.
        let closeLocation: Int
        let isSelfClosing: Bool
    }

    private static func firstDescriptionTag(in text: String) -> DescriptionTag? {
        guard let match = firstMatch(#"<rdf:Description\b(?:[^>"']|"[^"]*"|'[^']*')*?(/?)>"#, in: text) else { return nil }
        let slash = match.range(at: 1)
        let isSelfClosing = slash.length > 0
        let closeLocation = isSelfClosing ? slash.location : match.range.location + match.range.length - 1
        return DescriptionTag(range: match.range, closeLocation: closeLocation, isSelfClosing: isSelfClosing)
    }

    /// Indentation for a new attribute: the line of the tag's last attribute
    /// when the tag spans lines, else the tag's own line plus four.
    private static func attributeIndent(in text: String, tag: NSRange) -> String {
        let body = (text as NSString).substring(with: tag)
        if let lastBreak = body.range(of: "\n", options: .backwards) {
            return String(body[lastBreak.upperBound...].prefix { $0 == " " || $0 == "\t" })
        }
        return lineIndent(in: text, at: tag.location) + "    "
    }

    private static func lineIndent(in text: String, at location: Int) -> String {
        let ns = text as NSString
        let lineStart = ns.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: location)).location
        let start = lineStart == NSNotFound ? 0 : lineStart + 1
        return String(ns.substring(with: NSRange(location: start, length: location - start)).prefix { $0 == " " || $0 == "\t" })
    }

    private static func container(_ kind: String, items: [String], element: String, indent: String) -> String {
        ([ "<\(element)>", " <\(kind)>" ] + items.map { "  \($0)" } + [ " </\(kind)>", "</\(element)>" ])
            .enumerated()
            .map { $0.offset == 0 ? $0.element : indent + $0.element }
            .joined(separator: "\n")
    }

    static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func firstMatch(_ pattern: String, in text: String, dotAll: Bool = false) -> NSTextCheckingResult? {
        let regex = try? NSRegularExpression(pattern: pattern, options: dotAll ? [.dotMatchesLineSeparators] : [])
        return regex?.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    private static func replace(_ text: inout String, range: NSRange, with replacement: String) {
        text = (text as NSString).replacingCharacters(in: range, with: replacement)
    }
}
