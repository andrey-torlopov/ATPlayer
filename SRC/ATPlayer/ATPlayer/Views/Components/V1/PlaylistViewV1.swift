import SwiftUI

struct PlaylistPanelV1: View {
    @ObservedObject var viewModel: ATPlayerViewModel
    @Environment(\.playerThemeV1) private var theme
    @State private var isCreatingPlaylist = false
    @State private var newPlaylistName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Плейлисты")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(2)
                        .foregroundStyle(theme.textSecondary)
                    Text("Треков: \(viewModel.allTracks.count)")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)
                }

                Spacer(minLength: 8)

                CircularButtonV1(
                    symbol: "plus",
                    label: "Создать плейлист",
                    size: 44
                ) {
                    newPlaylistName = ""
                    isCreatingPlaylist = true
                }
            }

            LazyVStack(spacing: 16) {
                ForEach(viewModel.sections, id: \.id) { section in
                    PlaylistSectionV1(section: section, viewModel: viewModel)
                }
            }
        }
        .alert("Новый плейлист", isPresented: $isCreatingPlaylist) {
            TextField("Название", text: $newPlaylistName)
                .textInputAutocapitalization(.sentences)
            Button("Создать") {
                let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                viewModel.addSection(name: name)
                newPlaylistName = ""
            }
            .disabled(newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Отмена", role: .cancel) { newPlaylistName = "" }
        }
    }
}

private struct PlaylistSectionV1: View {
    let section: PlaylistSection
    @ObservedObject var viewModel: ATPlayerViewModel
    @Environment(\.playerThemeV1) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded: Bool
    @State private var isRenaming = false
    @State private var isConfirmingDeletion = false
    @State private var playlistName = ""
    @State private var trackToRemove: TrackItem?
    @State private var buttonFeedbackTrigger = false
    @State private var isEditingTracks = false

    init(section: PlaylistSection, viewModel: ATPlayerViewModel) {
        self.section = section
        self.viewModel = viewModel
        _isExpanded = State(initialValue: viewModel.lastPlayedSectionID.map { $0 == section.id } ?? true)
    }

    private var tracks: [TrackItem] { viewModel.tracks(in: section) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if isExpanded {
                if tracks.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 5) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            PlaylistTrackRowV1(
                                track: track,
                                number: index + 1,
                                isSelected: track.id == viewModel.selectedTrackID,
                                onPlay: { Task { await viewModel.play(track: track) } },
                                onRemove: { trackToRemove = track }
                            )
                        }
                    }
                }
            }
        }
        .padding(18)
        .softPanelV1(cornerRadius: 24)
        .playerButtonFeedbackV1(trigger: buttonFeedbackTrigger)
        .sheet(isPresented: $isEditingTracks) {
            PlaylistEditorV1(section: section, viewModel: viewModel)
                .environment(\.playerThemeV1, theme)
        }
        .alert("Переименовать плейлист", isPresented: $isRenaming) {
            TextField("Название", text: $playlistName)
            Button("Сохранить") {
                let name = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                viewModel.renameSection(section, to: name)
            }
            .disabled(playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Отмена", role: .cancel) {}
        }
        .confirmationDialog(
            "Удалить плейлист «\(section.name)»?",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("Удалить плейлист", role: .destructive) { viewModel.removeSection(section) }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Плейлист и записи его треков будут удалены. Исходные аудиофайлы сохранятся.")
        }
        .confirmationDialog(
            "Удалить трек из плейлиста?",
            isPresented: Binding(
                get: { trackToRemove != nil },
                set: { if !$0 { trackToRemove = nil } }
            ),
            titleVisibility: .visible,
            presenting: trackToRemove
        ) { track in
            Button("Удалить трек", role: .destructive) {
                viewModel.removeTrack(track)
                trackToRemove = nil
            }
            Button("Отмена", role: .cancel) { trackToRemove = nil }
        } message: { track in
            Text("«\(track.displayName)» будет удалён из плейлиста. Исходный аудиофайл сохранится.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                buttonFeedbackTrigger.toggle()
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(theme.textTertiary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.name)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(2)
                        Text("Треков: \(tracks.count)")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(section.name), треков: \(tracks.count)")
            .accessibilityValue(isExpanded ? "Развёрнут" : "Свёрнут")
            .accessibilityHint(isExpanded ? "Свернуть плейлист" : "Развернуть плейлист")

            CircularButtonV1(
                symbol: "plus",
                label: "Добавить треки в \(section.name)",
                size: 44
            ) { viewModel.requestImport(to: section) }
            .disabled(viewModel.isImporting)

            Menu {
                Button {
                    isEditingTracks = true
                } label: {
                    Label("Редактировать треки", systemImage: "list.bullet")
                }
                .disabled(tracks.isEmpty || viewModel.isImporting)

                Button {
                    playlistName = section.name
                    isRenaming = true
                } label: {
                    Label("Переименовать", systemImage: "pencil")
                }
                Button(role: .destructive) { isConfirmingDeletion = true } label: {
                    Label("Удалить плейлист", systemImage: "trash")
                }
                .disabled(viewModel.isImporting)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Действия с плейлистом \(section.name)")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Здесь будет ваша музыка")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(theme.textPrimary)
            Text("Добавьте аудиофайлы или папку.")
                .font(.system(size: 13))
                .foregroundStyle(theme.textSecondary)
            Button {
                buttonFeedbackTrigger.toggle()
                viewModel.requestImport(to: section)
            } label: {
                Label("Добавить музыку", systemImage: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .frame(maxWidth: .infinity, minHeight: 20)
            }
            .buttonStyle(SoftButtonStyleV1())
            .disabled(viewModel.isImporting)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

private struct PlaylistTrackRowV1: View {
    let track: TrackItem
    let number: Int
    let isSelected: Bool
    let onPlay: () -> Void
    let onRemove: () -> Void
    @Environment(\.playerThemeV1) private var theme
    @State private var buttonFeedbackTrigger = false

    private var title: String { track.displayName }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                buttonFeedbackTrigger.toggle()
                onPlay()
            } label: {
                HStack(spacing: 12) {
                    Group {
                        if isSelected {
                            Circle().fill(theme.accent).frame(width: 5, height: 5)
                        } else {
                            Text("\(number)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                    .frame(width: 18)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 14, weight: isSelected ? .medium : .regular))
                            .foregroundStyle(track.isCorrupted ? theme.textTertiary : theme.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if track.isCorrupted {
                            Label("Не удалось прочитать файл", systemImage: "exclamationmark.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(theme.destructive)
                        }
                    }

                    Spacer(minLength: 8)

                    Text(track.durationText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize()
                }
                .frame(minHeight: 54)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), \(track.durationText)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityHint(track.isCorrupted ? "Попробовать воспроизвести снова" : "Воспроизвести трек")

            Menu {
                Button(role: .destructive, action: onRemove) {
                    Label("Удалить из плейлиста", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
                    .frame(width: 44, height: 54)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Действия с треком \(title)")
        }
        .playerButtonFeedbackV1(trigger: buttonFeedbackTrigger)
        .padding(.leading, 10)
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(isSelected ? theme.accentSoft : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(isSelected ? theme.accent.opacity(0.12) : Color.clear, lineWidth: 0.8)
        }
    }
}
