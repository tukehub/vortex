"""Bake street-facing Tirana facade relief from the shipped building extrusions."""
from collections import defaultdict
import json
import math
from pathlib import Path
import random
import struct

import numpy as np

from common import OUT
from glb import GLB

LENGTH = 450.0
REACH = 49.0
CHUNK = 90.0
PLASTER = ((.78, .72, .62), (.81, .74, .68), (.66, .71, .71), (.76, .77, .73),
           (.69, .54, .45), (.74, .68, .55), (.68, .73, .65))
FRAME = (.21, .24, .23)
STONE = (.59, .54, .47)


def source_walls(path):
    """The extrusion writer emits four vertices per wall, bottom edge first."""
    data = path.read_bytes()
    magic, version, _, json_size, _ = struct.unpack_from('<4sIIII', data)
    if magic != b'glTF' or version != 2:
        raise ValueError(f'Unexpected building GLB: {path}')
    model = json.loads(data[20:20 + json_size])
    binary = memoryview(data)[28 + json_size:]

    def attribute(primitive, name, dtype, width):
        accessor = model['accessors'][primitive['attributes'][name]]
        view = model['bufferViews'][accessor['bufferView']]
        offset = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
        return np.frombuffer(binary, dtype, accessor['count'] * width, offset).reshape(-1, width)

    for node in model['nodes']:
        primitive = model['meshes'][node['mesh']]['primitives'][0]
        if model['materials'][primitive['material']]['name'] != 'facade':
            raise ValueError('Expected the first building surface to be the facade')
        points = attribute(primitive, 'POSITION', '<f4', 3) + node['translation']
        normals = attribute(primitive, 'NORMAL', '<f4', 3)
        colors = attribute(primitive, 'COLOR_0', 'u1', 4)
        yield from zip(points.reshape(-1, 4, 3), normals[::4], colors[::4], strict=True)


def linear(rgb):
    return tuple(channel / 12.92 if channel <= .04045 else ((channel + .055) / 1.055) ** 2.4
                 for channel in rgb)


class Elevation:
    def __init__(self, batch, a, b, normal):
        self.batch = batch
        self.a = a
        self.normal = normal
        self.axis = (b - a) / np.linalg.norm(b - a)

    def point(self, x, y, depth):
        point = self.a + x * self.axis + depth * self.normal
        point[1] += y
        return point

    def quad(self, corners, color, kind=0.0):
        p = np.array([self.point(*corner) for corner in corners])
        normal = np.cross(p[1] - p[0], p[2] - p[0])
        normal /= np.linalg.norm(normal)
        self.batch.append((p, normal, (*linear(color), kind)))

    def face(self, x0, y0, x1, y1, depth, color, kind=0.0):
        self.quad(((x1, y0, depth), (x0, y0, depth), (x0, y1, depth), (x1, y1, depth)), color, kind)

    def reveal(self, x0, y0, x1, y1, back, front, color, outside=False):
        sides = (
            ((x0, y0, back), (x0, y0, front), (x0, y1, front), (x0, y1, back)),
            ((x1, y0, front), (x1, y0, back), (x1, y1, back), (x1, y1, front)),
            ((x0, y0, back), (x1, y0, back), (x1, y0, front), (x0, y0, front)),
            ((x0, y1, front), (x1, y1, front), (x1, y1, back), (x0, y1, back)),
        )
        for side in sides:
            self.quad(side[::-1] if outside else side, color)

    def band(self, x0, y0, x1, y1, back, front, color):
        self.face(x0, y0, x1, y1, front, color, .25)
        self.reveal(x0, y0, x1, y1, back, front, color, outside=True)

    def bay(self, x, y, width, height, wall, rng, ground, style, rank):
        shop = ground and style != 1 and rank % 3 != 2
        opening = width * (.83 if shop else (.57 if ground else (.66, .51, .75)[style]))
        tall = height * (.73 if ground else (.62, .58, .75)[style])
        lo = x + (width - opening) * .5
        hi = lo + opening
        sill = y + (height * .18 if ground else (height - tall) * .44)
        lintel = sill + tall
        depth = .21 if ground else .15
        self.face(x, y, lo, y + height, depth, wall)
        self.face(hi, y, x + width, y + height, depth, wall)
        self.face(lo, y, hi, sill, depth, wall)
        self.face(lo, lintel, hi, y + height, depth, wall)
        self.reveal(lo, sill, hi, lintel, .035, depth, tuple(v * .73 for v in wall))
        self.face(lo, sill, hi, lintel, .036, FRAME, .25)
        frame = .095 if ground else .064
        glass = (.22, .29, .31) if rng.random() < .58 else (.29, .34, .33)
        lit = .78 if rng.random() < (.48 if ground else .26) else .52
        centre = (lo + hi) * .5
        self.face(lo + frame, sill + frame, centre - frame * .45, lintel - frame, .044, glass, lit)
        self.face(centre + frame * .45, sill + frame, hi - frame, lintel - frame, .044, glass, lit)
        if ground:
            # Transoms and muted fascia distinguish retail from residential doors.
            self.face(lo + frame, lintel - tall * .23, hi - frame, lintel - tall * .23 + .075, .052, FRAME, .25)
            if shop:
                awning = ((.27, .35, .32), (.40, .25, .19), (.30, .33, .39))[rank % 3]
                self.band(lo - .12, lintel + .07, hi + .12, lintel + .28, depth, .62, awning)
        else:
            self.band(lo - .07, sill - .085, hi + .07, sill + .005, depth, .27, STONE)
            if style == 0 and rng.random() < .31 and y < 17.0:
                self.band(lo - .12, y + .08, hi + .12, y + .25, depth, .93, STONE)
                self.band(lo - .12, y + 1.13, hi + .12, y + 1.19, .87, .93, FRAME)
                for rail in np.linspace(lo - .09, hi + .09, 5):
                    self.face(rail - .018, y + .25, rail + .018, y + 1.13, .92, FRAME, .25)


