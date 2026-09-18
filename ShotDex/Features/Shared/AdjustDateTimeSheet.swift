import Photos
import SwiftUI

/// Capture-date editor, reached from a photo's ⋯ menu or a multi-select.
///
/// One photo sets its date outright. A selection keeps the spacing between its
/// photos and moves as a block: the picker edits the *earliest* capture date and
/// everything else shifts by the same amount, which is the behaviour Photos has
/// when several photos are adjusted together.
struct AdjustDateTimeSheet: View {
    let request: AssetActionsCoordinator.DateRequest
    let onApply: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    init(
        request: AssetActionsCoordinator.DateRequest,
        onApply: @escaping (Date) -> Void
    ) {
        self.request = request
        self.onApply = onApply
        _date = State(initialValue: request.seed)
    }

    private var isBatch: Bool { request.assets.count > 1 }

    /// How far the picker has moved from the original date, spelled out so the
    /// user can see what a batch shift will do before committing.
    private var shiftDescription: String? {
        let delta = date.timeIntervalSince(request.seed)
        guard abs(delta) >= 60 else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.year, .month, .day, .hour, .minute]
        formatter.maximumUnitCount = 2
        guard let amount = formatter.string(from: abs(delta)) else { return nil }
        return delta > 0 ? "Later by \(amount)" : "Earlier by \(amount)"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker(
                        "Date & Time",
                        selection: $date,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)
                } footer: {
                    if isBatch {
                        Text("Adjusting \(request.assets.count) photos. The earliest photo moves to this date and the rest shift by the same amount, keeping their order.")
                    } else {
                        Text("The capture date in the original file is left unchanged, the same as in Photos.")
                    }
                }

                if let shiftDescription {
                    Section {
                        LabeledContent("Shift", value: shiftDescription)
                            .monospacedDigit()
                    }
                }
            }
            .navigationTitle(isBatch ? "Adjust \(request.assets.count) Photos" : "Adjust Date & Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Adjust") {
                        onApply(date)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(date == request.seed)
                }
            }
        }
    }
}
