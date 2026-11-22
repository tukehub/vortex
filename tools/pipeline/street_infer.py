"""Fill gaps in mapped street furniture with what a real street there would
carry (plans 3.4 / 3.5). OSM decides first; these rules only add where it has
nothing, and every added row ends in 1 so it is never mistaken for a mapped
one ([x, z, yaw, 1]; mapped rows stay [x, z, yaw]).

Rules, each checked against what is already mapped or added:
  signals    junctions where the circuit meets a trunk/primary/secondary/
             tertiary road, at least JUNCTION_GAP apart along the lap, not at
             a roundabout, with no mapped signal within 60 m: one pole on the
             right-hand kerb of each approach, 12 m before the junction.
  crossings  a zebra 6 m before every signalised junction (mapped or added)
             that has no mapped crossing within 40 m; mapped highway=crossing
             nodes on the race road come first.
  bins       beside every bus shelter without a bin within 10 m, and beside
             every third bench without one within 20 m.
  benches    along footways and pedestrian streets near the circuit, every
             BENCH_STEP metres where no bench stands within BENCH_STEP, on the
             side away from the traffic, facing the walkway.
  bollards   three across each pedestrian street where it meets a road.
"""
import math

import numpy as np

MAJOR = {'trunk': 4, 'primary': 3, 'secondary': 2, 'tertiary': 1,
         'trunk_link': 2, 'primary_link': 2, 'secondary_link': 1, 'tertiary_link': 1}
WALKS = {'footway', 'pedestrian'}
JUNCTION_GAP = 250.0
MAX_SIGNAL_JUNCTIONS = 14
SIGNAL_SETBACK = 12.0
CROSSING_SETBACK = 6.0
CROSSING_WIDTH = 4.0
MAX_CROSSINGS = 24
CROSSING_GAP = 60.0
BENCH_STEP = 35.0
BENCH_REACH = 90.0
MAX_BENCHES = 80
MAX_BOLLARD_ENTRIES = 20


def yaw_facing(fx, fz):
    return math.atan2(-fx, -fz)


class Lap:
    """Arc-length view of the circuit: position and heading at s, s of a point."""

    def __init__(self, pts):
        p = np.asarray([[q[0], q[2]] for q in pts], np.float64)
        self.p = p
        seg = np.linalg.norm(np.roll(p, -1, axis=0) - p, axis=1)
        self.cum = np.concatenate([[0.0], np.cumsum(seg)])
        self.L = float(self.cum[-1])

    def at(self, s):
        s = s % self.L
        i = int(np.searchsorted(self.cum, s, side='right') - 1)
        i = min(i, len(self.p) - 1)
        a, b = self.p[i], self.p[(i + 1) % len(self.p)]
        seg = max(self.cum[i + 1] - self.cum[i], 1e-9)
        t = (s - self.cum[i]) / seg
        d = (b - a) / seg
        q = a + (b - a) * t
        return float(q[0]), float(q[1]), float(d[0]), float(d[1])

    def locate(self, x, z):
        """(s, distance) of the closest point on the circuit."""
        a = self.p
        b = np.roll(a, -1, axis=0)
        d = b - a
        ln2 = np.maximum((d * d).sum(1), 1e-9)
        t = np.clip(((x - a[:, 0]) * d[:, 0] + (z - a[:, 1]) * d[:, 1]) / ln2, 0.0, 1.0)
        cx = a[:, 0] + d[:, 0] * t
        cz = a[:, 1] + d[:, 1] * t
        dist2 = (x - cx) ** 2 + (z - cz) ** 2
        i = int(np.argmin(dist2))
        return float(self.cum[i] + t[i] * math.sqrt(ln2[i])), math.sqrt(float(dist2[i]))

    def gap(self, s1, s2):
        d = abs(s1 - s2) % self.L
        return min(d, self.L - d)


def _near(rows, x, z, r):
    return any((x - q[0]) ** 2 + (z - q[1]) ** 2 < r * r for q in rows)


def junctions(lines, lap, hw):
    """Where a major road meets or crosses the circuit: [(s, rank)] sorted by s."""
    found = []
    for tags, pts in lines:
        rank = MAJOR.get(tags.get('highway'))
        if not rank or tags.get('junction') == 'roundabout' or len(pts) < 2:
            continue
        dist = [lap.locate(x, z) for x, z in pts]
        for i, (s, d) in enumerate(dist):
            if d > hw + 3.0:
                continue
            for j in (i - 1, i + 1):
                if 0 <= j < len(pts) and dist[j][1] > hw + 15.0:
                    found.append((s, rank))
                    break
    found.sort()
    merged = []
    for s, rank in found:
        if merged and lap.gap(merged[-1][0], s) < 30.0:
            if rank > merged[-1][1]:
                merged[-1] = (s, rank)
            continue
        merged.append((s, rank))
    return merged


def roundabout_near(lines, x, z, r=50.0):
    for tags, pts in lines:
        if tags.get('junction') == 'roundabout' and any((x - p[0]) ** 2 + (z - p[1]) ** 2 < r * r for p in pts):
            return True
    return False


def signals(street, lines, lap, hw, ok):
    """Adds signal poles; returns the s of every signalised junction."""
    lights = street['traffic_light']
    mapped = [r for r in lights if len(r) < 4]
    clear = hw + 2.0
    chosen, signalised = [], []
    for s, rank in sorted(junctions(lines, lap, hw), key=lambda j: (-j[1], j[0])):
        x, z, _, _ = lap.at(s)
        if _near(mapped, x, z, 60.0):
            signalised.append(s)
            continue
        if len(chosen) >= MAX_SIGNAL_JUNCTIONS or roundabout_near(lines, x, z):
            continue
        if any(lap.gap(s, c) < JUNCTION_GAP for c in chosen):
            continue
        chosen.append(s)
        signalised.append(s)
        for direction in (1.0, -1.0):
            px, pz, dx, dz = lap.at(s - direction * SIGNAL_SETBACK)
            dx, dz = dx * direction, dz * direction
            rx, rz = -dz, dx                       # right of the approaching car
            qx, qz = px + rx * (clear + 1.0), pz + rz * (clear + 1.0)
            if ok('traffic_light', qx, qz):
                lights.append([round(qx, 2), round(qz, 2), round(yaw_facing(-dx, -dz), 3), 1])
    return signalised


