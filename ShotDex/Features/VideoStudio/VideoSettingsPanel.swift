import Photos
import SwiftUI
import ShotDexKit

/// Video Settings (FS-12.10 §4): the frame's ratio, how clips sit in it,
/// what shows around them, and what the export writes — every change
/// applied at once and one undo step, so there is a Done and no ✕.
///
/// One content for every place it opens: the phone's panel, the iPad's
/// popover, the Duo's column and cover panel — inset 16 (14 on the Duo
/// cover), and the Duo drops the length from the second line.
struct VideoSettingsPanel: View {
    @Bindable var model: VideoStudioModel
    @Environment(\.videoMediaGrid) private var window
    /// 16 at the edges; 14 on the Duo cover.
    private var inset: CGFloat { window == .cover ? 14 : 16 }
    /// The Duo drops the length from the second line (FS-12.10 §4).
    private var showsLength: Bool { window != .cover && window != .duoColumn }
    /// Done when the panel is not the open tool — the iPad's popover.
    var onDone: (() -> Void)?
    @Environment(\.openURL) private var openURL
    /// Whether the Image background's photo can still be read.
    @State private var isBackgroundImageMissing = false

    var body: some View {
        if model.mediaPickPurpose == .backgroundImage {
            // Image → Choose…: Media in single-pick mode, photos only, in
            // the panel's place (FS-12.10 §5).
            VideoMediaPanel(model: model)
        } else {
            settings
        }
    }

