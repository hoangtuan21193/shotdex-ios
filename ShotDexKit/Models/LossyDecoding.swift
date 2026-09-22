import Foundation

/// An array that decodes one element at a time and **drops** the elements it
/// cannot read, instead of failing the whole array.
///
/// Swift's synthesized `Codable` fails closed: a single mask whose `kind` is a
/// string this build does not know throws out of `[PhotoMask]`, out of the
/// recipe, and every call site turns that into `nil` — which the editor reads
/// as "no edit at all". One unreadable mask wiped the crop, the colour, the
/// curve and every other mask on the photo; one unreadable preset wiped every
/// saved look. Losing the one element nobody can read is the honest failure;
/// losing everything next to it is not.
public struct LossyArray<Element: Decodable>: Decodable {
    public let elements: [Element]

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                // A failed decode does not advance an unkeyed container; read
                // the element as nothing so the loop moves past it.
                _ = try? container.decode(SkippedElement.self)
            }
        }
        self.elements = elements
    }
}

/// Consumes one element of an unkeyed container without reading it.
private struct SkippedElement: Decodable {
    init(from decoder: any Decoder) throws {}
}

public extension KeyedDecodingContainer {
    /// `decodeIfPresent` for an array, keeping every element that reads.
    func decodeLossyArrayIfPresent<Element: Decodable>(
        _ type: Element.Type,
        forKey key: Key
    ) throws -> [Element]? {
        try decodeIfPresent(LossyArray<Element>.self, forKey: key)?.elements
    }
}
