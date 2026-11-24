"""The shore road before the Uji i Ftohtë tunnel (Vlorë): modern hotels up
the hillside on the land side, and on the sea side a beach club with a long
pool, loungers and parasols, after photographs of that strip.

City config (cities.py):
  'resort': {'portal': (lat, lon),        # the tunnel portal the strip leads to
             'hotels': (from_m, to_m),    # land-side frontage, metres before it
             'club': metres_before}       # where the pool's centre is

`plan()` walks the lap back from the portal and returns props.json's
"resort" entry plus rectangles kept clear of mapped buildings and trees:
  hotels: [x, y, z, yaw, width, depth, floors, kind]  (front along local -Z,
          facing the road; y is the ground at the lowest corner; kind 0 a
          terraced white block, 1 a glass-fronted tower, 2 a white slab)
  club:   {x, y, z, yaw, length, depth, pool: [length, width]}
          (deck centre at road level, local -Z toward the road)
"""
import math

import numpy as np

import seafront

FLOOR = 3.2


def _walk_back(ref, index, metres):
    """Lap sample `metres` before `index` (by centreline distance)."""
    n = len(ref.xz)
    left, i = metres, index
    while left > 0.0:
        j = (i - 1) % n
        left -= float(np.linalg.norm(ref.xz[i] - ref.xz[j]))
        i = j
    return i


def _sea_side(ref, i, mask, nm, reach=160.0):
    """+1 when the sea is along +normal at sample i, -1 along -normal, and the
    distance to it from the centreline (None when no water within reach)."""
    for r in np.arange(4.0, reach, 2.5):
        for side in (1.0, -1.0):
            p = ref.xz[i] + side * r * ref.nrm[i]
            if seafront.is_water(mask, nm, *p):
                return side, float(r)
    return None, None


def _yaw_facing(direction):
    """Landmark yaw (degrees) whose local -Z points along `direction` (x, z)."""
    return math.degrees(math.atan2(-direction[0], -direction[1]))


def _footprint(x, z, yaw_deg, width, depth):
    a = math.radians(yaw_deg)
    right = np.array([math.cos(a), -math.sin(a)])
    back = np.array([math.sin(a), math.cos(a)])
    c = np.array([x, z])
    return np.array([c + right * sx * width / 2 + back * sz * depth / 2 for sx in (-1, 1) for sz in (-1, 1)])


def plan(ref, hw, proj, cfg, mask, nm, terrain_sample, rnd):
    portal = np.asarray(proj.to_xz(*cfg['portal']), float)
    ip = int(np.argmin(np.linalg.norm(ref.xz - portal, axis=1)))
    hotels, clear = [], []
    lo, hi = cfg['hotels']
    # Front row on the road, a second row stepped up the slope behind it.
    rows = ((hw + 12.0, (6, 9), 15.0), (hw + 52.0, (5, 7), 14.0))
    for row, (setback, (fmin, fmax), depth) in enumerate(rows):
        metres = float(lo) + (9.0 if row else 0.0)
        k = 0
        while metres < hi - 20.0:
            width = 30.0 + 18.0 * rnd(f'resort{row}', k)
            mid = metres + width / 2.0
            i = _walk_back(ref, ip, mid)
            side, _ = _sea_side(ref, i, mask, nm)
            land = -(side or 1.0)
            normal = ref.nrm[i] * land
            centre = ref.xz[i] + normal * (setback + depth / 2.0)
            yaw = _yaw_facing(-normal)
            tower = row == 0 and k == 2
            floors = 12 if tower else int(fmin + (fmax - fmin + 1) * rnd(f'resort{row}f', k))
            kind = 1 if tower else (0 if (k + row) % 3 else 2)
            corners = _footprint(centre[0], centre[1], yaw, width, depth)
            base = float(np.min(terrain_sample(corners[:, 0], corners[:, 1])))
            road_y = float(ref.y[i])
            base = max(base, road_y - 0.4) if row == 0 else base
            hotels.append([round(float(centre[0]), 1), round(base, 2), round(float(centre[1]), 1), round(yaw, 1),
                           round(width, 1), depth, floors, kind])
            mn, mx = corners.min(axis=0) - 4.0, corners.max(axis=0) + 4.0
            clear.append([round(float(v), 1) for v in (*mn, *mx)])
            metres += width + 8.0 + 6.0 * rnd(f'resort{row}g', k)
            k += 1
    # The beach club: a deck from the road edge to the shore, the pool
    # parallel to the road.
    i = _walk_back(ref, ip, float(cfg['club']))
    side, water = _sea_side(ref, i, mask, nm)
    if side is None:
        raise RuntimeError('resort: no sea beside the beach club')
    normal = ref.nrm[i] * side
    inner = hw + 2.5
    outer = max(inner + 20.0, water - 2.0)
    depth = outer - inner
    centre = ref.xz[i] + normal * (inner + depth / 2.0)
    length = 86.0
    yaw = _yaw_facing(-normal)
    club = {'x': round(float(centre[0]), 1), 'y': round(float(ref.y[i]) + 0.05, 2), 'z': round(float(centre[1]), 1),
            'yaw': round(yaw, 1), 'length': length, 'depth': round(depth, 1),
            'pool': [62.0, round(min(16.0, depth - 7.0), 1)]}
    corners = _footprint(club['x'], club['z'], yaw, length, depth)
    mn, mx = corners.min(axis=0) - 3.0, corners.max(axis=0) + 3.0
    clear.append([round(float(v), 1) for v in (*mn, *mx)])
    return {'hotels': hotels, 'club': club, 'clear': clear}


def clear_zones(resort):
    """build_city's keepout rectangles (x0, z0, x1, z1)."""
    return [tuple(r) for r in resort['clear']]
