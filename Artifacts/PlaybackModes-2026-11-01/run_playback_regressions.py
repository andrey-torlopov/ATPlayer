#!/usr/bin/env python3
"""Build isolated regression executables from the current production sources.

No Xcode project, user app installation, signing identity, or production plist is
changed. Pass --simulator only when simulator execution has been authorized.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent
SOURCE = ROOT / "SRC/ATPlayer/ATPlayer"
BUNDLE_ID = "dev.torlopov.atplayer.playback-regression"


def invoke(command: list[str], *, timeout: int = 120) -> str:
    print("RUN:", " ".join(command), flush=True)
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    print(result.stdout, end="", flush=True)
    if result.returncode:
        raise RuntimeError(f"Command exited {result.returncode}: {command[0]}")
    return result.stdout


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--simulator", help="Previously authorized dedicated simulator UDID")
    parser.add_argument("--output", type=Path, default=ARTIFACTS)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="ATPlayer-PlaybackRegression-", dir="/private/tmp"))
    queue_source = SOURCE / "Models/PlaybackQueue.swift"
    queue_test = ARTIFACTS / "PlaybackQueueRegression.swift"
    queue_binary = work / "PlaybackQueueRegression"
    queue_result = work / "queue-results.json"
    queue_command = ["xcrun", "swiftc", "-swift-version", "5", "-warnings-as-errors", "-module-cache-path", str(work / "ModuleCache"), str(queue_source), str(queue_test), "-o", str(queue_binary)]
    queue_build = invoke(queue_command)
    queue_log = invoke([str(queue_binary), str(queue_result)])
    (args.output / "queue-build.log").write_text(queue_build)
    (args.output / "queue-runtime.log").write_text(queue_log)
    (args.output / "queue-results.json").write_bytes(queue_result.read_bytes())
    sources = [queue_source, queue_test]
    commands = [queue_command, [str(queue_binary), str(queue_result)]]

    if args.simulator:
        available = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"], text=True))
        matches = [device for group in available["devices"].values() for device in group if device["udid"] == args.simulator]
        if len(matches) != 1:
            raise RuntimeError("Dedicated simulator was not found")
        if matches[0]["state"] != "Booted":
            invoke(["xcrun", "simctl", "boot", args.simulator])
        invoke(["xcrun", "simctl", "bootstatus", args.simulator, "-b"], timeout=180)
        app = work / "PlaybackRegression.app"
        app.mkdir()
        plist = {
            "CFBundleIdentifier": BUNDLE_ID,
            "CFBundleName": "PlaybackRegression",
            "CFBundleExecutable": "PlaybackRegression",
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1",
            "CFBundleShortVersionString": "1.0",
            "MinimumOSVersion": "26.2",
            "UIDeviceFamily": [1, 2],
            "UILaunchScreen": {},
            "UIBackgroundModes": ["audio"],
            "NSSupportsLiveActivities": False,
            "LSRequiresIPhoneOS": True,
            "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False},
        }
        (app / "Info.plist").write_bytes(plistlib.dumps(plist))
        production = [
            SOURCE / "Models/TrackItem.swift",
            queue_source,
            SOURCE / "Services/AudioPlaybackService.swift",
            SOURCE / "Services/PlaylistStorageService.swift",
            SOURCE / "Services/NowPlayingService.swift",
            SOURCE / "LiveActivity/ATPlayerActivityAttributes.swift",
            SOURCE / "LiveActivity/ATPlayerActivityService.swift",
            SOURCE / "ViewModels/ATPlayerViewModel.swift",
        ]
        integration_test = ARTIFACTS / "PlaybackIntegrationRegression.swift"
        sources += production + [integration_test]
        sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip()
        command = [
            "xcrun", "--sdk", "iphonesimulator", "swiftc", "-swift-version", "5", "-warnings-as-errors",
            "-default-isolation", "MainActor", "-target", "arm64-apple-ios26.2-simulator",
            "-sdk", sdk, "-module-cache-path", str(work / "SimulatorModuleCache"),
            "-parse-as-library", *map(str, production), str(integration_test),
            "-o", str(app / "PlaybackRegression"),
        ]
        commands.append(command)
        build_log = invoke(command, timeout=180)
        (args.output / "integration-build.log").write_text(build_log)
        invoke(["codesign", "--force", "--sign", "-", str(app)])
        invoke(["xcrun", "simctl", "install", args.simulator, str(app)])
        container = subprocess.check_output(["xcrun", "simctl", "get_app_container", args.simulator, BUNDLE_ID, "data"], text=True).strip()
        report = Path(container) / "Documents/integration-results.json"
        # Reinstalling an app retains its data. Remove only this harness's own
        # previous report so a crash before test execution cannot yield a stale pass.
        report.unlink(missing_ok=True)
        launch_command = ["xcrun", "simctl", "launch", "--terminate-running-process", "--console", args.simulator, BUNDLE_ID]
        commands.append(launch_command)
        runtime = invoke(launch_command, timeout=180)
        (args.output / "integration-runtime.log").write_text(runtime)
        (args.output / "integration-results.json").write_bytes(report.read_bytes())
        result = json.loads(report.read_text())
        if result["passed"] != result["total"]:
            raise RuntimeError("Integration regression reported failing cases")

    manifest = {
        "work_directory": str(work), "simulator": args.simulator,
        "bundle_id": BUNDLE_ID if args.simulator else None,
        "commands": commands,
        "source_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in set(sources)},
    }
    (args.output / "regression-run.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
