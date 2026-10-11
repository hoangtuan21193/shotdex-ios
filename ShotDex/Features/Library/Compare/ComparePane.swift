import AVKit
import Photos
import SwiftUI

/// One Compare frame (FS-01.08c §2): the photo fitted into its box at its
/// own aspect ratio, a role chip, its flag, the zoom, and under it a name,
/// one EXIF line, the stars and the flag control.
///
/// A tap makes it the working frame (amber ring) — it never changes a flag
/// (§1). Touch and hold offers Make Select · Share · Remove from
/// Comparison · Keep Only This (§5).
struct ComparePane: View {
    enum Role: Hashable { case select, candidate, survey }

    enum Style {
        /// iPhone and the Duo's inner 2-Up: name line + the Cull row.
        case cullRow
        /// The Duo's cover: name on the photo, the Cull row under it.
        case cover
        /// iPad 2-Up: two caption lines, five stars, None · Pick · Reject.
        case wide
        /// iPad Survey cell.
        case surveyWide
        /// The Duo's inner Survey cell: name on the photo, 32pt stars.
        case surveyCompact
    }

    let model: CompareModel
    let id: String
    let role: Role
    let frame: CompareLayout.Frame
    let style: Style
    let paneIndex: Int
    let onShare: () -> Void
    let onSingle: (String) -> Void

    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(\.appAccent) private var accent
    @Environment(\.displayScale) private var displayScale

    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var isVideo = false

    private var marks: PhotoMarkSummary { model.marks(for: id) }
    private var isWorking: Bool { model.session.workingId == id }
    private var isSurvey: Bool { role == .survey }
    private var isRejected: Bool { marks.flag == .reject }

    static var removeTitle: String {
        String(localized: "Remove from Comparison", comment: "Compare frame menu: stop comparing this photo; its flag stays")
    }

    static var keepOnlyTitle: String {
        String(localized: "Keep Only This", comment: "Compare frame menu: Reject every other photo, keep this one")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            photoBox
            caption
        }
        .frame(width: frame.size.width, height: frame.size.height, alignment: .top)
        .contentShape(Rectangle())
        .contextMenu { menu }
        .onAppear(perform: load)
        .onDisappear { player?.pause() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(roleLabel.map { "\($0), \(model.name(for: id))" } ?? model.name(for: id))
    }

    // MARK: Photo

