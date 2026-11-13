import Combine
import MetalKit
import OSLog
import PlaybackDomain
import SwiftUI

/// A decorative surface. The fallback stays behind Metal, including during setup failures.
struct AmbientMetalView: View {
    @Environment(\.scenePhase) private var scenePhase
    // The coordinator consumes spectrum frames directly, without invalidating SwiftUI.
    let playback: AudioPlaybackState
    let isAnimating: Bool
    let isLight: Bool
    var preferredFPS: Int = 30
    var resolutionScale: CGFloat = 0.5

    var body: some View {
        ZStack {
            fallback
            AmbientMetalSurface(
                playback: playback,
                isAnimating: isAnimating,
                isSceneActive: scenePhase == .active,
                isLight: isLight,
                preferredFPS: preferredFPS,
                resolutionScale: resolutionScale
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        let base = isLight
            ? Color(red: 0.035, green: 0.045, blue: 0.10)
            : Color(red: 0.015, green: 0.020, blue: 0.055)
        return GeometryReader { geometry in
            let radius = geometry.size.height * 0.82
            ZStack {
                base
                RadialGradient(
                    colors: [
                        Color(red: 0.64, green: 0.10, blue: 1.0).opacity(0.92),
                        Color(red: 0.32, green: 0.06, blue: 0.80).opacity(0.55),
                        .clear
                    ],
                    center: UnitPoint(x: 0.48, y: 0.47),
                    startRadius: 0,
                    endRadius: radius
                )
                RadialGradient(
                    colors: [Color(red: 0.03, green: 0.75, blue: 1.0).opacity(0.80), .clear],
                    center: UnitPoint(x: 0.37, y: 0.57),
                    startRadius: 0,
                    endRadius: radius * 0.70
                )
                RadialGradient(
                    colors: [Color(red: 1.0, green: 0.08, blue: 0.52).opacity(0.85), .clear],
                    center: UnitPoint(x: 0.62, y: 0.39),
                    startRadius: 0,
                    endRadius: radius * 0.68
                )
            }
        }
    }
}

private struct AmbientMetalSurface: UIViewRepresentable {
    private static let logger = Logger(subsystem: "ATPlayer", category: "AmbientMetal")
    let playback: AudioPlaybackState
    let isAnimating: Bool
    let isSceneActive: Bool
    let isLight: Bool
    let preferredFPS: Int
    let resolutionScale: CGFloat

    @MainActor
    final class Coordinator {
        var renderer: AmbientGlowRenderer?
        private weak var playback: AudioPlaybackState?
        private var spectrumSubscription: AnyCancellable?
        private var spectrumRequested = false

        func configure(_ view: MTKView, playback: AudioPlaybackState,
                       isAnimating: Bool, isSceneActive: Bool,
                       isLight: Bool, preferredFPS: Int) {
            if self.playback !== playback {
                cancelSpectrumSubscription()
            }
            self.playback = playback
            spectrumRequested = isAnimating && isSceneActive
            renderer?.configure(
                view, isAnimating: isAnimating, isSceneActive: isSceneActive,
                isLight: isLight, preferredFPS: preferredFPS
            )
            refreshSpectrumSubscription(in: view)
        }

        func refreshActivity(in view: MTKView) {
            renderer?.refreshActivity(in: view)
            refreshSpectrumSubscription(in: view)
        }

        func stop() {
            spectrumRequested = false
            cancelSpectrumSubscription()
            playback = nil
            renderer?.stop()
            renderer = nil
        }

        private func refreshSpectrumSubscription(in view: MTKView) {
            guard spectrumRequested, view.window != nil,
                  let playback, let renderer, renderer.acceptsSpectrum else {
                cancelSpectrumSubscription()
                return
            }
            guard spectrumSubscription == nil else { return }
            // AudioPlaybackState is MainActor-isolated. Combine delivers its current value
            // immediately and subsequent values synchronously on that same actor.
            // Use the emitted value: @Published sends it before updating the property.
            spectrumSubscription = playback.$visualizer.sink { [weak self, weak renderer] values in
                guard let renderer, renderer.acceptsSpectrum else {
                    self?.cancelSpectrumSubscription()
                    return
                }
                renderer.updateSpectrum(values)
            }
        }

        private func cancelSpectrumSubscription() {
            spectrumSubscription?.cancel()
            spectrumSubscription = nil
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> AmbientDrawableView {
        let device = MTLCreateSystemDefaultDevice()
        let view = AmbientDrawableView(frame: .zero, device: device)
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.autoResizeDrawable = false
        view.framebufferOnly = true
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .invalid
        view.sampleCount = 1
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        // An unrendered surface must not cover the fallback with an opaque system color.
        view.isOpaque = false
        view.backgroundColor = .clear
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.isHidden = true
        view.resolutionScale = resolutionScale

        guard let device else {
            Self.logger.error("Metal device unavailable; using the static ambient background.")
            return view
        }
        guard let renderer = AmbientGlowRenderer(device: device) else {
            return view
        }
        context.coordinator.renderer = renderer
        view.delegate = renderer
        let coordinator = context.coordinator
        view.onWindowChange = { [weak coordinator] view in
            coordinator?.refreshActivity(in: view)
        }
        coordinator.configure(
            view,
            playback: playback,
            isAnimating: isAnimating,
            isSceneActive: isSceneActive,
            isLight: isLight,
            preferredFPS: preferredFPS
        )
        return view
    }

    func updateUIView(_ view: AmbientDrawableView, context: Context) {
        view.resolutionScale = resolutionScale
        context.coordinator.configure(
            view,
            playback: playback,
            isAnimating: isAnimating,
            isSceneActive: isSceneActive,
            isLight: isLight,
            preferredFPS: preferredFPS
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: AmbientDrawableView,
                     context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height,
              width.isFinite, height.isFinite, width >= 0, height >= 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    static func dismantleUIView(_ view: AmbientDrawableView, coordinator: Coordinator) {
        coordinator.stop()
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.delegate = nil
        view.onWindowChange = nil
        view.releaseDrawables()
    }
}

/// Owns drawable sizing so resizing a paused surface also produces a fresh static frame.
@MainActor
private final class AmbientDrawableView: MTKView {
    var resolutionScale: CGFloat = 0.5 {
        didSet {
            if oldValue != resolutionScale { setNeedsLayout() }
        }
    }
    var onWindowChange: ((AmbientDrawableView) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        updateDrawableSize()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateDrawableSize()
        onWindowChange?(self)
    }

    private func updateDrawableSize() {
        guard bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0 else { return }
        let scale = resolutionScale.isFinite ? min(1, max(0.25, resolutionScale)) : 0.5
        let displayScale = window?.screen.scale ?? traitCollection.displayScale
        let size = CGSize(
            width: max(1, (bounds.width * displayScale * scale).rounded(.up)),
            height: max(1, (bounds.height * displayScale * scale).rounded(.up))
        )
        guard drawableSize != size else { return }
        drawableSize = size
        if isPaused && enableSetNeedsDisplay { setNeedsDisplay() }
    }
}
