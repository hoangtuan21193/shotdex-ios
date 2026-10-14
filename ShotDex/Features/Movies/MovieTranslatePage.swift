import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// Translate (FS-23.04 §1, board `PH_MovieTranslate`): a page of the Audio &
/// Subtitles panel — From, To, Using, where the words go, and one accent
/// button. The run goes on when the panel closes (Apple Translation aside:
/// its session lives with this page).
struct MovieTranslatePage: View {
    let model: MoviePlayerModel
    let onBack: () -> Void
    @Environment(\.appAccent) private var accent
    @State private var fromId: String?
    @State private var toLanguage = ""
    @State private var using: AIChoice?
    @State private var choosing: Field?
    @State private var lineCount = 0
    /// Set to start Apple Translation inside `translationTask`.
    @State private var heldRequest: HeldRequest?

    enum Field { case from, to, using }

    struct HeldRequest: Equatable {
        var fromId: String
        var fromLanguage: String?
        var toLanguage: String
    }

    var body: some View {
        Group {
            if let choosing {
                choices(choosing)
            } else if options.isEmpty {
                setUp
            } else {
                form
            }
        }
        .onAppear(perform: prepare)
        .task(id: fromId) {
            lineCount = await fromId.asyncMap { await model.document(for: $0)?.cues.count } ?? 0
        }
        .modifier(HeldTranslation(model: model, request: $heldRequest))
    }

    private var service: TranslationService? { model.translationService }
    private var options: [AIChoice] { service?.usingOptions() ?? [] }

