import AppLocalization
import LibraryDomain
import PlaybackDomain
import SwiftUI
import UniformTypeIdentifiers

struct SettingsViewV1: View {
    @ObservedObject var viewModel: ATPlayerViewModel
    @Environment(\.playerThemeV1) private var theme
    @Environment(\.locale) private var locale
    @AppStorage(PlayerAppearance.storageKey) private var appearance = PlayerAppearance.system.rawValue
    @AppStorage(L10n.languageKey) private var language = L10n.languageCode
    @State private var exportDocument = PlaylistExportDocumentV1(data: Data())
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var buttonFeedbackTrigger = false
    @AppStorage(AmbientPreferences.keepsScreenAwakeKey) private var keepsScreenAwake = true

    var body: some View {
        let _ = locale
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                displayPreferences

                VStack(alignment: .leading, spacing: 14) {
                    sectionLabel(L10n.text("Звук"))
                    NavigationLink {
                        EqualizerSettingsViewV1(playbackService: viewModel.playbackState)
                            .environment(\.playerThemeV1, theme)
                    } label: {
                        settingsRow(
                            symbol: "slider.horizontal.3",
                            title: L10n.text("Эквалайзер"),
                            subtitle: L10n.text("10 полос и предусиление"),
                            trailingSymbol: "chevron.right"
                        )
                    }
                    .buttonStyle(.plain)
                    .softPanelV1()
                }

                VStack(alignment: .leading, spacing: 14) {
                    sectionLabel(L10n.text("Горизонтальный режим"))
                    Toggle(isOn: $keepsScreenAwake) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.text("Не выключать экран"))
                                .font(.body)
                                .foregroundStyle(theme.textPrimary)
                            Text(L10n.text("В горизонтальном режиме, пока играет музыка. Экран будет расходовать больше заряда."))
                                .font(.footnote)
                                .foregroundStyle(theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(20)
                    .softPanelV1()
                    .accessibilityIdentifier("ambient-keep-screen-awake")
                }

                VStack(alignment: .leading, spacing: 14) {
                    sectionLabel(L10n.text("Медиатека"))
                    Button {
                        buttonFeedbackTrigger.toggle()
                        exportPlaylists()
                    } label: {
                        settingsRow(
                            symbol: "square.and.arrow.up",
                            title: L10n.text("Экспорт плейлистов"),
                            subtitle: L10n.text("Сохранить список в JSON"),
                            trailingSymbol: "arrow.up.right"
                        )
                    }
                    .buttonStyle(.plain)
                    .softPanelV1()

                    Text(L10n.text("Экспорт содержит названия плейлистов, треков и пути к файлам. Аудиофайлы сохраняются отдельно."))
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }

                VStack(alignment: .leading, spacing: 14) {
                    sectionLabel(L10n.text("О приложении"))
                    Link(destination: URL(string: "https://github.com/andrey-torlopov/ATPlayer/blob/main/PRIVACY.md")!) {
                        settingsRow(
                            symbol: "hand.raised",
                            title: L10n.text("Конфиденциальность"),
                            subtitle: L10n.text("Как приложение работает с данными"),
                            trailingSymbol: "arrow.up.right"
                        )
                    }
                    .buttonStyle(.plain)
                    .softPanelV1()

                    Link(destination: URL(string: "mailto:mail@torlopov.dev")!) {
                        settingsRow(
                            symbol: "envelope",
                            title: L10n.text("Поддержка"),
                            subtitle: "mail@torlopov.dev",
                            trailingSymbol: "arrow.up.right"
                        )
                    }
                    .buttonStyle(.plain)
                    .softPanelV1()
                }

                VStack(alignment: .leading, spacing: 14) {
                    sectionLabel(L10n.text("Об авторе"))
                    AboutDeveloperSectionV1()
                }
            }
            .padding(24)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle(L10n.text("Настройки"))
        .navigationBarTitleDisplayMode(.inline)
        .tint(theme.accent)
        .playerButtonFeedbackV1(trigger: buttonFeedbackTrigger)
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "playlists.json"
        ) { result in
            if case let .failure(error) = result {
                let cocoaError = error as NSError
                let wasCancelled = cocoaError.domain == NSCocoaErrorDomain
                    && cocoaError.code == CocoaError.userCancelled.rawValue
                if !wasCancelled {
                    exportError = L10n.text("Не удалось сохранить файл. Проверьте доступ к выбранной папке и попробуйте снова.")
                }
            }
        }
        .alert(L10n.text("Экспорт не выполнен"), isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button(L10n.text("Понятно"), role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private var displayPreferences: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                themeSelection
                Spacer(minLength: 0)
                languageSelection
            }
            VStack(alignment: .leading, spacing: 20) {
                themeSelection
                languageSelection
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .softPanelV1()
        .accessibilityIdentifier("settings-appearance-language")
    }

    private var themeSelection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(L10n.text("Тема"))
            HStack(spacing: 6) {
                ForEach(PlayerAppearance.allCases, id: \.rawValue) { option in
                    preferenceButton(isSelected: appearance == option.rawValue) {
                        appearance = option.rawValue
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: option.symbol)
                                .font(.body)
                            Text(option.title)
                                .font(.caption2)
                                .fixedSize()
                        }
                    }
                    .accessibilityLabel(option.title)
                    .accessibilityIdentifier("theme-\(option.rawValue)")
                }
            }
        }
    }

    private var languageSelection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(L10n.text("Язык"))
            HStack(spacing: 6) {
                ForEach(["ru", "en"], id: \.self) { code in
                    preferenceButton(isSelected: language == code) {
                        language = code
                    } label: {
                        Text(code.uppercased())
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityLabel(code == "ru" ? "Русский" : "English")
                    .accessibilityIdentifier("language-\(code)")
                }
            }
        }
    }

    private func preferenceButton<Label: View>(
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button {
            buttonFeedbackTrigger.toggle()
            action()
        } label: {
            label()
                .padding(.horizontal, 6)
                .frame(minWidth: 44, minHeight: 56)
                .foregroundStyle(isSelected ? theme.background : theme.textPrimary)
                .background(isSelected ? theme.accent : theme.elevated,
                            in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isSelected ? theme.accent : theme.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .tracking(2)
            .foregroundStyle(theme.textSecondary)
    }

    private func settingsRow(
        symbol: String,
        title: String,
        subtitle: String,
        trailingSymbol: String
    ) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(theme.accent)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
            }

            Spacer(minLength: 4)

            Image(systemName: trailingSymbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textTertiary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func exportPlaylists() {
        let data = viewModel.exportPlaylistsJSON()
        guard !data.isEmpty else {
            exportError = L10n.text("Не удалось подготовить плейлисты к экспорту. Попробуйте снова.")
            return
        }
        exportDocument = PlaylistExportDocumentV1(data: data)
        isExporting = true
    }
}

private struct PlaylistExportDocumentV1: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
