import AppLocalization
import Combine
import Foundation

public enum PlaybackError: LocalizedError, Sendable {
    case invalidAudioFile
    case audioUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidAudioFile:
            return L10n.text("Аудиофайл пуст или имеет недопустимые параметры.")
        case .audioUnavailable:
            return L10n.text("Не удалось запустить аудиовыход. Повторите воспроизведение.")
        }
    }
}

/// The observable state shared by the playback adapter and presentation layer.
/// The audio adapter owns playback mutations; the UI may edit equalizer values.
@MainActor
public final class AudioPlaybackState: ObservableObject {
    @Published public var isPlaying = false
    @Published public var isStarting = false
    @Published public var advancesTrackTime = false
    @Published public var radioPhase: RadioPhase = .bypassed
    @Published public var radioTemporarilyUnavailable = false
    @Published public var currentTime: TimeInterval = 0
    @Published public var duration: TimeInterval = 0
    @Published public var visualizer: [CGFloat] = Array(repeating: 0, count: 72)
    @Published public var playbackError: String?

    public let bands: [Float] = [60, 170, 310, 600, 1000, 3000, 6000, 12000, 14000, 16000]
    public var onPreampChange: ((Float) -> Void)?
    public var onGainsChange: (([Float]) -> Void)?

    @Published public var preamp: Float = 0 {
        didSet {
            let value = Self.boundedGain(preamp)
            if preamp != value { preamp = value }
            onPreampChange?(value)
        }
    }
    @Published public var gains: [Float] = Array(repeating: 0, count: 10) {
        didSet {
            let values = bands.indices.map { Self.boundedGain(gains.indices.contains($0) ? gains[$0] : 0) }
            if gains != values { gains = values }
            onGainsChange?(values)
        }
    }

    public init() {}

    private static func boundedGain(_ value: Float) -> Float {
        value.isFinite ? max(-12, min(12, value)) : 0
    }
}

/// A file opened on the inactive source. Identity is scoped to one request; handles are single-use.
public struct AudioPreparedTrack: Equatable, Hashable, Sendable {
    public let id: UUID
    public let requestID: UUID

    public init(id: UUID = UUID(), requestID: UUID) {
        self.id = id
        self.requestID = requestID
    }
}

public enum AudioPreparationError: Error, Sendable {
    case unsupported
    case staleHandle
}

@MainActor
public protocol AudioPlaying: AnyObject {
    var state: AudioPlaybackState { get }
    var onTrackFinished: (() -> Void)? { get set }
    var supportsPreparedTransitions: Bool { get }
    var onTransportCancelled: (() -> Void)? { get set }
    /// Delivered after B reaches the output timeline and A has stopped reading.
    var onTrackStarted: ((AudioPreparedTrack) -> Void)? { get set }
    /// A cancelled or replaced prepared file is no longer used by either source.
    var onTrackReleased: ((AudioPreparedTrack) -> Void)? { get set }
    func applyRadioSettings(_ settings: RadioSettings)
    func prepareTrack(url: URL, requestID: UUID) async throws -> AudioPreparedTrack
    func scheduleReplacement(_ handle: AudioPreparedTrack, atEnd: Bool) throws
    func cancelPreparedTrack(_ handle: AudioPreparedTrack)
    func cancelReplacement()
    func loadAndPlay(url: URL) async throws
    @discardableResult func play() -> Task<Void, Error>?
    func pauseByUser()
    func pause()
    func stop()
    func seek(to time: TimeInterval)
    /// Repairs published state after the system stops the audio output.
    func reconcilePlaybackState()
}

/// Existing dry-only adapters remain valid and advertise their narrower capability.
public extension AudioPlaying {
    var supportsPreparedTransitions: Bool { false }
    var onTransportCancelled: (() -> Void)? { get { nil } set {} }
    var onTrackStarted: ((AudioPreparedTrack) -> Void)? { get { nil } set {} }
    var onTrackReleased: ((AudioPreparedTrack) -> Void)? { get { nil } set {} }
    func applyRadioSettings(_ settings: RadioSettings) {}
    func prepareTrack(url: URL, requestID: UUID) async throws -> AudioPreparedTrack {
        throw AudioPreparationError.unsupported
    }
    func scheduleReplacement(_ handle: AudioPreparedTrack, atEnd: Bool) throws {
        throw AudioPreparationError.unsupported
    }
    func cancelPreparedTrack(_ handle: AudioPreparedTrack) {}
    func cancelReplacement() {}
}
