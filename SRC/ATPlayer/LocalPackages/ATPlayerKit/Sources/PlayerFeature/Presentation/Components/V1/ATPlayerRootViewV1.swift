import AppLocalization
import LibraryDomain
import PlaybackDomain
import SwiftUI

struct ATPlayerRootViewV1: View {
    @ObservedObject var viewModel: ATPlayerViewModel
    let folderLibrary: AnyView
    let onLibraryModeChange: (LibraryMode) -> Void
    var isFolderPresentationActive = false
    @State private var libraryMode: LibraryMode = .playlists
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var presentation = PlayerPresentationState()
    @State private var screenMode: PlayerScreenMode = .standard
    @State private var standardSize: CGSize = .zero
    @State private var isRootVisible = false
    @State private var ambientError: String?
    @State private var ambientErrors = AmbientErrorQueue()
    @State private var showsAmbientError = false
    @State private var buttonFeedbackTrigger = false

    private var theme: PlayerThemeV1 {
        colorScheme == .dark ? .dark : .light
    }

    private var hasBlockingPresentation: Bool {
        viewModel.showSettings || viewModel.showImporter
            || isFolderPresentationActive || presentation.hasPresentation
    }

    var body: some View {
        let _ = locale
        // This container keeps its size when a sheet's text field shows the keyboard.
        GeometryReader { geometry in
            let mode = screenMode.updated(for: geometry.size)
            let isLandscape = mode == .ambient
            let ambientVisible = isLandscape && isRootVisible && !hasBlockingPresentation && !showsAmbientError
            let normalVisible = !isLandscape || hasBlockingPresentation
            let canPresentAmbientError = isLandscape && isRootVisible && !hasBlockingPresentation
                && scenePhase == .active && !showsAmbientError
            let retainedSize = retainedStandardSize(current: geometry.size, isLandscape: isLandscape)

            NavigationStack {
                ZStack {
                    // An overlay preserves library/editor identities without letting the retained
                    // portrait height enlarge the landscape canvas or move its center offscreen.
                    Color.clear
                        .overlay(alignment: .top) {
                            standardContent(
                                size: retainedSize,
                                isActive: normalVisible && isRootVisible,
                                isInteractive: !isLandscape && isRootVisible && !hasBlockingPresentation
                            )
                            .frame(width: retainedSize.width, height: retainedSize.height)
                            .opacity(normalVisible ? 1 : 0)
                            .allowsHitTesting(normalVisible)
                            .accessibilityHidden(!normalVisible)
                        }
                        .clipped()

                    if isLandscape {
                        LandscapeAmbientViewV1(viewModel: viewModel, isVisible: ambientVisible)
                            .opacity(normalVisible ? 0 : 1)
                            .allowsHitTesting(ambientVisible)
                            .accessibilityHidden(!ambientVisible)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.background.ignoresSafeArea())
                .onAppear { isRootVisible = true }
                .onDisappear { isRootVisible = false }
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
            .environment(\.playerPresentationActivity) { owner, isPresented in
                presentation.setPresented(isPresented, for: owner)
            }
            .statusBarHidden(isLandscape && !hasBlockingPresentation)
            .fileImporter(
                isPresented: $viewModel.showImporter,
                allowedContentTypes: viewModel.supportedTypes,
                allowsMultipleSelection: true,
                onCompletion: viewModel.importFiles
            )
            .alert(L10n.text("Не удалось воспроизвести"), isPresented: $showsAmbientError) {
                Button(L10n.text("Понятно"), role: .cancel) {
                    if viewModel.importError == ambientError { viewModel.importError = nil }
                    ambientError = nil
                }
            } message: {
                Text(ambientError ?? "")
            }
            .onChange(of: viewModel.importError) { _, error in
                ambientErrors.record(error, isLandscape: isLandscape)
                presentPendingAmbientError(canPresent: canPresentAmbientError)
            }
            .onChange(of: canPresentAmbientError) { _, canPresent in
                presentPendingAmbientError(canPresent: canPresent)
            }
            .onChange(of: isLandscape) { _, landscape in
                if !landscape { ambientErrors.leaveLandscape() }
            }
            .onChange(of: geometry.size, initial: true) { _, size in
                screenMode = screenMode.updated(for: size)
                if screenMode == .standard, size.width > 0, size.height > 0 {
                    standardSize = size
                }
            }
        }
        .ignoresSafeArea(.keyboard)
    }

    private func presentPendingAmbientError(canPresent: Bool) {
        guard let message = ambientErrors.takePending(canPresent: canPresent) else { return }
        ambientError = message
        showsAmbientError = true
    }

    private func retainedStandardSize(current: CGSize, isLandscape: Bool) -> CGSize {
        guard isLandscape else { return current }
        if standardSize.width > 0, standardSize.height > 0 { return standardSize }
        // A cold landscape launch still mounts the normal library once, without exposing it.
        return CGSize(width: min(current.width, current.height), height: max(current.width, current.height))
    }

    private func standardContent(size: CGSize, isActive: Bool, isInteractive: Bool) -> some View {
        let usesColumns = size.width >= 760 && !dynamicTypeSize.isAccessibilitySize
        let layout = usesColumns
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 40))
            : AnyLayout(VStackLayout(spacing: 28))

        return ScrollView {
            VStack(spacing: 28) {
                header

                if viewModel.isImporting {
                    HStack(spacing: 12) {
                        ProgressView().tint(theme.accent)
                        Text(L10n.text("Добавление аудио…"))
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                        Spacer()
                        Button(L10n.text("Отменить")) {
                            buttonFeedbackTrigger.toggle()
                            viewModel.cancelImport()
                        }
                        .font(.subheadline)
                        .frame(minHeight: 44)
                    }
                }

                layout {
                    PlayerPanelV1(viewModel: viewModel, isActive: isActive, isInteractive: isInteractive)
                        .frame(maxWidth: usesColumns ? 400 : .infinity)
                    playlistContent
                        .frame(maxWidth: usesColumns ? 520 : .infinity)
                }
            }
            .padding(.horizontal, size.width < 380 ? 20 : 28)
            .padding(.top, 16)
            .padding(.bottom, 36)
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity)
        }
        .coordinateSpace(name: "player-library-viewport")
        .scrollIndicators(.hidden)
        .background(theme.background.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if isInteractive, let title = viewModel.preparingTrackTitle {
                preparationBanner(title)
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
    }

    private var playlistContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let error = viewModel.importError { errorMessage(error) }
            Picker(L10n.text("Источник музыки"), selection: $libraryMode) {
                Text(L10n.text("Плейлисты")).tag(LibraryMode.playlists)
                Text(L10n.text("Папки")).tag(LibraryMode.folders)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("library-mode")
            .onChange(of: libraryMode) { _, mode in onLibraryModeChange(mode) }

            if libraryMode == .playlists {
                PlaylistPanelV1(viewModel: viewModel)
            } else {
                folderLibrary
            }
        }
    }