def bake(directory):
    track = json.loads((directory / 'track.json').read_text())
    route = np.asarray(track['pts'])[:, [0, 2]]
    line = np.roll(route, -1, axis=0) - route
    lengths = np.linalg.norm(line, axis=1)
    arc = np.r_[0, np.cumsum(lengths[:-1])]
    batches = defaultdict(list)
    count = 0
    for points, normal, tint in source_walls(directory / 'buildings.glb'):
        a, b, c, _ = points
        width = np.linalg.norm(b - a)
        height = c[1] - b[1]
        if width < 2.4 or height < 3.6:
            continue
        # Use the nearest point on the complete loop to reject nearby parallel streets.
        mid = (a + b) * .5
        offset = mid[[0, 2]] - route
        t = np.clip(np.sum(offset * line, axis=1) / np.maximum(lengths**2, .001), 0, 1)
        delta = t[:, None] * line - offset
        dist2 = np.sum(delta**2, axis=1)
        closest = int(dist2.argmin())
        distance = math.sqrt(dist2[closest])
        along = arc[closest] + lengths[closest] * t[closest]
        if not track['hw'] + 1.9 <= distance <= REACH or not 0 <= along <= LENGTH:
            continue
        if delta[closest] @ normal[[0, 2]] < distance * .36:
            continue
        batch = batches[int(along // CHUNK)]
        facade = Elevation(batch, a, b, normal)
        # Adjacent faces of the same extrusion share the source tint and elevation.
        style_rng = random.Random(int(a[1] * 100) + int(tint[0]) * 8191 + int(tint[1]) * 2539)
        style = 2 if tint[3] > 200 else style_rng.randrange(3)
        plaster = PLASTER[style_rng.randrange(len(PLASTER))] if style != 2 else (.54, .59, .60)
        detail_rng = random.Random(round(mid[0] * 73) + round(mid[2] * 137))
        columns = max(1, round(width / (3.25, 2.45, 3.8)[style]))
        ground = min(4.15, height)
        floors = max(1, round((height - ground) / (3.05, 3.55, 3.35)[style]))
        for column in range(columns):
            bay_width = width / columns
            x = column * bay_width
            facade.bay(x, 0, bay_width, ground, STONE, detail_rng, True, style, column)
            # Above the first six floors the existing skyline facade shows through.
            floor_h = (height - ground) / floors
            detailed = min(floors, 6) if floor_h >= 2.1 else 0
            for level in range(detailed):
                facade.bay(x, ground + level * floor_h, bay_width, floor_h, plaster,
                           detail_rng, False, style, column)
            top = ground + detailed * floor_h
            if detailed == 0 and top < height - .001:
                facade.face(x, top, x + bay_width, height, .15, plaster)
            elif top < height - .001:
                facade.band(x, top - .16, x + bay_width, top, .02, .24, STONE)
        count += 1

    model = GLB()
    material = model.material('showcase_facade')
    triangles = 0
    for chunk, batch in sorted(batches.items()):
        positions = np.concatenate([quad[0] for quad in batch])
        origin = positions.mean(axis=0)
        normals = np.repeat(np.array([quad[1] for quad in batch]), 4, axis=0)
        colors = np.repeat(np.array([quad[2] for quad in batch]), 4, axis=0)
        indices = np.arange(0, len(positions), 4)[:, None] + [0, 1, 2, 0, 2, 3]
        # The masonry shader applies planar, world-scale UVs on all orientations.
        mesh = model.mesh(f'ShowcaseFacade{chunk}', [{
            'pos': positions - origin, 'nrm': normals, 'col': colors,
            'uv': np.zeros((len(positions), 2)), 'idx': indices, 'mat': material,
        }])
        model.node(f'ShowcaseFacade{chunk}', mesh, origin)
        triangles += len(batch) * 2
    if count == 0:
        raise ValueError('No Tirana showcase frontages were selected')
    size = model.write(directory / 'showcase_facades.glb')
    print(f'  Tirana showcase: {count} frontages, {len(batches)} batches, {triangles} triangles, {size // 1024} KiB')


if __name__ == '__main__':
    bake(Path(OUT) / 'tirane')
