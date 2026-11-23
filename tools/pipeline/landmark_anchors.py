"""Add a city's configured landmarks that its processed props.json lacks.

build_props() writes every landmark of cities.py on a full rebuild; this adds
new ones to an existing dataset with the same formula (local x/z from the
city projection plus offsets, y from the baked near terrain plus offset_y),
and, like build_props(), clears trees, lamps and street furniture out of each
new landmark's clear_half keepout. Existing rows are left untouched:
  python3 tools/pipeline/landmark_anchors.py vlore
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from common import OUT, Proj, log  # noqa: E402
from cities import CITIES  # noqa: E402


def terrain_sampler(out_dir):
    with open(os.path.join(out_dir, 'terrain.json'), encoding='utf8') as f:
        nm = json.load(f)['near']
    h = np.fromfile(os.path.join(out_dir, 'terrain_near.bin'), '<f4').reshape(nm['n'], nm['n'])

    def sample(x, z):
        fx = (x - nm['x0']) / nm['cell']
        fz = (z - nm['z0']) / nm['cell']
        i = int(np.clip(np.floor(fx), 0, nm['n'] - 2))
        j = int(np.clip(np.floor(fz), 0, nm['n'] - 2))
        a, b = fx - i, fz - j
        return float(h[j, i] * (1 - a) * (1 - b) + h[j, i + 1] * a * (1 - b)
                     + h[j + 1, i] * (1 - a) * b + h[j + 1, i + 1] * a * b)
    return sample


def process_city(cid):
    city = CITIES[cid]
    out_dir = os.path.join(OUT, cid)
    proj = Proj(*city['origin'], city.get('latitude_compression', ()))
    path = os.path.join(out_dir, 'props.json')
    with open(path, encoding='utf8') as f:
        props = json.load(f)
    have = {lm['id'] for lm in props.get('landmarks', [])}
    sample = terrain_sampler(out_dir)
    added = []
    for lm in city.get('landmarks', []):
        if lm['id'] in have:
            continue
        x, z = proj.to_xz(*lm['ll'])
        x = float(x) + lm.get('offset_x', 0)
        z = float(z) + lm.get('offset_z', 0)
        y = sample(x, z) + lm.get('offset_y', 0.0)
        props.setdefault('landmarks', []).append({'id': lm['id'], 'x': round(x, 1), 'y': round(y, 1), 'z': round(z, 1), 'yaw': lm.get('yaw', 0)})
        added.append(lm['id'])
    zones = []
    for lm in city.get('landmarks', []):
        if lm['id'] in added and 'clear_half' in lm:
            x, z = proj.to_xz(*lm['ll'])
            x = float(x) + lm.get('offset_x', 0)
            z = float(z) + lm.get('offset_z', 0)
            hx, hz = lm['clear_half']
            zones.append((x - hx - 1.0, z - hz - 1.0, x + hx + 1.0, z + hz + 1.0))

    def clear(rows, xi, zi):
        return [r for r in rows if not any(x0 <= r[xi] <= x1 and z0 <= r[zi] <= z1 for x0, z0, x1, z1 in zones)]
    before = (len(props.get('trees', [])), len(props.get('lamps', [])))
    props['trees'] = clear(props.get('trees', []), 0, 2)
    props['lamps'] = clear(props.get('lamps', []), 0, 2)
    for kind, rows in props.get('street', {}).items():
        props['street'][kind] = clear(rows, 0, 1)
    cleared = (before[0] - len(props['trees']), before[1] - len(props['lamps']))
    with open(path, 'w', encoding='utf8') as f:
        json.dump(props, f, separators=(',', ':'))
    log(f'[{cid}] landmarks added: {added or "none"}; cleared {cleared[0]} trees, {cleared[1]} lamps')
    return added


if __name__ == '__main__':
    for cid in sys.argv[1:] or ['vlore']:
        process_city(cid)
