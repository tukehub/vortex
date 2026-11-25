#!/usr/bin/env python3
"""Bake the Berat window atlas: godot/assets/textures/berat_windows.png.

Four 256 x 512 px windows side by side (0.85 x 1.7 m each), for the houses of
Mangalem, Gorica and the castle (godot/scripts/world/old_quarter.gd):
  0  six panes in a dark timber frame
  1  four tall panes, one leaf ajar
  2  six panes, a white curtain drawn behind the lower ones
  3  closed board shutters
Frames and shutters are cut from the CC0 Dark Wooden Planks texture (Poly
Haven, assets/textures/dark_timber_diff.jpg); the glass is painted: a dark
interior under a sky reflection that brightens toward the top. The alpha
channel marks the glass (255) for the night glow; 0 is frame or shutter.

    python3 tools/build_berat_windows.py
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
TIMBER = ROOT / 'godot/assets/textures/dark_timber_diff.jpg'
OUT = ROOT / 'godot/assets/textures/berat_windows.png'
W, H = 256, 512
REVEAL = 12      # plaster reveal in shadow round the opening
FRAME = 13
BAR = 7


def wood(w, h, seed, vertical=True):
    src = Image.open(TIMBER).convert('RGB')
    rng = np.random.default_rng(seed)
    x = int(rng.integers(0, src.width - 300))
    y = int(rng.integers(0, src.height - 300))
    tile = src.crop((x, y, x + 300, y + 300))
    if vertical:
        tile = tile.rotate(90, expand=True)
    tile = tile.resize((w, h))
    arr = np.asarray(tile, np.float32) * 0.78
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def glass(w, h, seed, curtain=False):
    rng = np.random.default_rng(seed)
    yy = np.linspace(0, 1, h)[:, None]
    xx = np.linspace(0, 1, w)[None, :]
    sky = np.array([118, 132, 146], np.float32)
    room = np.array([34, 38, 42], np.float32)
    t = (1.0 - yy) ** 1.6 * 0.55 + 0.08 * np.sin(xx * 3.0 + yy * 5.0 + rng.uniform(0, 6))
    img = room[None, None, :] * (1 - t[..., None]) + sky[None, None, :] * t[..., None]
    # A soft diagonal glint.
    glint = np.exp(-((xx * 0.8 - yy + rng.uniform(0.1, 0.5)) ** 2) / 0.01) * 16
    img += glint[..., None]
    if curtain:
        lower = (yy > 0.42).astype(np.float32)
        folds = 0.85 + 0.15 * np.sin(xx * 38.0)
        cloth = np.array([222, 218, 206], np.float32) * folds[..., None]
        img = img * (1 - lower[..., None] * 0.86) + cloth * lower[..., None] * 0.86
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))


def window(kind, seed):
    rgb = Image.new('RGB', (W, H), (226, 222, 212))
    mask = Image.new('L', (W, H), 0)
    d = ImageDraw.Draw(rgb)
    # Reveal: plaster, darker at the top and left (shade of the lintel).
    for i in range(REVEAL):
        shade = int(150 + i * 5)
        d.rectangle([i, i, W - 1 - i, H - 1 - i], outline=(shade, shade - 2, shade - 8))
    x0, y0, x1, y1 = REVEAL, REVEAL, W - REVEAL, H - REVEAL
    if kind == 3:
        boards = wood(x1 - x0, y1 - y0, seed, vertical=False)
        rgb.paste(boards, (x0, y0))
        bd = ImageDraw.Draw(rgb)
        mid = (x0 + x1) // 2
        bd.line([(mid, y0), (mid, y1)], fill=(24, 20, 16), width=3)
        for y in range(y0 + 18, y1 - 10, 22):
            bd.line([(x0 + 6, y), (x1 - 6, y)], fill=(30, 25, 20), width=2)
        return rgb, mask
    rgb.paste(wood(x1 - x0, y1 - y0, seed), (x0, y0))
    gx0, gy0, gx1, gy1 = x0 + FRAME, y0 + FRAME, x1 - FRAME, y1 - FRAME
    rows = 2 if kind == 1 else 3
    cols = 2
    pane_w = (gx1 - gx0 - (cols - 1) * BAR) // cols
    pane_h = (gy1 - gy0 - (rows - 1) * BAR) // rows
    for r in range(rows):
        for c in range(cols):
            px = gx0 + c * (pane_w + BAR)
            py = gy0 + r * (pane_h + BAR)
            ajar = kind == 1 and c == 1
            g = glass(pane_w, pane_h, seed * 7 + r * 3 + c, curtain=(kind == 2 and r > 0))
            if ajar:
                g = Image.fromarray((np.asarray(g, np.float32) * 0.55).astype(np.uint8))
            rgb.paste(g, (px, py))
            mask.paste(255 if not ajar else 200, (px, py, px + pane_w, py + pane_h))
    # A thin sill of grey stone under the frame.
    d.rectangle([REVEAL - 6, H - REVEAL - 2, W - REVEAL + 6, H - 1], fill=(188, 184, 176))
    return rgb, mask


def main():
    atlas = Image.new('RGBA', (W * 4, H))
    for k in range(4):
        rgb, mask = window(k, 11 + k * 5)
        rgb = rgb.filter(ImageFilter.SMOOTH_MORE)
        tile = rgb.convert('RGBA')
        tile.putalpha(mask)
        atlas.paste(tile, (k * W, 0))
    atlas.save(OUT, optimize=True)
    print(f'wrote {OUT.relative_to(ROOT)} {atlas.size}')


if __name__ == '__main__':
    main()
