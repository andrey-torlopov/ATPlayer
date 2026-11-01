#!/usr/bin/env python3
"""Capture a real Simulator JPEG through /private/tmp, then copy it unchanged.

Usage: python3 capture_screenshot.py UDID DISPLAY_UUID OUTPUT.jpg

Direct simctl writes to this project's external volume stalled in this session.
Capturing to /private/tmp completed immediately. This helper limits capture to
20 seconds and never overwrites an existing destination. It does not alter UI.
"""

import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("udid", help="Simulator device UUID")
    parser.add_argument("display", help="Display port UUID from simctl io enumerate")
    parser.add_argument("output", type=Path, help="New .jpg or .jpeg destination")
    args = parser.parse_args()
    output = args.output.expanduser().resolve()
    if output.suffix.lower() not in (".jpg", ".jpeg"):
        parser.error("output must end in .jpg or .jpeg")
    if output.exists():
        parser.error(f"refusing to overwrite existing file: {output}")
    if not output.parent.is_dir():
        parser.error(f"destination directory does not exist: {output.parent}")

    with tempfile.TemporaryDirectory(prefix="atplayer-screenshot-", dir="/private/tmp") as temporary:
        captured = Path(temporary) / "capture.jpg"
        command = [
            "xcrun", "simctl", "io", args.udid, "screenshot",
            f"--display={args.display}", "--type=jpeg", "--mask=ignored", str(captured),
        ]
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=20)
        except subprocess.TimeoutExpired:
            print("Capture exceeded 20 seconds; its subprocess was stopped. No output copied.", file=sys.stderr)
            return 1
        if result.returncode != 0:
            print(result.stderr or result.stdout or f"simctl exited {result.returncode}", file=sys.stderr)
            return 1
        if not captured.is_file() or captured.stat().st_size == 0:
            print("simctl returned success without a nonempty screenshot. No output copied.", file=sys.stderr)
            return 1
        with captured.open("rb") as source:
            if source.read(2) != b"\xff\xd8":
                print("Captured file is not JPEG. No output copied.", file=sys.stderr)
                return 1
            source.seek(0)
            with output.open("xb") as destination:
                shutil.copyfileobj(source, destination)
    print(f"Saved unchanged Simulator screenshot: {output}")
    inspection = subprocess.run(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", "-g", "hasAlpha", str(output)],
        capture_output=True, text=True, timeout=10,
    )
    print(inspection.stdout, end="")
    if inspection.returncode != 0:
        print(inspection.stderr, file=sys.stderr)
        return inspection.returncode
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
