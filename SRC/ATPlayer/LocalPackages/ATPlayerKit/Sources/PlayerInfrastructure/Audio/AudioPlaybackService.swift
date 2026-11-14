import AppLocalization
import Accelerate
import AVFoundation
import Combine
import Foundation
import OSLog
import PlaybackDomain

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
                    continuation.resume(throwing: PlaybackError.audioUnavailable)
                }
            }
        }
    }
}

@MainActor
public final class AudioPlaybackService: AudioPlaying {
    private enum AudioStartupStage: String {
        case startEngine
    }

    private static let logger = Logger(subsystem: "torlopov.atplayer", category: "AudioPlayback")
    private static let renderClockStartupTimeout: TimeInterval = 2

    public let state = AudioPlaybackState()
    public var onTrackFinished: (() -> Void)?
    public var onTrackStarted: ((AudioPreparedTrack) -> Void)?
    public var onTrackReleased: ((AudioPreparedTrack) -> Void)?
    public var onTransportCancelled: (() -> Void)?
    public var supportsPreparedTransitions: Bool { true }

    private var isPlaying: Bool {
        get { state.isPlaying }
        set { state.isPlaying = newValue }
    }
    private var isStarting: Bool {
        get { state.isStarting }
        set { state.isStarting = newValue }
    }
    private var currentTime: TimeInterval {
        get { state.currentTime }
        set { state.currentTime = newValue }
    }
    private var duration: TimeInterval {
        get { state.duration }
        set { state.duration = newValue }
    }
    private var visualizer: [CGFloat] {
        get { state.visualizer }
        set { state.visualizer = newValue }
    }
    private var playbackError: String? {
        get { state.playbackError }
        set { state.playbackError = newValue }
    }
    private var preamp: Float {
        get { state.preamp }
        set { state.preamp = newValue }
    }
    private var gains: [Float] {
        get { state.gains }
        set { state.gains = newValue }
    }
    private var bands: [Float] { state.bands }

    private var engine: AVAudioEngine
    private var playerNode: AVAudioPlayerNode
    private var standbyNode = AVAudioPlayerNode()
    private var musicMixer = AVAudioMixerNode()
    private var activeGateNode: AVAudioUnit?
    private var standbyGateNode: AVAudioUnit?
    private var radioNode: AVAudioUnit?
    private var radioUnit: RadioAudioUnit? { radioNode?.auAudioUnit as? RadioAudioUnit }
    private var activeGate: RadioAudioUnit? { activeGateNode?.auAudioUnit as? RadioAudioUnit }
    private var standbyGate: RadioAudioUnit? { standbyGateNode?.auAudioUnit as? RadioAudioUnit }
    private var radioSettings = RadioSettings()
    private var radioGraphTask: Task<Void, Never>?
    private var coordinator = PreparedPlaybackCoordinator()
    private struct PreparedFile {
        let handle: AudioPreparedTrack
        let file: AVAudioFile
        let playbackID: UUID
    }
    private var prepared: PreparedFile?
    private var activeHandle: AudioPreparedTrack?
    private var activePlaybackID = UUID()
    private var activeStartFrame: Int64?
    private var preparationRevision: UInt = 0
    private var isRebuildingGraph = false
    private let notificationCenter: NotificationCenter
    private var equalizer = AVAudioUnitEQ(numberOfBands: 10)
    private var currentFile: AVAudioFile?
    private var playbackOffset: TimeInterval = 0
    private var progressTimer: Timer?
    private let progressUpdateInterval: TimeInterval
    private var scheduleGeneration: UInt = 0
    private var pendingStart: Task<Void, Error>?
    private var spectrumAnalyzer: AudioSpectrumAnalyzer?
    private var spectrumGeneration: UInt = 0
    private var spectrumID = UUID()
    private var observers: [NSObjectProtocol] = []
    private var isInterrupted = false
    private var resumeAfterInterruption = false
    private var resumeAfterOutputStop = false

    public func applyRadioSettings(_ settings: RadioSettings) {
        // Commit an already audible prepared source without restarting it.
        reconcilePlaybackState()
        let previous = radioSettings
        radioSettings = settings
        radioUnit?.apply(effectIntensity: settings.effectIntensity, backgroundIntensity: settings.backgroundIntensity)
        if state.radioTemporarilyUnavailable, !settings.isBypassed, previous != settings {
            radioGraphTask = nil
            Task { @MainActor [weak self] in await self?.ensureRadioGraph() }
        }
        if !isPlaying { state.radioPhase = .bypassed }
    }

