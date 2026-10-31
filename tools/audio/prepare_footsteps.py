#!/usr/bin/env python3
"""Builds game-ready footstep variants from audio_library/player/Footsteps/.

    python3 tools/audio/prepare_footsteps.py            (needs ffmpeg)

Originals in audio_library/ are only read, never changed. For each surface the
game actually has, the 8 best takes (MAX_VARIANTS) are converted to 16-bit /
44.1 kHz mono WAV, given 2 ms / 12 ms anti-click fades, and level-matched to the
game's existing footstep (RMS about -19 dBFS, peak at most -1 dBFS), then written
to assets/creator/audio/player/footsteps/<surface>_NN.wav. Stone takes are hard-
clipped in the source: they are attenuated 8 dB and de-clipped (ffmpeg adeclip), which
rebuilds the flattened peaks (an estimate — listen to confirm). Carpet has no
recordings: its takes are derived from the wood takes (muffled, quieter).
Prints a JSON summary (used for the review report)."""
import json
import os
import subprocess
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "audio_library", "player", "Footsteps")
DST = os.path.join(ROOT, "assets", "creator", "audio", "player", "footsteps")
TAKES = 8
TARGET_RMS = -19.5
PEAK_CAP = -1.0
# game surface -> (source folder, extra ffmpeg filter before levelling, level offset dB)
SURFACES = {
    "wood": ("Wood footsteps", "", 0.0),
    "stone": ("Stone footsteps", "volume=-8dB,adeclip,", -1.0),   # headroom first, or adeclip cannot rebuild the peaks
    "dirt": ("Dirt footsteps", "", -1.0),
    "grass": ("Grass footsteps", "", -2.0),
    "gravel": ("Gravel Footsteps", "", -1.0),
    "carpet": ("Wood footsteps", "lowpass=f=1100,lowpass=f=1100,", -6.0),   # derived: no carpet recordings
}


def decode(path, filt=""):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-af", filt + "aresample=44100", "-ac", "1", "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, "<f4").astype(np.float64)


def flat_run(x):
    """Longest run of samples within 0.1% of the absolute peak (a flat-topped, clipped waveform)."""
    m = np.abs(x).max()
    hit = np.abs(x) >= m * 0.999
    best = run = 0
    for h in hit:
        run = run + 1 if h else 0
        best = max(best, run)
    return best


def rms_db(x):
    return 20 * np.log10(max(np.sqrt(np.mean(x ** 2)), 1e-9))


def take_number(name):
    digits = "".join(c for c in os.path.splitext(name)[0].split()[-1] if c.isdigit())
    return int(digits) if digits else 0


def main():
    os.makedirs(DST, exist_ok=True)
    summary = {}
    for surface, (folder, filt, offset) in SURFACES.items():
        files = sorted((f for f in os.listdir(os.path.join(SRC, folder)) if f.lower().endswith(".wav")), key=take_number)
        rows = []
        for f in files:
            raw = decode(os.path.join(SRC, folder, f))
            x = decode(os.path.join(SRC, folder, f), filt)
            rows.append({"file": f, "x": x, "dur": len(x) / 44100.0, "rms": rms_db(raw), "flat_before": flat_run(raw), "flat_after": flat_run(x)})
        # Keep the 8 most typical, cleanest takes: drop outliers in length/level, then the most clipped.
        md, mr = np.median([r["dur"] for r in rows]), np.median([r["rms"] for r in rows])
        for r in rows:
            r["score"] = abs(r["dur"] - md) / max(md, 1e-3) + abs(r["rms"] - mr) / 6.0 + r["flat_after"] / 40.0
        keep = sorted(sorted(rows, key=lambda r: r["score"])[:TAKES], key=lambda r: take_number(r["file"]))
        dropped = [r["file"] for r in rows if r not in keep]
        out = []
        for i, r in enumerate(keep, 1):
            x = r["x"]
            n_in, n_out = int(44100 * 0.002), int(44100 * 0.012)
            x[:n_in] *= np.linspace(0.0, 1.0, n_in)
            x[-n_out:] *= np.linspace(1.0, 0.0, n_out)
            gain = TARGET_RMS + offset - rms_db(x)
            peak_db = 20 * np.log10(max(np.abs(x).max(), 1e-9))
            gain = min(gain, PEAK_CAP - peak_db)
            y = np.clip(x * 10 ** (gain / 20.0), -1.0, 1.0)
            name = f"{surface}_{i:02d}.wav"
            path = os.path.join(DST, name)
            pcm = (y * 32767.0).round().astype("<i2").tobytes()
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "s16le", "-ar", "44100", "-ac", "1", "-i", "-", "-c:a", "pcm_s16le", path],
                           input=pcm, check=True)
            out.append({"game_file": os.path.relpath(path, ROOT), "source": f"{folder}/{r['file']}", "dur_s": round(r["dur"], 2),
                        "gain_db": round(gain, 1), "rms_out": round(rms_db(y), 1), "peak_out": round(20 * np.log10(max(np.abs(y).max(), 1e-9)), 1),
                        "flat_run_before": r["flat_before"], "flat_run_after": r["flat_after"]})
        summary[surface] = {"source_folder": folder, "derived": surface == "carpet", "files": out, "not_used": dropped}
    print(json.dumps(summary, indent=1))


if __name__ == "__main__":
    main()
