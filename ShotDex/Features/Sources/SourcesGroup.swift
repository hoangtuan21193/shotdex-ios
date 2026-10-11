import SwiftUI

/// The Sources group at the top of Collections on iPhone and the Duo cover
/// (board `PH_Sources`): every source with its count, Offline for one that
/// is away, and + to add one.
struct SourcesGroup: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var isAddingSource = false

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
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle.app(AppTheme.Radius.lg))
            Text("Photos stay where they are. Nothing is copied or moved. Rename, re-index or remove a source in Settings › Sources.",
                 comment: "Collections: footer under the Sources group")
                .font(.footnote)
                .foregroundStyle(Color(.secondaryLabel))
        }
        .padding(.horizontal)
        .onAppear { dependencies.sources.load() }
        .sheet(isPresented: $isAddingSource) {
            AddSourceSheet()
        }
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
