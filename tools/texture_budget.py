"""Keep 3D textures VRAM-compressed and mipmapped so the APK stays small and
the phone GPU reads compressed, cache-friendly texels.

Godot only converts a texture to VRAM compression when the editor GUI sees it
used in 3D ("detect_3d"); a headless import (CI) keeps whatever the .import
says. Textures added with compress/mode=0 therefore shipped lossless (WebP
re-encoded photos, 2-3x their JPEG size) and without mipmaps (every distant
pixel misses the texture cache). HDR skies shipped as raw RGBE (8.4 MB each).

    python3 tools/texture_budget.py           # report problems, exit 1 if any
    python3 tools/texture_budget.py --fix     # rewrite the .import files

After --fix, reimport: godot --headless --path godot --editor --import
"""
import argparse
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
GODOT = ROOT / 'godot'

# Drawn in 2D (UI, HUD, launcher): lossless is right for them.
FLAT = re.compile(r'^assets/(ui|powerups|fonts)/|^assets/icon(_192)?\.png$')
# Data maps where block compression would smear the weights; lossless with
# mipmaps keeps them exact and still cache-friendly.
DATA = re.compile(r'^assets/cities/[^/]+/(splat|ground_macro)\.png$')
# Not shipped (export_presets.cfg exclude_filter): leave as fetched.
UNSHIPPED = re.compile(r'^assets/props/(street_bin|promenade_lamp|utility_box|bench)/'
                       r'|^assets/cities/(berat|gjirokaster|tetove)/')
# Detail maps (normal, ARM) of the CC0 surface sets: grain and relief at a
# few metres, never filling the screen. 512 px keeps them sharp at 720p.
DETAIL_512 = re.compile(r'^assets/textures/((sand|promenade_paving|palm_bark|castle_wall|pole_metal)_(nor|arm)|marble_rock_rough)\.jpg$')
# Coastal 1K atlases are sliced into mipmapped texture arrays.
COAST_ARRAYS = re.compile(r'^assets/cities/vlore/(ground_layers\.jpg|ground_layers_pbr\.webp)$')
# Tall bark strip: 1024 x 2048 at source, a palm trunk never needs it.
DIFFUSE_1024 = re.compile(r'^assets/textures/palm_bark_diff\.jpg$')


def wanted(rel: str) -> dict:
    """Import parameters a texture must have; empty when anything goes."""
    if FLAT.search(rel) or UNSHIPPED.search(rel):
        return {}
    if DATA.search(rel):
        return {'mipmaps/generate': 'true'}
    if rel.endswith('.hdr') or rel.endswith('.exr'):
        # ASTC HDR on Android (BPTC on desktop): a quarter of raw RGBE.
        return {'compress/mode': '2'}
    out = {'compress/mode': '2', 'mipmaps/generate': 'true'}
    if COAST_ARRAYS.fullmatch(rel):
        out.update({'compress/high_quality': 'true', 'compress/channel_pack': '0',
                    'slices/horizontal': '2', 'slices/vertical': '2'})
    elif re.fullmatch(r"assets/textures/limestone_(diff|nor|arm)\.jpg", rel):
        out.update({'process/size_limit': '1024', 'compress/high_quality': 'true'})
    elif DETAIL_512.search(rel):
        out['process/size_limit'] = '512'
    elif DIFFUSE_1024.search(rel):
        out['process/size_limit'] = '1024'
    return out


def textures():
    for path in sorted((GODOT / 'assets').rglob('*.import')):
        text = path.read_text()
        rel = path.relative_to(GODOT).as_posix()[:-len('.import')]
        if 'importer="texture"' not in text and not COAST_ARRAYS.fullmatch(rel):
            continue
        yield path, rel, text


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--fix', action='store_true')
    args = ap.parse_args()
    problems = []
    for path, rel, text in textures():
        for key, value in wanted(rel).items():
            pattern = re.compile(r'^' + re.escape(key) + r'=.*$', re.M)
            current = pattern.search(text)
            if current and current.group(0) == f'{key}={value}':
                continue
            problems.append(f'{rel}: {key} should be {value}')
            if args.fix:
                text = pattern.sub(f'{key}={value}', text) if current else text.rstrip('\n') + f'\n{key}={value}\n'
        if args.fix:
            path.write_text(text)
    if problems and not args.fix:
        print('\n'.join(problems))
        print(f'{len(problems)} texture import settings off budget; run tools/texture_budget.py --fix')
        sys.exit(1)
    print(f'texture budget: {len(problems)} settings {"fixed" if args.fix else "off"}')


if __name__ == '__main__':
    main()
