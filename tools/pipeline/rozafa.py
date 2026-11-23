"""Rozafa castle above Shkodër, baked from its OpenStreetMap outlines.

Writes godot/assets/cities/shkoder/rozafa.json in metres relative to the
`rozafa` landmark anchor (x east, z south):
  wall   the curtain wall ring (way 319889243, barrier=city_wall)
  parts  every mapped structure inside it, each a footprint ring and a kind:
         gate (Barbakan), tower, citadel (Venetian complex / Don Zhon),
         church (St Stephen's church-mosque), minaret (its stump), museum (the Venetian arsenal
         that houses the castle museum), cistern, ruin
and drops props.json trees that stand on the walls or inside the courtyards
(the castle shows open grass and ruins there).

Run after build_city.py: python3 rozafa.py
Data (c) OpenStreetMap contributors (ODbL).
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from common import CACHE, OUT, Proj, log  # noqa: E402
from cities import CITIES  # noqa: E402

CITY = 'shkoder'
WALL_WAY = 319889243
# Mapped structures are inside this distance of the wall's centroid.
REACH = 200.0
TREE_CLEARANCE = 4.0


def kind_of(tags):
    name = tags.get('name', '').lower()
    if 'barbakan' in name:
        return 'gate'
    if 'museum' in name:
        return 'museum'
    if 'shën stefan' in name or 'stefanit' in name:
        return 'church'
    if 'don zhon' in name:
        return 'citadel'
    if tags.get('man_made') == 'tower':
        return 'tower'
    if 'cistern' in name:
        return 'cistern'
    if tags.get('building') or tags.get('historic') in ('ruins', 'castle'):
        return 'ruin'
    return None


def clean(ring):
    """Open ring (no repeated end), counter-clockwise in (x, z), no tiny edges."""
    if len(ring) > 1 and ring[0] == ring[-1]:
        ring = ring[:-1]
    out = []
    for p in ring:
        if not out or math.dist(p, out[-1]) > 0.5:
            out.append(p)
    if len(out) > 2 and math.dist(out[0], out[-1]) <= 0.5:
        out.pop()
    area = sum(out[i][0] * out[(i + 1) % len(out)][1] - out[(i + 1) % len(out)][0] * out[i][1] for i in range(len(out)))
    return out if area > 0 else out[::-1]


def polygon_area(ring):
    n = len(ring)
    return abs(sum(ring[i][0] * ring[(i + 1) % n][1] - ring[(i + 1) % n][0] * ring[i][1] for i in range(n))) / 2


def inside(p, ring):
    x, z = p
    hit = False
    for i in range(len(ring)):
        x0, z0 = ring[i]
        x1, z1 = ring[(i + 1) % len(ring)]
        if (z0 > z) != (z1 > z) and x < x0 + (z - z0) * (x1 - x0) / (z1 - z0):
            hit = not hit
    return hit


def edge_distance(p, ring):
    best = math.inf
    for i in range(len(ring)):
        ax, az = ring[i]
        bx, bz = ring[(i + 1) % len(ring)]
        dx, dz = bx - ax, bz - az
        t = max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - az) * dz) / (dx * dx + dz * dz or 1.0)))
        best = min(best, math.hypot(p[0] - ax - t * dx, p[1] - az - t * dz))
    return best


def bake(osm_path, out_dir, city=CITIES[CITY]):
    lat0, lon0 = city['origin']
    proj = Proj(lat0, lon0, city.get('latitude_compression', ()))
    anchor = next(lm for lm in city['landmarks'] if lm['id'] == 'rozafa')
    ax, az = proj.to_xz(*anchor['ll'])
    elements = json.load(open(osm_path, encoding='utf8'))['elements']
    nodes = {e['id']: (e['lat'], e['lon']) for e in elements if e['type'] == 'node' and 'lat' in e}

    def local(way):
        pts = [proj.to_xz(*nodes[n]) for n in way['nodes'] if n in nodes]
        return [(round(x - ax, 2), round(z - az, 2)) for x, z in pts]

    ways = {e['id']: e for e in elements if e['type'] == 'way'}
    wall = clean(local(ways[WALL_WAY]))
    parts = []
    for way in ways.values():
        tags = way.get('tags', {})
        if way['id'] == WALL_WAY or 'highway' in tags or way['nodes'][0] != way['nodes'][-1]:
            continue
        kind = kind_of(tags)
        if kind is None:
            continue
        ring = clean(local(way))
        if len(ring) < 3:
            continue
        cx = sum(p[0] for p in ring) / len(ring)
        cz = sum(p[1] for p in ring) / len(ring)
        # Inside the walls, or a tower set into them.
        if math.hypot(cx, cz) > REACH or not (inside((cx, cz), wall) or edge_distance((cx, cz), wall) < 12.0):
            continue
        parts.append({'kind': kind, 'id': way['id'], 'name': tags.get('name', ''),
                      'ring': [[x, z] for x, z in ring]})
    # Set against St Stephen's: the small square base is the minaret stump of
    # its mosque years.
    churches = [[tuple(q) for q in p['ring']] for p in parts if p['kind'] == 'church']
    kept = []
    for p in parts:
        cx = sum(q[0] for q in p['ring']) / len(p['ring'])
        cz = sum(q[1] for q in p['ring']) / len(p['ring'])
        if p['kind'] == 'ruin' and polygon_area(p['ring']) < 25.0 and any(
                inside((cx, cz), c) or edge_distance((cx, cz), c) < 4.0 for c in churches):
            p['kind'] = 'minaret'
        kept.append(p)
    parts = sorted(kept, key=lambda p: p['id'])
    data = {'wall': [[x, z] for x, z in wall], 'parts': parts}
    with open(os.path.join(out_dir, 'rozafa.json'), 'w', encoding='utf8') as f:
        json.dump(data, f, separators=(',', ':'), ensure_ascii=False)
    counts = {}
    for p in parts:
        counts[p['kind']] = counts.get(p['kind'], 0) + 1
    log(f'[{CITY}] rozafa: wall {len(wall)} points, ' + ', '.join(f'{n} {k}' for k, n in sorted(counts.items())))
    return data, (ax, az)


def clear_trees(props_path, wall, origin):
    """Keep the castle's courtyards and wall-walks clear of scattered trees."""
    props = json.load(open(props_path, encoding='utf8'))
    ax, az = origin
    keep = []
    for t in props.get('trees', []):
        p = (t[0] - ax, t[2] - az)
        if inside(p, wall) or edge_distance(p, wall) < TREE_CLEARANCE:
            continue
        keep.append(t)
    removed = len(props.get('trees', [])) - len(keep)
    props['trees'] = keep
    with open(props_path, 'w', encoding='utf8') as f:
        json.dump(props, f, separators=(',', ':'))
    log(f'[{CITY}] rozafa: {removed} trees cleared from the castle')


def process_city():
    out_dir = os.path.join(OUT, CITY)
    data, origin = bake(os.path.join(CACHE, 'osm', f'{CITY}.json'), out_dir)
    clear_trees(os.path.join(out_dir, 'props.json'), [tuple(p) for p in data['wall']], origin)


if __name__ == '__main__':
    process_city()
