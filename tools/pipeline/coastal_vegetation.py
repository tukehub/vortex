"""Bake ground-cover seeds against the same Vlorë meshes and shoreline used in-game."""
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import map_coordinates
from scipy.spatial import cKDTree

from cities import CITIES
from common import OUT, Proj, save_json
from vlore_facades import read_model

# Metres. The road skirt extends 7.1 m beyond half-width. Raster dilation
# includes sidewalks, clump radius, wind travel and spline interpolation.
PADDING = 3
GRASS, BRUSH, LAWN, PINE = range(4)


class FootprintMask:
    def __init__(self, route):
        self.origin = np.floor(route.min(axis=0) - 110)
        size = np.ceil(route.max(axis=0) + 110 - self.origin).astype(int)
        self.image = Image.new('L', tuple(size))
        self.pen = ImageDraw.Draw(self.image)

    def polygon(self, points):
        self.pen.polygon([tuple(p) for p in points-self.origin], fill=255)

    def line(self, points, width):
        self.pen.line([tuple(p) for p in points-self.origin], fill=255,
                      width=width, joint='curve')

    def mesh(self, path, surface):
        _, model, attribute, indices = read_model(path)
        for node in model['nodes']:
            prim = model['meshes'][node['mesh']]['primitives'][surface]
            pos = (attribute(prim, 'POSITION') + node['translation'])[:, [0, 2]]
            for tri in pos[indices(prim).reshape(-1, 3)]:
                self.polygon(tri)

    def buffered(self):
        return np.asarray(self.image.filter(ImageFilter.MaxFilter(2*PADDING+1)))

    def allows(self, points, raster):
        x, z = np.floor(points-self.origin).astype(int).T
        return raster[z, x] == 0


