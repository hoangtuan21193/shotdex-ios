import SwiftUI

/// Where the card's photos go (board `MAC_Ingest`'s inspector, FS-20 §6):
/// the destination source and its folders, what happens after, and what
/// Import will do — or why it can't yet.
struct MacIngestInspector: View {
    @Bindable var model: IngestModel
    let readiness: IngestReadiness?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                destination
                divider
                afterImport
                summary.padding(.top, 16)
            }
            .padding(16)
        }
        .disabled(model.isRunning)
    }

    private var divider: some View { Divider().padding(.vertical, 14) }

    // MARK: Destination

    @ViewBuilder
    private var destination: some View {
        heading(String(localized: "Destination", comment: "Mac Import from Card inspector section"))
        if model.destinations.isEmpty {
            Text("Add a folder or drive in Sources first: imported photos join it.",
                 comment: "Mac Import from Card: no folder source to import into")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(String(localized: "Add Folder…", comment: "Mac menu: File › Add Folder…")) {
                NotificationCenter.default.post(name: .macAddFolder, object: nil)
            }
            .buttonStyle(MacPushButtonStyle(isDefault: false))
            .padding(.top, 8)
        } else {
            Picker(selection: $model.settings.destinationSourceId) {
                ForEach(model.destinations, id: \.id) { source in
                    Label(source.name, systemImage: MacSidebar.symbol(forSourceKind: source.kind)).tag(Optional(source.id))
                }
            } label: {
                Text("Destination", comment: "Mac Import from Card inspector section")
            }
            .labelsHidden()
            .accessibilityLabel(String(localized: "Destination", comment: "Mac Import from Card inspector section"))
            if let caption = destinationCaption {
                caption
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
            HStack(spacing: 8) {
                Text("Folders", comment: "Mac Import from Card: the folders photos are filed into")
                    .font(.system(size: 13))
                    .frame(width: 58, alignment: .leading)
                Picker(selection: $model.settings.folders) {
                    ForEach(Self.folderPresets, id: \.template) { preset in
                        Text(preset.title).tag(preset.template)
                    }
                    if !Self.folderPresets.contains(where: { $0.template == model.settings.folders }) {
                        Text(IngestCopy.foldersSummary(model.settings.folders)).tag(model.settings.folders)
                    }
                } label: {
                    Text("Folders", comment: "Mac Import from Card: the folders photos are filed into")
                }
                .labelsHidden()
            }
            .padding(.top, 12)
            if let folder = model.exampleFolder {
                Text(String(localized: "Example: \(folder)", comment: "Mac Import from Card: the folder the first photo goes into"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                    .padding(.leading, 66)
            }
        }
    }

    /// `Joins the T7 RAW Archive source · 1.31 TB free`, or that it is unplugged.
    private var destinationCaption: Text? {
        guard let source = model.destination, let drive = readiness?.destination else { return nil }
        guard drive.isConnected else {
            return Text("\(source.name) isn't connected.", comment: "Mac Import from Card: the destination drive is unplugged")
                .foregroundStyle(MacTheme.redText)
        }
        let joins = String(localized: "Joins the \(source.name) source", comment: "Mac Import from Card: imported photos become part of this source")
        guard let free = drive.freeBytes else { return Text(joins) }
        return Text(joins + " · " + String(localized: "\(IngestCopy.bytes(free)) free", comment: "Mac Import from Card: room left on the destination"))
    }

    static let folderPresets: [(title: String, template: IngestFolderTemplate)] = [
        (String(localized: "Year / Date", comment: "Mac Import from Card folders: 2026/2026-10-03"), .yearDate),
        (String(localized: "Date", comment: "Mac Import from Card folders: 2026-10-03"), IngestFolderTemplate(pattern: "{date}")),
        (String(localized: "None", comment: "Mac Import from Card folders: everything in the destination itself"), IngestFolderTemplate(pattern: "")),
    ]

    // MARK: After Import

    @ViewBuilder
    private var afterImport: some View {
        heading(String(localized: "After Import", comment: "Mac Import from Card inspector section"))
        Toggle(isOn: $model.settings.ejectsAfterImport) {
            Text("Eject \(model.card.name) after import", comment: "Mac Import from Card: eject the card once every copy is verified")
                .font(.system(size: 13))
        }
        .toggleStyle(.checkbox)
    }

    // MARK: Summary

    /// `811 photos · 24.6 GB` and what Import does — or what stops it.
    @ViewBuilder
    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            if readiness?.blocker == .nothingChecked {
                Text("Check the photos you want to import.", comment: "Mac Import from Card: nothing ticked yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if let blocker = readiness?.footer {
                Text(blocker)
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.redText)
            } else {
                Text(String(localized: "\(model.checkedCount) photos · \(IngestCopy.bytes(model.checkedBytes))",
                            comment: "Mac Import from Card: what Import copies"))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                Text(String(localized: "Copied to \(model.destination?.name ?? ""), then each copy is read back and checked against the card before it counts as imported.",
                            comment: "Mac Import from Card: what happens on Import"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MacTheme.fill, in: RoundedRectangle(cornerRadius: 10))
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }
}
