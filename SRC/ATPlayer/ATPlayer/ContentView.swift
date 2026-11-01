import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var viewModel: ATPlayerViewModel

    var body: some View {
        ATPlayerRootView(viewModel: viewModel)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    viewModel.refreshPlaybackPresentation()
                }
            }
            .onOpenURL { url in
                viewModel.handleDeepLink(url)
            }
    }
}

#Preview {
    if let container = try? ModelContainer(
        for: TrackItem.self, PlaylistSection.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    ) {
        ContentView(viewModel: ATPlayerViewModel(context: container.mainContext))
            .modelContainer(container)
    } else {
        Text("Не удалось создать данные предпросмотра")
    }
}