    private var settings: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    // Board ES_*: the look-LUT line at the panel's head
                    // (FS-12.06c §6).
                    if model.missingLUTLookCount > 0 {
                        VideoMissingLUTBanner(count: model.missingLUTLookCount)
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                    }
                    ratioSection
                    framingRow
                    if model.recipe.framing == .fit { backgroundSection }
                    resolutionSection
                    frameRateSection
                    codecSection
                    outputRow
                }
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(EditorTheme.panelSolid)
        .task(id: model.recipe.background.imageAssetID) { checkBackgroundImage() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(VideoStudioCopy.videoSettings)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(verbatim: model.outputSummary(includesLength: showsLength))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                if let onDone { onDone() } else { model.showToolPanel(nil) }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(VideoStudioCopy.done))
        }
        .padding(.horizontal, inset)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: Sections

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(.white.opacity(0.7))
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .bottomLeading)
            .padding(.horizontal, inset)
            .padding(.bottom, 6)
    }

    private var ratioSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel(VideoStudioCopy.ratioHeader)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(VideoAspect.allCases) { aspect in
                    choice(isOn: model.recipe.aspect == aspect, height: 30, fontSize: 13) {
                        model.setAspect(aspect)
                    } label: {
                        HStack(spacing: 6) {
                            Self.ratioGlyph(aspect, side: 12)
                            Text(verbatim: aspect.displayName)
                        }
                    }
                    .accessibilityLabel(Text(VideoStudioCopy.ratioLabel(aspect.displayName)))
                }
            }
            .padding(.horizontal, inset)
        }
    }

    private var framingRow: some View {
        HStack(spacing: 8) {
            choice(isOn: model.recipe.framing == .fit, height: 28, fontSize: 12.5) {
                model.setFraming(.fit)
            } label: { Text(VideoStudioCopy.fitOnBackground) }
            choice(isOn: model.recipe.framing == .fill, height: 28, fontSize: 12.5) {
                model.setFraming(.fill)
            } label: { Text(VideoStudioCopy.fillCrop) }
        }
        .padding(.horizontal, inset)
        .padding(.top, 8)
    }

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel(VideoStudioCopy.backgroundHeader)
            HStack(spacing: 8) {
                ForEach(VideoBackground.Kind.allCases) { kind in
                    choice(isOn: model.recipe.background.kind == kind, height: 28, fontSize: 12.5) {
                        model.setBackgroundKind(kind)
                    } label: { Text(VideoStudioCopy.backgroundKind(kind)) }
                }
            }
            .padding(.horizontal, inset)
            Group {
                switch model.recipe.background.kind {
                case .blur: blurRow
                case .colour: colourRow
                case .image: imageRow
                }
            }
            .padding(.horizontal, inset)
            .padding(.top, 8)
        }
    }

    private var blurRow: some View {
        HStack(spacing: 10) {
            Text(VideoStudioCopy.blur)
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.8))
            Slider(
                value: Binding(
                    get: { model.recipe.background.blurAmount },
                    set: { model.setBlurAmount($0) }
                ),
                in: VideoBackground.blurRange,
                onEditingChanged: { editing in
                    if editing { model.beginUndoGroup() } else { model.endUndoGroup() }
                }
            )
            .tint(.white)
            Text(verbatim: "\(Int(model.recipe.background.blurAmount.rounded()))")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 30, alignment: .trailing)
        }
        .frame(height: 30)
    }

    /// Black · #808080 · white · a colour of one's own (FS-12.10 §4).
    private static let swatches: [OverlayColor] = [.black, OverlayColor(white: 128.0 / 255), .white]

    private var colourRow: some View {
        HStack(spacing: 12) {
            ForEach(Array(Self.swatches.enumerated()), id: \.offset) { _, swatch in
                let isOn = model.recipe.background.colour == swatch
                Button { model.setBackground(swatch) } label: {
                    Circle()
                        .fill(Color(red: swatch.red, green: swatch.green, blue: swatch.blue))
                        .frame(width: 28, height: 28)
                        .overlay(Circle().strokeBorder(isOn ? Color.white : Color.white.opacity(0.2), lineWidth: isOn ? 2 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(VideoStudioCopy.colourSwatch(swatch)))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
            ColorPicker(selection: Binding(
                get: {
                    let colour = model.recipe.background.colour
                    return Color(red: colour.red, green: colour.green, blue: colour.blue)
                },
                set: { picked in
                    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                    UIColor(picked).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                    model.pickBackgroundColour(OverlayColor(red: Double(red), green: Double(green), blue: Double(blue)))
                }
            ), supportsOpacity: false) { EmptyView() }
            .labelsHidden()
            .frame(width: 28, height: 28)
            .accessibilityLabel(Text(VideoStudioCopy.customColour))
            Spacer(minLength: 0)
        }
        .frame(height: 30)
    }

    private var imageRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VideoBackgroundThumbnail(assetID: model.recipe.background.imageAssetID, photoLibrary: model.photoLibrary)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Button { model.beginBackgroundImagePick() } label: {
                    Text(VideoStudioCopy.chooseImage)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(VideoMediaPanelMetrics.tabFill(isOn: false))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            if isBackgroundImageMissing {
                note(VideoStudioCopy.imageUnavailable)
            }
        }
    }

    private var resolutionSection: some View {
        let verdict = model.fourKVerdict
        return VStack(alignment: .leading, spacing: 0) {
            sectionLabel(VideoStudioCopy.resolutionHeader)
            HStack(spacing: 8) {
                ForEach(VideoResolution.allCases) { resolution in
                    let isLocked = resolution == .uhd4K && verdict != .allowed
                    choice(isOn: model.recipe.resolution == resolution, height: 30, fontSize: 13) {
                        model.setResolution(resolution)
                    } label: {
                        HStack(spacing: 4) {
                            if isLocked { Image(systemName: "lock.fill").font(.system(size: 10, weight: .semibold)) }
                            Text(verbatim: resolution.displayName)
                        }
                    }
                    .opacity(isLocked ? 0.35 : 1)
                    .disabled(isLocked)
                    .accessibilityLabel(Text(isLocked ? VideoStudioCopy.unavailable(resolution.displayName) : resolution.displayName))
                    .accessibilityHint(Text(isLocked ? (VideoStudioCopy.fourKReason(verdict) ?? "") : ""))
                }
            }
            .padding(.horizontal, inset)
            if let reason = VideoStudioCopy.fourKReason(verdict) {
                note(reason).padding(.horizontal, inset)
            }
        }
    }

    private var frameRateSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel(VideoStudioCopy.frameRateHeader)
            HStack(spacing: 8) {
                ForEach(VideoFrameRate.allCases) { rate in
                    choice(isOn: model.recipe.frameRate == rate, height: 28, fontSize: 12.5) {
                        model.setFrameRate(rate)
                    } label: { Text(verbatim: "\(rate.rawValue)") }
                    .accessibilityLabel(Text(VideoStudioCopy.framesPerSecond(rate.rawValue)))
                }
            }
            .padding(.horizontal, inset)
        }
    }

    private var codecSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel(VideoStudioCopy.codecHeader)
            HStack(spacing: 8) {
                ForEach(VideoCodec.allCases) { codec in
                    choice(isOn: model.recipe.codec == codec, height: 28, fontSize: 12.5) {
                        model.setCodec(codec)
                    } label: { Text(verbatim: codec.displayName) }
                }
            }
            .padding(.horizontal, inset)
            note(VideoStudioCopy.hevcNote).padding(.horizontal, inset)
        }
    }

    private var outputRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "film")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                Text(VideoStudioCopy.output)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Text(verbatim: model.outputSummary(includesLength: showsLength))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(height: 38)
            note(VideoStudioCopy.changesApplyRightAway)
        }
        .padding(.horizontal, inset)
        .padding(.top, 6)
    }

    // MARK: Pieces

    /// A choice in a row: white 20 % when on, 6 % when off, radius 8.
    private func choice(
        isOn: Bool,
        height: CGFloat,
        fontSize: CGFloat,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> some View
    ) -> some View {
        Button(action: action) {
            label()
                .font(.system(size: fontSize, weight: isOn ? .semibold : .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(VideoMediaPanelMetrics.tabFill(isOn: isOn))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.white.opacity(0.35))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 5)
    }

    /// A frame in a ratio — the glyph of the ratio buttons and of the
    /// Video Settings button.
    static func ratioGlyph(_ aspect: VideoAspect, side: CGFloat) -> some View {
        let ratio = aspect.ratio
        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .strokeBorder(Color.white, lineWidth: 1.4)
            .frame(width: ratio >= 1 ? side : side * ratio, height: ratio >= 1 ? side / ratio : side)
            .frame(width: side, height: side)
    }

    private func checkBackgroundImage() {
        guard let id = model.recipe.background.imageAssetID else {
            isBackgroundImageMissing = false
            return
        }
        isBackgroundImageMissing = model.serverFileURL(for: id) == nil
            && PhotoLibraryService.fetchAssets(ids: [id]).isEmpty
    }
}

/// The Image background's photo, small.
private struct VideoBackgroundThumbnail: View {
    let assetID: String?
    let photoLibrary: PhotoLibraryService
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .clipped()
            .task(id: assetID) {
                image = nil
                guard let assetID, let asset = PhotoLibraryService.fetchAssets(ids: [assetID]).first else { return }
                _ = photoLibrary.requestThumbnail(
                    for: asset,
                    targetSize: CGSize(width: 28 * displayScale, height: 28 * displayScale),
                    resizeMode: .fast,
                    allowNetwork: false
                ) { result, _ in
                    if let result { image = result }
                }
            }
    }
}
