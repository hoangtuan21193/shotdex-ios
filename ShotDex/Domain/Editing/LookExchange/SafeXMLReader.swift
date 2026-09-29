import Foundation

/// A parsed XML element: qualified name, attributes, children, text.
struct SafeXMLElement: Equatable {
    var name: String
    var attributes: [String: String]
    var children: [SafeXMLElement]
    var text: String

    /// The part after the prefix: "crs:Exposure2012" → "Exposure2012".
    var localName: String { name.split(separator: ":").last.map(String.init) ?? name }
    var prefix: String? { name.contains(":") ? String(name.split(separator: ":")[0]) : nil }
}

/// XML read defensively (FS-03.14a §2): no DTD, no entities — the file is
/// scanned for `<!DOCTYPE` / `<!ENTITY` before the parser sees it, so XXE and
/// billion-laughs never start — and no deeper than 64 levels.
enum SafeXMLReader {
    static let maximumDepth = 64

    enum Failure: Error, Equatable {
        case forbiddenDeclaration
        case tooDeep
        case malformed
    }

    static func read(_ data: Data) throws(Failure) -> SafeXMLElement {
        if containsDeclaration(data) { throw .forbiddenDeclaration }
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        let builder = Builder()
        parser.delegate = builder
        let ok = parser.parse()
        if builder.isTooDeep { throw .tooDeep }
        guard ok, let root = builder.root else { throw .malformed }
        return root
    }

    /// `<!DOCTYPE` or `<!ENTITY`, any case, anywhere.
    private static func containsDeclaration(_ data: Data) -> Bool {
        let lowered = String(decoding: data, as: UTF8.self).lowercased()
        return lowered.contains("<!doctype") || lowered.contains("<!entity")
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: SafeXMLElement?
        var stack: [SafeXMLElement] = []
        var isTooDeep = false

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String] = [:]
        ) {
            guard stack.count < SafeXMLReader.maximumDepth else {
                isTooDeep = true
                parser.abortParsing()
                return
            }
            stack.append(SafeXMLElement(name: elementName, attributes: attributes, children: [], text: ""))
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard !stack.isEmpty else { return }
            stack[stack.count - 1].text += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?
        ) {
            guard var element = stack.popLast() else { return }
            element.text = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if stack.isEmpty {
                root = element
            } else {
                stack[stack.count - 1].children.append(element)
            }
        }

        func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
            nil
        }
    }
}
