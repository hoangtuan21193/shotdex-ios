import Foundation

/// What a model is told to turn a search into conditions (FS-01.03 §4): the
/// fields and comparisons it may use, and the library's own camera, lens
/// and place names so it writes back names that exist. Shared by Apple
/// Intelligence and a home server — never sent to a cloud service
/// (FS-08.07 §5: the place names are where the user has been).
enum SearchModelPrompt {
    static let vocabularyLimit = 40

    static func instructions(vocabulary: FilterSuggestionCatalog) -> String {
        var lines = [
            """
            You convert a photographer's search request into structured conditions.
            The request may be in English or Vietnamese.

            Rules:
            - Use only these fields: place, camera, brand, lens, iso, aperture,
              shutter, focal, filename, date, favorite, filetype, sensor.
            - Use only these comparisons: is, contains, not, greater, less, range,
              before, after, lastdays.
            - aperture is an f-number (1.2, 5.6). shutter is in seconds, so a
              "faster" shutter is a smaller number: "faster than 1/500" is
              shutter less than 0.002.
            - date values are Unix timestamps in seconds, except with lastdays,
              where the value is a number of days.
            - Return no conditions at all if the request names none. Never invent
              a condition the request does not state.
            """
        ]
        func section(_ title: String, _ values: [String]) {
            let sample = values.prefix(vocabularyLimit)
            guard !sample.isEmpty else { return }
            lines.append("Known \(title): \(sample.joined(separator: ", ")).")
        }
        section("places", vocabulary.places)
        section("cameras", vocabulary.bodies)
        section("lenses", vocabulary.lenses)
        return lines.joined(separator: "\n\n")
    }

    static func prompt(for query: String) -> String {
        """
        Photo search request: "\(query)"
        List the conditions it asks for. Omit anything it does not say.
        """
    }

    /// For a model without structured output: the shape to answer in.
    static let jsonShape = """
        Answer with JSON only, no other text, in this shape:
        {"conditions":[{"field":"lens","comparison":"contains","text":"85mm","value":0,"upperValue":0}]}
        Use 0 for a number the condition does not have and "" for text it does not have.
        """

    /// The conditions in a JSON answer; tolerant of a fenced block or words
    /// around it. nil when there is no readable JSON.
    static func conditions(fromJSON answer: String) -> [GeneratedSearchRule]? {
        guard let start = answer.firstIndex(of: "{"), let end = answer.lastIndex(of: "}"), start < end,
              let object = try? JSONSerialization.jsonObject(with: Data(answer[start...end].utf8)) as? [String: Any],
              let list = object["conditions"] as? [[String: Any]] else { return nil }
        return list.compactMap { item in
            guard let field = item["field"] as? String, let comparison = item["comparison"] as? String else { return nil }
            let text = (item["text"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let value = (item["value"] as? NSNumber)?.doubleValue
            let upper = (item["upperValue"] as? NSNumber)?.doubleValue
            return GeneratedSearchRule(
                field: field, comparison: comparison, text: text,
                value: value == 0 ? nil : value, upperValue: upper == 0 ? nil : upper
            )
        }
    }
}
