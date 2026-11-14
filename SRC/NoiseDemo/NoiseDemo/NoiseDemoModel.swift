import AVFoundation
import Combine
import Foundation
import OSLog
import RadioNoiseKit

/// NotificationCenter registration/removal is thread-safe. The token is immutable;
/// main-actor owners release this object explicitly when a playback session ends.
private final class NotificationRegistration: @unchecked Sendable {
  private let token: NSObjectProtocol

  init(_ token: NSObjectProtocol) { self.token = token }
  deinit { NotificationCenter.default.removeObserver(token) }
}

enum DemoSource: String, CaseIterable, Identifiable {
  case generator
  case reference
  case mixture

  var id: Self { self }
  var title: String {
    switch self {
    case .generator: "Шум"
    case .reference: "Референс"
    case .mixture: "Музыка + шум"
    }
  }
}

enum DemoNoiseMaterial: String, CaseIterable, Identifiable {
  case recording12
  case procedural

  var id: Self { self }
  var title: String {
    switch self {
    case .recording12: "Запись 12"
    case .procedural: "Синтез"
    }
  }
}

struct NoiseControls {
  var gainDB: Double
  var intensity: Double
  var hiss: Double
  var crackle: Double
  var resonance: Double
  var chatter: Double
  var squelch: Double

  static var defaults: Self {
    Self(parameters: RadioNoiseParametersForPreset(RadioNoisePresetSquelch))
  }

  init(parameters: RadioNoiseParameters) {
    self.init(
      gainDB: 20 * log10(Double(parameters.masterLevel)),
      intensity: Double(parameters.character),
      hiss: Double(parameters.hissLevel),
      crackle: Double(parameters.crackleLevel),
      resonance: Double(parameters.resonanceLevel),
      chatter: Double(parameters.chatterLevel),
      squelch: Double(parameters.squelchLevel)
    )
  }

  private init(
    gainDB: Double, intensity: Double, hiss: Double, crackle: Double, resonance: Double,
    chatter: Double, squelch: Double
  ) {
    self.gainDB = gainDB
    self.intensity = intensity
    self.hiss = hiss
    self.crackle = crackle
    self.resonance = resonance
    self.chatter = chatter
    self.squelch = squelch
  }

  var parameters: RadioNoiseParameters {
    var result = RadioNoiseDefaultParameters()
    result.masterLevel = Float(pow(10, gainDB / 20))
    result.character = Float(intensity)
    result.hissLevel = Float(hiss)
    result.crackleLevel = Float(crackle)
    result.resonanceLevel = Float(resonance)
    result.chatterLevel = Float(chatter)
    result.squelchLevel = Float(squelch)
    return result
  }
}

