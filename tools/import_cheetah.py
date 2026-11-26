"""Convert mk2design's CC BY 4.0 "Generic Supercar Cheetah" to the Vortex rig.

Source: https://sketchfab.com/3d-models/f5420af7b30c4e8c874be33cc58724f2
Author: mk2design (instagram.com/mk2.design), licensed CC BY 4.0.
Download the GLB archive from that page (a Sketchfab account is needed), then:

  python3 tools/import_cheetah.py source.glb godot/assets/cars

Source GLB SHA-256: 663d575471ac634cca728a07a7562bb6856b0aba1ae705dd24b872d458b17714

Plain Python (numpy, Pillow), no Blender. The source's node transforms are
baked into the vertices, which keep the source's metric scale so the tyres
stay at the 0.38 m radius the tyre and rim shaders read; the profile's
visual_scale brings the car to the game's footprint. The car is regrouped
into the CarRoot contract of docs/vehicle-rigs.md, and its materials are
renamed to the runtime roles (paint, glass, interior, tyre, rim, light_front,
light_rear). The baked drop shadow is left out (the game draws its own). The
detail atlas ships as three PNGs next to the GLB, imported VRAM-compressed;
the plate's EU band is painted over in plain blue.
"""
import hashlib
import json
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

SOURCE_SHA256 = '663d575471ac634cca728a07a7562bb6856b0aba1ae705dd24b872d458b17714'
COMP = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NCOMP = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}
WHEELS = {'FL': 'Wheel_FL', 'FR': 'Wheel_FR', 'RL': 'Wheel_RL', 'RR': 'Wheel_RR'}
ATLAS = 'cheetah_atlas'


# ------------------------------------------------------------------ reading
def load_glb(path):
    data = Path(path).read_bytes()
    if data[:4] != b'glTF':
        raise SystemExit('not a GLB: ' + str(path))
    json_len = struct.unpack('<I', data[12:16])[0]
    doc = json.loads(data[20:20 + json_len])
    off = 20 + json_len
    bin_len = struct.unpack('<I', data[off:off + 4])[0]
    return doc, data[off + 8:off + 8 + bin_len]


def accessor(doc, blob, i):
    a = doc['accessors'][i]
    view = doc['bufferViews'][a['bufferView']]
    dt = np.dtype(COMP[a['componentType']])
    n = NCOMP[a['type']]
    start = view.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = view.get('byteStride', 0) or dt.itemsize * n
    raw = np.frombuffer(blob, np.uint8, stride * (a['count'] - 1) + dt.itemsize * n, start)
    rows = np.lib.stride_tricks.as_strided(raw, (a['count'], dt.itemsize * n), (stride, 1)).copy()
    arr = rows.view(dt).reshape(a['count'], n)
    return arr if n > 1 else arr[:, 0]


def node_matrix(node):
    if 'matrix' in node:
        return np.array(node['matrix'], float).reshape(4, 4).T
    m = np.eye(4)
    if 'scale' in node:
        m = np.diag(list(node['scale']) + [1.0]) @ m
    if 'rotation' in node:
        x, y, z, w = node['rotation']
        r = np.eye(4)
        r[:3, :3] = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
        m = r @ m
    if 'translation' in node:
        t = np.eye(4)
        t[:3, 3] = node['translation']
        m = t @ m
    return m


def parts(doc, blob):
    """Every primitive in world space (metres, +Y up, nose -Z)."""
    out = []

    def walk(i, parent):
        node = doc['nodes'][i]
        world = parent @ node_matrix(node)
        if 'mesh' in node:
            normal_m = np.linalg.inv(world[:3, :3]).T
            for prim in doc['meshes'][node['mesh']]['primitives']:
                at = prim['attributes']
                pos = accessor(doc, blob, at['POSITION']).astype(float) @ world[:3, :3].T + world[:3, 3]
                nor = accessor(doc, blob, at['NORMAL']).astype(float) @ normal_m.T
                nor /= np.maximum(np.linalg.norm(nor, axis=1, keepdims=True), 1e-12)
                uv = accessor(doc, blob, at['TEXCOORD_0']).astype(float) if 'TEXCOORD_0' in at else np.zeros((len(pos), 2))
                tri = accessor(doc, blob, prim['indices']).astype(np.int64).reshape(-1, 3)
                if np.linalg.det(world[:3, :3]) < 0:
                    tri = tri[:, ::-1]
                out.append({'name': node.get('name', ''), 'material': doc['materials'][prim['material']]['name'],
                            'pos': pos, 'nor': nor, 'uv': uv, 'tri': tri})
        for child in node.get('children', []):
            walk(child, world)

    for root in doc['scenes'][doc.get('scene', 0)]['nodes']:
        walk(root, np.eye(4))
    return out


