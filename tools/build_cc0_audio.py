"""Build the tyre screech loop and result jingles from CC0 recordings.

Sources (all CC0 1.0), placed in one directory passed as --src:

    71736__audible-edge__chrysler-lhs-tire-squeal-01-04-25-2009.wav
    71737__audible-edge__chrysler-lhs-tire-squeal-02-04-25-2009.wav
    71738__audible-edge__chrysler-lhs-tire-squeal-03-04-25-2009.wav
                    audible-edge, freesound.org/s/71736 .. 71738 (96 kHz mono)
    kenney_music-jingles.zip   or its unpacked Audio/ folder
                    Kenney "Music Jingles", kenney.nl/assets/music-jingles

Writes godot/assets/sfx/:
    screech_loop.wav   the steadiest squeal from each take, high-passed under
                       the engine, crossfaded end to end into one seamless loop
                       (replaces the procedural screech from gen_sfx.py)
    result_win.wav     STEEL10, rising  - first place
    result_podium.wav  STEEL15, rising  - second or third
    result_lose.wav    STEEL03, falling - everything else

    python3 tools/build_cc0_audio.py --src /path/to/sources

Needs ffmpeg on PATH for decoding.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import zipfile
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_sfx import SR, highpass, write_wav  # noqa: E402

SQUEALS = [
    "71736__audible-edge__chrysler-lhs-tire-squeal-01-04-25-2009.wav",
    "71737__audible-edge__chrysler-lhs-tire-squeal-02-04-25-2009.wav",
    "71738__audible-edge__chrysler-lhs-tire-squeal-03-04-25-2009.wav",
]
JINGLES = {
    "result_win": "Steel jingles/jingles_STEEL10.ogg",
    "result_podium": "Steel jingles/jingles_STEEL15.ogg",
    "result_lose": "Steel jingles/jingles_STEEL03.ogg",
}
WINDOW = 1.1      # seconds of steady squeal taken from each take
XFADE = 0.12      # equal-power crossfade between takes and across the seam


def decode(data_or_path, *, is_bytes: bool = False) -> np.ndarray:
    cmd = ["ffmpeg", "-v", "error", "-i", "-" if is_bytes else str(data_or_path),
           "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"]
    out = subprocess.run(cmd, input=data_or_path if is_bytes else None, capture_output=True, check=True).stdout
    return np.frombuffer(out, dtype="<f4").astype(np.float64)


def steadiest(x: np.ndarray) -> np.ndarray:
    """The WINDOW-long stretch with high level and the least level wobble."""
    frame = int(0.05 * SR)
    rms = np.sqrt(np.convolve(x * x, np.ones(frame) / frame, mode="valid")[::frame])
    span = int(WINDOW / 0.05)
    best, best_score = 0, -np.inf
    for i in range(len(rms) - span):
        w = rms[i:i + span]
        score = w.mean() - 1.5 * w.std()
        if score > best_score:
            best, best_score = i, score
    seg = x[best * frame: best * frame + int(WINDOW * SR)]
    return seg / (np.sqrt(np.mean(seg * seg)) + 1e-9)


def join(parts: list[np.ndarray]) -> np.ndarray:
    n = int(XFADE * SR)
    t = np.linspace(0.0, np.pi / 2, n)
    fade_in, fade_out = np.sin(t), np.cos(t)
    out = parts[0].copy()
    for p in parts[1:]:
        out[-n:] = out[-n:] * fade_out + p[:n] * fade_in
        out = np.concatenate([out, p[n:]])
    # Close the loop: blend the tail into the head, then drop the tail.
    out[:n] = out[:n] * fade_in + out[-n:] * fade_out
    return out[:-n]


def jingle_bytes(src: Path, rel: str) -> bytes:
    folder = src / "Audio" / rel
    if folder.exists():
        return folder.read_bytes()
    for zp in src.glob("*music-jingles*.zip"):
        with zipfile.ZipFile(zp) as z:
            name = "Audio/" + rel
            if name in z.namelist():
                return z.read(name)
    raise SystemExit(f"missing jingle: {rel} (put kenney_music-jingles.zip in --src)")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, type=Path)
    src = ap.parse_args().src

    takes = []
    for name in SQUEALS:
        p = next(src.glob("*" + name), None)
        if p is None:
            raise SystemExit(f"missing source: {name}")
        takes.append(steadiest(highpass(decode(p), 350.0)))
    loop = join(takes)
    loop *= 0.7 / np.max(np.abs(loop))
    write_wav("screech_loop", loop, loop=True)
    print(f"screech_loop.wav {len(loop) / SR:.2f} s")

    for out, rel in JINGLES.items():
        x = decode(jingle_bytes(src, rel), is_bytes=True)
        on = np.nonzero(np.abs(x) > 0.002)[0]
        x = x[on[0]: on[-1] + 1] if len(on) else x
        fade = min(int(0.03 * SR), len(x))
        x[-fade:] *= np.linspace(1.0, 0.0, fade)
        write_wav(out, x * (0.8 / max(np.max(np.abs(x)), 1e-9)))
        print(f"{out}.wav {len(x) / SR:.2f} s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
