import SwiftUI

/// The File Name screen (FS-03.07b §5), pushed from the Name row: the three
/// built-in templates with a checkmark, then Custom — a 44pt field, two rows
/// of token chips, and the first photo's name, which changes as you type.
struct FileNameScreen: View {
    @Bindable var model: FileExportModel
    @FocusState private var isCustomFocused: Bool

    private let tokens: [FileNameTemplate.Token] = [.original, .date, .time, .camera, .lens, .seq]

    var body: some View {
        Form {
            Section {
                ForEach(FileNameTemplate.builtIns, id: \.self) { template in
                    Button {
                        model.chooseTemplate(template)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ExportCopy.templateTitle(template)).foregroundStyle(.primary)
                                Text(verbatim: template.pattern)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.template == template {
                                Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.template == template ? .isSelected : [])
                }
            }

            Section {
                HStack {
                    TextField(ExportCopy.custom, text: $model.customTemplate)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($isCustomFocused)
                    if model.usesCustomTemplate {
                        Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityAddTraits(model.usesCustomTemplate ? .isSelected : [])

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.sm), count: 3),
                          spacing: AppTheme.Spacing.sm) {
                    ForEach(tokens, id: \.self) { token in
                        Button {
                            model.insert(token)
                        } label: {
                            Label(ExportCopy.tokenTitle(token), systemImage: "plus")
                                .labelStyle(TokenChipLabelStyle())
                                .frame(maxWidth: .infinity, minHeight: FileNameMetrics.chipHeight)
                                .background(.tint.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                        .accessibilityLabel(ExportCopy.insertToken(token))
                    }
                }
                .padding(.vertical, AppTheme.Spacing.xs)

                if let example = model.exampleName {
                    HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.md) {
                        Text(ExportCopy.exampleLabel).foregroundStyle(.secondary)
                        Text(verbatim: example)
                            .font(.subheadline.monospaced())
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text(ExportCopy.custom)
            } footer: {
                Text(ExportCopy.missingTokenFooter(model.missingTokenExample))
            }
        }
        .navigationTitle(ExportCopy.fileNameTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

/// `+ Date` on one line, or two when the column is narrow.
private struct TokenChipLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            configuration.icon.font(.caption.weight(.semibold))
            configuration.title.font(.subheadline).lineLimit(2).multilineTextAlignment(.center)
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
    }
}

/// From `PH34_FileName`: chips 32pt tall, three to a row.
enum FileNameMetrics {
    static let chipHeight: CGFloat = AppTheme.Size.pillHeightLight
}
