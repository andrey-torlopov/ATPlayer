import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var viewModel: ATPlayerViewModel
    @Environment(\.theme) private var theme
    @State private var showExportShare = false
    @State private var exportURL: URL?

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
        .sheet(isPresented: $showExportShare) {
            if let url = exportURL {
                ShareSheet(url: url)
            }
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
            exportURL = fileURL
            showExportShare = true
        } catch {
            viewModel.importError = "Не удалось экспортировать: \(error.localizedDescription)"
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
