import SwiftUI
import UIKit

@main
@MainActor
struct SearchBenchApp: App {
    @State private var model = BenchmarkModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            SearchBenchView(model: model)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    model.recordSceneState(phase == .active ? "active" : phase == .background ? "background" : "inactive")
                    if phase == .active { model.handleLaunchArguments() }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    model.recordSceneState(scenePhase == .active ? "active" : scenePhase == .background ? "background" : "inactive")
                    if scenePhase == .active { model.handleLaunchArguments() }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    model.recordSceneState(scenePhase == .active ? "active" : scenePhase == .background ? "background" : "inactive")
                }
        }
    }
}
