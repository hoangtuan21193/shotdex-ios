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

    private static let votedDefaultsKey = "support.votedTicketIDs"

    /// Team replies not yet read, for the badge on the Settings row.
    var unreadCount: Int { tickets.reduce(0) { $0 + $1.unread } }

    init(service: SupportService, metadataStore: MetadataStore) {
        self.service = service
        self.metadataStore = metadataStore
        let stored = UserDefaults.standard.stringArray(forKey: Self.votedDefaultsKey) ?? []
        votedIDs = Set(stored)
    }

    func refresh() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoadedOnce = true
        }
        do {
            // Both in one pass: the screen shows the two lists together, and a
            // second spinner for the roadmap would be noise.
            async let mine = service.tickets()
            async let items = service.roadmap()
            tickets = try await mine
            roadmap = try await items
        } catch let failure as SupportError {
            error = failure
        } catch {
            self.error = .network
        }
    }

    func submit(kind: SupportTicketKind, title: String, body: String, logs: String?) async -> Bool {
        do {
            let diagnostics = SupportDiagnostics(libraryCount: try? metadataStore.rowCount())
            try await service.createTicket(
                kind: kind,
                title: title,
                body: body,
                diagnostics: diagnostics,
                logs: logs
            )
            await refresh()
            return true
        } catch let failure as SupportError {
            error = failure
            return false
        } catch {
            self.error = .network
            return false
        }
    }

    func reply(to ticket: SupportTicket, body: String) async -> Bool {
        do {
            try await service.reply(to: ticket.id, body: body)
            await refresh()
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
        try? await service.markRead(ticketID: ticket.id)
        await refresh()
    }

    func isVoted(_ item: SupportRoadmapItem) -> Bool { votedIDs.contains(item.id) }

    func toggleVote(_ item: SupportRoadmapItem) async {
        let wasVoted = votedIDs.contains(item.id)
        setVoted(!wasVoted, id: item.id)
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
        UserDefaults.standard.set(Array(votedIDs), forKey: Self.votedDefaultsKey)
    }
}

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
