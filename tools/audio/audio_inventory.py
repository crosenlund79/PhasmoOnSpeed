#!/usr/bin/env python3
"""Inventory + measurements for audio_library/ (used by the /audio-review skill).

    python3 tools/audio/audio_inventory.py [folder] [--json out.json]

For every audio file: path, category (first folder), format, size, and — when it
can be decoded — duration, sample rate, channels, peak and RMS level (dBFS),
clipping, leading/trailing silence and loop-seam jump. WAV is decoded with the
standard library; OGG/MP3/FLAC/other need ffmpeg/ffprobe on PATH. Also lists the
game's current cue ids (from scripts/core/audio_catalog.gd) so files can be
matched to cues. Measures only — never changes or deletes anything."""
import json
import os
import re
import shutil
import subprocess
import sys
import wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AUDIO_EXT = {".wav", ".ogg", ".mp3", ".flac", ".aif", ".aiff", ".m4a", ".opus"}
FFMPEG = shutil.which("ffmpeg")
FFPROBE = shutil.which("ffprobe")


def db(x):
    return round(20 * np.log10(max(float(x), 1e-9)), 1)


def decode(path):
    """Returns (mono float32 samples, sample_rate, channels, bits) or None."""
    ext = os.path.splitext(path)[1].lower()
    if ext == ".wav":
        try:
            with wave.open(path, "rb") as w:
                ch, sw, sr, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
                raw = w.readframes(n)
            if sw in (1, 2, 4):
                dt = {1: np.uint8, 2: "<i2", 4: "<i4"}[sw]
                a = np.frombuffer(raw, dt).astype(np.float32)
                a = (a - 128.0) / 128.0 if sw == 1 else a / float(2 ** (8 * sw - 1))
                return a.reshape(-1, ch).mean(axis=1), sr, ch, 8 * sw
        except Exception:
            pass   # 24-bit / float WAVs fall through to ffmpeg
    if not (FFMPEG and FFPROBE):
        return None
    try:
        info = json.loads(subprocess.run([FFPROBE, "-v", "error", "-select_streams", "a:0", "-show_entries",
                                          "stream=sample_rate,channels,bits_per_raw_sample,bits_per_sample", "-of", "json", path],
                                         capture_output=True, text=True, timeout=30).stdout)["streams"][0]
        sr, ch = int(info["sample_rate"]), int(info["channels"])
        bits = int(info.get("bits_per_raw_sample") or info.get("bits_per_sample") or 0)
        raw = subprocess.run([FFMPEG, "-v", "error", "-i", path, "-f", "f32le", "-ac", "1", "-"],
                             capture_output=True, timeout=120).stdout
        return np.frombuffer(raw, "<f4"), sr, ch, bits
    except Exception:
        return None


def measure(path, folder):
    rel = os.path.relpath(path, ROOT)
    parts = os.path.relpath(path, folder).split(os.sep)
    row = {"path": rel, "category": parts[0] if len(parts) > 1 else "", "name": os.path.basename(path),
           "format": os.path.splitext(path)[1].lower().lstrip("."), "size_kb": round(os.path.getsize(path) / 1024, 1)}
    notes = os.path.splitext(path)[0] + ".txt"
    if os.path.exists(notes):
        row["notes"] = open(notes, encoding="utf-8", errors="replace").read().strip()[:500]
    d = decode(path)
    if d is None:
        row["decoded"] = False
        return row
    x, sr, ch, bits = d
    row.update({"decoded": True, "duration_s": round(len(x) / sr, 2) if sr else 0, "sample_rate": sr, "channels": ch, "bits": bits})
    if len(x) == 0:
        row["empty"] = True
        return row
    peak = float(np.max(np.abs(x)))
    rms = float(np.sqrt(np.mean(x.astype(np.float64) ** 2)))
    loud = np.abs(x) > 10 ** (-50 / 20)   # -50 dBFS threshold
    lead = int(np.argmax(loud)) / sr if loud.any() else len(x) / sr
    trail = int(np.argmax(loud[::-1])) / sr if loud.any() else len(x) / sr
    w = max(1, int(sr * 0.01))
    seam = abs(float(np.mean(x[:w])) - float(np.mean(x[-w:]))) + abs(float(x[0]) - float(x[-1]))
    row.update({"peak_dbfs": db(peak), "rms_dbfs": db(rms), "clipped_pct": round(100.0 * float(np.mean(np.abs(x) >= 0.999)), 3),
                "lead_silence_s": round(lead, 2), "trail_silence_s": round(trail, 2), "loop_seam_jump": round(seam, 3),
                "silent": peak < 10 ** (-50 / 20)})
    return row


def catalog_cues():
    path = os.path.join(ROOT, "scripts", "core", "audio_catalog.gd")
    text = open(path, encoding="utf-8").read()
    block = text[text.find("const CUES"):]
    block = block[:block.find("\n}") + 2]
    return [{"id": m.group(1), "creator_path": m.group(2) + "." + m.group(3)}
            for m in re.finditer(r'"(\w+)": \["([\w/]+)", "(\w+)"\]', block)]


def main(argv):
    folder = os.path.join(ROOT, "audio_library")
    out = None
    args = argv[1:]
    if "--json" in args:
        i = args.index("--json")
        out = args[i + 1]
        args = args[:i] + args[i + 2:]
    if args:
        folder = os.path.abspath(args[0])
    files = []
    for dp, dn, fn in os.walk(folder):
        dn[:] = [d for d in dn if not d.startswith("_") and not d.startswith(".")]   # skip _reports etc.
        for f in sorted(fn):
            if os.path.splitext(f)[1].lower() in AUDIO_EXT:
                files.append(os.path.join(dp, f))
    rows = [measure(f, folder) for f in sorted(files)]
    others = []
    for dp, dn, fn in os.walk(folder):
        dn[:] = [d for d in dn if not d.startswith("_") and not d.startswith(".")]
        for f in fn:
            ext = os.path.splitext(f)[1].lower()
            if ext not in AUDIO_EXT and ext != ".txt" and not f.startswith(".") and f != "README.md":
                others.append(os.path.relpath(os.path.join(dp, f), ROOT))
    report = {"folder": os.path.relpath(folder, ROOT), "decoder": "ffmpeg" if FFMPEG else "wav-only",
              "files": rows, "non_audio_files": sorted(others), "game_cues": catalog_cues()}
    if out:
        with open(out, "w", encoding="utf-8") as fh:
            json.dump(report, fh, indent=1)
    print(f"{len(rows)} audio files in {report['folder']} (decoder: {report['decoder']})")
    for r in rows:
        if not r.get("decoded"):
            print(f"  {r['path']}  [{r['size_kb']} KB]  UNDECODED")
            continue
        flags = [k for k in ("silent", "empty") if r.get(k)]
        if r.get("clipped_pct", 0) > 0.01:
            flags.append(f"clips {r['clipped_pct']}%")
        print(f"  {r['path']}  {r['duration_s']}s {r['sample_rate']}Hz {r['channels']}ch  peak {r.get('peak_dbfs')} rms {r.get('rms_dbfs')}"
              f"  sil {r.get('lead_silence_s')}/{r.get('trail_silence_s')}s  seam {r.get('loop_seam_jump')}  {' '.join(flags)}")
    if others:
        print(f"{len(others)} non-audio files: " + ", ".join(others[:20]))
    print(f"{len(report['game_cues'])} game cues known.")


if __name__ == "__main__":
    main(sys.argv)
