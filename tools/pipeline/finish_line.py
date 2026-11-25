"""Start/finish line placement for a city whose config names `finish_before`:

  'finish_before': {'ll': (lat, lon), 'metres': 100}

The lap is rotated so it begins `metres` before the point of the circuit
nearest `ll` (a landmark seen from the road). The line must sit on a straight
street: over the starting grid behind it and the run past it, no stretch may
bend tighter than MIN_RADIUS (a gently curving boulevard passes; a corner,
junction turn or roundabout does not), or placement fails rather than putting
the finish in a turn. Within SNAP metres, the sample nearest the asked
distance that passes wins.

Run on an already processed city (rotates track.json in place; idempotent):
  python3 tools/pipeline/finish_line.py vlore
build_city.py applies the same function to a fresh route.
"""
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from common import OUT, Proj, log  # noqa: E402
from cities import CITIES  # noqa: E402

GRID_BEHIND = 40.0     # metres behind the line: the grid is ~31 m deep (Race)
RUN_AFTER = 40.0       # metres past the line that must also be straight
MIN_RADIUS = 150.0     # tightest bend allowed there, metres
STEP = 12.0            # bend measured over this arc length
SNAP = 12.0            # metres the line may move to find the straightest spot
PASS_SLACK = 20.0      # a pass this much further than the nearest still counts


def _cum(xz):
    seg = np.linalg.norm(np.roll(xz, -1, axis=0) - xz, axis=1)
    return np.concatenate([[0.0], np.cumsum(seg)])


def _heading(xz, cum, s):
    s %= cum[-1]
    i = min(int(np.searchsorted(cum, s, side='right')) - 1, len(xz) - 1)
    j = (i + 1) % len(xz)
    return math.atan2(xz[j, 1] - xz[i, 1], xz[j, 0] - xz[i, 0])


def tightest_radius(xz, i0, behind=GRID_BEHIND, after=RUN_AFTER):
    """Smallest bend radius (metres) over any STEP-metre arc from `behind`
    metres before sample i0 to `after` metres past it (closed polyline)."""
    cum = _cum(xz)
    s0 = cum[i0]
    worst = math.inf
    s = s0 - behind
    while s + STEP <= s0 + after + 1e-6:
        turn = abs((_heading(xz, cum, s + STEP) - _heading(xz, cum, s) + math.pi) % (2 * math.pi) - math.pi)
        worst = min(worst, STEP / turn if turn > 1e-9 else math.inf)
        s += 3.0
    return worst


def place_finish_before(points, anchor_xz, metres):
    """Rotate closed `points` ([x, y, z] rows) to start `metres` before the
    point nearest `anchor_xz`. Returns (points, info)."""
    xz = np.asarray([[p[0], p[2]] for p in points], float)
    cum = _cum(xz)
    lap = cum[-1]
    # Where the lap first passes the landmark: on an out-and-back circuit the
    # landmark is passed twice (outbound and return, a carriageway apart), and
    # the line belongs to the first pass in lap order.
    dist = np.hypot(xz[:, 0] - anchor_xz[0], xz[:, 1] - anchor_xz[1])
    passes = np.where(dist <= dist.min() + PASS_SLACK)[0]
    near = int(min(passes, key=lambda i: (i, dist[i])))
    near = int(min((j for j in passes if abs(j - near) < 40), key=lambda j: dist[j]))
    target = (cum[near] - metres) % lap
    off = lambda i: abs((cum[i] - target + lap / 2) % lap - lap / 2)
    candidates = sorted((i for i in range(len(xz)) if off(i) <= SNAP), key=off)
    # The sample nearest the asked distance whose grid and run are straight.
    ok = [i for i in candidates if tightest_radius(xz, i) >= MIN_RADIUS]
    if not ok:
        radius = max(tightest_radius(xz, i) for i in candidates)
        raise ValueError(f'finish {metres:.0f} m before the landmark would sit in a turn (radius {radius:.0f} m)')
    best = ok[0]
    radius = tightest_radius(xz, best)
    before = (cum[near] - cum[best]) % lap
    return points[best:] + points[:best], {'index': best, 'tightest_radius_m': round(min(radius, 1e6)),
                                           'metres_before': round(float(before), 1),
                                           'distance_to_anchor': round(float(np.hypot(*(xz[near] - anchor_xz))), 1)}


def place_sprint(points, line_xz):
    """An out-and-back raced once without turning at the line: the lap passes
    `line_xz` twice, a carriageway apart. Rotate closed `points` to start on
    the pass the turn lies just behind, and return (points, sprint) with
    sprint = {'start': [x, z], 'finish': [x, z]}: the finish is the other
    pass beside the start, reached at the end of the run before the turn."""
    xz = np.asarray([[p[0], p[2]] for p in points], float)
    cum = _cum(xz)
    lap = cum[-1]
    cum = cum[:len(xz)]
    dist = np.hypot(xz[:, 0] - line_xz[0], xz[:, 1] - line_xz[1])
    first = int(np.argmin(dist))
    # The nearest sample of the other pass: far along the lap from the first.
    apart = np.abs((cum - cum[first] + lap / 2) % lap - lap / 2)
    other = int(np.argmin(np.where(apart > 60.0, dist, np.inf)))
    # Start where the run forward to the other pass is the long way round.
    forward = (cum[other] - cum[first]) % lap
    start, finish = (first, other) if forward > lap / 2 else (other, first)
    rotated = points[start:] + points[:start]
    return rotated, {'start': [round(float(v), 2) for v in xz[start]],
                     'finish': [round(float(v), 2) for v in xz[finish]]}


def process_sprint(cid):
    city = CITIES[cid]
    proj = Proj(*city['origin'], city.get('latitude_compression', ()))
    path = os.path.join(OUT, cid, 'track.json')
    with open(path, encoding='utf8') as f:
        tj = json.load(f)
    tj['pts'], tj['sprint'] = place_sprint(tj['pts'], np.asarray(proj.to_xz(*city['sprint']['ll']), float))
    with open(path, 'w', encoding='utf8') as f:
        json.dump(tj, f, separators=(',', ':'))
    log(f'[{cid}] sprint {tj["sprint"]}')
    return tj['sprint']


def process_city(cid):
    city = CITIES[cid]
    spec = city.get('finish_before')
    if not spec:
        raise SystemExit(f'{cid} has no finish_before')
    proj = Proj(*city['origin'], city.get('latitude_compression', ()))
    path = os.path.join(OUT, cid, 'track.json')
    with open(path, encoding='utf8') as f:
        tj = json.load(f)
    anchor = np.asarray(proj.to_xz(*spec['ll']), float)
    tj['pts'], info = place_finish_before(tj['pts'], anchor, float(spec.get('metres', 100.0)))
    with open(path, 'w', encoding='utf8') as f:
        json.dump(tj, f, separators=(',', ':'))
    log(f'[{cid}] start/finish {info}')
    return info


if __name__ == '__main__':
    for cid in sys.argv[1:] or ['vlore']:
        process_city(cid)
