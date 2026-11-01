import LibraryDomain
import PlaybackDomain
import SwiftUI

struct ATPlayerRootViewV1: View {
    @ObservedObject var viewModel: ATPlayerViewModel
    let folderLibrary: AnyView
    let onLibraryModeChange: (LibraryMode) -> Void
    @State private var libraryMode: LibraryMode = .playlists
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var buttonFeedbackTrigger = false

    private var theme: PlayerThemeV1 {
        colorScheme == .dark ? .dark : .light
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let isCompactLandscape = geometry.size.height < 500 && geometry.size.width > geometry.size.height
                ScrollView {
                    VStack(spacing: isCompactLandscape ? 16 : 28) {
                        header

                        if viewModel.isImporting {
                            HStack(spacing: 12) {
                                ProgressView().tint(theme.accent)
                                Text("Добавление аудио…")
                                    .font(.subheadline)
                                    .foregroundStyle(theme.textSecondary)
                                Spacer()
                                Button("Отменить") {
                                    buttonFeedbackTrigger.toggle()
                                    viewModel.cancelImport()
                                }
                                .font(.subheadline)
                                .frame(minHeight: 44)
                            }
                        }

                        if geometry.size.width >= (isCompactLandscape ? 620 : 760) && !dynamicTypeSize.isAccessibilitySize {
                            HStack(alignment: .top, spacing: isCompactLandscape ? 24 : 40) {
                                PlayerPanelV1(viewModel: viewModel, isCompact: isCompactLandscape)
                                    .frame(maxWidth: 400)
                                playlistContent
                                    .frame(maxWidth: 520)
                            }
                        } else {
                            PlayerPanelV1(viewModel: viewModel)
                            playlistContent
                        }
                    }
                    .padding(.horizontal, geometry.size.width < 380 ? 20 : 28)
                    .padding(.top, isCompactLandscape ? 0 : 16)
                    .padding(.bottom, isCompactLandscape ? 16 : 36)
                    .frame(maxWidth: 1040)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .background(theme.background.ignoresSafeArea())
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $viewModel.showSettings) {
                SettingsViewV1(viewModel: viewModel)
                    .environment(\.playerThemeV1, theme)
                    .toolbar(.visible, for: .navigationBar)
            }
        }
        .tint(theme.accent)
        .playerButtonFeedbackV1(trigger: buttonFeedbackTrigger)
        .environment(\.playerThemeV1, theme)
        .fileImporter(
            isPresented: $viewModel.showImporter,
            allowedContentTypes: viewModel.supportedTypes,
            allowsMultipleSelection: true,
            onCompletion: viewModel.importFiles
        )
    }

    private var playlistContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let error = viewModel.importError {
                errorMessage(error)
            }
            Picker("Источник музыки", selection: $libraryMode) {
                Text("Плейлисты").tag(LibraryMode.playlists)
                Text("Папки").tag(LibraryMode.folders)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("library-mode")
            .onChange(of: libraryMode) { _, mode in onLibraryModeChange(mode) }

            if let title = viewModel.preparingTrackTitle {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Подготовка: \(title)").font(.subheadline).lineLimit(2)
                    Spacer()
                    Button("Отмена") { Task { await viewModel.performPlaybackCommand(.pause) } }
                }
                .accessibilityIdentifier("playback-preparation")
            }
            if libraryMode == .playlists {
                PlaylistPanelV1(viewModel: viewModel)
            } else {
                folderLibrary
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(theme.accent)
                Text("ATPlayer")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .tracking(-0.5)
                    .foregroundStyle(theme.textPrimary)
            }
            .frame(height: 48)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 12)

            VStack(spacing: 10) {
                CircularButtonV1(symbol: "slider.horizontal.3", label: "Настройки") {
                    viewModel.showSettings = true
                }

                CircularButtonV1(
                    symbol: viewModel.playbackMode.symbol,
                    label: "Режим воспроизведения",
                    isProminent: viewModel.playbackMode != .off,
                    action: viewModel.cyclePlaybackMode
                )
                .accessibilityValue(viewModel.playbackModeTitle)
                .accessibilityHint("Следующий режим: \(viewModel.nextPlaybackModeTitle)")
                .accessibilityIdentifier("playback-mode")
            }
        }
    }

    private func errorMessage(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(theme.destructive)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                buttonFeedbackTrigger.toggle()
                viewModel.importError = nil
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Скрыть сообщение")
        }
        .padding(16)
        .softPanelV1(cornerRadius: 18)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player-error-banner")
    }
}
