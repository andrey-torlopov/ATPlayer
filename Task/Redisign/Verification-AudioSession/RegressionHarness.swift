import AVFoundation
import Foundation
import UIKit
import SwiftUI
import SwiftData

@MainActor
final class RegressionHarness {
    struct Result: Codable {
        let name: String
        let passed: Bool
        let detail: String
    }

    enum Failure: Error {
        case invalidFixtureFormat
    }

    let directory = URL.documentsDirectory.appendingPathComponent("AudioFixtures", isDirectory: true)
    private(set) var results: [Result] = []

    func check(_ condition: @autoclosure () -> Bool, _ name: String, detail: String = "") {
        let passed = condition()
        results.append(Result(name: name, passed: passed, detail: detail))
        print("\(passed ? "PASS" : "FAIL") \(name) \(detail)")
        fflush(stdout)
    }

    func wait(until condition: @escaping @MainActor () -> Bool, timeout: TimeInterval = 4) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return condition()
    }

    func fixture(name: String, seconds: Double, frequency: Double = 1000, channels: AVAudioChannelCount = 1, sampleRate: Double = 44100, silence: Bool = false, antiphase: Bool = false) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name).appendingPathExtension("caf")
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels) else {
            throw Failure.invalidFixtureFormat
        }
        let count = AVAudioFrameCount(seconds * sampleRate)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        if count > 0 {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count), let channelData = buffer.floatChannelData else {
                throw Failure.invalidFixtureFormat
            }
            buffer.frameLength = count
            for channel in 0..<Int(channels) {
                for frame in 0..<Int(count) {
                    let value = silence ? 0 : Float(0.5 * sin(2 * .pi * frequency * Double(frame) / sampleRate))
                    channelData[channel][frame] = antiphase && channel == 1 ? -value : value
                }
            }
            try file.write(from: buffer)
        }
        return url
    }

    func run() async {
        UserDefaults.standard.removeObject(forKey: "eq_preamp")
        UserDefaults.standard.removeObject(forKey: "eq_gains")
        do {
            try await runAudio()
            try await runMP3()
            try await SessionRegression.run(self)
        } catch {
            check(false, "audio.unexpectedError", detail: error.localizedDescription)
        }
        await LogicRegression.run(self)
        do {
            let data = try JSONEncoder().encode(results)
            let output = URL.documentsDirectory.appendingPathComponent("regression-results.json")
            try data.write(to: output, options: .atomic)
            print("RESULTS_PATH \(output.path)")
            print(results.allSatisfy(\.passed) ? "REGRESSION_PASS" : "REGRESSION_FAIL")
            fflush(stdout)
        } catch {
            print("RESULTS_WRITE_FAILED \(error.localizedDescription)")
            fflush(stdout)
        }
    }


    private func runMP3() async throws {
        let service = AudioPlaybackService()
        var fixtures: [URL] = []
        for name in ["tone-mono-44100", "tone-stereo-48000"] {
            guard let source = Bundle.main.url(forResource: name, withExtension: "mp3") else {
                throw Failure.invalidFixtureFormat
            }
            let url = directory.appendingPathComponent(name).appendingPathExtension("mp3")
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.copyItem(at: source, to: url)
            fixtures.append(url)
            try await service.loadAndPlay(url: url)
            check(service.isPlaying && service.playbackError == nil, "mp3.\(name).starts")
            check(service.duration > 3.9 && service.duration < 4.2, "mp3.\(name).duration")
            check(AVAudioSession.sharedInstance().category == .playback, "mp3.\(name).playbackCategory")
            check(AVAudioSession.sharedInstance().mode == .default, "mp3.\(name).defaultMode")
            let progressed = await wait { service.currentTime > 0.15 }
            check(progressed, "mp3.\(name).clock")
            let metered = await wait { (service.visualizer.max() ?? 0) > 0.1 }
            check(metered && service.visualizer.count == 72, "mp3.\(name).spectrum")
            service.pause()
            service.seek(to: 1.5)
            check(!service.isPlaying && abs(service.currentTime - 1.5) < 0.001, "mp3.\(name).pausedSeek")
            service.play()
            let resumed = await wait { service.currentTime > 1.6 }
            check(resumed && service.isPlaying, "mp3.\(name).resume")
            var finished = 0
            service.onTrackFinished = { finished += 1 }
            service.seek(to: service.duration - 0.3)
            let completed = await wait(until: { finished == 1 }, timeout: 2)
            check(completed && !service.isPlaying && service.currentTime == service.duration, "mp3.\(name).EOF")
            service.stop()
            service.onTrackFinished = nil
        }
        let schema = Schema([PlaylistSection.self, TrackItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let vm = ATPlayerViewModel(context: ModelContext(container))
        guard let section = vm.sections.first else { throw Failure.invalidFixtureFormat }
        vm.requestImport(to: section)
        vm.importFiles(.success(fixtures))
        let imported = await wait(until: { !vm.isImporting }, timeout: 6)
        check(imported && vm.allTracks.count == 2 && vm.importError == nil, "mp3.VM.importsBothFiles")
        if let first = vm.allTracks.first {
            await vm.play(track: first)
            check(vm.playbackService.isPlaying && vm.importError == nil && vm.selectedTrackID == first.id, "mp3.VM.importedFilePlays")
            vm.playbackService.stop()
        } else {
            check(false, "mp3.VM.importedFilePlays")
        }
    }

    private func runAudio() async throws {
        let service = AudioPlaybackService()
        service.preamp = .nan
        check(service.preamp == 0, "audio.eq.nonFinitePreamp")
        service.preamp = 99
        check(service.preamp == 12, "audio.eq.preampBounds")
        service.gains = [.nan, .infinity, -99, 99]
        check(service.gains == [0, 0, -12, 12, 0, 0, 0, 0, 0, 0], "audio.eq.sanitizeArray")
        let restored = AudioPlaybackService()
        check(restored.preamp == 12 && restored.gains == service.gains, "audio.eq.restoreSanitizedSettings")
        service.preamp = 0
        service.gains = Array(repeating: 0, count: 10)

        let tone = try fixture(name: "tone-mono-44k", seconds: 3)
        try await service.loadAndPlay(url: tone)
        check(service.isPlaying && abs(service.duration - 3) < 0.001, "audio.load.valid")
        let progressed = await wait { service.currentTime > 0.1 }
        check(progressed, "audio.clock.progresses")
        let metered = await wait { (service.visualizer.max() ?? 0) > 0.4 }
        check(metered && service.visualizer.count == 72 && service.visualizer.allSatisfy { $0.isFinite && (0...1).contains($0) }, "audio.spectrum.realBoundedBands")
        check((service.visualizer.max() ?? 0) - (service.visualizer.min() ?? 0) > 0.2, "audio.spectrum.frequencySelective")
        service.pause()
        let paused = service.currentTime
        try await Task.sleep(for: .milliseconds(180))
        check(!service.isPlaying && abs(service.currentTime - paused) < 0.001, "audio.pause.stableTime")
        check(service.visualizer.allSatisfy { $0 == 0 }, "audio.pause.spectrumCleared")
        service.seek(to: 1.2)
        check(!service.isPlaying && abs(service.currentTime - 1.2) < 0.001, "audio.seek.paused")
        service.seek(to: .nan)
        check(abs(service.currentTime - 1.2) < 0.001, "audio.seek.rejectsNaN")
        service.play()
        let resumed = await wait { service.currentTime > 1.35 }
        check(resumed && service.isPlaying, "audio.resume.fromOffset")
        service.seek(to: 2)
        let seekStarted = await wait { service.isPlaying && !service.isStarting }
        check(seekStarted && abs(service.currentTime - 2) < 0.15, "audio.seek.playing")
        service.stop()
        check(!service.isPlaying && service.duration == 0 && service.currentTime == 0 && service.visualizer.allSatisfy { $0 == 0 }, "audio.stop.unloads")
        service.play()
        check(!service.isPlaying && service.duration == 0, "audio.stop.cannotResumeStaleFile")

        let short = try fixture(name: "eof-tone", seconds: 1.2)
        var finished = 0
        var finishedAt: TimeInterval?
        service.onTrackFinished = {
            finished += 1
            finishedAt = ProcessInfo.processInfo.systemUptime
        }
        let startedAt = ProcessInfo.processInfo.systemUptime
        try await service.loadAndPlay(url: short)
        try await Task.sleep(for: .milliseconds(200))
        check(finished == 0 && service.isPlaying, "audio.eof.notDataConsumed")
        let reachedEOF = await wait(until: { finished == 1 }, timeout: 4)
        let elapsed = (finishedAt ?? startedAt) - startedAt
        check(reachedEOF && elapsed >= 1.05, "audio.eof.waitsPlayedBack", detail: "elapsed=\(elapsed), expected>=1.05s")
        check(!service.isPlaying && abs(service.currentTime - 1.2) < 0.001 && abs(service.duration - 1.2) < 0.001, "audio.eof.retainsFinalPosition")
        try await Task.sleep(for: .milliseconds(150))
        check(finished == 1, "audio.eof.callbackExactlyOnce")
        service.play()
        let replayStarted = await wait { service.isPlaying }
        check(replayStarted && service.currentTime < 0.15, "audio.eof.playRestarts")
        service.stop()
        service.onTrackFinished = nil

        let stereo = try fixture(name: "antiphase-stereo-48k", seconds: 2, channels: 2, sampleRate: 48000, antiphase: true)
        try await service.loadAndPlay(url: stereo)
        let antiphaseMetered = await wait { (service.visualizer.max() ?? 0) > 0.4 }
        check(antiphaseMetered, "audio.spectrum.antiphaseStereo")
        check(abs(service.duration - 2) < 0.001, "audio.format.stereo48kDuration")
        service.stop()

        let highRate = try fixture(name: "mono-96k", seconds: 2, sampleRate: 96000)
        let highRateStart = ProcessInfo.processInfo.systemUptime
        try await service.loadAndPlay(url: highRate)
        let highRateProgress = await wait { service.currentTime > 0.4 }
        let highRateElapsed = ProcessInfo.processInfo.systemUptime - highRateStart
        check(highRateProgress && abs(service.currentTime - highRateElapsed) < 0.25, "audio.format.mono96kClock", detail: "audio=\(service.currentTime), wall=\(highRateElapsed)")
        service.stop()

        let silence = try fixture(name: "silence", seconds: 2, silence: true)
        try await service.loadAndPlay(url: silence)
        try await Task.sleep(for: .milliseconds(250))
        let initialSilencePeak = service.visualizer.max() ?? 0
        let silenceSettled = await wait(until: { service.visualizer.allSatisfy { abs($0) < 0.00001 } }, timeout: 1.2)
        check(service.isPlaying && silenceSettled, "audio.spectrum.silenceConvergesToZero", detail: "initialPeak=\(initialSilencePeak), finalPeak=\(service.visualizer.max() ?? 0)")

        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
        ])
        let interrupted = await wait { !service.isPlaying }
        check(interrupted, "audio.interruption.beganPauses")
        service.play()
        let manualRecovery = await wait { service.isPlaying }
        check(manualRecovery, "audio.interruption.manualPlayWithoutEnded")
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
        ])
        _ = await wait { !service.isPlaying }
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
            AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue
        ])
        let automaticRecovery = await wait { service.isPlaying }
        check(automaticRecovery, "audio.interruption.shouldResumeRestarts")
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil, userInfo: [
            AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
        ])
        let unplugged = await wait { !service.isPlaying }
        check(unplugged, "audio.route.oldDeviceUnavailablePauses")

        let missing = directory.appendingPathComponent("does-not-exist.caf")
        do {
            try await service.loadAndPlay(url: missing)
            check(false, "audio.load.missingThrows")
        } catch {
            check(true, "audio.load.missingThrows")
        }
        check(!service.isPlaying && service.currentTime == 0 && service.duration == 0, "audio.load.failedDoesNotKeepStaleState")
        service.play()
        check(!service.isPlaying, "audio.load.failedCannotResumeOldFile")
        let empty = try fixture(name: "empty", seconds: 0)
        do {
            try await service.loadAndPlay(url: empty)
            check(false, "audio.load.emptyRejected")
        } catch AudioPlaybackService.PlaybackError.invalidAudioFile {
            check(true, "audio.load.emptyRejected")
        } catch {
            check(false, "audio.load.emptyRejected", detail: "unexpected error: \(error.localizedDescription)")
        }
        service.stop()
        restored.stop()
    }
}

@main
@MainActor
final class HarnessAppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = HarnessSceneDelegate.self
        return configuration
    }
}

@MainActor
final class HarnessSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        controller.view.backgroundColor = .systemBackground
        let label = UILabel(frame: controller.view.bounds)
        label.text = "ATPlayer regression checks"
        label.textAlignment = .center
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.addSubview(label)
        window.rootViewController = controller
        self.window = window
        window.makeKeyAndVisible()
        Task { @MainActor in
            await RegressionHarness().run()
            label.text = "ATPlayer regression complete — see retained results"
        }
    }
}
