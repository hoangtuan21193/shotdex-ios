import SwiftUI

/// Native filter sheet (medium/large detents). Edits a draft criteria and
/// applies on dismiss so cancel is cheap.
struct FilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var criteria: FilterCriteria
    let availableBrands: [String]
    let availableBodies: [String]
    let availableLenses: [String]

    @State private var draft: FilterCriteria = .empty

    var body: some View {
        NavigationStack {
            List {
                FilterCriteriaSections(
                    draft: $draft,
                    availableBrands: availableBrands,
                    availableBodies: availableBodies,
                    availableLenses: availableLenses
                )
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear All") { draft = .empty }
                        .disabled(draft.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") {
                        criteria = draft
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear { draft = criteria }
    }
}
