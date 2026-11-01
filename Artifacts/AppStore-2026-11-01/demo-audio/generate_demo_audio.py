#!/usr/bin/env python3
"""Create original, quiet ambient demo WAVs using only Python's standard library.

The generated audio and this script are dedicated to the public domain under
CC0 1.0 Universal. No recordings, samples, or third-party compositions are used.
"""

from array import array
import hashlib
import json
import math
from pathlib import Path
import struct
import sys
import wave


OUTPUT = Path(__file__).resolve().parent
SAMPLE_RATE = 44_100
TARGET_PEAK = 0.18
ARTIST = "ATPlayer Demo"
TRACKS = (
    ("Утренний свет", 120, (57, 61, 64), 0.021),
    ("Тихий берег", 128, (53, 57, 60), 0.017),
    ("Между облаками", 136, (60, 64, 67), 0.013),
    ("Дорога домой", 144, (55, 59, 62), 0.019),
)


def frequency(midi_note: int) -> float:
    return 440.0 * 2.0 ** ((midi_note - 69) / 12.0)


def info_chunk(tag: bytes, text: str) -> bytes:
    payload = text.encode("utf-8") + b"\0"
    return tag + struct.pack("<I", len(payload)) + payload + b"\0" * (len(payload) % 2)


def add_metadata(path: Path, title: str) -> None:
    payload = (
        b"INFO"
        + info_chunk(b"INAM", title)
        + info_chunk(b"IART", ARTIST)
        + info_chunk(b"ICOP", "CC0 1.0 Universal - original synthesized demo audio")
    )
    with path.open("r+b") as stream:
        stream.seek(0, 2)
        stream.write(b"LIST" + struct.pack("<I", len(payload)) + payload)
        total_size = stream.tell()
        stream.seek(4)
        stream.write(struct.pack("<I", total_size - 8))


def render(title: str, seconds: int, notes: tuple[int, ...], rate: float) -> dict:
    path = OUTPUT / f"{title}.wav"
    frame_count = SAMPLE_RATE * seconds
    frequencies = tuple(frequency(note) for note in notes)
    # A slowly breathing static harmony: no quoted melody and no sampled audio.
    # Six bounded oscillators sum to at most 1.0 before the quiet master gain.
    phase_steps = tuple(2.0 * math.pi * f / SAMPLE_RATE for f in frequencies)
    samples = array("h")
    peak = 0
    with wave.open(str(path), "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(SAMPLE_RATE)
        for frame in range(frame_count):
            t = frame / SAMPLE_RATE
            fade = min(1.0, t / 4.0, (seconds - t) / 6.0)
            breathing = 0.72 + 0.28 * math.sin(math.pi * rate * t) ** 2
            value = sum(
                0.24 * math.sin(step * frame + index * 0.73)
                + (1.0 / 3.0 - 0.24)
                * math.sin(0.5 * step * frame + index * 1.19)
                for index, step in enumerate(phase_steps)
            )
            pcm = round(value * fade * breathing * TARGET_PEAK * 32767)
            peak = max(peak, abs(pcm))
            samples.append(pcm)
            if len(samples) == SAMPLE_RATE:
                if sys.byteorder != "little":
                    samples.byteswap()
                stream.writeframesraw(samples.tobytes())
                samples = array("h")
        if samples:
            if sys.byteorder != "little":
                samples.byteswap()
            stream.writeframesraw(samples.tobytes())
    add_metadata(path, title)
    return {
        "file": path.name,
        "title": title,
        "artist": ARTIST,
        "frames": frame_count,
        "sample_rate_hz": SAMPLE_RATE,
        "duration_seconds": frame_count / SAMPLE_RATE,
        "duration_formula": f"{frame_count} / {SAMPLE_RATE} = {frame_count / SAMPLE_RATE}",
        "peak_pcm": peak,
        "peak_fraction": peak / 32768,
        "peak_formula": f"{peak} / 32768 = {peak / 32768:.8f}",
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    }


def verify(path: Path) -> dict:
    with wave.open(str(path), "rb") as stream:
        channels = stream.getnchannels()
        sample_width = stream.getsampwidth()
        rate = stream.getframerate()
        frames = stream.getnframes()
        compression = stream.getcomptype()
        assert channels == 1 and sample_width == 2
        assert rate == SAMPLE_RATE and compression == "NONE"
        pcm = array("h", stream.readframes(frames))
        if sys.byteorder != "little":
            pcm.byteswap()
        peak = max(abs(sample) for sample in pcm)
        assert peak / 32768 <= 0.2
        assert len(pcm) == frames
    return {
        "channels": channels,
        "sample_width_bytes": sample_width,
        "compression": compression,
        "verified_frames": frames,
        "verified_peak_fraction": peak / 32768,
    }


def main() -> None:
    report = []
    for title, seconds, notes, rate in TRACKS:
        result = render(title, seconds, notes, rate)
        result["verification"] = verify(OUTPUT / result["file"])
        report.append(result)
        print(json.dumps(result, ensure_ascii=False), flush=True)
    (OUTPUT / "verification.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