    // MARK: Form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                pickerRow(String(localized: "From", comment: "Translate: the subtitle to translate"), value: fromTitle) { choosing = .from }
                pickerRow(String(localized: "To", comment: "Translate: the language to translate into"), value: MovieLanguage.endonym(toLanguage) ?? toLanguage) { choosing = .to }
                pickerRow(String(localized: "Using", comment: "Translate: who translates"), value: using.map { service?.title(of: $0) ?? "" } ?? "") { choosing = .using }
                if let using, let service {
                    Text(service.note(for: using, lines: lineCount))
                        .font(.footnote)
                        .foregroundStyle(EditorTheme.secondaryText)
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .padding(.top, AppTheme.Spacing.sm)
                }
                status
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.top, AppTheme.Spacing.xl)
            }
            .padding(.bottom, AppTheme.Spacing.md)
        }
    }

    private var header: some View {
        Button(action: onBack) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "chevron.left")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(EditorTheme.control, in: Circle())
                Text(String(localized: "Translate", comment: "Translate page title"))
                    .font(.headline)
            }
            .padding(.horizontal, AppTheme.Spacing.sm)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Audio and Subtitles", comment: "Translate: back to the panel"))
    }

    @ViewBuilder
    private var status: some View {
        let run = model.translationRun
        switch run?.state {
        case .running?:
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text(String(localized: "Translating \(run?.done ?? 0) of \((run?.total ?? 0).formatted()) lines", comment: "Translate progress, e.g. Translating 412 of 1,380 lines"))
                    .font(.subheadline.monospacedDigit())
                ProgressView(value: Double(run?.done ?? 0), total: Double(max(1, run?.total ?? 1)))
                    .tint(.white)
                Button(String(localized: "Cancel", comment: "Translate: stop, keeping what is done")) { model.cancelTranslation() }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
        case .failed(let problem)?:
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text(problem.title).font(.subheadline.weight(.semibold))
                Text(problem.message).font(.footnote).foregroundStyle(EditorTheme.secondaryText).lineLimit(2)
                HStack(spacing: AppTheme.Spacing.md) {
                    if problem.opensSettings {
                        Button(String(localized: "Open AI Settings", comment: "Translate: go to Settings › AI")) { model.showsAISettings = true }
                    }
                    Button(String(localized: "Retry", comment: "Translate: try again from where it stopped"), action: translate)
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
            }
        default:
            Button(action: translate) {
                Text(translateTitle)
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(accent, in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(fromId == nil || using == nil || toLanguage.isEmpty)
        }
    }

    /// `Translate`, or `Continue (412 of 1,380)` for a stopped run (AC-31).
    private var translateTitle: String {
        if let fromId, let pending = model.translations?.pending(movieId: model.movie.id, fromId: fromId, toLanguage: toLanguage) {
            return String(localized: "Continue (\(pending.done.formatted()) of \(pending.total.formatted()))", comment: "Translate: carry on a stopped translation")
        }
        return String(localized: "Translate", comment: "Translate: start")
    }

    // MARK: Set Up AI (FS-23.04 §1)

    private var setUp: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            header
            Text(String(localized: "Set Up AI", comment: "Translate with no provider: title"))
                .font(.headline)
                .padding(.horizontal, AppTheme.Spacing.lg)
            Text(String(localized: "Choose how ShotDex translates: on this device, a model on your home computer, or a service you have an API key for.", comment: "Translate with no provider: explanation"))
                .font(.subheadline)
                .foregroundStyle(EditorTheme.secondaryText)
                .padding(.horizontal, AppTheme.Spacing.lg)
            Button {
                model.showsAISettings = true
            } label: {
                Text(String(localized: "Open AI Settings", comment: "Translate: go to Settings › AI"))
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(accent, in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppTheme.Spacing.lg)
            Spacer(minLength: 0)
        }
    }

    // MARK: Choosing

    private func choices(_ field: Field) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button { choosing = nil } label: {
                    Label(fieldName(field), systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                switch field {
                case .from:
                    ForEach(model.translatableSubtitles) { subtitle in
                        choiceRow(model.subtitleTitle(subtitle), isSelected: subtitle.id == fromId) { fromId = subtitle.id }
                    }
                case .to:
                    ForEach(targetLanguages, id: \.self) { code in
                        choiceRow(MovieLanguage.endonym(code) ?? code, isSelected: code == toLanguage) { toLanguage = code }
                    }
                case .using:
                    ForEach(options, id: \.self) { choice in
                        choiceRow(service?.title(of: choice) ?? "", isSelected: choice == using) { using = choice }
                    }
                }
            }
            .padding(.bottom, AppTheme.Spacing.md)
        }
    }

    private func fieldName(_ field: Field) -> String {
        switch field {
        case .from: String(localized: "From", comment: "Translate: the subtitle to translate")
        case .to: String(localized: "To", comment: "Translate: the language to translate into")
        case .using: String(localized: "Using", comment: "Translate: who translates")
        }
    }

    private func choiceRow(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            choosing = nil
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.semibold))
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 15)
                Text(title).font(.subheadline.weight(isSelected ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func pickerRow(_ title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Text(title).font(.subheadline)
                Spacer(minLength: AppTheme.Spacing.sm)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(EditorTheme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(EditorTheme.secondaryText)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.translationRun?.state == .running)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    // MARK: Work

    private var fromTitle: String {
        model.subtitle(id: fromId).map(model.subtitleTitle) ?? ""
    }

    /// Subtitle Languages first, then the rest; never the From language.
    private var targetLanguages: [String] {
        let from = MovieLanguage.code(model.subtitle(id: fromId)?.language)
        let preferred = MovieLanguagesScreen.current(.subtitles)
        var seen = Set<String>()
        return (preferred + MovieLanguagePreferences.offered).filter { $0 != from && seen.insert($0).inserted }
    }

    private func prepare() {
        guard fromId == nil else { return }
        let text = model.translatableSubtitles
        fromId = text.first { $0.id == model.subtitleChoice.primaryId }?.id ?? text.first?.id
        toLanguage = targetLanguages.first ?? "en"
        using = service?.defaultUsing()
    }

    private func translate() {
        guard let fromId, let using else { return }
        if using == .appleTranslation {
            heldRequest = HeldRequest(fromId: fromId, fromLanguage: model.subtitle(id: fromId)?.language, toLanguage: toLanguage)
            return
        }
        Task { await model.startTranslation(fromId: fromId, toLanguage: toLanguage, using: using) }
    }
}

/// Hosts Apple Translation's session for the run it starts (iOS 18+).
private struct HeldTranslation: ViewModifier {
    let model: MoviePlayerModel
    @Binding var request: MovieTranslatePage.HeldRequest?

    func body(content: Content) -> some View {
        #if canImport(Translation)
        if #available(iOS 18.0, *) {
            content.translationTask(configuration) { session in
                guard let request else { return }
                await model.runHeldTranslation(fromId: request.fromId, toLanguage: request.toLanguage, engine: AppleTranslationEngine(session: session))
                self.request = nil
            }
        } else {
            content
        }
        #else
        content
        #endif
    }

    #if canImport(Translation)
    @available(iOS 18.0, *)
    private var configuration: TranslationSession.Configuration? {
        guard let request else { return nil }
        return TranslationSession.Configuration(
            source: request.fromLanguage.map { Locale.Language(identifier: $0) },
            target: Locale.Language(identifier: request.toLanguage)
        )
    }
    #endif
}

private extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async -> T?) async -> T? {
        guard let value = self else { return nil }
        return await transform(value)
    }
}
