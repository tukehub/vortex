"""Fit reusable Vlorë bays to the final OSM extrusion, including road clearances."""
import json
import math
from pathlib import Path
import struct

import numpy as np
from PIL import Image, ImageDraw

from common import OUT
from glb import GLB

# Shuttered townhouses, ribbon balconies, postwar walk-ups, glazed hotels.
BAY_WIDTH = (3.0, 4.8, 3.7, 5.1)
OPENING = ((.30, .70), (.12, .88), (.21, .79), (.07, .93))
PLASTER = ((226, 193, 150), (238, 229, 209), (213, 164, 139), (207, 219, 216))
SASH = ((79, 94, 76), (105, 115, 116), (126, 96, 74), (58, 76, 83))
TILE = 128


def make_atlas(path):
    image = Image.new('RGB', (4 * TILE, 3 * TILE))
    for family, (lo, hi) in enumerate(OPENING):
        for row in range(3):  # upper window, shop, entrance
            tile = Image.new('RGB', (TILE, TILE), PLASTER[family])
            pen = ImageDraw.Draw(tile)
            a, b = (round(lo*TILE), round(hi*TILE)) if row == 0 else ((10, 118) if row == 1 else (40, 88))
            top, bottom = (18, 95) if row == 0 else (24, 125)
            pen.rectangle((0, 123, 127, 127), fill=tuple(int(x*.82) for x in PLASTER[family]))
            pen.rectangle((a-3, top-3, b+3, bottom+4), fill=(174, 163, 144))
            pen.rectangle((a, top, b, bottom), fill=SASH[family])
            for y in range(top+3, bottom-2):
                f = (y-top)/(bottom-top)
                pen.line((a+3, y, b-3, y), fill=(int(98-39*f), int(134-51*f), int(144-49*f)))
            for j in range(1, (panes := (2, 3, 2, 4)[family] if row != 2 else 1)):
                x = round(a+(b-a)*j/panes)
                pen.rectangle((x-1, top, x+1, bottom), fill=SASH[family])
            pen.line((a, top+15, b, top+15), fill=SASH[family], width=3)
            if row == 2:
                pen.rectangle((a+4, 87, b-4, bottom-3), fill=SASH[family])
                pen.rectangle((b-8, 69, b-6, 80), fill=(211, 195, 150))
            elif row == 1:
                pen.rectangle((6, 8, 122, 21), fill=SASH[family])
                pen.rectangle((8, 17, 120, 19), fill=(206, 185, 138))
            elif family == 0:
                for x in (a-16, b+4):
                    pen.rectangle((x, top, x+12, bottom), fill=SASH[0])
                    for y in range(top+4, bottom, 5):
                        pen.line((x+1, y, x+11, y), fill=(116, 129, 104))
            image.paste(tile, (family*TILE, row*TILE))
    image.save(path)


class Module:
    """Canonical bay in XY, outward +Z. Depth stays in metres when instanced."""
    def __init__(self):
        self.pos, self.uv, self.normals, self.colors, self.indices = [], [], [], [], []

    def quad(self, corners, tint=(1, 1, 1), textured=True):
        p = np.array(corners)
        n = np.cross(p[1]-p[0], p[2]-p[0])
        base = len(self.pos)
        self.pos.extend(p)
        self.normals.extend([n / np.linalg.norm(n)]*4)
        self.uv.extend([(x, y) for x, y, _ in p])
        self.colors.extend([(*tint, float(textured))]*4)
        self.indices.extend(base+i for i in (0, 1, 2, 0, 2, 3))

    def face(self, x, y, u, v, z):
        self.quad([(x,y,z), (u,y,z), (u,v,z), (x,v,z)])

    def box(self, x, y, z, u, v, w, tint):
        points = [(x,y,z),(u,y,z),(u,v,z),(x,v,z),(x,y,w),(u,y,w),(u,v,w),(x,v,w)]
        for face in ((4,5,6,7),(1,0,3,2),(0,4,7,3),(5,1,2,6),(3,7,6,2),(0,1,5,4)):
            self.quad([points[i] for i in face], tint, False)

    def write(self, glb, name, material):
        primitive = dict(pos=np.array(self.pos), nrm=np.array(self.normals), uv=np.array(self.uv),
                         col=np.array(self.colors), idx=np.array(self.indices), mat=material)
        glb.node(name, glb.mesh(name, [primitive]))


