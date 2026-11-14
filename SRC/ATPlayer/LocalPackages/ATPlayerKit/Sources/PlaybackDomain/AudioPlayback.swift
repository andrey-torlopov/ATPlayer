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

@MainActor
public protocol AudioPlaying: AnyObject {
    var state: AudioPlaybackState { get }
    var onTrackFinished: (() -> Void)? { get set }
    func loadAndPlay(url: URL) async throws
    @discardableResult func play() -> Task<Void, Error>?
    func pauseByUser()
    func pause()
    func stop()
    func seek(to time: TimeInterval)
    /// Repairs published state after the system stops the audio output.
    func reconcilePlaybackState()
}
