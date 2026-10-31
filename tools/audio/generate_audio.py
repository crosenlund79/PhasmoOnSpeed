#!/usr/bin/env python3
"""Procedural sound-effect generator for SPECTRAL RUN.

Everything is synthesized from scratch with numpy (no samples, no scipy).
Output: 16-bit mono 44.1 kHz WAV files in assets/audio/.

Usage:
    python3 tools/audio/generate_audio.py            # generate all
    python3 tools/audio/generate_audio.py pencil_scribble emf_spike   # subset

Reproducible: every sound uses its own fixed RNG seed.

Loops (ambience_house, music_menu, hunt_loop, spirit_box_static) are built
seamlessly: continuous layers are generated circularly (periodic noise filtered
with circular FFT filters, LFO / drone frequencies snapped to whole cycles per
loop, circular reverb) and discrete events that run past the loop end are
folded (cross-mixed) back into the head, so the tail flows into the start.
"""

import os
import sys
import wave

import numpy as np

SR = 44100
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "audio")

PEAK_ONESHOT = 10 ** (-3 / 20)   # -3 dBFS
PEAK_UI = 10 ** (-6 / 20)        # -6 dBFS (UI is meant to be subtle)
PEAK_LOOP = 10 ** (-12 / 20)     # -12 dBFS


# ---------------------------------------------------------------------------
# Basic helpers
# ---------------------------------------------------------------------------

def N(dur):
    return int(round(dur * SR))


def tt(n):
    return np.arange(n) / SR


def rng_for(seed):
    return np.random.default_rng(seed)


def place(buf, x, start_s):
    """Add x into buf starting at start_s seconds (clipped to buf)."""
    i = int(round(start_s * SR))
    if i >= len(buf):
        return buf
    j = min(len(buf), i + len(x))
    if i < 0:
        x = x[-i:]
        j = min(len(buf), len(x))
        i = 0
    buf[i:j] += x[: j - i]
    return buf


def fold(buf, L):
    """Fold a buffer longer than L back onto [0, L) (seamless loop of events)."""
    out = np.zeros(L)
    for k in range(0, len(buf), L):
        seg = buf[k:k + L]
        out[: len(seg)] += seg
    return out


def crossfade_loop(x, L, X):
    """Crossfade x[L:L+X] (tail) into the head x[:X]; returns length-L loop."""
    out = x[:L].copy()
    r = np.linspace(0, 1, X)
    out[:X] = x[:X] * np.sqrt(r) + x[L:L + X] * np.sqrt(1 - r)
    return out


def interp_keys(keys, t, log=False):
    """keys: scalar or list of (time, value). Linear (or log) interpolation."""
    if np.isscalar(keys):
        return np.full_like(t, float(keys), dtype=float)
    kt = np.array([k[0] for k in keys], dtype=float)
    kv = np.array([k[1] for k in keys], dtype=float)
    if log:
        return np.exp(np.interp(t, kt, np.log(kv)))
    return np.interp(t, kt, kv)


def env_ad(n, attack, decay_tau, sustain_end=None):
    """Attack (s) then exponential decay with time constant decay_tau (s)."""
    t = tt(n)
    a = np.clip(t / max(attack, 1e-5), 0, 1)
    d = np.exp(-np.maximum(t - attack, 0) / decay_tau)
    return a * d


def fades(x, fin=0.002, fout=0.02):
    x = x.copy()
    a, b = N(fin), N(fout)
    if a > 0:
        x[:a] *= np.linspace(0, 1, a)
    if b > 0:
        x[-b:] *= np.linspace(1, 0, b) ** 2
    return x


def fit(x, dur):
    n = N(dur)
    if len(x) >= n:
        return x[:n].copy()
    return np.concatenate([x, np.zeros(n - len(x))])


# ---------------------------------------------------------------------------
# Filters (frequency domain; zero phase)
# ---------------------------------------------------------------------------

def g_lp(f, fc, order=2):
    return 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))


def g_hp(f, fc, order=2):
    return 1.0 / np.sqrt(1.0 + (fc / np.maximum(f, 1e-3)) ** (2 * order))


def g_bp(f, lo, hi, order=2):
    return g_hp(f, lo, order) * g_lp(f, hi, order)


def g_peak(f, fc, bw):
    return 1.0 / (1.0 + ((f - fc) / (bw / 2.0)) ** 2)


def fft_filter(x, gain_fn, circular=False, pad=16384):
    n = len(x)
    m = n if circular else n + pad
    X = np.fft.rfft(x, m)
    f = np.fft.rfftfreq(m, 1 / SR)
    y = np.fft.irfft(X * gain_fn(f), m)
    return y[:n]


def lp(x, fc, order=2, circular=False):
    return fft_filter(x, lambda f: g_lp(f, fc, order), circular)


def hp(x, fc, order=2, circular=False):
    return fft_filter(x, lambda f: g_hp(f, fc, order), circular)


def bp(x, lo, hi, order=2, circular=False):
    return fft_filter(x, lambda f: g_bp(f, lo, hi, order), circular)


def tv_filter(x, gain_fn, nfft=1024, hop=256):
    """Time-varying filter by weighted overlap-add STFT.

    gain_fn(f[None, :], times[:, None]) -> (frames, bins) gain matrix.
    """
    n = len(x)
    win = np.hanning(nfft + 1)[:-1]
    pad = nfft
    xp = np.concatenate([np.zeros(pad), x, np.zeros(pad + nfft)])
    starts = np.arange(0, len(xp) - nfft, hop)
    idx = starts[:, None] + np.arange(nfft)[None, :]
    frames = xp[idx] * win
    X = np.fft.rfft(frames, axis=1)
    f = np.fft.rfftfreq(nfft, 1 / SR)
    times = (starts + nfft / 2 - pad) / SR
    G = gain_fn(f[None, :], times[:, None])
    Y = np.fft.irfft(X * G, nfft, axis=1) * win
    out = np.zeros(len(xp))
    norm = np.zeros(len(xp))
    np.add.at(out, idx, Y)
    np.add.at(norm, idx, np.broadcast_to(win ** 2, idx.shape))
    out /= np.maximum(norm, 1e-6)
    return out[pad:pad + n]


def smooth_noise(n, cutoff, rng, circular=False):
    y = lp(rng.standard_normal(n), cutoff, 2, circular)
    return y / (np.std(y) + 1e-12)


def remove_dc(x, fc=18.0, circular=False):
    y = hp(x, fc, 2, circular)
    return y - np.mean(y)


# ---------------------------------------------------------------------------
# Reverb
# ---------------------------------------------------------------------------

def make_ir(rt60, rng, damp=4000.0, predelay=0.015, early=True):
    n = N(rt60 * 1.1 + predelay)
    t = tt(n)
    noise = rng.standard_normal(n)
    lo = lp(noise, damp, 1)
    hi = noise - lo
    tdel = np.maximum(t - predelay, 0)
    env_lo = np.exp(-6.91 * tdel / rt60)
    env_hi = np.exp(-6.91 * tdel / (rt60 * 0.45))
    ir = (lo * env_lo + 0.5 * hi * env_hi) * (t >= predelay)
    # soft onset of the diffuse tail
    ir *= np.clip((t - predelay) / 0.02, 0, 1)
    if early:
        for k in range(8):
            d = predelay * 0.3 + rng.uniform(0.003, predelay + 0.03)
            i = N(d)
            if i < n:
                ir[i] += rng.uniform(-1, 1) * 2.5 * np.exp(-d / 0.05)
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-12
    return ir


def reverb(x, rt60=1.5, wet=0.35, rng=None, damp=4000.0, predelay=0.015,
           circular=False, tail=True):
    rng = rng if rng is not None else rng_for(999)
    ir = make_ir(rt60, rng, damp, predelay)
    if circular:
        L = len(x)
        Y = np.fft.rfft(x) * np.fft.rfft(ir[:L], L)
        y = np.fft.irfft(Y, L)
        dry = x
    else:
        m = len(x) + len(ir)
        y = np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(ir, m), m)
        dry = np.concatenate([x, np.zeros(len(ir))])
        if not tail:
            y, dry = y[:len(x)], dry[:len(x)]
    # match wet level to dry RMS
    y *= (np.sqrt(np.mean(dry ** 2)) + 1e-12) / (np.sqrt(np.mean(y ** 2)) + 1e-12)
    return dry * (1 - wet) + y * wet * 1.4


# ---------------------------------------------------------------------------
# Synthesis building blocks
# ---------------------------------------------------------------------------

def modes(n, freqs, taus, amps, rng=None, phase_rand=True):
    t = tt(n)
    y = np.zeros(n)
    for f, tau, a in zip(freqs, taus, amps):
        ph = rng.uniform(0, 2 * np.pi) if (rng is not None and phase_rand) else 0
        y += a * np.sin(2 * np.pi * f * t + ph) * np.exp(-t / tau)
    return y


def burst(n, rng, lo, hi, attack=0.0005, tau=0.004):
    return bp(rng.standard_normal(n), lo, hi) * env_ad(n, attack, tau)


def thump(dur, f_start, f_end, tau, rng, noise_amt=0.3, noise_fc=300):
    n = N(dur)
    t = tt(n)
    f = f_end + (f_start - f_end) * np.exp(-t / (tau * 0.5))
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = np.sin(ph) * env_ad(n, 0.002, tau)
    y += noise_amt * lp(rng.standard_normal(n), noise_fc) * env_ad(n, 0.001, tau * 0.4)
    return y


def chirp_tone(n, f0, f1, tau, curve="exp"):
    t = tt(n)
    dur = n / SR
    if curve == "exp":
        f = f0 * (f1 / f0) ** (t / dur)
    else:
        f = f0 + (f1 - f0) * t / dur
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / tau)


def bubble(rng, fmin=300, fmax=1500, scale=1.0):
    f = rng.uniform(fmin, fmax)
    d = rng.uniform(0.012, 0.045) * scale
    n = N(d * 3)
    t = tt(n)
    fr = f * (1 + 2.5 * t / d * 0.25)   # bubbles rise in pitch
    y = np.sin(2 * np.pi * np.cumsum(fr) / SR) * np.exp(-t / d)
    y *= np.clip(t / 0.0015, 0, 1)
    return y


# --- formant voice -----------------------------------------------------------

VOWELS = {
    "a": [(730, 90), (1090, 110), (2440, 160), (3400, 250)],
    "e": [(530, 70), (1840, 100), (2480, 160), (3500, 250)],
    "i": [(270, 60), (2290, 100), (3010, 170), (3700, 250)],
    "o": [(570, 80), (840, 90), (2410, 160), (3400, 250)],
    "u": [(300, 60), (870, 90), (2240, 150), (3300, 250)],
    "ae": [(660, 90), (1720, 110), (2410, 160), (3400, 250)],
    "er": [(490, 80), (1350, 100), (1690, 150), (3300, 250)],
    "m": [(250, 60), (1100, 300), (2300, 400), (3300, 400)],
    "l": [(360, 70), (1300, 150), (2800, 200), (3500, 300)],
    "h": [(600, 300), (1500, 400), (2600, 500), (3600, 600)],
}
FORMANT_AMPS = [1.0, 0.65, 0.35, 0.18]


def formant_tv_gain(vowel_keys, fshift=1.0, bw_scale=1.0, floor=0.01):
    kt = np.array([k[0] for k in vowel_keys])

    def gain(f, times):
        times = times[:, 0]
        G = np.full((len(times), f.shape[1]), floor)
        for k in range(4):
            Fk = np.array([VOWELS[v][k][0] for _, v in vowel_keys], float)
            Bk = np.array([VOWELS[v][k][1] for _, v in vowel_keys], float)
            F = np.interp(times, kt, Fk)[:, None] * fshift
            B = np.interp(times, kt, Bk)[:, None] * bw_scale
            G = G + FORMANT_AMPS[k] / (1 + ((f - F) / (B / 2)) ** 2)
        return G

    return gain


