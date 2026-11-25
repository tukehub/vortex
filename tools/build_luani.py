"""Bring the supplied lion sculpture into the game as Vlorë's Luani.

Input: the project's lion model archive (ZBrush OBJ, 10 614 quads, with 4K
base colour, normal and roughness maps), supplied for the lion fountain at
Rrapi. Output, under godot/assets/landmarks/luani/:

  luani.obj        the mesh, unchanged geometry and UVs (no material lib)
  luani_gilt.jpg   1024 px: the base colour's shading as gilded paint (the
                   source is painted as a living lion; the statue is gold)
  luani_nor.jpg    1024 px: the sculpted normal map
  luani_rough.jpg  1024 px: roughness, tightened toward polished paint
  luani.json       the transform LionFountain applies (scale, offset), the
                   mouth in model units and the feet's extent

  python3 tools/build_luani.py path/to/obj.zip
"""
import io
import json
import os
import sys
import zipfile

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'godot', 'assets', 'landmarks', 'luani')
SIZE = 1024
NOSE_TO_RUMP = 1.45      # metres: life size, as the statue on its rock
GOLD_DARK = np.array([0.36, 0.24, 0.09])
GOLD_LIGHT = np.array([0.98, 0.80, 0.42])


def main(zip_path):
    os.makedirs(OUT, exist_ok=True)
    z = zipfile.ZipFile(zip_path)
    names = {os.path.basename(n): n for n in z.namelist()}
    obj = z.read(names['lion_low.obj']).decode('utf8', 'replace')
    lines = [ln for ln in obj.splitlines() if not ln.startswith(('mtllib', 'usemtl'))]
    with open(os.path.join(OUT, 'luani.obj'), 'w', encoding='utf8') as f:
        f.write('# Luani, Vlorë: the supplied lion sculpture (tools/build_luani.py)\n')
        f.write('\n'.join(ln for ln in lines if not ln.startswith('#')) + '\n')
    v = np.array([[float(x) for x in ln.split()[1:4]] for ln in lines if ln.startswith('v ')])
    # The model: y up, head toward -z, tail out along +z; feet at the lowest y.
    feet = v[v[:, 1] < v[:, 1].min() + 0.8]
    body = v[(v[:, 2] <= feet[:, 2].max())]
    length = body[:, 2].max() - body[:, 2].min()
    scale = NOSE_TO_RUMP / length
    offset = [-float(np.median(v[:, 0])), -float(v[:, 1].min()),
              -float((feet[:, 2].min() + feet[:, 2].max()) * 0.5)]
    # The mouth: under the snout's tip, on its centre line.
    front = v[v[:, 2] < v[:, 2].min() + 0.6]
    tip = front[np.argmin(front[:, 2])]
    snout_x = float(np.median(front[:, 0]))
    mouth = [snout_x, float(tip[1]) - 1.1, float(tip[2]) + 0.25]
    meta = {'scale': round(float(scale), 6), 'offset': [round(o, 4) for o in offset],
            'mouth': [round(m, 4) for m in mouth],
            'feet_z': [round(float(feet[:, 2].min()), 3), round(float(feet[:, 2].max()), 3)],
            'feet_x': [round(float(feet[:, 0].min()), 3), round(float(feet[:, 0].max()), 3)],
            'tris': int(sum(1 for ln in lines if ln.startswith('f ')) * 2)}
    with open(os.path.join(OUT, 'luani.json'), 'w', encoding='utf8') as f:
        json.dump(meta, f, indent=1)
    # Textures at mobile size.
    base = Image.open(io.BytesIO(z.read(names['defaultMat_Base_Color_1001.png']))).convert('RGB').resize((SIZE, SIZE), Image.LANCZOS)
    lum = np.asarray(base.convert('L'), np.float32) / 255.0
    lum = (lum - lum.mean()) / max(lum.std(), 1e-3)
    t = np.clip(0.62 + 0.16 * lum, 0.0, 1.0)[..., None]
    gilt = GOLD_DARK + (GOLD_LIGHT - GOLD_DARK) * t
    Image.fromarray((gilt * 255).astype(np.uint8), 'RGB').save(os.path.join(OUT, 'luani_gilt.jpg'), quality=90)
    nor = Image.open(io.BytesIO(z.read(names['lion_normal.jpg']))).convert('RGB').resize((SIZE, SIZE), Image.LANCZOS)
    nor.save(os.path.join(OUT, 'luani_nor.jpg'), quality=92)
    rough = np.asarray(Image.open(io.BytesIO(z.read(names['defaultMat_Roughness_1001.png']))).convert('L').resize((SIZE, SIZE), Image.LANCZOS), np.float32) / 255.0
    rough = 0.22 + 0.4 * rough
    Image.fromarray((rough * 255).astype(np.uint8), 'L').save(os.path.join(OUT, 'luani_rough.jpg'), quality=90)
    print(f'luani: {meta["tris"]} triangles, scale {meta["scale"]}, feet z {meta["feet_z"]}, mouth {meta["mouth"]} -> {OUT}')


if __name__ == '__main__':
    main(sys.argv[1])
