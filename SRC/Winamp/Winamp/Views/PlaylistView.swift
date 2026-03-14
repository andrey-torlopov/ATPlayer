import SwiftUI

struct PlaylistPanelView: View {
    @ObservedObject var viewModel: WinampViewModel
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
    @ObservedObject var viewModel: WinampViewModel
    let theme: AppTheme
    @State private var isExpanded = true

    var body: some View {
        Section {
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

                Button {
                    viewModel.requestImport(to: section)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Добавить треки")
                            .font(AppFonts.caption(12))
                    }
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .listRowBackground(Color.clear)
            }
        } header: {
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
            .onLongPressGesture {
                viewModel.requestImport(to: section)
            }
            .contextMenu {
                Button {
                    viewModel.requestImport(to: section)
                } label: {
                    Label("Добавить треки", systemImage: "plus")
                }

                if viewModel.sections.count > 1 {
                    Button(role: .destructive) {
                        viewModel.removeSection(section)
                    } label: {
                        Label("Удалить секцию", systemImage: "trash")
                    }
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
