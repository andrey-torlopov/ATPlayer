import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioPlaybackService: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var visualizer: [CGFloat] = Array(repeating: 0.1, count: 24)

    var onTrackFinished: (() -> Void)?

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let equalizer = AVAudioUnitEQ(numberOfBands: 10)
    private var currentFile: AVAudioFile?
    private var playbackOffset: TimeInterval = 0
    private var scheduledAt: Date?
    private var progressTimer: Timer?
    private var meterTimer: Timer?
    private var scheduleGeneration: UInt = 0
    private var lastVisualizerUpdate: CFAbsoluteTime = 0

    let bands: [Float] = [60, 170, 310, 600, 1000, 3000, 6000, 12000, 14000, 16000]
    @Published var preamp: Float = 0 {
        didSet {
            equalizer.globalGain = preamp
            UserDefaults.standard.set(preamp, forKey: "eq_preamp")
        }
    }
    @Published var gains: [Float] = Array(repeating: 0, count: 10) {
        didSet {
            applyGains()
            UserDefaults.standard.set(gains, forKey: "eq_gains")
        }
    }

    init() {
        configureAudioSession()
        configureEngine()
        restoreEQSettings()
        startMeters()
    }

    deinit {
        progressTimer?.invalidate()
        meterTimer?.invalidate()
    }

    func loadAndPlay(url: URL) throws {
        invalidateSchedule()
        playerNode.stop()
        progressTimer?.invalidate()

        let file = try AVAudioFile(forReading: url)
        currentFile = file
        duration = TimeInterval(file.length) / file.processingFormat.sampleRate
        playbackOffset = 0
        currentTime = 0

        scheduleAndPlay(from: 0)
    }

    func play() {
        guard currentFile != nil else { return }
        guard !isPlaying else { return }
        scheduleAndPlay(from: playbackOffset)
    }

    func pause() {
        guard isPlaying else { return }
        updateProgressValue()
        playbackOffset = currentTime
        invalidateSchedule()
        playerNode.stop()
        isPlaying = false
        progressTimer?.invalidate()
    }

    func stop() {
        invalidateSchedule()
        playerNode.stop()
        progressTimer?.invalidate()
        playbackOffset = 0
        currentTime = 0
        scheduledAt = nil
        isPlaying = false
    }

    func seek(to time: TimeInterval) {
        guard currentFile != nil else { return }
        let clampedTime = max(0, min(duration, time))
        let wasPlaying = isPlaying

        invalidateSchedule()
        playerNode.stop()
        progressTimer?.invalidate()
        playbackOffset = clampedTime
        currentTime = clampedTime

        if wasPlaying {
            scheduleAndPlay(from: clampedTime)
        }
    }

    private func invalidateSchedule() {
        scheduleGeneration &+= 1
    }

    private func scheduleAndPlay(from offset: TimeInterval) {
        guard let file = currentFile else { return }
        let sampleRate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(offset * sampleRate)
        let remainingFrames = AVAudioFrameCount(max(0, file.length - startFrame))
        guard remainingFrames > 0 else {
            stop()
            onTrackFinished?()
            return
        }

        let generation = scheduleGeneration
        playerNode.stop()
        playerNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: remainingFrames,
            at: nil
        ) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.scheduleGeneration == generation else { return }
                self.stop()
                self.onTrackFinished?()
            }
        }
        playerNode.play()
        scheduledAt = .now
        isPlaying = true
        startProgressUpdates()
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error.localizedDescription)")
        }
    }

    private func configureEngine() {
        engine.attach(playerNode)
        engine.attach(equalizer)

        for (idx, frequency) in bands.enumerated() {
            let band = equalizer.bands[idx]
            band.filterType = .parametric
            band.frequency = frequency
            band.bandwidth = 1
            band.gain = 0
            band.bypass = false
        }

        let mainMixer = engine.mainMixerNode
        engine.connect(playerNode, to: equalizer, format: nil)
        engine.connect(equalizer, to: mainMixer, format: nil)

        mainMixer.installTap(onBus: 0, bufferSize: 4096, format: mainMixer.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            guard let self else { return }
            let now = CFAbsoluteTimeGetCurrent()
            guard now - self.lastVisualizerUpdate >= 0.07 else { return }
            self.lastVisualizerUpdate = now
            let level = self.calculateLevel(buffer: buffer)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateVisualizer(with: level)
            }
        }

        do {
            try engine.start()
        } catch {
            print("Audio engine error: \(error.localizedDescription)")
        }
    }

    private func calculateLevel(buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }

        let values = UnsafeBufferPointer(start: channelData[0], count: frames)
        let rms = sqrt(values.reduce(0) { $0 + $1 * $1 } / Float(frames))
        let db = 20 * log10(max(rms, 0.000_01))
        let normalized = max(0, min(1, (db + 60) / 60))
        return CGFloat(normalized)
    }

    private func updateVisualizer(with level: CGFloat) {
        visualizer = visualizer.map { previous in
            let randomPart = CGFloat.random(in: 0.1...1.0)
            let next = (level * randomPart * 0.85) + (previous * 0.15)
            return max(0.05, min(1, next))
        }
    }

    private func startMeters() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.isPlaying {
                    self.visualizer = self.visualizer.map { max(0.05, $0 * 0.9) }
                }
            }
        }
    }

    private func restoreEQSettings() {
        let savedPreamp = UserDefaults.standard.float(forKey: "eq_preamp")
        preamp = savedPreamp
        equalizer.globalGain = savedPreamp

        if let savedGains = UserDefaults.standard.array(forKey: "eq_gains") as? [Float],
           savedGains.count == 10 {
            gains = savedGains
            applyGains()
        }
    }

    private func applyGains() {
        for (index, value) in gains.enumerated() where index < equalizer.bands.count {
            equalizer.bands[index].gain = value
        }
    }

    private func startProgressUpdates() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateProgressValue()
            }
        }
    }

    private func updateProgressValue() {
        guard isPlaying else { return }
        guard let scheduledAt else { return }
        let played = Date().timeIntervalSince(scheduledAt)
        currentTime = min(duration, playbackOffset + played)
        if currentTime >= duration {
            stop()
            onTrackFinished?()
        }
    }
}
