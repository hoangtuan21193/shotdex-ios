import SwiftUI

/// Destination (FS-20 §6): a folder source the photos join, or a new folder
/// that becomes one.
struct IngestDestinationScreen: View {
    @Bindable var model: IngestModel
    @Environment(AppDependencies.self) private var dependencies
    @State private var isPickingFolder = false

    var body: some View {
        Form {
            Section {
                ForEach(model.destinations, id: \.id) { source in
                    Button {
                        model.settings.destinationSourceId = source.id
                    } label: {
                        HStack {
                            Label(source.name, systemImage: source.kind == "drive" ? "externaldrive" : "folder")
                                .foregroundStyle(.primary)
                            Spacer()
                            if model.settings.destinationSourceId == source.id {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .accessibilityAddTraits(model.settings.destinationSourceId == source.id ? .isSelected : [])
                }
                Button {
                    isPickingFolder = true
                } label: {
                    Label(String(localized: "New Folder…", table: IngestCopy.table, comment: "Import destination: pick a folder that becomes a source"),
                          systemImage: "folder.badge.plus")
                }
            } footer: {
                Text("Photos join the folder's source in the library. A new folder becomes a source.", tableName: IngestCopy.table,
                     comment: "Import destination footer")
            }
        }
        .navigationTitle(Text("Destination", tableName: IngestCopy.table, comment: "Import option screen title"))
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $isPickingFolder, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            let runner = dependencies.folderSources
            Task {
                guard let id = try? await runner.add(folder: url, includesSubfolders: true, pairsRawAndJpeg: true) else { return }
                await dependencies.sources.read(sourceId: id)
                model.loadDestinations()
                model.settings.destinationSourceId = id
            }
        }
    }
}

/// Folders (FS-20 §6): the folders under the destination, `Year` / `Date`
/// from the day the photo was taken.
struct IngestFoldersScreen: View {
    @Bindable var model: IngestModel

    var body: some View {
        Form {
            Section {
                TextField(String(localized: "Folders", table: IngestCopy.table, comment: "Import folders field"),
                          text: $model.settings.folders.pattern)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack {
                    chip(String(localized: "Year", table: IngestCopy.table, comment: "Import folders token"), "{year}")
                    chip(String(localized: "Date", table: IngestCopy.table, comment: "Import folders token"), "{date}")
                    chip("/", "/")
                }
            } footer: {
                if let example = model.exampleFolder {
                    Text("Example: \(example.isEmpty ? "—" : example)", tableName: IngestCopy.table, comment: "Import folders example")
                }
            }
        }
        .navigationTitle(Text("Folders", tableName: IngestCopy.table, comment: "Import option screen title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func chip(_ title: String, _ token: String) -> some View {
        Button {
            model.settings.folders.pattern += token
        } label: {
            Label(title, systemImage: "plus")
                .font(.subheadline)
                .padding(.horizontal, AppTheme.Spacing.md)
                .frame(minHeight: AppTheme.Size.pillHeightLight)
                .background(Color(.secondarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}

/// Backup (FS-20 §6): a second copy, verified the same way, to any folder;
/// it does not join the library.
struct IngestBackupScreen: View {
    @Bindable var model: IngestModel
    @State private var isPickingFolder = false

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Also Copy to a Backup Drive", table: IngestCopy.table, comment: "Import backup switch"),
                       isOn: $model.settings.backsUp)
                if model.settings.backsUp {
                    Button {
                        isPickingFolder = true
                    } label: {
                        LabeledContent(String(localized: "Folder", table: IngestCopy.table, comment: "Import backup folder row"),
                                       value: model.settings.backupFolder?.title
                                           ?? String(localized: "Choose", table: IngestCopy.table, comment: "Import option: nothing chosen yet"))
                    }
                }
            } footer: {
                Text("Copied and verified the same way. Not added to the library.", tableName: IngestCopy.table, comment: "Import backup footer")
            }
        }
        .navigationTitle(Text("Backup", tableName: IngestCopy.table, comment: "Import option screen title"))
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $isPickingFolder, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
            model.settings.backupFolder = try? ExportFolderStore.folder(for: url)
        }
    }
}

/// File Names (FS-20 §6): a preset, or a template from the same eight chips
/// as Export (AC-25).
struct IngestFileNamesScreen: View {
    @Bindable var model: IngestModel

    var body: some View {
        Form {
            Section {
                ForEach(IngestSettings.namePresets, id: \.self) { template in
                    Button {
                        model.settings.nameTemplate = template.pattern
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(IngestCopy.nameTitle(template)).foregroundStyle(.primary)
                                Text(verbatim: template.pattern).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.settings.template == template {
                                Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.settings.template == template ? .isSelected : [])
                }
            }
            Section {
                TextField(ExportCopy.custom, text: $model.settings.nameTemplate)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                FileNameTokenGrid { chip in
                    model.settings.nameTemplate = chip.appended(to: model.settings.nameTemplate).pattern
                }
                .padding(.vertical, AppTheme.Spacing.xs)
                if let example = model.exampleName {
                    HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.md) {
                        Text(ExportCopy.exampleLabel).foregroundStyle(.secondary)
                        Text(verbatim: example).font(.subheadline.monospaced())
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text(ExportCopy.custom)
            }
        }
        .navigationTitle(Text("File Names", tableName: IngestCopy.table, comment: "Import option screen title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Metadata (FS-20 §6): Creator, Copyright, Keywords, written to a `.xmp`
/// beside each copy — the photos themselves are copied byte for byte.
struct IngestMetadataScreen: View {
    @Bindable var model: IngestModel
    @State private var keyword = ""

    var body: some View {
        Form {
            Section {
                TextField(String(localized: "Creator", table: IngestCopy.table, comment: "Import metadata field"),
                          text: $model.settings.metadata.creator)
                TextField(String(localized: "Copyright", table: IngestCopy.table, comment: "Import metadata field"),
                          text: $model.settings.metadata.copyright)
            }
            Section {
                ForEach(model.settings.metadata.keywords, id: \.self) { word in
                    Text(word)
                }
                .onDelete { model.settings.metadata.keywords.remove(atOffsets: $0) }
                TextField(String(localized: "Add Keyword", table: IngestCopy.table, comment: "Import metadata: new keyword field"), text: $keyword)
                    .submitLabel(.done)
                    .onSubmit {
                        let word = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !word.isEmpty, !model.settings.metadata.keywords.contains(word) { model.settings.metadata.keywords.append(word) }
                        keyword = ""
                    }
            } header: {
                Text("Keywords", tableName: IngestCopy.table, comment: "Import metadata section")
            } footer: {
                Text("Written to a .xmp sidecar next to each copy; the photos themselves are copied byte for byte.", tableName: IngestCopy.table,
                     comment: "Import metadata footer")
            }
        }
        .navigationTitle(Text("Metadata", tableName: IngestCopy.table, comment: "Import option screen title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
