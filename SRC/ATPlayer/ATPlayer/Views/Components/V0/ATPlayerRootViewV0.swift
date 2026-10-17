import SwiftUI
import UIKit

struct ATPlayerRootViewV0: View {
    @StateObject private var viewModel: ATPlayerViewModel
    @ObservedObject private var playbackService: AudioPlaybackService
    @Environment(\.colorScheme) private var colorScheme

    init(viewModel: @autoclosure @escaping () -> ATPlayerViewModel) {
        let vm = viewModel()
        _viewModel = StateObject(wrappedValue: vm)
        _playbackService = ObservedObject(wrappedValue: vm.playbackService)
    }

    private var themeV0: AppThemeV0 {
        colorScheme == .dark ? AppThemeV0.dark : AppThemeV0.light
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                PlayerPanelViewV0(
                    viewModel: viewModel,
                    onSettings: { viewModel.showSettings = true }
                )

                NowPlayingVisualizerViewV0(
                    artworkData: viewModel.nowPlayingArtwork,
                    visualizerValues: playbackService.visualizer
                )

                PlaylistPanelViewV0(viewModel: viewModel)
                    .frame(maxHeight: .infinity)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(themeV0.background.ignoresSafeArea())
            .navigationDestination(isPresented: $viewModel.showSettings) {
                SettingsViewV0(viewModel: viewModel)
                    .environment(\.themeV0, themeV0)
            }
        }
        .environment(\.themeV0, themeV0)
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
