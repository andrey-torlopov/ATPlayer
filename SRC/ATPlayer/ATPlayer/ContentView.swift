import PlayerApplication
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var application: PlayerApplication

    var body: some View {
        application.rootView()
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { application.becameActive() }
            }
            .onOpenURL(perform: application.openURL)
    }
}
