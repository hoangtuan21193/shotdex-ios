import SwiftUI

/// After an import (FS-03.14a §3): "Reading 120 of 500" with Cancel while
/// files are read, then "12 looks added · 2 skipped" and a row per preset
/// that opens its lines. The report is not kept after it closes.
struct LookImportReportSheet: View {
    @Bindable var model: LookExchangeModel

    var body: some View {
        NavigationStack {
            Group {
                if let report = model.report {
                    reportList(report)
                } else {
                    reading
                }
            }
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.report == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { model.cancelImport() }
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { model.dismissReport() }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(model.report == nil)
    }

    private var reading: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            ProgressView(value: Double(model.progress?.read ?? 0), total: Double(max(1, model.progress?.total ?? 1)))
            Text("Reading \(model.progress?.read ?? 0) of \(model.progress?.total ?? 0)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(AppTheme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reportList(_ report: PresetImportReport) -> some View {
        List {
            Section {
                ForEach(report.entries) { entry in
                    if entry.lines.isEmpty {
                        row(entry)
                    } else {
                        DisclosureGroup {
                            ForEach(Array(entry.lines.enumerated()), id: \.offset) { _, line in
                                HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
                                    Text(line.symbol).accessibilityHidden(true)
                                    Text(line.text)
                                }
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .accessibilityElement(children: .combine)
                            }
                        } label: {
                            row(entry)
                        }
                    }
                }
            } header: {
                Text(report.header)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }
        }
    }

    private func row(_ entry: PresetImportReport.Entry) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text(entry.status.symbol)
                .foregroundStyle(entry.status == .skipped ? .secondary : .primary)
                .accessibilityHidden(true)
            Text(entry.name)
                .lineLimit(1)
            Spacer(minLength: AppTheme.Spacing.sm)
            Text(entry.status.title)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.name), \(entry.status.title)")
    }
}
