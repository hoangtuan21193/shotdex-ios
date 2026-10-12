import Photos
import SwiftUI

/// The Bursts tab's list (FS-06.06 §7b): every burst the app can see,
/// newest first, straight from PhotoKit. A row's frame and suggestion counts
/// load when it shows, never for the whole library at once (NF-01 rule 1).
@MainActor
@Observable
final class BurstListModel {
    enum Phase: Equatable { case loading, ready }

    private(set) var rows: [BurstSummary] = []
    private(set) var phase: Phase = .loading
    @ObservationIgnored private let library: any BurstLibrary
    @ObservationIgnored private var counting: Set<String> = []

    init(library: any BurstLibrary) {
        self.library = library
    }

    /// Bursts still listed — a burst left with one frame drops out.
    var listed: [BurstSummary] { rows.filter(\.isListed) }

    func reload() async {
        let fresh = BurstSummary.sorted(await library.bursts())
        // Keep counts already read for bursts that are still here, so a
        // library change does not blank every row; they are re-read below.
        let known = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        rows = fresh.map { row in
            var row = row
            row.frameCount = known[row.id]?.frameCount
            row.suggestedCount = known[row.id]?.suggestedCount
            return row
        }
        phase = .ready
        for row in rows where row.frameCount != nil {
            await count(row.id, force: true)
        }
    }

    /// Reads one row's counts the first time it shows.
    func count(_ id: String, force: Bool = false) async {
        guard force || rows.first(where: { $0.id == id })?.frameCount == nil, !counting.contains(id) else { return }
        counting.insert(id)
        defer { counting.remove(id) }
        let frames = await library.frames(ofBurst: id)
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].frameCount = frames.count
        rows[index].suggestedCount = frames.filter(\.isSuggested).count
    }

    func asset(for id: String) -> PHAsset? { library.asset(for: id) }
}

/// The rows, or *No Bursts*. No Merge, no Rescan, no red button here.
struct BurstListView: View {
    let model: BurstListModel
    @Binding var openBurst: BurstFramesRequest?

    @Environment(PhotoLibraryService.self) private var photoLibrary

    static let minimumRowWidth: CGFloat = 340

    var body: some View {
        switch model.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        case .ready:
            if model.listed.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Bursts", comment: "Bursts tab: the library holds no burst"),
                    systemImage: "square.stack.3d.down.right",
                    description: Text("Photos taken in a burst show up here.", comment: "Bursts tab: empty-state description")
                )
                .padding(.top, 40)
            } else {
                // More rows on a wide screen, not wider ones.
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: Self.minimumRowWidth), spacing: AppTheme.Spacing.md, alignment: .top)],
                    spacing: AppTheme.Spacing.sm
                ) {
                    ForEach(model.listed) { row in
                        BurstRow(row: row, asset: model.asset(for: row.coverId), photoLibrary: photoLibrary) {
                            openBurst = BurstFramesRequest(burstId: row.id)
                        }
                        .task { await model.count(row.id) }
                    }
                }
            }
        }
    }
}

/// One burst: cover · `24 frames` · date · `2 suggested by Photos`.
private struct BurstRow: View {
    let row: BurstSummary
    let asset: PHAsset?
    let photoLibrary: PhotoLibraryService
    let onOpen: () -> Void

    static let cover: CGFloat = 64

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: AppTheme.Spacing.md) {
                CullThumbnail(asset: asset, photoLibrary: photoLibrary, side: Self.cover)
                    .frame(width: Self.cover, height: Self.cover)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.framesTitle ?? " ")
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .redacted(reason: row.framesTitle == nil ? .placeholder : [])
                    if let date = row.date {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(row.suggestionTitle ?? " ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .redacted(reason: row.suggestionTitle == nil ? .placeholder : [])
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(AppTheme.Spacing.md)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the frames to choose which to keep", comment: "Bursts tab: VoiceOver hint on a row"))
    }
}
