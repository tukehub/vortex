"""Street furniture from OpenStreetMap (plan 3.4).

Adds a "street" entry to <city>/props.json:

  "street": {"traffic_light": [[x, z, yaw], ...], "bus_stop": [...],
             "bench": [...], "bin": [...], "bollard": [...]}

x/z are the city's local metres, yaw (radians) turns a model whose front looks
down -Z so it faces the road. Heights come from the terrain in the game.

Placement, from the mapped node:
  traffic_light  highway=traffic_signals; mapped on the carriageway, so the
                 pole moves to the right-hand kerb of its road
  bus_stop       highway=bus_stop or a public_transport=platform node; the
                 shelter stands at the kerb, its open front to the road
  bench, bin     amenity=bench / waste_basket, pushed off any carriageway
  bollard        barrier=bollard
Nothing stands on the race road: lights and stops move behind its edge, the
rest are dropped there. Items inside a building, a landmark keepout, open
water, or more than REACH metres from the track are dropped, as are repeats
of the same kind closer than its spacing. No item is invented: every one is
a mapped OSM node.

Only the street furniture near the circuit is fetched (Overpass, or the main
OSM API for a tile Overpass will not serve), cached per tile in tools/cache/osm/<city>_street/:
  python3 tools/pipeline/street_props.py tirane vlore
  (--api skips Overpass and reads the main OSM API, --force refetches)
Data (c) OpenStreetMap contributors, ODbL.
"""
import json
import math
import os
import sys
import urllib.parse

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from common import CACHE, OUT, Proj, ensure_dir, http_get, log  # noqa: E402
from cities import CITIES, ROAD_WIDTH  # noqa: E402

KINDS = ('traffic_light', 'bus_stop', 'bench', 'bin', 'bollard')
REACH = 250.0                      # metres from the track centreline
TRACK_KERB = 2.0                   # beyond the race road's half width
SPACING = {'traffic_light': 6.0, 'bus_stop': 15.0, 'bench': 1.2, 'bin': 1.0, 'bollard': 0.8}
CAP = {'traffic_light': 600, 'bus_stop': 300, 'bench': 1500, 'bin': 1000, 'bollard': 1500}
KERB_GAP = {'traffic_light': 1.0, 'bus_stop': 1.6, 'bench': 1.0, 'bin': 0.7, 'bollard': 0.0}
LANDMARK_CLEAR = 30.0              # around every landmark anchor
NO_CARS = {'footway', 'path', 'cycleway', 'pedestrian', 'steps', 'track', 'bridleway', 'corridor'}
ENDPOINT = 'https://overpass.private.coffee/api/interpreter'


def kind_of(tags):
    tags = tags or {}
    if tags.get('highway') == 'traffic_signals':
        return 'traffic_light'
    if tags.get('highway') == 'bus_stop' or tags.get('public_transport') == 'platform':
        return 'bus_stop'
    if tags.get('amenity') == 'bench':
        return 'bench'
    if tags.get('amenity') == 'waste_basket':
        return 'bin'
    if tags.get('barrier') == 'bollard':
        return 'bollard'
    return None


def yaw_facing(fx, fz):
    """Yaw that turns a -Z-facing model toward (fx, fz)."""
    return math.atan2(-fx, -fz)


class Track:
    """The race road's centreline as segments, for distance and side."""

    def __init__(self, pts, hw):
        p = np.asarray([[q[0], q[2]] for q in pts], np.float64)
        self.a = p
        self.b = np.roll(p, -1, axis=0)
        self.hw = float(hw)

    def nearest(self, x, z):
        """(distance, signed lateral, normal x, normal z) to the closest segment."""
        d = self.b - self.a
        ln2 = np.maximum((d * d).sum(1), 1e-9)
        t = np.clip(((x - self.a[:, 0]) * d[:, 0] + (z - self.a[:, 1]) * d[:, 1]) / ln2, 0.0, 1.0)
        cx = self.a[:, 0] + d[:, 0] * t
        cz = self.a[:, 1] + d[:, 1] * t
        dist2 = (x - cx) ** 2 + (z - cz) ** 2
        i = int(np.argmin(dist2))
        ln = math.sqrt(ln2[i])
        nx, nz = d[i, 1] / ln, -d[i, 0] / ln
        lateral = (x - cx[i]) * nx + (z - cz[i]) * nz
        return math.sqrt(dist2[i]), lateral, nx, nz


