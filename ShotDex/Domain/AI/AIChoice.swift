import Foundation

/// Who does an AI job (FS-08.07 §3): the two rows on top of Settings › AI.
enum AIChoice: Hashable, Sendable {
    /// Subtitle Translation's default: the Translate sheet asks.
    case askEachTime
    /// AI Search off: search is the parser alone.
    case off
    case appleTranslation
    case appleIntelligence
    case provider(String)

    var stored: String {
        switch self {
        case .askEachTime: "ask"
        case .off: "off"
        case .appleTranslation: "appleTranslation"
        case .appleIntelligence: "appleIntelligence"
        case .provider(let id): "provider:\(id)"
        }
    }

    init?(stored: String) {
        switch stored {
        case "ask": self = .askEachTime
        case "off": self = .off
        case "appleTranslation": self = .appleTranslation
        case "appleIntelligence": self = .appleIntelligence
        default:
            guard stored.hasPrefix("provider:") else { return nil }
            self = .provider(String(stored.dropFirst("provider:".count)))
        }
    }

    /// What the device offers on its own.
    struct OnDevice: Equatable, Sendable {
        var appleTranslation: Bool
        var appleIntelligence: Bool
    }

    /// Subtitle Translation: Ask Each Time, the built-in ones the device
    /// has, every provider.
    static func translationOptions(providers: [AIProvider], onDevice: OnDevice) -> [AIChoice] {
        var options: [AIChoice] = [.askEachTime]
        if onDevice.appleTranslation { options.append(.appleTranslation) }
        if onDevice.appleIntelligence { options.append(.appleIntelligence) }
        return options + providers.map { .provider($0.id) }
    }

    /// AI Search: never a cloud service (§5) — Apple Intelligence, home
    /// servers, Off.
    static func searchOptions(providers: [AIProvider], onDevice: OnDevice) -> [AIChoice] {
        var options: [AIChoice] = []
        if onDevice.appleIntelligence { options.append(.appleIntelligence) }
        options += providers.filter(\.kind.servesAISearch).map { .provider($0.id) }
        return options + [.off]
    }

    /// The stored value, or the default when unset or no longer offered —
    /// a deleted provider's row goes back to its default (AC-5).
    static func translation(stored: String?, providers: [AIProvider], onDevice: OnDevice) -> AIChoice {
        resolve(stored, options: translationOptions(providers: providers, onDevice: onDevice), fallback: .askEachTime)
    }

    static func search(stored: String?, providers: [AIProvider], onDevice: OnDevice) -> AIChoice {
        resolve(stored, options: searchOptions(providers: providers, onDevice: onDevice), fallback: onDevice.appleIntelligence ? .appleIntelligence : .off)
    }

    private static func resolve(_ stored: String?, options: [AIChoice], fallback: AIChoice) -> AIChoice {
        guard let stored, let choice = AIChoice(stored: stored), options.contains(choice) else { return fallback }
        return choice
    }
}
