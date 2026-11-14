import AVFoundation
import RadioNoiseAssets
import RadioNoiseKit

/// The pointer stays alive through the source node's strong render-block capture.
/// RadioNoiseKit supports one control writer and one render reader; no mutable Swift
/// state is shared with the audio thread and the callback does not allocate or lock.
private final class NoiseRenderContext: @unchecked Sendable {
  let noise: OpaquePointer?
  let sample: OpaquePointer?

  init(sampleRate: Double, seed: UInt64, parameters: RadioNoiseParameters,
    material: DemoNoiseMaterial) throws {
    switch material {
    case .recording12:
      let recording = try RadioNoiseAssets.loadReference12(sampleRate: sampleRate, balanced: true)
      guard let player = recording.samples.withUnsafeBufferPointer({
        RadioSampleCreate(sampleRate, $0.baseAddress, UInt64($0.count), seed)
      }) else { throw DemoAudioError.generatorUnavailable }
      sample = player
      noise = nil
    case .procedural:
      guard let generator = RadioNoiseCreate(sampleRate, 2, seed) else {
        throw DemoAudioError.generatorUnavailable
      }
      noise = generator
      sample = nil
      RadioNoiseSetParameters(generator, parameters)
    }
  }

  deinit {
    RadioNoiseDestroy(noise)
    RadioSampleDestroy(sample)
  }
}

@MainActor
final class NoiseEngine {
  let id = UUID()
  let engine = AVAudioEngine()
  let sampleRate: Double
  private var source: AVAudioSourceNode?
  private var context: NoiseRenderContext?
  private var musicPlayer: AVAudioPlayerNode?
  private var musicFile: AVAudioFile?
  private var mixUnit: AVAudioUnit?
  private var mixImplementation: NoiseMixAudioUnit?

  init(seed: UInt64, parameters: RadioNoiseParameters,
    material: DemoNoiseMaterial = .recording12, musicMode: Bool = false) throws {
    let outputRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
    sampleRate = outputRate > 0 ? outputRate : 48_000
    guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
      throw DemoAudioError.formatUnavailable
    }
    if musicMode { return }
    let context = try NoiseRenderContext(sampleRate: sampleRate, seed: seed,
      parameters: parameters, material: material)
    let source = AVAudioSourceNode(format: format) {
      [context] isSilence, _, frameCount, audioBufferList in
      let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
      guard buffers.count == 2,
        let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
        let right = buffers[1].mData?.assumingMemoryBound(to: Float.self)
      else {
        for buffer in buffers {
          buffer.mData?.initializeMemory(
            as: UInt8.self, repeating: 0, count: Int(buffer.mDataByteSize))
        }
        isSilence.pointee = true
        return noErr
      }
      if let sample = context.sample {
        RadioSampleRender(sample, left, frameCount)
        right.update(from: left, count: Int(frameCount))
      } else {
        RadioNoiseRender(context.noise, left, right, frameCount)
      }
      isSilence.pointee = false
      return noErr
    }
    self.context = context
    self.source = source
    engine.attach(source)
    engine.connect(source, to: engine.mainMixerNode, format: format)
    if material == .recording12 { engine.mainMixerNode.outputVolume = parameters.masterLevel }
  }

  static func music(
    url: URL, seed: UInt64, parameters: RadioNoiseParameters, intensity: Int32,
    backgroundIntensity: Int32,
    monitorGain: Float, material: DemoNoiseMaterial = .recording12,
    onFinished: @escaping @MainActor @Sendable () -> Void
  ) async throws -> NoiseEngine {
    let result = try NoiseEngine(seed: seed, parameters: parameters, musicMode: true)
    let file = try AVAudioFile(forReading: url)
    guard file.length > 0, (1...2).contains(file.processingFormat.channelCount),
      let format = AVAudioFormat(standardFormatWithSampleRate: result.sampleRate, channels: 2)
    else { throw DemoAudioError.formatUnavailable }
    let unit = try await NoiseMixAudioUnit.make()
    try Task.checkCancellation()
    guard let implementation = unit.auAudioUnit as? NoiseMixAudioUnit else {
      throw DemoAudioError.generatorUnavailable
    }
    implementation.configure(seed: seed, parameters: parameters, intensity: intensity,
      backgroundIntensity: backgroundIntensity,
      material: material)
    let player = AVAudioPlayerNode()
    result.engine.attach(player)
    result.engine.attach(unit)
    // The mixer converts mono and source sample rates before the stereo effect.
    let converter = AVAudioMixerNode()
    result.engine.attach(converter)
    result.engine.connect(player, to: converter, format: file.processingFormat)
    result.engine.connect(converter, to: unit, format: format)
    result.engine.connect(unit, to: result.engine.mainMixerNode, format: format)
    result.engine.mainMixerNode.outputVolume = monitorGain
    result.musicPlayer = player
    result.musicFile = file
    result.mixUnit = unit
    result.mixImplementation = implementation
    player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { _ in
      Task { @MainActor in onFinished() }
    }
    return result
  }

  func start() throws {
    engine.prepare()
    do {
      try engine.start()
      guard engine.isRunning else { throw DemoAudioError.generatorUnavailable }
      musicPlayer?.play()
    } catch {
      stop()
      throw error
    }
  }

  func setParameters(_ parameters: RadioNoiseParameters) {
    if let context {
      if context.sample != nil { engine.mainMixerNode.outputVolume = parameters.masterLevel }
      else { RadioNoiseSetParameters(context.noise, parameters) }
    }
    mixImplementation?.setParameters(parameters)
  }

  func setIntensity(_ intensity: Int32, backgroundIntensity: Int32) {
    mixImplementation?.setIntensity(intensity, backgroundIntensity: backgroundIntensity)
  }

  func setMonitorGain(_ gain: Float) { engine.mainMixerNode.outputVolume = gain }

  func stop() {
    musicPlayer?.stop()
    engine.stop()
    if let source { engine.detach(source) }
    source = nil
    context = nil
    musicPlayer = nil
    musicFile = nil
    mixImplementation = nil
    mixUnit = nil
  }

  deinit { engine.stop() }
}
