import SwiftUI

/// Types a caption straight over the photo, the way Snapseed's Text tool does,
/// rather than in a sheet that slides up and hides the picture.
///
/// A full-stage layer: the photo dims behind, a large centred field takes the
/// middle with the keyboard under it, and Cancel / Done sit up top level with the
/// Dynamic Island — the same shape as the drawing sub-mode's bar. The token chips
/// ride above the keyboard, which is the one reason ShotDex's text entry earns more
/// than a bare field: they are how a caption becomes reusable across photos.
struct EditorInlineTextEditor: View {
    let initialText: String
    let tokens: OverlayTokenValues
    let alignment: OverlayTextAlignment
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(
        initialText: String,
        tokens: OverlayTokenValues,
        alignment: OverlayTextAlignment,
        onCommit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialText = initialText
        self.tokens = tokens
        self.alignment = alignment
        self.onCommit = onCommit
        self.onCancel = onCancel
        _text = State(initialValue: initialText)
    }

    var body: some View {
        ZStack {
            // Dims the photo so the words are the only bright thing, and swallows
            // touches so nothing behind reacts while typing.
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { isFocused = true }

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                field
                if OverlayTokenResolver.containsKnownToken(text) {
                    preview
                }
                Spacer(minLength: 0)
            }
        }
        .safeAreaInset(edge: .bottom) { tokenBar }
        .onAppear { isFocused = true }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button("Cancel") { onCancel() }
                .font(.system(size: 16))
                .foregroundStyle(EditorTheme.secondaryText)
                .frame(minWidth: 56, minHeight: 44, alignment: .leading)

            Spacer(minLength: 0)

            Button("Done") { onCommit(text) }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(EditorTheme.accent)
                .frame(minWidth: 52, minHeight: 44, alignment: .trailing)
        }
        .padding(.horizontal, 26)
        .padding(.top, EditorLayoutMetrics.dynamicIslandRowTopInset)
    }

    /// A borderless multi-line field, centred and large, so it reads as writing on
    /// the photo rather than filling in a form. `TextEditor` over `TextField`: a
    /// caption is routinely two or three lines.
    private var field: some View {
        TextEditor(text: $text)
            .font(.system(size: 30, weight: .semibold))
            .multilineTextAlignment(textAlignment)
            .foregroundStyle(.white)
            .tint(EditorTheme.accent)
            .scrollContentBackground(.hidden)
            .background(.clear)
            .focused($isFocused)
            .frame(maxHeight: 220)
            .padding(.horizontal, 24)
            .shadow(color: .black.opacity(0.5), radius: 6, y: 1)
    }

    /// What the tokens expand to on *this* photo, shown live so a caption full of
    /// braces is not written blind.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ON THIS PHOTO")
                .font(EditorTheme.groupLabel)
                .tracking(1.1)
                .foregroundStyle(EditorTheme.secondaryText)
            Text(resolved.isEmpty ? "Nothing — this photo has none of these values." : resolved)
                .font(.system(size: 15))
                .foregroundStyle(resolved.isEmpty ? EditorTheme.clipping : .white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(EditorTheme.control.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }

    private var resolved: String {
        OverlayTokenResolver.resolve(text, values: tokens)
    }

    /// Token chips above the keyboard: tapping one drops its placeholder into the
    /// caption. Appended rather than inserted at the caret — `TextEditor` does not
    /// expose a selection, and a token landing mid-word is worse than one at the end
    /// where the finger already is.
    private var tokenBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(EditorTheme.hairline).frame(height: 0.5)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(OverlayToken.allCases) { token in
                        Button {
                            insert(token)
                        } label: {
                            VStack(spacing: 1) {
                                Text(token.displayName)
                                    .font(.system(size: 12, weight: .medium))
                                Text(tokens.value(for: token) ?? "—")
                                    .font(.system(size: 10))
                                    .foregroundStyle(
                                        tokens.value(for: token) == nil
                                            ? EditorTheme.dimText
                                            : EditorTheme.secondaryText
                                    )
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(EditorTheme.control, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .background(EditorTheme.panel)
    }

    private var textAlignment: TextAlignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private func insert(_ token: OverlayToken) {
        if !text.isEmpty, !text.hasSuffix(" "), !text.hasSuffix("\n") {
            text += " "
        }
        text += token.placeholder
    }
}