def voice(dur, f0_keys, vowel_keys, amp_keys, rng, breath=0.1, voiced=1.0,
          vib_rate=5.0, vib_depth=0.01, jitter=0.01, fshift=1.0, bw_scale=1.0,
          tilt=1.0, rough=0.0, sub=0.0, fmax=9000):
    n = N(dur)
    t = tt(n)
    f0 = interp_keys(f0_keys, t, log=True)
    vd = interp_keys(vib_depth, t)
    f0 = f0 * (1 + vd * np.sin(2 * np.pi * vib_rate * t + rng.uniform(0, 6.28))
               + jitter * smooth_noise(n, 25, rng))
    phase = 2 * np.pi * np.cumsum(f0) / SR
    src = np.zeros(n)
    kmax = int(fmax / max(np.min(f0), 30)) + 1
    for k in range(1, kmax + 1):
        mask = (k * f0) < fmax
        if not mask.any():
            break
        src += np.where(mask, np.sin(k * phase), 0.0) / k ** tilt
    if sub > 0:
        src += sub * np.sin(0.5 * phase) * (1 + 0.5 * smooth_noise(n, 15, rng))
    if rough > 0:
        src *= 1 + rough * smooth_noise(n, 90, rng)
    src /= np.std(src) + 1e-12
    src *= interp_keys(voiced, t)
    noise = rng.standard_normal(n) * interp_keys(breath, t)
    y = tv_filter(src + noise, formant_tv_gain(vowel_keys, fshift, bw_scale))
    return y * interp_keys(amp_keys, t)


def whisper(dur, vowel_keys, amp_keys, rng, fshift=1.0):
    n = N(dur)
    y = tv_filter(rng.standard_normal(n),
                  formant_tv_gain(vowel_keys, fshift, bw_scale=2.0, floor=0.03))
    return hp(y, 400) * interp_keys(amp_keys, tt(n))


# --- tonal instruments ------------------------------------------------------

def midi_hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def music_box_note(freq, dur, rng, vel=1.0):
    n = N(dur)
    t = tt(n)
    parts = [(1.0, 1.0, 1.6), (2.0, 0.12, 0.7), (4.07, 0.25, 0.35),
             (5.93, 0.1, 0.18), (8.6, 0.05, 0.08)]
    y = np.zeros(n)
    for r, a, tau in parts:
        f = freq * r
        if f > 16000:
            continue
        y += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / tau)
    y *= np.clip(t / 0.0015, 0, 1)
    click = hp(rng.standard_normal(n), 3000) * np.exp(-t / 0.002) * 0.15
    return (y + click) * vel


def organ_tone(freq, dur, rng, attack=0.25, release=0.6, bright=1.0):
    n = N(dur + release)
    t = tt(n)
    draw = [(0.5, 0.35), (1, 1.0), (2, 0.5 * bright), (3, 0.25 * bright),
            (4, 0.18 * bright), (6, 0.07 * bright), (8, 0.05 * bright)]
    y = np.zeros(n)
    for r, a in draw:
        for det in (-0.0015, 0.0015):
            y += a * np.sin(2 * np.pi * freq * r * (1 + det) * t + rng.uniform(0, 6.28))
    env = np.clip(t / attack, 0, 1)
    rel_start = dur
    env *= np.where(t > rel_start, np.exp(-(t - rel_start) / (release / 4)), 1.0)
    trem = 1 + 0.04 * np.sin(2 * np.pi * 5.2 * t)
    return y * env * trem


def bell(P, dur, rng, strike=1.0):
    n = N(dur)
    t = tt(n)
    ratios = [0.5, 1.0, 1.183, 1.506, 2.0, 2.514, 2.662, 3.011, 4.166, 5.433, 6.796]
    amps = [0.55, 0.6, 0.55, 0.3, 0.9, 0.35, 0.25, 0.3, 0.22, 0.14, 0.09]
    y = np.zeros(n)
    for r, a in zip(ratios, amps):
        f = P * r
        tau = 5.0 / r ** 0.75
        beat = rng.uniform(0.3, 1.6)
        y += a * 0.5 * (np.sin(2 * np.pi * f * t) + np.sin(2 * np.pi * (f + beat) * t + 1.0)) \
            * np.exp(-t / tau)
    y *= np.clip(t / 0.002, 0, 1)
    y += strike * 0.6 * bp(rng.standard_normal(n), 800, 6000) * np.exp(-t / 0.01)
    return y


def heartbeat(rng, strength=1.0):
    a = thump(0.25, 75, 42, 0.07, rng, 0.25, 180)
    b = thump(0.25, 65, 38, 0.06, rng, 0.2, 160) * 0.65
    out = np.zeros(N(0.45))
    place(out, a, 0)
    place(out, b, 0.15)
    return out * strength


def footstep_wood(rng, soft=1.0):
    n = N(0.35)
    t = tt(n)
    heel = lp(rng.standard_normal(n), 350) * env_ad(n, 0.002, 0.03)
    heel += 0.8 * modes(n, [105, 172, 260, 410], [0.06, 0.045, 0.03, 0.02],
                        [1, 0.6, 0.4, 0.25], rng)
    heel *= np.clip(t / 0.003, 0, 1)
    toe = np.zeros(n)
    m = N(0.25)
    toe[:m] = (bp(rng.standard_normal(m), 150, 1200) * env_ad(m, 0.003, 0.02)
               + 0.4 * modes(m, [190, 330], [0.03, 0.02], [1, 0.5], rng))
    out = heel.copy()
    place(out, toe * 0.55, rng.uniform(0.045, 0.06))
    # scuff
    out += 0.05 * bp(rng.standard_normal(n), 1500, 5000) * env_ad(n, 0.01, 0.04)
    return lp(out, 2500 * soft + 500)


def creak(dur, f_keys, rng, res=(650, 1300, 2500), jit=0.15, amp_keys=None):
    """Stick-slip friction creak: jittered impulse train through wood resonances."""
    n = N(dur)
    t = tt(n)
    f = interp_keys(f_keys, t, log=True) * (1 + jit * smooth_noise(n, 12, rng))
    ph = np.cumsum(f) / SR
    pulses = np.zeros(n)
    idx = np.nonzero(np.diff(np.floor(ph)) > 0)[0]
    pulses[idx] = rng.uniform(0.4, 1.0, len(idx))
    pulses += 0.05 * rng.standard_normal(n) * (np.abs(smooth_noise(n, 30, rng)) > 1.2)

    def g(fr):
        G = 0.03 + sum(a / (1 + ((fr - fc) / (fc * 0.09)) ** 2)
                       for fc, a in zip(res, (1.0, 0.7, 0.4)))
        return G * g_hp(fr, 120)

    y = fft_filter(pulses, g)
    env = interp_keys(amp_keys if amp_keys is not None else [(0, 0), (0.05, 1),
                                                           (dur - 0.1, 1), (dur, 0)], t)
    return y * env


def normalize(x, peak):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 0 else x


# ---------------------------------------------------------------------------
# Sounds
# ---------------------------------------------------------------------------

def s_pencil_scribble():
    rng = rng_for(101)
    dur = 0.64
    n = N(dur)
    t = tt(n)
    v = np.zeros(n)
    bright = np.zeros(n)
    strokes = [(0.015, 0.085, 0.85), (0.11, 0.065, 0.7), (0.19, 0.10, 1.0),
               (0.305, 0.055, 0.75), (0.372, 0.085, 0.9), (0.472, 0.05, 0.7)]
    for s, L, gmax in strokes:
        u = (t - s) / L
        m = (u >= 0) & (u <= 1)
        shape = np.zeros(n)
        shape[m] = np.sin(np.pi * u[m]) ** 0.55
        # direction reversal inside letters: quick speed dips
        for _ in range(rng.integers(1, 3)):
            c = rng.uniform(0.3, 0.75)
            shape *= 1 - 0.85 * np.exp(-((u - c) / 0.06) ** 2)
        v += shape * gmax * rng.uniform(0.85, 1.0)
    # final short flick: fast attack, quick fade, extra bright
    s, L = 0.555, 0.04
    u = (t - s) / L
    m = (u >= 0) & (u <= 1)
    fl = np.zeros(n)
    fl[m] = np.minimum(u[m] / 0.12, 1) * (1 - u[m]) ** 1.5
    v += fl * 1.1
    bright += fl
    # hand tremor / pressure irregularity
    v *= np.clip(1 + 0.22 * smooth_noise(n, 35, rng), 0.4, 1.6)
    v = np.clip(v, 0, None)

    vel_at = lambda times: np.interp(times, t, v)
    br_at = lambda times: np.interp(times, t, bright)

    def g(f, times):
        vv = vel_at(times[:, 0])[:, None]
        bb = br_at(times[:, 0])[:, None]
        fc = 2100 + 3300 * vv + 2500 * bb
        G = np.exp(-(np.log(f + 1) - np.log(fc)) ** 2 / (2 * 0.5 ** 2))
        G += 0.07 * g_hp(f, 7000, 2)      # graphite hiss
        G += 0.10 * g_bp(f, 500, 1200, 2)  # paper body
        return G

    base = tv_filter(rng.standard_normal(n), g, nfft=512, hop=128)
    # paper grain roughness: fast irregular amplitude texture
    rough = np.clip(1 + 0.75 * smooth_noise(n, 420, rng), 0.15, None)
    sig = base * v ** 1.3 * rough
    # graphite grain ticks
    rate = 900 * v / SR
    ticks = (rng.uniform(0, 1, n) < rate) * rng.uniform(0.3, 1.0, n) * np.sign(rng.standard_normal(n))
    ticks = hp(ticks, 2800) * 0.7
    sig += ticks * np.clip(v, 0, 1)
    # desk/paper body thump following pressure
    sig += 0.25 * lp(rng.standard_normal(n), 450) * v
    sig = remove_dc(sig)
    return fades(sig, 0.002, 0.03)


def s_ui_click():
    rng = rng_for(102)
    n = N(0.09)
    t = tt(n)
    y = modes(n, [1650, 2900, 4300], [0.012, 0.007, 0.004], [1, 0.5, 0.25], rng)
    y *= np.clip(t / 0.0008, 0, 1)
    y += 0.6 * burst(n, rng, 2000, 8000, 0.0003, 0.0015)
    y += 0.3 * lp(rng.standard_normal(n), 600) * env_ad(n, 0.0005, 0.008)
    return fades(remove_dc(y), 0.0005, 0.02)


def s_ui_hover():
    rng = rng_for(103)
    n = N(0.11)
    t = tt(n)
    env = np.sin(np.pi * np.clip(t / 0.09, 0, 1)) ** 2
    y = bp(rng.standard_normal(n), 1800, 6500) * env
    y *= np.clip(1 + 0.4 * smooth_noise(n, 300, rng), 0.2, None)
    y += 0.25 * modes(n, [3200], [0.01], [1], rng) * np.clip(t / 0.001, 0, 1)
    return fades(remove_dc(y), 0.001, 0.02)


def s_footstep():
    rng = rng_for(104)
    return fades(remove_dc(footstep_wood(rng)), 0.0005, 0.05)


def s_flashlight_click():
    rng = rng_for(105)
    n = N(0.16)

    def click(seed_amp):
        m = N(0.05)
        tm = tt(m)
        c = modes(m, [3100, 5200, 920], [0.006, 0.003, 0.01], [1, 0.6, 0.5], rng)
        c *= np.clip(tm / 0.0003, 0, 1)
        c += 1.2 * burst(m, rng, 2500, 12000, 0.0001, 0.0008)
        return c * seed_amp

    y = np.zeros(n)
    place(y, click(1.0), 0.005)
    place(y, click(0.6), 0.055)
    return fades(remove_dc(y), 0.0005, 0.02)


