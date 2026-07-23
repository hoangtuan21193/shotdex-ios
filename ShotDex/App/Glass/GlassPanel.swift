import SwiftUI

/// Reusable material-blurred rounded panel for floating chrome overlays.
struct GlassPanel<Content: View>: View {
    var cornerRadius: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            // Real Liquid Glass — no manual stroke/shadow, the effect supplies
            // its own edge and depth.
            content
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        }
    }
}

#Preview {
    ZStack {
        LinearGradient(colors: [.teal, .indigo], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        GlassPanel {
            Text("Indexing 4,213 of 52,000 photos")
                .padding()
        }
    }
}
