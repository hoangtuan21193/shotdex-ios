import SwiftUI

/// The saved signature library: stamp one onto this photo, or manage the list.
struct EditorSignatureSheet: View {
    let presets: [SignaturePreset]
    let onApply: (SignaturePreset) -> Void
    let onRename: (UUID, String) -> Void
    let onDelete: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var renamingID: UUID?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            Group {
                if presets.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .background(EditorTheme.panel)
            .navigationTitle("Presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Rename Signature", isPresented: isRenaming) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) { renamingID = nil }
                Button("Save") {
                    if let renamingID { onRename(renamingID, renameText) }
                    renamingID = nil
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var isRenaming: Binding<Bool> {
        Binding(
            get: { renamingID != nil },
            set: { if !$0 { renamingID = nil } }
        )
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "signature")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(EditorTheme.dimText)
            Text("No presets yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Text("Set up a caption or a logo on a photo, then use Save Preset "
                + "to keep it for the next one.")
                .font(EditorTheme.maskSubtitle)
                .foregroundStyle(EditorTheme.dimText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(presets) { preset in
                    Button {
                        onApply(preset)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "signature")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(EditorTheme.secondaryText)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .font(EditorTheme.maskTitle)
                                    .foregroundStyle(.white)
                                Text(summary(preset))
                                    .font(EditorTheme.maskSubtitle)
                                    .foregroundStyle(EditorTheme.dimText)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Text("Apply")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(EditorTheme.accent)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Rename") {
                            renameText = preset.name
                            renamingID = preset.id
                        }
                        Button("Delete", role: .destructive) { onDelete(preset.id) }
                    }
                    Rectangle()
                        .fill(EditorTheme.hairline)
                        .frame(height: 0.5)
                        .padding(.leading, 52)
                }
            }
        }
    }

    /// What the signature is made of, so two similarly named ones are told apart
    /// without applying them.
    private func summary(_ preset: SignaturePreset) -> String {
        let texts = preset.layers
            .filter { $0.kind == .text }
            .map { $0.text.replacingOccurrences(of: "\n", with: " ") }
            .filter { !$0.isEmpty }
        let imageCount = preset.layers.count { $0.kind == .image }
        var parts = texts
        if imageCount > 0 {
            parts.append(imageCount == 1 ? "1 image" : "\(imageCount) images")
        }
        return parts.isEmpty ? "\(preset.layers.count) layers" : parts.joined(separator: " · ")
    }
}
