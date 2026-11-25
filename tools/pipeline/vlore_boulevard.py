"""Vlorë: the boulevard past the Muradie Mosque as a city street.

From Sheshi i Flamurit south past the Muradie Mosque to Teatri Petro Marko
the game lines the race road with granite kerbs, paved sidewalks, tree pits,
benches and a planted verge (VloreBoulevard,
godot/scripts/world/vlore_boulevard.gd). It needs to know what already stands beside
the road, so this bake reads the city's own outputs, no OSM:

  roads.glb      side-road ribbons: the sidewalk drops its kerb at their mouths
  buildings.glb  the generic buildings: the sidewalk runs up to their walls
  props.json     landmark anchors and the cities.py clear_half plots round
                 them (the mosque garden, the monument square): no verge there

and writes boulevard.json:

  {"line": [[x, z], ...]    centreline of the lap's first pass by the stretch,
   "radius": m              samples of either pass this close are on it,
   "grid": {"x0", "z0", "cell", "w", "h",
            "rows": [[value, run, value, run, ...], ...]}}

Grid values are bit flags per cell: 1 side road, 2 building, 4 landmark plot.
Rows are run-length encoded from x0 eastward; row r is z0 + r * cell.
"""
import json
import struct
from pathlib import Path

import numpy as np

from common import Proj

CELL = 1.0
MARGIN = 40.0
RADIUS = 15.0
ROAD, BUILDING, LANDMARK = 1, 2, 4


def _glb_triangles(path):
    """World-space triangles (n, 3, 3) of every mesh node in a glTF binary
    whose nodes carry only a translation (as the pipeline writes them)."""
    blob = Path(path).read_bytes()
    json_len = struct.unpack('<I', blob[12:16])[0]
    doc = json.loads(blob[20:20 + json_len])
    bin_start = 20 + json_len + 8
    views = doc['bufferViews']
    accessors = doc['accessors']

    def read(index, comps):
        acc = accessors[index]
        view = views[acc['bufferView']]
        start = bin_start + view.get('byteOffset', 0) + acc.get('byteOffset', 0)
        dtype = {5126: '<f4', 5125: '<u4', 5123: '<u2', 5121: 'u1'}[acc['componentType']]
        arr = np.frombuffer(blob, dtype=dtype, count=acc['count'] * comps, offset=start)
        return arr.reshape(acc['count'], comps) if comps > 1 else arr

    out = []
    for node in doc['nodes']:
        if 'mesh' not in node:
            continue
        offset = np.asarray(node.get('translation', [0.0, 0.0, 0.0]), float)
        for prim in doc['meshes'][node['mesh']]['primitives']:
            pos = read(prim['attributes']['POSITION'], 3).astype(float) + offset
            if 'indices' in prim:
                idx = read(prim['indices'], 1).astype(np.int64)
            else:
                idx = np.arange(len(pos))
            out.append(pos[idx.reshape(-1, 3)])
    return np.concatenate(out) if out else np.zeros((0, 3, 3))


def _raster(grid, tris, x0, z0, cell, value):
    """OR `value` into every cell whose centre lies in a triangle's plan
    (x, z); edge-on triangles (walls) mark the cells their edges cross."""
    h, w = grid.shape
    xz = tris[:, :, [0, 2]]
    lo = np.floor((xz.min(axis=1) - (x0, z0)) / cell).astype(int)
    hi = np.floor((xz.max(axis=1) - (x0, z0)) / cell).astype(int)
    keep = (hi[:, 0] >= 0) & (hi[:, 1] >= 0) & (lo[:, 0] < w) & (lo[:, 1] < h)
    for t, a, b in zip(xz[keep], lo[keep], hi[keep]):
        ax, az = max(a[0], 0), max(a[1], 0)
        bx, bz = min(b[0], w - 1), min(b[1], h - 1)
        gx, gz = np.meshgrid(np.arange(ax, bx + 1), np.arange(az, bz + 1))
        px = x0 + (gx + 0.5) * cell
        pz = z0 + (gz + 0.5) * cell
        (x1, z1), (x2, z2), (x3, z3) = t
        det = (z2 - z3) * (x1 - x3) + (x3 - x2) * (z1 - z3)
        if abs(det) < 1e-6:
            # Edge-on: the cells the triangle's longest edge passes through.
            pts = t[np.argsort(t[:, 0] + t[:, 1])]
            p, q = pts[0], pts[-1]
            n = max(2, int(np.hypot(*(q - p)) / (cell * 0.5)) + 1)
            for s in np.linspace(0.0, 1.0, n):
                c = ((p + (q - p) * s) - (x0, z0)) / cell
                ci, cj = int(c[0]), int(c[1])
                if 0 <= ci < w and 0 <= cj < h:
                    grid[cj, ci] |= value
            continue
        l1 = ((z2 - z3) * (px - x3) + (x3 - x2) * (pz - z3)) / det
        l2 = ((z3 - z1) * (px - x3) + (x1 - x3) * (pz - z3)) / det
        inside = (l1 >= -1e-3) & (l2 >= -1e-3) & (l1 + l2 <= 1.0 + 1e-3)
        grid[gz[inside], gx[inside]] |= value


