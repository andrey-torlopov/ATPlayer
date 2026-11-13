import PlayerApplication
import SwiftUI

@main
struct ATPlayerApp: App {
    @StateObject private var application: PlayerApplication

    init() {
        do {
            let application = try PlayerApplication()
            _application = StateObject(wrappedValue: application)
        } catch {
            fatalError("Не удалось создать ModelContainer: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup { ContentView(application: application) }
    }
}
