"""A river through a city, baked from its OpenStreetMap centreline and the
Copernicus DEM (the Osum through Berat).

OSM maps the Osum only as a centreline (waterway=river), so the river's
surface, width and banks are derived here:

  centre    the named river way, clipped to the near terrain, resampled
            every SAMPLE m and smoothed, ordered upstream to downstream;
  surface   the low ground across the channel, never rising downstream
            (a running minimum) and smoothed: the water level, metres;
  width     `width` from the city config, narrowed on a side where the race
            road runs close (that side becomes a stone embankment wall up to
            the road), full width where the race crosses on a bridge;
  banks     per side 0 = gravel bank, 1 = embankment wall (with its top);
  bridges   where the race road crosses: the deck's two ends (x, z), the
            river sample and the deck level. The race road is lifted to that
            level over the river before the track elevation is smoothed.

carve() lowers the near terrain under the channel (below the water) after
the road conform, so the terrain never shows through the water; it never
touches the race road's corridor except under its bridges.

Writes <city>/river.json for the game (godot/scripts/world/river.gd).
Data (c) OpenStreetMap contributors (ODbL); elevation (c) Copernicus DEM.
"""
import math

import numpy as np
from scipy.spatial import cKDTree

SAMPLE = 5.0            # metres between river samples
DECK_CLEARANCE = 5.2    # race-road deck above the water surface at a bridge
WALL_GAP = 7.0          # metres between the road edge and an embankment wall
ROAD_ABOVE = 2.6        # a riverside road stays at least this far above the water
RIVERSIDE = 5.0         # ... and at most about this far (surface-model artefacts)
MIN_HALF = 9.0          # the narrowest half width a side is narrowed to


def _bilinear(h, x0, z0, cell, x, z):
    n = h.shape[0]
    fx = np.clip((np.asarray(x, float) - x0) / cell, 0, n - 1.001)
    fz = np.clip((np.asarray(z, float) - z0) / cell, 0, n - 1.001)
    ix, iz = np.floor(fx).astype(int), np.floor(fz).astype(int)
    u, v = fx - ix, fz - iz
    return (h[iz, ix] * (1 - u) * (1 - v) + h[iz, ix + 1] * u * (1 - v)
            + h[iz + 1, ix] * (1 - u) * v + h[iz + 1, ix + 1] * u * v)


def _resample(pts, step):
    seg = np.hypot(*np.diff(pts, axis=0).T)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    t = np.arange(0.0, s[-1], step)
    return np.stack([np.interp(t, s, pts[:, 0]), np.interp(t, s, pts[:, 1])], axis=1)


def _smooth(a, window):
    """Moving average with the ends held (window samples, odd)."""
    if len(a) < window:
        return a
    k = np.ones(window) / window
    pad = window // 2
    if a.ndim == 1:
        return np.convolve(np.pad(a, pad, mode='edge'), k, mode='valid')
    return np.stack([_smooth(a[:, j], window) for j in range(a.shape[1])], axis=1)