def make_modules(path):
    model = GLB()
    material = model.material('bay')
    stone, metal = (.64, .59, .49), (.094, .13, .14)
    for family, (a, b) in enumerate(OPENING):
        for row in range(3):
            m = Module()
            x, u = (a,b) if row == 0 else ((10/128,118/128) if row == 1 else (40/128,88/128))
            y, v = (33/128,110/128) if row == 0 else (3/128,104/128)
            front, back = .28, .045
            for rect in ((0,0,x,1),(u,0,1,1),(x,0,u,y),(x,v,u,1)):
                m.face(*rect, front)
            m.face(x,y,u,v,back)
            for start, end in (((x,y),(u,y)),((u,y),(u,v)),((u,v),(x,v)),((x,v),(x,y))):
                m.quad([(*start,front),(*end,front),(*end,back),(*start,back)], stone, False)
            if row == 0 and family in (1,2,3):
                depth = (0, 1.55, 1.05, 1.32)[family]
                left, right = (.02,.98) if family == 1 else (.12,.88)
                m.box(left,.015,.25,right,.077,depth,stone)
                for z in (.24, depth-.042):
                    m.box(left,.33,z,right,.346,z+.04,metal)
                for side in (left,right-.012):
                    m.box(side,.33,.25,side+.012,.346,depth,metal)
                for post in np.linspace(left,right-.012,6):
                    m.box(post,.077,depth-.046,post+.012,.33,depth,metal)
            elif row == 1:
                m.box(.045,.823,.23,.955,.88,.89,tuple(c/400 for c in SASH[family]))
            m.write(model, f'Bay{family}_{row}', material)
    for i in range(2):
        m = Module()
        if i == 0:  # tank and plinth
            m.box(-.65,0,-.6,.65,.22,.6,stone)
            m.box(-.53,.22,-.48,.53,1.32,.48,(.35,.43,.45))
        else:  # louvred ventilation housing
            m.box(-.83,0,-.5,.83,.73,.5,metal)
            for y in (.14,.31,.48,.65):
                m.box(-.88,y,-.54,.88,y+.055,.54,stone)
        m.write(model, f'Roof{i}', material)
    model.write(path)


def read_model(path):
    data = bytearray(path.read_bytes())
    size = struct.unpack_from('<I', data, 12)[0]
    model = json.loads(data[20:20+size])

    def attribute(primitive, name):
        a = model['accessors'][primitive['attributes'][name]]
        v = model['bufferViews'][a['bufferView']]
        dtype = {5126:'<f4', 5121:'u1'}[a['componentType']]
        width = int(a['type'][-1])
        return np.frombuffer(data, dtype, a['count']*width,
                             28+size+v['byteOffset']).reshape(-1,width)

    return data, model, attribute


def bake(directory):
    path = directory / 'buildings.glb'
    data, model, attr = read_model(path)
    track = json.loads((directory/'track.json').read_text())
    route = np.array(track['pts'])[:,[0,2]]
    placements = []
    for node in model['nodes']:
        wall, roof = model['meshes'][node['mesh']]['primitives']
        origin = node['translation']
        points = (attr(wall,'POSITION')+origin).reshape(-1,4,3)
        uv = attr(wall,'TEXCOORD_0').reshape(-1,4,2)
        colors = attr(wall,'COLOR_0').reshape(-1,4,4)
        last = None
        for i, (a,b,c,_) in enumerate(points):
            width, height = np.linalg.norm(b-a), c[1]-b[1]
            if last is None or not np.array_equal(a,last):
                seed = round(a[0]*10)*997 + round(a[2]*10)*31
                family = (0 if seed%3 else 2) if height < 12 else (1,2,3,1)[seed%4]
            last = b
            cols = max(1, round(width/BAY_WIDTH[family]))
            floors = max(1, round(height/3.25))
            uv[i] = ((cols,0),(0,0),(0,floors),(cols,floors))
            colors[i,:,3] = family*85
            mid = (a+b)*.5
            delta = route-mid[[0,2]]
            closest = delta[np.argmin(np.sum(delta*delta,axis=1))]
            distance = np.linalg.norm(closest)
            axis = (a-b)/width
            outward = np.array([-axis[2],axis[0]])
            if (width < 2.1 or height < 2.5 or distance > 120 or
                    np.dot(closest,outward) < .24*distance or distance < track['hw']+1.8):
                continue
            placements.append([family,*b,axis[0],axis[2],width/cols,height/floors,cols,floors,
                               *map(int,colors[i,0,:3])])
        # A large flat roof triangle contains its centroid and an inset service unit.
        roof_pos = attr(roof,'POSITION')+origin
        roof_normals = attr(roof,'NORMAL')
        idx = model['accessors'][roof['indices']]
        view = model['bufferViews'][idx['bufferView']]
        start = 28+struct.unpack_from('<I',data,12)[0]+view['byteOffset']
        triangles = np.frombuffer(data,'<u4',idx['count'],start).reshape(-1,3)
        used = set()
        for tri in triangles:
            p = roof_pos[tri]
            if roof_normals[tri[0],1] < .999 or np.ptp(p[:,1]) > .01:
                continue
            center = p.mean(axis=0)
            sides = np.linalg.norm(p-np.roll(p,1,axis=0),axis=1)
            clearance = np.linalg.norm(np.cross(p[1]-p[0],p[2]-p[0])) / max(1,3*sides.max())
            key = (int(center[0]//22), int(center[2]//22))
            if clearance < 1.4 or key in used or np.min(np.linalg.norm(route-center[[0,2]],axis=1)) > 115:
                continue
            used.add(key)
            placements.append([4+sum(key)%2,*center])
    path.write_bytes(data)
    (directory/'frontages.json').write_text(json.dumps(
        [[round(v,5) if isinstance(v,float) else v for v in row] for row in placements],
        separators=(',',':')))
    make_modules(directory/'facade_modules.glb')
    make_atlas(directory/'facade_atlas.png')


if __name__ == '__main__':
    bake(Path(OUT)/'vlore')