def subset(part, keep):
    """The triangles of `part` where `keep` (per triangle) is true, compacted."""
    tri = part['tri'][keep]
    used, index = np.unique(tri.ravel(), return_inverse=True)
    return dict(part, pos=part['pos'][used], nor=part['nor'][used], uv=part['uv'][used], tri=index.reshape(-1, 3))


# ------------------------------------------------------------------ writing
class Writer:
    def __init__(self):
        self.doc = {'asset': {'version': '2.0', 'generator': 'Vortex tools/import_cheetah.py'},
                    'scene': 0, 'scenes': [{'nodes': [0]}], 'nodes': [{'name': 'CarRoot', 'children': []}],
                    'meshes': [], 'materials': [], 'accessors': [], 'bufferViews': [], 'buffers': [],
                    'images': [], 'textures': [], 'samplers': [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 10497, 'wrapT': 10497}]}
        self.blob = bytearray()
        self.materials = {}

    def _view(self, data, target):
        while len(self.blob) % 4:
            self.blob.append(0)
        self.doc['bufferViews'].append({'buffer': 0, 'byteOffset': len(self.blob), 'byteLength': len(data), 'target': target})
        self.blob.extend(data)
        return len(self.doc['bufferViews']) - 1

    def _accessor(self, arr, kind, component, target, bounds=False):
        view = self._view(np.ascontiguousarray(arr).tobytes(), target)
        a = {'bufferView': view, 'componentType': component, 'count': int(len(arr)), 'type': kind}
        if bounds:
            a['min'] = [float(v) for v in arr.min(0)]
            a['max'] = [float(v) for v in arr.max(0)]
        self.doc['accessors'].append(a)
        return len(self.doc['accessors']) - 1

    def texture(self, uri):
        self.doc['images'].append({'uri': uri})
        self.doc['textures'].append({'sampler': 0, 'source': len(self.doc['images']) - 1})
        return len(self.doc['textures']) - 1

    def material(self, name, spec=None):
        if name not in self.materials:
            m = {'name': name, 'pbrMetallicRoughness': {}}
            m.update(spec or {})
            self.doc['materials'].append(m)
            self.materials[name] = len(self.doc['materials']) - 1
        return self.materials[name]

    def node(self, name, surfaces, at=(0.0, 0.0, 0.0), turned=False):
        """`surfaces`: [(material name, part)], each part in the node's own space."""
        node = {'name': name}
        if any(abs(v) > 0 for v in at):
            node['translation'] = [float(v) for v in at]
        if turned:
            node['rotation'] = [0.0, 1.0, 0.0, 0.0]
        prims = []
        for material, p in surfaces:
            if len(p['tri']) == 0:
                continue
            prims.append({'attributes': {
                'POSITION': self._accessor(p['pos'].astype(np.float32), 'VEC3', 5126, 34962, True),
                'NORMAL': self._accessor(p['nor'].astype(np.float32), 'VEC3', 5126, 34962),
                'TEXCOORD_0': self._accessor(p['uv'].astype(np.float32), 'VEC2', 5126, 34962)},
                'indices': self._accessor(p['tri'].astype(np.uint32).ravel(), 'SCALAR', 5125, 34963),
                'material': self.material(material)})
        if prims:
            self.doc['meshes'].append({'name': name, 'primitives': prims})
            node['mesh'] = len(self.doc['meshes']) - 1
        self.doc['nodes'].append(node)
        self.doc['nodes'][0]['children'].append(len(self.doc['nodes']) - 1)

    def save(self, path):
        while len(self.blob) % 4:
            self.blob.append(0)
        self.doc['buffers'] = [{'byteLength': len(self.blob)}]
        js = json.dumps(self.doc, separators=(',', ':')).encode()
        js += b' ' * (-len(js) % 4)
        out = struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(self.blob))
        out += struct.pack('<II', len(js), 0x4E4F534A) + js
        out += struct.pack('<II', len(self.blob), 0x004E4942) + bytes(self.blob)
        Path(path).write_bytes(out)