class River:
    def __init__(self, cfg, osm, near, nm):
        self.cfg = cfg
        self.half = float(cfg.get('width', 40.0)) * 0.5
        self.x0, self.z0, self.cell = float(nm['x0']), float(nm['z0']), float(nm['cell'])
        n = int(nm['n'])
        limit = (n - 1) * self.cell * 0.5 - 250.0
        best = []
        for w in osm.ways.values():
            tags = w.get('tags') or {}
            if tags.get('waterway') == 'river' and tags.get('name') == cfg['way_name']:
                coords = osm.coords(w)
                if len(coords) > len(best):
                    best = coords
        if len(best) < 2:
            raise RuntimeError(f"no river way named {cfg['way_name']}")
        pts = np.asarray(best, float)
        inside = (np.abs(pts[:, 0]) < limit) & (np.abs(pts[:, 1]) < limit)
        # The longest run of consecutive points inside the near terrain.
        runs, start = [], None
        for i, ok in enumerate(inside):
            if ok and start is None:
                start = i
            if (not ok or i == len(inside) - 1) and start is not None:
                runs.append((start, i if not ok else i + 1))
                start = None
        a, b = max(runs, key=lambda r: r[1] - r[0])
        pts = _resample(pts[a:b], SAMPLE)
        pts = _smooth(_smooth(pts, 9), 9)
        raw = _bilinear(near, self.x0, self.z0, self.cell, pts[:, 0], pts[:, 1])
        if raw[0] < raw[-1]:
            pts = pts[::-1]
        self.pts = pts
        tan = np.gradient(pts, axis=0)
        tan /= np.linalg.norm(tan, axis=1)[:, None]
        self.tan = tan
        self.nrm = np.stack([-tan[:, 1], tan[:, 0]], axis=1)   # left of the flow
        # Water level: the lowest ground across the channel, never rising
        # downstream, smoothed over ~200 m.
        lows = []
        for off in np.linspace(-self.half, self.half, 7):
            for along in (-10.0, 0.0, 10.0):
                q = pts + self.nrm * off + self.tan * along
                lows.append(_bilinear(near, self.x0, self.z0, self.cell, q[:, 0], q[:, 1]))
        low = np.min(np.stack(lows), axis=0)
        prof = np.minimum.accumulate(low)
        prof = np.minimum.accumulate(_smooth(prof, 41))
        self.surface = prof - 0.25
        self.tree = cKDTree(pts)
        m = len(pts)
        self.wl = np.full(m, self.half)
        self.wr = np.full(m, self.half)
        self.bank_l = np.zeros(m, int)
        self.bank_r = np.zeros(m, int)
        self.top_l = self.surface + 1.2
        self.top_r = self.surface + 1.2
        self.bridges = []
        self.footbridges = []

    # ------------------------------------------------------------------ the race road

    def crossings(self, dense):
        """(track index, river index) where the race centreline crosses the river."""
        out = []
        tt = cKDTree(dense)
        d, k = tt.query(self.pts)
        cand = np.nonzero(d < 4.0)[0]
        for i in cand:
            if out and abs(out[-1][1] - i) < 30:
                if d[i] < d[out[-1][1]]:
                    out[-1] = (int(k[i]), int(i))
                continue
            out.append((int(k[i]), int(i)))
        return out

    def hold_riverside(self, dense, y):
        """Riverside roads run a few metres above the water: the surface model
        reads the houses and trees beside them as ground, so cap a road near
        the river at RIVERSIDE above the water, rising gently farther away."""
        d, i = self.tree.query(dense)
        near = d < self.half + 90.0
        cap = self.surface[i] + RIVERSIDE + np.maximum(0.0, d - self.half - 30.0) * 0.12
        return np.where(near, np.minimum(y, cap), y)

    def lift_crossings(self, dense, y, spacing):
        """Hold the race road at deck level over the river at each crossing."""
        y = y.copy()
        n = len(dense)
        self._cross = self.crossings(dense)
        for k, i in self._cross:
            deck = float(self.surface[i]) + DECK_CLEARANCE
            span = self.half + 10.0       # flat over the water and the banks
            ramp = 70.0
            for j in range(-int((span + ramp) / spacing), int((span + ramp) / spacing) + 1):
                kk = (k + j) % n
                dist = abs(j) * spacing
                t = 0.0 if dist <= span else min(1.0, (dist - span) / ramp)
                t = t * t * (3 - 2 * t)
                y[kk] = max(y[kk], deck * (1 - t) + y[kk] * t)
        return y

    def fit_to_track(self, ref, hw):
        """Narrow the river where the road runs beside it (that side walled),
        keep it whole at crossings, and record the bridges."""
        m = len(self.pts)
        cross_i = [i for _, i in self._cross]
        # The water stays well below a riverside road: lower the level where a
        # road runs along it (and so everything downstream of it).
        for i in range(m):
            if any(abs(i - ci) * SAMPLE < self.half + 45.0 for ci in cross_i):
                continue
            d, k = ref.nearest(self.pts[i][0], self.pts[i][1])
            if d < self.half + hw + 60.0:
                self.surface[i] = min(self.surface[i], float(ref.y[k]) - ROAD_ABOVE)
        self.surface = np.minimum.accumulate(_smooth(np.minimum.accumulate(self.surface), 9))
        for i in range(m):
            if any(abs(i - ci) * SAMPLE < self.half + 45.0 for ci in cross_i):
                continue
            p = self.pts[i]
            d, k = ref.nearest(p[0], p[1])
            if d > self.half + hw + WALL_GAP + 25.0:
                continue
            side = np.dot(ref.xz[k] - p, self.nrm[i])
            room = max(MIN_HALF, d - hw - WALL_GAP)
            road_y = float(ref.y[k])
            if side > 0:
                self.wl[i] = min(self.wl[i], room)
                self.bank_l[i] = 1
                self.top_l[i] = max(road_y - 0.4, self.surface[i] + 2.0)
            else:
                self.wr[i] = min(self.wr[i], room)
                self.bank_r[i] = 1
                self.top_r[i] = max(road_y - 0.4, self.surface[i] + 2.0)
        # Smooth changes of width; a wall runs a little past where it is needed.
        for w in (self.wl, self.wr):
            w[:] = _smooth(np.minimum.reduce([np.roll(w, s) for s in range(-6, 7)]), 13)
        for b in (self.bank_l, self.bank_r):
            b[:] = (np.convolve(b, np.ones(9), mode='same') > 0).astype(int)
        self.top_l = _smooth(self.top_l, 9)
        self.top_r = _smooth(self.top_r, 9)
        for k, i in self._cross:
            t = ref.tan[k]
            deck = float(ref.y[k])
            # The deck spans the water and both gravel banks.
            reach = self.half + 9.0
            # Along the road; the crossing may be oblique.
            sin = abs(t[0] * self.tan[i][1] - t[1] * self.tan[i][0])
            reach /= max(0.45, sin)
            a = ref.xz[k] - t * reach
            b = ref.xz[k] + t * reach
            self.bridges.append({'a': [round(float(a[0]), 1), round(float(a[1]), 1)],
                                 'b': [round(float(b[0]), 1), round(float(b[1]), 1)],
                                 'river': int(i), 'deck': round(deck, 2)})

    def find_footbridges(self, osm):
        """Mapped footbridges over the river (Ura e Goricës, the Mangalem
        footbridge): their two ends, structure and name."""
        self.footbridges = []
        for w in osm.ways.values():
            tags = w.get('tags') or {}
            if tags.get('bridge') != 'yes' or tags.get('highway') not in ('pedestrian', 'footway', 'path', 'cycleway'):
                continue
            pts = osm.coords(w)
            if len(pts) < 2:
                continue
            a, b = np.asarray(pts[0], float), np.asarray(pts[-1], float)
            da, ia = self.tree.query(a)
            db, ib = self.tree.query(b)
            if da > self.half + 40.0 or db > self.half + 40.0:
                continue
            sa = float(np.dot(a - self.pts[ia], self.nrm[ia]))
            sb = float(np.dot(b - self.pts[ib], self.nrm[ib]))
            if sa * sb >= 0.0 or a.__sub__(b).dot(a - b) < 400.0:
                continue
            _, im = self.tree.query((a + b) * 0.5)
            self.footbridges.append({'a': [round(float(a[0]), 2), round(float(a[1]), 2)],
                                     'b': [round(float(b[0]), 2), round(float(b[1]), 2)],
                                     'structure': tags.get('bridge:structure', 'beam'),
                                     'name': tags.get('name', ''), 'historic': tags.get('historic') == 'yes',
                                     'surface': round(float(self.surface[im]), 2)})
        return self.footbridges

    # ------------------------------------------------------------------ terrain

    def carve(self, h, ref, hw):
        """Lower the terrain under the channel below the water (in place)."""
        n = h.shape[0]
        xs = self.x0 + np.arange(n) * self.cell
        zs = self.z0 + np.arange(n) * self.cell
        lo = self.pts.min(axis=0) - self.half - 60.0
        hi = self.pts.max(axis=0) + self.half + 60.0
        ix = np.nonzero((xs >= lo[0]) & (xs <= hi[0]))[0]
        iz = np.nonzero((zs >= lo[1]) & (zs <= hi[1]))[0]
        gx, gz = np.meshgrid(xs[ix], zs[iz])
        q = np.stack([gx.ravel(), gz.ravel()], axis=1)
        d, i = self.tree.query(q)
        lat = np.einsum('ij,ij->i', q - self.pts[i], self.nrm[i])
        width = np.where(lat > 0, self.wl[i], self.wr[i])
        walled = np.where(lat > 0, self.bank_l[i], self.bank_r[i]) > 0
        reach = width + np.where(walled, 0.5, 1.5) * self.cell
        inside = (np.abs(lat) < reach) & (d < self.half + 2.0 * self.cell)
        bridged = np.zeros(len(q), bool)
        for b in self.bridges:
            a, c = np.asarray(b['a']), np.asarray(b['b'])
            ab = c - a
            t = np.clip(((q - a) @ ab) / (ab @ ab), 0, 1)
            bridged |= np.hypot(*(a + t[:, None] * ab - q).T) < hw + 2.0
        carved = 0
        for k in np.nonzero(inside)[0]:
            if not bridged[k]:
                dt, _ = ref.nearest(q[k, 0], q[k, 1])
                if dt < hw + 4.0:
                    continue
            r, c = iz[k // len(ix)], ix[k % len(ix)]
            target = float(self.surface[i[k]]) - 1.4
            if h[r, c] > target:
                h[r, c] = target
                carved += 1
        return carved

    def water_at(self, x, z):
        """True where (x, z) is on the water or a gravel bank (for props)."""
        d, i = self.tree.query([x, z])
        lat = float(np.dot(np.asarray([x, z]) - self.pts[i], self.nrm[i]))
        w = self.wl[i] if lat > 0 else self.wr[i]
        return d < self.half + 30.0 and abs(lat) < w + 10.0

    def to_json(self):
        r = lambda a, k=2: [round(float(v), k) for v in a]
        return {
            'name': self.cfg['way_name'],
            'sample': SAMPLE,
            'x': r(self.pts[:, 0], 1), 'z': r(self.pts[:, 1], 1),
            'surface': r(self.surface), 'wl': r(self.wl, 1), 'wr': r(self.wr, 1),
            'bank_l': [int(v) for v in self.bank_l], 'bank_r': [int(v) for v in self.bank_r],
            'top_l': r(self.top_l), 'top_r': r(self.top_r),
            'bridges': self.bridges,
            'footbridges': getattr(self, 'footbridges', []),
        }
