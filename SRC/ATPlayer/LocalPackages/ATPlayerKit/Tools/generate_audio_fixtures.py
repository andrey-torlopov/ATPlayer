#!/usr/bin/env python3
"""Generate local audio decoder fixtures without storing media in Git."""

import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

CODECS = {
    "tone.mp3": "libmp3lame",
    "tone.flac": "flac",
    "tone.wav": "pcm_s16le",
    "tone.aiff": "pcm_s16be",
    "tone.caf": "pcm_s16le",
    "tone.aac": "aac",
    "tone.m4a": "aac",
    "tone-alac.m4a": "alac",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-directory",
        type=Path,
        default=Path(__file__).resolve().parents[1]
        / "Tests/PlayerInfrastructureTests/Fixtures",
    )
    args = parser.parse_args()
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        parser.error("FFmpeg is required; install it before generating audio fixtures.")

    destination = args.output_directory.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="atplayer-fixtures-") as temporary:
        temporary_directory = Path(temporary)
        for name, codec in CODECS.items():
            subprocess.run(
                [
                    ffmpeg, "-hide_banner", "-loglevel", "error", "-nostdin",
                    "-f", "lavfi", "-i",
                    "sine=frequency=440:sample_rate=44100:duration=0.1",
                    "-map_metadata", "-1", "-fflags", "+bitexact",
                    "-flags:a", "+bitexact", "-c:a", codec,
                    str(temporary_directory / name),
                ],
                check=True,
            )
        for name in CODECS:
            shutil.copyfile(temporary_directory / name, destination / name)
    print(f"Generated {len(CODECS)} audio fixtures in {destination}")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        sys.exit(f"Audio fixture generation failed: FFmpeg exited with {error.returncode}.")
