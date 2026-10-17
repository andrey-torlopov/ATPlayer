import Accelerate
import AVFoundation
import Combine
import Foundation
import OSLog

// AVAudioSession activation is synchronous on the supported iOS SDK. A Task
// created by the MainActor service would still run on the UI executor.
private nonisolated enum PlaybackAudioSession {
    private static let queue = DispatchQueue(label: "torlopov.atplayer.audio-session", qos: .userInitiated)
    private static let logger = Logger(subsystem: "torlopov.atplayer", category: "AudioPlayback")

    static func activate() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                dispatchPrecondition(condition: .onQueue(queue))
                let session = AVAudioSession.sharedInstance()
                var stage = "configureSession"
                do {
                    // Playback includes AirPlay/A2DP. Avoid reconfiguring an
                    // already active session when these settings match.
                    if session.category != .playback || session.mode != .default || !session.categoryOptions.isEmpty {
                        try session.setCategory(.playback, mode: .default, options: [])
                    }
                    stage = "activateSession"
                    try session.setActive(true)
                    continuation.resume()
                } catch {
                    let systemError = error as NSError
                    logger.error("Audio startup failed: stage=\(stage, privacy: .public), domain=\(systemError.domain, privacy: .public), code=\(systemError.code, privacy: .public)")
                    continuation.resume(throwing: AudioPlaybackService.PlaybackError.audioUnavailable)
                }
            }
        }
    }
}

@MainActor
final class AudioPlaybackService: ObservableObject {
    private enum AudioStartupStage: String {
        case startEngine
    }

    private static let logger = Logger(subsystem: "torlopov.atplayer", category: "AudioPlayback")

    nonisolated enum PlaybackError: LocalizedError {
        case invalidAudioFile
        case audioUnavailable

        var errorDescription: String? {
            switch self {
            case .invalidAudioFile:
                return "Аудиофайл пуст или имеет недопустимые параметры."
            case .audioUnavailable:
                return "Не удалось запустить аудиовыход. Повторите воспроизведение."
            }
        }
    }

    @Published private(set) var isPlaying = false
    @Published private(set) var isStarting = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var visualizer: [CGFloat] = Array(repeating: 0, count: 72)
    @Published private(set) var playbackError: String?

    var onTrackFinished: (() -> Void)?

    private var engine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var equalizer = AVAudioUnitEQ(numberOfBands: 10)
    private var currentFile: AVAudioFile?
    private var playbackOffset: TimeInterval = 0
    private var progressTimer: Timer?
    private var scheduleGeneration: UInt = 0
    private var pendingStart: Task<Void, Error>?
    private var spectrumAnalyzer: AudioSpectrumAnalyzer?
    private var spectrumGeneration: UInt = 0
    private var spectrumID = UUID()
    private var observers: [NSObjectProtocol] = []
    private var isInterrupted = false
    private var resumeAfterInterruption = false

    let bands: [Float] = [60, 170, 310, 600, 1000, 3000, 6000, 12000, 14000, 16000]
    @Published var preamp: Float = 0 {
        didSet {
            let value = Self.boundedGain(preamp)
            if preamp != value { preamp = value }
            equalizer.globalGain = value
            UserDefaults.standard.set(value, forKey: "eq_preamp")
        }
    }
    @Published var gains: [Float] = Array(repeating: 0, count: 10) {
        didSet {
            let values = bands.indices.map { Self.boundedGain(gains.indices.contains($0) ? gains[$0] : 0) }
            if gains != values { gains = values }
            applyGains()
            UserDefaults.standard.set(values, forKey: "eq_gains")
        }
    }

    init() {
        configureEngine()
        restoreEQSettings()
        observeAudioChanges()
    }

    deinit {
        pendingStart?.cancel()
        progressTimer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        engine.stop()
    }

    func loadAndPlay(url: URL) async throws {
        stop()
        try Task.checkCancellation()
        isInterrupted = false
        playbackError = nil
        let file = try AVAudioFile(forReading: url)
        let sampleRate = file.processingFormat.sampleRate
        guard file.length > 0, sampleRate.isFinite, sampleRate > 0,
              file.processingFormat.channelCount > 0 else {
            throw PlaybackError.invalidAudioFile
        }
        currentFile = file
        duration = TimeInterval(file.length) / sampleRate
        guard let start = scheduleAndPlay(from: 0) else { return }
        let generation = scheduleGeneration
        do {
            try await withTaskCancellationHandler {
                try await start.value
            } onCancel: {
                start.cancel()
            }
        } catch {
            // An older load must never stop a newer track or publish its error.
            guard scheduleGeneration == generation else { throw CancellationError() }
            stop()
            throw error
        }
    }