    private var photoBox: some View {
        let box = frame.photo
        return ZStack {
            media
                .aspectRatio(aspectRatio, contentMode: .fit)
                .frame(maxWidth: box.width, maxHeight: box.height)
                // Rejected in Survey: dimmed like a grid cell (12 §7).
                .opacity(isSurvey && isRejected ? 0.45 : 1)
        }
        .frame(width: box.width, height: box.height)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .strokeBorder(accent, lineWidth: isWorking ? 2 : 0)
        }
        .overlay(alignment: .topLeading) { chips.padding(AppTheme.Spacing.sm) }
        .overlay(alignment: .topTrailing) {
            if isWorking, isSurvey, model.session.canRemove {
                removeButton
            }
        }
        .overlay(alignment: style == .wide ? .bottomLeading : .bottomTrailing) {
            zoomLabel.padding(AppTheme.Spacing.sm)
        }
        .overlay(alignment: .bottomLeading) {
            if style == .cover || style == .surveyCompact { nameOnPhoto }
        }
        .padding(isSurvey && style == .surveyWide ? 3 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel(for: id))
        .accessibilityAddTraits(isWorking ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.session.setWorking(id) }
    }

    private var aspectRatio: CGFloat {
        let size = model.pixelSize(for: id)
        guard size.width > 0, size.height > 0 else { return 1.5 }
        return size.width / size.height
    }

    @ViewBuilder private var media: some View {
        if isVideo {
            if let player {
                CompareVideoPaneView(
                    player: player,
                    sync: model.sync,
                    paneIndex: paneIndex,
                    onSingleTap: { model.session.setWorking(id) }
                )
            } else {
                ProgressView()
            }
        } else if let image {
            ZoomableImageView(
                image: image,
                sync: isSurvey ? nil : model.sync,
                paneIndex: paneIndex,
                onSingleTap: { model.session.setWorking(id) },
                onSwipe: role == .candidate ? { swipe in handleSwipe(swipe) } : nil,
                maximumZoomScale: model.maximumZoom(box: frame.photo, screenScale: displayScale)
            )
        } else {
            ProgressView()
        }
    }

    /// Horizontal swipes on the Candidate at Fit step through the
    /// candidates; zoomed in, one finger pans instead (§3, AC-20).
    private func handleSwipe(_ swipe: CullGesturePolicy.Swipe) {
        switch swipe {
        case .left: model.session.nextCandidate()
        case .right: model.session.previousCandidate()
        default: break
        }
    }

    // MARK: Chips

    private var roleLabel: String? {
        switch role {
        case .select: String(localized: "Select", comment: "Compare: the reference frame's label")
        case .candidate: model.session.candidateLabel
        case .survey: nil
        }
    }

    @ViewBuilder private var chips: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            if let roleLabel {
                chip(roleLabel, fill: role == .select ? accent : Color.black.opacity(0.6), text: role == .select ? .black : .white)
            }
            switch marks.flag {
            case .pick:
                chip(MarkCopy.flagWord(.pick), systemImage: "flag.fill", fill: Color.black.opacity(0.6), text: .white)
            case .reject:
                chip(MarkCopy.rejectedFilter, systemImage: "xmark", fill: .red, text: .white)
            case nil:
                EmptyView()
            }
        }
        .accessibilityHidden(true)
    }

    private func chip(_ title: String, systemImage: String? = nil, fill: Color, text: Color) -> some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 10, weight: .bold))
            }
            Text(title).font(.caption.weight(.semibold))
        }
        .foregroundStyle(text)
        .padding(.horizontal, AppTheme.Spacing.sm)
        .frame(height: 26)
        .background(Capsule().fill(fill))
    }

    @ViewBuilder private var zoomLabel: some View {
        if !isSurvey, let percent = CompareZoom.percent(
            zoomScale: model.zoomScale,
            pixelSize: model.pixelSize(for: id),
            box: frame.photo,
            screenScale: displayScale
        ) {
            HStack(spacing: 4) {
                if style != .wide {
                    Image(systemName: "link").font(.system(size: 10, weight: .bold))
                }
                Text("\(percent)%").font(.caption.weight(.semibold)).monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .frame(height: 24)
            .background(Capsule().fill(Color.black.opacity(0.6)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(
                localized: "Zoom \(percent) percent, synced",
                comment: "VoiceOver: a compare frame's zoom, shared by every frame"
            ))
        }
    }

    private var nameOnPhoto: some View {
        Text(model.name(for: id))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
            .lineLimit(1)
            .padding(AppTheme.Spacing.sm)
            .padding(.leading, AppTheme.Spacing.xs)
    }

    private var removeButton: some View {
        Button {
            model.session.remove(id)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .glassBackground(Circle())
                .frame(width: AppTheme.Size.minTouch, height: AppTheme.Size.minTouch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.delete, modifiers: [])
        .accessibilityLabel(Text("Remove from Survey", comment: "Compare Survey: take the working photo out of the comparison"))
    }

    // MARK: Caption

    @ViewBuilder private var caption: some View {
        switch style {
        case .cullRow:
            VStack(spacing: 4) {
                nameLine
                markRow(starWidth: CullLayout.control)
            }
            .padding(.top, 4)
        case .cover:
            markRow(starWidth: CullLayout.control)
                .padding(.top, 4)
        case .surveyCompact:
            markRow(starWidth: 32, spacing: 8)
        case .wide:
            HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name(for: id)).font(.headline).foregroundStyle(.primary)
                    if let exif = model.exifLine(for: id) {
                        Text(exif).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                starsOnly
                flagSegmented
            }
            .padding(.horizontal, 2)
            .frame(height: CompareLayout.Metrics.wide.caption)
        case .surveyWide:
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(model.name(for: id)).font(.headline).foregroundStyle(.primary).lineLimit(1)
                    Spacer(minLength: 0)
                    starsOnly
                }
                HStack {
                    if let exif = model.exifLine(for: id) {
                        Text(exif).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    flagSegmented
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var nameLine: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text(model.name(for: id)).font(.caption.weight(.semibold)).foregroundStyle(.primary)
            if let exif = model.exifLine(for: id) {
                Text(exif).font(.caption).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .frame(height: 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    private func markRow(starWidth: CGFloat, spacing: CGFloat = CullLayout.controlGap) -> some View {
        PhotoMarkRow(
            marks: marks,
            surface: .viewer,
            starWidth: starWidth,
            starGlyph: starWidth < CullLayout.control ? 17 : CullLayout.starGlyph,
            spacing: spacing,
            canReject: model.canReject(id),
            photoName: model.name(for: id),
            onRate: { stars in Task { await model.setRating(stars, for: id) } },
            onFlag: { flag in Task { await model.setFlag(flag, for: id) } }
        )
        .frame(maxWidth: .infinity)
    }

    private var starsOnly: some View {
        HStack(spacing: 0) {
            ForEach(1...5, id: \.self) { stars in
                Button {
                    Task { await model.setRating(marks.rating == stars ? 0 : stars, for: id) }
                } label: {
                    Image(systemName: stars <= marks.rating ? "star.fill" : "star")
                        .font(.system(size: 17))
                        .foregroundStyle(stars <= marks.rating ? Color.primary : Color.secondary)
                        .frame(width: 32, height: AppTheme.Size.minTouch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(MarkCopy.starsAccessibility(stars))
                .accessibilityAddTraits(stars <= marks.rating ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(
            localized: "Rating for \(model.name(for: id))",
            comment: "VoiceOver: a compare frame's five stars"
        ))
    }

    private var flagSegmented: some View {
        PhotoFlagSegmented(
            flag: marks.flag,
            canReject: model.canReject(id),
            photoName: model.name(for: id),
            onFlag: { flag in Task { await model.setFlag(flag, for: id) } }
        )
    }

    // MARK: Menu

    @ViewBuilder private var menu: some View {
        if id != model.session.selectId {
            Button {
                model.session.makeSelect(id)
            } label: {
                Label(String(localized: "Make Select", comment: "Compare: swap Candidate and Select"), systemImage: "arrow.left.arrow.right")
            }
        }
        if style == .cullRow || style == .cover {
            Button(action: onShare) {
                Label(String(localized: "Share"), systemImage: "square.and.arrow.up")
            }
        }
        if model.session.canRemove {
            Button {
                model.session.remove(id)
            } label: {
                Label(Self.removeTitle, systemImage: "minus.circle")
            }
        }
        Button(role: .destructive) {
            Task { await model.keepOnly(id) }
        } label: {
            Label(Self.keepOnlyTitle, systemImage: "checkmark.circle")
        }
    }

    // MARK: Loading

    private func load() {
        guard let asset = model.asset(for: id) else { return }
        if asset.mediaType == .video {
            isVideo = true
            loadVideo(asset)
        } else {
            loadImage(asset)
        }
    }

    /// Muted, so frames side by side never play over each other.
    private func loadVideo(_ asset: PHAsset) {
        guard player == nil else { return }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
            guard let item else { return }
            Task { @MainActor in
                let avPlayer = AVPlayer(playerItem: item)
                avPlayer.isMuted = true
                player = avPlayer
            }
        }
    }

    /// A Survey cell asks for its own size, not the screen's: twelve
    /// screen-sized decodes on a 13" iPad is a few hundred megabytes for
    /// thumbnails (plan §6). 2-Up asks for the screen.
    private func loadImage(_ asset: PHAsset) {
        guard image == nil else { return }
        let targetSize = isSurvey
            ? CGSize(width: frame.photo.width * displayScale, height: frame.photo.height * displayScale)
            : ActiveDisplay.pixelSize()
        _ = photoLibrary.requestBestLocalImage(for: asset, targetSize: targetSize) { result in
            guard let result else { return }
            let currentPixels = (image?.size.width ?? 0) * (image?.scale ?? 1)
            if result.size.width * result.scale > currentPixels { image = result }
        }
        _ = photoLibrary.requestDetailImage(
            for: asset,
            targetSize: targetSize,
            allowNetwork: true,
            progress: { _ in }
        ) { result, isDegraded in
            if let result, !isDegraded { image = result }
        }
    }
}
