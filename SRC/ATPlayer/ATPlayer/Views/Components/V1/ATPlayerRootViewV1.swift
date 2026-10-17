import SwiftUI

struct ATPlayerRootViewV1: View {
    @ObservedObject var viewModel: ATPlayerViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                                Button("Отменить", action: viewModel.cancelImport)
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
            PlaylistPanelV1(viewModel: viewModel)
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(theme.accent)
                Text("ATPlayer")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .tracking(-0.5)
                    .foregroundStyle(theme.textPrimary)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 12)

            CircularButtonV1(symbol: "slider.horizontal.3", label: "Настройки") {
                viewModel.showSettings = true
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
