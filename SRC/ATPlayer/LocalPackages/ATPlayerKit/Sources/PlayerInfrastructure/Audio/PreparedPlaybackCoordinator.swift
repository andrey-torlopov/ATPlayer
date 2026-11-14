import Foundation
import PlaybackDomain

/// A prepared source replaces the outgoing source on one engine sample boundary.
/// The source gate closes A on precisely the frame on which B begins at frame zero.
struct PreparedPlaybackCoordinator {
    struct Plan: Equatable {
        let handle: AudioPreparedTrack
        let playbackID: UUID
        let generation: UInt64
        let sampleRate: Double
        let startFrame: Int64
    }

    private(set) var plan: Plan?
    private var revision: UInt64 = 0

    mutating func makePlan(handle: AudioPreparedTrack, playbackID: UUID,
                           earliestStart: Int64, sampleRate: Double,
                           outgoingEnd: Int64?) -> Plan {
        revision &+= 1
        // A ready automatic replacement uses exact EOF. A late decode or manual
        // replacement starts at the first safely schedulable frame, without a tail.
        let boundary = max(earliestStart, outgoingEnd ?? earliestStart)
        let result = Plan(handle: handle, playbackID: playbackID, generation: revision,
                          sampleRate: sampleRate, startFrame: boundary)
        plan = result
        return result
    }

    mutating func cancel() -> Plan? {
        defer { plan = nil }
        return plan
    }
}
