import SwiftUI
import UIKit

struct PlaylistPanelViewV0: View {
    @ObservedObject var viewModel: ATPlayerViewModel
    @Environment(\.themeV0) private var themeV0
    @State private var showNewSectionAlert = false
    @State private var newSectionName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PLAYLIST")
                    .font(AppFontsV0.body())
                    .foregroundStyle(themeV0.accent)
                Spacer()
                Button {
                    showNewSectionAlert = true
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(themeV0.accentSecondary)
                }
            }

            List {
                ForEach(viewModel.sections, id: \.id) { section in
                    SectionViewV0(
                        section: section,
                        viewModel: viewModel,
                        themeV0: themeV0
                    )
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 200)

            if let message = viewModel.importError {
                Text(message)
                    .font(AppFontsV0.caption())
                    .foregroundStyle(themeV0.destructive)
                    .lineLimit(2)
            }
        }
        .themedPanelV0()
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

private struct SectionViewV0: View {
    let section: PlaylistSection
    @ObservedObject var viewModel: ATPlayerViewModel
    let themeV0: AppThemeV0
    @State private var isExpanded: Bool
    @State private var showDeleteConfirmation = false
    @State private var showRenameAlert = false
    @State private var renameSectionName = ""

    init(section: PlaylistSection, viewModel: ATPlayerViewModel, themeV0: AppThemeV0) {
        self.section = section
        self.viewModel = viewModel
        self.themeV0 = themeV0
        _isExpanded = State(initialValue: section.id == viewModel.lastPlayedSectionID)
    }

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
                TrackRowViewV0(
                    track: track,
                    isSelected: track.id == viewModel.selectedTrackID,
                    themeV0: themeV0
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
                        .font(AppFontsV0.caption(12))
                }
                .foregroundStyle(themeV0.accentSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("\(viewModel.tracks(in: section).count)")
                .font(AppFontsV0.caption(10))
                .foregroundStyle(themeV0.textSecondary)
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

private struct TrackRowViewV0: View {
    let track: TrackItem
    let isSelected: Bool
    let themeV0: AppThemeV0
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                TrackArtworkViewV0(artworkData: track.artwork, size: 32, themeV0: themeV0)

                if track.isCorrupted {
                    Text("❌")
                        .font(.system(size: 12))
                }

                Text(track.displayTitle)
                    .foregroundStyle(trackColor)
                    .font(AppFontsV0.body(13))
                    .strikethrough(track.isCorrupted)

                Spacer()

                Text(track.durationText)
                    .foregroundStyle(themeV0.textSecondary)
                    .font(AppFontsV0.caption(11))
            }
        }
        .listRowBackground(
            isSelected
                ? themeV0.accent.opacity(0.15)
                : Color.clear
        )
    }

    private var trackColor: Color {
        if track.isCorrupted {
            return themeV0.textSecondary
        }
        return isSelected ? themeV0.accent : themeV0.textPrimary
    }
}

private struct TrackArtworkViewV0: View {
    let artworkData: Data?
    let size: CGFloat
    let themeV0: AppThemeV0

    var body: some View {
        if let artworkData, let uiImage = UIImage(data: artworkData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(themeV0.panel)
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(themeV0.textSecondary)
                )
        }
    }
}