def moved(p, offset, turned=False):
    """`p` relative to `offset`; `turned` also half-turns it about Y."""
    pos = p['pos'] - offset
    nor = p['nor'].copy()
    if turned:
        pos = pos * [-1.0, 1.0, -1.0]
        nor = nor * [-1.0, 1.0, -1.0]
    return dict(p, pos=pos, nor=nor)


def images(source_doc, blob, out_dir):
    """The detail atlas (colour, normal, metal-roughness) as PNGs next to the GLB."""
    import io

    material = next(m for m in source_doc['materials'] if m['name'] == 'Cheetah_Textures')
    pbr = material['pbrMetallicRoughness']
    picks = {'': pbr['baseColorTexture']['index'], '_nor': material['normalTexture']['index'],
             '_mr': pbr['metallicRoughnessTexture']['index']}
    for suffix, tex in picks.items():
        view = source_doc['bufferViews'][source_doc['images'][source_doc['textures'][tex]['source']]['bufferView']]
        start = view.get('byteOffset', 0)
        img = Image.open(io.BytesIO(blob[start:start + view['byteLength']])).convert('RGB')
        if suffix == '':
            # The plate's EU band (country letters, ring of stars): plain blue.
            box = (330, 845, 344, 882)
            colours = img.crop(box).getcolors(4096)
            band = max(colours)[1]
            img.paste(band, box)
        else:
            img = img.resize((512, 512), Image.LANCZOS)
        img.save(Path(out_dir) / f'{ATLAS}{suffix}.png', optimize=True)