def s_camera_shutter():
    rng = rng_for(106)
    y = np.zeros(N(0.55))

    def clk(a, f1, f2, tau):
        m = N(0.06)
        c = modes(m, [f1, f2, f1 * 2.3], [tau, tau * 0.6, tau * 0.4], [1, 0.6, 0.3], rng)
        c *= np.clip(tt(m) / 0.0002, 0, 1)
        c += burst(m, rng, 1500, 10000, 0.0001, 0.0012) * 1.5
        return c * a

    place(y, clk(1.0, 1900, 3400, 0.01), 0.005)
    # curtain swoosh
    m = N(0.05)
    place(y, bp(rng.standard_normal(m), 2000, 8000) * np.sin(np.pi * tt(m) / 0.05) * 0.25, 0.01)
    place(y, clk(0.9, 1500, 2800, 0.014), 0.06)
    # film advance ratchet
    for k in range(9):
        place(y, clk(0.25 + 0.1 * rng.uniform(), 2500, 4600, 0.004), 0.17 + k * 0.026 + rng.uniform(0, 0.004))
    m = N(0.25)
    place(y, lp(rng.standard_normal(m), 900) * np.sin(np.pi * tt(m) / 0.25) * 0.08, 0.16)
    return fades(remove_dc(y), 0.0005, 0.04)


def s_thermometer_tick():
    rng = rng_for(107)
    n = N(0.1)
    t = tt(n)
    y = 0.8 * burst(n, rng, 2000, 9000, 0.0002, 0.0012)
    blip = np.sign(np.sin(2 * np.pi * 3800 * t)) * 0.3 + np.sin(2 * np.pi * 3800 * t)
    blip *= np.clip(t / 0.002, 0, 1) * (t < 0.035) * np.clip((0.035 - t) / 0.004, 0, 1)
    y += 0.35 * lp(blip, 9000)
    return fades(remove_dc(y), 0.0005, 0.02)


def emf_tone(dur, f, rng):
    n = N(dur)
    t = tt(n)
    y = np.sin(2 * np.pi * f * t) + 0.18 * np.sin(2 * np.pi * 3 * f * t) + 0.08 * np.sin(2 * np.pi * 5 * f * t)
    a = N(0.003)
    env = np.ones(n)
    env[:a] = np.linspace(0, 1, a)
    env[-a:] = np.linspace(1, 0, a)
    return y * env


def s_emf_beep():
    rng = rng_for(108)
    y = emf_tone(0.08, 2050, rng)
    return remove_dc(y)


def s_emf_spike():
    rng = rng_for(109)
    dur = 0.8
    y = np.zeros(N(dur))
    tcur = 0.0
    while tcur < dur - 0.03:
        p = tcur / dur
        f = 1500 * (3300 / 1500) ** p * (1 + rng.uniform(-0.02, 0.02))
        bl = 0.045 - 0.025 * p
        place(y, emf_tone(bl, f, rng) * (0.7 + 0.3 * p), tcur)
        tcur += max(0.022, 0.095 * (1 - p) ** 1.6) + bl * 0.3
    n = len(y)
    t = tt(n)
    # interference crackle growing
    crackle = (rng.uniform(0, 1, n) < 0.004 * (t / dur)) * rng.uniform(-1, 1, n)
    y += 0.5 * hp(crackle, 1500)
    y += 0.06 * (t / dur) * bp(rng.standard_normal(n), 1000, 6000)
    return fades(remove_dc(y), 0.001, 0.02)


def s_spirit_box_static():
    rng = rng_for(110)
    dur = 2.0
    L = N(dur)
    t = tt(L)
    noise = rng.standard_normal(L)
    # station steps: every 1/12 s the "tuner" lands on a different band
    seg = L // 24
    out = np.zeros(L)
    bands = []
    for k in range(24):
        lo = rng.uniform(300, 1500)
        hi = lo * rng.uniform(2.0, 5.0)
        bands.append((lo, hi, rng.uniform(0.6, 1.0)))
    # pre-filter a small bank of circularly filtered static colours
    bank = [bp(noise, lo, hi, 2, circular=True) for lo, hi, _ in bands]
    bank = [b / (np.std(b) + 1e-12) for b in bank]
    win_x = N(0.006)
    for k in range(24):
        g = np.zeros(L)
        a, b = k * seg, (k + 1) * seg
        g[a:b] = 1.0
        out += bank[k] * g * bands[k][2]
    # smooth the hard steps a little but keep the choppy character (circular)
    out = fft_filter(out, lambda f: g_lp(f, 7000, 2), circular=True)
    step_env = np.ones(L)
    for k in range(24):
        i = k * seg
        idx = (np.arange(-win_x, win_x) + i) % L
        step_env[idx] *= np.abs(np.linspace(-1, 1, 2 * win_x)) ** 0.5 * 0.7 + 0.3
    out *= step_env
    # broadband hiss bed
    out += 0.25 * hp(rng.standard_normal(L), 3000, 2, circular=True)
    # 50 Hz-ish carrier hum, whole cycles per loop
    out += 0.08 * np.sin(2 * np.pi * 50 * t) + 0.04 * np.sin(2 * np.pi * 150 * t)
    # tuning blips / heterodyne whistles (events folded)
    ev = np.zeros(L + N(0.3))
    for k in range(24):
        if rng.uniform() < 0.55:
            d = rng.uniform(0.03, 0.07)
            f0 = rng.uniform(600, 2500)
            f1 = f0 * rng.uniform(0.6, 1.6)
            m = N(d)
            bl = chirp_tone(m, f0, f1, d * 2, "lin") * np.sin(np.pi * tt(m) / d)
            place(ev, bl * rng.uniform(0.25, 0.55), k * seg / SR + rng.uniform(0, 0.03))
    out = out + fold(ev, L)
    # periodic AM flutter (whole cycles)
    out *= 1 + 0.25 * np.sin(2 * np.pi * 11 * t) * np.sin(2 * np.pi * 1.5 * t)
    out = np.tanh(out * 0.9)
    return remove_dc(out, circular=True)


def s_spirit_box_voice():
    rng = rng_for(111)
    dur = 1.3
    # "...be...hind...you" -- warped, slowed
    v = voice(1.1,
              [(0, 135), (0.3, 120), (0.6, 112), (1.1, 88)],
              [(0, "h"), (0.08, "i"), (0.22, "a"), (0.42, "i"), (0.55, "m"),
               (0.7, "u"), (0.95, "u"), (1.1, "u")],
              [(0, 0), (0.05, 0.6), (0.2, 1), (0.32, 0.25), (0.42, 0.9),
               (0.55, 0.4), (0.68, 1.0), (0.95, 0.7), (1.1, 0)],
              rng, breath=[(0, 0.9), (0.2, 0.45), (1.1, 0.6)], vib_depth=0.03,
              vib_rate=3.0, jitter=0.03, fshift=0.88, rough=0.3)
    y = fit(v, dur)
    n = len(y)
    t = tt(n)
    # radio band-limit + saturation
    y = bp(y, 350, 3200, 3)
    y = np.tanh(3.0 * y / (np.max(np.abs(y)) + 1e-9))
    # spirit-box chopping (sweep gate) at ~14 Hz, partly open
    gate = 0.45 + 0.55 * (np.sin(2 * np.pi * 14 * t + 0.3) > -0.2)
    gate = lp(gate, 300)
    y *= gate
    static = bp(rng.standard_normal(n), 500, 5000) * 0.25
    static *= 0.6 + 0.4 * (1 - gate)
    y = y + static
    y += 0.04 * np.sin(2 * np.pi * 60 * t)
    y = reverb(y, 0.6, 0.18, rng, damp=3000, tail=False)
    return fades(remove_dc(fit(y, dur)), 0.01, 0.12)


def s_whisper_mimic():
    rng = rng_for(112)
    dur = 1.5
    # "help... meee"
    keys_v = [(0, "h"), (0.06, "e"), (0.2, "e"), (0.26, "l"), (0.33, "l"),
              (0.38, "er"), (0.46, "m"), (0.55, "m"), (0.62, "i"), (0.95, "i")]
    amp = [(0, 0), (0.05, 0.7), (0.18, 1), (0.3, 0.6), (0.36, 0.05), (0.43, 0.05),
           (0.47, 0.5), (0.58, 0.8), (0.75, 1.0), (0.95, 0)]
    f0 = [(0, 230), (0.2, 250), (0.45, 215), (0.6, 265), (0.95, 205)]
    a = voice(0.95, f0, keys_v, amp, rng, breath=0.8, vib_depth=0.025, vib_rate=6.5,
              jitter=0.02, fshift=1.12)
    b = voice(0.95, [(k, f * 0.94) for k, f in f0], keys_v, amp, rng, breath=1.0,
              vib_depth=0.035, vib_rate=4.3, jitter=0.03, fshift=1.05) * 0.6
    y = np.zeros(N(dur))
    place(y, a, 0.04)
    place(y, b, 0.07)
    # the "p" plosive
    m = N(0.03)
    place(y, bp(rng.standard_normal(m), 300, 3000) * env_ad(m, 0.001, 0.008) * 0.3, 0.42)
    y = lp(y, 3200, 2)   # distance
    y = reverb(y, 2.2, 0.62, rng, damp=2200, predelay=0.03)
    return fades(remove_dc(fit(y, dur)), 0.005, 0.25)


def s_salt_pour():
    rng = rng_for(113)
    dur = 1.2
    n = N(dur)
    t = tt(n)
    dens = interp_keys([(0, 0), (0.08, 1), (0.85, 1), (1.1, 0.1), (1.2, 0)], t)
    rate = 2500 * dens / SR
    grains = (rng.uniform(0, 1, n) < rate) * rng.uniform(0.1, 1.0, n) ** 2 \
        * np.sign(rng.standard_normal(n))
    g = bp(grains, 2500, 12000, 2)
    # grains landing on wood: tiny resonances
    g += 0.3 * bp(grains, 900, 2500, 2)
    hiss = bp(rng.standard_normal(n), 3000, 10000) * dens * 0.04
    y = g + hiss
    y *= 1 + 0.25 * smooth_noise(n, 8, rng)
    return fades(remove_dc(y), 0.01, 0.1)


def s_place_item():
    rng = rng_for(114)
    n = N(0.35)
    t = tt(n)
    hit = modes(n, [210, 470, 930, 1580], [0.05, 0.03, 0.018, 0.01], [1, 0.6, 0.4, 0.2], rng)
    hit *= np.clip(t / 0.001, 0, 1)
    hit += 0.8 * lp(rng.standard_normal(n), 700) * env_ad(n, 0.0005, 0.012)
    y = hit.copy()
    place(y, hit[: N(0.2)] * 0.25, 0.055)   # small settle rattle
    return fades(remove_dc(y), 0.0005, 0.05)


def s_pickup():
    rng = rng_for(115)
    n = N(0.3)
    t = tt(n)

    def g(f, times):
        fc = 800 + 4000 * np.clip(times / 0.15, 0, 1)
        return np.exp(-(np.log(f + 1) - np.log(fc)) ** 2 / (2 * 0.6 ** 2))

    sw = tv_filter(rng.standard_normal(n), g) * interp_keys([(0, 0), (0.06, 1), (0.16, 0.3), (0.25, 0)], t)
    y = sw * 0.6
    m = N(0.08)
    clk = modes(m, [1200, 2600, 3900], [0.02, 0.01, 0.006], [1, 0.5, 0.3], rng) * np.clip(tt(m) / 0.0005, 0, 1)
    place(y, clk * 0.6, 0.02)
    place(y, clk * 0.3, 0.1)
    return fades(remove_dc(y), 0.002, 0.05)


def s_holy_water_splash():
    rng = rng_for(116)
    dur = 1.1
    n = N(dur)
    t = tt(n)
    splash = bp(rng.standard_normal(n), 500, 7000) * env_ad(n, 0.004, 0.09)
    splash += 0.5 * lp(rng.standard_normal(n), 400) * env_ad(n, 0.002, 0.03)
    y = splash
    # droplets
    for _ in range(45):
        tc = abs(rng.normal(0.08, 0.2))
        place(y, bubble(rng, 700, 3200) * rng.uniform(0.1, 0.4) * np.exp(-tc / 0.5), tc)
    # soft holy sizzle where it lands
    sizz = hp(rng.standard_normal(n), 4000) * (rng.uniform(0, 1, n) < 0.3)
    y += 0.07 * sizz * interp_keys([(0, 0), (0.1, 1), (0.9, 0.2), (1.1, 0)], t)
    y = reverb(y, 0.7, 0.2, rng)
    return fades(remove_dc(fit(y, dur)), 0.001, 0.15)


