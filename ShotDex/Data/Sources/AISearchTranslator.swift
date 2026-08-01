import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Reads a typed query with Apple's on-device model, for the phrasings no pattern
/// was written for.
///
/// It is an addition, never the feature: `SystemLanguageModel` needs iOS 26 *and*
/// Apple-Intelligence hardware, which most of the installed base does not have, so
/// `SearchIntentParser` handles everything on its own and this only runs when it
/// can. Nothing here is on the critical path — a failure, a timeout, or an
/// unsupported device all end up in the same place: the parser's answer.
///
/// The model never sees SQL and never produces a rule. It fills in
/// `GeneratedSearchRule`, and `SearchIntentMapper` decides what, if anything, that
/// becomes. That boundary is the reason a hallucinated field or a nonsense number
/// costs nothing.
@available(iOS 26.0, *)
actor AISearchTranslator {
    /// How long a query may wait on the model before the parser's answer is used
    /// instead. A search box has to feel immediate; two seconds is already the
    /// outer edge of acceptable.
    private static let timeout = Duration.seconds(2)
    /// Vocabulary sent with the request. Enough to ground real names, short enough
    /// to keep the prompt small.
    private static let vocabularyLimit = 40

    #if canImport(FoundationModels)
    private var session: LanguageModelSession?

    /// Whether the device can run this at all — hardware, setting and language.
    static func isAvailable(locale: Locale = .current) -> Bool {
        let model = SystemLanguageModel.default
        return model.availability == .available && model.supportsLocale(locale)
    }

    /// Nudges the model into memory so the first real query is not the one paying
    /// for the load. Safe to call repeatedly.
    func prewarm(vocabulary: FilterSuggestionCatalog) {
        guard Self.isAvailable() else { return }
        let session = session ?? makeSession(vocabulary: vocabulary)
        self.session = session
        session.prewarm()
    }

    /// Translates `query`, or returns nil and lets the caller fall back.
    func translate(
        _ query: String,
        vocabulary: FilterSuggestionCatalog
    ) async -> [SmartAlbumRule]? {
        guard Self.isAvailable() else { return nil }
        let session = session ?? makeSession(vocabulary: vocabulary)
        self.session = session
        guard !session.isResponding else { return nil }

        let work = Task {
            try await session.respond(
                to: Self.prompt(for: query),
                generating: GeneratedSearch.self
            ).content
        }
        let timeout = Task {
            try? await Task.sleep(for: Self.timeout)
            work.cancel()
        }
        defer { timeout.cancel() }

        guard let generated = try? await work.value else { return nil }
        let rules = SearchIntentMapper.rules(from: generated.conditions.map(\.asGeneratedRule))
        return rules.isEmpty ? nil : rules
    }

    private func makeSession(vocabulary: FilterSuggestionCatalog) -> LanguageModelSession {
        LanguageModelSession(instructions: Self.instructions(vocabulary: vocabulary))
    }

    private static func prompt(for query: String) -> String {
        """
        Photo search request: "\(query)"
        List the conditions it asks for. Omit anything it does not say.
        """
    }

    /// The model is told the library's real camera, lens and place names, so it
    /// writes back names that exist instead of plausible-looking inventions.
    private static func instructions(vocabulary: FilterSuggestionCatalog) -> String {
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

    /// Flat on purpose: strings and numbers only, so the schema stays small and
    /// the model has no app type to get wrong.
    // Not `private`: the `@Generable` macro synthesises an initializer that has to
    // be at least as visible as the type it builds.
    @Generable
    struct GeneratedSearch: Equatable {
        @Guide(description: "One entry per condition the request states. Empty if none.")
        var conditions: [Condition]

        @Generable
        struct Condition: Equatable {
            @Guide(description: "place, camera, brand, lens, iso, aperture, shutter, focal, filename, date, favorite, filetype, sensor")
            var field: String
            @Guide(description: "is, contains, not, greater, less, range, before, after, lastdays")
            var comparison: String
            @Guide(description: "Text operand for place, camera, brand, lens, filename, filetype, sensor. Empty otherwise.")
            var text: String
            @Guide(description: "Numeric operand, or the lower bound of a range. Zero when the condition has no number.")
            var value: Double
            @Guide(description: "Upper bound when the comparison is range. Zero otherwise.")
            var upperValue: Double

            var asGeneratedRule: GeneratedSearchRule {
                GeneratedSearchRule(
                    field: field,
                    comparison: comparison,
                    text: text.isEmpty ? nil : text,
                    // A schema cannot express "no number", so zero is the stand-in.
                    // No field in the app has a meaningful zero — ISO 0, f/0 and a
                    // zero-second exposure are all nonsense — so this loses nothing.
                    value: value == 0 ? nil : value,
                    upperValue: upperValue == 0 ? nil : upperValue
                )
            }
        }
    }
    #else
    static func isAvailable(locale: Locale = .current) -> Bool { false }
    func prewarm(vocabulary: FilterSuggestionCatalog) {}
    func translate(_ query: String, vocabulary: FilterSuggestionCatalog) async -> [SmartAlbumRule]? {
        nil
    }
    #endif
}
