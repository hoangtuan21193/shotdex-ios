import Foundation
import Testing
@testable import ShotDex

/// FS-15.04 §2 states, against a scripted browser.
@Suite @MainActor struct ServerDiscoveryModelTests {
    final class ScriptedBrowser: LocalServerBrowsing {
        var onEvent: (@MainActor (LocalServerBrowserEvent) -> Void)?
        var isRunning = false
        func start(onEvent: @escaping @MainActor (LocalServerBrowserEvent) -> Void) {
            self.onEvent = onEvent
            isRunning = true
        }
        func stop() { isRunning = false }
    }

    private let smb = BonjourRecord(name: "Mac", type: "_smb._tcp", host: "mac.local.", port: 445)

    /// AC-29.
    @Test func emptyAfterTimeout() async {
        let browser = ScriptedBrowser()
        let model = ServerDiscoveryModel(browser: browser, giveUpAfter: .milliseconds(50))
        model.start()
        #expect(model.state == .searching)
        // Unresolved records are not rows yet.
        browser.onEvent?(.records([BonjourRecord(name: "Mac", type: "_smb._tcp")]))
        #expect(model.state == .searching)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(model.state == .none)
        #expect(!model.isSearching)

        // A server that turns up late still appears.
        browser.onEvent?(.records([smb]))
        guard case .found(let servers) = model.state else { Issue.record("expected found"); return }
        #expect(servers.map(\.name) == ["Mac"])

        model.stop()
        #expect(!browser.isRunning)
    }

    @Test func deniedWins() {
        let browser = ScriptedBrowser()
        let model = ServerDiscoveryModel(browser: browser, giveUpAfter: .seconds(60))
        model.start()
        browser.onEvent?(.denied)
        browser.onEvent?(.records([smb]))
        #expect(model.state == .denied)
        model.stop()
    }

    @Test func serverLeavingEmptiesTheList() {
        let browser = ScriptedBrowser()
        let model = ServerDiscoveryModel(browser: browser, giveUpAfter: .seconds(60))
        model.start()
        browser.onEvent?(.records([smb]))
        browser.onEvent?(.records([]))
        #expect(model.state == .searching)
        model.stop()
    }
}