def sizzle(n, rng, density=0.25, pop_rate=40):
    t = tt(n)
    base = hp(rng.standard_normal(n), 3500) * (rng.uniform(0, 1, n) < density)
    base = bp(base, 3000, 14000)
    flutter = np.clip(1 + 0.6 * smooth_noise(n, 25, rng), 0.1, None)
    pops = (rng.uniform(0, 1, n) < pop_rate / SR) * rng.uniform(-1, 1, n) * 6
    pops = bp(pops, 1500, 9000)
    return base * flutter + pops


def s_crucifix_burn():
    rng = rng_for(117)
    dur = 1.6
    n = N(dur)
    t = tt(n)
    env = interp_keys([(0, 0), (0.03, 1), (0.5, 0.8), (1.6, 0)], t) ** 1.2
    y = sizzle(n, rng, 0.35, 60) * env
    y += 0.25 * lp(rng.standard_normal(n), 300) * env      # burning whoosh body
    # dissonant ghostly flinch tone
    hum = np.sin(2 * np.pi * 311 * t) + 0.7 * np.sin(2 * np.pi * 329.6 * t)
    y += 0.06 * hum * interp_keys([(0, 0), (0.1, 1), (1.2, 0)], t)
    y = reverb(y, 0.8, 0.2, rng)
    return fades(remove_dc(fit(y, dur)), 0.002, 0.2)


def s_stake_strike():
    rng = rng_for(118)
    dur = 0.9
    y = np.zeros(N(dur))
    place(y, thump(0.6, 110, 48, 0.12, rng, 0.6, 400), 0)
    # crack: splinter crackle
    m = N(0.15)
    tm = tt(m)
    cr = np.zeros(m)
    for k in range(14):
        tc = abs(rng.normal(0, 0.03))
        i = N(tc)
        if i < m:
            cr[i] += rng.uniform(-1, 1) * np.exp(-tc / 0.04)
    cr = bp(cr, 1200, 8000) * 3 + bp(rng.standard_normal(m), 1500, 7000) * env_ad(m, 0.0003, 0.012)
    cr += modes(m, [780, 1430, 2350], [0.03, 0.02, 0.012], [0.6, 0.4, 0.3], rng)
    place(y, cr * 0.9, 0.004)
    y = reverb(y, 0.6, 0.15, rng)
    return fades(remove_dc(fit(y, dur)), 0.0005, 0.1)


def s_melt_silver():
    rng = rng_for(119)
    dur = 2.0
    n = N(dur)
    t = tt(n)
    env = interp_keys([(0, 0), (0.15, 1), (1.6, 0.9), (2.0, 0.4)], t)
    y = sizzle(n, rng, 0.2, 25) * env * 0.6
    tc = 0.02
    while tc < dur:
        place(y, bubble(rng, 180, 900, 1.6) * rng.uniform(0.15, 0.6), tc)
        tc += rng.exponential(1 / 28)
    y += 0.2 * lp(rng.standard_normal(n), 150) * env    # boil rumble
    y = reverb(y, 0.5, 0.15, rng)
    return fades(remove_dc(fit(y, dur)), 0.01, 0.3)


def s_mirror_reveal():
    rng = rng_for(120)
    dur = 2.2
    n = N(dur)
    t = tt(n)
    y = np.zeros(n)
    partials = [2093, 3322, 4699, 6272, 8126, 9956]
    for i, f in enumerate(partials):
        a = 1 / (1 + i * 0.5)
        swell = interp_keys([(0, 0), (0.25 + 0.05 * i, 1), (dur, 0)], t) ** 1.5
        y += a * (np.sin(2 * np.pi * f * t) + np.sin(2 * np.pi * (f * 1.0021) * t + i)) * swell * 0.5
    # glass sparkle pings rising
    for k in range(40):
        tc = rng.uniform(0, 1.4)
        f = rng.uniform(2500, 9000) * (1 + tc * 0.3)
        m = N(0.4)
        place(y, np.sin(2 * np.pi * f * tt(m)) * np.exp(-tt(m) / 0.08) * rng.uniform(0.05, 0.25), tc)
    # airy rising whoosh
    def g(f, times):
        fc = 1500 * 2 ** (2.5 * np.clip(times / 0.7, 0, 1))
        return np.exp(-(np.log(f + 1) - np.log(fc)) ** 2 / 0.4)
    y += 0.3 * tv_filter(rng.standard_normal(n), g) * interp_keys([(0, 0), (0.5, 1), (1.0, 0)], t)
    y = reverb(y, 2.0, 0.45, rng, damp=7000)
    return fades(remove_dc(fit(y, dur)), 0.01, 0.4)


def s_candle_light():
    rng = rng_for(121)
    dur = 1.4
    n = N(dur)
    t = tt(n)
    y = np.zeros(n)
    # match strike: rough scrape
    m = N(0.13)
    tm = tt(m)
    sc = bp(rng.standard_normal(m), 1200, 7000) * np.clip(1 + 0.9 * smooth_noise(m, 250, rng), 0, None)
    sc *= interp_keys([(0, 0), (0.01, 1), (0.1, 0.8), (0.13, 0)], tm)
    place(y, sc, 0.0)
    # ignition pop + fffft
    m = N(0.5)
    tm = tt(m)
    ign = 1.2 * bp(rng.standard_normal(m), 400, 9000) * env_ad(m, 0.002, 0.06)
    ign += 0.7 * lp(rng.standard_normal(m), 1500) * env_ad(m, 0.01, 0.15)
    place(y, ign, 0.11)
    # flare: soft whoosh with flicker
    m = N(1.25)
    tm = tt(m)
    fl = lp(rng.standard_normal(m), 600) * env_ad(m, 0.05, 0.4)
    fl *= np.clip(1 + 0.5 * smooth_noise(m, 12, rng), 0.2, None)
    fl += 0.08 * sizzle(m, rng, 0.05, 15) * env_ad(m, 0.05, 0.3)
    place(y, fl * 0.6, 0.15)
    return fades(remove_dc(y), 0.001, 0.2)


def s_door_creak():
    rng = rng_for(122)
    dur = 1.9
    c = creak(1.7, [(0, 90), (0.4, 220), (0.8, 160), (1.2, 340), (1.7, 260)], rng,
              res=(620, 1250, 2600), jit=0.2,
              amp_keys=[(0, 0), (0.1, 0.8), (0.5, 1), (0.9, 0.6), (1.3, 1), (1.7, 0)])
    c2 = creak(1.7, [(0, 45), (0.8, 80), (1.7, 60)], rng, res=(300, 750, 1500), jit=0.3) * 0.4
    y = np.zeros(N(dur))
    place(y, c + c2, 0.0)
    y = reverb(y, 1.0, 0.25, rng)
    return fades(remove_dc(fit(y, dur)), 0.01, 0.2)


def s_poltergeist_bang():
    rng = rng_for(123)
    dur = 1.6
    n = N(dur)
    y = np.zeros(n)

    # throw whoosh
    m = N(0.18)
    def g(f, times):
        fc = 600 + 2500 * np.clip(times / 0.18, 0, 1)
        return np.exp(-(np.log(f + 1) - np.log(fc)) ** 2 / 0.5)
    place(y, tv_filter(rng.standard_normal(m), g) * np.sin(np.pi * tt(m) / 0.18) ** 2 * 0.35, 0)
    # impact
    t0 = 0.17
    place(y, thump(0.6, 120, 55, 0.1, rng, 1.0, 600) * 1.0, t0)
    m = N(0.4)
    crash = bp(rng.standard_normal(m), 500, 9000) * env_ad(m, 0.001, 0.05)
    place(y, crash * 0.9, t0)
    # ceramic shards
    for _ in range(18):
        tc = t0 + abs(rng.normal(0.02, 0.12))
        mm = N(0.2)
        fs = rng.uniform(2500, 7500)
        sh = modes(mm, [fs, fs * 1.47, fs * 2.13], [0.03, 0.02, 0.01], [1, 0.5, 0.3], rng)
        sh *= np.clip(tt(mm) / 0.0003, 0, 1)
        place(y, sh * rng.uniform(0.1, 0.4), tc)
    # debris clatter: bounces getting closer together
    tb, amp = t0 + 0.18, 0.5
    while amp > 0.05 and tb < dur - 0.2:
        mm = N(0.12)
        fb = rng.uniform(300, 900)
        b = modes(mm, [fb, fb * 2.3, fb * 3.9], [0.03, 0.02, 0.01], [1, 0.5, 0.3], rng)
        b *= np.clip(tt(mm) / 0.0005, 0, 1)
        place(y, b * amp, tb)
        tb += rng.uniform(0.06, 0.16) * amp * 2
        amp *= 0.72
    y = reverb(y, 1.2, 0.28, rng)
    return fades(remove_dc(fit(y, dur)), 0.001, 0.2)


def s_ghost_wail():
    rng = rng_for(124)
    dur = 2.0
    f0 = [(0, 300), (0.5, 520), (0.9, 610), (1.3, 450), (1.7, 260)]
    vk = [(0, "u"), (0.5, "o"), (0.9, "a"), (1.3, "o"), (1.7, "u")]
    amp = [(0, 0), (0.35, 0.8), (0.9, 1), (1.4, 0.6), (1.7, 0)]
    a = voice(1.7, f0, vk, amp, rng, breath=0.35, vib_depth=0.03, vib_rate=5.5, jitter=0.01,
              fshift=1.1, tilt=1.3)
    b = voice(1.7, [(k, f * 1.06) for k, f in f0], vk, amp, rng, breath=0.5, vib_depth=0.04,
              vib_rate=4.1, fshift=1.05, tilt=1.4) * 0.5
    y = fit(a + b, dur)
    y = lp(y, 5000)
    y = reverb(y, 2.4, 0.55, rng, damp=3000, predelay=0.03)
    return fades(remove_dc(fit(y, dur)), 0.01, 0.3)


def s_hunt_start():
    rng = rng_for(125)
    dur = 2.5
    n = N(dur)
    t = tt(n)
    y = np.zeros(n)
    boom = thump(2.0, 70, 30, 0.6, rng, 0.8, 200) * 1.4
    boom += 0.5 * lp(rng.standard_normal(N(2.0)), 120) * env_ad(N(2.0), 0.005, 0.5)
    place(y, boom, 0)
    # rising dissonant cluster
    rise = interp_keys([(0, 0), (0.15, 0), (2.2, 1), (2.5, 1)], t)
    cluster = np.zeros(n)
    for r in (1.0, 1.059, 1.122, 1.414, 1.498, 2.12):
        f = 330 * r * 2 ** (1.7 * rise) * (1 + 0.004 * smooth_noise(n, 6, rng))
        ph = 2 * np.pi * np.cumsum(f) / SR
        saw = sum(np.sin(k * ph) / k for k in range(1, 8))
        cluster += saw
    cluster *= interp_keys([(0, 0), (0.2, 0.05), (2.2, 1), (2.5, 0.9)], t) ** 1.5
    cluster *= 1 + 0.35 * np.sin(2 * np.pi * interp_keys([(0, 5), (2.5, 14)], t) * t)
    cluster = bp(cluster, 200, 6000)
    y += 0.35 * cluster / (np.max(np.abs(cluster)) + 1e-9)
    # shriek voice on top
    sh = voice(2.3, [(0, 600), (1.2, 900), (2.3, 1500)], [(0, "a"), (1.5, "e"), (2.3, "i")],
               [(0, 0), (0.8, 0.1), (2.1, 1), (2.3, 1)], rng, breath=0.6, vib_depth=0.05,
               vib_rate=7, jitter=0.03, fshift=1.3, rough=0.4)
    sh = np.tanh(2 * sh / (np.max(np.abs(sh)) + 1e-9))
    place(y, 0.4 * sh, 0.2)
    y = reverb(y, 2.0, 0.35, rng)
    return fades(remove_dc(fit(y, dur)), 0.001, 0.08)


