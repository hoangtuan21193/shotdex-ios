import SwiftUI

/// Support: report a bug, request a feature, read the replies, and vote on what
/// other people asked for.
///
/// Apple gives a developer no way to message a user — review replies need a
/// review first, and TestFlight feedback never reaches App Store users — so
/// this is the channel. It stays anonymous: no account, no email address, no
/// password. Tier A (`List`, `.insetGrouped`), per DESIGN.md §10.1.
struct SupportScreen: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.appAccent) private var accent
    @State private var model: SupportModel
    @State private var composeKind: SupportTicketKind?
    @State private var isMailFailureAlertPresented = false

    init(service: SupportService, metadataStore: MetadataStore) {
        _model = State(wrappedValue: SupportModel(service: service, metadataStore: metadataStore))
    }

    var body: some View {
        List {
            composeSection
            if !model.tickets.isEmpty { threadsSection }
            roadmapSection
            privacySection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }
        .task { await model.refresh() }
        .sheet(item: $composeKind) { kind in
            SupportComposeScreen(kind: kind) { title, body, logs in
                await model.submit(kind: kind, title: title, body: body, logs: logs)
            }
        }
        .alert(
            "No mail account on this device",
            isPresented: $isMailFailureAlertPresented
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Write to \(Self.supportAddress) from wherever you read your mail.")
        }
        .alert(item: $model.error) { error in
            Alert(
                title: Text(error.errorDescription ?? ""),
                message: Text(error.recoverySuggestion ?? ""),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: Compose

    private var composeSection: some View {
        Section {
            if model.canUsePortal {
                Button {
                    composeKind = .bug
                } label: {
                    Label("Report a Bug", systemImage: SupportTicketKind.bug.symbolName)
                }
                Button {
                    composeKind = .feature
                } label: {
                    Label("Request a Feature", systemImage: SupportTicketKind.feature.symbolName)
                }
            } else {
                // App Attest does not exist on a simulator, needs a paid Apple
                // Developer Program membership to be signed in at all, and can
                // be refused for a device. Mail is the fallback rather than a
                // dead button that silently does nothing.
                Button {
                    openMail()
                } label: {
                    Label("Contact Support by Email", systemImage: "envelope")
                }
            }
        } footer: {
            // The promise has to match the route actually on offer: a build that
            // cannot attest has no inbox to deliver a reply to.
            Text(model.canUsePortal
                 ? "Replies arrive here in the app. There is no account and no email address to give."
                 : "This build cannot use the in-app channel, so support runs by email. Replies go to wherever you write from.")
        }
    }

    // MARK: Your threads

    private var threadsSection: some View {
        Section("Your Messages") {
            ForEach(model.tickets) { ticket in
                NavigationLink {
                    SupportThreadScreen(ticket: ticket, model: model)
                } label: {
                    SupportTicketRow(ticket: ticket, accent: accent)
                }
            }
        }
    }

    // MARK: Roadmap

    @ViewBuilder
    private var roadmapSection: some View {
        Section {
            if model.roadmap.isEmpty {
                if model.isLoading && !model.hasLoadedOnce {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Nothing here yet. Requests appear once they have been read.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(model.roadmap) { item in
                    SupportRoadmapRow(
                        item: item,
                        accent: accent,
                        isVoted: model.isVoted(item),
                        canVote: model.canUsePortal
                    ) {
                        Task { await model.toggleVote(item) }
                    }
                }
            }
        } header: {
            Text("What People Asked For")
        } footer: {
            Text(model.canUsePortal
                 ? "One vote per device. The most wanted requests are built first."
                 : "Voting needs the in-app channel, which this build cannot use.")
        }
    }

    private var privacySection: some View {
        Section {
            Text(model.canUsePortal
                 ? "A message carries your words, the app and iOS version, the device model and roughly how many photos you have. Never a photo, a name or an email address."
                 : "An email carries whatever you write, plus the app and iOS versions and the device model, which are filled in for you. Never a photo.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Helpers

    static let supportAddress = "support@shotdex.app"

    private func openMail() {
        let diagnostics = SupportDiagnostics(libraryCount: nil)
        let body = """


        ---
        ShotDex \(diagnostics.appVersion) (\(diagnostics.buildNumber))
        iOS \(diagnostics.osVersion) · \(diagnostics.deviceModel)
        """
        var components = URLComponents(string: "mailto:\(Self.supportAddress)")
        components?.queryItems = [
            URLQueryItem(name: "subject", value: "ShotDex support"),
            URLQueryItem(name: "body", value: body),
        ]
        guard let url = components?.url else { return }
        openURL(url) { accepted in
            isMailFailureAlertPresented = !accepted
        }
    }
}

/// One of this install's own threads.
private struct SupportTicketRow: View {
    let ticket: SupportTicket
    let accent: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
            Image(systemName: ticket.kind.symbolName)
                .foregroundStyle(.secondary)
                .font(.footnote)
            VStack(alignment: .leading, spacing: 2) {
                Text(ticket.title)
                    .lineLimit(2)
                HStack(spacing: AppTheme.Spacing.xs) {
                    Text(ticket.status.label)
                        .foregroundStyle(ticket.status.tint(accent: accent))
                    Text(ticket.updatedAt, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            Spacer(minLength: 0)
            if ticket.unread > 0 {
                Text(ticket.unread, format: .number)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(accent, in: Capsule())
                    .accessibilityLabel(Text("\(ticket.unread) unread replies"))
            }
        }
    }
}

/// One public request, with its vote control.
private struct SupportRoadmapRow: View {
    let item: SupportRoadmapItem
    let accent: Color
    let isVoted: Bool
    let canVote: Bool
    let onVote: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .lineLimit(3)
                Text(item.status.label)
                    .font(.caption)
                    .foregroundStyle(item.status.tint(accent: accent))
            }
            Spacer(minLength: 0)
            Button(action: onVote) {
                VStack(spacing: 1) {
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.caption)
                    Text(item.votes, format: .number)
                        .font(.caption2.monospacedDigit())
                }
                .foregroundStyle(isVoted ? accent : Color.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!canVote)
            .accessibilityLabel(isVoted ? Text("Remove your vote") : Text("Vote for this request"))
            .accessibilityValue(Text("\(item.votes) votes"))
        }
    }
}

extension SupportTicketKind: Identifiable {
    var id: String { rawValue }
}

extension SupportError: Identifiable {
    var id: String { localizedDescription }
}
