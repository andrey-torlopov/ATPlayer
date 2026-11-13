import MetalKit
import OSLog
import QuartzCore

/// MTKView's iOS delegate callbacks and all state changes stay on the UI actor.
@MainActor
final class AmbientGlowRenderer: NSObject, MTKViewDelegate {
    private static let logger = Logger(subsystem: "ATPlayer", category: "AmbientMetal")
    // Two float4 values keep the Swift/Metal layout aligned without scalar padding.
    private struct Uniforms {
        var parameters: SIMD4<Float>
        var spectrumParameters: SIMD4<Float>
    }

    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private weak var view: MTKView?
    private var isLight = false
    private var isSceneActive = false
    private var animationRequested = false
    private var accumulatedTime: CFTimeInterval = 0
    private var animationStartedAt: CFTimeInterval?
    private var spectrum = AmbientSpectrum()
    private var lastSpectrumFrameTime: CFTimeInterval?
    private var isAvailableForDrawing = false
    private var hasFailed = false

    var acceptsSpectrum: Bool {
        !hasFailed && animationRequested && isAvailableForDrawing
    }

    init?(device: MTLDevice) {
        guard let commandQueue = device.makeCommandQueue() else {
            Self.logger.error("Metal command queue unavailable; using the static ambient background.")
            return nil
        }
        guard let libraryURL = Bundle.module.url(forResource: "default", withExtension: "metallib") else {
            Self.logger.error("Packaged ambient Metal library is missing; using the static background.")
            return nil
        }
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(URL: libraryURL)
        } catch {
            Self.logger.error("Packaged ambient Metal library could not load; using the static background.")
            return nil
        }
        guard let vertex = library.makeFunction(name: "ambient_glow_vertex"),
              let fragment = library.makeFunction(name: "ambient_glow_fragment") else {
            Self.logger.error("Ambient Metal functions are missing; using the static background.")
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "ATPlayer ambient glow"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        do {
            self.pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            Self.logger.error("Ambient Metal pipeline could not initialize; using the static background.")
            return nil
        }
        self.commandQueue = commandQueue
        super.init()
    }

    func configure(_ view: MTKView, isAnimating: Bool, isSceneActive: Bool,
                   isLight: Bool, preferredFPS: Int) {
        guard !hasFailed else { return }
        let themeChanged = self.isLight != isLight || self.view == nil
        self.view = view
        self.isLight = isLight
        self.isSceneActive = isSceneActive
        animationRequested = isAnimating
        let frameRate = min(30, max(1, preferredFPS))
        if view.preferredFramesPerSecond != frameRate { view.preferredFramesPerSecond = frameRate }
        if view.isHidden { view.isHidden = false }
        refreshActivity(in: view)
        if themeChanged && view.isPaused && isAvailableForDrawing { view.setNeedsDisplay() }
    }

    func updateSpectrum(_ values: [CGFloat]) {
        guard acceptsSpectrum else { return }
        spectrum.update(values)
    }

    func refreshActivity(in view: MTKView) {
        guard !hasFailed else { return }
        // scenePhase is an observed input. A second, unobserved applicationState gate could
        // leave the loop paused if UIKit became active after the last SwiftUI update.
        let isAvailable = view.window != nil && isSceneActive
        let availabilityChanged = isAvailableForDrawing != isAvailable
        isAvailableForDrawing = isAvailable
        let shouldAnimate = animationRequested && isAvailable
        let wasAnimating = animationStartedAt != nil
        if shouldAnimate != wasAnimating {
            if shouldAnimate {
                let now = CACurrentMediaTime()
                animationStartedAt = now
                lastSpectrumFrameTime = now
            } else {
                freezeTime()
            }
        }
        if !shouldAnimate { resetSpectrum() }
        if view.enableSetNeedsDisplay != !shouldAnimate {
            view.enableSetNeedsDisplay = !shouldAnimate
        }
        if view.isPaused != !shouldAnimate { view.isPaused = !shouldAnimate }
        if !shouldAnimate && isAvailable && (availabilityChanged || wasAnimating) {
            view.setNeedsDisplay()
        }
    }

    func stop() {
        animationRequested = false
        freezeTime()
        resetSpectrum()
        view?.isPaused = true
        view?.enableSetNeedsDisplay = false
        isAvailableForDrawing = false
        view = nil
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        if view.isPaused && !hasFailed && isAvailableForDrawing { view.setNeedsDisplay() }
    }

    func draw(in view: MTKView) {
        guard !hasFailed, isSceneActive,
              view.window != nil,
              view.drawableSize.width > 0, view.drawableSize.height > 0,
              let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else { return }
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            fail()
            return
        }

        let now = CACurrentMediaTime()
        let time = accumulatedTime + (animationStartedAt.map { now - $0 } ?? 0)
        if acceptsSpectrum {
            spectrum.advance(by: now - (lastSpectrumFrameTime ?? now))
            lastSpectrumFrameTime = now
        } else {
            resetSpectrum()
        }
        var uniforms = Uniforms(
            parameters: SIMD4<Float>(
                Float(time), Float(view.drawableSize.width), Float(view.drawableSize.height),
                isLight ? 1 : 0
            ),
            // One aggregate per frame lets the entire curve disappear on silence.
            spectrumParameters: SIMD4<Float>(spectrum.levels.max() ?? 0, 0, 0, 0)
        )
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        // The model always retains exactly 72 floats, including silence and malformed input.
        spectrum.levels.withUnsafeBufferPointer { buffer in
            if let address = buffer.baseAddress {
                encoder.setFragmentBytes(address, length: buffer.count * MemoryLayout<Float>.stride, index: 1)
            }
        }
        // The vertex shader generates a full-screen triangle, so no vertex buffer is needed.
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { [weak self] completed in
            guard completed.status == .error else { return }
            Task { @MainActor [weak self] in self?.fail() }
        }
        commandBuffer.commit()
    }

    private func freezeTime() {
        if let animationStartedAt {
            accumulatedTime += CACurrentMediaTime() - animationStartedAt
            self.animationStartedAt = nil
        }
    }

    private func resetSpectrum() {
        spectrum.reset()
        lastSpectrumFrameTime = nil
    }

    private func fail() {
        guard !hasFailed else { return }
        Self.logger.error("Ambient Metal frame failed; retaining the static background.")
        hasFailed = true
        animationRequested = false
        freezeTime()
        resetSpectrum()
        view?.isPaused = true
        view?.enableSetNeedsDisplay = false
        view?.isHidden = true
    }
}