    func play() {
        guard currentFile != nil, !isPlaying, !isStarting else { return }
        // An interruption-ended notification is not guaranteed. A user request must
        // be able to reactivate the session; active interruptions still fail activation.
        isInterrupted = false
        resumeAfterInterruption = false
        scheduleAndPlay(from: playbackOffset >= duration ? 0 : playbackOffset)
    }

    func pause() {
        guard isPlaying || isStarting else { return }
        if isPlaying { updateProgressValue() }
        playbackOffset = currentTime
        cancelPlayback()
    }

    /// Unloads the file, including its duration. Pause preserves a resumable file.
    func stop() {
        cancelPlayback()
        currentFile = nil
        playbackOffset = 0
        currentTime = 0
        duration = 0
        resumeAfterInterruption = false
    }

    func seek(to time: TimeInterval) {
        guard currentFile != nil, time.isFinite else { return }
        let target = max(0, min(duration, time))
        let wasPlaying = isPlaying || isStarting
        cancelPlayback()
        playbackOffset = target
        currentTime = target
        guard wasPlaying else { return }
        if target >= duration {
            finishPlayback()
        } else {
            scheduleAndPlay(from: target)
        }
    }

    private func cancelPlayback() {
        // stop() itself invokes completion handlers: invalidate before stopping.
        scheduleGeneration &+= 1
        pendingStart?.cancel()
        pendingStart = nil
        isStarting = false
        isPlaying = false
        playerNode.stop()
        progressTimer?.invalidate()
        progressTimer = nil
        spectrumGeneration = spectrumAnalyzer?.reset() ?? 0
        visualizer = Array(repeating: 0, count: 72)
    }

    @discardableResult
    private func scheduleAndPlay(from offset: TimeInterval) -> Task<Void, Error>? {
        guard let file = currentFile else { return nil }
        cancelPlayback()
        let generation = scheduleGeneration
        isStarting = true
        let start = Task { @MainActor [weak self] in
            guard let self else { throw CancellationError() }
            do {
                try Task.checkCancellation()
                guard !self.isInterrupted else { throw PlaybackError.audioUnavailable }
                try await PlaybackAudioSession.activate()
                try Task.checkCancellation()
                guard self.scheduleGeneration == generation, self.currentFile === file,
                      !self.isInterrupted else { throw CancellationError() }
                if !self.engine.isRunning {
                    self.engine.prepare()
                    try self.audioStartupStep(.startEngine) { try self.engine.start() }
                }
                self.isStarting = false
                self.pendingStart = nil
                self.scheduleFile(file, from: offset, generation: generation)
            } catch {
                guard self.scheduleGeneration == generation else { throw CancellationError() }
                self.isStarting = false
                self.pendingStart = nil
                if !(error is CancellationError) { self.playbackError = error.localizedDescription }
                throw error
            }
        }
        pendingStart = start
        return start
    }

