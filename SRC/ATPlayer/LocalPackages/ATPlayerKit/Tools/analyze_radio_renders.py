#!/usr/bin/env python3
"""Measure WAVs independently with FFmpeg EBU R128 and 8x windowed-sinc reconstruction."""

import argparse
import array
import json
import math
from pathlib import Path
import re
import subprocess


def measure(path):
    ebu = subprocess.run(
        ["ffmpeg", "-hide_banner", "-nostdin", "-i", str(path),
         "-filter_complex", "ebur128=peak=true", "-f", "null", "-"],
        capture_output=True, text=True, check=True,
    )
    reported = re.findall(r"Peak:\s+(-?\d+\.\d+) dBFS", ebu.stderr)
    if not reported:
        raise RuntimeError(f"No EBU true peak measurement for {path.name}")
    process = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-nostdin", "-i", str(path), "-map", "0:a:0",
         "-af", "aresample=384000:resampler=swr:filter_size=64:cutoff=1:filter_type=kaiser:kaiser_beta=12",
         "-c:a", "pcm_f32le",
         "-f", "f32le", "pipe:1"], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    count = 0
    squared = 0.0
    peak = 0.0
    nonfinite = 0
    while chunk := process.stdout.read(65536):
        samples = array.array("f")
        samples.frombytes(chunk)
        for value in samples:
            count += 1
            if not math.isfinite(value):
                nonfinite += 1
                continue
            peak = max(peak, abs(value))
            squared += value * value
    error = process.stderr.read().decode()
    if process.wait() != 0:
        raise RuntimeError(error)
    result = {
        "name": path.name,
        "output_sample_rate": 384000,
        "oversampling_ratio": "384000 / 48000 = 8",
        "sample_count": count,
        "sum_of_squares": squared,
        "rms": math.sqrt(squared / count),
        "rms_formula": f"sqrt({squared:.9f} / {count})",
        "reconstructed_peak_amplitude": peak,
        "reconstructed_peak_dbfs": 20 * math.log10(peak) if peak > 0 else None,
        "peak_formula": f"20 * log10({peak:.9f} / 1)",
        "ebu_true_peak_dbtp": float(reported[-1]),
        "nonfinite_samples": nonfinite,
    }
    print(f"{path.name}: EBU TP={result['ebu_true_peak_dbtp']:.1f} dBTP; "
          f"8x peak={result['peak_formula']}={result['reconstructed_peak_dbfs']:.4f} dBFS; "
          f"RMS={result['rms_formula']}={result['rms']:.9f}; NaN/Inf={nonfinite}", flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--pattern", default="*.wav")
    parser.add_argument("--output", default="analysis.json")
    args = parser.parse_args()
    paths = sorted(args.directory.glob(args.pattern))
    if not paths:
        parser.error("No input WAV files")
    results = [measure(path) for path in paths]
    destination = args.directory / args.output
    destination.write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n")
    if any(item["nonfinite_samples"] for item in results):
        raise SystemExit("Nonfinite samples detected")
    if any(item["reconstructed_peak_dbfs"] > -1 for item in results if item["name"].startswith("stress-")):
        raise SystemExit("Steady wet stress output exceeds -1 dBTP target")


if __name__ == "__main__":
    main()
