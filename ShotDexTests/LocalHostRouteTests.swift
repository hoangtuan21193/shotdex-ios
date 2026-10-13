import Foundation
import Testing
@testable import ShotDex

/// A `.local` name resolves only on the home network: mDNS is not carried
/// by a VPN. Away from home, over a VPN another app set up, the address the
/// name had last time still routes home (FS-15.04 §7).
@Suite struct LocalHostRouteTests {
    @Test func onlyMulticastNamesAreRouted() {
        #expect(LocalHostRoute.isMulticastDNS("NAS-Home.local"))
        #expect(LocalHostRoute.isMulticastDNS("nas.local."))
        #expect(LocalHostRoute.isMulticastDNS("Nas.LOCAL"))
        #expect(!LocalHostRoute.isMulticastDNS("192.168.1.20"))
        #expect(!LocalHostRoute.isMulticastDNS("nas.example.com"))
        #expect(!LocalHostRoute.isMulticastDNS("local"))
        #expect(!LocalHostRoute.isMulticastDNS("mylocal"))
    }

    /// At home the name resolves: it is used, and its address remembered.
    @Test func atHomeTheNameIsUsedAndItsAddressRemembered() {
        let choice = LocalHostRoute.choose(host: "nas.local", resolved: "192.168.1.20", lastKnown: nil)
        #expect(choice == .init(host: "nas.local", remember: "192.168.1.20"))
        let same = LocalHostRoute.choose(host: "nas.local", resolved: "192.168.1.20", lastKnown: "192.168.1.20")
        #expect(same == .init(host: "nas.local", remember: nil))
        let moved = LocalHostRoute.choose(host: "nas.local", resolved: "192.168.1.31", lastKnown: "192.168.1.20")
        #expect(moved == .init(host: "nas.local", remember: "192.168.1.31"))
    }

    /// Away (over a VPN) the name does not resolve: the remembered address
    /// is used; with none, the name is kept and fails as it did before.
    @Test func awayTheRememberedAddressIsUsed() {
        #expect(LocalHostRoute.choose(host: "nas.local", resolved: nil, lastKnown: "192.168.1.20") == .init(host: "192.168.1.20", remember: nil))
        #expect(LocalHostRoute.choose(host: "nas.local", resolved: nil, lastKnown: nil) == .init(host: "nas.local", remember: nil))
    }

    /// Other hosts pass through untouched, resolved or not.
    @Test func otherHostsPassThrough() {
        #expect(LocalHostRoute.choose(host: "192.168.1.20", resolved: nil, lastKnown: "10.0.0.1") == .init(host: "192.168.1.20", remember: nil))
        #expect(LocalHostRoute.choose(host: "nas.example.com", resolved: "1.2.3.4", lastKnown: nil) == .init(host: "nas.example.com", remember: nil))
    }

    /// The client resolves once, connects to the address it chose and tells
    /// the address book what it learned.
    @Test func routedClientConnectsToTheRememberedAddressAway() async throws {
        let server = FileServer(name: "NAS", transferProtocol: .webdav, host: "nas.local", username: "me")
        let book = InMemoryServerAddressBook()
        book.setAddress("192.168.1.20", for: server.id)
        let made = MadeHosts()
        let client = RoutedRemoteFileClient(server: server, addresses: book, resolve: { _ in nil }) { routed in
            made.append(routed.host)
            return InMemoryRemoteFileClient()
        }
        try await client.connect()
        _ = try await client.directoryExists("photos")
        #expect(made.hosts == ["192.168.1.20"])
    }

    @Test func routedClientRemembersTheAddressAtHome() async throws {
        let server = FileServer(name: "NAS", transferProtocol: .smb, host: "nas.local", username: "me")
        let book = InMemoryServerAddressBook()
        let client = RoutedRemoteFileClient(server: server, addresses: book, resolve: { _ in "192.168.1.20" }) { _ in
            InMemoryRemoteFileClient()
        }
        try await client.connect()
        #expect(book.address(for: server.id) == "192.168.1.20")
    }

    /// The background-upload extension cannot resolve first, so it is handed
    /// the remembered address of a `.local` connection.
    @Test func extensionGetsTheRememberedAddress() {
        let server = FileServer(name: "NAS", transferProtocol: .webdav, host: "nas.local", username: "me")
        let job = BackupJob(sourceId: PhotoLibrarySource.id, connectionId: server.id, folder: "Backup")
        let book = InMemoryServerAddressBook()
        #expect(BackupUploadExtensionSync.config(jobs: [job], servers: [server], addresses: book).jobs.first?.baseURL.contains("nas.local") == true)
        book.setAddress("192.168.1.20", for: server.id)
        #expect(BackupUploadExtensionSync.config(jobs: [job], servers: [server], addresses: book).jobs.first?.baseURL.contains("192.168.1.20") == true)
    }
}

private final class MadeHosts: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    var hosts: [String] { lock.withLock { stored } }
    func append(_ host: String) { lock.withLock { stored.append(host) } }
}
