import LibraryDomain
import SwiftUI

struct PlaylistOrderEditorV1: View {
    @ObservedObject var viewModel: ATPlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.playerThemeV1) private var theme
    @State private var operationError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(viewModel.sections, id: \.id) { section in
                        HStack(spacing: 12) {
                            Image(systemName: "music.note.list")
                                .foregroundStyle(theme.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(section.name)
                                    .font(.body)
                                    .foregroundStyle(theme.textPrimary)
                                    .lineLimit(2)
                                Text("Треков: \(section.tracks.count)")
                                    .font(.caption)
                                    .foregroundStyle(theme.textSecondary)
                            }
                            Spacer(minLength: 8)
                        }
                        .frame(minHeight: 44)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("playlist-order-\(section.id.uuidString)")
                        .listRowBackground(theme.surface)
                    }
                    .onMove(perform: moveSections)
                } footer: {
                    Text("Перетащите плейлисты за значок справа. Порядок сохраняется автоматически.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .disabled(viewModel.isImporting)
            .navigationTitle("Порядок плейлистов")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .tint(theme.accent)
        .alert("Не удалось сохранить изменения", isPresented: Binding(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )) {
            Button("Понятно", role: .cancel) { operationError = nil }
        } message: {
            Text(operationError ?? "")
        }
    }

    private func moveSections(from source: IndexSet, to destination: Int) {
        guard viewModel.moveSections(from: source, to: destination) else {
            operationError = viewModel.importError ?? "Не удалось сохранить порядок плейлистов."
            return
        }
    }
}
