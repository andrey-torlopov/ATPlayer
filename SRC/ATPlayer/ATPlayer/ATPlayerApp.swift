import SwiftData
import SwiftUI

@main
struct ATPlayerApp: App {
    private let container: ModelContainer
    @StateObject private var viewModel: ATPlayerViewModel

    init() {
        do {
            container = try ModelContainer(for: TrackItem.self, PlaylistSection.self)
            // Construct the player at app startup, including launches for audio
            // intents. All scenes and system controls use this one instance.
            let player = ATPlayerViewModel(context: container.mainContext)
            _viewModel = StateObject(wrappedValue: player)
        } catch {
            fatalError("Не удалось создать ModelContainer: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .modelContainer(container)
    }
}