def crossings(mapped_nodes, signalised, lap, hw):
    """Zebra crossings on the race road: [[x, z, width, inferred]]."""
    out = []
    for x, z in mapped_nodes:
        s, d = lap.locate(x, z)
        if d <= hw + 1.0 and not any(lap.gap(s, lap.locate(q[0], q[1])[0]) < CROSSING_GAP for q in out):
            px, pz, _, _ = lap.at(s)
            out.append([round(px, 2), round(pz, 2), CROSSING_WIDTH, 0])
    mapped_s = [lap.locate(q[0], q[1])[0] for q in out]
    for s in sorted(signalised):
        if any(lap.gap(s, m) < 40.0 for m in mapped_s):
            continue
        cs = s - CROSSING_SETBACK
        if any(lap.gap(cs, lap.locate(q[0], q[1])[0]) < CROSSING_GAP for q in out):
            continue
        px, pz, _, _ = lap.at(cs)
        out.append([round(px, 2), round(pz, 2), CROSSING_WIDTH, 1])
    out.sort(key=lambda q: (q[3], lap.locate(q[0], q[1])[0]))
    return out[:MAX_CROSSINGS]


def _side(yaw):
    """The model's local +X in world space."""
    return math.cos(yaw), -math.sin(yaw)


def bins(street, ok):
    rows = street['bin']
    for stop in street['bus_stop']:
        sx, sz = _side(stop[2])
        x, z = stop[0] + sx * 2.4, stop[1] + sz * 2.4
        if not _near(rows, stop[0], stop[1], 10.0) and ok('bin', x, z):
            rows.append([round(x, 2), round(z, 2), 0.0, 1])
    for i, bench in enumerate(street['bench']):
        if i % 3:
            continue
        sx, sz = _side(bench[2])
        x, z = bench[0] + sx * 1.3, bench[1] + sz * 1.3
        if not _near(rows, bench[0], bench[1], 20.0) and ok('bin', x, z):
            rows.append([round(x, 2), round(z, 2), 0.0, 1])


def benches(street, lines, lap, hw, roads, ok):
    rows = street['bench']
    added = 0
    for tags, pts in lines:
        if tags.get('highway') not in WALKS or len(pts) < 2:
            continue
        carry = BENCH_STEP * 0.5
        for (ax, az), (bx, bz) in zip(pts, pts[1:]):
            seg = math.hypot(bx - ax, bz - az)
            if seg < 0.5:
                continue
            ux, uz = (bx - ax) / seg, (bz - az) / seg
            t = carry
            while t < seg:
                x, z = ax + ux * t, az + uz * t
                t += BENCH_STEP
                if added >= MAX_BENCHES:
                    return
                s, d = lap.locate(x, z)
                if d < hw + 5.0 or d > BENCH_REACH or _near(rows, x, z, BENCH_STEP):
                    continue
                # Beside the walkway, on the side away from the traffic.
                nx, nz = -uz, ux
                road = roads.nearest(x, z)
                if road is not None and (road[2] - x) * nx + (road[3] - z) * nz > 0:
                    nx, nz = -nx, -nz
                half = 1.5 if tags.get('highway') == 'footway' else 3.5
                qx, qz = x + nx * (half + 0.6), z + nz * (half + 0.6)
                if ok('bench', qx, qz):
                    rows.append([round(qx, 2), round(qz, 2), round(yaw_facing(-nx, -nz), 3), 1])
                    added += 1
            carry = t - seg


def bollards(street, lines, roads, lap, reach, ok):
    rows = street['bollard']
    entries = 0
    for tags, pts in lines:
        if tags.get('highway') != 'pedestrian' or len(pts) < 2:
            continue
        for end, nxt in ((pts[0], pts[1]), (pts[-1], pts[-2])):
            if entries >= MAX_BOLLARD_ENTRIES:
                return
            road = roads.nearest(*end)
            if road is None or road[0] > road[1] + 1.5 or lap.locate(*end)[1] > reach:
                continue
            ln = math.hypot(nxt[0] - end[0], nxt[1] - end[1])
            if ln < 4.0 or _near(rows, end[0], end[1], 12.0):
                continue
            ux, uz = (nxt[0] - end[0]) / ln, (nxt[1] - end[1]) / ln
            # Just inside the pedestrian street, clear of the kerb.
            inside = max(2.0, road[1] - road[0] + 2.0)
            cx, cz = end[0] + ux * inside, end[1] + uz * inside
            placed = 0
            for k in (-1.6, 0.0, 1.6):
                x, z = cx - uz * k, cz + ux * k
                if ok('bollard', x, z):
                    rows.append([round(x, 2), round(z, 2), 0.0, 1])
                    placed += 1
            entries += 1 if placed else 0


def fill(street, lines, crossing_nodes, lap, hw, roads, ok, reach):
    """Adds inferred rows to `street` in place; returns the road crossings."""
    signalised = signals(street, lines, lap, hw, ok)
    benches(street, lines, lap, hw, roads, ok)
    bins(street, ok)
    bollards(street, lines, roads, lap, reach, ok)
    return crossings(crossing_nodes, signalised, lap, hw)
