"""Traditional quarters baked from OpenStreetMap footprints (Berat's
Mangalem, Gorica and the inhabited castle).

Every mapped building inside a quarter polygon becomes an Ottoman-era house
for godot/scripts/world/old_quarter.gd instead of a generic extrusion:

  ring    the footprint (x, z metres, counter-clockwise, no repeated end)
  lo, hi  the lowest and highest ground under it (the downhill side shows
          a tall stone base, the uphill side a low one)
  floors  plastered upper floors over the stone ground floor (1 or 2;
          building:levels when mapped)
  front   the edge that looks downhill, toward the valley: it carries the
          close rows of windows Berat is known for
  q       quarter index in `quarters` (names)

A quarter is a lat/lon polygon in the city config, or 'way:<id>' for a
mapped ring (the castle's curtain wall).

Data (c) OpenStreetMap contributors (ODbL).
"""
import math
import zlib

import numpy as np


def _inside(poly, x, z):
    inside = False
    n = len(poly)
    for i in range(n):
        x0, z0 = poly[i]
        x1, z1 = poly[(i + 1) % n]
        if (z0 > z) != (z1 > z) and x < x0 + (z - z0) * (x1 - x0) / (z1 - z0):
            inside = not inside
    return inside


def _clean(ring):
    if len(ring) > 1 and math.dist(ring[0], ring[-1]) < 0.05:
        ring = ring[:-1]
    out = []
    for p in ring:
        if not out or math.dist(p, out[-1]) > 0.4:
            out.append(p)
    if len(out) > 2 and math.dist(out[0], out[-1]) <= 0.4:
        out.pop()
    # Drop near-collinear points so walls are whole faces.
    changed = True
    while changed and len(out) > 3:
        changed = False
        for i in range(len(out)):
            a, b, c = np.asarray(out[i - 1]), np.asarray(out[i]), np.asarray(out[(i + 1) % len(out)])
            u, v = b - a, c - b
            if abs(u[0] * v[1] - u[1] * v[0]) < 0.06 * np.linalg.norm(u) * np.linalg.norm(v):
                out.pop(i)
                changed = True
                break
    area = 0.0
    for i in range(len(out)):
        x0, z0 = out[i]
        x1, z1 = out[(i + 1) % len(out)]
        area += x0 * z1 - x1 * z0
    if area < 0:
        out = out[::-1]
    return out, abs(area) * 0.5


def quarter_polygons(cfg, osm, proj):
    polys = []
    for name, spec in cfg.items():
        if isinstance(spec, str) and spec.startswith('way:'):
            w = osm.ways.get(int(spec[4:]))
            polys.append((name, osm.coords(w) if w else []))
        else:
            polys.append((name, [proj.to_xz(lat, lon) for lat, lon in spec]))
    return polys


def select(osm, polys):
    """OSM building way ids inside any quarter, with their quarter index."""
    out = {}
    for wid, w in osm.ways.items():
        tags = w.get('tags') or {}
        if 'building' not in tags or w['nodes'][0] != w['nodes'][-1]:
            continue
        if (tags.get('amenity') == 'place_of_worship' or tags.get('historic') in ('ruins', 'city_gate')
                or tags.get('building') in ('church', 'mosque', 'chapel', 'cathedral')):
            continue
        ring = osm.coords(w)
        if len(ring) < 4:
            continue
        cx = sum(p[0] for p in ring) / len(ring)
        cz = sum(p[1] for p in ring) / len(ring)
        for qi, (_, poly) in enumerate(polys):
            if len(poly) > 2 and _inside(poly, cx, cz):
                out[wid] = qi
                break
    return out


def bake(osm, picked, polys, terrain_sample, river=None, ref=None, hw=0.0):
    houses = []
    for wid, qi in sorted(picked.items()):
        w = osm.ways[wid]
        tags = w.get('tags') or {}
        ring, area = _clean(osm.coords(w))
        if len(ring) < 3 or area < 12.0 or area > 900.0:
            continue
        arr = np.asarray(ring)
        g = terrain_sample(arr[:, 0], arr[:, 1])
        lo, hi = float(np.min(g)), float(np.max(g))
        if river is not None and any(river.water_at(x, z) for x, z in ring):
            continue
        # Nothing stands on the race road: test the corners and edge midpoints.
        if ref is not None:
            probe = list(ring) + [((ring[i][0] + ring[(i + 1) % len(ring)][0]) * 0.5,
                                   (ring[i][1] + ring[(i + 1) % len(ring)][1]) * 0.5) for i in range(len(ring))]
            if any(ref.nearest(x, z)[0] < hw + 1.5 for x, z in probe):
                continue
        # Downhill: the terrain gradient at the footprint, or toward the river.
        c = arr.mean(axis=0)
        e = 6.0
        gx = float(terrain_sample([c[0] + e], [c[1]])[0] - terrain_sample([c[0] - e], [c[1]])[0]) / (2 * e)
        gz = float(terrain_sample([c[0]], [c[1] + e])[0] - terrain_sample([c[0]], [c[1] - e])[0]) / (2 * e)
        down = np.array([-gx, -gz])
        if np.linalg.norm(down) < 0.04 and river is not None:
            _, i = river.tree.query(c)
            down = river.pts[i] - c
        down = down / max(np.linalg.norm(down), 1e-6)
        best, front = -2.0, 0
        for i in range(len(ring)):
            a, b = np.asarray(ring[i]), np.asarray(ring[(i + 1) % len(ring)])
            edge = b - a
            length = float(np.linalg.norm(edge))
            if length < 2.0:
                continue
            out = np.array([edge[1], -edge[0]]) / length     # outward for a CCW ring (x east, z south)
            score = float(out @ down) + 0.02 * length
            if score > best:
                best, front = score, i
        seed = zlib.crc32(str(wid).encode()) & 0xffff
        levels = tags.get('building:levels')
        try:
            floors = max(1, min(2, int(float(levels)) - 1))
        except (TypeError, ValueError):
            floors = 2 if (area > 70.0 and seed % 3 != 0) else 1
        houses.append({'id': wid, 'q': qi, 'ring': [[round(x, 2), round(z, 2)] for x, z in ring],
                       'lo': round(lo, 2), 'hi': round(hi, 2), 'floors': floors, 'front': front, 'seed': seed})
    return {'quarters': [name for name, _ in polys], 'houses': houses}
