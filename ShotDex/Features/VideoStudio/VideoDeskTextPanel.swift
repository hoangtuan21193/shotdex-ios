import SwiftUI
import ShotDexKit

/// A caption's controls on the iPad (FS-12.04b §4, boards IL3_TextOverlay and
/// IP3_TextOverlay): every section at once — the words, Font with B · I,
/// Align, Size, Opacity, Color, Style, Animate — instead of the phone's one
/// tool at a time. The inspector is 584 tall and the dock 1000 wide: there is
/// room to see a caption's whole look while changing one part of it.
///
/// The command row still lights the cell last tapped; in the inspector the
/// tap brings that section to the top, Edit puts the cursor in the field.
/// The dock shows its three columns whole, so a tap there only lights.
struct VideoDeskTextPanel: View {
    @Bindable var model: VideoStudioModel
    let overlay: PhotoOverlay
    let actions: VideoInspectorActions
    /// The portrait dock's three columns of 312, else the 360 inspector.
    let isDock: Bool

    /// The sections, top to bottom in the inspector, each a scroll target
    /// a command cell can bring up (FS-12.04b §4).
    enum Section: Hashable, CaseIterable {
        case text, font, align, color, style, animate, spacing

        /// The command cell that brings this section up.
        init(_ tool: VideoStudioModel.TextTool) {
            switch tool {
            case .edit, .transform: self = .text
            case .font: self = .font
            case .align: self = .align
            case .color: self = .color
            case .style: self = .style
            case .animate: self = .animate
            }
        }
    }

    var body: some View {
        if isDock { dockBody } else { inspectorBody }
    }

    // MARK: Inspector (IL3_TextOverlay)