    private func scheduleFile(_ file: AVAudioFile, from offset: TimeInterval, generation: UInt) {
        let sampleRate = file.processingFormat.sampleRate
        var startFrame = min(file.length, max(0, AVAudioFramePosition(offset * sampleRate)))
        playbackOffset = TimeInterval(startFrame) / sampleRate
        currentTime = playbackOffset
        guard startFrame < file.length else {
            finishPlayback()
            return
        }

        // AVAudioFrameCount is UInt32; long recordings need contiguous segments.
        while startFrame < file.length {
            let count = AVAudioFrameCount(min(file.length - startFrame, AVAudioFramePosition(UInt32.max)))
            let isLastSegment = startFrame + AVAudioFramePosition(count) == file.length
            playerNode.scheduleSegment(
                file,
                startingFrame: startFrame,
                frameCount: count,
                at: nil,
                completionCallbackType: .dataPlayedBack
            ) { [weak self] _ in
                guard isLastSegment else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.scheduleGeneration == generation, self.isPlaying else { return }
                    self.finishPlayback()
                }
            }
            startFrame += AVAudioFramePosition(count)
        }
        playbackError = nil
        spectrumGeneration = spectrumAnalyzer?.reset(enabled: true) ?? 0
        playerNode.play()
        isPlaying = true
        startProgressUpdates()
    }

    private func finishPlayback() {
        cancelPlayback()
        playbackOffset = duration
        currentTime = duration
        onTrackFinished?()
    }

    private func audioStartupStep(_ stage: AudioStartupStage, operation: () throws -> Void) throws {
        do {
            try operation()
        } catch {
            let systemError = error as NSError
            Self.logger.error("Audio startup failed: stage=\(stage.rawValue, privacy: .public), domain=\(systemError.domain, privacy: .public), code=\(systemError.code, privacy: .public)")
            throw PlaybackError.audioUnavailable
        }
    }

    private func configureEngine() {
        engine.attach(playerNode)
        engine.attach(equalizer)
        for (index, frequency) in bands.enumerated() {
            let band = equalizer.bands[index]
            band.filterType = .parametric
            band.frequency = frequency
            band.bandwidth = 1
            band.bypass = false
        }
        let mixer = engine.mainMixerNode
        // File segments adapt sample rate/channels in AVAudioPlayerNode. Unlike
        // scheduleBuffer, scheduleSegment does not require the file's PCM format.
        engine.connect(playerNode, to: equalizer, format: nil)
        engine.connect(equalizer, to: mixer, format: nil)

        let id = UUID()
        spectrumID = id
        let analyzer = AudioSpectrumAnalyzer { [weak self] values, generation in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying, self.spectrumID == id,
                      self.spectrumGeneration == generation else { return }
                self.visualizer = zip(self.visualizer, values).map { previous, value in
                    previous * 0.25 + value * 0.75
                }
            }
        }
        spectrumAnalyzer = analyzer
        spectrumGeneration = analyzer.reset()
        mixer.installTap(onBus: 0, bufferSize: 4096, format: nil) { [analyzer] buffer, _ in
            analyzer.consume(buffer)
        }
        equalizer.globalGain = preamp
        applyGains()
    }

    private func observeAudioChanges() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
            let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
            Task { @MainActor [weak self] in
                guard let self, let type, let interruption = AVAudioSession.InterruptionType(rawValue: type) else { return }
                if interruption == .began {
                    self.resumeAfterInterruption = self.isPlaying || self.isStarting
                    self.pause()
                    self.isInterrupted = true
                } else {
                    self.isInterrupted = false
                    let shouldResume = self.resumeAfterInterruption && AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
                    self.resumeAfterInterruption = false
                    if shouldResume { self.play() }
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
            Task { @MainActor [weak self] in
                guard reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
                self?.resumeAfterInterruption = false
                self?.pause()
            }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] notification in
            let changedEngine = notification.object as? AVAudioEngine
            Task { @MainActor [weak self] in
                guard let self, changedEngine === self.engine, self.isPlaying, !self.engine.isRunning else { return }
                self.pause()
                self.play()
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pause()
                self.engine.stop()
                self.engine.mainMixerNode.removeTap(onBus: 0)
                self.engine = AVAudioEngine()
                self.playerNode = AVAudioPlayerNode()
                self.equalizer = AVAudioUnitEQ(numberOfBands: self.bands.count)
                self.configureEngine()
                self.isInterrupted = false
                self.resumeAfterInterruption = false
                self.playbackError = "Аудиосистема была перезапущена. Нажмите воспроизведение, чтобы продолжить."
            }
        })
    }

    private func restoreEQSettings() {
        preamp = UserDefaults.standard.float(forKey: "eq_preamp")
        if let savedGains = UserDefaults.standard.array(forKey: "eq_gains") as? [NSNumber] {
            gains = savedGains.map(\.floatValue)
        }
    }

    private static func boundedGain(_ value: Float) -> Float {
        value.isFinite ? max(-12, min(12, value)) : 0
    }

    private func applyGains() {
        for index in equalizer.bands.indices {
            equalizer.bands[index].gain = gains.indices.contains(index) ? Self.boundedGain(gains[index]) : 0
        }
    }

    private func startProgressUpdates() {
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateProgressValue() }
        }
        progressTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateProgressValue() {
        guard isPlaying, let renderTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: renderTime),
              playerTime.sampleRate > 0 else { return }
        let played = TimeInterval(max(0, playerTime.sampleTime)) / playerTime.sampleRate
        currentTime = min(duration, playbackOffset + played)
        // Only .dataPlayedBack completes a track; render time can precede audible output.
    }
}

