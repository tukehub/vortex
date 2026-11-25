"""Bake visual relief over the shipped Vlorë DEM without rebuilding the circuit.

    python3 tools/pipeline/vlore_terrain_detail.py

Each 120 m tile adds signed centimetres and three material/transition weights
to the original triangulated terrain, at 1.875 m intervals. The regional DEM
determines the slopes and drainage. The sub-grid detail is procedural.
"""
import argparse
from pathlib import Path
import zlib

import numpy as np
from scipy import ndimage
from scipy.spatial import cKDTree

from cities import CITIES
from coastal_vegetation import FootprintMask
from common import OUT, Proj, load_json, save_json

BASE_CELLS = 8
SUBDIVISIONS = 8
TILE_CELLS = BASE_CELLS * SUBDIVISIONS
SAMPLES = TILE_CELLS + 1
RECORD = np.dtype([('height', '<i2'), ('rock', 'u1'), ('gully', 'u1'), ('blend', 'u1')])
# World-space lower corner and number of tiles east/south. Origins align to
# Vlorë's existing 15 m grid. Separate hills share no texture or mesh atlas.
REGIONS = (
    (60, -2820, 2, 4),    # Kuzum Baba's western slope
    (180, -60, 2, 3),     # inland above lower Lungomare
    (60, 420, 3, 5),     # Dhimitër Konomi's south-facing slopes
    (-180, 660, 2, 3),   # above Uji i Ftohtë, behind the modeled portals
)


def smooth(low, high, value):
    t = np.clip((value - low) / (high - low), 0, 1)
    return t * t * (3 - 2 * t)


def triangular(grid, z, x):
    ix, iz = x.astype(int), z.astype(int)
    u, v = x - ix, z - iz
    a, b, c, d = grid[iz, ix], grid[iz, ix+1], grid[iz+1, ix], grid[iz+1, ix+1]
    return a + u*(b-a) + v*(c-a) + np.maximum(u+v-1, 0)*(d-b-c+a)


def field(rng, x, z, wavelength):
    """Band-limited, non-periodic detail in metres."""
    x, z = (x - x.min()) / wavelength + 2, (z - z.min()) / wavelength + 2
    samples = rng.uniform(-1, 1, (int(z.max()) + 4, int(x.max()) + 4))
    return ndimage.map_coordinates(samples, [z, x], order=3)


def runoff(height, rain):
    """Accumulate catchment area downhill with two weighted receivers per cell."""
    pad = np.pad(height, 1, constant_values=np.inf)
    h, w = height.shape
    ids = np.arange(height.size).reshape(height.shape)
    slopes = []
    receivers = []
    for dz, dx in ((-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)):
        neighbor = pad[1+dz:1+dz+h, 1+dx:1+dx+w]
        slopes.append(((height - neighbor) / np.hypot(dx, dz)).ravel())
        receivers.append((ids + dz*w + dx).ravel())
    slopes, receivers = np.asarray(slopes), np.asarray(receivers)
    steepest = np.argsort(slopes, axis=0)[-2:]
    scores = np.maximum(0, np.take_along_axis(slopes, steepest, axis=0)) ** 3
    # The larger drop gets most of the water. Split comparable gradients
    # between neighbouring cells to soften the square sampling directions.
    weights = scores[0] / np.maximum(scores.sum(axis=0), 1e-12)
    secondary, primary = np.take_along_axis(receivers, steepest, axis=0)
    active = scores[1] > 0
    flow = rain.ravel().copy()
    for i in np.argsort(height, axis=None)[::-1]:
        if active[i]:
            flow[primary[i]] += flow[i] * (1 - weights[i])
            if weights[i] > 0:
                flow[secondary[i]] += flow[i] * weights[i]
    return flow.reshape(height.shape)


def hardscape(directory, route, span):
    # Project the shipped meshes, including the side-street and roof outlines.
    # Add foundations the city deliberately models separately from buildings.glb.
    corners = [(x+u*span, z+v*span) for x, z, u, v in REGIONS] + [(x, z) for x, z, _, _ in REGIONS]
    mask = FootprintMask(np.vstack((route, corners)))
    mask.mesh(directory/'roads.glb', 0)
    mask.mesh(directory/'buildings.glb', 1)
    cfg = CITIES['vlore']
    proj = Proj(*cfg['origin'], cfg.get('latitude_compression', ()))
    rects = [(proj.to_xz(*ll), extent) for ll, extent in cfg['scenery_clearances']]
    props = load_json(directory/'props.json')
    extents = {item['id']: item.get('clear_half', (18, 18)) for item in cfg['landmarks']}
    rects += [((lm['x'], lm['z']), extents.get(lm['id'], (18, 18))) for lm in props['landmarks']]
    for (x, z), (a, b) in rects:
        mask.polygon(np.array(((x-a,z-b), (x+a,z-b), (x+a,z+b), (x-a,z+b))))
    return np.asarray(mask.image), mask.origin