    public func prepareTrack(url: URL, requestID: UUID) async throws -> AudioPreparedTrack {
        preparationRevision &+= 1
        let revision = preparationRevision
        await ensureRadioGraph()
        try Task.checkCancellation()
        guard revision == preparationRevision else { throw CancellationError() }
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard file.length > 0, format.sampleRate.isFinite, format.sampleRate > 0,
              format.channelCount > 0 else { throw PlaybackError.invalidAudioFile }
        cancelReplacement()
        let handle = AudioPreparedTrack(requestID: requestID)
        prepared = PreparedFile(handle: handle, file: file, playbackID: UUID())
        return handle
    }

    public func scheduleReplacement(_ handle: AudioPreparedTrack, atEnd: Bool) throws {
        guard let pending = prepared, pending.handle == handle, coordinator.plan == nil else {
            throw AudioPreparationError.staleHandle
        }
        guard engine.isRunning, !isInterrupted else { throw PlaybackError.audioUnavailable }
        updateProgressValue()
        let rate = engineSampleRate
        // The source decoder is prepared before selecting a boundary. Two output
        // buffers give AVAudioPlayerNode a finite scheduling lead, not a UI timer.
        standbyNode.stop()
        scheduleSegments(pending.file, on: standbyNode, startingFrame: 0,
                         generation: scheduleGeneration, playbackID: pending.playbackID)
        standbyNode.prepare(withFrameCount: 4096)
        let now = renderedSampleTime
        let lead = activeGate == nil ? 0 : Int64((max(0.005, AVAudioSession.sharedInstance().ioBufferDuration * 2) * rate).rounded(.up))
        let earliest = now + lead
        let remaining = max(0, duration - playbackOffset)
        let outgoingEnd: Int64? = (atEnd || (duration > 0 && currentTime >= duration))
            ? activeStartFrame.map { $0 + Int64((remaining * rate).rounded()) } ?? now
            : nil
        let plan = coordinator.makePlan(
            handle: handle, playbackID: pending.playbackID,
            earliestStart: earliest, sampleRate: rate, outgoingEnd: outgoingEnd)
        activeGate?.setSourceGate(closeSampleTime: plan.startFrame)
        if activeGate == nil { playerNode.stop() }
        standbyGate?.setSourceGate(closeSampleTime: nil)
        radioUnit?.setTransport(active: true)
        standbyNode.play(at: AVAudioTime(sampleTime: plan.startFrame, atRate: rate))
        isPlaying = true
        isStarting = false
        startProgressUpdates()
        observeReplacement()
    }

    public func cancelPreparedTrack(_ handle: AudioPreparedTrack) {
        guard prepared?.handle == handle else { return }
        cancelReplacement()
    }

    public func cancelReplacement() {
        // If B is already audible it is the active track, not a cancellable preload.
        observeReplacement()
        guard prepared != nil || coordinator.plan != nil else { return }
        _ = coordinator.cancel()
        activeGate?.setSourceGate(closeSampleTime: nil)
        discardPrepared()
        state.radioPhase = isPlaying && radioSettings.isEffectActive ? .receiving : .bypassed
    }

    private func discardPrepared() {
        guard let pending = prepared else { return }
        prepared = nil
        standbyNode.stop()
        standbyGate?.setSourceGate(closeSampleTime: nil)
        onTrackReleased?(pending.handle)
    }

    private var engineSampleRate: Double {
        let rate = radioUnit?.renderSampleRate ?? musicMixer.outputFormat(forBus: 0).sampleRate
        return rate.isFinite && rate > 0 ? rate : 48_000
    }

    private var renderedSampleTime: Int64 {
        if let radioUnit { return radioUnit.renderedSampleTime }
        guard let time = engine.outputNode.lastRenderTime, time.sampleRate > 0 else { return 0 }
        return Int64(Double(time.sampleTime) * engineSampleRate / time.sampleRate)
    }

