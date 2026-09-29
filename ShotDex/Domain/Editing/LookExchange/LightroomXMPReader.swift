import Foundation

/// What a Lightroom preset says, as read from its `crs:` settings: plain
/// values by tag, `rdf:Seq` lists (tone curves, Point Colors) by tag, and the
/// names of the nested structures it carries (Look, masks, retouch).
struct LightroomSettings: Equatable {
    /// `crs:Name`, when the preset has one.
    var name: String?
    /// Plain settings: "Exposure2012" → "+0.50".
    var values: [String: String] = [:]
    /// Lists: "ToneCurvePV2012" → ["0, 0", "128, 140", "255, 255"].
    var lists: [String: [String]] = [:]
    /// Nested structures present, by tag: "Look", "MaskGroupBasedCorrections".
    var structures: Set<String> = []
    /// The creative/camera profile's `Look` structure, flattened one level:
    /// "Name", "Amount"; "Parameters" present when it carries a table.
    var look: [String: String] = [:]
}

/// Reads a Lightroom `.xmp` preset (FS-03.14a §1) through `SafeXMLReader`.
enum LightroomXMPReader {
    static let crsNamespace = "http://ns.adobe.com/camera-raw-settings/1.0/"

    enum Failure: Error, Equatable {
        /// The XML does not parse, is too deep or declares a DTD.
        case notValidXMP
        /// Parsed, but carries no `crs:` setting — a sidecar, not a preset.
        case noLightroomSettings

        var message: String {
            switch self {
            case .notValidXMP: "The file is not valid XMP. Try exporting the preset from Lightroom again."
            case .noLightroomSettings: "This XMP has no Lightroom edit settings"
            }
        }
    }

    static func read(_ data: Data) throws(Failure) -> LightroomSettings {
        let root: SafeXMLElement
        do {
            root = try SafeXMLReader.read(data)
        } catch {
            throw .notValidXMP
        }
        let prefixes = crsPrefixes(in: root)
        guard !prefixes.isEmpty else { throw .noLightroomSettings }
        var settings = LightroomSettings()
        collect(root, prefixes: prefixes, into: &settings)
        guard settings.name != nil || !settings.values.isEmpty || !settings.lists.isEmpty || !settings.structures.isEmpty
        else { throw .noLightroomSettings }
        return settings
    }

    /// Every prefix bound to the `crs:` namespace anywhere in the document.
    private static func crsPrefixes(in element: SafeXMLElement) -> Set<String> {
        var found: Set<String> = []
        for (key, value) in element.attributes where key.hasPrefix("xmlns:") && value == crsNamespace {
            found.insert(String(key.dropFirst("xmlns:".count)))
        }
        for child in element.children { found.formUnion(crsPrefixes(in: child)) }
        return found
    }

    private static func collect(_ element: SafeXMLElement, prefixes: Set<String>, into settings: inout LightroomSettings) {
        // Settings written as attributes of an rdf:Description.
        for (key, value) in element.attributes {
            let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, prefixes.contains(parts[0]) else { continue }
            if parts[1] == "Name" { settings.name = value } else { settings.values[parts[1]] = value }
        }
        for child in element.children {
            guard let prefix = child.prefix, prefixes.contains(prefix) else {
                collect(child, prefixes: prefixes, into: &settings)
                continue
            }
            let tag = child.localName
            let container = child.children.first { ["rdf:Seq", "rdf:Bag", "rdf:Alt"].contains($0.name) }
            if tag == "Name" {
                // Lightroom writes the name as an rdf:Alt of languages.
                settings.name = container?.children.first?.text ?? (child.text.isEmpty ? nil : child.text)
            } else if let container, container.children.allSatisfy({ $0.children.isEmpty && $0.attributes.filter { !$0.key.hasPrefix("xml:") }.isEmpty }) {
                settings.lists[tag] = container.children.map(\.text)
            } else if container != nil || child.children.contains(where: { $0.name == "rdf:Description" }) || child.attributes.contains(where: { key, _ in key.split(separator: ":").first.map { prefixes.contains(String($0)) } ?? false }) {
                settings.structures.insert(tag)
                if tag == "Look" { settings.look = lookFields(child, prefixes: prefixes) }
            } else {
                settings.values[tag] = child.text
            }
        }
    }

    /// The `Look` structure's own fields, whether written as attributes or
    /// child elements; "Parameters" when a nested table is there.
    private static func lookFields(_ element: SafeXMLElement, prefixes: Set<String>) -> [String: String] {
        var fields: [String: String] = [:]
        func visit(_ node: SafeXMLElement) {
            for (key, value) in node.attributes {
                let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
                if parts.count == 2, prefixes.contains(parts[0]) { fields[parts[1]] = value }
            }
            for child in node.children {
                if let prefix = child.prefix, prefixes.contains(prefix) {
                    if child.localName == "Parameters" { fields["Parameters"] = "present" }
                    else if child.children.isEmpty { fields[child.localName] = child.text }
                    else { visit(child) }
                } else {
                    visit(child)
                }
            }
        }
        visit(element)
        return fields
    }
}
