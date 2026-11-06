import Foundation
import Testing
@testable import ShotDex

/// FS-18.04 §3 AC-78: what Settings › Servers says about Local Network access.
@Suite struct LocalNetworkAccessTests {
    @Test func lineFollowsTheBrowser() {
        #expect(LocalNetworkAccessLine.from(isSearching: true, isDenied: false, refusedBeforePrompt: false) == .checking)
        #expect(LocalNetworkAccessLine.from(isSearching: false, isDenied: false, refusedBeforePrompt: false) == .allowed)
        #expect(LocalNetworkAccessLine.from(isSearching: false, isDenied: true, refusedBeforePrompt: false) == .off)
        // Refused before any prompt, still refused when the look is over: an old "no", not "allowed".
        #expect(LocalNetworkAccessLine.from(isSearching: false, isDenied: false, refusedBeforePrompt: true) == .off)
        // Refused while the look goes: maybe the prompt is up; wait.
        #expect(LocalNetworkAccessLine.from(isSearching: true, isDenied: false, refusedBeforePrompt: true) == .checking)
        #expect(LocalNetworkAccessLine.off.text.hasPrefix("Off · "))
        #expect(LocalNetworkAccessLine.privacySettingsURL.absoluteString.hasSuffix("Privacy_LocalNetwork"))
    }

    /// The model keeps the refusal it saw before a prompt closed, for Settings to read.
    @MainActor
    @Test func modelRemembersAnEarlyRefusal() async throws {
        let browser = ServerDiscoveryModelTests.ScriptedBrowser()
        let model = ServerDiscoveryModel(browser: browser, giveUpAfter: .milliseconds(50))
        model.start()
        browser.onEvent?(.denied)
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.deniedWhilePrompting)
        #expect(LocalNetworkAccessLine.from(isSearching: model.state == .searching, isDenied: model.state == .denied,
                                            refusedBeforePrompt: model.deniedWhilePrompting) == .off)
    }
}
