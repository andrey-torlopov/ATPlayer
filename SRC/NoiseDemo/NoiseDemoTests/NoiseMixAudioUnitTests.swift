import AVFoundation
import RadioNoiseAssets
import RadioNoiseKit
import XCTest
@testable import NoiseDemo

@MainActor
final class NoiseMixAudioUnitTests: XCTestCase {
  private struct Measurement {
    var minimumGain = Double.greatestFiniteMagnitude
    var maximumGain = 0.0
    var largestNoiseToMusic = 0.0
    var cleanWindows = 0
    var idleWindows = 0
    var audibleIdleWindows = 0
    var idleNoiseSquares = 0.0
    var idleMusicSquares = 0.0
    var maximumDryError: Float = 0
    var noiseProbe: [Float] = []
    var noiseToSourceWindows: [Double] = []
    var silentWindowNoiseRMS: [Double] = []
    var noiseEnergyImmediatelyAfterDisable = 0.0
    var maximumNoiseAfterDisableSettles = 0.0

    var idleNoiseToMusic: Double {
      sqrt(idleNoiseSquares / max(idleMusicSquares, 1e-20))
    }
  }

  // Scheduling must return before manual rendering starts; awaiting playback
  // completion here would prevent the test from ever rendering its input.
  private func schedule(_ buffer: AVAudioPCMBuffer, on player: AVAudioPlayerNode) {
    player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
  }

