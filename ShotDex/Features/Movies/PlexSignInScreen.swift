import SwiftUI

/// Add a Source… › Plex Server (FS-23.07 §1, board `PH_PlexSignIn`): a
/// 4-character code to enter at plex.tv/link, then the account's servers —
/// the one on this network first — then its libraries, then Add.
struct PlexSignInScreen: View {
    /// The source was added; the sheet closes.
    let onAdded: () -> Void
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.openURL) private var openURL
    @Environment(\.appAccent) private var accent
    @State private var step: Step = .code(nil)
    @State private var failure: String?

    enum Step {
        case code(PlexClient.Pin?)
        case servers([PlexClient.Server])
        case libraries(PlexClient.Server, URL?, [PlexClient.Library], Set<String>)
        case adding
    }

    private let client = PlexClient()

    var body: some View {
        Group {
            switch step {
            case .code(let pin): codeView(pin)
            case .servers(let servers): serverList(servers)
            case .libraries(let server, let address, let libraries, let chosen): libraryList(server, address, libraries, chosen)
            case .adding:
                ProgressView(String(localized: "Looking for movies…", comment: "Plex: listing the chosen libraries"))
            }
        }
        .navigationTitle(String(localized: "Sign In to Plex", comment: "Plex sign-in title"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            String(localized: "Couldn't Sign In to Plex", comment: "Plex sign-in failed"),
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }),
            presenting: failure
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
    }

    // MARK: Code

    private func codeView(_ pin: PlexClient.Pin?) -> some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                // Markdown: the link name in bold, as on the board.
                Text(LocalizedStringKey(String(localized: "Go to **plex.tv/link** on any device and enter this code:", comment: "Plex sign-in instruction; keep the ** around plex.tv/link")))
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.top, AppTheme.Spacing.xxl)
                Text(spaced(pin?.code ?? "····"))
                    .font(.system(size: 52, weight: .bold, design: .rounded).monospaced())
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
                    .accessibilityLabel(String(localized: "Code \(spaced(pin?.code ?? ""))", comment: "Plex sign-in: the code, letter by letter"))
                Text(String(localized: "Waiting for plex.tv… A new code appears if this one expires.", comment: "Plex sign-in status"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    if let url = URL(string: "https://plex.tv/link") { openURL(url) }
                } label: {
                    Text(String(localized: "Open plex.tv/link", comment: "Plex sign-in: open the link page in Safari"))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(accent, in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, AppTheme.Spacing.lg)
                Text(String(localized: "This is your own Plex account. ShotDex keeps the sign-in on this iPhone only and reads your Plex libraries to stream and download movies.", comment: "Plex sign-in footer"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, AppTheme.Size.screenMargin)
        }
        .task { await waitForSignIn() }
    }

    private func spaced(_ code: String) -> String {
        code.map(String.init).joined(separator: " ")
    }

    /// A code, then plex.tv every 2 s; an expired code is replaced (§1).
    private func waitForSignIn() async {
        while !Task.isCancelled {
            guard let pin = try? await client.createPin() else {
                failure = String(localized: "plex.tv didn't answer. Check your connection and try again.", comment: "Plex sign-in: no code")
                return
            }
            step = .code(pin)
            while Date() < pin.expiresAt, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if let token = try? await client.token(for: pin) {
                    await loadServers(token)
                    return
                }
            }
        }
    }

    // MARK: Servers

    private func loadServers(_ token: String) async {
        do {
            let servers = try await client.servers(accountToken: token)
            step = .servers(servers)
        } catch {
            failure = String(localized: "plex.tv didn't list your servers.", comment: "Plex sign-in: no servers")
        }
    }

    private func serverList(_ servers: [PlexClient.Server]) -> some View {
        List {
            Section {
                ForEach(servers) { server in
                    Button {
                        Task { await choose(server) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.name)
                            if server.isOnThisNetwork {
                                Text(String(localized: "On this network", comment: "Plex: a server reachable at home"))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(minHeight: 44)
                    }
                    .tint(.primary)
                }
            } footer: {
                if servers.isEmpty {
                    Text(String(localized: "This Plex account has no servers.", comment: "Plex: an account with no servers"))
                }
            }
        }
    }

    private func choose(_ server: PlexClient.Server) async {
        let address = await client.fastestConnection(server)
        guard let address else {
            failure = String(localized: "\(server.name) didn't answer. Check that it is on and on this network.", comment: "Plex: the chosen server is out of reach")
            return
        }
        do {
            let libraries = try await client.libraries(server: address, token: server.accessToken)
            step = .libraries(server, address, libraries, Set(libraries.map(\.key)))
        } catch {
            failure = String(localized: "\(server.name) didn't list its libraries.", comment: "Plex: libraries failed")
        }
    }

    // MARK: Libraries

    private func libraryList(_ server: PlexClient.Server, _ address: URL?, _ libraries: [PlexClient.Library], _ chosen: Set<String>) -> some View {
        List {
            Section {
                ForEach(libraries) { library in
                    Button {
                        var next = chosen
                        if next.contains(library.key) { next.remove(library.key) } else { next.insert(library.key) }
                        step = .libraries(server, address, libraries, next)
                    } label: {
                        HStack {
                            Text(library.title)
                            Spacer()
                            if chosen.contains(library.key) {
                                Image(systemName: "checkmark").foregroundStyle(accent).accessibilityHidden(true)
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .tint(.primary)
                    .accessibilityAddTraits(chosen.contains(library.key) ? .isSelected : [])
                }
            } header: {
                Text(server.name)
            } footer: {
                Text(String(localized: "Movies stream at home; download the ones you want to take with you.", comment: "Plex: library list footer"))
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Add", comment: "Plex: add the server as a source")) {
                    step = .adding
                    Task {
                        // Every library chosen is stored as none: new ones join.
                        let keys = chosen.count == libraries.count ? [] : Array(chosen)
                        await dependencies.movieSync.addPlex(server, address: address, libraries: keys)
                        onAdded()
                    }
                }
                .disabled(chosen.isEmpty)
            }
        }
    }
}
