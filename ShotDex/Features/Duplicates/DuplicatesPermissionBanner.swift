import SwiftUI
import UIKit

/// The top banner when Duplicates cannot see the whole library (FS-06.06
/// §7.3, A5): how many photos it can see under limited access, or that it
/// sees none — with a way to Settings either way. Silence here is how a
/// user ends up trusting a scan of 1,240 photos as a scan of 38,000.
struct DuplicatesPermissionBanner: View {
    enum Access: Equatable {
        case limited(visible: Int)
        case denied
    }

    let access: Access

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
            Image(systemName: access == .denied ? "eye.slash" : "photo.on.rectangle")
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: AppTheme.Spacing.sm)
            Button(String(localized: "Settings", comment: "Duplicates permission banner: open the app's Settings page")) {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .font(.subheadline.weight(.medium))
            .frame(minHeight: 44)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle.app(AppTheme.Radius.md))
        // `.contain`: the Settings button must stay its own element — it is
        // the only way out of the denied state.
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        switch access {
        case .limited(let visible):
            String(localized: "ShotDex can see \(visible.formatted()) of your photos",
                   comment: "Duplicates banner under limited Photos access")
        case .denied:
            String(localized: "ShotDex can't see your photos", comment: "Duplicates banner when Photos access is denied")
        }
    }

    private var detail: String {
        switch access {
        case .limited:
            String(localized: "Duplicates among the others are not found.",
                   comment: "Duplicates banner under limited access: what the limit means")
        case .denied:
            String(localized: "Allow access to check for duplicates.",
                   comment: "Duplicates banner when access is denied: what to do")
        }
    }
}
