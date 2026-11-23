"""Remove a mapped building from an already built buildings.glb.

On a full rebuild, cities.py 'landmark_buildings' keeps an OSM building out
of buildings.glb so a landmark model can stand in its place. For a dataset
that is already built, this drops the triangles whose centre lies inside
that building's footprint (grown by BUFFER metres, which takes the walls
too). Only the index lists change, rewritten in place, so every other byte
of the file stays as it was:
  python3 tools/pipeline/glb_cut.py vlore 1222923149

Footprints come from the OSM tiles street_props.py cached for the city
(tools/cache/osm/<city>_street/), else the main OSM API.
"""
import glob
import json
import os
import struct
import sys
import urllib.request

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from common import CACHE, OUT, UA, Proj, log  # noqa: E402
from cities import CITIES  # noqa: E402

BUFFER = 0.8


def footprint(cid, way_id, proj):
    """Local (x, z) ring of an OSM way."""
    for path in glob.glob(os.path.join(CACHE, 'osm', f'{cid}_street', '*.json')):
        with open(path, encoding='utf8') as f:
            elements = json.load(f)['elements']
        ways = [e for e in elements if e['type'] == 'way' and e['id'] == way_id]
        if ways:
            nodes = {e['id']: e for e in elements if e['type'] == 'node'}
            if all(n in nodes for n in ways[0]['nodes']):
                return [tuple(float(v) for v in proj.to_xz(nodes[n]['lat'], nodes[n]['lon'])) for n in ways[0]['nodes']]
    req = urllib.request.Request(f'https://api.openstreetmap.org/api/0.6/way/{way_id}/full.json', headers={'User-Agent': UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        elements = json.load(r)['elements']
    nodes = {e['id']: e for e in elements if e['type'] == 'node'}
    way = next(e for e in elements if e['type'] == 'way')
    return [tuple(float(v) for v in proj.to_xz(nodes[n]['lat'], nodes[n]['lon'])) for n in way['nodes']]


def _inside(px, pz, ring):
    inside = np.zeros(px.shape, bool)
    n = len(ring)
    for i in range(n):
        x1, z1 = ring[i]
        x2, z2 = ring[(i + 1) % n]
        cross = (z1 > pz) != (z2 > pz)
        xi = x1 + (pz - z1) * (x2 - x1) / ((z2 - z1) if z2 != z1 else 1e-12)
        inside ^= cross & (px < xi)
    return inside


def _edge_distance(px, pz, ring):
    d = np.full(px.shape, np.inf)
    n = len(ring)
    for i in range(n):
        a = np.array(ring[i])
        b = np.array(ring[(i + 1) % n])
        ab = b - a
        t = np.clip(((px - a[0]) * ab[0] + (pz - a[1]) * ab[1]) / max(ab @ ab, 1e-12), 0, 1)
        d = np.minimum(d, np.hypot(px - (a[0] + ab[0] * t), pz - (a[1] + ab[1] * t)))
    return d


def cut(glb_path, rings):
    with open(glb_path, 'rb') as f:
        data = bytearray(f.read())
    jlen = struct.unpack_from('<I', data, 12)[0]
    gltf = json.loads(data[20:20 + jlen])
    bin_start = 20 + jlen + 8
    removed = 0
    for node in gltf['nodes']:
        if 'mesh' not in node:
            continue
        tx, _, tz = node.get('translation', [0.0, 0.0, 0.0])
        for prim in gltf['meshes'][node['mesh']]['primitives']:
            pos_acc = gltf['accessors'][prim['attributes']['POSITION']]
            pos_view = gltf['bufferViews'][pos_acc['bufferView']]
            stride = pos_view.get('byteStride', 12)
            base = bin_start + pos_view.get('byteOffset', 0) + pos_acc.get('byteOffset', 0)
            raw = np.frombuffer(bytes(data[base:base + stride * pos_acc['count']]), np.uint8).reshape(pos_acc['count'], stride)
            pos = raw[:, :12].copy().view('<f4').reshape(-1, 3)
            idx_acc = gltf['accessors'][prim['indices']]
            idx_view = gltf['bufferViews'][idx_acc['bufferView']]
            ctype = {5121: '<u1', 5123: '<u2', 5125: '<u4'}[idx_acc['componentType']]
            size = np.dtype(ctype).itemsize
            ibase = bin_start + idx_view.get('byteOffset', 0) + idx_acc.get('byteOffset', 0)
            idx = np.frombuffer(bytes(data[ibase:ibase + size * idx_acc['count']]), ctype).reshape(-1, 3)
            centre = pos[idx].mean(axis=1)
            cx = centre[:, 0] + tx
            cz = centre[:, 2] + tz
            drop = np.zeros(len(idx), bool)
            for ring in rings:
                drop |= _inside(cx, cz, ring) | (_edge_distance(cx, cz, ring) <= BUFFER)
            if not drop.any():
                continue
            keep = idx[~drop].astype(ctype).tobytes()
            data[ibase:ibase + len(keep)] = keep
            idx_acc['count'] = int((~drop).sum() * 3)
            removed += int(drop.sum())
    # Rewrite the JSON chunk (padded to the same length when it fits).
    text = json.dumps(gltf, separators=(',', ':')).encode()
    if len(text) > jlen:
        raise RuntimeError('JSON chunk grew; rebuild the city instead')
    text += b' ' * (jlen - len(text))
    data[20:20 + jlen] = text
    with open(glb_path, 'wb') as f:
        f.write(data)
    return removed


def process(cid, way_ids):
    city = CITIES[cid]
    proj = Proj(*city['origin'], city.get('latitude_compression', ()))
    rings = []
    for way_id in way_ids:
        ring = footprint(cid, way_id, proj)
        if ring[0] == ring[-1]:
            ring = ring[:-1]
        rings.append(ring)
    removed = cut(os.path.join(OUT, cid, 'buildings.glb'), rings)
    log(f'[{cid}] removed {removed} triangles of buildings {way_ids}')
    return removed


if __name__ == '__main__':
    process(sys.argv[1], [int(w) for w in sys.argv[2:]])
