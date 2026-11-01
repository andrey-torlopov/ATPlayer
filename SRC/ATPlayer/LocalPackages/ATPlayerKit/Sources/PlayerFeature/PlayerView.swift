import SwiftUI

/// The feature entry point. Its session is owned by the application composition root.
public struct PlayerView: View {
    @ObservedObject private var viewModel: ATPlayerViewModel

    public init(viewModel: ATPlayerViewModel) { self.viewModel = viewModel }

    public var body: some View { ATPlayerRootView(viewModel: viewModel) }
}
