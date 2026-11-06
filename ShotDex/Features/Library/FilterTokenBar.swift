import SwiftUI

/// Capsule used by active search/filter bars. The visible xmark stays compact
/// while the native button keeps a 44pt touch target.
struct ActiveConditionChip: View {
    let label: String
    var removalAccessibilityLabel: String?
    var onRemove: (() -> Void)?
    /// A chip that does something other than remove itself (the match-mode
    /// switch). Mutually exclusive with `onRemove`.
    var onTap: (() -> Void)?
    /// Full-strength label. A chip that carries a condition is the content;
    /// one that carries a setting about the conditions reads a step quieter.
    var isEmphasised = true

    /// How far the chip row dissolves at its trailing edge, and therefore how
    /// much room the row leaves after its last chip so that chip can still be
    /// scrolled out of the fade.
    static let scrollFadeWidth: CGFloat = 28

    var body: some View {
        if let onRemove {
            Button(action: onRemove) {
                chipContent(showsRemove: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(removalAccessibilityLabel ?? "Remove \(label)")
            .accessibilityHint("Removes this condition")
        } else if let onTap {
            Button(action: onTap) {
                chipContent(showsRemove: false)
            }
            .buttonStyle(.plain)
        } else {
            chipContent(showsRemove: false)
                .accessibilityLabel(label)
        }
    }

    private func chipContent(showsRemove: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.footnote)
                .lineLimit(1)
                .foregroundStyle(isEmphasised ? Color(.label) : Color(.secondaryLabel))

            if showsRemove {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, showsRemove ? 10 : 12)
        .padding(.vertical, 7)
        // Glass, not a flat fill: the bar these chips sit in has no background
        // of its own, so a chip floats directly over the photos and a
        // translucent system fill all but disappears against a bright one.
        .glassBackground(Capsule())
        .frame(minHeight: 44)
        .contentShape(Capsule())
    }
}

extension View {
    /// Dissolves the trailing edge of a horizontally scrolling chip row.
    ///
    /// The row ends right beside the pinned Edit/Clear capsule, and a chip cut
    /// off there by a straight edge reads as a chip *hidden behind the buttons*
    /// — which is what it looked like. A fade reads as a row that keeps going,
    /// and it is the only affordance a scroll view without a scroll bar has.
    /// It costs nothing when the chips fit: there is no content at that edge to
    /// fade out.
    func fadingTrailingEdge(_ width: CGFloat = ActiveConditionChip.scrollFadeWidth) -> some View {
        mask {
            HStack(spacing: 0) {
                Rectangle()
                LinearGradient(
                    colors: [.black, .black.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: width)
            }
        }
    }
}

/// Horizontal chips describing active search and filter conditions, with a
/// trailing Clear button that stays outside the scroll view.
struct FilterTokenBar: View {
    @Binding var criteria: FilterCriteria
    /// Read-only header (smart-album detail): show conditions but hide Clear
    /// and disable removal.
    var readOnly = false
    /// The ids the grid shows, for Delete Rejected (FS-01.12b §5): with the
    /// Rejected filter on, a red **Delete N** pill sits by Clear and sends
    /// exactly these photos' Rejected ones to the system's deletion. Nil on
    /// a bar with no grid behind it.
    var rejectedScope: (() -> [String])?
    /// Photos a Delete Rejected that reached a file or a server copy took
    /// out of the grid — no PhotoKit change arrives to say so.
    var onSourceDeletion: ((Set<String>) -> Void)?
    @Environment(PhotoMarks.self) private var photoMarks: PhotoMarks?
    @Environment(AppDependencies.self) private var dependencies: AppDependencies?
    @State private var sourceDeletion: DeletionTargetQueries.Request?

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tokens) { token in
                        if readOnly {
                            ActiveConditionChip(label: token.label)
                        } else {
                            ActiveConditionChip(
                                label: token.label,
                                removalAccessibilityLabel: token.removalAccessibilityLabel,
                                onRemove: { remove(token) }
                            )
                        }
                    }
                }
                .padding(.leading)
                .padding(.trailing, ActiveConditionChip.scrollFadeWidth)
                .padding(.vertical, 6)
            }
            .fadingTrailingEdge()

            if !readOnly {
                Button("Clear") {
                    criteria = .empty
                }
                .font(.footnote.weight(.medium))
                .tint(.primary)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .glassBackground(Capsule())
                .padding(.trailing, deletePillCount == nil ? AppTheme.Size.floatingChromeMargin : 8)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            }
            if let count = deletePillCount {
                deletePill(count)
                    .padding(.trailing, AppTheme.Size.floatingChromeMargin)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
        }
        .sourceDeletion($sourceDeletion) { removed, _ in onSourceDeletion?(removed) }
        // No background. The bar is floating chrome over the grid, like the
        // toolbar above it: a full-width fill — opaque or glass — draws a band
        // with a cut edge across the photos, and a second one against the
        // toolbar's own transparent strip, which is the seam Photos does not
        // have. The grid keeps its first row clear of the chips through its top
        // content inset instead (see `LibraryScreen.photoGrid`), and Clear
        // carries its own glass capsule so it stays legible once photos do
        // scroll behind it.
    }

    // MARK: Delete Rejected (FS-01.12b §5)

    private var rejectedIds: [String] {
        guard !readOnly, RejectedDeletion.showsPill(for: criteria), let rejectedScope, let photoMarks else { return [] }
        _ = photoMarks.version
        return RejectedDeletion.ids(visible: rejectedScope(), flag: photoMarks.flag(for:))
    }

    private var deletePillCount: Int? {
        let count = rejectedIds.count
        return count > 0 ? count : nil
    }

    /// 32pt red pill in a 44pt target, pinned beside Clear.
    private func deletePill(_ count: Int) -> some View {
        // One read per draw: the verb and the spoken name come from it.
        let plan = rejectedPlan
        return Button {
            let ids = rejectedIds
            guard let dependencies, !ids.isEmpty else { return }
            let roots = dependencies.folderRoots
            if let request = try? DeletionTargetQueries(database: dependencies.database, hasTrash: { roots.hasTrash($0) })
                .request(photoIds: ids, selection: .rejected) {
                sourceDeletion = request
                return
            }
            Task { _ = await RejectedDeleter.live(photoLibrary: dependencies.photoLibrary, banner: dependencies.banner).delete(ids) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                Text(MarkCopy.deletePill(count, verb: plan?.verb ?? .delete))
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Color.red, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(plan?.commandName ?? MarkCopy.deletePillAccessibility(count))
    }

    private var rejectedPlan: MixedDeletionPlan? {
        guard let dependencies else { return nil }
        let roots = dependencies.folderRoots
        return try? DeletionTargetQueries(database: dependencies.database, hasTrash: { roots.hasTrash($0) })
            .plan(photoIds: rejectedIds, selection: .rejected)
    }

    /// One active condition as a removable chip. Shared with the smart
    /// album's conditions bar, which appends these after its saved rules,
    /// and with the Mac's filter bar.
    typealias FilterToken = ActiveFilterToken

    private func remove(_ token: FilterToken) {
        var updated = criteria
        token.clear(&updated)
        criteria = updated
    }

    private var tokens: [FilterToken] { Self.tokens(for: criteria) }

    static func tokens(for criteria: FilterCriteria) -> [FilterToken] {
        ActiveFilterToken.tokens(for: criteria)
    }
}
