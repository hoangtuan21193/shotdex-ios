import SwiftUI
import UIKit

/// Picks a typeface from everything installed on the device.
///
/// `UIFontPickerViewController` rather than a hand-rolled list over
/// `UIFont.familyNames`: it searches, it previews every face in its own typeface,
/// it handles fonts installed by other apps and downloadable ones, and it needs no
/// maintenance as iOS ships new families. A custom list would be a worse copy of
/// it, and this is the one screen in the editor where the platform control is
/// straightforwardly better than anything built here.
///
/// The recents row above it exists because the picker is a long list: with every
/// installed family in it, re-finding the same face for the next photo is the slow
/// part, not choosing it the first time.
struct EditorFontPickerSheet: View {
    let recents: [OverlayFontChoice]
    let current: OverlayFontChoice
    let onPick: (OverlayFontChoice) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !recents.isEmpty {
                    recentsSection
                }
                FontPickerRepresentable { choice in
                    onPick(choice)
                    dismiss()
                }
            }
            .background(EditorTheme.panel)
            .navigationTitle("Font")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENT")
                .font(EditorTheme.groupLabel)
                .tracking(1.1)
                .foregroundStyle(EditorTheme.secondaryText)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(recents) { choice in
                        let isSelected = choice.postScriptName == current.postScriptName
                        Button {
                            onPick(choice)
                            dismiss()
                        } label: {
                            Text(choice.displayName)
                                // Drawn in its own face, the way the system picker
                                // does: the name of a typeface is not what you are
                                // choosing between.
                                .font(preview(for: choice))
                                .lineLimit(1)
                                .foregroundStyle(isSelected ? .white : EditorTheme.secondaryText)
                                .padding(.horizontal, 14)
                                .frame(height: 40)
                                .background(
                                    isSelected ? EditorTheme.accent : EditorTheme.control,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 12)
    }

    private func preview(for choice: OverlayFontChoice) -> Font {
        guard !choice.postScriptName.isEmpty,
              let font = UIFont(name: choice.postScriptName, size: 15)
        else { return .system(size: 15) }
        return Font(font)
    }
}

private struct FontPickerRepresentable: UIViewControllerRepresentable {
    let onPick: (OverlayFontChoice) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIFontPickerViewController {
        let configuration = UIFontPickerViewController.Configuration()
        // Faces, not just families: a signature set in Helvetica Light is not the
        // same signature as one in Helvetica Bold, and the recipe stores a face.
        configuration.includeFaces = true
        let controller = UIFontPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIFontPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIFontPickerViewControllerDelegate {
        private let onPick: (OverlayFontChoice) -> Void

        init(onPick: @escaping (OverlayFontChoice) -> Void) {
            self.onPick = onPick
        }

        func fontPickerViewControllerDidPickFont(_ controller: UIFontPickerViewController) {
            guard let descriptor = controller.selectedFontDescriptor else { return }
            // `postscriptName` is empty when the user picked a family rather than a
            // face, so a concrete face is resolved before the choice is stored — the
            // renderer needs a name it can look up.
            let family = descriptor.object(forKey: .family) as? String ?? ""
            let postScriptName = descriptor.postscriptName.isEmpty
                ? UIFont(descriptor: descriptor, size: 20).fontName
                : descriptor.postscriptName
            let visible = descriptor.object(forKey: .visibleName) as? String
            onPick(
                OverlayFontChoice(
                    postScriptName: postScriptName,
                    familyName: family,
                    displayName: visible ?? (family.isEmpty ? postScriptName : family)
                )
            )
        }
    }
}