def bake(directory):
    read = lambda name: json.loads((directory/name).read_text())
    track, props, terrain = (read(name+'.json') for name in ('track', 'props', 'terrain'))
    route = np.array(track['pts'])[:, [0, 2]]
    front = props['seafront']
    line = np.array(front['line'])
    shore_route = line[:, [0, 2]]
    sea_normal = line[:, 3:5]
    mask = FootprintMask(route)
    mask.mesh(directory/'roads.glb', 0)
    mask.mesh(directory/'buildings.glb', 1)  # projected roof triangles include concave footprints
    mask.line(np.vstack((route, route[0])), int(2*(track['hw']+8)))
    cfg = CITIES['vlore']
    proj = Proj(*cfg['origin'], cfg.get('latitude_compression', ()))
    clear = [(proj.to_xz(*ll), extent) for ll, extent in cfg['scenery_clearances']]
    for landmark, anchor in zip(cfg['landmarks'], props['landmarks'], strict=True):
        clear.append(((anchor['x'], anchor['z']), landmark.get('clear_half', (20, 20))))
    clear += [((x, z), (11, 11)) for x, _, z, *_ in props['cafes']]
    for (x, z), (w, h) in clear:
        mask.polygon(np.array([[x-w,z-h], [x+w,z-h], [x+w,z+h], [x-w,z+h]]))

    hw = front['hw']
    outer = shore_route + sea_normal * line[:, 5:6]
    pave = shore_route + sea_normal * np.minimum(line[:, 5:6], hw+12)
    land = shore_route - sea_normal * np.minimum(line[:, 6:7], hw+9)
    for i in range(1, len(line)):
        mask.polygon(np.array([land[i-1], land[i], pave[i], pave[i-1]]))
    hard = mask.buffered()
    for i in range(1, len(line)):
        mask.polygon(np.array([pave[i-1], pave[i], outer[i], outer[i-1]]))
    natural = mask.buffered()

    g = terrain['near']
    heights = np.fromfile(directory/'terrain_near.bin', '<f4').reshape(g['n'], g['n'])
    shore = np.fromfile(directory/'water_near.bin', 'u1').reshape(heights.shape)
    def grid_coords(xz):
        return ((xz - [g['x0'],g['z0']]) / g['cell']).T[::-1]

    def surface(xz):
        # Interpolate along the same diagonal as Terrain._grid_mesh.
        iz, ix = grid_coords(xz)
        z, x = iz.astype(int), ix.astype(int)
        u, v = ix-x, iz-z
        h00, h10, h01, h11 = heights[z,x], heights[z,x+1], heights[z+1,x], heights[z+1,x+1]
        return (h00 + u*(h10-h00) + v*(h01-h00)
                + np.maximum(u+v-1, 0)*(h11-h10-h01+h00))

    splat = np.asarray(Image.open(directory/'splat.png'))
    macro = np.asarray(Image.open(directory/'ground_macro.png'))
    rng = np.random.default_rng(18471)
    xx, zz = np.meshgrid(np.arange(2,mask.image.width-2,2.4),
                         np.arange(2,mask.image.height-2,2.4))
    pts = np.column_stack((xx.ravel(),zz.ravel())) + mask.origin
    pts += rng.uniform(-.95,.95,pts.shape)
    pts = pts[mask.allows(pts, natural)]
    pts = pts[cKDTree(route).query(pts)[0] <= 95]
    sp = ((pts / terrain['splat']['span'] + .5) * len(splat)).astype(int)
    road, green, water, urban = splat[sp[:,1],sp[:,0]].T
    codes = map_coordinates(shore,grid_coords(pts),order=1)
    elevation = surface(pts)
    rise = np.abs(surface(pts + [3,0]) - elevation) + np.abs(surface(pts + [0,3]) - elevation)
    hillside = (elevation > 35) | ((elevation > 17) & (rise > .6))
    permitted = (codes < 42) & (road < 22) & (water < 20) & ((urban < 140) | (green > 105) | hillside)
    pts = pts[permitted]
    y = surface(pts)
    uv = np.floor(pts / 1580 * len(macro)).astype(int) % len(macro)
    scrub = macro[uv[:,1], uv[:,0], 0] / 255
    keep = rng.random(len(pts)) < (.22 + scrub*.67)
    pts, y, scrub = pts[keep], y[keep], scrub[keep]
    bushes = (y > 8) & (rng.random(len(y)) < np.clip((scrub-.27)*1.7,.10,.74))
    rows = [np.column_stack((pts[:,0], y, pts[:,1], bushes.astype(float)))]

    # Match SeafrontPromenade._strip's triangles, lift and UVs. Sample the
    # lawn interiors only, with clearance from both families of diagonal paths.
    along = np.r_[0, np.cumsum(np.linalg.norm(np.diff(shore_route,axis=0),axis=1))]
    anchors = np.array([[a['x'],a['z']] for a in props['landmarks']])
    lawn = []
    for i in range(1,len(line)):
        ids = [i-1,i]
        edges = line[ids,5]
        start = hw + 12
        if edges.min() <= start+2:
            continue
        cuts = int(np.ceil((edges.max()-start)/4))
        for k in range(cuts):
            low = start + (edges-start)*k/cuts
            high = start + (edges-start)*(k+1)/cuts
            across = np.array([low[0],low[1],high[1],high[0]])
            j = [i-1,i,i,i-1]
            pos = shore_route[j] + sea_normal[j]*across[:,None]
            if np.linalg.norm(anchors-(pos[0]+pos[2])*.5,axis=1).min() < 26:
                continue
            height = map_coordinates(heights,grid_coords(pos),order=1) + .16
            uv = np.column_stack((along[j],across))
            for tri in ([0,1,2],[0,2,3]):
                p = pos[tri]
                a, b = p[1]-p[0], p[2]-p[0]
                area = abs(a[0]*b[1] - a[1]*b[0])*.5
                weights = rng.random((int(area/3.0+rng.random()),2))
                weights = np.where(weights.sum(axis=1)[:,None]>1,1-weights,weights)
                bary = np.column_stack((1-weights.sum(axis=1),weights))
                xz = bary@p
                u,v = (bary@uv[tri]).T
                paths = np.mod(np.array([u+v,u-v])+17,34)-17
                ok = ((np.abs(paths).min(axis=0)>2.35) & (v>start+1.3)
                      & (v < bary@np.array([edges[0],edges[1],edges[1],edges[0]])[tri]-1.3)
                      & mask.allows(xz,hard) & (map_coordinates(shore,grid_coords(xz),order=1)<100))
                lawn.extend(np.column_stack((xz[:,0],bary@height[tri],xz[:,1],np.full(len(xz),LAWN)))[ok])
    if lawn:
        rows.append(np.array(lawn))

    all_sites = np.concatenate(rows)
    # Occasional wind-shaped pines behind the waterfront. Keep the mapped
    # palm rhythm and give crowns room around terraces, paths and façades.
    coastal = cKDTree(shore_route).query(pts)[0] < 80
    tree_sites = pts[coastal & (y < 16)]
    if lawn:
        tree_sites = np.vstack((tree_sites, np.asarray(lawn)[::8, [0,2]]))
    pines = []
    palms = np.array(props['palms'])[:,[0,2]]
    for point in tree_sites[rng.permutation(len(tree_sites))]:
        if np.linalg.norm(palms-point,axis=1).min() < 9:
            continue
        if pines and np.linalg.norm(np.array(pines)-point,axis=1).min() < 78:
            continue
        pines.append(point)
    if pines:
        xz = np.array(pines)
        all_sites = np.vstack((all_sites,np.column_stack((xz[:,0],surface(xz),xz[:,1],np.full(len(xz),PINE)))))

    # Keep the mapped street trees that have a planting surface. Farther
    # inland trees retain their OSM positions. Palms occupy their own tree pits.
    trees = props['trees']
    if trees:
        tree_xz = np.asarray(trees)[:,[0,2]]
        pixel = tree_xz - mask.origin
        inside = np.all((pixel >= 0) & (pixel < mask.image.size), axis=1)
        keep = map_coordinates(shore, grid_coords(tree_xz), order=1) < 85
        keep[inside] &= mask.allows(tree_xz[inside], hard)
        if pines:
            keep &= cKDTree(pines).query(tree_xz)[0] > 7
        props['tree_exclusions'] = np.flatnonzero(~keep).tolist()
        save_json(directory/'props.json', props)

    # A seeded shuffle gives each spatial batch a representative density prefix.
    rng.shuffle(all_sites)
    all_sites.astype('<f4').tofile(directory/'ground_cover.bin')
    print('Vlorë grass, brush, lawn, pine seeds:', np.bincount(all_sites[:,3].astype(int)))


if __name__ == '__main__':
    bake(Path(OUT)/'vlore')
