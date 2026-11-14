import AudioToolbox
import AVFoundation
import RadioNoiseAssets
import RadioNoiseKit
import Synchronization

/// Private host adapter. The event and noise model live in RadioNoiseKit;
/// this unit supplies the imported music and its pre-duck RMS.
final class NoiseMixAudioUnit: AUAudioUnit {
  private static let component = AudioComponentDescription(
    componentType: kAudioUnitType_Effect, componentSubType: 0x6e646d78,
    componentManufacturer: 0x4174506c, componentFlags: 0, componentFlagsMask: 0)
  private static let registration: Void = {
    AUAudioUnit.registerSubclass(NoiseMixAudioUnit.self, as: component,
      name: "Noise Demo: Absorption", version: 1)
  }()

  private struct RenderState {
    var noise: OpaquePointer?
    var sample: OpaquePointer?
    var interference: OpaquePointer?
    var left: UnsafeMutablePointer<Float>?
    var right: UnsafeMutablePointer<Float>?
    var capacity: AUAudioFrameCount = 0
    var rmsSquared: Float = 0
    var inputPower: Float = 0
    var referenceRMS: Float = 0
    var previousPhase = RadioInterferencePhaseIdle
    var quietFrames: UInt64 = 0
    var quietLimit: UInt64 = 1
    var rmsAlpha: Float = 0
    var inputPowerAlpha: Float = 0
  }

  /// Stable identity survives the host obtaining its render block before allocation.
  /// State is render-owned while running; control writes only while stopped.
  private final class Resources: @unchecked Sendable {
    let state: UnsafeMutablePointer<RenderState>
    let levels = Atomic<UInt32>(10 | (7 << 8))
    init() {
      state = .allocate(capacity: 1)
      state.initialize(to: RenderState())
    }
    deinit {
      state.deinitialize(count: 1)
      state.deallocate()
    }
  }

  private let resources = Resources()
  private var inputBus: AUAudioUnitBus!
  private var outputBus: AUAudioUnitBus!
  private var inputs: AUAudioUnitBusArray!
  private var outputs: AUAudioUnitBusArray!
  private var scratch: AVAudioPCMBuffer?
  private var seed: UInt64 = 140
  private var material = DemoNoiseMaterial.recording12
  private var parameters = RadioNoiseParametersForPreset(RadioNoisePresetSquelch)
  /// Only read during allocation, never by the render callback. Errors propagate
  /// to the host instead of silently substituting a different noise source.
  var reference12Loader: (Double) throws -> RadioNoiseSample = {
    try RadioNoiseAssets.loadReference12(sampleRate: $0, balanced: true)
  }

