import Combine
import PlaybackDomain
import SwiftUI

struct LandscapeAmbientViewV1: View {
    @ObservedObject var viewModel: ATPlayerViewModel
    let isVisible: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var environment = AmbientEnvironmentState()
    @AppStorage(AmbientPreferences.keepsScreenAwakeKey) private var keepsScreenAwake = true
    @State private var isPlaying = false
    @State private var isMounted = false
    @State private var idleTimerOwner = UUID()

    private var policy: AmbientRenderPolicy {
        AmbientRenderPolicy(
            isVisible: isVisible && isMounted,
            isSceneActive: scenePhase == .active,
            isPlaying: isPlaying,
            reduceMotion: reduceMotion,
            isLowPowerModeEnabled: environment.isLowPowerModeEnabled,
            thermalState: environment.thermalState,
            keepsScreenAwake: keepsScreenAwake
        )
    }

    var body: some View {
        ZStack {
            AmbientMetalView(
                playback: viewModel.playbackState,
                isAnimating: policy.isAnimating,
                isLight: colorScheme == .light,
                preferredFPS: policy.preferredFPS,
                resolutionScale: policy.resolutionScale
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            AmbientTransportControlsV1(viewModel: viewModel, playback: viewModel.playbackState)
                .disabled(!isVisible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("landscape-ambient")
        .onReceive(viewModel.playbackState.$isPlaying.removeDuplicates()) { isPlaying = $0 }
        .onAppear {
            isMounted = true
            environment.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { environment.refresh() }
            if phase != .active { AmbientIdleTimerController.shared.remove(idleTimerOwner) }
        }
        .onChange(of: policy.shouldKeepAwake, initial: true) { _, requested in
            AmbientIdleTimerController.shared.setRequested(requested, for: idleTimerOwner)
        }
        .onDisappear {
            isMounted = false
            AmbientIdleTimerController.shared.remove(idleTimerOwner)
        }
    }
}
