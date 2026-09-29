import SwiftUI

/// Before an approximate export leaves (FS-03.14c §1): what does not carry,
/// in one line, and for `.xmp` the two lines about Adobe. Export opens the
/// share sheet with the file.
struct LookExportSheet: View {
    struct Plan: Identifiable {
        let id = UUID()
        var title: String
        var fileURL: URL
        var lostLine: String?
        var mentionsAdobe: Bool
    }

    let plan: Plan
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                if let lost = plan.lostLine {
                    Label(lost, systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                }
                if plan.mentionsAdobe {
                    Text(LookXMPWriter.explanation)
                        .font(.subheadline)
                    Text(LookXMPWriter.notAffiliated)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(plan.fileURL.lastPathComponent)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(AppTheme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .navigationTitle(plan.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") {
                        let url = plan.fileURL
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            PhotoShareSheet.present(items: [url])
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
