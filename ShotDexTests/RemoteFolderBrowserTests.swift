import Foundation
import Testing
@testable import ShotDex

/// The folder browser in the upload sheet (FS-15.02 §2a, AC-22, AC-23).
@Suite @MainActor struct RemoteFolderBrowserTests {
    private func server() -> InMemoryRemoteFileClient {
        let client = InMemoryRemoteFileClient()
        client.put("Photos/a.CR3", Data([1]))
        client.put("Photos/RAW/b.CR3", Data([2]))
        client.put("Photos/.snapshots/c", Data([3]))
        client.put("Photos/10/d.CR3", Data([4]))
        client.put("Photos/2/e.CR3", Data([5]))
        return client
    }

    @Test func listsSubfoldersSortedWithoutHidden() async {
        let browser = RemoteFolderBrowser(client: server())
        await browser.load("Photos")
        #expect(browser.listing(for: "Photos") == .loaded(["2", "10", "RAW"]))
        await browser.load("")
        #expect(browser.listing(for: "") == .loaded(["Photos"]))
    }

    @Test func newFolderIsCreatedAndOpened() async throws {
        let client = server()
        let browser = RemoteFolderBrowser(client: client)
        await browser.load("Photos")

        let created = await browser.createFolder(named: "  Trip ", in: "Photos")
        #expect(created == "Photos/Trip")
        #expect(try await client.directoryExists("Photos/Trip"))
        #expect(browser.listing(for: "Photos") == .loaded(["2", "10", "RAW", "Trip"]))
        await browser.load("Photos/Trip")
        #expect(browser.listing(for: "Photos/Trip") == .loaded([]))

        // Already there: opened, not an error.
        #expect(await browser.createFolder(named: "RAW", in: "Photos") == "Photos/RAW")
        #expect(browser.createError == nil)
        // Not a name.
        #expect(await browser.createFolder(named: "a/b", in: "Photos") == nil)
        #expect(await browser.createFolder(named: "   ", in: "Photos") == nil)
        // One connection for the whole browse.
        #expect(client.connectCount == 1)
    }

    @Test func failureShowsReasonAndRetries() async {
        let client = server()
        client.connectError = .authenticationFailed
        let browser = RemoteFolderBrowser(client: client)
        await browser.load("Photos")
        #expect(browser.listing(for: "Photos") == .failed(.authenticationFailed))
        #expect(RemoteFileError.authenticationFailed.localizedDescription == "The username or password was rejected.")

        // Opening it again does not hammer the server; Try Again does.
        await browser.load("Photos")
        #expect(client.connectCount == 1)
        client.connectError = nil
        await browser.load("Photos", force: true)
        #expect(client.connectCount == 2)
        #expect(browser.listing(for: "Photos") == .loaded(["2", "10", "RAW"]))
    }

    /// The browser opens at the chosen folder, Back walking up to the root.
    @Test func routeChainWalksDownFromTheRoot() {
        #expect(RemoteFolderRoute.chain(to: "/Photos//Trip/").map(\.path) == ["", "Photos", "Photos/Trip"])
        #expect(RemoteFolderRoute.chain(to: "").map(\.path) == [""])
    }
}
