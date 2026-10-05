import SwiftUI
import ShotDexKit

/// The controls the Video Studio's contextual sheets are built from: one slider
/// row, the overlay colour/animation/alignment strips, and the project-wide
/// ratio / background / filter strips.

/// Wraps the editor's one slider with the studio's undo grouping so every param
/// row reads and behaves like the photo editor's.
struct InspectorSlider: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let valueText: String
    var anchor: Double = 0
    var notch = false
    var detent: Double?
    let model: VideoStudioModel
    let set: (Double) -> Void
    let reset: () -> Void

    var body: some View {
        EditorValueSlider(
            label: label, value: value, range: range, valueText: valueText,
            isActive: false, anchor: anchor, showsAnchorNotch: notch, detent: detent,
            onBeginDrag: { model.beginUndoGroup() },
            onDrag: set,
            onEndDrag: { _, _, _ in model.endUndoGroup() },
            onReset: reset
        )
    }
}

/// A Volume row with its speaker (FS-12.04b §5): a 26pt disc on white 10 %
/// at the head of the row mutes and unmutes; muted, the slider dims to 30 %
/// and keeps its number, so unmuting returns the level it had.
struct MutableVolumeRow: View {
    let isMuted: Bool
    let volume: Double
    let model: VideoStudioModel
    let toggleMute: () -> Void
    let set: (Double) -> Void
    let reset: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: toggleMute) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: VideoStudioMetrics.muteDisc, height: VideoStudioMetrics.muteDisc)
                    .background(Circle().fill(Color.white.opacity(0.10)))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .accessibilityLabel(isMuted ? VideoStudioCopy.unmute : VideoStudioCopy.mute)
            InspectorSlider(
                label: "Volume", value: volume, range: 0...1,
                valueText: "\(Int(volume * 100))", model: model,
                set: set, reset: reset
            )
            .opacity(isMuted ? 0.3 : 1)
        }
    }
}

/// The caption's own words, first row of the text panel. Single-line inline
/// editing covers most captions; the expand button hands off to the full-screen
/// editor for multi-line ones.
struct OverlayTextField: View {
    @Bindable var model: VideoStudioModel
    let overlay: PhotoOverlay
    let onExpand: () -> Void
    /// Edit: the field takes focus as it appears, so the keyboard is up.
    var focusesOnAppear = false

    @FocusState private var isFocused: Bool
    /// Local mirror: routing every keystroke through the recipe and back makes
    /// the field fight the caret, so the text is pushed one way while typing and
    /// re-seeded when a different overlay is selected.
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField("Text", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .foregroundStyle(.white)
                .tint(EditorTheme.accent)
                .submitLabel(.done)
                .focused($isFocused)
                .task(id: overlay.id) {
                    draft = overlay.text
                    if focusesOnAppear { isFocused = true }
                }
                // The full-screen editor and undo change the caption behind this
                // field's back; without this the row kept showing the placeholder
                // while the title row showed the words.
                .onChange(of: overlay.text) { if overlay.text != draft { draft = overlay.text } }
                .onChange(of: draft) {
                    guard draft != overlay.text else { return }
                    model.updateSelectedOverlay { $0.text = draft }
                }
                // One undo step per editing session, like the sliders.
                .onChange(of: isFocused) { if isFocused { model.beginUndoGroup() } else { model.endUndoGroup() } }

            Button(action: onExpand) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EditorTheme.dimText)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit text full screen")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }
}

/// The colour swatches an overlay's fill or outline is set from — the greys a
/// caption is usually one of, plus a few vivid tints. Horizontally scrollable so
/// the row never overflows the sheet. No system `ColorPicker`, matching the rest
/// of the app.
struct OverlaySwatchRow: View {
    @Bindable var model: VideoStudioModel
    let selected: OverlayColor
    let set: (OverlayColor) -> Void

    private static let swatches: [OverlayColor] = [
        .white,
        OverlayColor(white: 0.6),
        .black,
        OverlayColor(red: 0.92, green: 0.27, blue: 0.24),
        OverlayColor(red: 0.96, green: 0.62, blue: 0.20),
        OverlayColor(red: 1.0, green: 0.84, blue: 0.25),
        OverlayColor(red: 0.36, green: 0.72, blue: 0.42),
        OverlayColor(red: 0.30, green: 0.55, blue: 0.90),
        OverlayColor(red: 0.96, green: 0.86, blue: 0.66),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(Self.swatches.enumerated()), id: \.offset) { pair in
                    swatch(pair.element)
                }
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 44)
    }

    private func swatch(_ color: OverlayColor) -> some View {
        let isSelected = isClose(color, selected)
        return Button {
            model.pushUndo(); set(color)
        } label: {
            Circle()
                .fill(Color(red: color.red, green: color.green, blue: color.blue))
                .frame(width: 26, height: 26)
                .overlay { Circle().strokeBorder(EditorTheme.hairline, lineWidth: 1) }
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(EditorTheme.accent, lineWidth: 2).frame(width: 33, height: 33)
                    }
                }
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func isClose(_ a: OverlayColor, _ b: OverlayColor) -> Bool {
        abs(a.red - b.red) < 0.02 && abs(a.green - b.green) < 0.02 && abs(a.blue - b.blue) < 0.02
    }
}

