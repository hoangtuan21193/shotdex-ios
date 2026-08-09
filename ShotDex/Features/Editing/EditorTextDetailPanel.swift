import SwiftUI
import UIKit

/// Controls for the selected overlay layer.
///
/// Grouped the way the work goes: what it says, what it looks like, how it sits on
/// the photo. Outline and shadow share a section because they exist for the same
/// reason — a white caption over a bright sky is unreadable without one of them.
struct EditorTextDetailPanel: View {
    @Bindable var controller: PhotoEditorController
    @Bindable var chrome: EditorChromeModel
    let editText: () -> Void
    let pickFont: () -> Void
    let replaceImage: () -> Void
    let saveSignature: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            if let overlay = controller.selectedOverlay {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        switch overlay.kind {
                        case .text:
                            textSections(overlay)
                        case .image:
                            imageSections(overlay)
                        }
                        Section {
                            placementRows(overlay)
                        } header: {
                            EditorGroupHeader(title: "Placement")
                        }
                        Color.clear.frame(height: 16)
                    }
                }
                .scrollDisabled(chrome.activePlainSliderID != nil)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Button {
                // Back to the list, but the layer stays selected so its box and
                // move / resize gestures remain live on the photo.
                controller.closeOverlayDetail()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Layers")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(EditorTheme.accent)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button("Save Preset", action: saveSignature)
                .buttonStyle(EditorTextButtonStyle())

            Button {
                controller.deleteSelectedOverlay()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(EditorTheme.secondaryText)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete layer")
        }
        .padding(.horizontal, 10)
    }

    // MARK: Text layer

    @ViewBuilder
    private func textSections(_ overlay: PhotoOverlay) -> some View {
        Section {
            contentRow(overlay)
            fontRow(overlay)
            styleAlignmentRow(overlay)
        } header: {
            EditorGroupHeader(title: "Text", isFirst: true)
        }

        Section {
            colorControl(
                idPrefix: "overlay.fill",
                color: overlay.fill,
                keyPath: \.fill
            )
            slider(
                overlay,
                "Size",
                id: "overlay.size",
                keyPath: \.size,
                range: 1...30,
                defaultValue: PhotoOverlay.text().size,
                text: { String(format: "%.1f%%", $0 * 100) }
            )
            slider(
                overlay,
                "Opacity",
                id: "overlay.opacity",
                keyPath: \.opacity,
                range: 0...100,
                detent: 100,
                defaultValue: 1,
                text: percent
            )
        } header: {
            EditorGroupHeader(title: "Fill")
        }

        Section {
            slider(
                overlay,
                "Outline",
                id: "overlay.outline",
                keyPath: \.outlineWidth,
                range: 0...12,
                defaultValue: 0,
                text: { String(format: "%.1f", $0 * 100) }
            )
            if overlay.hasOutline {
                colorControl(
                    idPrefix: "overlay.outlineColor",
                    color: overlay.outlineColor,
                    keyPath: \.outlineColor
                )
            }
            slider(
                overlay,
                "Shadow",
                id: "overlay.shadow",
                keyPath: \.shadowOpacity,
                range: 0...100,
                defaultValue: 0,
                text: percent,
                after: { layer in
                    // A shadow at zero blur and zero offset is invisible, so
                    // turning the control up has to hand over something to see.
                    guard layer.shadowOpacity > 0.001 else { return }
                    if layer.shadowRadius == 0, layer.shadowOffsetY == 0 {
                        layer.shadowRadius = 0.12
                        layer.shadowOffsetY = 0.06
                    }
                }
            )
            if overlay.hasShadow {
                slider(
                    overlay,
                    "Blur",
                    id: "overlay.shadowRadius",
                    keyPath: \.shadowRadius,
                    range: 0...50,
                    defaultValue: 0.12,
                    text: { String(format: "%.0f", $0 * 100) }
                )
                slider(
                    overlay,
                    "Offset",
                    id: "overlay.shadowOffset",
                    keyPath: \.shadowOffsetY,
                    range: -40...40,
                    isBipolar: true,
                    detent: 0,
                    defaultValue: 0.06,
                    text: { String(format: "%.0f", $0 * 100) }
                )
            }
        } header: {
            EditorGroupHeader(title: "Outline & Shadow")
        }

        Section {
            slider(
                overlay,
                "Width",
                id: "overlay.width",
                keyPath: \.maximumWidth,
                range: 10...100,
                defaultValue: 0.9,
                text: percent
            )
            slider(
                overlay,
                "Leading",
                id: "overlay.lineSpacing",
                keyPath: \.lineSpacing,
                range: 0...100,
                defaultValue: 0.15,
                text: { String(format: "%.0f", $0 * 100) }
            )
            slider(
                overlay,
                "Tracking",
                id: "overlay.tracking",
                keyPath: \.tracking,
                range: -10...40,
                isBipolar: true,
                detent: 0,
                defaultValue: 0,
                text: { String(format: "%.0f", $0 * 100) }
            )
        } header: {
            EditorGroupHeader(title: "Layout")
        }
    }

    private func contentRow(_ overlay: PhotoOverlay) -> some View {
        Button(action: editText) {
            HStack(spacing: 8) {
                Text("Content")
                    .font(EditorTheme.rowLabel)
                    .foregroundStyle(EditorTheme.secondaryText)
                    .frame(width: EditorLayoutMetrics.sliderLabelWidth, alignment: .leading)
                Text(preview(of: overlay))
                    .font(EditorTheme.rowLabel)
                    .foregroundStyle(overlay.text.isEmpty ? EditorTheme.dimText : .white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(EditorTheme.dimText)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fontRow(_ overlay: PhotoOverlay) -> some View {
        let resolved = TextOverlayLayout.resolvedFont(for: overlay, pointSize: 20)
        return Button(action: pickFont) {
            HStack(spacing: 8) {
                Text("Font")
                    .font(EditorTheme.rowLabel)
                    .foregroundStyle(EditorTheme.secondaryText)
                    .frame(width: EditorLayoutMetrics.sliderLabelWidth, alignment: .leading)
                Text(fontName(overlay))
                    .font(EditorTheme.rowLabel)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if resolved.didSubstitute {
                    // Never silent: the caption is being laid out in a different
                    // typeface than the one this recipe asked for.
                    Text("Unavailable")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(EditorTheme.clipping)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(EditorTheme.clipping.opacity(0.18), in: Capsule())
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(EditorTheme.dimText)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Bold, italic and the three alignments on a single line. Two separate rows
    /// read as two unrelated controls and wasted a whole row's height; the style
    /// toggles and the alignment picker are both "how the type is set", so they
    /// share the line — the toggles on the left, the alignment segment filling the
    /// rest.
    private func styleAlignmentRow(_ overlay: PhotoOverlay) -> some View {
        HStack(spacing: 8) {
            Button {
                controller.updateSelectedOverlay { $0.isBold.toggle() }
            } label: {
                Image(systemName: "bold")
            }
            .buttonStyle(EditorChipButtonStyle(isSelected: overlay.isBold))
            .accessibilityLabel("Bold")
            .accessibilityAddTraits(overlay.isBold ? .isSelected : [])

            Button {
                controller.updateSelectedOverlay { $0.isItalic.toggle() }
            } label: {
                Image(systemName: "italic")
            }
            .buttonStyle(EditorChipButtonStyle(isSelected: overlay.isItalic))
            .accessibilityLabel("Italic")
            .accessibilityAddTraits(overlay.isItalic ? .isSelected : [])

            HStack(spacing: 4) {
                ForEach(OverlayTextAlignment.allCases) { alignment in
                    let isSelected = overlay.alignment == alignment
                    Button {
                        controller.updateSelectedOverlay { $0.alignment = alignment }
                    } label: {
                        Image(systemName: alignment.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : EditorTheme.secondaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background(isSelected ? EditorTheme.accent : .clear, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(3)
            .background(EditorTheme.control, in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    // MARK: Image layer

    @ViewBuilder
    private func imageSections(_ overlay: PhotoOverlay) -> some View {
        Section {
            if isMissing(overlay) {
                Text("This signature's image is no longer stored on this device. "
                    + "Pick it again to bring the layer back.")
                    .font(EditorTheme.maskSubtitle)
                    .foregroundStyle(EditorTheme.clipping)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Choose Image", action: replaceImage)
                    .buttonStyle(EditorChipButtonStyle(isSelected: false))
                Spacer(minLength: 0)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
            slider(
                overlay,
                "Size",
                id: "overlay.size",
                keyPath: \.size,
                range: 2...100,
                defaultValue: PhotoOverlay(kind: .image).size,
                text: percent
            )
            slider(
                overlay,
                "Opacity",
                id: "overlay.opacity",
                keyPath: \.opacity,
                range: 0...100,
                detent: 100,
                defaultValue: 1,
                text: percent
            )
        } header: {
            EditorGroupHeader(title: "Image", isFirst: true)
        }
    }

    // MARK: Placement

    @ViewBuilder
    private func placementRows(_ overlay: PhotoOverlay) -> some View {
        // Degrees, not a fraction, so this row's slider works in stored units.
        slider(
            overlay,
            "Rotate",
            id: "overlay.rotation",
            keyPath: \.rotationDegrees,
            range: -180...180,
            scale: 1,
            isBipolar: true,
            detent: 0,
            defaultValue: 0,
            text: { String(format: "%.0f\u{00B0}", $0) }
        )
        slider(
            overlay,
            "Across",
            id: "overlay.centerX",
            keyPath: \.center.x,
            range: 0...100,
            detent: 50,
            defaultValue: 0.5,
            text: percent
        )
        slider(
            overlay,
            "Down",
            id: "overlay.centerY",
            keyPath: \.center.y,
            range: 0...100,
            detent: 50,
            defaultValue: overlay.kind == .text ? 0.9 : 0.88,
            text: percent
        )
        HStack(spacing: 8) {
            Button("Send Backward") { controller.moveSelectedOverlayBackward() }
                .buttonStyle(EditorChipButtonStyle(isSelected: false))
            Button("Bring Forward") { controller.moveSelectedOverlayForward() }
                .buttonStyle(EditorChipButtonStyle(isSelected: false))
            Spacer(minLength: 0)
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    // MARK: Helpers

    /// One row per editable number.
    ///
    /// `scale` is the bridge between the two units in play: the recipe stores
    /// fractions, and a panel showing "0.05" where it means "5%" is unreadable. The
    /// slider works in display units and divides on the way back in.
    ///
    /// Every drag opens and closes a continuous change, so a gesture is one undo
    /// step rather than one per frame.
    private func slider(
        _ overlay: PhotoOverlay,
        _ title: String,
        id: String,
        keyPath: WritableKeyPath<PhotoOverlay, Double>,
        range: ClosedRange<Double>,
        scale: Double = 100,
        isBipolar: Bool = false,
        detent: Double? = nil,
        defaultValue: Double,
        text: (Double) -> String,
        after: ((inout PhotoOverlay) -> Void)? = nil
    ) -> some View {
        let stored = overlay[keyPath: keyPath]
        return EditorPlainSliderRow(
            title: title,
            value: stored * scale,
            range: range,
            isBipolar: isBipolar,
            valueText: text(stored),
            isActive: chrome.activePlainSliderID == id,
            detent: detent,
            onBeginDrag: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                chrome.activePlainSliderID = id
                // `beginOverlayGesture`, not `beginContinuousChange`: the preview
                // leaves the overlays out while a layer is selected, so a sweep
                // needs the undo grouping but no render at all.
                controller.beginOverlayGesture()
            },
            onDrag: { value in
                controller.updateSelectedOverlay { layer in
                    layer[keyPath: keyPath] = value / scale
                    after?(&layer)
                }
            },
            onEndDrag: {
                chrome.activePlainSliderID = nil
                controller.endOverlayGesture()
            },
            onReset: {
                controller.updateSelectedOverlay { layer in
                    layer[keyPath: keyPath] = defaultValue
                    after?(&layer)
                }
            }
        )
    }

    private func colorControl(
        idPrefix: String,
        color: OverlayColor,
        keyPath: WritableKeyPath<PhotoOverlay, OverlayColor>
    ) -> some View {
        EditorOverlayColorControl(
            chrome: chrome,
            idPrefix: idPrefix,
            color: color,
            onBegin: { controller.beginOverlayGesture() },
            onChange: { picked in
                controller.updateSelectedOverlay { $0[keyPath: keyPath] = picked }
                // A colour chosen here is what the next layer starts from, the same
                // way the brush keeps its last size.
                if keyPath == \PhotoOverlay.fill { controller.lastFill = picked }
            },
            onEnd: { controller.endOverlayGesture() }
        )
    }

    private func preview(of overlay: PhotoOverlay) -> String {
        guard !overlay.text.isEmpty else { return "Tap to write" }
        return controller.resolvedText(for: overlay)
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func fontName(_ overlay: PhotoOverlay) -> String {
        if overlay.fontPostScriptName.isEmpty { return OverlayFontChoice.system.displayName }
        return overlay.fontFamilyName.isEmpty
            ? overlay.fontPostScriptName
            : overlay.fontFamilyName
    }

    private func isMissing(_ overlay: PhotoOverlay) -> Bool {
        guard let id = overlay.imageID else { return true }
        return !OverlayImageStore().imageExists(id: id)
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}
