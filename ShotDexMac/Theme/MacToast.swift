import SwiftUI

/// A short line at the foot of the window after a run that leaves no screen
/// of its own — what a Move did (FS-19.04 §2's banner). Only the front window
/// shows it; it goes after a few seconds or on a click.
struct MacToast: ViewModifier {
    @Environment(\.appearsActive) private var appearsActive
    @State private var text: String?
    @State private var hideTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let text {
                    Text(text)
                        .font(.system(size: 13))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(MacTheme.separator))
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 2)
                        .padding(.bottom, 24)
                        .onTapGesture { self.text = nil }
                        .transition(.opacity)
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            .animation(.easeOut(duration: 0.2), value: text)
            .onReceive(NotificationCenter.default.publisher(for: .macToast)) { note in
                guard appearsActive, let line = note.object as? String, !line.isEmpty else { return }
                text = line
                AccessibilityNotification.Announcement(line).post()
                hideTask?.cancel()
                hideTask = Task {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    text = nil
                }
            }
    }
}

extension Notification.Name {
    /// A line for `MacToast`, the text as the object.
    static let macToast = Notification.Name("macToast")
}
