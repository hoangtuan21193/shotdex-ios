import SwiftUI

/// What the Keep sheet was raised for: a set of photos, or a whole album.
struct KeepRequest: Identifiable {
    struct Album {
        let id: String
        let title: String
    }

    let id = UUID()
    let ids: [String]
    var album: Album?

    /// The menu row, the same wherever it is offered.
    static var menuTitle: String {
        String(localized: "Keep on This \(KeepDevice.name)…", comment: "Menu row: keep the photos on the device for offline use")
    }
}

/// "iPhone" or "iPad" — the device the copies are kept on, so an iPad says
/// On This iPad the way Files says On My iPad. The Duo is an iPhone.
enum KeepDevice {
    static var name: String {
        UIDevice.current.userInterfaceIdiom == .pad
            ? String(localized: "iPad", comment: "Keep on This iPad: the device kept copies live on, as in On This iPad")
            : String(localized: "iPhone", comment: "Keep on This iPhone: the device kept copies live on, as in On This iPhone")
    }
}

/// Keep on This iPhone (board `PH_KeepOnIPhone`): asked once per keep —
/// Viewing Copies (the default) or Originals, with what each costs and what
/// is free — and, for an album, whether photos added later come too.
struct KeepOnIPhoneSheet: View {
    let request: KeepRequest

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isDuoInner) private var isDuoInner
    @State private var quality: KeepQuality = .viewingCopy
    @State private var keepsNewPhotos = true
    @State private var estimate = KeepEstimate()
    @State private var freeSpace: Int64?

    private var bytes: Int64 { estimate.bytes(for: quality) }

    /// Short of room once the headroom is counted: Keep is off and says why.
    private var shortfall: Int64? {
        DeviceSpaceCheck.shortfall(for: bytes, free: freeSpace)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    qualityRow(.viewingCopy,
                               title: String(localized: "Viewing Copies", comment: "Keep sheet option: smaller copies for looking at"),
                               detail: String(localized: "Photos up to 2732 px · videos 1080p", comment: "Keep sheet: what a viewing copy is"))
                    qualityRow(.original,
                               title: String(localized: "Originals", comment: "Keep sheet option: the full files"),
                               detail: String(localized: "Full files, RAW and 4K included", comment: "Keep sheet: what an original is"))
                } header: {
                    Text("Keep", comment: "Keep sheet: section header over Viewing Copies / Originals")
                }

                if request.album != nil {
                    Section {
                        Toggle(String(localized: "Keep New Photos Added Later", comment: "Keep sheet: an album keeps photos added to it later"),
                               isOn: $keepsNewPhotos)
                    }
                }

            }
            .navigationTitle(String(localized: "Keep on This \(KeepDevice.name)", comment: "Keep sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }
                        .tint(.primary)
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("Keep on This \(KeepDevice.name)", comment: "Keep sheet title").font(.headline)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: AppTheme.Spacing.md) {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(shortfall == nil ? Color.secondary : Color(.systemRed))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                Button(action: keep) {
                    Text(keepTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(shortfall != nil || request.ids.isEmpty)
                .padding(.horizontal)
                }
                .padding(.bottom, AppTheme.Spacing.sm)
            }
        }
        // Sized to the options, the footer and the button — a full-height
        // sheet left half the screen empty. The Duo's inner form sheet is
        // 652pt wide, so the footer wraps to fewer lines than on a phone and
        // the phone height left ~120pt blank; nothing scrolls, so no `.large`.
        .presentationDetents(isDuoInner
            ? [.height(request.album == nil ? 430 : 500)]
            : [.height(request.album == nil ? 520 : 590), .large])
        .task {
            estimate = (try? dependencies.kept.estimate(ids: request.ids)) ?? KeepEstimate(photos: request.ids.count)
            freeSpace = KeptFileStore.freeSpace()
        }
    }

    private func qualityRow(_ value: KeepQuality, title: String, detail: String) -> some View {
        Button {
            quality = value
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Color(.label))
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(Self.format(estimate.bytes(for: value)))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .opacity(quality == value ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        // Plain: a Form button tints its whole label, detail and size too.
        .buttonStyle(.plain)
        .accessibilityAddTraits(quality == value ? .isSelected : [])
    }

    private var subtitle: String {
        let counts = [
            estimate.photos > 0 ? String(localized: "\(estimate.photos) photos", comment: "Keep sheet subtitle: photo count") : nil,
            estimate.videos > 0 ? String(localized: "\(estimate.videos) videos", comment: "Keep sheet subtitle: video count") : nil,
        ].compactMap { $0 }
        return ([request.album?.title].compactMap { $0 } + counts).joined(separator: " · ")
    }

    private var keepTitle: String {
        request.ids.count == 1
            ? String(localized: "Keep 1 Item", comment: "Keep sheet button for one photo or video")
            : String(localized: "Keep \(request.ids.count) Items", comment: "Keep sheet button: start keeping this many photos and videos")
    }

    private var footer: String {
        if let shortfall {
            return String(localized: "Not enough space. Free up \(Self.format(shortfall)) on this \(KeepDevice.name), or keep viewing copies.",
                          comment: "Keep sheet footer when the device is too full")
        }
        let free = freeSpace.map(Self.format) ?? "—"
        return String(localized: "Uses about \(Self.format(bytes)) of the \(free) free on this \(KeepDevice.name). Kept copies open without a connection, are not uploaded to iCloud or included in your \(KeepDevice.name) backup, and stay until you remove them in Utilities › On This \(KeepDevice.name).",
                      comment: "Keep sheet footer: the space it takes and what a kept copy is")
    }

    private func keep() {
        if let album = request.album {
            dependencies.keepRunner.keepAlbum(id: album.id, title: album.title, quality: quality, keepsNewPhotos: keepsNewPhotos)
        } else {
            dependencies.keepRunner.keep(ids: request.ids, quality: quality)
        }
        dependencies.banner.show(request.ids.count == 1
            ? String(localized: "Keeping 1 item on this \(KeepDevice.name)", comment: "Banner after Keep on This iPhone, one item")
            : String(localized: "Keeping \(request.ids.count) items on this \(KeepDevice.name)", comment: "Banner after Keep on This iPhone"))
        dismiss()
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

extension View {
    /// Hosts the Keep sheet for a request binding — the root tab view for
    /// selections and album menus, the viewer for its own ⋯ menu (a sheet at
    /// the root cannot rise over the viewer's full-screen cover).
    func keepOnIPhonePresenter(_ request: Binding<KeepRequest?>) -> some View {
        sheet(item: request) { KeepOnIPhoneSheet(request: $0) }
    }
}
