import SwiftUI

/// The alert Edit shows in place of the editor for a RAW this iOS build
/// can't read (FS-03.04b §3) — before anything is loaded or downloaded.
/// A modifier so the viewer's long body stays within the type checker.
struct UnsupportedRAWAlert: ViewModifier {
    @Binding var message: UnsupportedRAWMessage?

    func body(content: Content) -> some View {
        content.alert(
            message?.title ?? "",
            isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } }),
            presenting: message
        ) { _ in
            Button("OK", role: .cancel) { message = nil }
        } message: { message in
            Text(message.text)
        }
    }
}

extension View {
    func unsupportedRAWAlert(_ message: Binding<UnsupportedRAWMessage?>) -> some View {
        modifier(UnsupportedRAWAlert(message: message))
    }
}
