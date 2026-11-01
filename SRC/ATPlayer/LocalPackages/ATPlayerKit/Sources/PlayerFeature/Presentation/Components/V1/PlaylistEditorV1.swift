import LibraryDomain
import PlaybackDomain
import SwiftUI

struct PlaylistEditorV1: View {
    let section: Playlist
    @ObservedObject var viewModel: ATPlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.playerThemeV1) private var theme
    @State private var selectedTrackIDs = Set<UUID>()
    @State private var pendingRemovalIDs = Set<UUID>()
    @State private var isConfirmingRemoval = false
    @State private var operationError: String?
    @State private var buttonFeedbackTrigger = false

    private var tracks: [PlaylistTrack] { viewModel.tracks(in: section) }
    private var trackIDs: Set<UUID> { Set(tracks.map(\.id)) }
    private var allTracksSelected: Bool { !trackIDs.isEmpty && selectedTrackIDs == trackIDs }

    var body: some View {
        NavigationStack {
            List(selection: $selectedTrackIDs) {
                if !tracks.isEmpty {
                    Section {
                        ForEach(tracks, id: \.id) { track in
                            trackRow(track)
                                .tag(track.id)
                                .listRowBackground(theme.surface)
                        }
                        .onMove(perform: moveTracks)
                    } footer: {
                        Text("Выберите треки для удаления или перетащите их за значок справа. Порядок сохраняется автоматически.")
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .disabled(viewModel.isImporting)
            .overlay {
                if tracks.isEmpty {
                    ContentUnavailableView(
                        "Плейлист пуст",
                        systemImage: "music.note.list",
                        description: Text("Добавьте музыку в плейлист на главном экране.")
                    )
                }
            }
            .navigationTitle(section.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(allTracksSelected ? "Снять выбор" : "Выбрать все") {
                        buttonFeedbackTrigger.toggle()
                        selectedTrackIDs = allTracksSelected ? [] : trackIDs
                    }
                    .disabled(tracks.isEmpty || viewModel.isImporting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Text("Выбрано: \(selectedTrackIDs.count)")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)

                    Spacer()

                    Button(role: .destructive) {
                        pendingRemovalIDs = selectedTrackIDs.intersection(trackIDs)
                        guard !pendingRemovalIDs.isEmpty else { return }
                        buttonFeedbackTrigger.toggle()
                        isConfirmingRemoval = true
                    } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                    .disabled(selectedTrackIDs.isEmpty || viewModel.isImporting)
                }
            }
        }
        .tint(theme.accent)
        .playerButtonFeedbackV1(trigger: buttonFeedbackTrigger)
        .onChange(of: trackIDs) { _, availableIDs in
            selectedTrackIDs.formIntersection(availableIDs)
        }
        .confirmationDialog(
            "Удалить выбранные треки?",
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Удалить выбранные (\(pendingRemovalIDs.count))", role: .destructive) {
                removeSelectedTracks()
            }
            Button("Отмена", role: .cancel) { pendingRemovalIDs.removeAll() }
        } message: {
            Text("Треки будут удалены из плейлиста. Исходные аудиофайлы сохранятся.")
        }
        .alert("Не удалось сохранить изменения", isPresented: Binding(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )) {
            Button("Понятно", role: .cancel) { operationError = nil }
        } message: {
            Text(operationError ?? "")
        }
    }

    private func trackRow(_ track: PlaylistTrack) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(track.displayName)
                    .font(.body)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)

                if let artist = track.displayArtist {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(track.durationText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(theme.textSecondary)
                .fixedSize()
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private func moveTracks(from source: IndexSet, to destination: Int) {
        guard viewModel.moveTracks(in: section, from: source, to: destination) else {
            operationError = viewModel.importError ?? "Не удалось сохранить порядок треков."
            return
        }
    }

    private func removeSelectedTracks() {
        let removedIDs = pendingRemovalIDs
        pendingRemovalIDs.removeAll()
        guard viewModel.removeTracks(withIDs: removedIDs, from: section) else {
            operationError = viewModel.importError ?? "Не удалось удалить выбранные треки."
            return
        }
        selectedTrackIDs.subtract(removedIDs)
    }
}