@MainActor
final class NoiseDemoModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
  @Published var controls = NoiseControls.defaults {
    didSet { generator?.setParameters(controls.parameters) }
  }
  @Published var seedText = "140"
  @Published private(set) var noiseMaterial = DemoNoiseMaterial.recording12
  @Published private(set) var source = DemoSource.generator
  @Published private(set) var isPlaying = false
  @Published private(set) var isStarting = false
  @Published private(set) var musicName: String?
  @Published private(set) var musicDuration = 0.0
  @Published private(set) var overlapLevel = 10.0
  @Published private(set) var backgroundLevel = 7.0
  @Published var monitorGainDB = -12.0 {
    didSet { if source == .mixture { generator?.setMonitorGain(Float(pow(10, monitorGainDB / 20))) } }
  }
  @Published private(set) var referenceName: String?
  @Published private(set) var referenceDuration = 0.0
  @Published private(set) var sampleRate: Double?
  @Published private(set) var activeSeed: UInt64?
  @Published var referenceGainDB = -14.0 {
    didSet { referencePlayer?.volume = Float(pow(10, referenceGainDB / 20)) }
  }
  @Published var loopsReference = true {
    didSet { referencePlayer?.numberOfLoops = loopsReference ? -1 : 0 }
  }
  @Published var errorMessage: String?

  private var generator: NoiseEngine?
  private var referencePlayer: AVAudioPlayer?
  private var referenceURL: URL?
  private var hasSecurityScope = false
  private var musicURL: URL?
  private var musicHasSecurityScope = false
  private var startupTask: Task<Void, Never>?
  private var playbackGeneration: UInt64 = 0
  private var engineChangeObserver: NotificationRegistration?
  private var sessionObservers: [NotificationRegistration] = []
  private static let logger = Logger(subsystem: "dev.torlopov.noisedemo", category: "AudioSession")

  override init() {
    super.init()
    let center = NotificationCenter.default
    sessionObservers = [
      NotificationRegistration(
        center.addObserver(
          forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
          let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
          guard rawType == AVAudioSession.InterruptionType.began.rawValue else { return }
          Task { @MainActor [weak self] in
            guard let self, self.isPlaying || self.isStarting else { return }
            self.stop()
            self.errorMessage =
              "Воспроизведение прервано системой. Нажмите «Старт», чтобы продолжить."
          }
        }),
      NotificationRegistration(
        center.addObserver(
          forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
          let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
          guard let rawReason, let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason),
            [
              .newDeviceAvailable, .oldDeviceUnavailable, .noSuitableRouteForCategory,
              .routeConfigurationChange,
            ].contains(reason)
          else { return }
          Task { @MainActor [weak self] in
            guard let self, self.isPlaying || self.isStarting else { return }
            self.stop()
            self.errorMessage = "Аудиоустройство изменилось. Нажмите «Старт», чтобы продолжить."
          }
        }),
    ]
  }

  var parsedSeed: UInt64? {
    let text = seedText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
    return UInt64(text)
  }

  var canStart: Bool {
    switch source {
    case .generator: parsedSeed != nil
    case .reference: referencePlayer != nil
    case .mixture: parsedSeed != nil && musicURL != nil
    }
  }

  func selectSource(_ newSource: DemoSource) {
    guard newSource != source else { return }
    let resume = isPlaying || isStarting
    stop()
    source = newSource
    if resume { start() }
  }

  func selectNoiseMaterial(_ material: DemoNoiseMaterial) {
    guard material != noiseMaterial else { return }
    let resume = (isPlaying || isStarting) && source != .reference
    if source != .reference { stop() }
    noiseMaterial = material
    if resume { start() }
  }

  func setOverlapLevel(_ level: Double) {
    overlapLevel = level.isFinite ? max(0, min(10, level.rounded())) : 0
    backgroundLevel = min(backgroundLevel, overlapLevel)
    updateNoiseLevels()
  }

  func setBackgroundLevel(_ level: Double) {
    backgroundLevel = level.isFinite ? max(0, min(10, level.rounded())) : 0
    overlapLevel = max(overlapLevel, backgroundLevel)
    updateNoiseLevels()
  }

  private func updateNoiseLevels() {
    generator?.setIntensity(Int32(overlapLevel), backgroundIntensity: Int32(backgroundLevel))
  }

  func togglePlayback() {
    if isPlaying || isStarting { stop() } else { start() }
  }

  func start() {
    guard !isPlaying && !isStarting else { return }
    errorMessage = nil
    guard canStart else {
      switch source {
      case .generator: errorMessage = "Введите корректный seed."
      case .reference: errorMessage = "Сначала выберите WAV-референс."
      case .mixture: errorMessage = "Выберите музыку и введите корректный seed."
      }
      return
    }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default)
      try session.setActive(true)
    } catch {
      errorMessage = "Не удалось включить аудиосессию: \(error.localizedDescription)"
      return
    }
    playbackGeneration &+= 1
    let generation = playbackGeneration
    switch source {
    case .mixture:
      guard let url = musicURL, let seed = parsedSeed else {
        deactivateSession()
        return
      }
      isStarting = true
      let parameters = controls.parameters
      let material = noiseMaterial
      let level = Int32(overlapLevel.rounded())
      let background = Int32(backgroundLevel.rounded())
      let monitorGain = Float(pow(10, monitorGainDB / 20))
      startupTask = Task { @MainActor [weak self] in
        do {
          let engine = try await NoiseEngine.music(
            url: url, seed: seed, parameters: parameters, intensity: level,
            backgroundIntensity: background,
            monitorGain: monitorGain, material: material
          ) { [weak self] in
            guard let self, self.playbackGeneration == generation, self.source == .mixture else { return }
            self.stop()
          }
          guard let self, !Task.isCancelled, self.playbackGeneration == generation else {
            engine.stop()
            return
          }
          engine.setParameters(self.controls.parameters)
          engine.setIntensity(Int32(self.overlapLevel), backgroundIntensity: Int32(self.backgroundLevel))
          engine.setMonitorGain(Float(pow(10, self.monitorGainDB / 20)))
          try engine.start()
          self.generator = engine
          self.sampleRate = engine.sampleRate
          self.activeSeed = seed
          self.observeConfiguration(of: engine)
          self.isStarting = false
          self.isPlaying = true
          self.startupTask = nil
        } catch {
          guard let self, self.playbackGeneration == generation else { return }
          self.isStarting = false
          self.startupTask = nil
          self.deactivateSession()
          if !(error is CancellationError) { self.errorMessage = "Не удалось запустить музыку: \(error.localizedDescription)" }
        }
      }
    case .generator:
      guard let seed = parsedSeed else {
        errorMessage = "Seed должен быть целым числом от 0 до 18446744073709551615."
        return
      }
      do {
        let newGenerator = try NoiseEngine(seed: seed, parameters: controls.parameters,
          material: noiseMaterial)
        try newGenerator.start()
        generator = newGenerator
        sampleRate = newGenerator.sampleRate
        activeSeed = seed
        observeConfiguration(of: newGenerator)
        isPlaying = true
      } catch {
        deactivateSession()
        errorMessage = "Не удалось запустить аудиодвижок: \(error.localizedDescription)"
      }
    case .reference:
      guard let referencePlayer else {
        errorMessage = "Сначала выберите локальный WAV-файл."
        return
      }
      referencePlayer.currentTime = 0
      referencePlayer.volume = Float(pow(10, referenceGainDB / 20))
      referencePlayer.numberOfLoops = loopsReference ? -1 : 0
      isPlaying = referencePlayer.play()
      if !isPlaying {
        deactivateSession()
        errorMessage = "Не удалось воспроизвести WAV-файл."
      }
    }
  }

  private func observeConfiguration(of generator: NoiseEngine) {
    let generatorID = generator.id
    engineChangeObserver = NotificationRegistration(
      NotificationCenter.default.addObserver(
        forName: .AVAudioEngineConfigurationChange, object: generator.engine, queue: .main
      ) { [weak self] _ in
        Task { @MainActor [weak self] in
          guard let self, self.generator?.id == generatorID, self.isPlaying else { return }
          self.stop()
          self.errorMessage = "Аудиоустройство изменилось. Нажмите «Старт», чтобы продолжить."
        }
      })
  }

  func stop() {
    playbackGeneration &+= 1
    startupTask?.cancel()
    startupTask = nil
    isStarting = false
    engineChangeObserver = nil
    generator?.stop()
    generator = nil
    referencePlayer?.stop()
    referencePlayer?.currentTime = 0
    isPlaying = false
    deactivateSession()
  }

  private func deactivateSession() {
    do {
      try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      Self.logger.error("Audio stopped, but the system could not deactivate the session.")
    }
  }

  /// Every explicit start uses a new context, so seed + controls reproduce the same sequence.
  func restart() {
    stop()
    start()
  }

  func randomizeSeed() {
    seedText = String(UInt64.random(in: UInt64.min...UInt64.max))
    if isPlaying || isStarting, source != .reference { restart() }
  }

  func resetControls() {
    controls = .defaults
  }

  func applyPreset(_ preset: RadioNoisePreset) {
    // Keep the user's listening level when comparing noise characters.
    var updated = NoiseControls(parameters: RadioNoiseParametersForPreset(preset))
    updated.gainDB = controls.gainDB
    controls = updated
  }

  func importReference(_ url: URL) {
    let acquired = url.startAccessingSecurityScopedResource()
    do {
      let player = try AVAudioPlayer(contentsOf: url)
      guard player.duration.isFinite, player.duration > 0 else {
        throw DemoAudioError.emptyReference
      }
      // Do not interrupt the generator just because a reference is being selected.
      if source == .reference { stop() }
      referencePlayer?.stop()
      referencePlayer = nil
      if hasSecurityScope { referenceURL?.stopAccessingSecurityScopedResource() }
      referenceURL = url
      hasSecurityScope = acquired
      referencePlayer = player
      player.delegate = self
      player.volume = Float(pow(10, referenceGainDB / 20))
      player.numberOfLoops = loopsReference ? -1 : 0
      referenceName = url.lastPathComponent
      referenceDuration = player.duration
      errorMessage = nil
    } catch {
      if acquired { url.stopAccessingSecurityScopedResource() }
      errorMessage = "Не удалось открыть WAV-файл: \(error.localizedDescription)"
    }
  }

  func importMusic(_ url: URL) {
    let acquired = url.startAccessingSecurityScopedResource()
    do {
      let file = try AVAudioFile(forReading: url)
      guard file.length > 0, (1...2).contains(file.processingFormat.channelCount) else {
        throw DemoAudioError.emptyReference
      }
      if source == .mixture { stop() }
      if musicHasSecurityScope { musicURL?.stopAccessingSecurityScopedResource() }
      musicURL = url
      musicHasSecurityScope = acquired
      musicName = url.lastPathComponent
      musicDuration = Double(file.length) / file.processingFormat.sampleRate
      errorMessage = nil
    } catch {
      if acquired { url.stopAccessingSecurityScopedResource() }
      errorMessage = "Не удалось открыть музыку: \(error.localizedDescription)"
    }
  }

  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    let playerID = ObjectIdentifier(player)
    Task { @MainActor [weak self] in
      guard let self, let current = self.referencePlayer,
        ObjectIdentifier(current) == playerID, self.source == .reference,
        !current.isPlaying
      else { return }
      self.isPlaying = false
      self.deactivateSession()
      if !flag { self.errorMessage = "Воспроизведение WAV завершилось с ошибкой." }
    }
  }

  nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    let playerID = ObjectIdentifier(player)
    Task { @MainActor [weak self] in
      guard let self, let current = self.referencePlayer,
        ObjectIdentifier(current) == playerID, self.source == .reference
      else { return }
      self.stop()
      self.errorMessage = "Не удалось декодировать WAV-файл."
    }
  }

  deinit {
    startupTask?.cancel()
    referencePlayer?.stop()
    if musicHasSecurityScope { musicURL?.stopAccessingSecurityScopedResource() }
    if hasSecurityScope { referenceURL?.stopAccessingSecurityScopedResource() }
  }
}

enum DemoAudioError: LocalizedError {
  case formatUnavailable
  case generatorUnavailable
  case emptyReference

  var errorDescription: String? {
    switch self {
    case .formatUnavailable: "Аудиоформат устройства недоступен."
    case .generatorUnavailable: "Не удалось создать генератор."
    case .emptyReference: "Файл не содержит аудио."
    }
  }
}
