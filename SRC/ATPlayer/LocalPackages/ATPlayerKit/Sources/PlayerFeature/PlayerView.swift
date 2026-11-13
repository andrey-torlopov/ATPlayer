import AppLocalization
import SwiftUI

public enum LibraryMode: String, CaseIterable {
    case playlists
    case folders
}

/// The application composes independent library features through this UI slot.
public struct PlayerView: View {
    @ObservedObject private var viewModel: ATPlayerViewModel
    @AppStorage(PlayerAppearance.storageKey) private var appearance = PlayerAppearance.system.rawValue
    @AppStorage(L10n.languageKey) private var language = L10n.languageCode
    private let folderLibrary: AnyView
    private let onLibraryModeChange: (LibraryMode) -> Void
    private let isFolderPresentationActive: Bool

    public init(viewModel: ATPlayerViewModel, folderLibrary: AnyView,
                isFolderPresentationActive: Bool = false,
                onLibraryModeChange: @escaping (LibraryMode) -> Void) {
        self.viewModel = viewModel
        self.folderLibrary = folderLibrary
        self.onLibraryModeChange = onLibraryModeChange
        self.isFolderPresentationActive = isFolderPresentationActive
    }

    public var body: some View {
        ATPlayerRootView(viewModel: viewModel, folderLibrary: folderLibrary,
                         onLibraryModeChange: onLibraryModeChange,
                         isFolderPresentationActive: isFolderPresentationActive)
            .preferredColorScheme(PlayerAppearance(rawValue: appearance)?.colorScheme)
            .environment(\.locale, Locale(identifier: language))
    }
}
