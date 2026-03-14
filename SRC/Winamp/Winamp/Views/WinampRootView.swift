import SwiftUI

struct WinampRootView: View {
    @StateObject private var viewModel: WinampViewModel
    @Environment(\.colorScheme) private var colorScheme

    init(viewModel: @autoclosure @escaping () -> WinampViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    private var theme: AppTheme {
        colorScheme == .dark ? AppTheme.dark : AppTheme.light
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                PlayerPanelView(viewModel: viewModel)

                EqualizerCompactView(playbackService: viewModel.playbackService) {
                    viewModel.showEqualizerWindow = true
                }

                PlaylistPanelView(viewModel: viewModel)
                    .frame(maxHeight: .infinity)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.background.ignoresSafeArea())
            .navigationDestination(isPresented: $viewModel.showEqualizerWindow) {
                EqualizerWindowView(playbackService: viewModel.playbackService)
                    .environment(\.theme, theme)
            }
        }
        .environment(\.theme, theme)
        .fileImporter(
            isPresented: $viewModel.showImporter,
            allowedContentTypes: viewModel.supportedTypes,
            allowsMultipleSelection: true,
            onCompletion: viewModel.importFiles
        )
        .onAppear {
            viewModel.reloadSections()
        }
    }
}