    private func preparationBanner(_ title: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(theme.accent)
                .accessibilityHidden(true)
            Text(L10n.format("Подготовка: %@", title))
                .font(.subheadline)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(L10n.text("Отмена")) {
                Task { await viewModel.performPlaybackCommand(.pause) }
            }
            .font(.subheadline)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minHeight: 44)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .softPanelV1(cornerRadius: 18)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("playback-preparation")
    }

    private var header: some View {
        HStack(alignment: .top) {
            DeveloperBrandV1()

            Spacer(minLength: 12)

            VStack(spacing: 10) {
                CircularButtonV1(symbol: "slider.horizontal.3", label: L10n.text("Настройки")) {
                    viewModel.showSettings = true
                }
                CircularButtonV1(
                    symbol: viewModel.playbackMode.symbol,
                    label: L10n.text("Режим воспроизведения"),
                    isProminent: viewModel.playbackMode != .off,
                    action: viewModel.cyclePlaybackMode
                )
                .accessibilityValue(viewModel.playbackModeTitle)
                .accessibilityHint(L10n.format("Следующий режим: %@", viewModel.nextPlaybackModeTitle))
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
                Image(systemName: "xmark").frame(width: 44, height: 44)
            }
            .accessibilityLabel(L10n.text("Скрыть сообщение"))
        }
        .padding(16)
        .softPanelV1(cornerRadius: 18)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player-error-banner")
    }
}