    private var audibleSampleTime: Int64 {
        let latency = max(0, radioNode?.outputPresentationLatency ?? playerNode.outputPresentationLatency)
            + (radioUnit?.latency ?? 0)
        return renderedSampleTime - Int64((latency * engineSampleRate).rounded(.up))
    }

    private func observeReplacement() {
        guard isPlaying else { return }
        if let plan = coordinator.plan, audibleSampleTime >= plan.startFrame {
            commitReplacement(plan)
        }
        state.radioPhase = radioUnit?.radioPhase ?? .bypassed
    }

    private func commitReplacement(_ plan: PreparedPlaybackCoordinator.Plan) {
        guard coordinator.plan?.generation == plan.generation,
              let pending = prepared, pending.handle == plan.handle else { return }
        prepared = nil
        _ = coordinator.cancel()
        // The source gate has already closed A at the sample boundary. Stop its
        // decoder before the feature receives a resource-release or commit event.
        playerNode.stop()
        let released = activeHandle
        let previousNode = playerNode
        playerNode = standbyNode
        standbyNode = previousNode
        let previousGate = activeGateNode
        activeGateNode = standbyGateNode
        standbyGateNode = previousGate
        standbyGate?.setSourceGate(closeSampleTime: nil)
        currentFile = pending.file
        activeHandle = pending.handle
        activePlaybackID = pending.playbackID
        activeStartFrame = plan.startFrame
        playbackOffset = 0
        duration = Double(pending.file.length) / pending.file.processingFormat.sampleRate
        currentTime = min(duration, max(0, Double(audibleSampleTime - plan.startFrame) / plan.sampleRate))
        state.advancesTrackTime = true
        radioUnit?.resetReception(remainingDuration: max(0, duration - currentTime))
        state.radioPhase = radioSettings.isEffectActive ? .receiving : .bypassed
        if let released { onTrackReleased?(released) }
        onTrackStarted?(pending.handle)
    }

