"""Berat castle (Kalaja e Beratit) on its hill, baked from OpenStreetMap.

Writes godot/assets/cities/berat/castle.json in metres relative to the
`castle_berat` landmark anchor (x east, z south):
  wall      the curtain wall ring round the hilltop (way 426996540)
  lines     the other mapped stretches of wall: the inner citadel (Iç Kala),
            the cross walls and the wall running down to Mangalem, open
  towers    flanking towers set on the curtain wall where it turns and at
            most 68 m apart (the castle had some two dozen), each a centre,
            its outward direction and size
  gate      the main gate (the mapped city_gate building)
  churches  the castle's churches and mosques: footprint, name, kind
            (church, domed church, mosque ruin), the Byzantine churches of
            the Kala quarter, St Michael's on the cliff above the river, the
            Red and White mosques' ruins
  flag      where the flag flies, the castle's southern spur over Mangalem
and drops props.json trees standing on the walls. The Kala quarter's houses
are built by old_quarters.py with Mangalem's and Gorica's.

Data (c) OpenStreetMap contributors (ODbL).
"""
import json
import math
import os

import numpy as np

from common import Proj, log
from rozafa import clean, edge_distance, inside, polygon_area

WALL_WAY = 426996540
TOWER_SPACING = 68.0
TOWER_TURN = math.radians(28.0)
# Churches crowned with a dome on a drum.
DOMED = ('Shën Mëri Vllahernës', 'Shën Triadhës', 'Shën Mëhilli', 'Shën Todrit', 'Shën Kostandinit')


def _local(nodes, proj, origin, way):
    pts = [proj.to_xz(*nodes[n]) for n in way['nodes'] if n in nodes]
    return [(round(x - origin[0], 2), round(z - origin[1], 2)) for x, z in pts]


