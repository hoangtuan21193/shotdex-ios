import SwiftUI

/// The read of a folder or drive (board `MAC_SourceIndexing`, FS-19.01 §4):
/// a banner over the grid that never blocks it — photos take their place by
/// capture date as they are read. Pause keeps what was read; the close hides
/// the banner and the sidebar foot keeps the line.
struct MacSourceReadBanner: View {
    let progress: SourceReadProgress
    let pause: () -> Void
    let resume: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 18))
                .foregroundStyle(MacTheme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(progress.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(detail(now: context.date))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 12)
            MacProgressBar(fraction: progress.fraction)
                .frame(width: 140)
                .accessibilityLabel(String(localized: "Adding progress", comment: "Mac source read banner: progress bar, VoiceOver"))
            Text(progress.fraction, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)
            if !progress.isDisconnected {
                Button(progress.isPaused ? String(localized: "Resume", comment: "Mac source read banner: carry on reading")
                                         : String(localized: "Pause", comment: "Mac source read banner: stop for now, keep what was read"),
                       action: progress.isPaused ? resume : pause)
                    .buttonStyle(MacPushButtonStyle(isDefault: false))
                    .fixedSize()
            }
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(String(localized: "Hide Banner", comment: "Mac source read banner: close"))
            .accessibilityLabel(String(localized: "Hide Banner", comment: "Mac source read banner: close"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 48)
        // The system's glass, as the toolbar's capsules: no hand-made shadow.
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(MacTheme.separator))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(progress.title)
    }

    /// The board's line: progress, time, and what happens meanwhile.
    private func detail(now: Date) -> String {
        guard !progress.isPaused, !progress.isDisconnected else { return progress.detail(now: now) }
        return progress.detail(now: now) + " · " + String(localized: "they take their place by capture date as they are read · previews come from each file's embedded JPEG",
                                                    comment: "Mac source read banner: what happens while a folder is read")
    }
}

/// A drive or server that is not connected (FS-19.01b §2): its photos stay,
/// and the banner says what still works and how to bring it back.
struct MacSourceOfflineBanner: View {
    let name: String
    let photoCount: Int
    let isServer: Bool
    let locate: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(MacTheme.fill)
                .frame(width: 28, height: 28)
                .overlay(Image(systemName: isServer ? "server.rack" : "externaldrive").font(.system(size: 16)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(name) is offline", comment: "Mac offline source banner: title")
                    .font(.system(size: 13, weight: .semibold))
                Text(isServer
                     ? String(localized: "Its \(photoCount) photos stay in your library. You can still browse, search and sort them; connect to the server to open originals.",
                              comment: "Mac offline source banner: a server (plural)")
                     : String(localized: "Its \(photoCount) photos stay in your library. You can still browse, search and sort them; connect the drive to open originals.",
                              comment: "Mac offline source banner: a drive (plural)"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !isServer {
                Button(String(localized: "Locate…", comment: "Mac offline source banner: point at where the folder is now"), action: locate)
                    .buttonStyle(MacPushButtonStyle(isDefault: false))
                    .fixedSize()
                    .accessibilityLabel(String(localized: "Locate \(name)", comment: "Mac offline source banner: Locate, VoiceOver"))
            }
            Button(String(localized: "Remove Source…", comment: "Mac offline source banner: remove the source"), action: remove)
                .buttonStyle(MacPushButtonStyle(isDefault: false))
                .fixedSize()
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .background(RoundedRectangle(cornerRadius: 12).fill(MacTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(MacTheme.separator))
        .accessibilityElement(children: .contain)
    }
}

/// A 4pt bar, radius 2: amber on the `sep` track (board `MAC_SourceIndexing`).
struct MacProgressBar: View {
    let fraction: Double

    var body: some View {
        Capsule().fill(MacTheme.separator)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(MacTheme.accent).frame(width: proxy.size.width * min(1, max(0, fraction)))
                }
            }
            .frame(height: 4)
            .accessibilityElement()
            .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}

/// The 14pt ring on a source row being read: amber arc from twelve o'clock.
struct MacProgressRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(MacTheme.separator, lineWidth: 1.75)
            Circle().trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(MacTheme.accent, style: StrokeStyle(lineWidth: 1.75, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 14, height: 14)
    }
}

/// Reads the read's progress itself, so its ten updates a second redraw
/// the banner and not the window around it.
struct MacSourceReadBannerHost: View {
    let model: SourcesModel
    /// The source whose banner was closed while it ran (the foot keeps it).
    @Binding var hiddenSourceId: String?

    var body: some View {
        if let progress = model.readProgress, hiddenSourceId != progress.sourceId {
            MacSourceReadBanner(progress: progress,
                                pause: { model.pauseRead() },
                                resume: { Task { await model.resumeRead() } },
                                // Hides the banner only: the foot keeps the
                                // line, and a click on it brings this back.
                                close: { hiddenSourceId = progress.sourceId })
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
    }
}

/// Several sources offline, away from their own rows: one line naming them,
/// each name opening that source (and its full banner).
struct MacOfflineSummary: View {
    let names: [String]
    let open: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "externaldrive").foregroundStyle(.secondary)
            Text("\(names.count) sources offline:", comment: "Mac: several sources not connected (plural)")
                .foregroundStyle(.secondary)
            ForEach(names, id: \.self) { name in
                Button(name) { open(name) }.buttonStyle(.link)
            }
            Spacer()
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 10).fill(MacTheme.fill))
    }
}