    private func scheduleSegments(_ file: AVAudioFile, on node: AVAudioPlayerNode,
                                  startingFrame: AVAudioFramePosition, generation: UInt,
                                  playbackID: UUID) {
        var frame = startingFrame
        while frame < file.length {
            let count = AVAudioFrameCount(min(file.length - frame, AVAudioFramePosition(UInt32.max)))
            let isLast = frame + AVAudioFramePosition(count) == file.length
            node.scheduleSegment(file, startingFrame: frame, frameCount: count, at: nil,
                                 completionCallbackType: .dataPlayedBack) { [weak self] _ in
                guard isLast else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.scheduleGeneration == generation,
                          self.isPlaying, self.engine.isRunning, !self.isInterrupted else { return }
                    if let plan = self.coordinator.plan, plan.playbackID == playbackID {
                        // Very short B may finish before the presentation poll.
                        self.commitReplacement(plan)
                    }
                    guard self.activePlaybackID == playbackID else { return }
                    // The coordinator, not A's EOF, owns a scheduled replacement.
                    guard self.coordinator.plan == nil else { return }
                    self.finishPlayback()
                }
            }
            frame += AVAudioFramePosition(count)
        }
    }

    private func ensureRadioGraph() async {
        if radioNode != nil { return }
        if let radioGraphTask { await radioGraphTask.value; return }
        let graphEngine = engine
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let unit = try await RadioAudioUnit.makeAVAudioUnit()
                let firstGate = try await RadioAudioUnit.makeSourceGate()
                let secondGate = try await RadioAudioUnit.makeSourceGate()
                try Task.checkCancellation()
                guard self.engine === graphEngine else { return }
                let wasRunning = graphEngine.isRunning
                self.isRebuildingGraph = true
                defer { self.isRebuildingGraph = false }
                if wasRunning { graphEngine.pause() }
                let format = self.musicMixer.outputFormat(forBus: 0)
                graphEngine.attach(unit)
                graphEngine.attach(firstGate)
                graphEngine.attach(secondGate)
                graphEngine.disconnectNodeOutput(self.playerNode)
                graphEngine.disconnectNodeOutput(self.standbyNode)
                graphEngine.disconnectNodeOutput(self.equalizer)
                graphEngine.connect(self.playerNode, to: firstGate, format: format)
                graphEngine.connect(firstGate, to: self.musicMixer, fromBus: 0, toBus: 0, format: format)
                graphEngine.connect(self.standbyNode, to: secondGate, format: format)
                graphEngine.connect(secondGate, to: self.musicMixer, fromBus: 0, toBus: 1, format: format)
                graphEngine.connect(self.equalizer, to: unit, format: format)
                graphEngine.connect(unit, to: graphEngine.mainMixerNode, format: format)
                self.radioNode = unit
                self.activeGateNode = firstGate
                self.standbyGateNode = secondGate
                self.radioUnit?.apply(effectIntensity: self.radioSettings.effectIntensity,
                                      backgroundIntensity: self.radioSettings.backgroundIntensity)
                self.radioUnit?.setTransport(active: self.isPlaying)
                self.state.radioTemporarilyUnavailable = false
                if wasRunning { graphEngine.prepare(); try graphEngine.start() }
            } catch {
                // Receiver processing is optional. Its failure must never mark
                // the user's file invalid or erase the saved radio preferences.
                guard self.engine === graphEngine else { return }
                self.state.radioTemporarilyUnavailable = true
                Self.logger.error("Radio processing unavailable; the session uses dry playback")
            }
        }
        radioGraphTask = task
        await task.value
    }

    public convenience init() {
        self.init(engine: AVAudioEngine(), playerNode: AVAudioPlayerNode(), notificationCenter: .default)
    }

    init(engine: AVAudioEngine, playerNode: AVAudioPlayerNode, notificationCenter: NotificationCenter,
         progressUpdateInterval: TimeInterval = 0.1) {
        self.progressUpdateInterval = max(0.01, progressUpdateInterval)
        self.engine = engine
        self.playerNode = playerNode
        self.notificationCenter = notificationCenter
        state.onPreampChange = { [weak self] value in
            self?.equalizer.globalGain = value
            UserDefaults.standard.set(value, forKey: "eq_preamp")
        }
        state.onGainsChange = { [weak self] values in
            self?.applyGains()
            UserDefaults.standard.set(values, forKey: "eq_gains")
        }
        configureEngine()
        restoreEQSettings()
        observeAudioChanges()
    }

    deinit {
        pendingStart?.cancel()
        radioGraphTask?.cancel()
        progressTimer?.invalidate()
        observers.forEach { notificationCenter.removeObserver($0) }
        engine.stop()
    }

    public func loadAndPlay(url: URL) async throws {
        stop()
        try Task.checkCancellation()
        isInterrupted = false
        playbackError = nil
        await ensureRadioGraph()
        try Task.checkCancellation()
        let file = try AVAudioFile(forReading: url)
        let sampleRate = file.processingFormat.sampleRate
        guard file.length > 0, sampleRate.isFinite, sampleRate > 0,
              file.processingFormat.channelCount > 0 else {
            throw PlaybackError.invalidAudioFile
        }
        currentFile = file
        activePlaybackID = UUID()
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

    @discardableResult
    public func play() -> Task<Void, Error>? {
        reconcilePlaybackState()
        guard currentFile != nil, !isPlaying, !isStarting else { return nil }
        // An interruption-ended notification is not guaranteed. A user request must
        // be able to reactivate the session; active interruptions still fail activation.
        isInterrupted = false
        resumeAfterInterruption = false
        resumeAfterOutputStop = false
        return scheduleAndPlay(from: playbackOffset >= duration ? 0 : playbackOffset)
    }

    public func pauseByUser() {
        // A remote Pause during an interruption must cancel automatic resume,
        // even when the player is already paused by the audio session.
        resumeAfterInterruption = false
        pause()
    }

    public func pause() {
        observeReplacement()
        onTransportCancelled?()
        resumeAfterOutputStop = false
        if isPlaying { updateProgressValue() }
        guard isPlaying || isStarting || prepared != nil else { return }
        playbackOffset = currentTime
        cancelPlayback()
    }

    public func reconcilePlaybackState() {
        observeReplacement()
        // A system stop can precede its notification. Never let a stale UI flag
        // reject an explicit Play or make Toggle pause an already stopped output.
        let replacementOwnsOutput = coordinator.plan != nil
        guard isPlaying, !isStarting, !isRebuildingGraph,
              !engine.isRunning || (!playerNode.isPlaying && !replacementOwnsOutput) else { return }
        Self.logger.notice("Reconciling playback after the audio output stopped")
        pause()
        // The timer may see a hardware stop before the corresponding notification.
        // Retain intent so that notification can still recover active playback.
        resumeAfterOutputStop = true
    }

    /// Unloads the file, including its duration. Pause preserves a resumable file.
    public func stop() {
        observeReplacement()
        onTransportCancelled?()
        cancelPlayback()
        if let handle = activeHandle { activeHandle = nil; onTrackReleased?(handle) }
        currentFile = nil
        playbackOffset = 0
        currentTime = 0
        duration = 0
        resumeAfterInterruption = false
        resumeAfterOutputStop = false
    }

    public func seek(to time: TimeInterval) {
        observeReplacement()
        onTransportCancelled?()
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
        state.advancesTrackTime = false
        radioUnit?.setTransport(active: false)
        state.radioPhase = .bypassed
        preparationRevision &+= 1
        discardPrepared()
        _ = coordinator.cancel()
        activeStartFrame = nil
        activeGate?.setSourceGate(closeSampleTime: nil)
        playerNode.stop()
        standbyNode.stop()
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
        activePlaybackID = UUID()
        isStarting = true
        // A headphone command can wake a paused app only briefly. Keep execution
        // through asynchronous session activation and the engine's actual start.
        let backgroundTask = PlaybackBackgroundTask(name: "Start audio playback")
        let start = Task { @MainActor [weak self] in
            defer { backgroundTask.finish() }
            guard let self else { throw CancellationError() }
            do {
                try Task.checkCancellation()
                guard !self.isInterrupted else { throw PlaybackError.audioUnavailable }
                await self.ensureRadioGraph()
                try Task.checkCancellation()
                try await PlaybackAudioSession.activate()
                try Task.checkCancellation()
                guard self.scheduleGeneration == generation, self.currentFile === file,
                      !self.isInterrupted else { throw CancellationError() }
                let previousClock = self.renderedSampleTime
                let startedEngine = !self.engine.isRunning
                if startedEngine {
                    self.engine.prepare()
                    try self.startEngineWithRadioFallback()
                }
                try await self.waitForRenderClock(generation: generation,
                                                  previousSampleTime: startedEngine ? previousClock : nil)
                try Task.checkCancellation()
                guard self.scheduleGeneration == generation, self.currentFile === file else {
                    throw CancellationError()
                }
                self.radioUnit?.apply(effectIntensity: self.radioSettings.effectIntensity,
                                      backgroundIntensity: self.radioSettings.backgroundIntensity)
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
        let startFrame = min(file.length, max(0, AVAudioFramePosition(offset * sampleRate)))
        playbackOffset = TimeInterval(startFrame) / sampleRate
        currentTime = playbackOffset
        guard startFrame < file.length else {
            finishPlayback()
            return
        }

        scheduleSegments(file, on: playerNode, startingFrame: startFrame,
                         generation: generation, playbackID: activePlaybackID)
        playbackError = nil
        spectrumGeneration = spectrumAnalyzer?.reset(enabled: true) ?? 0
        activeGate?.setSourceGate(closeSampleTime: nil)
        radioUnit?.resetReception(remainingDuration: max(0, duration - playbackOffset))
        radioUnit?.setTransport(active: true)
        let start = renderedSampleTime + Int64((max(0.005, AVAudioSession.sharedInstance().ioBufferDuration * 2) * engineSampleRate).rounded(.up))
        activeStartFrame = start
        playerNode.play(at: AVAudioTime(sampleTime: start, atRate: engineSampleRate))
        state.advancesTrackTime = true
        state.radioPhase = radioSettings.isEffectActive && !state.radioTemporarilyUnavailable ? .receiving : .bypassed
        resumeAfterOutputStop = false
        isPlaying = true
        startProgressUpdates()
    }

    private func finishPlayback() {
        cancelPlayback()
        playbackOffset = duration
        currentTime = duration
        onTrackFinished?()
    }

    private func waitForRenderClock(generation: UInt, previousSampleTime: Int64?) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + Self.renderClockStartupTimeout
        while true {
            try Task.checkCancellation()
            guard scheduleGeneration == generation else { throw CancellationError() }
            guard engine.isRunning else { throw PlaybackError.audioUnavailable }
            let sampleTime = renderedSampleTime
            if sampleTime != 0, previousSampleTime.map({ sampleTime != $0 }) ?? true { return }
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw PlaybackError.audioUnavailable }
            // Only startup readiness is polled, off the render thread. Once the
            // first callback establishes the HAL epoch, all sound uses sample times.
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    private func startEngineWithRadioFallback() throws {
        do {
            try engine.start()
        } catch {
            guard radioNode != nil else {
                throw PlaybackError.audioUnavailable
            }
            isRebuildingGraph = true
            defer { isRebuildingGraph = false }
            engine.stop()
            engine.disconnectNodeOutput(playerNode)
            engine.disconnectNodeOutput(standbyNode)
            engine.disconnectNodeOutput(equalizer)
            for node in [radioNode, activeGateNode, standbyGateNode].compactMap({ $0 }) {
                engine.detach(node)
            }
            radioNode = nil
            activeGateNode = nil
            standbyGateNode = nil
            engine.connect(playerNode, to: musicMixer, fromBus: 0, toBus: 0, format: nil)
            engine.connect(standbyNode, to: musicMixer, fromBus: 0, toBus: 1, format: nil)
            engine.connect(equalizer, to: engine.mainMixerNode, format: nil)
            state.radioTemporarilyUnavailable = true
            engine.prepare()
            try audioStartupStep(.startEngine) { try engine.start() }
        }
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
        engine.attach(standbyNode)
        engine.attach(musicMixer)
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
        engine.connect(playerNode, to: musicMixer, fromBus: 0, toBus: 0, format: nil)
        engine.connect(standbyNode, to: musicMixer, fromBus: 0, toBus: 1, format: nil)
        engine.connect(musicMixer, to: equalizer, format: nil)
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
        let center = notificationCenter
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
            let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
            // NotificationCenter delivers this observer on the main queue. Handle
            // it before returning, while the app still has execution time.
            MainActor.assumeIsolated {
                guard let self, let type, let interruption = AVAudioSession.InterruptionType(rawValue: type) else { return }
                if interruption == .began {
                    if !self.isInterrupted {
                        self.resumeAfterInterruption = self.isPlaying || self.isStarting || self.resumeAfterOutputStop
                    }
                    self.isInterrupted = true
                    self.pause()
                } else {
                    guard self.isInterrupted else { return }
                    self.isInterrupted = false
                    let shouldResume = self.resumeAfterInterruption && AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
                    self.resumeAfterInterruption = false
                    if shouldResume { self.play() }
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
            MainActor.assumeIsolated {
                guard reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
                self?.resumeAfterInterruption = false
                self?.pause()
            }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] notification in
            let changedEngine = notification.object as? AVAudioEngine
            MainActor.assumeIsolated {
                guard let self, !self.isRebuildingGraph, changedEngine === self.engine, self.isPlaying || self.resumeAfterOutputStop,
                      !self.isInterrupted, !self.engine.isRunning else { return }
                self.pause()
                self.play()
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pause()
                self.engine.stop()
                self.engine.mainMixerNode.removeTap(onBus: 0)
                self.engine = AVAudioEngine()
                self.playerNode = AVAudioPlayerNode()
                self.standbyNode = AVAudioPlayerNode()
                self.musicMixer = AVAudioMixerNode()
                self.radioGraphTask?.cancel()
                self.radioGraphTask = nil
                self.radioNode = nil
                self.activeGateNode = nil
                self.standbyGateNode = nil
                self.equalizer = AVAudioUnitEQ(numberOfBands: self.bands.count)
                self.configureEngine()
                self.isInterrupted = false
                self.resumeAfterInterruption = false
                self.playbackError = L10n.text("Аудиосистема была перезапущена. Нажмите воспроизведение, чтобы продолжить.")
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
        progressTimer?.invalidate()
        let timer = Timer(timeInterval: progressUpdateInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.observeReplacement()
                self?.reconcilePlaybackState()
                self?.updateProgressValue()
            }
        }
        progressTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateProgressValue() {
        guard isPlaying, let start = activeStartFrame else { return }
        let played = max(0, Double(audibleSampleTime - start) / engineSampleRate)
        currentTime = min(duration, playbackOffset + played)
        state.advancesTrackTime = true
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
