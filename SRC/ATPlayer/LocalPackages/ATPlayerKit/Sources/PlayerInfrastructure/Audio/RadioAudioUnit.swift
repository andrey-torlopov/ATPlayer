import AudioToolbox
import AVFoundation
import PlaybackDomain
import RadioDSP
import RadioNoiseAssets

/// An internal effect AU. Its render closure captures only preallocated pointers;
/// all sample processing and lock-free controls live behind the C boundary.
final class RadioAudioUnit: AUAudioUnit {
    private static let component = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: 0x61747264, // atrd
        componentManufacturer: 0x4174506C, // AtPl
        componentFlags: 0,
        componentFlagsMask: 0
    )
    private static let registration: Void = {
        AUAudioUnit.registerSubclass(RadioAudioUnit.self, as: component, name: "ATPlayer: Radio Noise", version: 1)
    }()

    /// Hosts may cache the render block before allocation. Its capture therefore
    /// has stable identity for the entire AU lifetime; this POD contains no ARC objects.
    private struct RenderResources {
        var kernel: OpaquePointer?
        var left: UnsafeMutablePointer<Float>?
        var right: UnsafeMutablePointer<Float>?
        var channels = 0
        var capacity: AUAudioFrameCount = 0
        var gateOnly = false
    }
    private final class RenderResourcesOwner {
        let pointer: UnsafeMutablePointer<RenderResources>
        init() {
            pointer = .allocate(capacity: 1)
            pointer.initialize(to: RenderResources())
        }
        deinit {
            pointer.deinitialize(count: 1)
            pointer.deallocate()
        }
    }
    // ARC also releases this owner if a throwing AU initializer fails partway.
    private let renderResourcesOwner = RenderResourcesOwner()
    private var renderResources: UnsafeMutablePointer<RenderResources> { renderResourcesOwner.pointer }

    private var inputBus: AUAudioUnitBus!
    private var outputBus: AUAudioUnitBus!
    private var inputs: AUAudioUnitBusArray!
    private var outputs: AUAudioUnitBusArray!
    private var kernel: OpaquePointer?
    private var scratch: AVAudioPCMBuffer?
    private var sourceGateMode = false
    private var effectIntensity = 0
    private var backgroundIntensity = 0
    private var transportActive = false
    private var sourceCloseFrame = Int64.max
    private var remainingDuration: TimeInterval = 0
    private let seed: UInt64
    private var allocationGeneration: UInt64 = 0

    override init(componentDescription: AudioComponentDescription,
                  options: AudioComponentInstantiationOptions = []) throws {
        seed = UInt64.random(in: UInt64.min...UInt64.max)
        try super.init(componentDescription: componentDescription, options: options)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FormatNotSupported))
        }
        inputBus = try AUAudioUnitBus(format: format)
        outputBus = try AUAudioUnitBus(format: format)
        inputBus.maximumChannelCount = 2
        outputBus.maximumChannelCount = 2
        inputs = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        outputs = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        maximumFramesToRender = 4_096
    }

    static func makeAVAudioUnit() async throws -> AVAudioUnit {
        _ = registration
        return try await withCheckedThrowingContinuation { continuation in
            AVAudioUnit.instantiate(with: component, options: []) { unit, error in
                if let unit { continuation.resume(returning: unit) }
                else {
                    continuation.resume(throwing: error ?? NSError(
                        domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FailedInitialization)))
                }
            }
        }
    }

    static func makeSourceGate() async throws -> AVAudioUnit {
        let unit = try await makeAVAudioUnit()
        guard let implementation = unit.auAudioUnit as? RadioAudioUnit else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FailedInitialization))
        }
        implementation.sourceGateMode = true
        implementation.renderResources.pointee.gateOnly = true
        return unit
    }

    override var inputBusses: AUAudioUnitBusArray { inputs }
    override var outputBusses: AUAudioUnitBusArray { outputs }
    override var canProcessInPlace: Bool { true }
    override var latency: TimeInterval {
        sourceGateMode ? 0 : Double(RadioDSPLatencyFrames()) / outputBus.format.sampleRate
    }

    override func shouldChange(to format: AVAudioFormat, for bus: AUAudioUnitBus) -> Bool {
        !renderResourcesAllocated && format.commonFormat == .pcmFormatFloat32 && !format.isInterleaved
            && (1...2).contains(format.channelCount) && (8_000...384_000).contains(format.sampleRate)
    }

    override func allocateRenderResources() throws {
        let format = outputBus.format
        // A route rebuild must not replay the session's previous interference.
        // This runs off the render thread, without changing preferences or UI state.
        allocationGeneration &+= 1
        let allocationSeed = seed &+ (allocationGeneration &* 0x9e3779b97f4a7c15)
        guard inputBus.format == format,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maximumFramesToRender),
              let newKernel = RadioDSPCreate(format.sampleRate, format.channelCount, allocationSeed) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FormatNotSupported))
        }
        do {
            if !sourceGateMode {
                // Decode/resample/copy before exposing the kernel to rendering.
                // A missing recording fails allocation and reaches the host's
                // unavailable path; it must not silently restore synthetic hiss.
                let sample = try RadioNoiseAssets.loadReference12(sampleRate: format.sampleRate, balanced: true)
                let installed = sample.samples.withUnsafeBufferPointer {
                    RadioDSPSetReferenceSample(newKernel, $0.baseAddress, UInt64($0.count))
                }
                guard installed else {
                    throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FailedInitialization))
                }
            }
        } catch {
            RadioDSPDestroy(newKernel)
            throw error
        }
        RadioDSPDestroy(kernel)
        kernel = newKernel
        scratch = buffer
        renderResources.pointee.kernel = newKernel
        renderResources.pointee.left = buffer.floatChannelData?[0]
        renderResources.pointee.right = format.channelCount == 2 ? buffer.floatChannelData?[1] : nil
        renderResources.pointee.channels = Int(format.channelCount)
        renderResources.pointee.capacity = maximumFramesToRender
        renderResources.pointee.gateOnly = sourceGateMode
        RadioDSPSetSettings(newKernel, Int32(effectIntensity), Int32(backgroundIntensity))
        RadioDSPSetTransport(newKernel, transportActive)
        RadioDSPSetSourceGate(newKernel, sourceCloseFrame)
        RadioDSPResetReception(newKernel, remainingDuration)
        do { try super.allocateRenderResources() }
        catch {
            clearRenderResources()
            setRenderResourcesAllocated(false)
            throw error
        }
    }

    override func deallocateRenderResources() {
        super.deallocateRenderResources()
        clearRenderResources()
    }

    private func clearRenderResources() {
        // AVAudioUnit's resource lifecycle guarantees that rendering has stopped.
        renderResources.pointee.kernel = nil
        renderResources.pointee.left = nil
        renderResources.pointee.right = nil
        RadioDSPDestroy(kernel)
        kernel = nil
        scratch = nil
    }

    deinit { RadioDSPDestroy(kernel) }

    func apply(effectIntensity: Int, backgroundIntensity: Int = 0) {
        self.effectIntensity = max(0, min(10, effectIntensity))
        self.backgroundIntensity = max(0, min(self.effectIntensity, backgroundIntensity))
        RadioDSPSetSettings(kernel, Int32(self.effectIntensity), Int32(self.backgroundIntensity))
    }

    func setTransport(active: Bool) {
        transportActive = active
        RadioDSPSetTransport(kernel, active)
    }

    func resetReception(remainingDuration: TimeInterval) {
        self.remainingDuration = remainingDuration
        RadioDSPResetReception(kernel, remainingDuration)
    }

    func setSourceGate(closeSampleTime: Int64?) {
        sourceCloseFrame = closeSampleTime ?? Int64.max
        RadioDSPSetSourceGate(kernel, sourceCloseFrame)
    }

    var renderedSampleTime: Int64 { RadioDSPRenderedSampleTime(kernel) }
    /// The sample is immutable for the allocated graph's lifetime.
    var hasReferenceSample: Bool { RadioDSPHasReferenceSample(kernel) }
    var renderSampleRate: Double { outputBus.format.sampleRate }
    var radioPhase: RadioPhase {
        switch RadioDSPCurrentPhase(kernel) {
        case RadioDSPPhaseReceiving: return .receiving
        case RadioDSPPhaseInterference: return .interference
        default: return .bypassed
        }
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        // The host is allowed to fetch this before allocateRenderResources().
        // Capture the stable POD pointer, never a stale kernel or source-gate mode.
        let resources = renderResources
        return { flags, timestamp, frameCount, _, output, _, pullInput in
            guard let kernel = resources.pointee.kernel,
                  let leftStorage = resources.pointee.left else { return kAudioUnitErr_Uninitialized }
            let channels = resources.pointee.channels
            let rightStorage = resources.pointee.right
            guard frameCount <= resources.pointee.capacity else { return kAudioUnitErr_TooManyFramesToProcess }
            let buffers = UnsafeMutableAudioBufferListPointer(output)
            guard buffers.count == channels else { return kAudioUnitErr_FormatNotSupported }
            if buffers[0].mData == nil { buffers[0].mData = UnsafeMutableRawPointer(leftStorage) }
            buffers[0].mDataByteSize = frameCount * UInt32(MemoryLayout<Float>.size)
            if channels == 2 {
                if buffers[1].mData == nil { buffers[1].mData = rightStorage.map(UnsafeMutableRawPointer.init) }
                buffers[1].mDataByteSize = frameCount * UInt32(MemoryLayout<Float>.size)
            }
            guard let pullInput else { return kAudioUnitErr_NoConnection }
            let status = pullInput(flags, timestamp, frameCount, 0, output)
            if status != noErr { return status }
            guard let left = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return kAudioUnitErr_InvalidPropertyValue }
            let right = channels == 2 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
            if flags.pointee.contains(.unitRenderAction_OutputIsSilence) {
                left.update(repeating: 0, count: Int(frameCount))
                right?.update(repeating: 0, count: Int(frameCount))
            }
            let time = Int64(timestamp.pointee.mSampleTime)
            let silent = resources.pointee.gateOnly
                ? RadioDSPProcessSourceGate(kernel, left, right, frameCount, time)
                : RadioDSPProcess(kernel, left, right, frameCount, time)
            if silent { flags.pointee.insert(.unitRenderAction_OutputIsSilence) }
            else { flags.pointee.remove(.unitRenderAction_OutputIsSilence) }
            return noErr
        }
    }
}
