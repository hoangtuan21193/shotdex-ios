import SwiftUI

@main
struct ShotDexApp: App {
    @State private var dependencies: AppDependencies
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let dependencies = AppDependencies.live()
        _dependencies = State(initialValue: dependencies)
        // BGTaskScheduler requires registration before launch finishes.
        dependencies.backgroundIndex.register()
        dependencies.resolveNewlyKnownCameras()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(dependencies)
                .environment(dependencies.photoLibrary)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        dependencies.backgroundIndex.scheduleContinuationIfNeeded()
                    }
                }
        }
    }
}
