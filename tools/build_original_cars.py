"""Build the original, unbranded VORTEX estate and hatch from metric profiles.

First-party geometry for commercial use in VORTEX. No external mesh, image or scan.
"""
from pathlib import Path

import numpy as np

from gen_cars import Builder, CARS, OUT, build_body, build_wheel, ellipsoid

HATCH = dict(L=4.08, W=1.79, wheel_r=.32, tyre_w=.21, wheels=(.185,.805),
             spokes=6, rim=.73, tumble=.44,
             roof=[(0,.64),(.19,.8),(.29,.87),(.42,1.45),(.54,1.52),(.80,1.5),(.89,1.43),(1,.86)],
             glass=[(.29,.53),(.55,.76),(.78,.86),(.89,.985)],
             screens=[(.29,.42),(.89,.985)])
ESTATE = dict(L=4.78, W=1.90, wheel_r=.35, tyre_w=.235, wheels=(.20,.80),
              spokes=9, rim=.77, tumble=.34,
              roof=[(0,.62),(.24,.80),(.34,.86),(.46,1.47),(.58,1.54),(.89,1.53),(.95,1.44),(1,.91)],
              glass=[(.34,.58),(.60,.76),(.78,.91),(.95,.993)],
              screens=[(.34,.46),(.95,.993)])


class MobileBuilder(Builder):
    def mat(self, name):
        return super().mat({'chrome': 'rim', 'brake': 'tyre', 'plate': 'trim'}.get(name, name))

    def flush(self, name):
        # The loft shares positions across glazing and paint. Drop vertices
        # unused by each surface before writing the split glTF accessors.
        for prim in self.prims:
            vertices, index = np.unique(prim['idx'].ravel(), return_inverse=True)
            for key in ('pos', 'nrm', 'uv'):
                prim[key] = prim[key][vertices]
            prim['idx'] = index.reshape(-1, 3)
        return super().flush(name)


def build(name, dimensions):
    spec = dict(CARS['vortex_gt'], **dimensions, stations=76)
    b = MobileBuilder()
    geometry = build_body(b, spec)
    glazing = b.prims.pop()
    length, width = spec['L'], spec['W']
    nose, tail = -length*.5, length*.5
    estate = name == 'estate'
    for side in (-1, 1):
        b.box((side*(width*.5-.02), .91, nose*.20), (.18,.11,.24), 'paint', rot_y=side*.14)
        for door in (.48, .72):
            b.box((side*(width*.5-.005), .79, (door-.5)*length), (.024,.035,.15), 'trim')
        if estate:
            b.box((side*.54, 1.54, .65), (.036,.042,1.73), 'trim')
    # Bumper openings follow the rounded nose. Recessed upper grilles,
    # body-colour dividers and wheel-side sills break up the flat end cap.
    grille_width = width * (.43 if estate else .37)
    b.box((0,.49,nose+.008), (grille_width,.12,.072), 'trim')
    for y in (.458,.49,.522):
        b.box((0,y,nose-.033), (grille_width*.94,.009,.011), 'paint')
    b.box((0,.323,nose+.015), (width*.74,.096,.11), 'trim')
    b.box((0,.43,nose-.038), (.36,.085,.016), 'trim')
    for side in (-1,1):
        x = side*.57
        z = nose+.05
        if estate:
            b.box((x,.604,z), (.38,.093,.085), 'trim', rot_y=-side*.18)
        else:
            ellipsoid(b,(x,.594,z),(.164,.10,.084),'trim',rings=7,segments=16)
        b.box((side*(width*.5-.045), .34, .015), (.063,.076,length*.49), 'trim')
        b.box((side*.57,.335,tail+.004), (.19,.049,.095), 'trim')
        if estate:
            for rail_z in (-.12,1.4):
                b.box((side*.54,1.50,rail_z),(.052,.068,.086),'trim')
    b.box((0,.43,tail+.002), (.44,.125,.076), 'trim')
    b.box((0,.3,tail-.025), (width*.8,.105,.10), 'trim')
    nodes = [b.g.node('Body', b.flush('Body'))]
    b.prims.append(glazing)
    nodes.append(b.g.node('Glass', b.flush('Glass')))
    b.box((0,.78,-.53), (width*.78,.13,.32), 'interior')
    for side in (-1,1):
        for z in (-.07,.83):
            b.box((side*.39,.64,z), (.48,.14,.47), 'interior')
            b.box((side*.39,.85,z+.18), (.47,.39,.12), 'interior', rot_x=-.12)
            ellipsoid(b,(side*.39,1.10,z+.20),(.14,.11,.075),'interior',rings=5,segments=10)
    nodes.append(b.g.node('Interior', b.flush('Interior')))
    for role, mat, z in [('Headlights','light_front',nose), ('BrakeLights','light_rear',tail)]:
        for side in (-1,1):
            if estate:
                b.box((side*.57,.61 if z < 0 else .745,z+(.007 if z < 0 else .025)), (.34,.038,.058), mat, rot_y=-side*.18)
            else:
                ellipsoid(b,(side*.57,.607 if z < 0 else .735,z+.018),(.132,.065,.071),mat,rings=6,segments=14)
        nodes.append(b.g.node(role,b.flush(role)))
    wheel = build_wheel(b,spec)
    for axle,z in zip(('F','R'),geometry['wheel_z']):
        for side,letter in [(-1,'L'),(1,'R')]:
            offset = side * (width*.5-spec['tyre_w']*.5-.02)
            nodes.append(b.g.node('Wheel_'+axle+letter,wheel,(offset,spec['wheel_r'],z),
                                  rotation=(0,1,0,0) if side<0 else None))
    for side,letter in [(-1,'L'),(1,'R')]:
        nodes.append(b.g.node('Nitro_'+letter, translation=(side*width*.3,.29,tail)))
    root = b.g.node('CarRoot', children=nodes)
    b.g.write(str(Path(OUT)/(name+'.glb')), [root])


if __name__ == '__main__':
    build('hatch', HATCH)
    build('estate', ESTATE)
