import SwiftUI

public enum LibraryMode: String, CaseIterable {
    case playlists
    case folders
}

/// The application composes independent library features through this UI slot.
public struct PlayerView: View {
    @ObservedObject private var viewModel: ATPlayerViewModel
    private let folderLibrary: AnyView
    private let onLibraryModeChange: (LibraryMode) -> Void

    public init(viewModel: ATPlayerViewModel, folderLibrary: AnyView,
                onLibraryModeChange: @escaping (LibraryMode) -> Void) {
        self.viewModel = viewModel
        self.folderLibrary = folderLibrary
        self.onLibraryModeChange = onLibraryModeChange
    }

    public var body: some View {
        ATPlayerRootView(viewModel: viewModel, folderLibrary: folderLibrary,
                         onLibraryModeChange: onLibraryModeChange)
    }
}