def region_detail(x, z, width, height, base, shore, meta, route, hard, seed):
    rng = np.random.default_rng(seed)
    grid = meta['near']
    step = grid['cell'] / SUBDIVISIONS
    span = grid['cell'] * BASE_CELLS
    # Use surroundings to establish the drainage even at the patch borders.
    pad = 40
    rz, rx = np.meshgrid(np.arange(-pad, height*TILE_CELLS+pad+1), np.arange(-pad, width*TILE_CELLS+pad+1), indexing='ij')
    xx, zz = x + step*rx, z + step*rz
    coords = [(zz-grid['z0'])/grid['cell'], (xx-grid['x0'])/grid['cell']]
    original = triangular(base, *coords)
    broad = field(rng, xx, zz, 34)
    medium = field(rng, xx, zz, 11)
    fine = field(rng, xx, zz, 4)
    source = ndimage.map_coordinates(base, coords, order=3)
    shaped = source + broad * 2.4 + medium * 0.9
    gz, gx = np.gradient(shaped, step)
    slope = np.hypot(gx, gz)
    flow = runoff(shaped, np.clip(1.0 + broad*.6, .3, 1.7))
    valley = smooth(1.5, 3.9, ndimage.gaussian_filter(np.log1p(flow), 1.4))
    ravine = smooth(2.1, 4.9, ndimage.gaussian_filter(np.log1p(flow), .72))
    # Folded beds run across the slope and break into isolated outcrops.
    strata = (shaped + .105*xx - .062*zz + 3.0*broad + medium) / 5.8
    ledges = smooth(-.30, .62, np.sin(strata * 2*np.pi)) * smooth(-.32, .55, broad + .5*medium)
    bedrock = smooth(.20, .82, slope + .20*broad + .17*medium + .25*ledges)
    relief = (np.clip(source-original, -3, 3)*.65 + broad*2.0 + medium*.86 + fine*.33
              + ledges*bedrock*2.7 - valley*1.6 - ravine*(1.5 + 2.4*smooth(.18, .9, slope)))

    # No displacement on the race shoulders, side roads, foundations, modeled
    # tunnel cliff, or beach. Fade around their margins and the patch union.
    route_dist = route.query(np.column_stack((xx.ravel(), zz.ravel())))[0].reshape(xx.shape)
    road_guard = meta['half_width'] + 23
    hard_map, origin = hard
    blocked = ndimage.map_coordinates(hard_map, [zz-origin[1], xx-origin[0]], order=0) > 0
    clearance = ndimage.distance_transform_edt(~blocked) * step
    water = ndimage.map_coordinates(shore, coords, order=1, output=np.float32)
    margin = step * np.minimum.reduce([rx, rz, width*TILE_CELLS-rx, height*TILE_CELLS-rz])
    blend = smooth(0, 21, margin)
    mask = (blend * smooth(road_guard, road_guard+33, route_dist)
            * (1-smooth(230, 410, route_dist)) * smooth(3, 19, clearance)
            * (1-smooth(56, 101, water)) * smooth(9, 25, original)
            * smooth(.065, .28, slope + broad*.05))
    data = np.zeros(xx.shape, dtype=RECORD)
    data['height'] = np.rint(100 * np.clip(relief, -7, 6) * mask).astype('<i2')
    data['rock'] = np.rint(np.clip((bedrock*.73 + ledges*.24) * mask, 0, 1)*255)
    data['gully'] = np.rint(np.clip((valley*.44 + ravine*.56) * mask, 0, 1)*255)
    data['blend'] = np.rint(blend*255)
    return data[pad:-pad, pad:-pad]


def bake(directory):
    meta = load_json(directory/'terrain.json')
    g = meta['near']
    track = load_json(directory/'track.json')
    meta['half_width'] = track['hw']
    line = np.asarray(track['pts'])[:, [0, 2]]
    # Densify the closed spline's shipped control polyline to sub-grid spacing.
    following = np.roll(line, -1, axis=0)
    route = (line[:, None] + (following-line)[:, None]*np.linspace(0, 1, 8, endpoint=False)[None, :, None]).reshape(-1, 2)
    base = np.fromfile(directory/'terrain_near.bin', '<f4').reshape(g['n'], g['n'])
    shore = np.fromfile(directory/'water_near.bin', 'u1').reshape(base.shape)
    water = meta['water']['surface']
    base = np.where(shore >= 128, np.minimum(base, water-3), np.maximum(base, water+.25))
    span = g['cell'] * BASE_CELLS
    footprints = hardscape(directory, route, span)
    tree = cKDTree(route)
    tiles, records = [], []
    for i, (x, z, width, height) in enumerate(REGIONS):
        detail = region_detail(x, z, width, height, base, shore, meta, tree, footprints, 4410+i)
        gx, gz = (x-g['x0'])/span, (z-g['z0'])/span
        if gx % 1 or gz % 1:
            raise ValueError('Detail regions must align with the terrain tile grid.')
        for j in range(height):
            for k in range(width):
                row, col = j*TILE_CELLS, k*TILE_CELLS
                tile = detail[row:row+SAMPLES, col:col+SAMPLES]
                tiles.append([int(gx)+k, int(gz)+j])
                records.append(tile.tobytes())
    (directory/'terrain_detail.bin').write_bytes(zlib.compress(b''.join(records), level=9))
    save_json(directory/'terrain_detail.json', {'version': 1, 'tiles': tiles})
    print(f'  Vlorë detail: {len(tiles)} tiles, {g["cell"]/SUBDIVISIONS:g} m spacing')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--city-dir', type=Path, default=Path(OUT)/'vlore')
    bake(parser.parse_args().city_dir)