def s_hunt_loop():
    rng = rng_for(126)
    dur = 4.0
    L = N(dur)
    t = tt(L)
    ev = np.zeros(L + N(1.0))
    # 120 bpm heartbeat: 8 beats in 4 s
    for k in range(8):
        place(ev, heartbeat(rng, 1.0 + 0.05 * rng.uniform(-1, 1)), k * 0.5)
    hb = fold(ev, L)
    # low dissonant drone (frequencies are multiples of 1/4 Hz => periodic)
    drone = np.zeros(L)
    for f, a in ((55.0, 1.0), (58.25, 0.8), (77.75, 0.5), (110.0, 0.25), (116.5, 0.2), (164.75, 0.12)):
        drone += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28))
    drone *= 1 + 0.2 * np.sin(2 * np.pi * 0.5 * t)
    # dark breathy noise texture (circular)
    tex = bp(rng.standard_normal(L), 200, 900, 2, circular=True)
    tex *= 0.5 + 0.5 * np.sin(2 * np.pi * 0.25 * t) ** 2
    y = hb * 1.0 + 0.3 * drone + 0.08 * tex
    y = reverb(y, 1.2, 0.2, rng, circular=True)
    return remove_dc(y, circular=True)


def s_vampire_hiss():
    rng = rng_for(127)
    dur = 1.2
    n = N(dur)
    t = tt(n)
    env = interp_keys([(0, 0), (0.06, 1), (0.7, 0.85), (1.1, 0)], t)
    def g(f, times):
        return (g_bp(f, 2500, 9000, 2) + 0.6 * g_peak(f, 4200, 1500)
                + 0.3 * g_peak(f, 1500 + 500 * times / dur, 600))
    y = tv_filter(rng.standard_normal(n), g) * env
    y *= np.clip(1 + 0.5 * smooth_noise(n, 45, rng), 0.1, None)
    growl = voice(1.0, [(0, 70), (1.0, 60)], [(0, "a"), (1.0, "o")],
                  [(0, 0), (0.1, 1), (0.8, 0.6), (1.0, 0)], rng, breath=0.5, jitter=0.08,
                  rough=0.8, sub=0.6, fshift=0.75)
    y += 0.25 * fit(growl, dur) / (np.max(np.abs(growl)) + 1e-9) * np.max(np.abs(y))
    y = reverb(y, 0.8, 0.2, rng)
    return fades(remove_dc(fit(y, dur)), 0.005, 0.15)


def s_werewolf_howl():
    rng = rng_for(128)
    dur = 2.5
    f0 = [(0, 240), (0.35, 470), (0.6, 520), (1.6, 545), (1.9, 470), (2.1, 300)]
    vk = [(0, "u"), (0.35, "o"), (0.8, "a"), (1.5, "o"), (1.9, "u"), (2.1, "u")]
    amp = [(0, 0), (0.3, 0.9), (0.6, 1), (1.7, 0.95), (2.1, 0)]
    a = voice(2.1, f0, vk, amp, rng, breath=0.25, vib_depth=[(0, 0), (0.8, 0.005), (1.6, 0.02)],
              vib_rate=5.5, jitter=0.012, fshift=0.92, rough=0.25)
    b = voice(2.1, [(k, f * 0.997) for k, f in f0], vk, amp, rng, breath=0.3,
              vib_depth=0.012, vib_rate=4.2, fshift=0.9, rough=0.3) * 0.5
    y = fit(a + b, dur)
    y = reverb(y, 2.8, 0.4, rng, damp=3500, predelay=0.04)
    return fades(remove_dc(fit(y, dur)), 0.01, 0.35)


def s_werewolf_growl():
    rng = rng_for(129)
    dur = 1.5
    g = voice(1.4, [(0, 85), (0.5, 72), (1.4, 64)], [(0, "o"), (0.6, "a"), (1.4, "o")],
              [(0, 0), (0.12, 1), (0.9, 0.85), (1.4, 0)], rng, breath=0.6, jitter=0.12,
              rough=1.0, sub=0.9, fshift=0.7, tilt=0.8)
    n = len(g)
    g *= 1 + 0.6 * np.sin(2 * np.pi * 23 * tt(n)) * (1 + 0.3 * smooth_noise(n, 5, rng))
    g = np.tanh(2.5 * g / (np.max(np.abs(g)) + 1e-9))
    g = lp(g, 3500)
    y = reverb(fit(g, dur), 0.7, 0.15, rng)
    return fades(remove_dc(fit(y, dur)), 0.01, 0.15)


def s_shapeshift():
    rng = rng_for(130)
    dur = 1.6
    n = N(dur)
    t = tt(n)
    def g(f, times):
        fc = 250 * 2 ** (3.5 * np.sin(np.pi * np.clip(times / 1.4, 0, 1)))
        return np.exp(-(np.log(f + 1) - np.log(fc)) ** 2 / 0.25) + 0.05
    wh = tv_filter(rng.standard_normal(n), g)
    wh *= interp_keys([(0, 0), (0.3, 1), (1.1, 0.9), (1.5, 0)], t)
    y = wh * 0.8
    # wet squelches
    tc = 0.1
    while tc < 1.35:
        place(y, bubble(rng, 120, 500, 2.5) * rng.uniform(0.3, 0.8), tc)
        tc += rng.exponential(0.05)
    # bone cracks
    for tc in (0.35, 0.62, 0.66, 0.95):
        m = N(0.05)
        place(y, burst(m, rng, 800, 7000, 0.0002, 0.004) * 1.0
              + 0.4 * modes(m, [1100, 2300], [0.01, 0.006], [1, 0.5], rng), tc)
    # bending low tone
    f = interp_keys([(0, 90), (0.7, 45), (1.4, 120)], t, log=True)
    y += 0.25 * np.sin(2 * np.pi * np.cumsum(f) / SR) * interp_keys([(0, 0), (0.3, 1), (1.4, 0)], t)
    y = reverb(y, 0.9, 0.2, rng)
    return fades(remove_dc(fit(y, dur)), 0.01, 0.2)


def s_cat_meow():
    rng = rng_for(131)
    dur = 1.4
    f0 = [(0, 480), (0.15, 820), (0.45, 900), (0.75, 560), (1.0, 300)]
    vk = [(0, "i"), (0.15, "e"), (0.4, "a"), (0.7, "o"), (1.0, "u")]
    amp = [(0, 0), (0.08, 0.8), (0.4, 1), (0.8, 0.6), (1.0, 0)]
    a = voice(1.0, f0, vk, amp, rng, breath=0.15, vib_depth=[(0, 0.005), (0.7, 0.03)],
              vib_rate=6.5, jitter=0.02, fshift=1.55, tilt=1.1)
    # unsettling: a faint voice an octave below that lags and droops
    b = voice(1.0, [(k, f * 0.5 * (1 - 0.15 * k)) for k, f in f0], vk, amp, rng, breath=0.3,
              vib_depth=0.03, vib_rate=3, fshift=1.1) * 0.3
    y = np.zeros(N(dur))
    place(y, a, 0)
    place(y, b, 0.06)
    y = reverb(y, 1.2, 0.3, rng)
    return fades(remove_dc(fit(y, dur)), 0.005, 0.25)


def s_harbinger_arrival():
    rng = rng_for(132)
    dur = 5.0
    n = N(dur)
    t = tt(n)
    y = np.zeros(n)
    # sub boom
    place(y, thump(3.0, 55, 26, 1.0, rng, 0.8, 120) * 1.2, 0)
    # tolling bells
    place(y, bell(98, 5.0, rng) * 0.7, 0.0)
    place(y, bell(98, 3.0, rng) * 0.6, 2.2)
    # rising choir-like detuned drone
    choir = np.zeros(n)
    base = [110, 130.8, 155.6, 164.8, 220, 233.1]
    for i, f in enumerate(base):
        fk = [(0, f), (1.0, f), (4.3, f * 2 ** (rng.uniform(5, 8) / 12))]
        v = voice(4.4, fk, [(0, "o"), (2.5, "a"), (4.4, "e")],
                  [(0, 0), (0.6, 0.15), (3.8, 1), (4.4, 1)], rng, breath=0.2,
                  vib_depth=0.008, vib_rate=rng.uniform(4.5, 5.8), jitter=0.006,
                  fshift=rng.uniform(0.95, 1.05))
        place(choir, v * (1 + 0.1 * i), 0.2)
    choir /= np.max(np.abs(choir)) + 1e-9
    y += 0.55 * choir
    # ending shriek
    sh = voice(0.85, [(0, 700), (0.5, 1500), (0.85, 1700)], [(0, "a"), (0.4, "i"), (0.85, "i")],
               [(0, 0), (0.1, 0.6), (0.5, 1), (0.85, 0.7)], rng, breath=0.7, vib_depth=0.06,
               vib_rate=8, jitter=0.04, fshift=1.35, rough=0.5)
    sh = np.tanh(2.5 * sh / (np.max(np.abs(sh)) + 1e-9))
    place(y, sh * 0.6, 4.05)
    m = N(0.9)
    place(y, hp(rng.standard_normal(m), 2500) * interp_keys([(0, 0), (0.5, 1), (0.9, 0.6)], tt(m)) * 0.15, 4.05)
    y = reverb(y, 3.0, 0.35, rng, damp=3500, predelay=0.03)
    return fades(remove_dc(fit(y, dur)), 0.001, 0.25)


def s_reckless_reaction():
    rng = rng_for(133)
    dur = 3.0
    n = N(dur)
    t = tt(n)
    y = np.zeros(n)
    rumble = lp(rng.standard_normal(n), 90, 3) * interp_keys([(0, 0), (0.8, 1), (2.2, 0.8), (3.0, 0)], t)
    y += rumble * 3.0
    g1 = creak(2.4, [(0, 18), (0.8, 30), (1.6, 22), (2.4, 35)], rng, res=(180, 420, 900), jit=0.35,
               amp_keys=[(0, 0), (0.4, 1), (1.2, 0.6), (1.9, 1), (2.4, 0)])
    place(y, g1 * 1.0, 0.1)
    g2 = creak(1.3, [(0, 60), (0.6, 110), (1.3, 80)], rng, res=(400, 900, 1800), jit=0.25)
    place(y, g2 * 0.5, 1.0)
    place(y, lp(thump(1.0, 80, 40, 0.15, rng, 1.0, 300), 400) * 1.5, 1.6)
    wh = whisper(0.7, [(0, "h"), (0.15, "e"), (0.4, "u"), (0.7, "h")],
                 [(0, 0), (0.1, 1), (0.5, 0.8), (0.7, 0)], rng)
    place(y, wh * 0.35, 2.1)
    y = reverb(y, 2.0, 0.4, rng, damp=2000, predelay=0.03)
    return fades(remove_dc(fit(y, dur)), 0.02, 0.3)


def s_player_hurt():
    rng = rng_for(134)
    dur = 0.7
    y = np.zeros(N(dur))
    gr = voice(0.32, [(0, 170), (0.1, 150), (0.32, 110)], [(0, "a"), (0.15, "er"), (0.32, "u")],
               [(0, 0), (0.02, 1), (0.15, 0.7), (0.32, 0)], rng, breath=0.4, jitter=0.04,
               rough=0.5, fshift=0.95)
    gr = np.tanh(2 * gr / (np.max(np.abs(gr)) + 1e-9))
    place(y, gr * 0.8, 0.01)
    place(y, thump(0.3, 140, 60, 0.06, rng, 0.8, 500) * 0.9, 0.0)
    m = N(0.6)
    ring = np.sin(2 * np.pi * 3200 * tt(m)) * env_ad(m, 0.01, 0.2) * 0.06
    place(y, ring, 0.02)
    y = reverb(y, 0.5, 0.12, rng)
    return fades(remove_dc(fit(y, dur)), 0.0005, 0.1)


