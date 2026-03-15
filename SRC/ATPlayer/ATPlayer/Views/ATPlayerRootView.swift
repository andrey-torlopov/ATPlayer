import SwiftUI
import UIKit

struct ATPlayerRootView: View {
    @StateObject private var viewModel: ATPlayerViewModel
    @ObservedObject private var playbackService: AudioPlaybackService
    @Environment(\.colorScheme) private var colorScheme

    init(viewModel: @autoclosure @escaping () -> ATPlayerViewModel) {
        let vm = viewModel()
        _viewModel = StateObject(wrappedValue: vm)
        _playbackService = ObservedObject(wrappedValue: vm.playbackService)
    }

    private var theme: AppTheme {
        colorScheme == .dark ? AppTheme.dark : AppTheme.light
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                PlayerPanelView(
                    viewModel: viewModel,
                    onSettings: { viewModel.showSettings = true }
                )

                NowPlayingVisualizerView(
                    artworkData: viewModel.nowPlayingArtwork,
                    visualizerValues: playbackService.visualizer
                )

                PlaylistPanelView(viewModel: viewModel)
                    .frame(maxHeight: .infinity)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.background.ignoresSafeArea())
            .navigationDestination(isPresented: $viewModel.showSettings) {
                SettingsView(viewModel: viewModel)
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
