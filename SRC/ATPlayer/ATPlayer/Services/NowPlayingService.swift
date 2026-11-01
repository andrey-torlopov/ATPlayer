import Foundation
import MediaPlayer

@MainActor
final class NowPlayingService {
    nonisolated struct Snapshot: Equatable, Sendable {
        let trackID: UUID
        let title: String
        let artist: String
        let duration: TimeInterval
        let currentTime: TimeInterval
        let isPlaying: Bool
        let canPlayPrevious: Bool
        let canPlayNext: Bool
    }

    nonisolated enum Command: Sendable {
        case play
        case pause
        case toggle
        case previous
        case next
        case seek(TimeInterval)
    }

    private let infoCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()
    private let handleCommand: @MainActor @Sendable (Command) -> Void
    private var registrations: [(command: MPRemoteCommand, target: Any)] = []
    private var latestSnapshot: Snapshot?
    private var publishedSnapshot: Snapshot?
    private var publishedAt: TimeInterval = 0

    init(handleCommand: @escaping @MainActor @Sendable (Command) -> Void) {
        self.handleCommand = handleCommand
        register(commandCenter.playCommand, action: .play)
        register(commandCenter.pauseCommand, action: .pause)
        register(commandCenter.togglePlayPauseCommand, action: .toggle)
        register(commandCenter.previousTrackCommand, action: .previous)
        register(commandCenter.nextTrackCommand, action: .next)
        let seek = commandCenter.changePlaybackPositionCommand
        registrations.append((seek, seek.addTarget(handler: Self.seekHandler(owner: self))))
        updateCommandAvailability(nil)
    }

    isolated deinit {
        // Remove only this service's handlers, without clearing a newer owner's state.
        for registration in registrations {
            registration.command.removeTarget(registration.target)
        }
    }

    func update(_ snapshot: Snapshot, force: Bool = false) {
        let duration = snapshot.duration.isFinite ? max(0, snapshot.duration) : 0
        let elapsed = snapshot.currentTime.isFinite ? min(duration, max(0, snapshot.currentTime)) : 0
        let state = Snapshot(
            trackID: snapshot.trackID,
            title: snapshot.title,
            artist: snapshot.artist,
            duration: duration,
            currentTime: elapsed,
            isPlaying: snapshot.isPlaying,
            canPlayPrevious: snapshot.canPlayPrevious,
            canPlayNext: snapshot.canPlayNext
        )

        if latestSnapshot == nil
            || latestSnapshot?.canPlayPrevious != state.canPlayPrevious
            || latestSnapshot?.canPlayNext != state.canPlayNext
            || latestSnapshot?.duration != state.duration {
            updateCommandAvailability(state)
        }
        latestSnapshot = state

        let now = ProcessInfo.processInfo.systemUptime
        if !force, let previous = publishedSnapshot,
           previous.trackID == state.trackID,
           previous.title == state.title,
           previous.artist == state.artist,
           previous.duration == state.duration,
           previous.isPlaying == state.isPlaying {
            let timeSinceUpdate = max(0, now - publishedAt)
            let predictedElapsed = min(
                duration,
                previous.currentTime + (previous.isPlaying ? timeSinceUpdate : 0)
            )
            // MediaPlayer extrapolates elapsed time from this anchor and playback rate.
            // Explicit seeks use force; drift also repairs the anchor after a stall.
            if abs(state.currentTime - predictedElapsed) < 0.25,
               !state.isPlaying || timeSinceUpdate < 5 {
                return
            }
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: state.title,
            MPMediaItemPropertyPlaybackDuration: state.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: state.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: state.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyExternalContentIdentifier: state.trackID.uuidString,
            MPNowPlayingInfoPropertyIsLiveStream: false
        ]
        if !state.artist.isEmpty {
            info[MPMediaItemPropertyArtist] = state.artist
        }
        infoCenter.nowPlayingInfo = info
        publishedSnapshot = state
        publishedAt = now
    }

    func clear() {
        guard latestSnapshot != nil || publishedSnapshot != nil else { return }
        latestSnapshot = nil
        publishedSnapshot = nil
        publishedAt = 0
        updateCommandAvailability(nil)
        infoCenter.nowPlayingInfo = nil
    }

    private func updateCommandAvailability(_ snapshot: Snapshot?) {
        let hasTrack = snapshot != nil
        commandCenter.playCommand.isEnabled = hasTrack
        commandCenter.pauseCommand.isEnabled = hasTrack
        commandCenter.togglePlayPauseCommand.isEnabled = hasTrack
        commandCenter.previousTrackCommand.isEnabled = snapshot?.canPlayPrevious == true
        commandCenter.nextTrackCommand.isEnabled = snapshot?.canPlayNext == true
        commandCenter.changePlaybackPositionCommand.isEnabled = (snapshot?.duration ?? 0) > 0
    }

    private func register(_ remoteCommand: MPRemoteCommand, action: Command) {
        let target = remoteCommand.addTarget(handler: Self.handler(action: action, owner: self))
        registrations.append((remoteCommand, target))
    }

    private func perform(_ command: Command) {
        guard let state = latestSnapshot else { return }
        switch command {
        case .previous where !state.canPlayPrevious, .next where !state.canPlayNext:
            return
        case let .seek(position):
            guard state.duration > 0 else { return }
            publishedSnapshot = nil
            handleCommand(.seek(min(state.duration, max(0, position))))
        default:
            handleCommand(command)
        }
    }

    // MediaPlayer does not promise a callback executor. These Sendable closures are
    // created outside MainActor isolation and pass only command values to the actor.
    private nonisolated static func handler(
        action: Command,
        owner: NowPlayingService
    ) -> @Sendable (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        { [weak owner] _ in
            enqueue(action, owner: owner)
        }
    }

    private nonisolated static func seekHandler(
        owner: NowPlayingService
    ) -> @Sendable (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        { [weak owner] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent,
                  event.positionTime.isFinite else { return .commandFailed }
            return enqueue(.seek(event.positionTime), owner: owner)
        }
    }

    private nonisolated static func enqueue(
        _ command: Command,
        owner: NowPlayingService?
    ) -> MPRemoteCommandHandlerStatus {
        guard let owner else { return .noActionableNowPlayingItem }
        Task { @MainActor [weak owner] in
            owner?.perform(command)
        }
        // The request is accepted here; its current availability is rechecked on MainActor.
        return .success
    }
}
