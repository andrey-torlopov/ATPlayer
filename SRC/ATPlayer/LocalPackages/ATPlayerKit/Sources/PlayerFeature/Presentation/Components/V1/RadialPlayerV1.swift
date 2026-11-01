import LibraryDomain
import PlaybackDomain
import SwiftUI

struct RadialPlayerV1: View {
    @ObservedObject var playback: AudioPlaybackState
    @Environment(\.playerThemeV1) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @GestureState private var seekPreview: TimeInterval?
    @State private var seekFeedbackTrigger = false
    @State private var lastSeekFeedbackStep: Int?
    @State private var lastSeekFeedbackTime: ContinuousClock.Instant?
    let onSeek: (TimeInterval) -> Void

    private static let seekFeedbackSteps = 60.0
    private static let minimumSeekFeedbackInterval: Duration = .milliseconds(80)

    private var duration: TimeInterval {
        playback.duration.isFinite ? max(0, playback.duration) : 0
    }

    private var displayedTime: TimeInterval {
        let value = seekPreview ?? playback.currentTime
        return value.isFinite ? min(duration, max(0, value)) : 0
    }

    private var progress: Double {
        duration > 0 ? displayedTime / duration : 0
    }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)

            ZStack {
                SpectrumRaysV1(
                    values: playback.visualizer,
                    isActive: playback.isPlaying && !reduceMotion
                )
                .accessibilityHidden(true)

                Circle()
                    .fill(theme.surface)
                    .frame(width: side * 0.66, height: side * 0.66)
                    .shadow(color: theme.shadow, radius: 12, x: 7, y: 9)
                    .shadow(color: theme.highlight, radius: 10, x: -7, y: -7)
                    .overlay {
                        Circle()
                            .strokeBorder(theme.highlight, lineWidth: 1)
                            .frame(width: side * 0.66, height: side * 0.66)
                    }

                Circle()
                    .stroke(theme.inset, lineWidth: 3)
                    .frame(width: side * 0.61, height: side * 0.61)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: side * 0.61, height: side * 0.61)

                if duration > 0 {
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 8, height: 8)
                        .overlay { Circle().strokeBorder(theme.elevated, lineWidth: 1.5) }
                        .offset(
                            x: sin(progress * 2 * .pi) * side * 0.305,
                            y: -cos(progress * 2 * .pi) * side * 0.305
                        )
                }

                VStack(spacing: 8) {
                    if side >= 220 {
                        Text(playback.isPlaying ? "ВОСПРОИЗВЕДЕНИЕ" : (duration > 0 ? "ПАУЗА" : "АУДИОПЛЕЕР"))
                            .font(.system(size: 8, weight: .semibold))
                            .tracking(1.6)
                            .foregroundStyle(theme.textSecondary)
                    }

                    Text(PlaybackTimeV1.string(displayedTime))
                        .font(.system(size: side < 220 ? 30 : (dynamicTypeSize.isAccessibilitySize ? 36 : 46), weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)

                    Text("из \(PlaybackTimeV1.string(duration))")
                        .font(.system(size: 12, weight: .regular))
                        .monospacedDigit()
                        .foregroundStyle(theme.textSecondary)
                }
                .frame(width: side * 0.51)
                .allowsHitTesting(false)

                RingHitShapeV1()
                    .fill(.clear, style: FillStyle(eoFill: true))
                    .contentShape(RingHitShapeV1(), eoFill: true)
                    .frame(width: side * 0.73, height: side * 0.73)
                    .gesture(seekGesture(diameter: side * 0.73))
                    .allowsHitTesting(duration > 0)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: seekPreview) { _, preview in
            updateSeekFeedback(for: preview)
        }
        .sensoryFeedback(.selection, trigger: seekFeedbackTrigger)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Позиция воспроизведения")
        .accessibilityValue("\(PlaybackTimeV1.string(displayedTime)) из \(PlaybackTimeV1.string(duration))")
        .accessibilityHint("Проведите по кольцу для перемотки")
        .accessibilityAdjustableAction { direction in
            guard duration > 0 else { return }
            switch direction {
            case .increment: onSeek(min(duration, displayedTime + 5))
            case .decrement: onSeek(max(0, displayedTime - 5))
            @unknown default: break
            }
        }
    }

    private func updateSeekFeedback(for preview: TimeInterval?) {
        guard let preview, preview.isFinite, duration > 0 else {
            lastSeekFeedbackStep = nil
            lastSeekFeedbackTime = nil
            return
        }

        let fraction = min(1, max(0, preview / duration))
        let step = Int(fraction * Self.seekFeedbackSteps)
        guard step != lastSeekFeedbackStep else { return }
        lastSeekFeedbackStep = step

        let now = ContinuousClock.now
        if let lastSeekFeedbackTime,
           lastSeekFeedbackTime.duration(to: now) < Self.minimumSeekFeedbackInterval {
            return
        }

        lastSeekFeedbackTime = now
        seekFeedbackTrigger.toggle()
    }

    private func seekGesture(diameter: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($seekPreview) { value, preview, _ in
                guard duration > 0 else { return }
                preview = seekTime(at: value.location, diameter: diameter)
            }
            .onEnded { value in
                guard duration > 0 else { return }
                let target = seekTime(at: value.location, diameter: diameter)
                onSeek(target)
            }
    }

    private func seekTime(at point: CGPoint, diameter: CGFloat) -> TimeInterval {
        let angle = atan2(point.y - diameter / 2, point.x - diameter / 2) + .pi / 2
        let normalized = angle < 0 ? angle + 2 * .pi : angle
        return duration * normalized / (2 * .pi)
    }
}

private struct RingHitShapeV1: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: rect)
        path.addEllipse(in: rect.insetBy(dx: rect.width * 0.17, dy: rect.height * 0.17))
        return path
    }
}

struct SpectrumRaysV1: View {
    @Environment(\.playerThemeV1) private var theme
    let values: [CGFloat]
    let isActive: Bool

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let count = 72

            for index in 0..<count {
                let sample = values.isEmpty ? 0 : values[min(values.count - 1, index * values.count / count)]
                let amplitude = isActive && sample.isFinite ? min(1, max(0, sample)) : 0
                let angle = Double(index) / Double(count) * 2 * .pi - .pi / 2
                let start = side * 0.373
                let end = start + side * (0.018 + amplitude * 0.095)
                var ray = Path()
                ray.move(to: CGPoint(x: center.x + cos(angle) * start, y: center.y + sin(angle) * start))
                ray.addLine(to: CGPoint(x: center.x + cos(angle) * end, y: center.y + sin(angle) * end))

                var shaded = context
                shaded.addFilter(.shadow(color: theme.shadow, radius: 1.5, x: 1.5, y: 2))
                shaded.stroke(
                    ray,
                    with: .color(isActive ? theme.accent.opacity(0.45 + amplitude * 0.55) : theme.border),
                    style: StrokeStyle(lineWidth: max(2, side * 0.007), lineCap: .round)
                )
            }
        }
    }
}

enum PlaybackTimeV1 {
    static func string(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(min(seconds, Double(Int.max / 2)))
        let hours = total / 3600
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, total / 60 % 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

#Preview("Круг · светлый") {
    SpectrumRaysV1(values: [], isActive: false)
        .frame(width: 320, height: 320)
        .padding(24)
        .background(PlayerThemeV1.light.background)
        .environment(\.playerThemeV1, .light)
}
