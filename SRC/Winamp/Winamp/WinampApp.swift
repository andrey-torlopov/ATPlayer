import SwiftData
import SwiftUI

@main
struct WinampApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: TrackItem.self, PlaylistSection.self)
        } catch {
            fatalError("Не удалось создать ModelContainer: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
