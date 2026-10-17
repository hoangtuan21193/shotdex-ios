import Photos
import SwiftUI

/// Which group the viewer opens on, and at which photo.
struct DuplicateViewerPresentation: Identifiable, Equatable {
    let id = UUID()
    let groupId: String
    let startId: String
}

/// One group, big (FS-06.06 §7.6, board `PH_DuplicatesViewer`): swipe across
/// its photos, pinch to zoom, then **Keep this** (the group's keeper becomes
/// this photo) or **Remove** / **Don't remove**. Tier D — dark whatever the
/// system appearance, so the photo is judged against black. Swipe down
/// closes; there is no X.
struct DuplicateGroupViewer: View {
    let model: DuplicatesModel
    let presentation: DuplicateViewerPresentation
    @Environment(\.dismiss) private var dismiss
    @State private var currentId: String

    init(model: DuplicatesModel, presentation: DuplicateViewerPresentation) {
        self.model = model
        self.presentation = presentation
        _currentId = State(initialValue: presentation.startId)
    }

    private var group: DuplicateGroup? {
        model.groups.first { $0.memberIds.contains(presentation.startId) }
    }

    var body: some View {
        ZStack {
            EditorTheme.background.ignoresSafeArea()
            if let group {
                VStack(spacing: AppTheme.Spacing.md) {
                    header(group)
                    TabView(selection: $currentId) {
                        ForEach(group.members) { member in
                            DuplicateViewerPage(asset: model.assetsById[member.assetId])
                                .tag(member.assetId)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    if let member = group.members.first(where: { $0.assetId == currentId }) {
                        footer(member, in: group)
                    }
                }
                .padding(.bottom, AppTheme.Spacing.md)
            }
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .onChange(of: group == nil) { _, gone in if gone { dismiss() } }
    }

    private func header(_ group: DuplicateGroup) -> some View {
        let index = (group.members.firstIndex { $0.assetId == currentId } ?? 0) + 1
        return VStack(spacing: 2) {
            Text(String(localized: "\(group.kind.title) · \(index) of \(group.count)",
                        comment: "Duplicates viewer title: kind, which photo of how many"))
                .font(.headline)
                .foregroundStyle(Color.white)
                .monospacedDigit()
            let chips = chips(for: currentId, in: group)
            if !chips.isEmpty {
                Text(chips.joined(separator: " · "))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(EditorTheme.secondaryText)
            }
        }
        .padding(.top, AppTheme.Spacing.xl)
        .accessibilityElement(children: .combine)
    }

    /// The keeper's reasons on the keeper, a copy's caption on a copy.
    private func chips(for assetId: String, in group: DuplicateGroup) -> [String] {
        guard let member = group.members.first(where: { $0.assetId == assetId }) else { return [] }
        if model.keeper(of: group)?.assetId == assetId {
            return model.reasons(for: group).map(\.title)
        }
        return model.caption(of: member, in: group)
    }

    private func footer(_ member: HashedPhoto, in group: DuplicateGroup) -> some View {
        let isKeeper = model.keeper(of: group)?.assetId == member.assetId
        let isMarked = model.isMarked(member.assetId)
        return VStack(spacing: AppTheme.Spacing.md) {
            Text(facts(member))
                .font(.footnote)
                .foregroundStyle(EditorTheme.secondaryText)
                .monospacedDigit()
                .lineLimit(2)
                .multilineTextAlignment(.center)
            HStack(spacing: AppTheme.Spacing.md) {
                Button {
                    model.keepThis(member.assetId, in: group)
                    dismiss()
                } label: {
                    Label(String(localized: "Keep this", comment: "Duplicates viewer: make this photo the group's kept one"),
                          systemImage: "checkmark")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(Color.white)
                .disabled(isKeeper && !isMarked)

                Button {
                    withAnimation(AppTheme.Motion.standard) { _ = model.toggleMark(member.assetId, in: group) }
                } label: {
                    Label(isMarked
                          ? String(localized: "Don't remove", comment: "Duplicates viewer: take this photo's mark away")
                          : String(localized: "Remove", comment: "Duplicates viewer: mark this photo for removal"),
                          systemImage: isMarked ? "trash.slash" : "trash")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(isMarked ? Color.white : .red)
                .disabled(!isMarked && model.isLastUnmarked(member.assetId, in: group))
            }
            .padding(.horizontal, AppTheme.Size.screenMargin)
        }
    }

    /// Size, MB, where it is from, and what was measured — the numbers the
    /// tiles leave out (§7.4).
    private func facts(_ member: HashedPhoto) -> String {
        var parts: [String] = []
        if let dimensions = DuplicateReview.dimensions(member) { parts.append(dimensions) }
        if let size = member.fileSize { parts.append(DuplicatesScreen.byteFormatter.string(fromByteCount: Int64(size))) }
        if let name = member.originalFilename { parts.append(name) }
        var lines = [parts.joined(separator: " · ")]
        if let score = model.scores[member.assetId], let sharpness = score.sharpness {
            let best = model.groups.first { $0.memberIds.contains(member.assetId) }?
                .members.compactMap { model.scores[$0.assetId]?.sharpness }.max() ?? sharpness
            let share = best > 0 ? Int((sharpness / best * 100).rounded()) : 100
            lines.append(String(localized: "Sharpness \(share)% of the sharpest · highlights clipped \((score.highlightClip * 100).formatted(.number.precision(.fractionLength(1))))%",
                                comment: "Duplicates viewer: what the scoring pass measured on this photo"))
        }
        return lines.joined(separator: "\n")
    }
}

/// One page: the photo at screen size, pinch- and double-tap-zoomable.
private struct DuplicateViewerPage: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary
    let asset: PHAsset?
    @State private var image: UIImage?
    @State private var requestId: PHImageRequestID?

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image {
                    ZoomableImageView(image: image)
                } else {
                    ProgressView().tint(EditorTheme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onAppear { load(side: max(proxy.size.width, proxy.size.height)) }
        }
        .onDisappear {
            if let requestId { photoLibrary.cancelThumbnailRequest(requestId) }
            requestId = nil
        }
    }

    private func load(side: CGFloat) {
        guard let asset, image == nil, side > 0 else { return }
        let pixels = side * ActiveDisplay.scale
        requestId = photoLibrary.requestThumbnail(
            for: asset, targetSize: CGSize(width: pixels, height: pixels), contentMode: .aspectFit, allowNetwork: true
        ) { result in
            if let result { image = result }
        }
    }
}
