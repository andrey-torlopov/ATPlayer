import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var viewModel: ATPlayerViewModel
    @Environment(\.theme) private var theme
    @State private var exportFileURL: URL?
    @State private var showFileExporter = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                exportSection
                equalizerSection
            }
            .padding()
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Настройки")
        .fileExporter(
            isPresented: $showFileExporter,
            document: JSONExportDocument(url: exportFileURL),
            contentType: .json,
            defaultFilename: "playlists.json"
        ) { result in
            if case let .failure(error) = result {
                viewModel.importError = "Не удалось сохранить: \(error.localizedDescription)"
            }
            cleanupExportFile()
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ЭКСПОРТ")
                .font(AppFonts.body())
                .foregroundStyle(theme.accent)

            Button {
                exportPlaylists()
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Экспортировать плейлисты в JSON")
                        .font(AppFonts.caption(13))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
        }
        .themedPanel()
    }

    private var equalizerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ЭКВАЛАЙЗЕР")
                .font(AppFonts.body())
                .foregroundStyle(theme.accent)

            NavigationLink {
                EqualizerWindowView(playbackService: viewModel.playbackService)
                    .environment(\.theme, theme)
            } label: {
                HStack {
                    Image(systemName: "slider.vertical.3")
                    Text("Настроить эквалайзер")
                        .font(AppFonts.caption(13))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accentSecondary)
        }
        .themedPanel()
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
            viewModel.importError = "Не удалось экспортировать: \(error.localizedDescription)"
        }
    }

    private func cleanupExportFile() {
        guard let url = exportFileURL else { return }
        try? FileManager.default.removeItem(at: url)
        exportFileURL = nil
    }
}

private struct JSONExportDocument: FileDocument {
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
