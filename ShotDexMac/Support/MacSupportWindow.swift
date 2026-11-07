import AppKit
import SwiftUI

/// Help › ShotDex Support… (board `MAC_Support`, FS-13, FS-18.04 §6): a
/// 760×600 sheet on the Library window, not a window of its own (user
/// 2026-11-07: fewer windows) — Report a Bug… / Request a Feature…, this
/// install's threads and the public roadmap on the left, the open thread and
/// its reply box on the right; Done or Esc closes it. No account and no
/// email: the install's App Attest key is the identity, and a build that
/// cannot attest turns into mail.
struct MacSupportSheet: View {
    static let size = CGSize(width: 760, height: 600)

    @Environment(MacDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?
    @State private var composing: SupportTicketKind?

    private var model: SupportModel { dependencies.support }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                // Where the window's lights were (board): the way out.
                HStack {
                    Button(String(localized: "Done", comment: "Mac support: close the sheet")) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .controlSize(.small)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 4)
                sidebar
            }
            .frame(width: 228)
            .background(.regularMaterial)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "ShotDex Support", comment: "Mac window: support"))
        .tint(MacTheme.accent)
        .task {
            await model.refresh()
            if selection == nil { selection = model.tickets.first?.id }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Quiet: coming back to the app offline is not worth an alert.
            Task { await model.refresh(reportsErrors: false) }
        }
        .sheet(item: $composing) { kind in
            MacSupportComposeSheet(kind: kind, model: model) { title, body, log in
                let before = Set(model.tickets.map(\.id))
                let sent = await model.submit(kind: kind, title: title, body: body, logs: log)
                if sent {
                    model.composeDrafts[kind] = nil
                    selection = model.tickets.first { !before.contains($0.id) }?.id ?? selection
                    return nil
                }
                // Said inside the sheet: an alert behind it would wait for it to close.
                let message = model.error.map { [$0.errorDescription, $0.recoverySuggestion].compactMap { $0 }.joined(separator: " ") }
                model.error = nil
                return message ?? String(localized: "Couldn't send. Try again.", comment: "Mac support compose: send failed")
            }
        }
        .alert(item: Binding(get: { model.error }, set: { model.error = $0 })) { error in
            Alert(title: Text(error.errorDescription ?? ""), message: Text(error.recoverySuggestion ?? ""))
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        // No List selection: it paints system blue; rows pick and draw grey themselves.
        List {
            Group {
                composeRow(.bug, String(localized: "Report a Bug…", comment: "Mac support: write a bug report"), symbol: "ladybug")
                composeRow(.feature, String(localized: "Request a Feature…", comment: "Mac support: write a feature request"), symbol: "lightbulb")
            }
            .disabled(!model.canUsePortal)
            Section(String(localized: "Your Messages", comment: "Mac support: this install's threads")) {
                if model.tickets.isEmpty {
                    if model.lastRefreshFailed {
                        HStack {
                            Text("Couldn't load.", comment: "Mac support: the lists could not be read").font(.system(size: 12)).foregroundStyle(.secondary)
                            Button(String(localized: "Try Again", comment: "Mac support: read the lists again")) { Task { await model.refresh() } }
                                .controlSize(.small)
                        }
                    } else {
                        Text(model.hasLoadedOnce
                             ? String(localized: "Nothing sent yet.", comment: "Mac support: no threads")
                             : String(localized: "Loading…", comment: "Mac support: threads loading"))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                ForEach(model.tickets) { ticket in
                    Button { selection = ticket.id } label: { ticketRow(ticket).contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection == ticket.id ? [.isSelected] : [])
                        .accessibilityLabel(ticket.title)
                        .accessibilityValue(ticket.unread > 0
                            ? String(AttributedString(localized: "^[\(ticket.unread) unread reply](inflect: true)",
                                                      comment: "VoiceOver: a thread's unread team replies").characters)
                            : "")
                        // Grey `rowSel`, as the main sidebar — not the system blue.
                        .listRowBackground(selection == ticket.id
                                           ? RoundedRectangle(cornerRadius: 8).fill(MacTheme.rowSelection).padding(.horizontal, 8)
                                           : nil)
                }
            }
            Section(String(localized: "What People Asked For", comment: "Mac support: the public roadmap")) {
                if model.roadmap.isEmpty, model.hasLoadedOnce {
                    Text(model.lastRefreshFailed ? String(localized: "Couldn't load.", comment: "Mac support: the lists could not be read")
                                                 : String(localized: "No public requests yet.", comment: "Mac support: empty roadmap"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                ForEach(model.roadmap) { item in
                    roadmapRow(item)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Text(model.canUsePortal
                 ? "No account and no email. A message carries your words, the app and macOS version, the Mac model and roughly how many photos you have — never a photo or a name."
                 : "In this version support runs by email; the threads and votes here need the in-app channel.",
                 comment: "Mac support: what a message carries (FS-13 §6), or why the sidebar is empty in the mail fallback")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                // A width of its own: the inset proposes none, and a note
                // wrapped one word a line grew the whole window to 1,800pt.
                .frame(width: 194, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)
        }
        // Read once it has been on screen a moment — not the instant the
        // window opens on it — and again when a reply lands while it is open.
        .task(id: "\(selection ?? "")-\(model.tickets.first { $0.id == selection }?.unread ?? 0)") {
            guard let id = selection, (model.tickets.first { $0.id == id }?.unread ?? 0) > 0 else { return }
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, let ticket = model.tickets.first(where: { $0.id == id }) else { return }
            await model.markRead(ticket)
        }
    }

    private func composeRow(_ kind: SupportTicketKind, _ title: String, symbol: String) -> some View {
        Button { composing = kind } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol).foregroundStyle(MacTheme.accent)
            }
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .padding(.horizontal, 10)
            .background(MacTheme.fill, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .selectionDisabled()
        .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
    }

    private func ticketRow(_ ticket: SupportTicket) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ticket.title).font(.system(size: 13)).lineLimit(1)
                Text("\(Text(ticket.status.label)) · \(ticket.updatedAt.formatted(.relative(presentation: .named)))",
                     comment: "Mac support: a thread's status and when it last changed")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if ticket.unread > 0 {
                Text(ticket.unread.formatted())
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(MacTheme.onAccentFill)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(MacTheme.accentFill, in: Capsule())
                    .accessibilityLabel(String(AttributedString(localized: "^[\(ticket.unread) unread reply](inflect: true)",
                                                                comment: "VoiceOver: a thread's unread team replies").characters))
            }
        }
        .frame(minHeight: 34)
        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
    }

    private func roadmapRow(_ item: SupportRoadmapItem) -> some View {
        let isVoted = model.isVoted(item)
        return HStack(spacing: 6) {
            Text(item.title).font(.system(size: 12)).lineLimit(1).help(item.title)
            Spacer(minLength: 4)
            Button { Task { await model.toggleVote(item) } } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up").font(.system(size: 9, weight: .bold))
                    Text(item.votes.formatted()).monospacedDigit()
                }
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .frame(height: 20)
                .foregroundStyle(.primary)
                // Board: flat `fill` until voted, then raised `segOn` like a picked segment.
                .background {
                    if isVoted {
                        Capsule().fill(MacTheme.segmentOn).shadow(color: MacTheme.segmentShadow, radius: 1, y: 1)
                    } else {
                        Capsule().fill(MacTheme.fill)
                    }
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!model.canUsePortal || model.pendingVotes.contains(item.id))
            .opacity(model.pendingVotes.contains(item.id) ? 0.6 : 1)
            .accessibilityLabel(isVoted ? String(localized: "Remove your vote", comment: "Mac support: un-vote a public request")
                                        : String(localized: "Vote for this request", comment: "Mac support: vote for a public request"))
            .accessibilityValue(String(AttributedString(localized: "^[\(item.votes) vote](inflect: true)", comment: "VoiceOver: a request's votes").characters))
            .help(isVoted ? String(localized: "Remove your vote", comment: "Mac support: un-vote a public request")
                          : String(localized: "Vote for this request", comment: "Mac support: vote for a public request"))
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if !model.canUsePortal {
            MacSupportMailView()
        } else if let ticket = model.tickets.first(where: { $0.id == selection }) {
            MacSupportThreadView(ticket: ticket, model: model)
                .id(ticket.id)
        } else {
            VStack(spacing: 10) {
                Text(model.tickets.isEmpty
                     ? String(localized: "Nothing sent yet", comment: "Mac support: no threads, title")
                     : String(localized: "No Message Selected", comment: "Mac support: no thread selected"))
                    .font(.system(size: 15, weight: .semibold))
                Text("Report a bug or ask for a feature; replies arrive here.", comment: "Mac support: empty detail")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                HStack {
                    Button(String(localized: "Report a Bug…", comment: "Mac support: write a bug report")) { composing = .bug }
                    Button(String(localized: "Request a Feature…", comment: "Mac support: write a feature request")) { composing = .feature }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// One thread (board `MAC_Support`): title, kind · replies and status on
/// top, the first message as a card, the conversation as bubbles — the team
/// left on `card`, you right on `accentSoft` — and the reply box.
struct MacSupportThreadView: View {
    let ticket: SupportTicket
    let model: SupportModel
    @State private var reply = ""
    @State private var isSending = false
    @FocusState private var isReplyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(ticket.title).font(.system(size: 15, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                        .help(ticket.title)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(ticket.status.label)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .foregroundStyle(statusColor)
                    .background(statusColor.opacity(0.14), in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        firstMessage
                        if !ticket.messages.isEmpty {
                            Text("Conversation", comment: "Mac support: the replies under a thread's first message")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.top, 8)
                                .padding(.leading, 4)
                        }
                        ForEach(ticket.messages) { message in
                            bubble(message).id(message.id)
                        }
                        if !ticket.messages.contains(where: { $0.author == .team }) {
                            // Nothing tells the user a reply came: say where to look.
                            Text("Sent. A reply from the ShotDex team will appear here — there is no notification, so check back.",
                                 comment: "Mac support: a thread with no team reply yet")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                                .padding(.top, 4).padding(.leading, 4)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .onAppear { if let last = ticket.messages.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                .onChange(of: ticket.messages.count) {
                    if let last = ticket.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            replyBox
        }
    }

    private var subtitle: String {
        let kind = ticket.kind == .bug ? String(localized: "Bug report", comment: "Mac support: a thread's kind")
                                       : String(localized: "Feature request", comment: "Mac support: a thread's kind")
        let replies = ticket.messages.filter { $0.author == .team }.count
        return "\(kind) · " + String(AttributedString(localized: "^[\(replies) reply](inflect: true)",
                                                       comment: "Mac support: how many times the team answered").characters)
    }

    private var statusColor: Color {
        switch ticket.status {
        // `accentFill`: small amber text reaches 4.5:1 only in the darker tone.
        case .planned, .inProgress: MacTheme.accentFill
        case .shipped: MacTheme.greenText
        default: .secondary
        }
    }

    private var firstMessage: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(ticket.kind == .bug ? String(localized: "Bug", comment: "Mac support: kind chip")
                                         : String(localized: "Feature", comment: "Mac support: kind chip"))
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 6)
                    .frame(height: 16)
                    .foregroundStyle(ticket.kind == .bug ? MacTheme.redText : MacTheme.accentFill)
                    .background((ticket.kind == .bug ? MacTheme.redText : MacTheme.accentFill).opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
                Text("You · \(ticket.createdAt.formatted(date: .abbreviated, time: .omitted))",
                     comment: "Mac support: who wrote the first message and when")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text(ticket.body).font(.system(size: 13)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacTheme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func bubble(_ message: SupportMessage) -> some View {
        let isTeam = message.author == .team
        return HStack {
            if !isTeam { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 3) {
                Text(isTeam ? "ShotDex" : String(localized: "You", comment: "Mac support: your own message"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isTeam ? MacTheme.accentFill : .secondary)
                Text(message.body).font(.system(size: 13)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Text(message.createdAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 384, alignment: .leading)
            .background(isTeam ? AnyShapeStyle(MacTheme.card) : AnyShapeStyle(MacTheme.accentSoft), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)
            if isTeam { Spacer(minLength: 60) }
        }
    }

    private var replyBox: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(String(localized: "Add to this message", comment: "Mac support: reply field placeholder"), text: $reply, axis: .vertical)
                // Kept by the model: the sheet closed by Esc leaves the draft for next time.
                .onAppear { if reply.isEmpty { reply = model.replyDrafts[ticket.id] ?? "" } }
                .onChange(of: reply) { _, text in model.replyDrafts[ticket.id] = text.isEmpty ? nil : text }
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(2...5)
                .focused($isReplyFocused)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(minHeight: 52, alignment: .topLeading)
                .background(MacTheme.content, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MacTheme.separator))
                .accessibilityLabel(String(localized: "Add to this message", comment: "Mac support: reply field placeholder"))
            Button {
                send()
            } label: {
                Text("Send Reply", comment: "Mac support: send the reply").frame(minWidth: 71)
            }
            .buttonStyle(MacFilledButtonStyle())
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(trimmed.isEmpty || isSending)
            .help(String(localized: "Send Reply (⌘Return)", comment: "Mac support: Send Reply tooltip"))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .padding(.top, 4)
    }

    private var trimmed: String { reply.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func send() {
        guard !trimmed.isEmpty, !isSending else { return }
        isSending = true
        let text = trimmed
        Task {
            // Kept on failure: the alert says why, the words stay to try again.
            // Cleared only if nothing was typed while it went.
            if await model.reply(to: ticket, body: text), reply.trimmingCharacters(in: .whitespacesAndNewlines) == text { reply = "" }
            isSending = false
        }
    }
}

/// A build that cannot attest (FS-13 §2): support runs by email.
struct MacSupportMailView: View {
    @Environment(\.openURL) private var openURL
    @State private var showsNoMail = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "envelope").font(.system(size: 28)).foregroundStyle(.secondary)
            Text("Support by Email", comment: "Mac support: the mail fallback title").font(.system(size: 15, weight: .semibold))
            Text("Messages inside ShotDex aren't available in this version. Write to the address below; the reply comes back to the address you write from.",
                 comment: "Mac support: why mail")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
            Text(SupportModel.supportAddress).font(.system(size: 13, weight: .medium)).textSelection(.enabled)
            Button(String(localized: "Contact Support by Email", comment: "Mac support: open a mail to support")) { openMail() }
                .controlSize(.large)
            Text("The mail includes the app and macOS version and your Mac model.", comment: "Mac support: what the mailto body carries")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(String(localized: "No mail app set up", comment: "Mac support: mailto refused"), isPresented: $showsNoMail) {
            Button(String(localized: "Copy Address", comment: "Mac support: copy the support address")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(SupportModel.supportAddress, forType: .string)
            }
            Button(String(localized: "OK", comment: "Mac alert: dismiss"), role: .cancel) {}
        } message: {
            Text("Write to \(SupportModel.supportAddress) from wherever you read your mail.", comment: "Mac support: mailto refused")
        }
    }

    private func openMail() {
        let diagnostics = SupportDiagnostics(libraryCount: nil)
        let body = "\n\n---\nShotDex \(diagnostics.appVersion) (\(diagnostics.buildNumber)) · macOS \(diagnostics.osVersion) · \(diagnostics.deviceModel)"
        var components = URLComponents(string: "mailto:\(SupportModel.supportAddress)")
        components?.queryItems = [URLQueryItem(name: "subject", value: "ShotDex support"), URLQueryItem(name: "body", value: body)]
        guard let url = components?.url else { return }
        openURL(url) { accepted in if !accepted { showsNoMail = true } }
    }
}

/// Report a Bug… / Request a Feature… (FS-13 §5–§6): title, what happened,
/// the log you can read before it goes (on for a bug, off for a request),
/// and what else is sent.
struct MacSupportComposeSheet: View {
    let kind: SupportTicketKind
    /// Keeps the title and message when the sheet is closed unsent.
    var model: SupportModel? = nil
    /// Nil when the message reached the server, else what went wrong.
    let onSend: (String, String, String?) async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var failure: String?
    @State private var title = ""
    @State private var message = ""
    @State private var includesLog: Bool
    @State private var log: String?
    @State private var showsLog = false
    @State private var isSending = false

    init(kind: SupportTicketKind, model: SupportModel? = nil, onSend: @escaping (String, String, String?) async -> String?) {
        self.kind = kind
        self.model = model
        self.onSend = onSend
        _includesLog = State(initialValue: kind == .bug)
    }

    private func keepDraft() {
        model?.composeDrafts[kind] = title.isEmpty && message.isEmpty ? nil : (title, message)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kind == .bug ? String(localized: "Report a Bug", comment: "Mac support compose title")
                              : String(localized: "Request a Feature", comment: "Mac support compose title"))
                .font(.system(size: 15, weight: .semibold))
                // What was typed and left unsent comes back; Esc or Cancel keeps it for this launch.
                .onAppear {
                    if title.isEmpty, message.isEmpty, let draft = model?.composeDrafts[kind] {
                        title = draft.title
                        message = draft.message
                    }
                }
                .onChange(of: title) { keepDraft() }
                .onChange(of: message) { keepDraft() }
            TextField(String(localized: "Title", comment: "Mac support compose: title field"), text: $title,
                      prompt: Text(kind == .bug ? "One line: what went wrong" : "One line: what you want to do",
                                   comment: "Mac support compose: title placeholder"))
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(MacTheme.content, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MacTheme.separator))
                .accessibilityLabel(String(localized: "Title", comment: "Mac support compose: title field"))
            VStack(alignment: .leading, spacing: 4) {
                Text(kind == .bug ? String(localized: "What happened", comment: "Mac support compose: body label")
                                  : String(localized: "What you would like", comment: "Mac support compose: body label"))
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                TextEditor(text: $message)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 140)
                    .background(MacTheme.content, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MacTheme.separator))
                    .accessibilityLabel(kind == .bug ? String(localized: "What happened", comment: "Mac support compose: body label")
                                                     : String(localized: "What you would like", comment: "Mac support compose: body label"))
                Text(kind == .bug ? "What you did, what happened, and what you expected instead. Steps help most."
                                  : "What you are trying to achieve, and where in ShotDex you would look for it.",
                     comment: "Mac support compose: body hint")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack {
                Toggle(String(localized: "Include Diagnostic Log", comment: "Mac support compose: log toggle"), isOn: $includesLog)
                    .toggleStyle(.checkbox)
                if includesLog {
                    Button(String(localized: "Read the Log…", comment: "Mac support compose: show the log that will be sent")) { showsLog = true }
                        .disabled(log == nil)
                }
            }
            Text("Goes to the ShotDex team; no account needed. Replies appear in the Support window — there is no notification, so check back. The log covers the last fifteen minutes of this run only: reproduce the problem, then send. It holds no photos and no file names. Also sent: the ShotDex and macOS versions, the Mac model, your language, and roughly how many photos you have.",
                 comment: "Mac support compose: who reads it and what is sent")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                if isSending {
                    ProgressView().controlSize(.small)
                    Text("Sending…", comment: "Mac support compose: in flight").font(.system(size: 11)).foregroundStyle(.secondary)
                } else if let failure {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(failure).font(.system(size: 11)).foregroundStyle(MacTheme.redText).lineLimit(2)
                        // Still a way to the team, with what was written.
                        Button(String(localized: "Email This Instead", comment: "Mac support compose: send the report by mail")) { emailInstead() }
                            .buttonStyle(.link).font(.system(size: 11))
                    }
                }
                Spacer()
                // Never locked: a hung send can always be left.
                Button(String(localized: "Cancel", comment: "Mac sheet: cancel"), role: .cancel) { dismiss() }
                    // A send in flight answers here: closed, its failure would be told to nobody.
                    .disabled(isSending)
                    .keyboardShortcut(.cancelAction)
                Button { send() } label: {
                    Text("Send", comment: "Mac support compose: send").frame(minWidth: 56)
                }
                .buttonStyle(MacFilledButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!isSendable || isSending)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 480)
        // A sheet does not inherit the window's tint: the checkbox is amber here too.
        .tint(MacTheme.accentFill)
        .presentationBackground(MacTheme.sheet)
        // The preview reads the log as it is now; Send reads it again.
        .task(id: includesLog) {
            if includesLog, log == nil { log = await SupportLogCollector.collect() }
        }
        .onChange(of: showsLog) { _, shows in
            if shows { Task { log = await SupportLogCollector.collect() } }
        }
        .sheet(isPresented: $showsLog) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Diagnostic Log", comment: "Mac support: the log preview title").font(.system(size: 15, weight: .semibold))
                ScrollView {
                    Text(log ?? "").font(.system(size: 11).monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(MacTheme.content, in: RoundedRectangle(cornerRadius: 8))
                HStack { Spacer(); Button(String(localized: "Done", comment: "Mac sheet: done")) { showsLog = false }.keyboardShortcut(.defaultAction) }
            }
            .padding(20)
            .frame(width: 560, height: 420)
            .presentationBackground(MacTheme.sheet)
        }
    }

    @Environment(\.openURL) private var openURL

    private func emailInstead() {
        var components = URLComponents(string: "mailto:\(SupportModel.supportAddress)")
        components?.queryItems = [URLQueryItem(name: "subject", value: title), URLQueryItem(name: "body", value: message)]
        if let url = components?.url { openURL(url) }
    }

    /// Same thresholds as iOS: a title of four characters and ten of text.
    private var isSendable: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4
            && message.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
    }

    private func send() {
        guard isSendable, !isSending else { return }
        isSending = true
        failure = nil
        Task {
            // Read now, not when the sheet opened: the reproduction is in it.
            let sentLog = includesLog ? await SupportLogCollector.collect() : nil
            let problem = await onSend(title.trimmingCharacters(in: .whitespacesAndNewlines),
                                       message.trimmingCharacters(in: .whitespacesAndNewlines),
                                       sentLog)
            isSending = false
            // Stay on failure: the words are kept, the line above Send says why.
            if let problem { failure = problem } else { dismiss() }
        }
    }
}

/// The default button drawn by hand (board `MAC_Support`): `accentFill` with
/// `onAccentFill` words when on; off, label-3 words on `fill` that still
/// read — the system's disabled prominent button washes both out.
struct MacFilledButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isEnabled ? AnyShapeStyle(MacTheme.onAccentFill) : AnyShapeStyle(.tertiary))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(isEnabled ? AnyShapeStyle(MacTheme.accentFill) : AnyShapeStyle(MacTheme.fill), in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
    }
}

extension Notification.Name {
    /// Help › ShotDex Support…: the front Library window shows the sheet.
    static let macShowSupport = Notification.Name("ShotDexMacShowSupport")
}

/// A menu command for a Library window (Support, Activity) waiting for one
/// to be in front: set by the menu, taken by the first active window — so
/// it is not lost when the window has to be opened first.
@MainActor
enum MacWindowRequest {
    static var showsSupport = false
    static var showsActivity = false
}

/// The Support sheet on a Library window: Help › ShotDex Support… brings
/// that window forward and the front one shows it.
struct MacSupportSheetHost: ViewModifier {
    @State private var isPresented = false
    @Environment(\.appearsActive) private var appearsActive
    @Environment(MacDependencies.self) private var dependencies

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) { MacSupportSheet() }
            // A reply lands while the sheet is shut: the Dock says so (there is
            // no notification). Read again each time ShotDex comes forward.
            .task { await dependencies.support.refresh(reportsErrors: false) }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                Task { await dependencies.support.refresh(reportsErrors: false) }
            }
            .onChange(of: dependencies.support.unreadCount, initial: true) { _, unread in
                NSApp.dockTile.badgeLabel = unread > 0 ? unread.formatted() : nil
            }
            // Asked from the Help menu: the window in front takes the request,
            // whenever it becomes so — one opened for it included.
            .onReceive(NotificationCenter.default.publisher(for: .macShowSupport)) { _ in takeRequest() }
            .onAppear { takeRequest() }
            .onChange(of: appearsActive) { takeRequest() }
    }

    private func takeRequest() {
        guard appearsActive, MacWindowRequest.showsSupport else { return }
        MacWindowRequest.showsSupport = false
        isPresented = true
    }
}
