"""Vlorë: apartment blocks behind the boulevard, where the mapped city is thin.

OpenStreetMap has few footprints west of Bulevardi Ismail Qemali, behind
the Muradie Mosque and Teatri Petro Marko, so the lots there read as empty.
This bake lines the side streets of that quarter with the city's usual
4-8 storey blocks (pallate), from the city's own outputs, no OSM:

  roads.glb, buildings.glb  side streets to front, buildings to keep clear of
  props.json + cities.py    landmark plots (clear_half) to keep clear of
  terrain_near.bin          ground above the sea and level enough to build on

Only the west side of the boulevard is filled: Kuzum Baba, the view the
boulevard keeps (cities.py 'sightlines'), is to the east. Writes infill.json:
  {"blocks": [[cx, cz, yaw, width, depth, floors, tint], ...]}
yaw turns the block's width to run along its street; tint indexes the
game's palette (VloreInfill.TINTS).
"""
import json
import math
from pathlib import Path

import numpy as np

from common import Proj
from landmark_anchors import terrain_sampler
from vlore_boulevard import BUILDING, ROAD, _glb_triangles, _raster, stretch_line

CELL = 1.0
WEST_OF_LINE = 34.0     # metres west of the boulevard's centreline at least
REACH = 380.0           # metres west of the line at most
ALONG_MARGIN = 60.0     # beyond the boulevard's ends
SETBACK = 3.5           # pavement in front of a block
GAP = 3.0               # between blocks
MAX_SLOPE = 4.5         # metres of fall across a footprint
MAX_BLOCKS = 220
SIZES = [(24.0, 13.0), (20.0, 12.0), (16.0, 12.0), (13.0, 11.0)]


def _dilate(mask, r):
    out = mask.copy()
    for dz in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dz * dz > r * r:
                continue
            out |= np.roll(np.roll(mask, dz, axis=0), dx, axis=1)
    return out


def _rect_cells(cx, cz, yaw, w, d, x0, z0, h, wd, grow=0.0):
    """Cell indices (rows, cols) covered by an oriented rectangle."""
    c, s = math.cos(yaw), math.sin(yaw)
    hw, hd = w / 2 + grow, d / 2 + grow
    ext = math.hypot(hw, hd)
    ax, bx = int((cx - ext - x0) / CELL), int((cx + ext - x0) / CELL) + 1
    az, bz = int((cz - ext - z0) / CELL), int((cz + ext - z0) / CELL) + 1
    if ax < 0 or az < 0 or bx >= wd or bz >= h:
        return None
    gx, gz = np.meshgrid(np.arange(ax, bx), np.arange(az, bz))
    px = x0 + (gx + 0.5) * CELL - cx
    pz = z0 + (gz + 0.5) * CELL - cz
    u = px * c + pz * s
    v = -px * s + pz * c
    inside = (np.abs(u) <= hw) & (np.abs(v) <= hd)
    return gz[inside], gx[inside]


