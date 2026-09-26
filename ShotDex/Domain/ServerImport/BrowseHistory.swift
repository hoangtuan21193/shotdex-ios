import Foundation

/// Where the server browser has been (FS-17.01 §2a): Back and Forward walk
/// the visits like a web browser, not the folder tree — the title menu is
/// the way up.
struct BrowseHistory: Equatable, Sendable {
    private(set) var backStack: [String] = []
    private(set) var current: String
    private(set) var forwardStack: [String] = []

    init(start: String) {
        current = start
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    /// A folder opened by a tap, New Folder or the title menu: a new visit,
    /// which drops whatever Forward held.
    mutating func open(_ path: String) {
        guard path != current else { return }
        backStack.append(current)
        current = path
        forwardStack = []
    }

    /// False at the first visit — the screen is left instead.
    @discardableResult
    mutating func goBack() -> Bool {
        guard let previous = backStack.popLast() else { return false }
        forwardStack.append(current)
        current = previous
        return true
    }

    @discardableResult
    mutating func goForward() -> Bool {
        guard let next = forwardStack.popLast() else { return false }
        backStack.append(current)
        current = next
        return true
    }

    /// The folders above `path`, nearest first, ending at the root (`""`):
    /// the title menu.
    static func ancestors(of path: String) -> [String] {
        var components = ServerUploadPath.normalizedFolder(path).split(separator: "/").map(String.init)
        var result: [String] = []
        while !components.isEmpty {
            components.removeLast()
            result.append(components.joined(separator: "/"))
        }
        return result
    }
}
