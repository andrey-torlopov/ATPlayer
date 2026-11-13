import AppLocalization
import LibraryDomain
import PlaybackDomain
import SwiftUI
import UniformTypeIdentifiers

struct SettingsViewV0: View {
    @Environment(\.locale) private var locale
    @ObservedObject var viewModel: ATPlayerViewModel
    @Environment(\.themeV0) private var themeV0
    @State private var exportFileURL: URL?
    @State private var showFileExporter = false

    var body: some View {
        let _ = locale
        ScrollView {
            VStack(spacing: 16) {
                exportSection
                equalizerSection
            }
            .padding()
        }
        .background(themeV0.background.ignoresSafeArea())
        .navigationTitle(L10n.text("Настройки"))
        .fileExporter(
            isPresented: $showFileExporter,
            document: JSONExportDocumentV0(url: exportFileURL),
            contentType: .json,
            defaultFilename: "playlists.json"
        ) { result in
            if case let .failure(error) = result {
                viewModel.importError = L10n.format("Не удалось сохранить: %@", error.localizedDescription)
            }
            cleanupExportFile()
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("ЭКСПОРТ"))
                .font(AppFontsV0.body())
                .foregroundStyle(themeV0.accent)

            Button {
                exportPlaylists()
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text(L10n.text("Экспортировать плейлисты в JSON"))
                        .font(AppFontsV0.caption(13))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .tint(themeV0.accent)
        }
        .themedPanelV0()
    }

    private var equalizerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("ЭКВАЛАЙЗЕР"))
                .font(AppFontsV0.body())
                .foregroundStyle(themeV0.accent)

            NavigationLink {
                EqualizerWindowViewV0(playbackService: viewModel.playbackState)
                    .environment(\.themeV0, themeV0)
            } label: {
                HStack {
                    Image(systemName: "slider.vertical.3")
                    Text(L10n.text("Настроить эквалайзер"))
                        .font(AppFontsV0.caption(13))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .tint(themeV0.accentSecondary)
        }
        .themedPanelV0()
    }

    private func exportPlaylists() {
        let data = viewModel.exportPlaylistsJSON()
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("playlists.json")
        do {
            try data.write(to: fileURL)
            exportFileURL = fileURL
            showFileExporter = true
        } catch {
            viewModel.importError = L10n.format("Не удалось экспортировать: %@", error.localizedDescription)
        }
    }

    private func cleanupExportFile() {
        guard let url = exportFileURL else { return }
        try? FileManager.default.removeItem(at: url)
        exportFileURL = nil
    }
}

private struct JSONExportDocumentV0: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(url: URL?) {
        self.data = (try? Data(contentsOf: url ?? URL(fileURLWithPath: ""))) ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