def s_player_death():
    rng = rng_for(135)
    dur = 2.6
    n = N(dur)
    t = tt(n)
    y = np.zeros(n)
    place(y, thump(2.0, 60, 28, 0.7, rng, 0.8, 150) * 1.2, 0)
    groan = voice(1.6, [(0, 140), (0.6, 110), (1.6, 70)], [(0, "a"), (0.7, "o"), (1.6, "u")],
                  [(0, 0), (0.05, 1), (0.8, 0.6), (1.6, 0)], rng,
                  breath=[(0, 0.5), (1.6, 1.0)], jitter=0.05, rough=0.4, fshift=0.92)
    place(y, groan * 0.5 / (np.max(np.abs(groan)) + 1e-9), 0.05)
    # final heartbeats slowing
    place(y, heartbeat(rng, 0.8), 0.9)
    place(y, heartbeat(rng, 0.5), 1.75)
    ring = np.sin(2 * np.pi * 4100 * t) * interp_keys([(0, 0), (0.1, 1), (2.6, 0)], t) * 0.05
    y += ring
    y = reverb(y, 1.6, 0.3, rng, damp=2500)
    return fades(remove_dc(fit(y, dur)), 0.0005, 0.3)


def scream_post(v, dur, rng, drive=2.0, lpf=4200, rt=2.2, wet=0.55):
    v = np.tanh(drive * v / (np.max(np.abs(v)) + 1e-9))
    y = fit(np.concatenate([np.zeros(N(0.03)), v]), dur)
    y = lp(y, lpf)
    y = reverb(y, rt, wet, rng, damp=2600, predelay=0.04)
    return fades(remove_dc(fit(y, dur)), 0.005, 0.3)


def s_scream_1():
    rng = rng_for(136)
    v = voice(1.3, [(0, 600), (0.2, 900), (0.8, 980), (1.3, 700)], [(0, "ae"), (0.3, "a"), (1.3, "a")],
              [(0, 0), (0.1, 1), (0.9, 0.9), (1.3, 0)], rng, breath=0.35, vib_depth=0.03,
              vib_rate=7.5, jitter=0.025, fshift=1.25, rough=0.5)
    return scream_post(v, 1.9, rng, 2.2)


def s_scream_2():
    rng = rng_for(137)
    f0 = [(0, 1300), (0.5, 1000), (1.2, 550), (1.6, 300)]
    vk = [(0, "i"), (0.6, "e"), (1.2, "o"), (1.6, "u")]
    amp = [(0, 0), (0.05, 1), (1.0, 0.8), (1.6, 0)]
    a = voice(1.6, f0, vk, amp, rng, breath=0.45, vib_depth=0.07, vib_rate=9, jitter=0.03,
              fshift=1.4, rough=0.3)
    b = voice(1.6, [(k, f * 1.07) for k, f in f0], vk, amp, rng, breath=0.5, vib_depth=0.08,
              vib_rate=6.3, fshift=1.3, rough=0.3) * 0.7
    return scream_post(a + b, 2.3, rng, 1.8, 5000, 2.6, 0.6)


def s_scream_3():
    rng = rng_for(138)
    v = np.zeros(N(1.6))
    # stuttering "ah-ah-AAAH" with a three-voice cluster
    for i, (st, ln, f) in enumerate([(0.0, 0.16, 480), (0.22, 0.16, 520), (0.45, 1.1, 560)]):
        for r, a in ((1.0, 1.0), (1.122, 0.6), (0.749, 0.5)):
            fk = [(0, f * r), (ln * 0.5, f * r * 1.15), (ln, f * r * (0.8 if i == 2 else 1.0))]
            seg = voice(ln, fk, [(0, "a"), (ln, "o" if i == 2 else "a")],
                        [(0, 0), (0.03, 1), (ln * 0.7, 0.9), (ln, 0)], rng, breath=0.3,
                        vib_depth=0.04, vib_rate=rng.uniform(5, 8), jitter=0.03, fshift=1.15,
                        rough=0.6)
            place(v, seg * a, st)
    return scream_post(v, 2.1, rng, 2.4, 3800, 2.0, 0.55)


def s_npc_gasp():
    rng = rng_for(139)
    dur = 0.6
    g = voice(0.42, [(0, 260), (0.42, 330)], [(0, "h"), (0.15, "ae"), (0.42, "a")],
              [(0, 0), (0.05, 0.6), (0.2, 1), (0.42, 0)], rng,
              breath=[(0, 1.5), (0.2, 1.0), (0.42, 0.8)], voiced=[(0, 0), (0.15, 0.1), (0.3, 0.6), (0.42, 0.2)],
              jitter=0.03, fshift=1.1)
    y = reverb(fit(g, dur), 0.5, 0.12, rng)
    return fades(remove_dc(fit(y, dur)), 0.005, 0.1)


def s_npc_flee():
    rng = rng_for(140)
    dur = 1.6
    y = np.zeros(N(dur))
    yelp = voice(0.28, [(0, 420), (0.08, 640), (0.28, 520)], [(0, "ae"), (0.1, "a"), (0.28, "o")],
                 [(0, 0), (0.02, 1), (0.18, 0.7), (0.28, 0)], rng, breath=0.3, jitter=0.03,
                 rough=0.3, fshift=1.1)
    place(y, yelp * 0.8 / (np.max(np.abs(yelp)) + 1e-9), 0)
    for k in range(7):
        st = footstep_wood(rng, soft=max(0.1, 1 - k * 0.15))
        st /= np.max(np.abs(st)) + 1e-9
        place(y, st * 0.7 * (0.88 ** k), 0.22 + k * 0.17 + rng.uniform(-0.01, 0.01))
    y = reverb(y, 0.8, 0.2, rng)
    return fades(remove_dc(fit(y, dur)), 0.002, 0.15)


def s_vanquish_success():
    rng = rng_for(141)
    dur = 3.0
    n = N(dur)
    t = tt(n)
    y = np.zeros(n)
    chord = [62, 66, 69, 74, 76, 81]   # D major add9
    for i, m in enumerate(chord):
        f = midi_hz(m)
        env = interp_keys([(0, 0), (0.25 + 0.05 * i, 1), (dur, 0)], t) ** 1.6
        tone = np.zeros(n)
        for h, a in ((1, 1), (2, 0.3), (3, 0.12), (4, 0.06)):
            tone += a * (np.sin(2 * np.pi * f * h * t) + np.sin(2 * np.pi * f * h * 1.003 * t + 1))
        tone *= 1 + 0.3 * np.sin(2 * np.pi * (6 + i * 0.7) * t)   # shimmer
        y += tone * env / (1 + i * 0.2)
    # dissipation: closing lowpass
    def g(f, times):
        fc = 8000 * 2 ** (-3 * np.clip(times / dur, 0, 1))
        return g_lp(f, fc, 2)
    y = tv_filter(y, g)
    # sparkle grains rising
    for _ in range(50):
        tc = rng.uniform(0.0, 2.2)
        m = N(0.3)
        f = midi_hz(rng.choice([86, 90, 93, 98, 100, 102])) * (1 + 0.002 * rng.standard_normal())
        place(y, np.sin(2 * np.pi * f * tt(m)) * np.exp(-tt(m) / 0.07) * rng.uniform(0.1, 0.35) * (1 - tc / 2.5), tc)
    # rising airy whoosh (spirit leaving)
    def gw(f, times):
        fc = 600 * 2 ** (3.5 * np.clip(times / 1.5, 0, 1))
        return np.exp(-(np.log(f + 1) - np.log(fc)) ** 2 / 0.4)
    y += 0.5 * tv_filter(rng.standard_normal(n), gw) * interp_keys([(0, 0), (0.4, 1), (1.6, 0)], t)
    y = reverb(y, 2.5, 0.45, rng, damp=6000)
    return fades(remove_dc(fit(y, dur)), 0.01, 0.5)


def timpani(f, rng, dur=1.5, tau=0.5):
    n = N(dur)
    t = tt(n)
    y = modes(n, [f, f * 1.5, f * 1.98, f * 2.44], [tau, tau * 0.6, tau * 0.4, tau * 0.3],
              [1, 0.5, 0.35, 0.2], rng)
    y *= np.clip(t / 0.003, 0, 1)
    y += 0.6 * lp(rng.standard_normal(n), 500) * env_ad(n, 0.001, 0.04)
    return y


def chord_organ(midis, dur, rng, attack=0.05, release=0.6, bright=1.0):
    out = None
    for m in midis:
        o = organ_tone(midi_hz(m), dur, rng, attack, release, bright)
        out = o if out is None else out + o
    return out / len(midis)


def s_results_win():
    rng = rng_for(142)
    dur = 3.0
    y = np.zeros(N(dur))
    place(y, chord_organ([50, 57, 62, 65, 69], 0.55, rng, 0.03, 0.3), 0.0)   # D minor
    place(y, timpani(midi_hz(38), rng, 1.0, 0.4), 0.0)
    place(y, chord_organ([46, 58, 62, 65, 70], 0.55, rng, 0.03, 0.3), 0.6)   # Bb major
    place(y, timpani(midi_hz(34), rng, 1.0, 0.4) * 0.7, 0.6)
    place(y, chord_organ([38, 50, 57, 62, 66, 69, 74], 1.4, rng, 0.04, 0.8, 1.2), 1.2)  # D major (picardy)
    place(y, timpani(midi_hz(38), rng, 1.5, 0.6) * 1.1, 1.2)
    place(y, bell(midi_hz(74) / 2, 1.8, rng) * 0.35, 1.2)
    y = reverb(y, 2.2, 0.35, rng, damp=4500)
    return fades(remove_dc(fit(y, dur)), 0.002, 0.4)


def s_results_lose():
    rng = rng_for(143)
    dur = 3.0
    y = np.zeros(N(dur))
    place(y, timpani(midi_hz(33), rng, 2.0, 0.8) * 1.2, 0.0)
    place(y, thump(2.0, 50, 28, 0.7, rng, 0.5, 120), 0.0)
    place(y, chord_organ([38, 45, 50, 53, 57], 0.9, rng, 0.04, 0.4, 0.8), 0.0)    # D minor
    place(y, chord_organ([37, 44, 49, 52, 56], 0.9, rng, 0.06, 0.4, 0.8), 0.85)   # slides down a semitone
    place(y, chord_organ([32, 44, 47, 50, 53], 1.0, rng, 0.08, 0.9, 0.7), 1.65)   # Ab dim-ish (tritone)
    place(y, timpani(midi_hz(32), rng, 1.5, 0.7), 1.65)
    place(y, bell(65, 1.4, rng, 0.5) * 0.4, 1.65)
    y = lp(y, 5000)
    y = reverb(y, 2.4, 0.35, rng, damp=3000)
    return fades(remove_dc(fit(y, dur)), 0.002, 0.4)


