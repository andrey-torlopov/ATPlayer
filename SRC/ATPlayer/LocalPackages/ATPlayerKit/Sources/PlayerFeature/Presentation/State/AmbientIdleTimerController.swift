import Foundation
import UIKit

@MainActor
final class AmbientIdleTimerController {
    static let shared = AmbientIdleTimerController { isDisabled in
        UIApplication.shared.isIdleTimerDisabled = isDisabled
    }

    private var requests = AmbientIdleTimerRequests()
    private let setIdleTimerDisabled: @MainActor (Bool) -> Void

    init(setIdleTimerDisabled: @escaping @MainActor (Bool) -> Void) {
        self.setIdleTimerDisabled = setIdleTimerDisabled
    }

    func setRequested(_ requested: Bool, for owner: UUID) {
        guard let value = requests.setRequested(requested, for: owner) else { return }
        setIdleTimerDisabled(value)
    }

    func remove(_ owner: UUID) {
        setRequested(false, for: owner)
    }

    isolated deinit {
        if requests.isRequested { setIdleTimerDisabled(false) }
    }
}