  override init(componentDescription: AudioComponentDescription,
    options: AudioComponentInstantiationOptions = []) throws {
    try super.init(componentDescription: componentDescription, options: options)
    guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2) else {
      throw DemoAudioError.formatUnavailable
    }
    inputBus = try AUAudioUnitBus(format: format)
    outputBus = try AUAudioUnitBus(format: format)
    inputBus.maximumChannelCount = 2
    outputBus.maximumChannelCount = 2
    inputs = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
    outputs = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
    maximumFramesToRender = 4_096
  }

  static func make() async throws -> AVAudioUnit {
    _ = registration
    return try await withCheckedThrowingContinuation { continuation in
      AVAudioUnit.instantiate(with: component, options: []) { unit, error in
        if let unit { continuation.resume(returning: unit) }
        else { continuation.resume(throwing: error ?? DemoAudioError.generatorUnavailable) }
      }
    }
  }

  func configure(seed: UInt64, parameters: RadioNoiseParameters, intensity: Int32,
    backgroundIntensity: Int32,
    material: DemoNoiseMaterial = .recording12) {
    precondition(!renderResourcesAllocated)
    self.seed = seed
    self.material = material
    setParameters(parameters)
    setIntensity(intensity, backgroundIntensity: backgroundIntensity)
  }

  func setParameters(_ parameters: RadioNoiseParameters) {
    var unitParameters = parameters
    unitParameters.masterLevel = 1
    self.parameters = unitParameters
    RadioNoiseSetParameters(resources.state.pointee.noise, unitParameters)
  }

  func setIntensity(_ intensity: Int32, backgroundIntensity: Int32) {
    let main = max(0, min(10, intensity))
    let background = max(0, min(main, backgroundIntensity))
    resources.levels.store(UInt32(main | (background << 8)), ordering: .relaxed)
  }

  override var inputBusses: AUAudioUnitBusArray { inputs }
  override var outputBusses: AUAudioUnitBusArray { outputs }
  override var canProcessInPlace: Bool { true }

  override func shouldChange(to format: AVAudioFormat, for bus: AUAudioUnitBus) -> Bool {
    !renderResourcesAllocated && format.commonFormat == .pcmFormatFloat32
      && !format.isInterleaved && format.channelCount == 2
      && (8_000...384_000).contains(format.sampleRate)
  }

  override func allocateRenderResources() throws {
    let format = outputBus.format
    guard inputBus.format == format,
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maximumFramesToRender)
    else { throw DemoAudioError.formatUnavailable }
    let noise: OpaquePointer?
    let sample: OpaquePointer?
    switch material {
    case .recording12:
      let recording = try reference12Loader(format.sampleRate)
      guard let player = recording.samples.withUnsafeBufferPointer({
        RadioSampleCreate(format.sampleRate, $0.baseAddress, UInt64($0.count), seed)
      }) else { throw DemoAudioError.generatorUnavailable }
      sample = player
      noise = nil
    case .procedural:
      guard let generator = RadioNoiseCreate(format.sampleRate, 2, seed) else {
        throw DemoAudioError.generatorUnavailable
      }
      noise = generator
      sample = nil
    }
    guard let interference = RadioInterferenceCreate(format.sampleRate, seed) else {
      RadioNoiseDestroy(noise)
      RadioSampleDestroy(sample)
      throw DemoAudioError.generatorUnavailable
    }
    clearResources()
    scratch = buffer
    let state = resources.state
    state.pointee.noise = noise
    state.pointee.sample = sample
    state.pointee.interference = interference
    state.pointee.left = buffer.floatChannelData?[0]
    state.pointee.right = buffer.floatChannelData?[1]
    state.pointee.capacity = maximumFramesToRender
    state.pointee.rmsAlpha = Float(1 - exp(-1 / format.sampleRate))
    state.pointee.inputPowerAlpha = Float(1 - exp(-1 / (format.sampleRate * 0.02)))
    state.pointee.quietLimit = UInt64(format.sampleRate * 0.5)
    RadioNoiseSetParameters(noise, parameters)
    if let sample { RadioInterferenceSetNoiseRMS(interference, RadioSampleRMS(sample)) }
    do { try super.allocateRenderResources() }
    catch { clearResources(); throw error }
  }

  override func deallocateRenderResources() {
    super.deallocateRenderResources()
    clearResources()
  }

  private func clearResources() {
    RadioNoiseDestroy(resources.state.pointee.noise)
    RadioSampleDestroy(resources.state.pointee.sample)
    RadioInterferenceDestroy(resources.state.pointee.interference)
    resources.state.pointee = RenderState()
    scratch = nil
  }

  deinit { clearResources() }

  override var internalRenderBlock: AUInternalRenderBlock {
    let resources = resources
    return { flags, timestamp, frames, _, output, _, pullInput in
      let state = resources.state
      guard state.pointee.noise != nil || state.pointee.sample != nil,
        let interference = state.pointee.interference,
        let leftStorage = state.pointee.left, let rightStorage = state.pointee.right
      else { return kAudioUnitErr_Uninitialized }
      guard frames <= state.pointee.capacity else { return kAudioUnitErr_TooManyFramesToProcess }
      let buffers = UnsafeMutableAudioBufferListPointer(output)
      guard buffers.count == 2 else { return kAudioUnitErr_FormatNotSupported }
      if buffers[0].mData == nil { buffers[0].mData = UnsafeMutableRawPointer(leftStorage) }
      if buffers[1].mData == nil { buffers[1].mData = UnsafeMutableRawPointer(rightStorage) }
      buffers[0].mDataByteSize = frames * UInt32(MemoryLayout<Float>.size)
      buffers[1].mDataByteSize = frames * UInt32(MemoryLayout<Float>.size)
      guard let pullInput else { return kAudioUnitErr_NoConnection }
      let status = pullInput(flags, timestamp, frames, 0, output)
      guard status == noErr else { return status }
      guard let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
        let right = buffers[1].mData?.assumingMemoryBound(to: Float.self)
      else { return kAudioUnitErr_InvalidPropertyValue }
      if flags.pointee.contains(.unitRenderAction_OutputIsSilence) {
        left.update(repeating: 0, count: Int(frames))
        right.update(repeating: 0, count: Int(frames))
      }
      let noise = state.pointee.noise
      let sample = state.pointee.sample
      RadioNoiseBeginBlock(noise)
      let levels = resources.levels.load(ordering: .relaxed)
      let intensity = Float(levels & 255)
      let backgroundIntensity = Float((levels >> 8) & 255)
      var silent = true
      for index in 0..<Int(frames) {
        let l = left[index].isFinite ? left[index] : 0
        let r = right[index].isFinite ? right[index] : 0
        let power = min((l * l + r * r) * 0.5, 16)
        state.pointee.rmsSquared += state.pointee.rmsAlpha * (power - state.pointee.rmsSquared)
        state.pointee.inputPower += state.pointee.inputPowerAlpha * (power - state.pointee.inputPower)
        if state.pointee.inputPower < 0.000001 { state.pointee.quietFrames += 1 }
        else { state.pointee.quietFrames = 0 }
        if state.pointee.previousPhase == RadioInterferencePhaseIdle,
          state.pointee.inputPower >= 0.000001,
          state.pointee.rmsSquared >= 0.000001 {
          state.pointee.referenceRMS = sqrt(state.pointee.rmsSquared)
        }
        let audible = state.pointee.quietFrames < state.pointee.quietLimit
        let texture: Float
        if let sample { texture = RadioSampleNextFrame(sample) }
        else { texture = RadioNoiseNextFrame(noise).left }
        // A positive background survives digital silence in a playing file.
        // The 0.02 reference is only for a silent intro before music is measured.
        let reference = backgroundIntensity > 0
          ? (state.pointee.referenceRMS > 0 ? state.pointee.referenceRMS : 0.02)
          : (audible ? state.pointee.referenceRMS : 0)
        let frame = RadioInterferenceNextFrame(interference, intensity, backgroundIntensity, audible,
          texture, reference)
        state.pointee.previousPhase = frame.phase
        // Monitor headroom is separate. This last-resort bound handles pathological
        // source peaks; level zero still passes the original finite samples exactly.
        let mixedL = l * frame.musicGain + frame.noiseSample
        let mixedR = r * frame.musicGain + frame.noiseSample
        let dry = intensity == 0 && frame.noiseRatio == 0 && frame.musicGain == 1
        left[index] = dry ? l : min(1, max(-1, mixedL))
        right[index] = dry ? r : min(1, max(-1, mixedR))
        silent = silent && left[index] == 0 && right[index] == 0
      }
      if silent { flags.pointee.insert(.unitRenderAction_OutputIsSilence) }
      else { flags.pointee.remove(.unitRenderAction_OutputIsSilence) }
      return noErr
    }
  }
}
