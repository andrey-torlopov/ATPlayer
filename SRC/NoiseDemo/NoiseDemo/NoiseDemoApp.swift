import SwiftUI

@main
struct NoiseDemoApp: App {
  @StateObject private var model = NoiseDemoModel()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      NoiseDemoView(model: model)
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in
          if phase == .background { model.stop() }
        }
    }
  }
}
