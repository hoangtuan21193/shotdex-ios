import SwiftUI

/// A card import in Activity (FS-20 §7, board `MAC_IngestProgress`): where
/// it goes and how far, Pause / Resume and Stop Import…, the Copy · Verify
/// · Backup bars, the photos either side of the one in hand, and what
/// happens to each copy. Reads the run's own observable state; nothing is
/// queried here.
struct MacIngestActivityCard: View {
    let model: IngestModel
    /// Stop Import… asked: the window holds the question (the popover
    /// closes first).
    let askStop: () -> Void

    private var backsUp: Bool { model.settings.backsUp && model.settings.backupFolder != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            bars
            fileList
            Text(MacIngestActivityWords.footnote(model))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(MacTheme.separator))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(MacIngestActivityWords.title(model))
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sdcard")
                .font(.system(size: 14))
                .foregroundStyle(model.isPaused ? Color.secondary : MacTheme.accent)
                .frame(width: 28, height: 28)
                .background(model.isPaused ? MacTheme.fill : MacTheme.accentSoft, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(MacIngestActivityWords.title(model))
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(String(localized: "\(model.progress.done.formatted()) of \(model.progress.total.formatted())",
                                comment: "Mac Activity › card import: photos done of all"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                MacIngestBar(fraction: MacIngestActivityWords.copyFraction(model), isWaiting: model.isParked, height: 5)
                    .accessibilityHidden(true)
                Text(MacIngestActivityWords.line(model))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: 6) {
                iconButton(model.isPaused ? "play.fill" : "pause.fill",
                           model.isPaused
                           ? String(localized: "Resume", comment: "Mac Activity › card import: carry on after Pause")
                           : String(localized: "Pause", comment: "Mac Activity › card import: wait after the photo in hand"),
                           identifier: "ingest.pause") {
                    model.isPaused ? model.resume() : model.pause()
                }
                iconButton("stop.fill", String(localized: "Stop Import…", comment: "Mac Activity › card import: stop the run, asks first"),
                           identifier: "ingest.stop", action: askStop)
            }
            .disabled(model.isStopping)
        }
    }

    private func iconButton(_ symbol: String, _ label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline)
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(MacIngestSquareButtonStyle())
        .help(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    // MARK: Bars

    private var bars: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
            if model.runKind != .backupOnly {
                barRow(String(localized: "Copy", comment: "Mac Activity › card import: the copy bar"),
                       MacIngestActivityWords.copyFraction(model),
                       String(localized: "\(max(0, model.progress.done - model.failedCount).formatted()) of \(model.progress.total.formatted()) copied",
                              comment: "Mac Activity › card import: photos copied of all"))
                barRow(String(localized: "Verify", comment: "Mac Activity › card import: the verify bar"),
                       fraction(model.verifiedCount),
                       String(localized: "\(model.verifiedCount.formatted()) verified", comment: "Mac Activity › card import: photos whose copy matches the card"))
            }
            if backsUp {
                barRow(String(localized: "Backup", comment: "Mac Activity › card import: the backup bar"),
                       fraction(model.backedUpCount),
                       String(localized: "\(model.backedUpCount.formatted()) on \(MacIngestActivityWords.backupName(model))",
                              comment: "Mac Activity › card import: photos on the backup drive"))
            }
        }
        .font(.subheadline)
        .padding(.leading, 38)
    }

    private func barRow(_ title: String, _ fraction: Double, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
            MacIngestBar(fraction: fraction, isWaiting: model.isParked)
                .frame(maxWidth: .infinity)
            // A fixed column: the three bars keep one width whatever the words.
            Text(value).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                .frame(width: 132, alignment: .trailing)
        }
        .frame(height: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private func fraction(_ count: Int) -> Double {
        model.progress.total > 0 ? min(1, Double(count) / Double(model.progress.total)) : 0
    }

    // MARK: Files

    private var fileList: some View {
        let rows = model.files.rows
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                MacIngestFileRow(row: row, root: model.root, backsUp: backsUp, isAlternate: index.isMultiple(of: 2) == false)
            }
        }
        .background(MacTheme.content)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(MacTheme.separator))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Files", comment: "Mac Activity › card import: the list of photos either side of the one in hand"))
    }
}

/// The sidebar's foot while a card import runs (board `MAC_IngestProgress`):
/// `Importing from EOS_DIGITAL 51%` and its bar, a click away from Activity.
struct MacIngestFoot: View {
    let model: IngestModel