def main():
    if len(sys.argv) != 3:
        raise SystemExit('Expected: source.glb output_dir')
    source, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    if digest != SOURCE_SHA256:
        print('warning: source SHA-256 %s differs from the pinned %s' % (digest, SOURCE_SHA256))
    doc, blob = load_glb(source)
    all_parts = [p for p in parts(doc, blob) if p['material'] != 'Cheetah_Shadow']

    # Ground at y = 0 (tyre contact), origin midway between the axles.
    tyres = {k: next(p for p in all_parts if p['name'] == f'Wh_{k}_Cheetah_Textures_0') for k in WHEELS}
    centres = {k: (p['pos'].min(0) + p['pos'].max(0)) * 0.5 for k, p in tyres.items()}
    ground = min(p['pos'][:, 1].min() for p in tyres.values())
    mid_z = (centres['FL'][2] + centres['RL'][2]) * 0.5
    shift = np.array([0.0, ground, mid_z])
    for p in all_parts:
        p['pos'] = p['pos'] - shift
    for k in centres:
        centres[k] = centres[k] - shift

    def find(name):
        return next(p for p in all_parts if p['name'] == name)

    # The detail atlas mesh: rear reflectors, plate, carbon, and the front
    # lamp strips (the white vertical-line tile, u 0.50-0.56) which become
    # the headlights.
    details = find('Details_Cheetah_Textures_0')
    centre_uv = details['uv'][details['tri']].mean(1)
    front_strip = (centre_uv[:, 0] > 0.5) & (centre_uv[:, 0] < 0.56) & (details['pos'][details['tri']].mean(1)[:, 2] < 0)

    w = Writer()
    atlas = w.texture(f'{ATLAS}.png')
    atlas_nor = w.texture(f'{ATLAS}_nor.png')
    atlas_mr = w.texture(f'{ATLAS}_mr.png')
    w.material('paint', {'pbrMetallicRoughness': {'baseColorFactor': [0.02, 0.16, 0.29, 1.0], 'metallicFactor': 0.5, 'roughnessFactor': 0.2}})
    w.material('cheetah_plastic', {'pbrMetallicRoughness': {'baseColorFactor': [0.013, 0.013, 0.014, 1.0], 'metallicFactor': 0.0, 'roughnessFactor': 0.72}})
    w.material('cheetah_black', {'pbrMetallicRoughness': {'baseColorFactor': [0.004, 0.004, 0.004, 1.0], 'metallicFactor': 0.0, 'roughnessFactor': 0.9}})
    w.material('chrome', {'pbrMetallicRoughness': {'baseColorFactor': [0.9, 0.9, 0.92, 1.0], 'metallicFactor': 1.0, 'roughnessFactor': 0.12}})
    w.material(ATLAS, {'pbrMetallicRoughness': {'baseColorTexture': {'index': atlas}, 'metallicRoughnessTexture': {'index': atlas_mr},
                                                'metallicFactor': 1.0, 'roughnessFactor': 1.0},
                       'normalTexture': {'index': atlas_nor}})

    w.node('Body', [('paint', find('Body_Cheetah_Body_0')),
                    ('cheetah_plastic', find('Details_Cheetah_Plastic_0')),
                    ('cheetah_black', find('Details_Cheetah_Black_0')),
                    ('chrome', find('Details_Cheetah_Chrome_0')),
                    (ATLAS, subset(details, ~front_strip))])
    w.node('Glass', [('glass', find('Glass_Cheetah_Glass_0'))])
    w.node('Interior', [('interior', find('Interior_Cheetah_Black_0'))])
    w.node('Headlights', [('light_front', subset(details, front_strip))])
    w.node('BrakeLights', [('light_rear', find('Glass_Red_Cheetah_Glass_Red_0'))])
    for key, node_name in WHEELS.items():
        left = key.endswith('L')
        c = centres[key]
        tyre_part = tyres[key]
        # The wheel's atlas mesh is the tyre plus the brake disc (the disc
        # tile sits at the top right of the atlas).
        uv_c = tyre_part['uv'][tyre_part['tri']].mean(1)
        disc = (uv_c[:, 0] > 0.8) & (uv_c[:, 1] < 0.1)
        w.node(node_name, [('tyre', moved(subset(tyre_part, ~disc), c, left)),
                           ('rim', moved(find(f'Wh_{key}_Cheetah_Chrome_0'), c, left)),
                           (ATLAS, moved(subset(tyre_part, disc), c, left))], at=c, turned=left)
        # Calipers steer with the wheel but do not spin (CarVisual reads the
        # optional Caliper_* nodes of the rig).
        w.node('Caliper_' + key, [(ATLAS, moved(find(f'Caliper_{key}_Cheetah_Textures_0'), c, left))], at=c, turned=left)
    # Quad exhausts: two pipes either side at x 0.45 and 0.75; one nitro
    # flame per side between them, just behind the tips.
    exhaust = find('Details_Cheetah_Chrome_0')
    tips = exhaust['pos'][(exhaust['pos'][:, 2] > 2.15 - shift[2]) & (exhaust['pos'][:, 1] < 0.5)]
    for side, name in ((-1, 'Nitro_L'), (1, 'Nitro_R')):
        pipes = tips[np.sign(tips[:, 0]) == side]
        w.node(name, [], at=(float(np.mean([pipes[:, 0].min(), pipes[:, 0].max()])), float(pipes[:, 1].mean()), float(pipes[:, 2].max()) + 0.02))
    out_dir.mkdir(parents=True, exist_ok=True)
    w.save(out_dir / 'cheetah.glb')
    images(doc, blob, out_dir)
    lo = np.min([p['pos'].min(0) for p in all_parts], axis=0)
    hi = np.max([p['pos'].max(0) for p in all_parts], axis=0)
    print('cheetah.glb: extents', np.round(lo, 3), np.round(hi, 3))
    for k, c in centres.items():
        print('wheel', k, np.round(c, 4))
    print('wheel radius %.4f wheelbase %.4f' % (centres['FL'][1], centres['RL'][2] - centres['FL'][2]))


if __name__ == '__main__':
    main()
