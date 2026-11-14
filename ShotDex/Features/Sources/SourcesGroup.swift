import SwiftUI

/// The Sources group at the top of Collections on iPhone and the Duo cover
/// (board `PH_Sources`): every source with its count, Offline for one that
/// is away, and + to add one.
struct SourcesGroup: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var isAddingSource = false
    /// The card whose Import from Card screen is up (FS-20 §4).
    @State private var openCard: RememberedCard?

    var body: some View {
        let rows = dependencies.sources.rows
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Text("Sources", comment: "Collections: the group of places photos come from")
                    .font(.title2.bold())
                Spacer()
                Button { isAddingSource = true } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Add a Source", comment: "Collections: + beside Sources"))
            }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().padding(.leading, 52) }
                    rowView(row)
                }
                // A card plugged in shows here within 2 s and opens nothing
                // until tapped (FS-20 AC-19).
                ForEach(dependencies.cards.connectedCards) { card in
                    Divider().padding(.leading, 52)
                    Button { openCard = card } label: { cardRow(card) }
                        .buttonStyle(.plain)
                }
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle.app(AppTheme.Radius.lg))
            Text("Photos stay where they are. Nothing is copied or moved. Rename, re-index or remove a source in Settings › Sources.",
                 comment: "Collections: footer under the Sources group")
                .font(.footnote)
                .foregroundStyle(Color(.secondaryLabel))
        }
        .padding(.horizontal)
        .onAppear {
            dependencies.sources.refresh()
            #if DEBUG
            dependencies.cards.seedIfAsked()
            #endif
            dependencies.cards.startWatching()
        }
        .fullScreenCover(item: $openCard) { card in
            if let root = dependencies.cards.connected[card.id] {
                IngestScreen(model: dependencies.ingest.model(for: card, root: root, dependencies: dependencies))
                    .environment(dependencies)
            }
        }
        .sheet(isPresented: $isAddingSource) {
            AddSourceSheet()
        }
    }

    /// Board `PH_Sources`: the card's name, and under it what it holds —
    /// how many photos are new once its screen has read it, or how far the
    /// import has got.
    private func cardRow(_ card: RememberedCard) -> some View {
        let model = dependencies.ingest.models[card.id]
        return HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "sdcard")
                .frame(width: 24)
                .foregroundStyle(Color(.secondaryLabel))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.name).lineLimit(1)
                Text(cardDetail(model))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(1)
            }
            Spacer(minLength: AppTheme.Spacing.sm)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(.tertiaryLabel))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Import from Card", tableName: IngestCopy.table, comment: "VoiceOver hint of a card's row in Sources"))
    }

    private func cardDetail(_ model: IngestModel?) -> String {
        let kind = String(localized: "Memory card", table: IngestCopy.table, comment: "Collections: what a card row is")
        guard let model else { return kind }
        if model.isRunning {
            return String(localized: "Importing \(model.progress.fraction.formatted(.percent.precision(.fractionLength(0))))",
                          table: IngestCopy.table, comment: "Collections: a card being imported, with its progress")
        }
        guard model.phase != .loading else { return kind }
        return kind + " · " + String(localized: "\(model.newCount) new photos", table: IngestCopy.table,
                                     comment: "Collections: new photos on a card")
    }

    private func rowView(_ row: SourcesModel.Row) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: SourceRowView.systemImage(row.text.kind))
                .frame(width: 24)
                .foregroundStyle(Color(.secondaryLabel))
                .accessibilityHidden(true)
            Text(row.name)
                .foregroundStyle(row.text.isOffline ? Color(.secondaryLabel) : Color(.label))
                .lineLimit(1)
            Spacer(minLength: AppTheme.Spacing.sm)
            if row.text.isOffline {
                Label(String(localized: "Offline", comment: "Collections: a source that is unplugged or unreachable"), systemImage: "bolt.horizontal.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.secondaryLabel))
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, 3)
                    .background(Color(.tertiarySystemFill), in: Capsule())
            } else {
                Text(row.text.count.formatted())
                    .monospacedDigit()
                    .foregroundStyle(Color(.secondaryLabel))
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}
