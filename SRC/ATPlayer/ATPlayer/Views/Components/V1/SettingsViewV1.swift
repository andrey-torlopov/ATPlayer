import SwiftUI
import UniformTypeIdentifiers

struct SettingsViewV1: View {
    @ObservedObject var viewModel: ATPlayerViewModel
    @Environment(\.playerThemeV1) private var theme
    @State private var exportDocument = PlaylistExportDocumentV1(data: Data())
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var buttonFeedbackTrigger = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 14) {
                    sectionLabel("Звук")
                    NavigationLink {
                        EqualizerSettingsViewV1(playbackService: viewModel.playbackService)
                            .environment(\.playerThemeV1, theme)
                    } label: {
                        settingsRow(
                            symbol: "slider.horizontal.3",
                            title: "Эквалайзер",
                            subtitle: "10 полос и предусиление",
                            trailingSymbol: "chevron.right"
                        )
                    }
                    .buttonStyle(.plain)
                    .softPanelV1()
                }

                VStack(alignment: .leading, spacing: 14) {
                    sectionLabel("Медиатека")
                    Button {
                        buttonFeedbackTrigger.toggle()
                        exportPlaylists()
                    } label: {
                        settingsRow(
                            symbol: "square.and.arrow.up",
                            title: "Экспорт плейлистов",
                            subtitle: "Сохранить список в JSON",
                            trailingSymbol: "arrow.up.right"
                        )
                    }
                    .buttonStyle(.plain)
                    .softPanelV1()

                    Text("Экспорт содержит названия плейлистов, треков и пути к файлам. Аудиофайлы сохраняются отдельно.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
            }
            .padding(24)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Настройки")
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
                    exportError = "Не удалось сохранить файл. Проверьте доступ к выбранной папке и попробуйте снова."
                }
            }
        }
        .alert("Экспорт не выполнен", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("Понятно", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
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
            exportError = "Не удалось подготовить плейлисты к экспорту. Попробуйте снова."
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