def _towers(wall):
    """Towers at the wall's turns, then fill so none is TOWER_SPACING apart."""
    n = len(wall)
    pts = np.asarray(wall, float)
    area = sum(wall[i][0] * wall[(i + 1) % n][1] - wall[(i + 1) % n][0] * wall[i][1] for i in range(n))
    seg = np.roll(pts, -1, axis=0) - pts
    length = np.linalg.norm(seg, axis=1)
    s = np.concatenate([[0.0], np.cumsum(length)])
    perimeter = s[-1]

    def at(dist):
        dist %= perimeter
        i = int(np.searchsorted(s, dist, side='right') - 1)
        i = min(i, n - 1)
        t = (dist - s[i]) / max(length[i], 1e-6)
        p = pts[i] + seg[i] * t
        e = seg[i] / max(length[i], 1e-6)
        out = np.array([e[1], -e[0]]) if area > 0 else np.array([-e[1], e[0]])
        return p, out

    marks = []
    for i in range(n):
        a = seg[i - 1] / max(length[i - 1], 1e-6)
        b = seg[i] / max(length[i], 1e-6)
        turn = math.acos(max(-1.0, min(1.0, float(a @ b))))
        if turn > TOWER_TURN and length[i] > 4.0 and length[i - 1] > 4.0:
            if not marks or s[i] - marks[-1] > 22.0:
                marks.append(float(s[i]))
    if not marks:
        marks = [0.0]
    filled = []
    for k, m in enumerate(marks):
        nxt = marks[(k + 1) % len(marks)] + (perimeter if k == len(marks) - 1 else 0.0)
        filled.append(m)
        gap = nxt - m
        extra = int(gap // TOWER_SPACING)
        for j in range(1, extra + 1):
            filled.append(m + gap * j / (extra + 1))
    towers = []
    for k, d in enumerate(filled):
        p, out = at(d)
        size = 7.0 if k % 3 == 0 else 5.8
        towers.append({'at': [round(float(p[0]), 2), round(float(p[1]), 2)],
                       'out': [round(float(out[0]), 3), round(float(out[1]), 3)], 'size': size,
                       'round': k % 4 == 2})
    return towers


def bake(osm_path, out_dir, city):
    proj = Proj(*city['origin'])
    anchor = next(lm for lm in city['landmarks'] if lm['id'] == 'castle_berat')
    origin = proj.to_xz(*anchor['ll'])
    elements = json.load(open(osm_path, encoding='utf8'))['elements']
    nodes = {e['id']: (e['lat'], e['lon']) for e in elements if e['type'] == 'node' and 'lat' in e}
    ways = {e['id']: e for e in elements if e['type'] == 'way'}
    wall = clean(_local(nodes, proj, origin, ways[WALL_WAY]))
    lines, churches, gate = [], [], None
    for way in ways.values():
        tags = way.get('tags', {})
        if way['id'] == WALL_WAY:
            continue
        pts = _local(nodes, proj, origin, way)
        if len(pts) < 2:
            continue
        cx = sum(p[0] for p in pts) / len(pts)
        cz = sum(p[1] for p in pts) / len(pts)
        if math.hypot(cx, cz) > 650.0:
            continue
        if tags.get('barrier') == 'city_wall':
            lines.append([[x, z] for x, z in pts])
        elif tags.get('historic') == 'city_gate':
            ring = clean(pts)
            gate = {'ring': [[x, z] for x, z in ring]}
        elif tags.get('amenity') == 'place_of_worship' or (tags.get('building') in ('church', 'mosque') and tags.get('historic')):
            ring = clean(pts)
            if len(ring) < 3 or polygon_area(ring) < 15.0:
                continue
            name = tags.get('name', '')
            if tags.get('building') == 'mosque' or 'Xhami' in name:
                if not (tags.get('historic') == 'ruins'):
                    continue
                kind = 'mosque_ruin'
            else:
                kind = 'domed' if any(k in name for k in DOMED) else 'church'
            # The castle's own churches, and St Michael's on the cliff below.
            if not (inside((cx, cz), wall) or edge_distance((cx, cz), wall) < 130.0):
                continue
            churches.append({'id': way['id'], 'name': name, 'kind': kind, 'ring': [[x, z] for x, z in ring]})
    towers = _towers(wall)
    # The flag over the southern spur, where the walls look down on Mangalem.
    south = max(wall, key=lambda p: p[1])
    data = {'wall': [[x, z] for x, z in wall], 'lines': lines, 'towers': towers, 'gate': gate,
            'churches': sorted(churches, key=lambda c: c['id']), 'flag': [south[0], south[1]]}
    with open(os.path.join(out_dir, 'castle.json'), 'w', encoding='utf8') as f:
        json.dump(data, f, separators=(',', ':'), ensure_ascii=False)
    perimeter = sum(math.dist(wall[i], wall[(i + 1) % len(wall)]) for i in range(len(wall)))
    log(f'  castle: curtain wall {perimeter:.0f} m, {len(towers)} towers, {len(lines)} more walls, '
        f'{len(churches)} churches and mosques, gate {"mapped" if gate else "missing"}')
    return data, origin


def clear_trees(props_path, data, origin):
    props = json.load(open(props_path, encoding='utf8'))
    wall = [tuple(p) for p in data['wall']]
    keep = []
    for t in props.get('trees', []):
        p = (t[0] - origin[0], t[2] - origin[1])
        if edge_distance(p, wall) < 5.0:
            continue
        if any(inside(p, [tuple(q) for q in c['ring']]) for c in data['churches']):
            continue
        keep.append(t)
    removed = len(props['trees']) - len(keep)
    props['trees'] = keep
    with open(props_path, 'w', encoding='utf8') as f:
        json.dump(props, f, separators=(',', ':'))
    log(f'  castle: {removed} trees cleared from the walls')


def process_city(cid, city, osm_path, out_dir):
    data, origin = bake(osm_path, out_dir, city)
    clear_trees(os.path.join(out_dir, 'props.json'), data, origin)
