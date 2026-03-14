import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioPlaybackService: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var visualizer: [CGFloat] = Array(repeating: 0.1, count: 24)

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let equalizer = AVAudioUnitEQ(numberOfBands: 10)
    private var currentFile: AVAudioFile?
    private var playbackOffset: TimeInterval = 0
    private var scheduledAt: Date?
    private var progressTimer: Timer?
    private var meterTimer: Timer?

    let bands: [Float] = [60, 170, 310, 600, 1000, 3000, 6000, 12000, 14000, 16000]
    @Published var preamp: Float = 0 {
        didSet { equalizer.globalGain = preamp }
    }
    @Published var gains: [Float] = Array(repeating: 0, count: 10) {
        didSet { applyGains() }
    }

    init() {
        configureAudioSession()
        configureEngine()
        startMeters()
    }

    deinit {
        progressTimer?.invalidate()
        meterTimer?.invalidate()
    }

    func loadAndPlay(url: URL) throws {
        stop()
        let file = try AVAudioFile(forReading: url)
        currentFile = file
        duration = TimeInterval(file.length) / file.processingFormat.sampleRate
        playbackOffset = 0
        scheduleCurrentFile(from: playbackOffset)
        playerNode.play()
        scheduledAt = .now
        isPlaying = true
        startProgressUpdates()
    }

    func play() {
        guard let _ = currentFile else { return }
        guard !isPlaying else { return }
        scheduleCurrentFile(from: playbackOffset)
        playerNode.play()
        scheduledAt = .now
        isPlaying = true
        startProgressUpdates()
    }

    func pause() {
        guard isPlaying else { return }
        updateProgressValue()
        playerNode.stop()
        isPlaying = false
        progressTimer?.invalidate()
    }

    func stop() {
        playerNode.stop()
        progressTimer?.invalidate()
        playbackOffset = 0
        currentTime = 0
        scheduledAt = nil
        isPlaying = false
    }

    private func scheduleCurrentFile(from offset: TimeInterval) {
        guard let file = currentFile else { return }
        let sampleRate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(offset * sampleRate)
        let remainingFrames = AVAudioFrameCount(max(0, file.length - startFrame))
        guard remainingFrames > 0 else {
            stop()
            return
        }

        playerNode.stop()
        playerNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: remainingFrames,
            at: nil
        ) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.stop()
            }
        }
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

        mainMixer.installTap(onBus: 0, bufferSize: 1024, format: mainMixer.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            guard let self else { return }
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
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { [weak self] _ in
            guard let self else { return }
            if !self.isPlaying {
                self.visualizer = self.visualizer.map { max(0.05, $0 * 0.9) }
            }
        }
    }

    private func applyGains() {
        for (index, value) in gains.enumerated() where index < equalizer.bands.count {
            equalizer.bands[index].gain = value
        }
    }

    private func startProgressUpdates() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.updateProgressValue()
        }
    }

    private func updateProgressValue() {
        guard isPlaying else { return }
        guard let scheduledAt else { return }
        let played = Date().timeIntervalSince(scheduledAt)
        currentTime = min(duration, playbackOffset + played)
        if currentTime >= duration {
            stop()
        }
    }
}
