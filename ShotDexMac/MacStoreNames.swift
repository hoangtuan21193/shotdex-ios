import Foundation
import Observation

/// Source and server names, and whether any server connection exists, read
/// off the main actor (Mac hang 2026-11-08: a synchronous read on the main
/// thread waits for a free reader of the pool, and long background reads can
/// hold them all). Views that drew a row per job used to read these in their
/// body on every progress tick; they read this instead. Read again when
/// Sources or the servers change (the root window asks).
@MainActor
@Observable
final class MacStoreNames {
    private(set) var sources: [String: String] = [:]
    private(set) var connections: [String: String] = [:]
    private(set) var isLoaded = false
    var hasConnections: Bool { !connections.isEmpty }

    @ObservationIgnored private let sourceStore: SourceStore
    @ObservationIgnored private let fileServers: FileServerStore
    @ObservationIgnored private var token = 0
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []

    init(sources: SourceStore, fileServers: FileServerStore) {
        sourceStore = sources
        self.fileServers = fileServers
    }

    /// Reads both again; the newest read wins.
    func refresh() {
        token &+= 1
        let token = self.token
        let sourceStore = self.sourceStore
        let fileServers = self.fileServers
        Task {
            let (sources, connections) = await Task.detached(priority: .userInitiated) { () -> ([String: String], [String: String]) in
                let sources = Dictionary(((try? sourceStore.sources()) ?? []).map { ($0.id, $0.name) }) { first, _ in first }
                let connections = Dictionary(((try? fileServers.fetchAll()) ?? []).map { ($0.id, $0.name) }) { first, _ in first }
                return (sources, connections)
            }.value
            guard token == self.token else { return }
            if sources != self.sources { self.sources = sources }
            if connections != self.connections { self.connections = connections }
            isLoaded = true
            let waiting = waiters
            waiters = []
            waiting.forEach { $0.resume() }
        }
    }

    /// Returns once the first read is in.
    func loaded() async {
        if isLoaded { return }
        if token == 0 { refresh() }
        await withCheckedContinuation { waiters.append($0) }
    }
}
