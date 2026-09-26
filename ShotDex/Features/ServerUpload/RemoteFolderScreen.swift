import SwiftUI

/// One screen of the folder browser: a folder on the server.
struct RemoteFolderRoute: Hashable {
    let path: String

    /// The screens from the top down to `folder` — the browser opens at the
    /// chosen folder with Back walking up to the root.
    static func chain(to folder: String) -> [RemoteFolderRoute] {
        var routes = [RemoteFolderRoute(path: "")]
        var current = ""
        for component in ServerUploadPath.normalizedFolder(folder).split(separator: "/") {
            current = ServerUploadPath.join(current, String(component))
            routes.append(RemoteFolderRoute(path: current))
        }
        return routes
    }
}

/// Upload to Server → Folder (FS-15.02 §2a): the folders inside one folder
/// on the server, Use This Folder, and New Folder. Tier A.
struct RemoteFolderScreen: View {
    let path: String
    let title: String
    let browser: RemoteFolderBrowser
    /// Pushes a folder that is not a row yet — the one New Folder made.
    let onOpen: (String) -> Void
    let onChoose: (String) -> Void
    @State private var isNamingFolder = false
    @State private var newName = ""

    var body: some View {
        List {
            Section {
                Button {
                    onChoose(path)
                } label: {
                    Label("Use This Folder", systemImage: "checkmark.circle")
                }
            }
            switch browser.listing(for: path) {
            case .loading:
                Section {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading Folders…")
                            .foregroundStyle(.secondary)
                    }
                }
            case .failed(let error):
                Section {
                    Text(error.localizedDescription)
                        .foregroundStyle(.secondary)
                    Button("Try Again") {
                        Task { await browser.load(path, force: true) }
                    }
                }
            case .loaded(let names):
                Section {
                    if names.isEmpty {
                        Text("No folders inside.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(names, id: \.self) { name in
                            NavigationLink(value: RemoteFolderRoute(path: ServerUploadPath.join(path, name))) {
                                Label(name, systemImage: "folder")
                            }
                        }
                    }
                } header: {
                    Text("Folders")
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newName = ""
                    isNamingFolder = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .accessibilityLabel("New Folder")
            }
        }
        .alert("New Folder", isPresented: $isNamingFolder) {
            TextField("Name", text: $newName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Create") {
                let name = newName
                Task {
                    if let created = await browser.createFolder(named: name, in: path) { onOpen(created) }
                }
            }
            .disabled(RemoteFolderListing.validatedName(newName) == nil)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The folder is created on the server inside \(title).", comment: "Upload to Server: New Folder alert message")
        }
        .alert(
            "Couldn't Create Folder",
            isPresented: Binding(get: { browser.createError != nil }, set: { if !$0 { browser.createError = nil } }),
            presenting: browser.createError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0.localizedDescription) }
        .task { await browser.load(path) }
    }
}