def s_ambience_house():
    rng = rng_for(144)
    dur = 10.0
    L = N(dur)
    t = tt(L)
    # wind: several circular-filtered noise bands with periodic gusts (whole cycles per loop)
    wind = np.zeros(L)
    for lo, hi, a, cyc in ((120, 450, 1.0, 1), (300, 900, 0.6, 2), (700, 1800, 0.25, 3), (1500, 3500, 0.08, 5)):
        band = bp(rng.standard_normal(L), lo, hi, 2, circular=True)
        ph = rng.uniform(0, 6.28)
        gust = 0.55 + 0.45 * np.sin(2 * np.pi * cyc * t / dur + ph) * np.sin(2 * np.pi * (cyc + 1) * t / dur + ph * 0.5)
        wind += a * band * gust
    # whistle through a gap: narrow band moving slowly (periodic)
    whis = fft_filter(rng.standard_normal(L), lambda f: g_peak(f, 820, 40), circular=True)
    whis *= np.clip(np.sin(2 * np.pi * 2 * t / dur), 0, None) ** 3
    wind += 0.6 * whis / (np.std(whis) + 1e-9) * np.std(wind) * 0.4
    # very low drone; frequencies snapped to multiples of 0.1 Hz (periodic over 10 s)
    drone = 0.6 * np.sin(2 * np.pi * 41.2 * t) + 0.4 * np.sin(2 * np.pi * 41.5 * t) \
        + 0.2 * np.sin(2 * np.pi * 61.7 * t) + 0.1 * np.sin(2 * np.pi * 82.4 * t)
    drone *= 0.8 + 0.2 * np.sin(2 * np.pi * t / dur)
    # occasional creaks and ticks (events folded across the seam)
    ev = np.zeros(L + N(3.0))
    place(ev, creak(0.9, [(0, 70), (0.5, 140), (0.9, 100)], rng, jit=0.25) * 0.5, 2.3)
    place(ev, creak(0.6, [(0, 160), (0.6, 260)], rng, res=(800, 1600, 3000)) * 0.3, 6.8)
    place(ev, creak(1.2, [(0, 30), (1.2, 50)], rng, res=(220, 500, 1100), jit=0.4) * 0.6, 9.3)  # crosses seam
    m = N(0.2)
    place(ev, modes(m, [900, 1700], [0.02, 0.01], [1, 0.5], rng) * np.clip(tt(m) / 0.0005, 0, 1) * 0.3, 4.6)
    place(ev, modes(m, [600, 1300], [0.03, 0.015], [1, 0.4], rng) * np.clip(tt(m) / 0.0005, 0, 1) * 0.25, 8.1)
    evf = fold(ev, L)
    evf = reverb(evf, 1.4, 0.45, rng, damp=2500, circular=True)
    ws = np.std(wind)
    y = wind / ws * 0.5 + drone * 0.25 + evf / (np.max(np.abs(evf)) + 1e-9) * 1.2
    return remove_dc(y, circular=True)


def s_music_menu():
    rng = rng_for(145)
    beat = 1.0               # 60 bpm, 3/4, 8 bars = 24 s
    dur = 24.0
    L = N(dur)
    t = tt(L)
    buf = np.zeros(L + N(6.0))
    # melody (beat, midi, length) in A minor
    mel = [
        (0, 76), (1, 72), (2, 69),
        (3, 77), (4, 76), (5, 72),
        (6, 74), (7, 77), (8, 81),
        (9, 80), (11, 76),
        (12, 76), (13, 72), (13.5, 74), (14, 76),
        (15, 77), (16, 72), (17, 69),
        (18, 74), (19, 72), (19.5, 71), (20, 68),
        (21, 69), (22.5, 64),
    ]
    for b, m in mel:
        vel = 0.9 if (b % 3 == 0) else 0.7
        vel *= rng.uniform(0.9, 1.05)
        # slight rubato-free mechanical timing with tiny jitter like a worn music box
        place(buf, music_box_note(midi_hz(m), 3.5, rng, vel), b * beat + rng.uniform(0, 0.008))
        # ghostly octave echo
        if rng.uniform() < 0.35:
            place(buf, music_box_note(midi_hz(m + 12), 2.0, rng, vel * 0.2), b * beat + 0.5)
    # organ pad chords per bar
    chords = [[57, 60, 64], [53, 57, 60], [50, 57, 62, 65], [52, 56, 59, 64],
              [57, 60, 64], [53, 57, 60], [50, 53, 57, 62], [57, 60, 64]]
    for i, ch in enumerate(chords):
        pad = chord_organ([c - 12 for c in ch], 3.0 * beat, rng, attack=0.8, release=1.5, bright=0.4)
        place(buf, pad * 0.5, i * 3 * beat)
    # bar 7 second half: E major (harmonic minor tension)
    place(buf, chord_organ([40, 44, 47, 52], 1.0, rng, 0.4, 1.0, 0.4) * 0.35, 19.5)
    music = fold(buf, L)
    music = lp(music, 7000, 2, circular=True)
    music = reverb(music, 2.6, 0.4, rng, damp=4000, circular=True)
    # soft drone (A1/E2/A2), frequencies snapped to whole cycles over 24 s
    snap = lambda f: round(f * dur) / dur
    drone = np.zeros(L)
    for f, a in ((55.0, 1.0), (82.41, 0.4), (110.0, 0.35), (110.0 * 1.003, 0.25)):
        drone += a * np.sin(2 * np.pi * snap(f) * t + rng.uniform(0, 6.28))
    drone *= 0.8 + 0.2 * np.sin(2 * np.pi * 3 * t / dur)
    air = bp(rng.standard_normal(L), 200, 1200, 2, circular=True)
    air *= 0.6 + 0.4 * np.sin(2 * np.pi * 2 * t / dur) ** 2
    y = music / (np.max(np.abs(music)) + 1e-9) + 0.12 * drone + 0.02 * air / (np.std(air) + 1e-9)
    return remove_dc(y, circular=True)


# --- Nightmare Mode ---------------------------------------------------------

def s_critter_squish():
    """A brief wet crunch underfoot: brittle clicks over a short damp squelch."""
    rng = rng_for(301)
    dur = 0.32
    n = N(dur)
    y = np.zeros(n)
    for k in range(9):
        tc = abs(rng.normal(0.0, 0.012))
        place(y, burst(N(0.01), rng, 2500, 9000, 0.0002, 0.0015) * rng.uniform(0.4, 1.0), tc)
    m = N(0.22)
    sq = bp(rng.standard_normal(m), 250, 1800) * env_ad(m, 0.004, 0.05)
    sq *= 1.0 + 0.6 * np.sin(2 * np.pi * 38 * tt(m))
    place(y, sq * 0.8, 0.008)
    place(y, thump(0.12, 160, 70, 0.03, rng, 0.4, 500) * 0.5, 0.0)
    return fades(remove_dc(fit(y, dur)), 0.0005, 0.06)


def s_nm_knock():
    """Three slow knocks somewhere behind the walls."""
    rng = rng_for(302)
    dur = 2.4
    y = np.zeros(N(dur))
    for i, tc in enumerate([0.05, 0.62, 1.12]):
        k = thump(0.3, 140, 85, 0.05, rng, 0.5, 900)
        k += 0.4 * modes(N(0.3), [210, 390, 640], [0.05, 0.03, 0.02], [1, 0.5, 0.3], rng)
        place(y, k * (1.0 - 0.15 * i), tc)
    y = lp(y, 1400)
    y = reverb(y, 1.8, 0.45, rng, 2500)
    return fades(remove_dc(fit(y, dur)), 0.002, 0.4)


def s_nm_drag():
    """Something heavy dragged across floorboards above or below."""
    rng = rng_for(303)
    dur = 2.6
    n = N(dur)
    y = creak(dur, [(0, 18), (1.2, 26), (2.6, 14)], rng, (300, 700, 1500), 0.35,
              [(0, 0), (0.3, 0.9), (2.0, 0.7), (2.6, 0)])
    y += 0.25 * lp(rng.standard_normal(n), 220) * interp_keys([(0, 0), (0.3, 1), (2.2, 0.8), (2.6, 0)], tt(n))
    y = lp(y, 1800)
    y = reverb(y, 1.4, 0.4, rng, 2200)
    return fades(remove_dc(fit(y, dur)), 0.05, 0.3)


# --- Revision 5: environment, Witch's Needle, new entities -------------------

def s_door_slam():
    rng = rng_for(401)
    dur = 1.3
    y = np.zeros(N(dur))
    place(y, creak(0.25, [(0, 160), (0.25, 320)], rng, (620, 1250, 2600), 0.25) * 0.5, 0.0)
    k = thump(0.5, 120, 55, 0.08, rng, 0.7, 700)
    k += 0.5 * modes(N(0.5), [180, 310, 520, 880], [0.08, 0.05, 0.03, 0.02], [1, 0.6, 0.4, 0.2], rng)
    place(y, k, 0.22)
    place(y, bp(rng.standard_normal(N(0.08)), 1500, 6000) * env_ad(N(0.08), 0.0005, 0.01) * 0.4, 0.23)
    y = reverb(y, 1.2, 0.3, rng)
    return fades(remove_dc(fit(y, dur)), 0.002, 0.25)


def s_flame_snuff():
    rng = rng_for(402)
    dur = 0.7
    n = N(dur)
    t = tt(n)
    y = lp(rng.standard_normal(n), 900) * interp_keys([(0, 0), (0.02, 1), (0.25, 0.4), (0.7, 0)], t)
    y += 0.3 * bp(rng.standard_normal(n), 2000, 6000) * env_ad(n, 0.005, 0.05)
    return fades(remove_dc(fit(y, dur)), 0.002, 0.15)


def s_needle_tap():
    """A tiny metal-on-glass tink."""
    rng = rng_for(403)
    dur = 0.18
    n = N(dur)
    y = modes(n, [2870, 4310, 6020, 7950], [0.05, 0.035, 0.022, 0.015], [1, 0.55, 0.35, 0.2], rng)
    y += 0.3 * hp(rng.standard_normal(n), 5000) * env_ad(n, 0.0002, 0.0015)
    return fades(remove_dc(fit(y, dur)), 0.0002, 0.04)


def s_blight_ping():
    """A hollow sonar-like pulse with a soured, bending pitch."""
    rng = rng_for(404)
    dur = 1.2
    n = N(dur)
    t = tt(n)
    f = 620 * np.exp(-t * 0.6)
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.35)
    y += 0.35 * np.sin(2 * np.pi * np.cumsum(f * 1.47) / SR) * np.exp(-t / 0.2)
    y *= np.clip(t / 0.004, 0, 1)
    y = reverb(y, 1.6, 0.45, rng, 3000)
    return fades(remove_dc(fit(y, dur)), 0.002, 0.3)


def s_music_box():
    rng = rng_for(405)
    dur = 2.2
    y = np.zeros(N(dur))
    for k, m in enumerate([76, 79, 83, 81, 79, 76]):
        place(y, music_box_note(midi_hz(m) * 0.985, 0.9, rng, 0.8), 0.05 + k * 0.3 * (1 + k * 0.06))
    y = reverb(y, 1.4, 0.35, rng)
    return fades(remove_dc(fit(y, dur)), 0.002, 0.4)


def s_ignite():
    """Supernatural combustion: a roaring whoosh that catches and crackles."""
    rng = rng_for(406)
    dur = 2.2
    n = N(dur)
    t = tt(n)
    env = interp_keys([(0, 0), (0.12, 1), (0.6, 0.8), (2.2, 0)], t)
    y = lp(rng.standard_normal(n), 700) * env * 1.2
    y += 0.4 * bp(rng.standard_normal(n), 900, 4000) * env
    tc = 0.15
    while tc < dur - 0.1:
        place(y, burst(N(0.02), rng, 2000, 9000, 0.0003, 0.004) * rng.uniform(0.2, 0.7), tc)
        tc += rng.exponential(1 / 30)
    y = reverb(y, 0.9, 0.2, rng)
    return fades(remove_dc(fit(y, dur)), 0.01, 0.4)


def s_furnace_roar():
    rng = rng_for(407)
    dur = 2.8
    n = N(dur)
    t = tt(n)
    env = interp_keys([(0, 0), (0.3, 1), (2.0, 0.9), (2.8, 0)], t)
    y = lp(rng.standard_normal(n), 260) * env * 1.6
    y += 0.5 * bp(rng.standard_normal(n), 400, 1800) * env * (1 + 0.5 * np.sin(2 * np.pi * 3.0 * t))
    place(y, thump(0.6, 70, 35, 0.15, rng, 0.6, 300), 0.05)
    y = reverb(y, 1.5, 0.35, rng, 2000)
    return fades(remove_dc(fit(y, dur)), 0.01, 0.4)


