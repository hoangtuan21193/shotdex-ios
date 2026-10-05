import SwiftUI

/// What the "Your library" card says (FS-08.01b §1), worked out from the index
/// counts — pure, so each state has a test rather than a screenshot.
struct SettingsLibraryStatus: Equatable {
    /// "55,231 photos · 1,204 videos · indexed".
    let counts: String
    /// How full the bar is, 0…1.
    let fraction: Double
    /// "Up to date · 2 min. ago" / "Reading photo info · 64%".
    let status: String
    /// Every asset has been read — the bar is drawn in green.
    let isComplete: Bool

    struct Input: Equatable {
        var access: PhotoAuthorizationState
        var photoCount: Int
        var videoCount: Int
        /// Assets whose read has finished (`MetadataStore.completedCount`).
        var readCount: Int
        /// Every asset the index knows (`MetadataStore.rowCount`).
        var totalCount: Int
        /// The live run's progress, when one is going.
        var isIndexing: Bool
        var runFraction: Double?
        var lastIndexedAt: Date?
    }

    init(counts: String, fraction: Double, status: String, isComplete: Bool) {
        self.counts = counts
        self.fraction = fraction
        self.status = status
        self.isComplete = isComplete
    }

    init(_ input: Input, now: Date = .now, locale: Locale = .current) {
        let isComplete = input.totalCount > 0 && input.readCount >= input.totalCount && !input.isIndexing
        let photos = String(AttributedString(
            localized: "^[\(input.photoCount) photo](inflect: true)",
            locale: locale,
            comment: "Settings, Your library card: number of photos"
        ).characters)
        let videos = String(AttributedString(
            localized: "^[\(input.videoCount) video](inflect: true)",
            locale: locale,
            comment: "Settings, Your library card: number of videos"
        ).characters)
        var counts = SettingsSummary.joined(photos, videos)
        if isComplete {
            counts = SettingsSummary.joined(counts, String(localized: "indexed", comment: "Settings, Your library card: every photo and video has been read"))
        }

        let stored = input.totalCount > 0 ? Double(input.readCount) / Double(input.totalCount) : 0
        let fraction = min(1, max(0, input.isIndexing ? (input.runFraction ?? stored) : stored))

        let status: String
        if !input.access.canReadLibrary {
            status = String(localized: "ShotDex has no access to your photos", comment: "Settings, Your library card status without photo access")
        } else if input.isIndexing {
            if let runFraction = input.runFraction {
                let percent = Int((min(1, max(0, runFraction)) * 100).rounded(.down))
                status = String(localized: "Reading photo info · \(percent)%", comment: "Settings, Your library card status while indexing, with percent done")
            } else {
                status = String(localized: "Reading photo info…", comment: "Settings, Your library card status while indexing, before a percentage is known")
            }
        } else if input.totalCount == 0 {
            status = String(localized: "Not indexed yet", comment: "Settings, Your library card status before the first index")
        } else if !isComplete {
            status = String(
                localized: "\(input.readCount.formatted()) of \(input.totalCount.formatted()) read",
                comment: "Settings, Your library card status: photos and videos read of the library, when a run stopped part-way"
            )
        } else if let lastIndexedAt = input.lastIndexedAt {
            status = String(
                localized: "Up to date · \(Self.relative(lastIndexedAt, now: now, locale: locale))",
                comment: "Settings, Your library card status: index complete, and how long ago it last ran"
            )
        } else {
            status = String(localized: "Up to date", comment: "Settings, Your library card status: index complete")
        }

        self.init(counts: counts, fraction: fraction, status: status, isComplete: isComplete)
    }

    /// "2 min. ago", or "just now" under a minute — "5 sec. ago" reads as a
    /// stopwatch.
    static func relative(_ date: Date, now: Date, locale: Locale) -> String {
        if now.timeIntervalSince(date) < 60 {
            return String(localized: "just now", comment: "Settings, Your library card: the index ran less than a minute ago")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = locale
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

/// The "Your library" card at the top of the compact root and of the Photo
/// Library page: counts, one bar, one status line, and Re-index.
///
/// Re-index greys out while a run is going rather than turning into Cancel
/// under the finger — the second tap of a double tap would otherwise stop the
/// run it just started (FS-08.02 §1). The page variant carries Cancel and the
/// run's details underneath instead.
struct SettingsLibraryCard<Details: View>: View {
    let status: SettingsLibraryStatus
    let canReindex: Bool
    let reindex: () -> Void
    @ViewBuilder var details: () -> Details

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your library", comment: "Settings: title of the library status card")
                    .font(.headline)
                Spacer(minLength: AppTheme.Spacing.sm)
                Button(action: reindex) {
                    Text("Re-index", comment: "Settings, Your library card: button that reads the whole library again")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .disabled(!canReindex)
                .accessibilityLabel(SettingsRowLabel.reindexLibrary.title)
            }
            Text(status.counts)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            ProgressView(value: status.fraction)
                .tint(status.isComplete ? .green : nil)
                .padding(.top, AppTheme.Spacing.md)
                .accessibilityLabel(Text("Index progress", comment: "Settings, Your library card: VoiceOver name of the progress bar"))
            Text(status.status)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.top, AppTheme.Spacing.sm)
            details()
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle.app(AppTheme.Radius.lg))
    }
}

extension SettingsLibraryCard where Details == EmptyView {
    init(status: SettingsLibraryStatus, canReindex: Bool, reindex: @escaping () -> Void) {
        self.init(status: status, canReindex: canReindex, reindex: reindex) { EmptyView() }
    }
}