/// PCM is copied before the tap returns. Only one FFT job can own the scratch buffers.
/// The lock protects the single-flight flag/generation; the render callback never waits.
private nonisolated final class AudioSpectrumAnalyzer: @unchecked Sendable {
    private static let frameCount = 4096
    private static let bandCount = 72
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "ATPlayer.audioSpectrum", qos: .userInitiated)
    private let completion: @Sendable ([CGFloat], UInt) -> Void
    private let setup: vDSP_DFT_Setup?
    private var window = [Float](repeating: 0, count: AudioSpectrumAnalyzer.frameCount)
    private var samples = (0..<2).map { _ in [Float](repeating: 0, count: AudioSpectrumAnalyzer.frameCount) }
    private var windowed = [Float](repeating: 0, count: AudioSpectrumAnalyzer.frameCount)
    private let zeros = [Float](repeating: 0, count: AudioSpectrumAnalyzer.frameCount)
    private var real = [Float](repeating: 0, count: AudioSpectrumAnalyzer.frameCount)
    private var imaginary = [Float](repeating: 0, count: AudioSpectrumAnalyzer.frameCount)
    private var power = [Float](repeating: 0, count: AudioSpectrumAnalyzer.frameCount / 2)
    private var isProcessing = false
    private var isEnabled = false
    private var generation: UInt = 0
    private var lastUpdate: TimeInterval = 0

    init(completion: @escaping @Sendable ([CGFloat], UInt) -> Void) {
        self.completion = completion
        setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(Self.frameCount), .FORWARD)
        vDSP_hann_window(&window, vDSP_Length(Self.frameCount), Int32(vDSP_HANN_NORM))
    }

    deinit {
        if let setup { vDSP_DFT_DestroySetup(setup) }
    }

    func reset(enabled: Bool = false) -> UInt {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        isEnabled = enabled
        lastUpdate = 0
        return generation
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0, lock.try() else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard isEnabled, !isProcessing, now - lastUpdate >= 0.07 else {
            lock.unlock()
            return
        }
        let channelCount = min(Int(buffer.format.channelCount), samples.count)
        guard channelCount > 0 else {
            lock.unlock()
            return
        }
        isProcessing = true
        lastUpdate = now
        let token = generation
        let count = min(Int(buffer.frameLength), Self.frameCount)
        let isInterleaved = buffer.format.isInterleaved
        let stride = Int(buffer.format.channelCount)
        for channel in 0..<channelCount {
            for frame in 0..<Self.frameCount {
                if frame < count {
                    let sample = isInterleaved
                        ? channels[0][frame * stride + channel]
                        : channels[channel][frame]
                    samples[channel][frame] = sample.isFinite ? sample : 0
                } else {
                    samples[channel][frame] = 0
                }
            }
        }
        let sampleRate = buffer.format.sampleRate
        lock.unlock()
        queue.async { [self] in
            let values = spectrum(sampleRate: sampleRate, channelCount: channelCount)
            lock.lock()
            isProcessing = false
            let isCurrent = generation == token
            lock.unlock()
            if isCurrent { completion(values, token) }
        }
    }

    private func spectrum(sampleRate: Double, channelCount: Int) -> [CGFloat] {
        guard let setup, sampleRate.isFinite, sampleRate > 40 else {
            return Array(repeating: 0, count: Self.bandCount)
        }
        for bin in power.indices { power[bin] = 0 }
        for channel in 0..<channelCount {
            vDSP_vmul(samples[channel], 1, window, 1, &windowed, 1, vDSP_Length(Self.frameCount))
            vDSP_DFT_Execute(setup, windowed, zeros, &real, &imaginary)
            for bin in power.indices {
                // Average channel power rather than summing PCM, which cancels antiphase stereo.
                power[bin] += (real[bin] * real[bin] + imaginary[bin] * imaginary[bin]) / Float(channelCount)
            }
        }
        let binWidth = sampleRate / Double(Self.frameCount)
        let upperFrequency = min(20_000, sampleRate / 2)
        let windowScale = 2 / window.reduce(0, +)
        return (0..<Self.bandCount).map { index in
            let lower = 20 * pow(upperFrequency / 20, Double(index) / Double(Self.bandCount))
            let upper = 20 * pow(upperFrequency / 20, Double(index + 1) / Double(Self.bandCount))
            let first = max(1, min(power.count - 1, Int((lower / binWidth).rounded())))
            let last = max(first, min(power.count - 1, Int((upper / binWidth).rounded())))
            let peakPower = power[first...last].max() ?? 0
            let amplitude = sqrt(peakPower) * windowScale
            let decibels = 20 * log10(max(amplitude, 0.000_001))
            return CGFloat(max(0, min(1, (decibels + 60) / 60)))
        }
    }
}