def s_crawl_drag():
    rng = rng_for(408)
    dur = 1.6
    n = N(dur)
    t = tt(n)
    y = creak(dur, [(0, 30), (0.8, 55), (1.6, 25)], rng, (250, 600, 1300), 0.5, [(0, 0), (0.2, 1), (1.3, 0.8), (1.6, 0)]) * 0.6
    y += 0.5 * lp(rng.standard_normal(n), 400) * interp_keys([(0, 0), (0.2, 1), (1.4, 0.6), (1.6, 0)], t)
    y = reverb(y, 1.0, 0.3, rng)
    return fades(remove_dc(fit(y, dur)), 0.02, 0.2)


def s_water_drip():
    """Two or three slow drops of sea water onto boards, in a hollow room."""
    rng = rng_for(409)
    dur = 1.4
    y = np.zeros(N(dur))
    for k, at in enumerate([0.03, 0.55, 1.0][:rng.integers(2, 4)]):
        place(y, bubble(rng, 700, 1300, 1.4) * (1.0 - 0.25 * k), at)
        m = N(0.05)
        place(y, lp(rng.standard_normal(m), 900) * env_ad(m, 0.001, 0.01) * 0.25, at)
    y = reverb(y, 1.2, 0.4, rng, 3500)
    return fades(remove_dc(fit(y, dur)), 0.002, 0.2)


def s_water_splash():
    """Something heavy rising out of standing water."""
    rng = rng_for(410)
    dur = 1.6
    n = N(dur)
    t = tt(n)
    env = interp_keys([(0, 0), (0.06, 1), (0.5, 0.5), (1.6, 0)], t)
    y = bp(rng.standard_normal(n), 300, 3500) * env * 0.8
    tc = 0.02
    while tc < 1.2:
        place(y, bubble(rng, 250, 1400, 2.0) * rng.uniform(0.3, 0.9), tc)
        tc += rng.exponential(1 / 25)
    place(y, thump(0.4, 90, 45, 0.1, rng, 0.5, 400) * 0.6, 0.0)
    y = reverb(y, 1.3, 0.35, rng, 3000)
    return fades(remove_dc(fit(y, dur)), 0.004, 0.3)


def s_wood_creak():
    """Ship's timbers: a long, low groan of wet wood under strain."""
    rng = rng_for(411)
    dur = 2.0
    y = creak(dur, [(0, 22), (0.9, 40), (2.0, 18)], rng, (180, 420, 900), 0.3,
              [(0, 0), (0.3, 1), (1.5, 0.8), (2.0, 0)])
    y = reverb(lp(y, 2200), 1.6, 0.4, rng, 2500)
    return fades(remove_dc(fit(y, dur)), 0.02, 0.3)


def s_sea_whisper():
    """A far-off, breathy shanty fragment under a wash of surf."""
    rng = rng_for(412)
    dur = 3.0
    n = N(dur)
    t = tt(n)
    surf = lp(rng.standard_normal(n), 600) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.35 * t - 1.2)) ** 2
    y = surf * 0.35
    keys_v = [(0, "h"), (0.2, "o"), (0.6, "o"), (0.8, "a"), (1.2, "a"), (1.5, "u"), (1.9, "h")]
    amp = [(0, 0), (0.15, 0.8), (0.6, 1), (0.8, 0.5), (1.2, 1), (1.6, 0.6), (1.9, 0)]
    a = voice(1.9, [(0, 140), (0.6, 155), (1.2, 130), (1.9, 120)], keys_v, amp, rng, breath=1.2,
              voiced=0.35, vib_depth=0.03, vib_rate=4.0, jitter=0.03, fshift=0.92)
    place(y, a * 0.8, 0.5)
    y = lp(y, 2500, 2)
    y = reverb(y, 2.6, 0.6, rng, damp=2000, predelay=0.04)
    return fades(remove_dc(fit(y, dur)), 0.05, 0.6)


def s_plague_breath():
    """Slow, rasping breath drawn through a long leather beak."""
    rng = rng_for(413)
    dur = 2.4
    n = N(dur)
    t = tt(n)
    inh = interp_keys([(0, 0), (0.5, 1), (0.9, 0.3), (1.0, 0)], t)
    exh = interp_keys([(0, 0), (1.15, 0), (1.5, 0.9), (2.2, 0.2), (2.4, 0)], t)
    noise = rng.standard_normal(n) * (1 + 0.8 * smooth_noise(n, 40, rng))
    y = bp(noise, 400, 2400) * inh * 0.8 + bp(noise, 250, 1500) * exh
    y = fft_filter(y, lambda f: 0.2 + 1 / (1 + ((f - 700) / 120) ** 2) + 0.6 / (1 + ((f - 1500) / 200) ** 2))
    y = reverb(y, 0.8, 0.2, rng, 3000)
    return fades(remove_dc(fit(y, dur)), 0.02, 0.3)


def s_bottle_clink():
    """Glass medicine bottles knocking together in a satchel."""
    rng = rng_for(414)
    dur = 1.2
    y = np.zeros(N(dur))
    for k, at in enumerate([0.02, 0.17, 0.29]):
        m = N(0.6)
        f0 = rng.uniform(2600, 3400)
        place(y, modes(m, [f0, f0 * 2.3, f0 * 3.9], [0.18, 0.1, 0.05], [1, 0.4, 0.2], rng) * (1 - 0.3 * k), at)
    y = reverb(y, 0.7, 0.25, rng, 6000)
    return fades(remove_dc(fit(y, dur)), 0.001, 0.2)


def s_clock_toll():
    """A grandfather clock: a few ticks, one deep toll, then the ticking stops."""
    rng = rng_for(415)
    dur = 3.2
    y = np.zeros(N(dur))
    for k in range(4):
        m = N(0.05)
        tick = bp(rng.standard_normal(m), 1800 if k % 2 == 0 else 1500, 5000) * env_ad(m, 0.0005, 0.006)
        place(y, tick * 0.35, 0.05 + k * 0.42)
    place(y, bell(110, 2.6, rng, 0.4) * 0.8, 1.75)
    y = reverb(y, 1.8, 0.4, rng, 3000)
    return fades(remove_dc(fit(y, dur)), 0.002, 0.5)


def s_weeper_sob():
    """Muffled sobbing behind a wall: three catching breaths and a long wavering cry."""
    rng = rng_for(416)
    dur = 3.4
    y = np.zeros(N(dur))
    for k, at in enumerate([0.05, 0.42, 0.74]):
        hic = voice(0.22, [(0, 330), (0.22, 300)], [(0, "h"), (0.08, "u"), (0.22, "h")],
                    [(0, 0), (0.04, 1), (0.18, 0.3), (0.22, 0)], rng, breath=1.0, voiced=0.4, jitter=0.04, fshift=1.15)
        place(y, hic * (0.6 - 0.1 * k), at)
    cry = voice(2.2, [(0, 360), (0.6, 410), (1.2, 330), (1.8, 380), (2.2, 260)], [(0, "u"), (0.5, "o"), (1.4, "u"), (2.2, "h")],
                [(0, 0), (0.2, 0.9), (1.0, 1.0), (1.7, 0.6), (2.2, 0)], rng, breath=0.7, voiced=0.8,
                vib_rate=7.5, vib_depth=0.05, jitter=0.03, fshift=1.15)
    place(y, cry, 1.05)
    y = lp(y, 2400, 2)   # through a wall
    y = reverb(y, 2.0, 0.5, rng, damp=2200, predelay=0.03)
    return fades(remove_dc(fit(y, dur)), 0.01, 0.4)


# name -> (generator, kind, expected duration (approx))
SOUNDS = {
    "pencil_scribble": (s_pencil_scribble, "oneshot"),
    "ui_click": (s_ui_click, "ui"),
    "ui_hover": (s_ui_hover, "ui"),
    "footstep": (s_footstep, "oneshot"),
    "flashlight_click": (s_flashlight_click, "oneshot"),
    "camera_shutter": (s_camera_shutter, "oneshot"),
    "thermometer_tick": (s_thermometer_tick, "oneshot"),
    "emf_beep": (s_emf_beep, "oneshot"),
    "emf_spike": (s_emf_spike, "oneshot"),
    "spirit_box_static": (s_spirit_box_static, "loop"),
    "spirit_box_voice": (s_spirit_box_voice, "oneshot"),
    "whisper_mimic": (s_whisper_mimic, "oneshot"),
    "salt_pour": (s_salt_pour, "oneshot"),
    "place_item": (s_place_item, "oneshot"),
    "pickup": (s_pickup, "oneshot"),
    "holy_water_splash": (s_holy_water_splash, "oneshot"),
    "crucifix_burn": (s_crucifix_burn, "oneshot"),
    "stake_strike": (s_stake_strike, "oneshot"),
    "melt_silver": (s_melt_silver, "oneshot"),
    "mirror_reveal": (s_mirror_reveal, "oneshot"),
    "candle_light": (s_candle_light, "oneshot"),
    "door_creak": (s_door_creak, "oneshot"),
    "poltergeist_bang": (s_poltergeist_bang, "oneshot"),
    "ghost_wail": (s_ghost_wail, "oneshot"),
    "hunt_start": (s_hunt_start, "oneshot"),
    "hunt_loop": (s_hunt_loop, "loop"),
    "vampire_hiss": (s_vampire_hiss, "oneshot"),
    "werewolf_howl": (s_werewolf_howl, "oneshot"),
    "werewolf_growl": (s_werewolf_growl, "oneshot"),
    "shapeshift": (s_shapeshift, "oneshot"),
    "cat_meow": (s_cat_meow, "oneshot"),
    "harbinger_arrival": (s_harbinger_arrival, "oneshot"),
    "reckless_reaction": (s_reckless_reaction, "oneshot"),
    "player_hurt": (s_player_hurt, "oneshot"),
    "player_death": (s_player_death, "oneshot"),
    "scream_1": (s_scream_1, "oneshot"),
    "scream_2": (s_scream_2, "oneshot"),
    "scream_3": (s_scream_3, "oneshot"),
    "npc_gasp": (s_npc_gasp, "oneshot"),
    "npc_flee": (s_npc_flee, "oneshot"),
    "vanquish_success": (s_vanquish_success, "oneshot"),
    "results_win": (s_results_win, "oneshot"),
    "results_lose": (s_results_lose, "oneshot"),
    "ambience_house": (s_ambience_house, "loop"),
    "music_menu": (s_music_menu, "loop"),
    "critter_squish": (s_critter_squish, "oneshot"),
    "nm_knock": (s_nm_knock, "oneshot"),
    "nm_drag": (s_nm_drag, "oneshot"),
    "door_slam": (s_door_slam, "oneshot"),
    "flame_snuff": (s_flame_snuff, "oneshot"),
    "needle_tap": (s_needle_tap, "ui"),
    "blight_ping": (s_blight_ping, "oneshot"),
    "music_box": (s_music_box, "oneshot"),
    "ignite": (s_ignite, "oneshot"),
    "furnace_roar": (s_furnace_roar, "oneshot"),
    "crawl_drag": (s_crawl_drag, "oneshot"),
    "water_drip": (s_water_drip, "oneshot"),
    "water_splash": (s_water_splash, "oneshot"),
    "wood_creak": (s_wood_creak, "oneshot"),
    "sea_whisper": (s_sea_whisper, "oneshot"),
    "plague_breath": (s_plague_breath, "oneshot"),
    "bottle_clink": (s_bottle_clink, "oneshot"),
    "clock_toll": (s_clock_toll, "oneshot"),
    "weeper_sob": (s_weeper_sob, "oneshot"),
}


def write_wav(path, x):
    pcm = np.clip(np.round(x * 32767), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main(argv):
    os.makedirs(OUT_DIR, exist_ok=True)
    names = argv[1:] or list(SOUNDS)
    for name in names:
        fn, kind = SOUNDS[name]
        x = np.asarray(fn(), dtype=float)
        peak = {"oneshot": PEAK_ONESHOT, "ui": PEAK_UI, "loop": PEAK_LOOP}[kind]
        x = normalize(x, peak)
        path = os.path.join(OUT_DIR, name + ".wav")
        write_wav(path, x)
        print(f"{name:20s} {len(x) / SR:6.3f}s  {kind}")


if __name__ == "__main__":
    main(sys.argv)
