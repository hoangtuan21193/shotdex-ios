import SwiftUI

/// Short pre-permission onboarding: explain value, then trigger the
/// photo library prompt.
struct OnboardingScreen: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(\.appAccent) private var accent

    var body: some View {
        VStack(spacing: 0) {
            // Scrolls rather than squeezes: at accessibility sizes the four
            // promises did not fit the screen and SwiftUI answered by
            // truncating each one to a single line ending in "…", which is a
            // pre-permission screen that cannot say what it is asking for.
            // `.basedOnSize` keeps it a static screen at normal sizes.
            ScrollView {
                pitch
            }
            .scrollBounceBehavior(.basedOnSize)

            Button {
                Task { await photoLibrary.requestAuthorization() }
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
        }
        .background(Color(.systemBackground))
    }

    private var pitch: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            Image(systemName: "camera.metering.matrix")
                .font(.system(size: 56))
                .foregroundStyle(accent)
                .padding(.bottom, 16)

            Text("ShotDex")
                .font(.largeTitle.bold())
                .padding(.bottom, 32)

            VStack(alignment: .leading, spacing: 22) {
                onboardingRow(
                    icon: "magnifyingglass",
                    title: "Find photos by camera and lens",
                    detail: "Search and filter your library by gear and exposure settings."
                )
                onboardingRow(
                    icon: "chart.bar.xaxis",
                    title: "Explore your most-used gear",
                    detail: "See which bodies, lenses and focal lengths you really use."
                )
                onboardingRow(
                    icon: "arrow.left.arrow.right",
                    title: "Compare focal lengths across sensor sizes",
                    detail: "Full-frame equivalent views across all your cameras."
                )
                onboardingRow(
                    icon: "lock.shield",
                    title: "Your photos stay on your device",
                    detail: "Your photos and metadata never leave your device."
                )
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity)
    }

    private func onboardingRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    OnboardingScreen()
        .environment(AppDependencies.preview().photoLibrary)
}
