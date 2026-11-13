import AppLocalization
import FolderDomain
import SwiftUI
import UniformTypeIdentifiers

public struct FolderBrowserView: View {
    @ObservedObject private var model: FolderBrowserViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @State private var sourceToRemove: FolderSource?
    @State private var showingRemoval = false
    private let onPresentationChange: (Bool) -> Void

    public init(model: FolderBrowserViewModel, onPresentationChange: @escaping (Bool) -> Void = { _ in }) {
        self.model = model
        self.onPresentationChange = onPresentationChange
    }

    private var accent: Color {
        colorScheme == .dark
            ? Color(red: 0.66, green: 0.80, blue: 0.71)
            : Color(red: 0.30, green: 0.43, blue: 0.36)
    }

    private var surface: Color {
        colorScheme == .dark
            ? Color(red: 0.13, green: 0.15, blue: 0.14)
            : Color(red: 0.92, green: 0.94, blue: 0.93)
    }

    public var body: some View {
        let _ = locale
        VStack(alignment: .leading, spacing: 16) {
            controls
            if let error = model.errorMessage { errorView(error) }
            if model.source != nil { pathBar }

            if model.isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(L10n.text("Чтение папки…")).font(.subheadline)
                }
                .accessibilityElement(children: .combine)
            }

            if model.source == nil {
                roots
            } else {
                directoryEntries
            }
        }
        .tint(accent)
        .fileImporter(
            isPresented: $model.showPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: model.importFolder
        )
        .confirmationDialog(L10n.text("Убрать папку из ATPlayer?"), isPresented: $showingRemoval, titleVisibility: .visible) {
            if let sourceToRemove {
                Button(L10n.format("Убрать «%@»", sourceToRemove.name), role: .destructive) { model.remove(sourceToRemove) }
            }
            Button(L10n.text("Отмена"), role: .cancel) { sourceToRemove = nil }
        } message: {
            Text(L10n.text("Исходные папки и файлы сохранятся. Воспроизведение из этой папки остановится."))
        }
        .onChange(of: model.showPicker || showingRemoval, initial: true) { _, isPresented in
            onPresentationChange(isPresented)
        }
        .onAppear { onPresentationChange(model.showPicker || showingRemoval) }
        .onDisappear { onPresentationChange(false) }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                model.showPicker = true
            } label: {
                Label(model.isUpdatingSources ? L10n.text("Сохранение…") : L10n.text("Добавить папку"), systemImage: "folder.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .disabled(model.isUpdatingSources)
            .accessibilityIdentifier("add-folder")
            Spacer(minLength: 0)
            Button(action: model.refresh) {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(L10n.text("Обновить папку"))
            .accessibilityIdentifier("refresh-folder")
            .disabled(model.isUpdatingSources)
        }
    }

    private var pathBar: some View {
        HStack(spacing: 8) {
            Button(action: model.goBack) {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(model.relativePath.isEmpty ? L10n.text("К списку папок") : L10n.text("На уровень выше"))
            .accessibilityIdentifier("folder-back")
            Text(model.pathTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(L10n.format("Текущая папка: %@", model.pathTitle))
        }
    }

    private var roots: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.sources.isEmpty, !model.isLoading {
                emptyState(
                    title: L10n.text("Папки ещё не добавлены"),
                    text: L10n.text("Выберите папку в приложении «Файлы». Сохранится только доступ к выбранному каталогу.")
                )
            }
            ForEach(model.sources) { source in
                HStack(spacing: 8) {
                    Button { model.open(source) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill").foregroundStyle(accent)
                            Text(source.name)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("folder-source-\(source.id.uuidString)")
                    Button {
                        sourceToRemove = source
                        showingRemoval = true
                    } label: {
                        Image(systemName: "minus.circle").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(L10n.format("Убрать папку %@", source.name))
                    .disabled(model.isUpdatingSources)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(surface, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var directoryEntries: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            if model.entries.isEmpty, !model.isLoading, model.errorMessage == nil {
                emptyState(title: L10n.text("Папка пуста"), text: L10n.text("Здесь нет вложенных папок и поддерживаемых аудиофайлов."))
            }
            ForEach(model.entries) { entry in
                Button {
                    if entry.kind == .directory { model.open(entry) }
                    else { model.play(entry) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: entry.kind == .directory ? "folder.fill" : "music.note")
                            .foregroundStyle(accent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            if entry.kind == .audio { preparationLabel(for: entry) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: entry.kind == .directory ? "chevron.right" : "play.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accent)
                    }
                    .frame(minHeight: 48)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(surface, in: RoundedRectangle(cornerRadius: 14))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint(entry.kind == .directory ? L10n.text("Открыть папку") : L10n.text("Воспроизвести файлы только этой папки"))
                .accessibilityIdentifier("folder-entry-\(entry.id.uuidString)")
            }
        }
    }

    @ViewBuilder
    private func preparationLabel(for entry: FolderEntry) -> some View {
        switch model.preparation[entry.id] ?? .waiting {
        case .waiting:
            EmptyView()
        case .preparing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(L10n.text("Подготовка…")).font(.caption).foregroundStyle(.secondary)
            }
        case .ready:
            Label(L10n.text("Подготовлен"), systemImage: "checkmark.circle")
                .font(.caption).foregroundStyle(.secondary)
        case let .failed(message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
    }

    private func emptyState(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func errorView(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
            Text(error).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            Button { model.errorMessage = nil } label: {
                Image(systemName: "xmark").frame(width: 44, height: 44)
            }
            .accessibilityLabel(L10n.text("Скрыть сообщение папки"))
        }
        .padding(12)
        .background(surface, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("folder-error")
    }
}
