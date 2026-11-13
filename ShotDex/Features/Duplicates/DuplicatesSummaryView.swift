import Photos
import SwiftUI

/// Quick clean over the Duplicates list (FS-06.06 §7.2, board
/// `PH_Duplicates`): the identical copies nobody has
/// decided yet, and one button that previews them before anything is marked.
/// **Review…** is the screen's one accent-filled button (DESIGN.md §4).
/// Stays until the next load once every copies group is decided, so the
/// cards under it never move on a tap.
struct DuplicatesQuickCleanBand: View {
    let model: DuplicatesModel
    let review: () -> Void

    var body: some View {
        let pending = model.pendingQuickClean
        HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Quick clean", comment: "Duplicates list: band over the cards"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(pending.copies == 0
                     ? String(localized: "Every copy decided", comment: "Duplicates Quick clean band: nothing left for it")
                     : pending.copies == 1
                     ? String(localized: "1 copy · \(bytes(pending.bytes))", comment: "Duplicates Quick clean band: copies to remove and their size")
                     : String(localized: "\(pending.copies.formatted()) copies · \(bytes(pending.bytes))",
                              comment: "Duplicates Quick clean band: copies to remove and their size"))
                    .font(.headline)
                    .monospacedDigit()
                Text(String(localized: "Identical copies. Favorites, edits and album photos stay.",
                            comment: "Duplicates Quick clean band: what it removes and what it never touches"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: review) {
                Text(String(localized: "Review…", comment: "Duplicates Quick clean band: opens the preview; the screen's one accent button"))
                    .font(.headline)
                    .frame(minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(model.isBusy || pending.copies == 0)
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle.app(AppTheme.Radius.lg))
        .accessibilityElement(children: .contain)
    }

    private func bytes(_ count: Int) -> String {
        DuplicatesScreen.byteFormatter.string(fromByteCount: Int64(count))
    }
}

/// A 32pt thumbnail of a kind's first keeper, or a Quick clean row's keeper.
private struct DuplicatesKindThumbnail: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary
    let asset: PHAsset?
    @State private var image: UIImage?
    @State private var requestId: PHImageRequestID?

    var body: some View {
        RoundedRectangle.app(AppTheme.Radius.sm)
            .fill(Color(.tertiarySystemFill))
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle.app(AppTheme.Radius.sm))
            .accessibilityHidden(true)
            .onAppear {
                guard let asset, image == nil else { return }
                let pixels = 32 * ActiveDisplay.scale
                requestId = photoLibrary.requestThumbnail(
                    for: asset, targetSize: CGSize(width: pixels, height: pixels), allowNetwork: false
                ) { result in
                    if let result { image = result }
                }
            }
            .onDisappear {
                if let requestId { photoLibrary.cancelThumbnailRequest(requestId) }
                requestId = nil
            }
    }
}

/// "Scanning 1,200 of 38,000 · 40 found so far" with Cancel (A4).
struct DuplicatesCheckProgress: View {
    /// The band's status slot: two lines, the 44pt Cancel row and the bar.
    static let height: CGFloat = 54

    let step: DuplicatesCheckStep
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            HStack(spacing: AppTheme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Self.title(step))
                        .font(.footnote.weight(.semibold))
                    Text(Self.detail(step))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
                .lineLimit(1)
                Spacer(minLength: 0)
                // Accent, not red: on this screen red only ever means
                // "this photo goes" (Q8). Cancelling keeps what was read.
                if step != .grouping {
                    Button(String(localized: "Cancel", comment: "Duplicates: stop the check in progress"), action: cancel)
                        .font(.footnote.weight(.semibold))
                        .frame(minHeight: 44)
                }
            }
            if let fraction = Self.fraction(step) {
                ProgressView(value: fraction)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func fraction(_ step: DuplicatesCheckStep) -> Double? {
        switch step {
        case .reading(let scan): scan.total > 0 ? scan.fraction : nil
        case .grouping: nil
        case .comparing(let progress): progress.total > 0 ? Double(progress.processed) / Double(progress.total) : nil
        }
    }

    static func title(_ step: DuplicatesCheckStep) -> String {
        switch step {
        case .reading: String(localized: "Step 1 of 3 · Reading photos", comment: "Duplicates header: first step of the check")
        case .grouping: String(localized: "Step 2 of 3 · Grouping", comment: "Duplicates header: second step of the check")
        case .comparing: String(localized: "Step 3 of 3 · Comparing matches", comment: "Duplicates header: third step, Vision confirms each group")
        }
    }

    static func detail(_ step: DuplicatesCheckStep) -> String {
        switch step {
        case .reading(let scan):
            guard scan.total > 0 else {
                return String(localized: "Getting ready…", comment: "Duplicates header: before the first batch of the check")
            }
            return String(localized: "\(scan.processed.formatted()) of \(scan.total.formatted()) photos",
                          comment: "Duplicates header: check progress")
        case .grouping:
            return String(localized: "Finding photos that look alike…", comment: "Duplicates header: grouping step")
        case .comparing(let progress):
            return String(localized: "\(progress.processed.formatted()) of \(progress.total.formatted()) photos · list updates when done",
                          comment: "Duplicates header: comparing step progress")
        }
    }
}

/// The Quick clean preview (§7.2): each copies group with what it keeps and
/// what it would mark, a tick per row, and one button that marks — nothing
/// is deleted here.
struct DuplicatesQuickCleanSheet: View {
    let model: DuplicatesModel
    @Environment(\.dismiss) private var dismiss
    @State private var items: [QuickCleanItem]?
    @State private var unticked: Set<String> = []

    private var selectedCount: Int {
        (items ?? []).filter { !unticked.contains($0.groupId) }.reduce(0) { $0 + $1.removal.remove.count }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let items {
                    List(items) { item in
                        row(item)
                    }
                    .listStyle(.insetGrouped)
                    .safeAreaInset(edge: .bottom) { footer }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(String(localized: "Quick clean", comment: "Duplicates: Quick clean sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Duplicates Quick clean: close without marking")) { dismiss() }
                }
            }
        }
        .task {
            items = await model.quickCleanItems()
        }
    }

    private func row(_ item: QuickCleanItem) -> some View {
        let isTicked = !unticked.contains(item.groupId)
        return Button {
            if isTicked { unticked.insert(item.groupId) } else { unticked.remove(item.groupId) }
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: isTicked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isTicked ? Color.accentColor : Color.secondary)
                DuplicatesKindThumbnail(asset: model.assetsById[item.keeperId])
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Remove \(item.removal.remove.count) · \(DuplicatesScreen.byteFormatter.string(fromByteCount: Int64(item.removal.removeBytes)))",
                                comment: "Duplicates Quick clean row: copies it would mark and their size"))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    if let kept = DuplicateProtection.keptLine(item.removal.kept, namingAlbums: true) {
                        Text(kept)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isTicked ? .isSelected : [])
    }

    private var footer: some View {
        Button {
            model.applyQuickClean(items ?? [], excluding: unticked)
            dismiss()
        } label: {
            Text(selectedCount == 1
                 ? String(localized: "Select 1 photo", comment: "Duplicates Quick clean: mark the ticked copies")
                 : String(localized: "Select \(selectedCount.formatted()) photos", comment: "Duplicates Quick clean: mark the ticked copies"))
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: AppTheme.Radius.md))
        .controlSize(.large)
        .disabled(selectedCount == 0)
        .padding(.horizontal, AppTheme.Size.screenMargin)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(.bar)
    }
}