/// A titled horizontal strip of animation choices (None / Fade / Slide… / Pop),
/// for the in ramp or the out ramp.
struct OverlayAnimationRow: View {
    let title: LocalizedStringKey
    let selected: OverlayAnimation
    let set: (OverlayAnimation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(EditorTheme.dimText)
                .padding(.leading, 14)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(OverlayAnimation.allCases) { kind in
                        chip(kind)
                    }
                }
                .padding(.horizontal, 14)
            }
        }
    }

    private func chip(_ kind: OverlayAnimation) -> some View {
        let isSelected = kind == selected
        return Button { set(kind) } label: {
            VStack(spacing: 4) {
                Image(systemName: kind.systemImage).font(.system(size: 16, weight: .regular))
                // Same reason as the command cells: a 54pt chip fits the
                // English word and not its translation.
                Text(kind.displayName)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isSelected ? EditorTheme.accent : .white)
            .frame(width: 54, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? EditorTheme.accent.opacity(0.18) : Color.white.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The clip's motion / look effect as a chip strip — every option visible and
/// named, where the old Animate command cycled blindly through them. Fills the
/// param zone a photo clip (Duration only) left mostly empty.
/// A pop-up button (FS-12.04b §6 on the iPad, the Mac-style canvas): one
/// choice of many as "Motion: Zoom In ⌃⌄", 44 tall on white 8 %, radius 12,
/// opening a menu of every option with the current one checked. The iPhone
/// and the Duo show the same options as chips; both are built from one list.
struct VideoPopUpButton<Option: Hashable>: View {
    let title: String
    let options: [Option]
    let selected: Option
    let name: (Option) -> String
    let set: (Option) -> Void
    /// Rows after the options — "More Fonts…".
    var extra: (title: String, action: () -> Void)? = nil
    /// Where a label beside it already names it (the Video Settings form's
    /// "Ratio"), the button shows only the value; VoiceOver still hears both.
    var showsTitle = true
    /// A glyph before the value — the ratio's own shape.
    var glyph: ((Option) -> AnyView)? = nil

    var body: some View {
        Menu {
            Picker(selection: Binding(get: { selected }, set: { set($0) })) {
                ForEach(options, id: \.self) { option in
                    Text(verbatim: name(option)).tag(option)
                }
            } label: {
                Text(verbatim: title)
            }
            .pickerStyle(.inline)
            if let extra {
                Divider()
                Button(extra.title, action: extra.action)
            }
        } label: {
            HStack(spacing: 8) {
                if let glyph { glyph(selected) }
                Text(verbatim: showsTitle ? "\(title): \(name(selected))" : name(selected))
                    .font(.system(size: 17))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: VideoStudioMetrics.popUpHeight)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous).fill(Color.white.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(verbatim: "\(title): \(name(selected))"))
    }
}

struct ClipEffectRow: View {
    let selected: VideoClipEffect
    let set: (VideoClipEffect) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Motion", tableName: VideoStudioCopy.table, comment: "Video Studio clip panel: header over the clip's motion effects — zoom, pan, shake")
                .textCase(.uppercase)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(EditorTheme.dimText)
                .padding(.leading, 14)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(VideoClipPanelSections.motionOptions) { effect in
                        chip(effect)
                    }
                }
                .padding(.horizontal, 14)
            }
        }
    }

    private func chip(_ effect: VideoClipEffect) -> some View {
        let isSelected = effect == selected
        return Button { set(effect) } label: {
            VStack(spacing: 4) {
                Image(systemName: effect.systemImage).font(.system(size: 16, weight: .regular))
                Text(effect.displayName)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isSelected ? EditorTheme.accent : .white)
            .frame(width: 54, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? EditorTheme.accent.opacity(0.18) : Color.white.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(effect.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Leading / centre / trailing alignment for a multi-line caption.
struct OverlayAlignmentRow: View {
    @Bindable var model: VideoStudioModel
    let selected: OverlayTextAlignment

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OverlayTextAlignment.allCases) { alignment in
                let isSelected = alignment == selected
                Button {
                    model.pushUndo(); model.updateSelectedOverlay { $0.alignment = alignment }
                } label: {
                    Image(systemName: alignment.systemImage)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isSelected ? EditorTheme.accent : .white)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? EditorTheme.accent.opacity(0.18) : Color.white.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(alignment.rawValue)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }
}

