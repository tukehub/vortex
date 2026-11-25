"""Bake the sea and river ripple normal map from CC0 wave heightmaps.

Source: "Seamless looping waves heightmaps" by zookeeper, OpenGameArt,
CC0 1.0 (https://opengameart.org/content/seamless-looping-waves-heightmaps):
512x512 8-bit heightmaps, seamless both ways. Two frames of the loop are
blended (a softer, less regular surface than one alone) and turned into a
tangent-space normal map with wrap-around central differences, so it still
tiles: godot/assets/textures/water_waves_nor.png (RGB, OpenGL +Y).
  python3 tools/build_wave_normals.py
The heightmaps are cached under tools/cache/cc0/waves/ (git-ignored).
"""
import os
import urllib.request

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, 'tools', 'cache', 'cc0', 'waves')
OUT = os.path.join(ROOT, 'godot', 'assets', 'textures', 'water_waves_nor.png')
URL = 'https://opengameart.org/sites/default/files/oga-textures/46094/{}.png'
FRAMES = ('00', '05')
STRENGTH = 110.0  # the maps rise ~0.0025 a pixel; ripples want slopes ~0.3


def frame(name):
    path = os.path.join(CACHE, f'{name}.png')
    if not os.path.exists(path):
        os.makedirs(CACHE, exist_ok=True)
        urllib.request.urlretrieve(URL.format(name), path)
    return np.asarray(Image.open(path).convert('L'), np.float32) / 255.0


def main():
    h = sum(frame(f) for f in FRAMES) / len(FRAMES)
    # Smooth the 8-bit steps (wrapping, so it still tiles).
    for _ in range(2):
        h = sum(np.roll(np.roll(h, a, axis=0), b, axis=1) for a in (-1, 0, 1) for b in (-1, 0, 1)) / 9.0
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5 * STRENGTH
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5 * STRENGTH
    n = np.stack([-dx, dy, np.ones_like(h)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    rgb = ((n * 0.5 + 0.5) * 255.0 + 0.5).clip(0, 255).astype(np.uint8)
    Image.fromarray(rgb, 'RGB').save(OUT, optimize=True)
    print(f'water normals: {OUT} ({rgb.shape[1]}x{rgb.shape[0]}), mean z {n[..., 2].mean():.3f}')


if __name__ == '__main__':
    main()
