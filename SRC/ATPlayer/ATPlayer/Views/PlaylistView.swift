import SwiftUI
import UIKit

struct PlaylistPanelView: View {
    @ObservedObject var viewModel: ATPlayerViewModel
    @Environment(\.theme) private var theme
    @State private var showNewSectionAlert = false
    @State private var newSectionName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PLAYLIST")
                    .font(AppFonts.body())
                    .foregroundStyle(theme.accent)
                Spacer()
                Button {
                    showNewSectionAlert = true
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(theme.accentSecondary)
                }
            }

            List {
                ForEach(viewModel.sections, id: \.id) { section in
                    SectionView(
                        section: section,
                        viewModel: viewModel,
                        theme: theme
                    )
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 200)

            if let message = viewModel.importError {
                Text(message)
                    .font(AppFonts.caption())
                    .foregroundStyle(theme.destructive)
                    .lineLimit(2)
            }
        }
        .themedPanel()
        .alert("Новый плейлист", isPresented: $showNewSectionAlert) {
            TextField("Название", text: $newSectionName)
            Button("Создать") {
                let name = newSectionName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                viewModel.addSection(name: name)
                newSectionName = ""
            }
            Button("Отмена", role: .cancel) {
                newSectionName = ""
            }
        }
    }
}

private struct SectionView: View {
    let section: PlaylistSection
    @ObservedObject var viewModel: ATPlayerViewModel
    let theme: AppTheme
    @State private var isExpanded = true
    @State private var showDeleteConfirmation = false
    @State private var showRenameAlert = false
    @State private var renameSectionName = ""

    var body: some View {
        sectionHeader
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0))
            .alert("Удалить плейлист \"\(section.name)\"?", isPresented: $showDeleteConfirmation) {
                Button("Удалить", role: .destructive) {
                    viewModel.removeSection(section)
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Все треки в этом плейлисте будут удалены.")
            }
            .alert("Переименовать плейлист", isPresented: $showRenameAlert) {
                TextField("Название", text: $renameSectionName)
                Button("Сохранить") {
                    let name = renameSectionName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    viewModel.renameSection(section, to: name)
                }
                Button("Отмена", role: .cancel) {}
            }

        if isExpanded {
            let tracks = viewModel.tracks(in: section)
            ForEach(tracks, id: \.id) { track in
                TrackRowView(
                    track: track,
                    isSelected: track.id == viewModel.selectedTrackID,
                    theme: theme
                ) {
                    viewModel.selectedTrackID = track.id
                    Task { await viewModel.play(track: track) }
                }
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        viewModel.removeTrack(track)
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var sectionHeader: some View {
        HStack {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                    Text(section.name.uppercased())
                        .font(AppFonts.caption(12))
                }
                .foregroundStyle(theme.accentSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("\(viewModel.tracks(in: section).count)")
                .font(AppFonts.caption(10))
                .foregroundStyle(theme.textSecondary)
        }
        .contextMenu {
            Button {
                viewModel.requestImport(to: section)
            } label: {
                Label("Добавить треки", systemImage: "plus")
            }

            Button {
                renameSectionName = section.name
                showRenameAlert = true
            } label: {
                Label("Переименовать", systemImage: "pencil")
            }

            if viewModel.sections.count > 1 {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Удалить плейлист", systemImage: "trash")
                }
            }
        }
    }
}

private struct TrackRowView: View {
    let track: TrackItem
    let isSelected: Bool
    let theme: AppTheme
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                TrackArtworkView(artworkData: track.artwork, size: 32, theme: theme)

                if track.isCorrupted {
                    Text("❌")
                        .font(.system(size: 12))
                }

                Text(track.displayTitle)
                    .foregroundStyle(trackColor)
                    .font(AppFonts.body(13))
                    .strikethrough(track.isCorrupted)

                Spacer()

                Text(track.durationText)
                    .foregroundStyle(theme.textSecondary)
                    .font(AppFonts.caption(11))
            }
        }
        .listRowBackground(
            isSelected
                ? theme.accent.opacity(0.15)
                : Color.clear
        )
    }

    private var trackColor: Color {
        if track.isCorrupted {
            return theme.textSecondary
        }
        return isSelected ? theme.accent : theme.textPrimary
    }
}

private struct TrackArtworkView: View {
    let artworkData: Data?
    let size: CGFloat
    let theme: AppTheme

    var body: some View {
        if let artworkData, let uiImage = UIImage(data: artworkData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(theme.panel)
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(theme.textSecondary)
                )
        }
    }
}