    var body: some View {
        let fraction = MacIngestActivityWords.copyFraction(model)
        let percent = fraction.formatted(.percent.precision(.fractionLength(0)))
        Button {
            MacWindowRequest.showsActivity = true
            NotificationCenter.default.post(name: .macShowActivity, object: nil)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(MacIngestActivityWords.title(model)).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(MacIngestActivityWords.footState(model) ?? percent)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.caption)
                MacIngestBar(fraction: fraction, isWaiting: model.isParked)
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(MacTheme.fill, in: RoundedRectangle(cornerRadius: 10))
            // The sidebar list scrolls under the foot: an opaque base under the fill.
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .help(String(localized: "Show the import in Activity", comment: "Mac sidebar foot: card import tooltip"))
        .accessibilityLabel(MacIngestActivityWords.title(model))
        .accessibilityValue(MacIngestActivityWords.footState(model) ?? percent)
        .accessibilityIdentifier("ingest.foot")
    }
}

/// One photo in the list: preview, name, and its step — a mini bar while
/// it copies, a green check once its copy reads back as the card's bytes.
private struct MacIngestFileRow: View {
    let row: IngestFileList.Row
    let root: URL
    let backsUp: Bool
    var isAlternate = false
    @State private var image: CGImage?

    private var isInHand: Bool {
        switch row.state {
        case .copying, .verifying, .backingUp: true
        default: false
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                MacTheme.fill2
                if let image { Image(decorative: image, scale: 1).resizable().scaledToFill() }
            }
            .frame(width: 20, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(row.name)
                .font(.subheadline)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 118, alignment: .leading)
            status
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(isInHand ? MacTheme.accentSoft : (isAlternate ? MacTheme.rowAlternate : Color.clear))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.name)
        .accessibilityValue(MacIngestActivityWords.status(row, backsUp: backsUp))
        .task(id: row.id) {
            image = await MacCardThumbnails.shared.image(for: row.id, on: root)
        }
    }

    @ViewBuilder
    private var status: some View {
        let words = MacIngestActivityWords.status(row, backsUp: backsUp)
        switch row.state {
        case .copying(let fraction):
            MacIngestBar(fraction: fraction, isWaiting: false).frame(width: 72)
            Text(words).font(.subheadline).monospacedDigit()
        case .verifying, .backingUp:
            ProgressView().controlSize(.mini)
            Text(words).font(.subheadline)
        case .verified, .backedUp:
            Label(words, systemImage: "checkmark.circle")
                .font(.subheadline)
                .foregroundStyle(MacTheme.greenText)
                .labelStyle(MacIngestStatusLabelStyle())
        case .failed, .backupFailed:
            Label(words, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(MacTheme.redText)
                .labelStyle(MacIngestStatusLabelStyle())
        case .waiting:
            Text(words).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}

private struct MacIngestStatusLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 11))
            configuration.title
        }
    }
}

/// A 4pt capsule bar in the accent; grey while the run waits.
struct MacIngestBar: View {
    let fraction: Double
    var isWaiting = false
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(MacTheme.separator)
                Capsule().fill(isWaiting ? Color.secondary.opacity(0.5) : MacTheme.accent)
                    .frame(width: geometry.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: height)
    }
}

/// Board `MAC_IngestProgress`: a 26×24 filled square around a glyph.
private struct MacIngestSquareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(MacTheme.fill, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).fill(configuration.isPressed ? MacTheme.pressed : .clear))
    }
}

/// The card's and the foot's words, worked out from the run.
@MainActor
enum MacIngestActivityWords {
    static func title(_ model: IngestModel) -> String {
        switch model.runKind {
        case .fresh:
            String(localized: "Importing from \(model.card.name)", comment: "Mac Activity › card import: title; the argument is the card's name")
        case .rest:
            String(localized: "Importing the rest from \(model.card.name)", comment: "Mac Activity › card import: Import Remaining or Retry Failed is running")
        case .backupOnly:
            String(localized: "Backing up from \(model.card.name)", comment: "Mac Activity › card import: Back Up Remaining is running")
        }
    }

    /// The foot's word in place of the percent, when there is one.
    static func footState(_ model: IngestModel) -> String? {
        if model.isStopping { return String(localized: "Stopping…", comment: "Mac sidebar foot: the card import is stopping") }
        if model.isParked { return String(localized: "Paused", comment: "Mac sidebar foot: the card import is paused") }
        if model.isPaused { return String(localized: "Pausing…", comment: "Mac sidebar foot: Pause pressed, the photo in hand finishing") }
        return nil
    }

    /// Bytes in, the photo in hand included.
    static func copyFraction(_ model: IngestModel) -> Double {
        min(1, model.liveProgress.fraction)
    }