def bake(out_dir, city, seed=1912):
    out_dir = Path(out_dir)
    proj = Proj(*city['origin'], city.get('latitude_compression', ()))
    track = json.loads((out_dir / 'track.json').read_text())
    line = stretch_line(track['pts'], proj, city['boulevard'])
    sea = float(track.get('sea_level', 0.0))
    z_lo, z_hi = line[:, 1].min() - ALONG_MARGIN, line[:, 1].max() + ALONG_MARGIN
    x0 = math.floor(line[:, 0].min() - REACH)
    x1 = math.ceil(line[:, 0].max())
    z0, z1 = math.floor(z_lo), math.ceil(z_hi)
    wd, h = int((x1 - x0) / CELL), int((z1 - z0) / CELL)
    grid = np.zeros((h, wd), np.uint8)
    for name, value in (('roads.glb', ROAD), ('buildings.glb', BUILDING)):
        path = out_dir / name
        if path.exists():
            _raster(grid, _glb_triangles(path), x0, z0, CELL, value)
    road = (grid & ROAD) > 0
    blocked = _dilate(road, 3) | _dilate((grid & BUILDING) > 0, 3)
    # Landmark plots, and the quarter outside the strip west of the boulevard.
    props = json.loads((out_dir / 'props.json').read_text())
    halves = {lm['id']: lm['clear_half'] for lm in city.get('landmarks', ()) if 'clear_half' in lm}
    for lm in props.get('landmarks', ()):
        if lm['id'] in halves:
            hx, hz = halves[lm['id']]
            ax, bx = int((lm['x'] - hx - 6 - x0) / CELL), int((lm['x'] + hx + 6 - x0) / CELL)
            az, bz = int((lm['z'] - hz - 6 - z0) / CELL), int((lm['z'] + hz + 6 - z0) / CELL)
            blocked[max(az, 0):max(min(bz + 1, h), 0), max(ax, 0):max(min(bx + 1, wd), 0)] = True
    zs = z0 + (np.arange(h) + 0.5) * CELL
    order = np.argsort(line[:, 1])
    line_x = np.interp(zs, line[order, 1], line[order, 0])
    xs = x0 + (np.arange(wd) + 0.5) * CELL
    west = xs[None, :] <= (line_x[:, None] - WEST_OF_LINE)
    blocked |= ~west
    blocked |= (zs[:, None] < z_lo) | (zs[:, None] > z_hi)
    ground = terrain_sampler(str(out_dir))
    rng = np.random.default_rng(seed)
    # Street frontage: road cells on a 4 m lattice, nearest the boulevard first.
    rz, rx = np.nonzero(road)
    keep = (rz % 4 == 0) & (rx % 4 == 0)
    rz, rx = rz[keep], rx[keep]
    px = x0 + (rx + 0.5) * CELL
    pz = z0 + (rz + 0.5) * CELL
    near_line = np.interp(pz, line[order, 1], line[order, 0]) - px
    pick = (near_line > WEST_OF_LINE - 10) & (near_line < REACH)
    rz, rx, px, pz = rz[pick], rx[pick], px[pick], pz[pick]
    first = np.argsort(near_line[pick] + rng.uniform(0, 30, len(px)))
    road_pts = np.c_[x0 + (np.nonzero(road)[1] + 0.5) * CELL, z0 + (np.nonzero(road)[0] + 0.5) * CELL]
    blocks = []
    for i in first:
        if len(blocks) >= MAX_BLOCKS:
            break
        p = np.array([px[i], pz[i]])
        local = road_pts[np.linalg.norm(road_pts - p, axis=1) < 7.0]
        if len(local) < 6:
            continue
        # The street's direction: the main axis of the road cells round it.
        cov = np.cov((local - local.mean(axis=0)).T)
        evals, evecs = np.linalg.eigh(cov)
        if evals[1] < 3.0 * max(evals[0], 1e-3):
            continue          # a junction or a blob, not a street
        t = evecs[:, 1]
        yaw = math.atan2(t[1], t[0])
        n = np.array([-t[1], t[0]])
        for sgn in (1.0, -1.0) if rng.random() < 0.5 else (-1.0, 1.0):
            placed = False
            for w, d in SIZES:
                # Back from the street until the plot is clear: the road's
                # ribbon is wider than one cell, so the frontage line varies.
                c = None
                for back in np.arange(2.0, 12.0, 1.0):
                    q = p + n * sgn * (back + SETBACK + d / 2)
                    cells = _rect_cells(q[0], q[1], yaw, w, d, x0, z0, h, wd, grow=1.0)
                    if cells is None or len(cells[0]) == 0:
                        break
                    if not blocked[cells].any():
                        c = q
                        break
                    # Stop at the first back line past the street with only
                    # buildings or plots in the way.
                if c is None:
                    continue
                corners = [c + t * a * w / 2 + n * b * d / 2 for a in (-1, 1) for b in (-1, 1)]
                hs = [ground(q[0], q[1]) for q in corners]
                if min(hs) < sea + 1.0 or max(hs) - min(hs) > MAX_SLOPE:
                    continue
                floors = int(rng.choice([4, 5, 5, 6, 6, 7, 8]))
                tint = int(rng.integers(0, 6))
                blocks.append([round(float(c[0]), 2), round(float(c[1]), 2), round(yaw, 4),
                               w, d, floors, tint])
                grown = _rect_cells(c[0], c[1], yaw, w, d, x0, z0, h, wd, grow=GAP)
                blocked[grown if grown is not None else cells] = True
                placed = True
                break
            if placed and len(blocks) >= MAX_BLOCKS:
                break
    data = {'blocks': blocks}
    (out_dir / 'infill.json').write_text(json.dumps(data, separators=(',', ':')))
    return data


if __name__ == '__main__':
    import sys
    from cities import CITIES
    root = Path(__file__).resolve().parents[2]
    cid = sys.argv[1] if len(sys.argv) > 1 else 'vlore'
    data = bake(root / 'godot' / 'assets' / 'cities' / cid, CITIES[cid])
    b = data['blocks']
    print(f'infill {cid}: {len(b)} blocks, {sum(x[3] * x[4] for x in b):.0f} m2 of footprint, '
          f'{sum(x[5] for x in b) / max(len(b), 1):.1f} floors on average')
