import Foundation
import SwiftUI

/// Owns the Support screen's state: the threads this install opened, the public
/// roadmap, and whatever is in flight.
///
/// There is no account behind any of it — the install's App Attest key is the
/// only identity, so "your messages" means "messages from this install".
@MainActor
@Observable
final class SupportModel {
    private let service: SupportService
    private let metadataStore: MetadataStore

    private(set) var tickets: [SupportTicket] = []
    private(set) var roadmap: [SupportRoadmapItem] = []
    private(set) var isLoading = false
    private(set) var hasLoadedOnce = false
    /// Ids this install has voted for, so the roadmap can show the state before
    /// the server answers. The server is still the authority on the count.
    private(set) var votedIDs: Set<String> = []
    var error: SupportError?
    /// Set the first time the Secure Enclave refuses, which is what a build
    /// signed without the App Attest capability does. The screen then offers
    /// mail rather than buttons that cannot work.
    private(set) var canUsePortal = SupportService.isPortalPossible

    private static let votedDefaultsKey = "support.votedTicketIDs"

    /// Where support runs when this build cannot use the in-app channel.
    static let supportAddress = "support@shotdex.app"

    #if DEBUG
    /// Seeded threads and roadmap that never reach the server (the Mac's
    /// `-ShotDexDemoLibrary`): sending and voting change only this model.
    private var isDemo = false
    #endif

    /// Team replies not yet read, for the badge on the Settings row.
    var unreadCount: Int { tickets.reduce(0) { $0 + $1.unread } }

    init(service: SupportService, metadataStore: MetadataStore) {
        self.service = service
        self.metadataStore = metadataStore
        let stored = UserDefaults.standard.stringArray(forKey: Self.votedDefaultsKey) ?? []
        votedIDs = Set(stored)
    }

