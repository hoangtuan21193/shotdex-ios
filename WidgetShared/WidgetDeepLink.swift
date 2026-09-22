import Foundation

/// The URLs a widget tap opens the app with.
///
/// Built by the widget, parsed by the app's `onOpenURL`; both from this one
/// type so the two never drift. A photo's local identifier contains slashes
/// (`ABCD-1234/L0/001`), which is why it travels as a query item rather than
/// a path — `URLComponents` percent-encodes it going out and decodes it
/// coming back.
enum WidgetDeepLink: Equatable {
    /// Open the On This Day screen for the day named by `dayKey`
    /// (`WidgetSharedContainer.dayKey`).
    case onThisDay(dayKey: String)
    /// Open one photo in the viewer. `opensEditor` comes from the share sheet's
    /// **Edit in ShotDex** action, which means "take me straight to the editor"
    /// rather than "show me this photo" — the widget's own taps leave it false.
    case photo(assetId: String, opensEditor: Bool = false)

    static let scheme = "shotdex"

    private enum Host {
        static let onThisDay = "on-this-day"
        static let photo = "photo"
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .onThisDay(let dayKey):
            components.host = Host.onThisDay
            components.queryItems = [URLQueryItem(name: "day", value: dayKey)]
        case .photo(let assetId, let opensEditor):
            components.host = Host.photo
            components.queryItems = [URLQueryItem(name: "id", value: assetId)]
            if opensEditor {
                components.queryItems?.append(URLQueryItem(name: "edit", value: "1"))
            }
        }
        // Every field above is a fixed literal or a percent-encoded query
        // value, so the only way this fails is a programming error.
        return components.url ?? URL(string: "\(Self.scheme)://")!
    }

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == Self.scheme
        else { return nil }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        switch components.host?.lowercased() {
        case Host.onThisDay:
            guard let day = value("day") else { return nil }
            self = .onThisDay(dayKey: day)
        case Host.photo:
            guard let id = value("id") else { return nil }
            self = .photo(assetId: id, opensEditor: value("edit") == "1")
        default:
            return nil
        }
    }
}