class Roads:
    """Mapped carriageways: segments with their half widths."""

    def __init__(self, segments):
        # rows: x1, z1, x2, z2, half width
        self.s = np.asarray(segments, np.float64).reshape(-1, 5)

    def nearest(self, x, z):
        """(distance, half width, point x, point z, direction x, direction z) or None."""
        if not len(self.s):
            return None
        a, b = self.s[:, 0:2], self.s[:, 2:4]
        d = b - a
        ln2 = np.maximum((d * d).sum(1), 1e-9)
        t = np.clip(((x - a[:, 0]) * d[:, 0] + (z - a[:, 1]) * d[:, 1]) / ln2, 0.0, 1.0)
        cx = a[:, 0] + d[:, 0] * t
        cz = a[:, 1] + d[:, 1] * t
        # Distance to the kerb, so a wide road wins over a lane mapped closer.
        gap = np.sqrt((x - cx) ** 2 + (z - cz) ** 2) - self.s[:, 4]
        i = int(np.argmin(gap))
        ln = math.sqrt(ln2[i])
        return (float(gap[i] + self.s[i, 4]), float(self.s[i, 4]), float(cx[i]), float(cz[i]),
                float(d[i, 0] / ln), float(d[i, 1] / ln))


def point_in_ring(x, z, ring):
    inside = False
    n = len(ring)
    j = n - 1
    for i in range(n):
        xi, zi = ring[i]
        xj, zj = ring[j]
        if (zi > z) != (zj > z) and x < (xj - xi) * (z - zi) / ((zj - zi) or 1e-12) + xi:
            inside = not inside
        j = i
    return inside


class Buildings:
    def __init__(self, rings, cell=50.0):
        self.cell = cell
        self.grid = {}
        for ring in rings:
            if len(ring) < 3:
                continue
            xs = [p[0] for p in ring]
            zs = [p[1] for p in ring]
            for gx in range(int(math.floor(min(xs) / cell)), int(math.floor(max(xs) / cell)) + 1):
                for gz in range(int(math.floor(min(zs) / cell)), int(math.floor(max(zs) / cell)) + 1):
                    self.grid.setdefault((gx, gz), []).append(ring)

    def contains(self, x, z):
        for ring in self.grid.get((int(math.floor(x / self.cell)), int(math.floor(z / self.cell))), ()):
            if point_in_ring(x, z, ring):
                return True
        return False


def place(items, track, roads, buildings, keepouts=(), anchors=(), water=None):
    """items: [(kind, x, z, way_dir or None)] -> {kind: [[x, z, yaw], ...]}.

    way_dir is the direction (dx, dz) of a carriageway the node is mapped on.
    """
    out = {k: [] for k in KINDS}
    clear = track.hw + TRACK_KERB
    ranked = []
    for kind, x, z, way_dir in items:
        dist, lateral, nx, nz = track.nearest(x, z)
        if dist > REACH:
            continue
        yaw = 0.0
        road = roads.nearest(x, z)
        if kind in ('traffic_light', 'bus_stop'):
            if way_dir is not None and road is not None:
                # Mapped on the carriageway: step out to its right-hand kerb.
                dx, dz = way_dir
                rx, rz = -dz, dx
                if kind == 'bus_stop' and road[0] > 0.5:
                    # A stop beside the road keeps its own side.
                    side = 1.0 if (x - road[2]) * rx + (z - road[3]) * rz >= 0 else -1.0
                else:
                    side = 1.0
                off = road[1] + KERB_GAP[kind]
                x, z = road[2] + rx * side * off, road[3] + rz * side * off
                yaw = yaw_facing(-rx * side, -rz * side) if kind == 'bus_stop' else yaw_facing(-dx, -dz)
            elif road is not None and road[0] < 25.0:
                fx, fz = road[2] - x, road[3] - z
                if road[0] < road[1] + KERB_GAP[kind]:
                    ln = math.hypot(fx, fz) or 1.0
                    off = road[1] + KERB_GAP[kind]
                    x, z = road[2] - fx / ln * off, road[3] - fz / ln * off
                yaw = yaw_facing(fx, fz)
            dist, lateral, nx, nz = track.nearest(x, z)
            if dist < clear + 0.5:
                # On or against the race road: behind its kerb, facing it.
                side = 1.0 if lateral >= 0 else -1.0
                cx, cz = x - nx * lateral, z - nz * lateral
                x, z = cx + nx * side * (clear + KERB_GAP[kind]), cz + nz * side * (clear + KERB_GAP[kind])
                if kind == 'bus_stop':
                    yaw = yaw_facing(-nx * side, -nz * side)
                dist, lateral, nx, nz = track.nearest(x, z)
        else:
            if dist < clear:
                continue
            if kind != 'bollard' and road is not None and road[0] < road[1] + KERB_GAP[kind]:
                fx, fz = x - road[2], z - road[3]
                ln = math.hypot(fx, fz)
                if ln < 0.05:
                    continue
                off = road[1] + KERB_GAP[kind]
                x, z = road[2] + fx / ln * off, road[3] + fz / ln * off
                dist, lateral, nx, nz = track.nearest(x, z)
            if kind == 'bench':
                if road is not None and road[0] < 15.0:
                    yaw = yaw_facing(road[2] - x, road[3] - z)
                else:
                    yaw = (hash((round(x), round(z))) % 628) / 100.0
        if dist < clear:
            continue
        if buildings.contains(x, z):
            continue
        if any(x0 <= x <= x1 and z0 <= z <= z1 for x0, z0, x1, z1 in keepouts):
            continue
        if any((x - ax) ** 2 + (z - az) ** 2 < LANDMARK_CLEAR ** 2 for ax, az in anchors):
            continue
        if water is not None and water(x, z):
            continue
        ranked.append((dist, kind, x, z, yaw))
    ranked.sort(key=lambda r: r[0])
    for dist, kind, x, z, yaw in ranked:
        rows = out[kind]
        if len(rows) >= CAP[kind]:
            continue
        gap = SPACING[kind]
        if any((x - r[0]) ** 2 + (z - r[1]) ** 2 < gap * gap for r in rows[-400:]):
            continue
        rows.append([round(x, 2), round(z, 2), round(math.atan2(math.sin(yaw), math.cos(yaw)), 3)])
    return out