    nonisolated private static func attempt<T: Sendable>(_ body: @Sendable () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await body()) } catch { return .failure(error) }
    }

    /// The last refresh could not read the lists: the screen says so rather
    /// than "nothing sent yet".
    private(set) var lastRefreshFailed = false

    /// Bumped by every refresh: an older one that answers late is dropped
    /// rather than putting back a list a newer one already replaced.
    private var refreshGeneration = 0

    /// - Parameter reportsErrors: false for a refresh nobody asked for
    ///   (the app coming to the front) — offline, that would be an alert on
    ///   every switch.
    func refresh(reportsErrors: Bool = true) async {
        #if DEBUG
        if isDemo { hasLoadedOnce = true; return }
        #endif
        // A quiet refresh while one is on its way adds nothing but requests.
        if !reportsErrors, isLoading { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        isLoading = true
        defer {
            if generation == refreshGeneration { isLoading = false }
            hasLoadedOnce = true
        }
        // Both in one pass: the screen shows the two lists together, and a
        // second spinner for the roadmap would be noise. Each lands on its
        // own, so a failed thread list still shows the roadmap.
        async let mine = Self.attempt { try await self.service.tickets() }
        async let items = Self.attempt { try await self.service.roadmap() }
        let (ticketsResult, roadmapResult) = await (mine, items)
        // A closed window cancels its refresh: that is not a failure to report.
        guard !Task.isCancelled, generation == refreshGeneration else { return }
        if case .success(let value) = ticketsResult { tickets = value }
        if case .success(let value) = roadmapResult { roadmap = value }
        guard case .failure(let thrown) = ticketsResult.flatMap({ _ in roadmapResult.map { _ in () } }) else {
            lastRefreshFailed = false
            return
        }
        if thrown is CancellationError { return }
        lastRefreshFailed = true
        if let failure = thrown as? SupportError {
            // Failing to load is not worth an alert when the cause is that this
            // build cannot attest: the screen simply becomes the mail screen.
            if case .attestationUnavailable = failure {
                canUsePortal = false
            } else if reportsErrors {
                error = failure
            }
        } else if reportsErrors {
            self.error = .network
        }
    }

    func submit(kind: SupportTicketKind, title: String, body: String, logs: String?) async -> Bool {
        #if DEBUG
        if isDemo {
            let now = Date()
            tickets.insert(SupportTicket(id: UUID().uuidString, kind: kind, title: title, body: body, status: .open, votes: 0,
                                         createdAt: now, updatedAt: now, unread: 0, messages: []), at: 0)
            return true
        }
        #endif
        do {
            // The count is a read of every row: off the main actor.
            let store = metadataStore
            let count = await Task.detached(priority: .userInitiated) { try? store.rowCount() }.value
            let diagnostics = SupportDiagnostics(libraryCount: count)
            try await service.createTicket(
                kind: kind,
                title: title,
                body: body,
                diagnostics: diagnostics,
                logs: logs
            )
            // The write went through; a failed re-read is not the user's failure.
            await refresh(reportsErrors: false)
            return true
        } catch let failure as SupportError {
            if case .attestationUnavailable = failure { canUsePortal = false }
            error = failure
            return false
        } catch {
            self.error = .network
            return false
        }
    }

    func reply(to ticket: SupportTicket, body: String) async -> Bool {
        #if DEBUG
        if isDemo {
            guard let index = tickets.firstIndex(where: { $0.id == ticket.id }) else { return false }
            let old = tickets[index]
            let now = Date()
            tickets[index] = SupportTicket(id: old.id, kind: old.kind, title: old.title, body: old.body, status: old.status,
                                           votes: old.votes, createdAt: old.createdAt, updatedAt: now, unread: old.unread,
                                           messages: old.messages + [SupportMessage(id: UUID().uuidString, author: .user, body: body, createdAt: now)])
            return true
        }
        #endif
        do {
            try await service.reply(to: ticket.id, body: body)
            // The write went through; a failed re-read is not the user's failure.
            await refresh(reportsErrors: false)
            return true
        } catch let failure as SupportError {
            error = failure
            return false
        } catch {
            self.error = .network
            return false
        }
    }

    /// Clears the badge for one thread. Failure is silent on purpose: the user
    /// asked to read a message, not to perform a sync, and the badge simply
    /// stays until the next refresh.
    func markRead(_ ticket: SupportTicket) async {
        guard ticket.unread > 0 else { return }
        #if DEBUG
        if isDemo {
            guard let index = tickets.firstIndex(where: { $0.id == ticket.id }) else { return }
            let old = tickets[index]
            tickets[index] = SupportTicket(id: old.id, kind: old.kind, title: old.title, body: old.body, status: old.status,
                                           votes: old.votes, createdAt: old.createdAt, updatedAt: old.updatedAt, unread: 0,
                                           messages: old.messages)
            return
        }
        #endif
        try? await service.markRead(ticketID: ticket.id)
        await refresh(reportsErrors: false)
    }

    func isVoted(_ item: SupportRoadmapItem) -> Bool { votedIDs.contains(item.id) }

    /// Votes on their way: a second click waits, or a DELETE could overtake the POST.
    private(set) var pendingVotes: Set<String> = []

    func toggleVote(_ item: SupportRoadmapItem) async {
        guard !pendingVotes.contains(item.id) else { return }
        pendingVotes.insert(item.id)
        defer { pendingVotes.remove(item.id) }
        let wasVoted = votedIDs.contains(item.id)
        setVoted(!wasVoted, id: item.id)
        #if DEBUG
        if isDemo {
            guard let index = roadmap.firstIndex(where: { $0.id == item.id }) else { return }
            roadmap[index] = SupportRoadmapItem(id: item.id, kind: item.kind, title: item.title, status: item.status,
                                                votes: item.votes + (wasVoted ? -1 : 1))
            return
        }
        #endif
        do {
            let votes = try await service.setVote(!wasVoted, ticketID: item.id)
            if let index = roadmap.firstIndex(where: { $0.id == item.id }) {
                roadmap[index] = SupportRoadmapItem(
                    id: item.id,
                    kind: item.kind,
                    title: item.title,
                    status: item.status,
                    votes: votes
                )
            }
        } catch let failure as SupportError {
            // Put the vote back: a count that lies is worse than no count.
            setVoted(wasVoted, id: item.id)
            error = failure
        } catch {
            setVoted(wasVoted, id: item.id)
            self.error = .network
        }
    }

    private func setVoted(_ isVoted: Bool, id: String) {
        if isVoted {
            votedIDs.insert(id)
        } else {
            votedIDs.remove(id)
        }
        #if DEBUG
        // The demo's votes never overwrite this install's real ones.
        if isDemo { return }
        #endif
        UserDefaults.standard.set(Array(votedIDs), forKey: Self.votedDefaultsKey)
    }
}