    /// `To T7 RAW Archive › RAW/2026 · 12.6 GB of 24.6 GB · 2 min left`.
    static func line(_ model: IngestModel) -> String {
        var place = model.destination?.name ?? ""
        if let folder = model.files.folder, !folder.isEmpty { place += " › " + folder }
        var parts = [String(localized: "To \(place)", comment: "Mac Activity › card import: where the photos go")]
        if model.progress.bytesTotal > 0 {
            let done = model.copiedBytes.formatted(.byteCount(style: .file))
            let total = model.progress.bytesTotal.formatted(.byteCount(style: .file))
            parts.append(String(localized: "\(done) of \(total)", comment: "Mac Activity › card import: bytes copied of all"))
        }
        if model.isStopping {
            parts.append(String(localized: "Stopping…", comment: "Mac Activity › card import: Stop pressed, the file in hand finishing"))
        } else if model.isParked {
            parts.append(String(localized: "Paused", comment: "Mac Activity › card import: the run waits after Pause"))
        } else if model.isPaused {
            parts.append(String(localized: "Pausing after this photo…", comment: "Mac Activity › card import: Pause pressed, the photo in hand finishes first"))
        } else if let seconds = model.secondsLeft {
            parts.append(seconds < 60
                         ? String(localized: "less than a minute left", comment: "Mac Activity › card import: time left")
                         : String(localized: "\((seconds + 59) / 60) min left", comment: "Mac Activity › card import: time left in minutes"))
        }
        return parts.joined(separator: " · ")
    }

    static func backupName(_ model: IngestModel) -> String {
        guard let folder = model.settings.backupFolder else { return "" }
        return folder.place.isEmpty ? folder.name : folder.place
    }

    static func status(_ row: IngestFileList.Row, backsUp: Bool) -> String {
        switch row.state {
        case .waiting:
            String(localized: "Waiting · \(row.bytes.formatted(.byteCount(style: .file)))", comment: "Mac Activity › card import: a photo not started; the argument is its size")
        case .copying(let fraction):
            String(localized: "Copying · \(fraction.formatted(.percent.precision(.fractionLength(0))))", comment: "Mac Activity › card import: a photo going in")
        case .verifying:
            String(localized: "Verifying…", comment: "Mac Activity › card import: the copy is read back against the card")
        case .verified:
            String(localized: "Verified", comment: "Mac Activity › card import: the copy matches the card")
        case .backingUp:
            String(localized: "Verified · backing up", comment: "Mac Activity › card import: verified, its backup copy going")
        case .backedUp:
            String(localized: "Verified · backed up", comment: "Mac Activity › card import: verified, and on the backup drive too")
        case .failed:
            String(localized: "Couldn't copy", comment: "Mac Activity › card import: this photo failed; Retry Failed comes at the end")
        case .backupFailed:
            String(localized: "Verified · backup failed", comment: "Mac Activity › card import: in the destination, but its backup copy failed")
        }
    }

    /// `399 more waiting. Each copy is checked with SHA-256 after it lands
    /// and gets an .xmp sidecar with the <Creator> metadata. EOS_DIGITAL
    /// ejects when every copy is verified.`
    static func footnote(_ model: IngestModel) -> String {
        var sentences: [String] = []
        if model.failedCount > 0 {
            sentences.append(String(AttributedString(localized: "^[\(model.failedCount) photo](inflect: true) couldn't be copied — Retry Failed when the import ends.",
                                                     comment: "Mac Activity › card import: failures so far").characters))
        }
        let more = model.files.moreWaiting
        if more > 0 {
            sentences.append(String(AttributedString(localized: "^[\(more) more photo](inflect: true) waiting.",
                                                     comment: "Mac Activity › card import: photos waiting below the list").characters))
        }
        let metadata = model.settings.metadata
        let creator = metadata.creator.trimmingCharacters(in: .whitespacesAndNewlines)
        if !creator.isEmpty {
            sentences.append(String(localized: "Each copy is checked with SHA-256 after it lands and gets an .xmp sidecar with the \(creator) metadata.",
                                    comment: "Mac Activity › card import: what happens to each copy; the argument is the Creator"))
        } else if !metadata.copyright.isEmpty || !metadata.keywords.isEmpty {
            sentences.append(String(localized: "Each copy is checked with SHA-256 after it lands and gets an .xmp sidecar with your metadata.",
                                    comment: "Mac Activity › card import: what happens to each copy"))
        } else {
            sentences.append(String(localized: "Each copy is checked with SHA-256 after it lands.",
                                    comment: "Mac Activity › card import: what happens to each copy"))
        }
        if model.settings.ejectsAfterImport {
            sentences.append(String(localized: "\(model.card.name) ejects when every copy is verified.",
                                    comment: "Mac Activity › card import: After Import › Eject is on"))
        }
        return sentences.joined(separator: " ")
    }
}