# --------------------------------------------------------------------------- OSM
TILE = 700.0                       # metres per Overpass call


def tiles(proj, pts):
    """Overpass bounding boxes (s, w, n, e) covering the track grown by REACH.
    The public servers time out on one city-sized call (and an `around`
    polyline filter is slower still), so the box is cut into TILE squares and
    distance is filtered here."""
    xs = [p[0] for p in pts]
    zs = [p[2] for p in pts]
    pad = REACH + 40.0
    x0, x1 = min(xs) - pad, max(xs) + pad
    z0, z1 = min(zs) - pad, max(zs) + pad
    track = np.asarray([[p[0], p[2]] for p in pts])
    out = []
    for i in range(int(math.ceil((x1 - x0) / TILE))):
        for j in range(int(math.ceil((z1 - z0) / TILE))):
            ax, az = x0 + i * TILE, z0 + j * TILE
            bx, bz = min(x1, ax + TILE), min(z1, az + TILE)
            # Skip tiles nowhere near the circuit.
            cx = np.clip(track[:, 0], ax, bx)
            cz = np.clip(track[:, 1], az, bz)
            if np.min((track[:, 0] - cx) ** 2 + (track[:, 1] - cz) ** 2) > pad * pad:
                continue
            s_lat, w_lon = proj.to_ll(ax, bz)
            n_lat, e_lon = proj.to_ll(bx, az)
            out.append((float(s_lat), float(w_lon), float(n_lat), float(e_lon)))
    return out


def query(bbox):
    bb = '%.6f,%.6f,%.6f,%.6f' % bbox
    return f"""[out:json][timeout:120];
(
  node["highway"~"^(traffic_signals|bus_stop)$"]({bb});
  node["public_transport"="platform"]({bb});
  node["amenity"~"^(bench|waste_basket)$"]({bb});
  node["barrier"="bollard"]({bb});
);
out body;
(
  way["highway"]({bb});
  way["building"]({bb});
);
out body;
>;
out skel qt;
"""


def api_elements(folder, bbox):
    """The same tile from the main OSM API (fetch_osm_api's 2x2 sub-tiles),
    when Overpass will not answer. The API returns every node of a way that
    crosses the box, so roads and buildings arrive whole."""
    import fetch_osm_api
    s_, w_, n_, e_ = bbox
    saved = fetch_osm_api.TILES
    fetch_osm_api.TILES = 2
    try:
        paths = fetch_osm_api.fetch_tiles(os.path.join(folder, 'api_%.5f_%.5f_%.5f_%.5f' % bbox), s_, w_, n_, e_)
    finally:
        fetch_osm_api.TILES = saved
    nodes, ways, _ = fetch_osm_api.merge(paths)
    out = []
    for wid, w in ways.items():
        if 'highway' in w['tags'] or 'building' in w['tags']:
            out.append({'type': 'way', 'id': wid, 'nodes': w['nodes'], 'tags': w['tags']})
    for nid, nd in nodes.items():
        item = {'type': 'node', 'id': nid, 'lat': nd['lat'], 'lon': nd['lon']}
        if nd['tags']:
            item['tags'] = nd['tags']
        out.append(item)
    return out


