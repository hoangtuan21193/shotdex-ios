import SwiftUI

/// Writing one bug report or feature request.
///
/// The log toggle shows the log itself rather than describing it: sending
/// somebody your diagnostics without being able to read them first is the part
/// of "send logs to the developer" that people are right to distrust.
struct SupportComposeScreen: View {
    @Environment(\.dismiss) private var dismiss

    let kind: SupportTicketKind
    /// Returns true when the message reached the server.
    let onSend: (String, String, String?) async -> Bool

    @State private var title = ""
    @State private var message = ""
    @State private var includesLog: Bool
    @State private var log: String?
    @State private var isLogPresented = false
    @State private var isSending = false
    @FocusState private var isTitleFocused: Bool

    init(kind: SupportTicketKind, onSend: @escaping (String, String, String?) async -> Bool) {
        self.kind = kind
        self.onSend = onSend
        // A crash or a stall is worth a log; a feature request is not, and
        // sending one by default would be collecting what is not needed.
        _includesLog = State(initialValue: kind == .bug)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(titlePrompt, text: $title, axis: .vertical)
                        .lineLimit(1...2)
                        .focused($isTitleFocused)
                } header: {
                    Text("Title")
                }

                Section {
                    TextEditor(text: $message)
                        .frame(minHeight: 160)
                        .font(.body)
                } header: {
                    Text(kind == .bug ? "What happened" : "What you would like")
                } footer: {
                    Text(bodyPrompt)
                }

                logSection
                diagnosticsSection
            }
            .navigationTitle(kind == .bug ? "Report a Bug" : "Request a Feature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Send", action: send)
                            .disabled(!isSendable)
                    }
                }
            }
            .task {
                isTitleFocused = true
                if includesLog { await loadLog() }
            }
            .onChange(of: includesLog) { _, isOn in
                if isOn && log == nil {
                    Task { await loadLog() }
                }
            }
            .sheet(isPresented: $isLogPresented) {
                SupportLogPreview(text: log ?? "")
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var logSection: some View {
        Section {
            Toggle("Include Diagnostic Log", isOn: $includesLog)
            if includesLog {
                Button("Read the Log") { isLogPresented = true }
                    .disabled(log == nil)
            }
        } footer: {
            Text("The log covers the last fifteen minutes of this session only — iOS does not keep it across launches. Reproduce the problem, then send. It holds no photos and no file names.")
        }
    }

    private var diagnosticsSection: some View {
        Section {
            Text("Also sent: the ShotDex and iOS versions, the device model, your language, and roughly how many photos you have.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Behaviour

    private var isSendable: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4
            && message.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
    }

    private var titlePrompt: LocalizedStringKey {
        kind == .bug ? "One line: what went wrong" : "One line: what you want to do"
    }

    private var bodyPrompt: LocalizedStringKey {
        kind == .bug
            ? "What you did, what happened, and what you expected instead. Steps help most."
            : "What you are trying to achieve, and where in ShotDex you would look for it."
    }

    private func loadLog() async {
        log = await SupportLogCollector.collect()
    }

    private func send() {
        isSending = true
        Task {
            let sent = await onSend(
                title.trimmingCharacters(in: .whitespacesAndNewlines),
                message.trimmingCharacters(in: .whitespacesAndNewlines),
                includesLog ? log : nil
            )
            isSending = false
            // Stay put on failure: the alert belongs to the screen underneath,
            // but dismissing would throw away what they just wrote.
            if sent { dismiss() }
        }
    }
}

/// The log, exactly as it will be sent.
private struct SupportLogPreview: View {
    @Environment(\.dismiss) private var dismiss
    let text: String

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppTheme.Spacing.md)
            }
            .navigationTitle("Diagnostic Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