#if DEBUG
extension SupportModel {
    /// The board's threads (`MAC_Support`): one bug with a reply waiting,
    /// two older ones, and five public requests.
    static func demo(service: SupportService, metadataStore: MetadataStore, now: Date = Date()) -> SupportModel {
        let model = SupportModel(service: service, metadataStore: metadataStore)
        model.isDemo = true
        model.canUsePortal = true
        model.hasLoadedOnce = true
        model.votedIDs = []
        func ago(days: Double, hours: Double = 0) -> Date { now.addingTimeInterval(-(days * 86_400 + hours * 3_600)) }
        model.tickets = [
            SupportTicket(id: "demo-smb", kind: .bug, title: "Upload to SMB server stops at 99% on large HEIC files",
                          body: "Uploading a batch of 40 HEIC files to my Synology over SMB gets to 99% and stays there. Smaller batches finish fine. MacBook Air on Wi-Fi.",
                          status: .inProgress, votes: 0, createdAt: ago(days: 16), updatedAt: ago(days: 2), unread: 1, messages: [
                SupportMessage(id: "m1", author: .team, body: "Thanks, we can reproduce it with files over 25 MB. A fix is going into the next build.", createdAt: ago(days: 15, hours: 4)),
                SupportMessage(id: "m2", author: .user, body: "Great, happy to test it. It happens with ProRAW DNGs too.", createdAt: ago(days: 14, hours: 20)),
                SupportMessage(id: "m3", author: .team, body: "Noted, the same fix covers DNGs. We will reply here when it ships.", createdAt: ago(days: 2)),
            ]),
            SupportTicket(id: "demo-lens", kind: .feature, title: "Filter Smart Albums by lens focal range",
                          body: "I would like a smart album of everything shot between 70 and 200mm.",
                          status: .planned, votes: 12, createdAt: ago(days: 30), updatedAt: ago(days: 7), unread: 0, messages: [
                SupportMessage(id: "m4", author: .team, body: "Planned — Focal Length already has a range condition; we will make it easier to find.", createdAt: ago(days: 7)),
            ]),
            SupportTicket(id: "demo-iphone16", kind: .bug, title: "Statistics lists iPhone 16 Pro twice",
                          body: "The camera chart has two iPhone 16 Pro bars.",
                          status: .shipped, votes: 0, createdAt: ago(days: 40), updatedAt: ago(days: 21), unread: 0, messages: [
                SupportMessage(id: "m5", author: .team, body: "Fixed in 1.0 (22): the two names now count as one camera.", createdAt: ago(days: 21)),
            ]),
        ]
        model.roadmap = [
            SupportRoadmapItem(id: "r1", kind: .feature, title: "Luminance range masks", status: .planned, votes: 412),
            SupportRoadmapItem(id: "r2", kind: .feature, title: "Sync edits between Mac and iPhone", status: .triaged, votes: 368),
            SupportRoadmapItem(id: "r3", kind: .feature, title: "RAW + JPEG pairs as one photo", status: .planned, votes: 291),
            SupportRoadmapItem(id: "r4", kind: .feature, title: "Contact sheet as PDF", status: .triaged, votes: 147),
            SupportRoadmapItem(id: "r5", kind: .feature, title: "Map of every photo", status: .triaged, votes: 96),
        ]
        return model
    }
}
#endif

extension SupportTicketStatus {
    /// What the row says. `open` reads as "received" rather than "open", which
    /// sounds like something the reader has to close.
    var label: LocalizedStringKey {
        switch self {
        case .open: "Received"
        case .triaged: "Considering"
        case .planned: "Planned"
        case .inProgress: "In Progress"
        case .shipped: "Shipped"
        case .declined: "Not Planned"
        case .duplicate: "Already Reported"
        }
    }

    /// - Parameter accent: passed in rather than read from the environment,
    ///   because DESIGN.md §3.1 forbids `Color.accentColor` and an enum has no
    ///   environment to read from.
    func tint(accent: Color) -> Color {
        switch self {
        case .open, .triaged: .secondary
        case .planned, .inProgress: accent
        case .shipped: .green
        case .declined, .duplicate: .secondary
        }
    }
}

extension SupportTicketKind {
    var label: LocalizedStringKey {
        switch self {
        case .bug: "Bug"
        case .feature: "Feature Request"
        }
    }

    var symbolName: String {
        switch self {
        case .bug: "ladybug"
        case .feature: "lightbulb"
        }
    }
}

// Sheets and alerts keyed by these (iOS and Mac Support screens).
extension SupportTicketKind: Identifiable {
    var id: String { rawValue }
}

extension SupportError: Identifiable {
    var id: String { localizedDescription }
}
