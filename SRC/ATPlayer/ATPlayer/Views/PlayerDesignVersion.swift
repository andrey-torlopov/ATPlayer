import SwiftUI

enum PlayerDesignVersion {
    case v0
    case v1

    /// The only switch needed to open the preserved interface for comparison.
    static let current: PlayerDesignVersion = .v1
}

struct ATPlayerRootView: View {
    @ObservedObject var viewModel: ATPlayerViewModel
    var version: PlayerDesignVersion = .current

    var body: some View {
        switch version {
        case .v0:
            ATPlayerRootViewV0(viewModel: viewModel)
        case .v1:
            ATPlayerRootViewV1(viewModel: viewModel)
        }
    }
}