  /// Runs the actual AVAudioEngine -> AU render block, including the case where
  /// AVAudioEngine obtains the block before allocating its resources.
  private func render(level: Int32, background: Int32 = 0, seed: UInt64 = 140,
    includesSilentPassages: Bool = false,
    disableAtFrame: Int? = nil,
    material: DemoNoiseMaterial = .recording12,
    parameters: RadioNoiseParameters = RadioNoiseParametersForPreset(RadioNoisePresetSquelch)
  ) async throws -> Measurement {
    let rate = 48_000.0
    let length = 40 * 48_000
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
    let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(length)))
    input.frameLength = UInt32(length)
    let channels = try XCTUnwrap(input.floatChannelData)
    for index in 0..<length {
      let sample: Float = includesSilentPassages && (index < 96_000 || index >= 384_000)
        ? 0 : Float(0.2 * sin(2 * Double.pi * 440 * Double(index) / rate))
      channels[0][index] = sample
      channels[1][index] = -sample
    }
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let unit = try await NoiseMixAudioUnit.make()
    let implementation = try XCTUnwrap(unit.auAudioUnit as? NoiseMixAudioUnit)
    implementation.configure(seed: seed, parameters: parameters, intensity: level,
      backgroundIntensity: background,
      material: material)
    engine.attach(player)
    engine.attach(unit)
    engine.connect(player, to: unit, format: format)
    engine.connect(unit, to: engine.mainMixerNode, format: format)
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
    let output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
    schedule(input, on: player)
    try engine.start()
    player.play()
    defer { player.stop(); engine.stop(); engine.disableManualRenderingMode() }
    var result = Measurement()
    var rendered = 0
    var disabledAt: Int?
    var retries = 0
    var musicSquares = 0.0
    var noiseSquares = 0.0
    var sourceSquares = 0.0
    var windowFrames = 0
    let windowLength = 12_000
    while rendered < length {
      if let disableAtFrame, disabledAt == nil, rendered >= disableAtFrame {
        implementation.setIntensity(0, backgroundIntensity: 0)
        disabledAt = rendered
      }
      let count = UInt32(min(512, length - rendered))
      let status = try engine.renderOffline(count, to: output)
      if status == .cannotDoInCurrentContext {
        retries += 1
        guard retries < 32 else { throw DemoAudioError.generatorUnavailable }
        continue
      }
      XCTAssertEqual(status, .success)
      guard status == .success else { throw DemoAudioError.generatorUnavailable }
      retries = 0
      let values = try XCTUnwrap(output.floatChannelData)
      for index in 0..<Int(output.frameLength) {
        let source = channels[0][rendered]
        let left = values[0][index]
        let right = values[1][index]
        XCTAssertTrue(left.isFinite && right.isFinite)
        if level == 0 {
          result.maximumDryError = max(result.maximumDryError, abs(left - source), abs(right + source))
        }
        let music = Double((left - right) * 0.5)
        let noise = Double((left + right) * 0.5)
        if let disabledAt {
          let offset = rendered - disabledAt
          if offset < 256 { result.noiseEnergyImmediatelyAfterDisable += noise * noise }
          if offset >= 12_000 {
            result.maximumNoiseAfterDisableSettles = max(result.maximumNoiseAfterDisableSettles, abs(noise))
          }
        }
        if rendered.isMultiple(of: 97) { result.noiseProbe.append(Float(noise)) }
        musicSquares += music * music
        noiseSquares += noise * noise
        sourceSquares += Double(source) * Double(source)
        rendered += 1
        windowFrames += 1
        if windowFrames == windowLength {
          if sourceSquares < 1e-12 {
            if rendered > windowLength {
              result.silentWindowNoiseRMS.append(sqrt(noiseSquares / Double(windowLength)))
            }
            musicSquares = 0; noiseSquares = 0; sourceSquares = 0; windowFrames = 0
            continue
          }
          let gain = sqrt(musicSquares / sourceSquares)
          if rendered >= 2 * 48_000 {
            result.noiseToSourceWindows.append(sqrt(noiseSquares / sourceSquares))
          }
          result.minimumGain = min(result.minimumGain, gain)
          result.maximumGain = max(result.maximumGain, gain)
          result.largestNoiseToMusic = max(result.largestNoiseToMusic,
            sqrt(noiseSquares / max(musicSquares, 1e-20)))
          if abs(gain - 1) < 0.0001 {
            result.idleWindows += 1
            result.idleNoiseSquares += noiseSquares
            result.idleMusicSquares += musicSquares
            if noiseSquares < 1e-10 { result.cleanWindows += 1 }
            else { result.audibleIdleWindows += 1 }
          }
          musicSquares = 0; noiseSquares = 0; sourceSquares = 0; windowFrames = 0
        }
      }
    }
    print("Demo AU level=\(level), background=\(background), musicGainRMS=sqrt(sum(music^2)/sum(source^2)), min=\(result.minimumGain), max=\(result.maximumGain), maxNoise/music=sqrt(sum(noise^2)/sum(music^2))=\(result.largestNoiseToMusic), idleNoise/music=sqrt(sum(idleNoise^2)/sum(idleMusic^2))=\(result.idleNoiseToMusic), audibleIdleWindows=\(result.audibleIdleWindows)/\(result.idleWindows), cleanWindows=\(result.cleanWindows), dryMaxError=\(result.maximumDryError)")
    return result
  }

  func testZeroPassesMusicWithoutNoiseThroughActualAudioUnit() async throws {
    let result = try await render(level: 0)
    XCTAssertLessThan(result.maximumDryError, 0.000001)
    XCTAssertEqual(result.cleanWindows, 160)
  }

  func testStrongEventsAbsorbMusicAndReturnToQuietRadioBedThroughActualAudioUnit() async throws {
    let result = try await render(level: 10, background: 7)
    XCTAssertEqual(result.minimumGain, 0.425, accuracy: 0.005)
    XCTAssertEqual(result.maximumGain, 1, accuracy: 0.0001)
    XCTAssertGreaterThan(result.largestNoiseToMusic, 1.3)
    XCTAssertGreaterThan(result.idleWindows, 20)
    XCTAssertGreaterThan(result.audibleIdleWindows, 20)
    XCTAssertGreaterThan(result.idleNoiseToMusic, 0.4)
    XCTAssertLessThan(result.idleNoiseToMusic, 0.65)
    XCTAssertGreaterThan(result.largestNoiseToMusic, result.idleNoiseToMusic * 2.5)
  }

  func testLowPositiveLevelKeepsQuietRadioBedBetweenEvents() async throws {
    let result = try await render(level: 1, background: 1)
    XCTAssertEqual(result.minimumGain, 0.895, accuracy: 0.005)
    XCTAssertEqual(result.maximumGain, 1, accuracy: 0.0001)
    XCTAssertGreaterThan(result.audibleIdleWindows, 20)
    XCTAssertGreaterThan(result.idleNoiseToMusic, 0.105)
    XCTAssertLessThan(result.idleNoiseToMusic, 0.175)
  }

  func testEqualLevelsKeepNoiseVolumeWithinThirtyPercentAcrossEvents() async throws {
    let result = try await render(level: 7, background: 7)
    let minimum = try XCTUnwrap(result.noiseToSourceWindows.min())
    let maximum = try XCTUnwrap(result.noiseToSourceWindows.max())
    print("Equal-level noise/source RMS=sqrt(sum(noise^2)/sum(source^2)), min=\(minimum), max=\(maximum), target=0.5175")
    XCTAssertGreaterThan(minimum, 0.5175 * 0.7)
    XCTAssertLessThan(maximum, 0.5175 * 1.3)
    XCTAssertGreaterThan(result.audibleIdleWindows, 20)
  }

  func testZeroBackgroundRemovesNoiseBetweenEventsOnly() async throws {
    let result = try await render(level: 10, background: 0)
    XCTAssertEqual(result.idleNoiseToMusic, 0, accuracy: 0.000001)
    XCTAssertGreaterThan(result.cleanWindows, 20)
    XCTAssertGreaterThan(result.largestNoiseToMusic, 1.3)
  }

  func testPositiveBackgroundSurvivesSilentIntroAndSilentPassage() async throws {
    let result = try await render(level: 10, background: 7, includesSilentPassages: true)
    XCTAssertGreaterThan(result.silentWindowNoiseRMS.count, 100)
    XCTAssertGreaterThan(try XCTUnwrap(result.silentWindowNoiseRMS.min()), 0.005)
  }

  func testDisablingIdleBackgroundRampsBeforeExactDryPassage() async throws {
    // The first event cannot start before three seconds. Disable at two seconds
    // to exercise the idle background, independently of an absorption envelope.
    let result = try await render(level: 10, background: 7, disableAtFrame: 96_000)
    XCTAssertGreaterThan(result.noiseEnergyImmediatelyAfterDisable, 0.0001,
      "The first samples after control zero must retain the smooth background release")
    XCTAssertEqual(result.maximumNoiseAfterDisableSettles, 0, accuracy: 0.000001)
  }

  func testImportedMonoFileStreamsThroughMixGraphAtOutputSampleRate() async throws {
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
    addTeardownBlock { try FileManager.default.removeItem(at: fileURL) }
    let sourceRate = 44_100.0
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sourceRate, channels: 1))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100))
    buffer.frameLength = 44_100
    let channel = try XCTUnwrap(buffer.floatChannelData)[0]
    for index in 0..<44_100 {
      channel[index] = Float(0.15 * sin(2 * Double.pi * 440 * Double(index) / sourceRate))
    }
    do {
      let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
      try file.write(from: buffer)
    }
    let engine = try await NoiseEngine.music(url: fileURL, seed: 140,
      parameters: RadioNoiseParametersForPreset(RadioNoisePresetSquelch), intensity: 10,
      backgroundIntensity: 0,
      monitorGain: 1, onFinished: {})
    let outputFormat = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: engine.sampleRate, channels: 2))
    try engine.engine.enableManualRenderingMode(.offline, format: outputFormat, maximumFrameCount: 512)
    let output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 512))
    try engine.start()
    defer { engine.stop(); engine.engine.disableManualRenderingMode() }
    var energy = 0.0
    var tailEnergy = 0.0
    var frames = 0
    var retries = 0
    while frames < Int(engine.sampleRate * 2.2) {
      let status = try engine.engine.renderOffline(512, to: output)
      if status == .cannotDoInCurrentContext {
        retries += 1
        guard retries < 32 else { throw DemoAudioError.generatorUnavailable }
        continue
      }
      XCTAssertEqual(status, .success)
      guard status == .success else { throw DemoAudioError.generatorUnavailable }
      retries = 0
      let data = try XCTUnwrap(output.floatChannelData)
      for index in 0..<Int(output.frameLength) {
        XCTAssertEqual(data[0][index], data[1][index], accuracy: 0.000001)
        let samplePower = Double(data[0][index]) * Double(data[0][index])
        energy += samplePower
        if frames + index > Int(engine.sampleRate * 1.8) { tailEnergy += samplePower }
      }
      frames += Int(output.frameLength)
    }
    XCTAssertGreaterThan(energy, 100)
    XCTAssertLessThan(tailEnergy, 0.000001)
    // dataPlayedBack uses the device clock and is verified by live playback;
    // offline mode proves that the quiet-input gate also silences the radio bed.
  }

  func testRecordingIgnoresSynthComponentsAndRepeatsSeedThroughActualAudioUnit() async throws {
    var mutedSynth = RadioNoiseDefaultParameters()
    mutedSynth.hissLevel = 0
    mutedSynth.crackleLevel = 0
    mutedSynth.resonanceLevel = 0
    mutedSynth.chatterLevel = 0
    mutedSynth.squelchLevel = 0
    let first = try await render(level: 10, parameters: mutedSynth)
    let repeated = try await render(level: 10, parameters: mutedSynth)
    let changed = try await render(level: 10, seed: 141, parameters: mutedSynth)
    let procedural = try await render(level: 10, material: .procedural, parameters: mutedSynth)
    XCTAssertGreaterThan(first.largestNoiseToMusic, 1.3)
    XCTAssertEqual(first.noiseProbe, repeated.noiseProbe)
    XCTAssertNotEqual(first.noiseProbe, changed.noiseProbe)
    XCTAssertEqual(procedural.largestNoiseToMusic, 0, accuracy: 0.000001)
  }

  func testSoloGraphPlaysBundledRecordingPCM() throws {
    var parameters = RadioNoiseDefaultParameters()
    parameters.masterLevel = 1
    let noise = try NoiseEngine(seed: 140, parameters: parameters)
    let recording = try RadioNoiseAssets.loadReference12(sampleRate: noise.sampleRate, balanced: true)
    let rawRecording = try RadioNoiseAssets.loadReference12(sampleRate: noise.sampleRate)
    XCTAssertNotEqual(recording.samples, rawRecording.samples,
      "The raw asset remains available separately; the production solo uses the balanced recording")
    let sampler = try XCTUnwrap(recording.samples.withUnsafeBufferPointer {
      RadioSampleCreate(noise.sampleRate, $0.baseAddress, UInt64($0.count), 140)
    })
    defer { RadioSampleDestroy(sampler) }
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: noise.sampleRate, channels: 2))
    try noise.engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
    let output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
    try noise.start()
    defer { noise.stop(); noise.engine.disableManualRenderingMode() }
    var maximumError: Float = 0
    var energy = 0.0
    for _ in 0..<16 {
      XCTAssertEqual(try noise.engine.renderOffline(512, to: output), .success)
      let channels = try XCTUnwrap(output.floatChannelData)
      for index in 0..<Int(output.frameLength) {
        let expected = RadioSampleNextFrame(sampler)
        maximumError = max(maximumError, abs(channels[0][index] - expected),
          abs(channels[1][index] - expected))
        energy += Double(expected) * Double(expected)
      }
    }
    print("Solo recorded PCM maximum absolute error=\(maximumError), source energy=sum(sample^2)=\(energy)")
    XCTAssertLessThan(maximumError, 0.000001)
    XCTAssertGreaterThan(energy, 0.001)
  }

  func testRecordingResourceFailurePropagatesWithoutSynthFallback() async throws {
    let unit = try await NoiseMixAudioUnit.make()
    let implementation = try XCTUnwrap(unit.auAudioUnit as? NoiseMixAudioUnit)
    let failure = NSError(domain: "NoiseDemoTests.MissingRecording", code: 12)
    implementation.reference12Loader = { _ in throw failure }
    XCTAssertThrowsError(try implementation.allocateRenderResources()) { error in
      XCTAssertEqual((error as NSError).domain, failure.domain)
      XCTAssertEqual((error as NSError).code, failure.code)
    }
    XCTAssertFalse(implementation.renderResourcesAllocated)
    implementation.reference12Loader = { try RadioNoiseAssets.loadReference12(sampleRate: $0, balanced: true) }
    try implementation.allocateRenderResources()
    XCTAssertTrue(implementation.renderResourcesAllocated)
    implementation.deallocateRenderResources()
  }

  func testMaterialAndControlsDoNotStartPlaybackWhenStopped() {
    let model = NoiseDemoModel()
    XCTAssertEqual(model.noiseMaterial, .recording12)
    XCTAssertEqual(model.overlapLevel, 10)
    XCTAssertEqual(model.backgroundLevel, 7)
    model.selectNoiseMaterial(.procedural)
    model.applyPreset(RadioNoisePresetRetro07)
    model.randomizeSeed()
    model.resetControls()
    model.selectNoiseMaterial(.recording12)
    model.setOverlapLevel(2)
    XCTAssertEqual(model.backgroundLevel, 2)
    model.setBackgroundLevel(7)
    XCTAssertEqual(model.overlapLevel, 7)
    XCTAssertEqual(model.backgroundLevel, 7)
    model.setOverlapLevel(0)
    XCTAssertEqual(model.backgroundLevel, 0)
    model.setBackgroundLevel(7)
    XCTAssertEqual(model.overlapLevel, 7)
    model.controls.gainDB = -18
    XCTAssertFalse(model.isPlaying)
    XCTAssertFalse(model.isStarting)
    XCTAssertNil(model.activeSeed)
    XCTAssertNil(model.errorMessage)
  }

}
