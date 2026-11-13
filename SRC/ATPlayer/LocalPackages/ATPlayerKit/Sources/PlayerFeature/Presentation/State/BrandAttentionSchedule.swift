import Foundation

/// Counts only eligible foreground time. The caller supplies a monotonic instant,
/// so the schedule can be tested without timers or real waiting.
struct BrandAttentionSchedule {
    private let interval: Duration
    private var remaining: Duration
    private var eligibleSince: ContinuousClock.Instant?

    init(interval: Duration = .seconds(300)) {
        self.interval = max(.seconds(1), interval)
        remaining = max(.seconds(1), interval)
    }

    mutating func setEligible(_ isEligible: Bool, at now: ContinuousClock.Instant) {
        if isEligible {
            if eligibleSince == nil { eligibleSince = now }
        } else if let since = eligibleSince {
            remaining = max(.zero, remaining - max(.zero, since.duration(to: now)))
            eligibleSince = nil
        }
    }

    func delay(at now: ContinuousClock.Instant) -> Duration {
        guard let since = eligibleSince else { return remaining }
        return max(.zero, remaining - max(.zero, since.duration(to: now)))
    }

    mutating func fireIfDue(at now: ContinuousClock.Instant) -> Bool {
        guard eligibleSince != nil, delay(at: now) == .zero else { return false }
        // A late wake-up emits one event and begins a new interval, never a backlog.
        remaining = interval
        eligibleSince = now
        return true
    }

    mutating func reset(at now: ContinuousClock.Instant) {
        remaining = interval
        if eligibleSince != nil { eligibleSince = now }
    }
}