def fetch(cid, proj, pts, force=False, api=False):
    """All tiles' elements, each tile cached under tools/cache/osm/<city>_street/.
    Overpass first; a tile it will not serve comes from the main OSM API."""
    folder = ensure_dir(os.path.join(CACHE, 'osm', f'{cid}_street'))
    elements = []
    boxes = tiles(proj, pts)
    for k, bbox in enumerate(boxes):
        path = os.path.join(folder, '%.5f_%.5f_%.5f_%.5f.json' % bbox)
        if not (os.path.exists(path) and os.path.getsize(path) > 100) or force:
            data = urllib.parse.urlencode({'data': query(bbox)}).encode()
            try:
                if api:
                    raise RuntimeError('--api')
                log(f'[{cid}] tile {k + 1}/{len(boxes)} {ENDPOINT}')
                blob = http_get(ENDPOINT, data=data, timeout=240, retries=2)
                if not blob.lstrip().startswith(b'{'):
                    raise RuntimeError(blob[:200])
            except Exception as e:  # noqa: BLE001
                log(f'  overpass failed ({e}); main OSM API instead')
                blob = json.dumps({'elements': api_elements(folder, bbox)}).encode()
            with open(path + '.part', 'wb') as f:
                f.write(blob)
            os.replace(path + '.part', path)
        with open(path, encoding='utf8') as f:
            elements += json.load(f)['elements']
    return elements


def from_osm(elements, proj):
    """Items, carriageway segments and building rings from Overpass elements."""
    nodes, ways = {}, []
    for el in elements:
        if el['type'] == 'node':
            x, z = proj.to_xz(el['lat'], el['lon'])
            old = nodes.get(el['id'])
            nodes[el['id']] = (float(x), float(z), el.get('tags') or (old[2] if old else None))
        elif el['type'] == 'way':
            ways.append(el)
    segments, rings, on_way = [], [], {}
    seen = set()
    for w in ways:
        if w['id'] in seen:
            continue
        seen.add(w['id'])
        tags = w.get('tags', {})
        pts = [nodes[n] for n in w.get('nodes', []) if n in nodes]
        if 'building' in tags:
            if len(pts) >= 4:
                rings.append([(p[0], p[1]) for p in pts])
            continue
        hw = tags.get('highway')
        if hw not in ROAD_WIDTH or hw in NO_CARS:
            continue
        half = float(ROAD_WIDTH[hw]) / 2.0
        ids = [n for n in w.get('nodes', []) if n in nodes]
        for i in range(len(ids) - 1):
            a, b = nodes[ids[i]], nodes[ids[i + 1]]
            segments.append((a[0], a[1], b[0], b[1], half))
        for i, n in enumerate(ids):
            a = nodes[ids[max(0, i - 1)]]
            b = nodes[ids[min(len(ids) - 1, i + 1)]]
            ln = math.hypot(b[0] - a[0], b[1] - a[1])
            if ln > 0.01 and n not in on_way:
                on_way[n] = ((b[0] - a[0]) / ln, (b[1] - a[1]) / ln)
    items = []
    for nid, (x, z, tags) in nodes.items():
        kind = kind_of(tags)
        if kind:
            items.append((kind, x, z, on_way.get(nid)))
    items.sort(key=lambda it: (KINDS.index(it[0]) if it[0] != 'bus_stop' else -1, it[1], it[2]))
    return items, segments, rings


def keepouts_for(city, proj):
    # Lazy: build_city pulls in the whole pipeline.
    from build_city import landmark_clearance_zones
    return landmark_clearance_zones(city, proj)


def water_test(out_dir):
    tj = json.load(open(os.path.join(out_dir, 'terrain.json')))
    path = os.path.join(out_dir, 'water_near.bin')
    if 'water' not in tj or not os.path.exists(path):
        return None
    nm = tj['near']
    mask = np.fromfile(path, np.uint8).reshape(nm['n'], nm['n'])

    def wet(x, z):
        ix = int(round((x - nm['x0']) / nm['cell']))
        iz = int(round((z - nm['z0']) / nm['cell']))
        if 0 <= ix < nm['n'] and 0 <= iz < nm['n']:
            return mask[iz, ix] >= 128
        return False
    return wet


def process_city(cid, force=False, api=False):
    city = CITIES[cid]
    out_dir = os.path.join(OUT, cid)
    lat0, lon0 = city['origin']
    proj = Proj(lat0, lon0, city.get('latitude_compression', ()))
    tj = json.load(open(os.path.join(out_dir, 'track.json')))
    props_path = os.path.join(out_dir, 'props.json')
    props = json.load(open(props_path))
    items, segments, rings = from_osm(fetch(cid, proj, tj['pts'], force, api), proj)
    anchors = [(float(a['x']), float(a['z'])) for a in props.get('landmarks', [])]
    street = place(items, Track(tj['pts'], tj['hw']), Roads(segments), Buildings(rings),
                   keepouts_for(city, proj), anchors, water_test(out_dir))
    props['street'] = street
    with open(props_path, 'w', encoding='utf8') as f:
        json.dump(props, f, separators=(',', ':'))
    log(f'[{cid}] street: ' + ', '.join(f'{len(street[k])} {k}' for k in KINDS)
        + f' from {len(items)} mapped nodes')
    return street


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    for cid in args or ['tirane', 'vlore']:
        process_city(cid, force='--force' in sys.argv, api='--api' in sys.argv)