    /// One column, read top to bottom: the board's rows sit where it draws
    /// them (Text 150, Font 202, Align 254, Size 298, Color 392, Style 472,
    /// Animate 596); Tracking, Line Spacing and Starts At follow, past the
    /// fold.
    private var inspectorBody: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    textField.padding(.top, 3).id(Section.text)
                    fontPopUp.padding(.top, 8).id(Section.font)
                    HStack(spacing: 0) {
                        alignment
                        Color.clear.frame(width: 12)
                        boldItalic
                        Spacer(minLength: 0)
                    }
                    .frame(height: 44)
                    .padding(.top, 4)
                    .id(Section.align)
                    sizeSlider.padding(.top, 4)
                    opacitySlider
                    header(Text("Color")).padding(.top, 6).id(Section.color)
                    fillSwatches
                    header(Text("Style")).padding(.top, 8).id(Section.style)
                    styleRows
                    header(Text("Animate")).padding(.top, 8).id(Section.animate)
                    animateRows.padding(.top, 2)
                    header(Text(VideoStudioCopy.textSpacing)).padding(.top, 8).id(Section.spacing)
                    spacingRows
                    startsAtSlider
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .onChange(of: model.inspectorTextTool) { _, tool in
                withAnimation(EditorTheme.animation) { proxy.scrollTo(Section(tool), anchor: .top) }
            }
        }
    }

    // MARK: Dock (IP3_TextOverlay)

    /// Three columns, all seen at once: the words, Font · B · I, Size | Color,
    /// Align, Opacity | Style, Animate. Rows past the dock's 187 scroll in
    /// their own column.
    private var dockBody: some View {
        DockColumns(gap: VideoStudioDeskGeometry.dockColumnGap) {
            column {
                textField
                HStack(spacing: 0) {
                    fontPopUp.frame(width: 212)
                    Color.clear.frame(width: 8)
                    boldItalic
                    Spacer(minLength: 0)
                }
                .padding(.top, 8)
                sizeSlider.padding(.top, 8)
                startsAtSlider
            }
        } second: {
            column {
                dockHeader(Text("Color"))
                fillSwatches
                HStack(spacing: 0) { alignment; Spacer(minLength: 0) }.padding(.top, 6)
                opacitySlider.padding(.top, 6)
                spacingRows
            }
        } third: {
            column {
                dockHeader(Text("Style"))
                styleRows
                animateRows.padding(.top, 8)
            }
        }
        .frame(height: VideoStudioDeskGeometry.dockParamHeight)
    }

    private func column<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.bottom, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: Rows

    /// The words, with the full-screen editor's button; Edit gives it the
    /// cursor (a new field takes focus as it appears).
    private var textField: some View {
        OverlayTextField(
            model: model, overlay: overlay,
            onExpand: { actions.onEditText(overlay) },
            focusesOnAppear: model.inspectorTextTool == .edit,
            isDesk: true
        )
        .id("\(overlay.id)-\(model.inspectorTextTool == .edit)")
    }

    /// "Font: SF Pro ⌃⌄" — the fonts used before, then More Fonts….
    private var fontPopUp: some View {
        let recents = model.fontRecents
        var families = recents.map(\.familyName)
        if !families.contains(overlay.fontFamilyName) { families.insert(overlay.fontFamilyName, at: 0) }
        return VideoPopUpButton(
            title: VideoStudioCopy.font,
            options: families,
            selected: overlay.fontFamilyName,
            name: { $0.isEmpty ? String(localized: "System") : $0 },
            set: { family in
                guard let choice = recents.first(where: { $0.familyName == family }) else { return }
                model.rememberFont(choice)
                model.updateSelectedOverlay {
                    $0.fontPostScriptName = choice.postScriptName
                    $0.fontFamilyName = choice.familyName
                }
            },
            extra: (VideoStudioCopy.moreFonts, actions.onPickFont)
        )
    }

    private var boldItalic: some View {
        HStack(spacing: 4) {
            toggle("B", isOn: overlay.isBold, label: Text("Bold")) {
                model.pushUndo(); model.updateSelectedOverlay { $0.isBold.toggle() }
            }
            toggle("I", isOn: overlay.isItalic, label: Text("Italic")) {
                model.pushUndo(); model.updateSelectedOverlay { $0.isItalic.toggle() }
            }
        }
    }

    /// B, I: 44pt squares, white 20 % while on.
    private func toggle(_ glyph: String, isOn: Bool, label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: glyph)
                .font(.system(size: 17, weight: glyph == "B" ? .bold : .regular))
                .italic(glyph == "I")
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .fill(Color.white.opacity(isOn ? 0.20 : 0.08))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// Leading · Center · Trailing as the iPad's 180×36 segmented control.
    private var alignment: some View {
        HStack(spacing: 2) {
            ForEach(OverlayTextAlignment.allCases) { value in
                let isOn = value == overlay.alignment
                Button {
                    model.pushUndo(); model.updateSelectedOverlay { $0.alignment = value }
                } label: {
                    Image(systemName: value.systemImage)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isOn ? Color.white.opacity(0.20) : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(VideoStudioCopy.alignment(value))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(2)
        .frame(width: 180, height: 36)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Align"))
    }

    private var sizeSlider: some View {
        row(InspectorSlider(
            label: "Size", value: overlay.size, range: 0.02...0.4,
            valueText: String(format: "%.0f", overlay.size * 1000), model: model,
            set: { newValue in model.updateSelectedOverlay { $0.size = newValue } },
            reset: { model.pushUndo(); model.updateSelectedOverlay { $0.size = 0.05 } }
        ))
    }

    private var opacitySlider: some View {
        row(InspectorSlider(
            label: "Opacity", value: overlay.opacity, range: 0...1,
            valueText: "\(Int(overlay.opacity * 100))", model: model,
            set: { newValue in model.updateSelectedOverlay { $0.opacity = newValue } },
            reset: { model.pushUndo(); model.updateSelectedOverlay { $0.opacity = 1 } }
        ))
    }

    private var fillSwatches: some View {
        OverlaySwatchRow(model: model, selected: overlay.fill) { color in
            model.updateSelectedOverlay { $0.fill = color }
        }
        .padding(.horizontal, -14)
    }

    /// Outline (and its colours once there is one), Shadow (and its Blur
    /// once it shows) — the two ways to lift a caption off a busy frame.
    @ViewBuilder
    private var styleRows: some View {
        row(InspectorSlider(
            label: "Outline", value: overlay.outlineWidth, range: 0...0.15,
            valueText: String(format: "%.0f", overlay.outlineWidth * 100), model: model,
            set: { newValue in model.updateSelectedOverlay { $0.outlineWidth = newValue } },
            reset: { model.pushUndo(); model.updateSelectedOverlay { $0.outlineWidth = 0 } }
        ))
        if overlay.outlineWidth > 0.0005 {
            OverlaySwatchRow(model: model, selected: overlay.outlineColor) { color in
                model.updateSelectedOverlay { $0.outlineColor = color }
            }
            .padding(.horizontal, -14)
        }
        row(InspectorSlider(
            label: "Shadow", value: overlay.shadowOpacity, range: 0...1,
            valueText: "\(Int(overlay.shadowOpacity * 100))", model: model,
            set: { newValue in
                model.updateSelectedOverlay {
                    $0.shadowOpacity = newValue
                    // A shadow with zero blur and zero offset is invisible;
                    // seed sensible geometry the first time it is turned up.
                    if newValue > 0.001, $0.shadowRadius == 0, $0.shadowOffsetY == 0 {
                        $0.shadowRadius = 0.06
                        $0.shadowOffsetY = 0.03
                    }
                }
            },
            reset: { model.pushUndo(); model.updateSelectedOverlay { $0.shadowOpacity = 0 } }
        ))
        if overlay.shadowOpacity > 0.001 {
            row(InspectorSlider(
                label: "Blur", value: overlay.shadowRadius, range: 0...0.2,
                valueText: String(format: "%.0f", overlay.shadowRadius * 100), model: model,
                set: { newValue in model.updateSelectedOverlay { $0.shadowRadius = newValue } },
                reset: { model.pushUndo(); model.updateSelectedOverlay { $0.shadowRadius = 0.06 } }
            ))
        }
    }

    /// Animate In · Animate Out side by side, and each one's length once
    /// it is not None.
    @ViewBuilder
    private var animateRows: some View {
        let timed = model.selectedTimedOverlay
        HStack(spacing: 8) {
            VideoPopUpButton(
                title: VideoStudioCopy.animateIn,
                options: OverlayAnimation.allCases,
                selected: timed?.animateIn ?? .none,
                name: \.displayName,
                set: { kind in
                    model.pushUndo()
                    model.updateSelectedTimedOverlay { $0.animateIn = kind }
                },
                visibleTitle: VideoStudioCopy.animateInShort
            )
            VideoPopUpButton(
                title: VideoStudioCopy.animateOut,
                options: OverlayAnimation.allCases,
                selected: timed?.animateOut ?? .none,
                name: \.displayName,
                set: { kind in
                    model.pushUndo()
                    model.updateSelectedTimedOverlay { $0.animateOut = kind }
                },
                visibleTitle: VideoStudioCopy.animateOutShort
            )
        }
        if (timed?.animateIn ?? .none) != .none {
            row(InspectorSlider(
                label: "In time", value: timed?.inDuration ?? 0.4, range: 0.1...2,
                valueText: String(format: "%.1fs", timed?.inDuration ?? 0.4), model: model,
                set: { newValue in model.updateSelectedTimedOverlay { $0.inDuration = newValue } },
                reset: { model.pushUndo(); model.updateSelectedTimedOverlay { $0.inDuration = 0.4 } }
            ))
        }
        if (timed?.animateOut ?? .none) != .none {
            row(InspectorSlider(
                label: "Out time", value: timed?.outDuration ?? 0.4, range: 0.1...2,
                valueText: String(format: "%.1fs", timed?.outDuration ?? 0.4), model: model,
                set: { newValue in model.updateSelectedTimedOverlay { $0.outDuration = newValue } },
                reset: { model.pushUndo(); model.updateSelectedTimedOverlay { $0.outDuration = 0.4 } }
            ))
        }
    }

    @ViewBuilder
    private var spacingRows: some View {
        row(InspectorSlider(
            label: "Tracking", value: overlay.tracking, range: -0.1...0.4,
            valueText: String(format: "%+.0f", overlay.tracking * 100),
            anchor: 0, notch: true, detent: 0, model: model,
            set: { newValue in model.updateSelectedOverlay { $0.tracking = newValue } },
            reset: { model.pushUndo(); model.updateSelectedOverlay { $0.tracking = 0 } }
        ))
        row(InspectorSlider(
            label: "Line spacing", value: overlay.lineSpacing, range: 0...0.6,
            valueText: String(format: "%.0f", overlay.lineSpacing * 100), model: model,
            set: { newValue in model.updateSelectedOverlay { $0.lineSpacing = newValue } },
            reset: { model.pushUndo(); model.updateSelectedOverlay { $0.lineSpacing = 0.15 } }
        ))
    }

    private var startsAtSlider: some View {
        let timed = model.selectedTimedOverlay
        let start = timed?.start ?? 0
        return row(InspectorSlider(
            label: "Starts at", value: start, range: 0...max(0.1, model.totalDuration),
            valueText: String(format: "%.1fs", start), model: model,
            set: { newValue in model.setOverlayTiming(start: newValue, duration: timed?.duration, forOverlay: overlay.id) },
            reset: { model.pushUndo(); model.setOverlayTiming(start: 0, duration: timed?.duration, forOverlay: overlay.id) }
        ))
    }

    /// A slider in the boards' 44pt row; the shared slider row brings its
    /// own 14 inset, so it steps out by that much to line its name up.
    private func row(_ slider: InspectorSlider) -> some View {
        slider
            .frame(height: 44)
            .padding(.horizontal, -14)
    }

    /// Title Case, 28 tall in the inspector (FS-12.04b §4).
    private func header(_ title: Text) -> some View {
        title
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(height: VideoStudioMetrics.deskSectionTitleHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    /// The dock's column titles, 24 tall at the column's top (IP3).
    private func dockHeader(_ title: Text) -> some View {
        title
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(height: 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

extension VideoStudioCopy {
    /// The iPad caption inspector's last section (FS-12.04b §4): Tracking
    /// and Line Spacing, after the rows the boards draw.
    static var textSpacing: String {
        String(localized: "Spacing", table: table, comment: "Video Studio iPad text inspector: section title over Tracking and Line spacing")
    }
}

extension VideoStudioCopy {
    /// On the button beside Animate Out: "In: Fade" (IL3, IP3).
    static var animateInShort: String {
        String(localized: "In", table: table, comment: "Video Studio clip panel: the fade-in slider under FADE; also the short title on the iPad text inspector's Animate In pop-up — In: Fade")
    }

    static var animateOutShort: String {
        String(localized: "Out", table: table, comment: "Video Studio clip panel: the fade-out slider under FADE; also the short title on the iPad text inspector's Animate Out pop-up — Out: None")
    }

    /// VoiceOver on the Align segments: Align Left · Align Center · Align Right.
    static func alignment(_ value: OverlayTextAlignment) -> String {
        switch value {
        case .leading: String(localized: "Align Left", table: table, comment: "Video Studio iPad text inspector: aligns the caption's lines to the left")
        case .center: String(localized: "Align Center", table: table, comment: "Video Studio iPad text inspector: centers the caption's lines")
        case .trailing: String(localized: "Align Right", table: table, comment: "Video Studio iPad text inspector: aligns the caption's lines to the right")
        }
    }
}