def stretch_line(pts, proj, cfg):
    """The lap's samples from the one nearest cfg['from'] to the one nearest
    cfg['to'], the shorter way round."""
    xz = np.asarray([[p[0], p[2]] for p in pts], float)
    ends = []
    for key in ('from', 'to'):
        q = np.asarray(proj.to_xz(*cfg[key]), float)
        ends.append(int(np.argmin(np.linalg.norm(xz - q, axis=1))))
    a, b = ends
    n = len(xz)
    forward = (b - a) % n
    idx = [(a + k) % n for k in range(forward + 1)] if forward <= n - forward else [(a - k) % n for k in range(n - forward + 1)]
    return xz[idx]


def _rle(row):
    out = []
    start = 0
    for i in range(1, len(row) + 1):
        if i == len(row) or row[i] != row[start]:
            out += [int(row[start]), i - start]
            start = i
    return out


def bake(out_dir, city):
    out_dir = Path(out_dir)
    cfg = city['boulevard']
    proj = Proj(*city['origin'], city.get('latitude_compression', ()))
    track = json.loads((out_dir / 'track.json').read_text())
    line = stretch_line(track['pts'], proj, cfg)
    x0, z0 = np.floor(line.min(axis=0) - MARGIN)
    x1, z1 = np.ceil(line.max(axis=0) + MARGIN)
    w, h = int((x1 - x0) / CELL), int((z1 - z0) / CELL)
    grid = np.zeros((h, w), np.uint8)
    for name, value in (('roads.glb', ROAD), ('buildings.glb', BUILDING)):
        path = out_dir / name
        if path.exists():
            _raster(grid, _glb_triangles(path), x0, z0, CELL, value)
    props = json.loads((out_dir / 'props.json').read_text())
    halves = {lm['id']: lm['clear_half'] for lm in city.get('landmarks', ()) if 'clear_half' in lm}
    for lm in props.get('landmarks', ()):
        if lm['id'] not in halves:
            continue
        hx, hz = halves[lm['id']]
        ax, bx = int((lm['x'] - hx - x0) / CELL), int((lm['x'] + hx - x0) / CELL)
        az, bz = int((lm['z'] - hz - z0) / CELL), int((lm['z'] + hz - z0) / CELL)
        grid[max(az, 0):max(min(bz + 1, h), 0), max(ax, 0):max(min(bx + 1, w), 0)] |= LANDMARK
    data = {
        'line': [[round(float(x), 2), round(float(z), 2)] for x, z in line],
        'radius': RADIUS,
        'grid': {'x0': float(x0), 'z0': float(z0), 'cell': CELL, 'w': w, 'h': h,
                 'rows': [_rle(r) for r in grid]},
    }
    (out_dir / 'boulevard.json').write_text(json.dumps(data, separators=(',', ':')))
    return data, grid


if __name__ == '__main__':
    import sys
    from cities import CITIES
    root = Path(__file__).resolve().parents[2]
    cid = sys.argv[1] if len(sys.argv) > 1 else 'vlore'
    data, grid = bake(root / 'godot' / 'assets' / 'cities' / cid, CITIES[cid])
    print(f'boulevard {cid}: {len(data["line"])} line points, grid {grid.shape[1]}x{grid.shape[0]}, '
          f'road {int((grid & ROAD).astype(bool).sum())} building {int((grid & BUILDING).astype(bool).sum())} '
          f'landmark {int((grid & LANDMARK).astype(bool).sum())} cells')
