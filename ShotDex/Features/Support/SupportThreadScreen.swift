import SwiftUI

/// One conversation: what was reported, what the team said back, and a box to
/// keep it going. This is the inbox that replaces an email address.
struct SupportThreadScreen: View {
    @Environment(\.appAccent) private var accent

    let ticket: SupportTicket
    let model: SupportModel

    @State private var reply = ""
    @State private var isSending = false

    var body: some View {
        List {
            Section {
                Text(ticket.body)
                LabeledContent("Status") {
                    Text(ticket.status.label)
                        .foregroundStyle(ticket.status.tint(accent: accent))
                }
                LabeledContent("Sent") {
                    Text(ticket.createdAt, format: .dateTime.day().month().year())
                }
            } header: {
                Text(ticket.kind.label)
            }

            if !ticket.messages.isEmpty {
                Section("Conversation") {
                    ForEach(ticket.messages) { message in
                        SupportMessageRow(message: message, accent: accent)
                    }
                }
            }

            Section {
                TextField("Add to this message", text: $reply, axis: .vertical)
                    .lineLimit(2...6)
                Button(action: send) {
                    if isSending {
                        ProgressView()
                    } else {
                        Text("Send Reply")
                    }
                }
                .disabled(isSending || reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(ticket.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.markRead(ticket) }
    }

    private func send() {
        isSending = true
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let sent = await model.reply(to: ticket, body: text)
            isSending = false
            if sent { reply = "" }
        }
    }
}

private struct SupportMessageRow: View {
    let message: SupportMessage
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.author == .team ? "ShotDex" : "You")
                .font(.caption.weight(.semibold))
                .foregroundStyle(message.author == .team ? accent : Color.secondary)
            Text(message.body)
            Text(message.createdAt, format: .dateTime.day().month().hour().minute())
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
