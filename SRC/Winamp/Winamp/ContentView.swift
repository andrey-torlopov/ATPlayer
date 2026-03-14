import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel: WinampViewModel?

    private var theme: AppTheme {
        colorScheme == .dark ? AppTheme.dark : AppTheme.light
    }

    var body: some View {
        Group {
            if let viewModel {
                WinampRootView(viewModel: viewModel)
            } else {
                ProgressView()
                    .tint(theme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.background.ignoresSafeArea())
            }
        }
        .task {
            guard viewModel == nil else { return }
            viewModel = WinampViewModel(context: modelContext)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [TrackItem.self, PlaylistSection.self], inMemory: true)
}
