"""Regression: inferred street furniture and crossings follow street practice
and only fill gaps in what OSM maps."""
import math
import unittest

from street_infer import (CROSSING_SETBACK, SIGNAL_SETBACK, Lap, bins, bollards, benches, crossings, fill,
                          junctions, signals)
from street_props import KINDS, Roads


def facing(yaw):
    return -math.sin(yaw), -math.cos(yaw)


def empty():
    return {k: [] for k in KINDS}


class StreetInferTest(unittest.TestCase):
    def setUp(self):
        # A 4 km square lap, driven east along z = -1000 first; half width 8.
        pts = []
        for side in range(4):
            for i in range(200):
                t = -1000.0 + i * 10.0
                pts.append([[t, 0, -1000.0], [1000.0, 0, t], [-t, 0, 1000.0], [-1000.0, 0, -t]][side])
        self.lap = Lap(pts)
        self.hw = 8.0
        # A primary road crossing the first straight at x = 0, running north–south.
        self.primary = ({'highway': 'primary'}, [(0.0, -1200.0), (0.0, -1000.0), (0.0, -800.0)])
        self.roads = Roads([(0.0, -1200.0, 0.0, -800.0, 5.5), (-1000.0, -1000.0, 1000.0, -1000.0, 8.0)])
        self.ok = lambda kind, x, z: True

    def test_junction_found_where_a_major_road_meets_the_lap(self):
        found = junctions([self.primary], self.lap, self.hw)
        self.assertEqual(len(found), 1)
        self.assertAlmostEqual(found[0][0], 1000.0, delta=1.0)
        minor = ({'highway': 'residential'}, self.primary[1])
        self.assertEqual(junctions([minor], self.lap, self.hw), [])

    def test_signals_on_right_kerb_of_each_approach_facing_traffic(self):
        street = empty()
        signalised = signals(street, [self.primary], self.lap, self.hw, self.ok)
        self.assertEqual(len(signalised), 1)
        poles = street['traffic_light']
        self.assertEqual(len(poles), 2)
        for x, z, yaw, inferred in poles:
            self.assertEqual(inferred, 1)
            self.assertAlmostEqual(abs(x), SIGNAL_SETBACK, delta=0.5)
            self.assertGreaterEqual(abs(z + 1000.0), self.hw + 2.0)
        east = [p for p in poles if p[0] < 0][0]   # approached driving east (+x)
        self.assertGreater(east[1], -1000.0)        # right of an eastbound car is south (+z)
        self.assertLess(facing(east[2])[0], -0.9)   # head looks back west at the traffic
        west = [p for p in poles if p[0] > 0][0]
        self.assertLess(west[1], -1000.0)
        self.assertGreater(facing(west[2])[0], 0.9)

    def test_mapped_signal_means_no_new_poles(self):
        street = empty()
        street['traffic_light'].append([3.0, -985.0, 0.0])
        signalised = signals(street, [self.primary], self.lap, self.hw, self.ok)
        self.assertEqual(len(signalised), 1)
        self.assertEqual(len(street['traffic_light']), 1)

    def test_no_signals_at_a_roundabout(self):
        ring = ({'highway': 'primary', 'junction': 'roundabout'}, [(20.0, -990.0), (-20.0, -990.0)])
        street = empty()
        self.assertEqual(signals(street, [self.primary, ring], self.lap, self.hw, self.ok), [])

    def test_crossing_before_signalised_junction_unless_mapped(self):
        marks = crossings([], [1000.0], self.lap, self.hw)
        self.assertEqual(len(marks), 1)
        x, z, width, inferred = marks[0]
        self.assertEqual(inferred, 1)
        self.assertAlmostEqual(x, -CROSSING_SETBACK, delta=0.5)
        marks = crossings([(10.0, -1001.0)], [1000.0], self.lap, self.hw)
        self.assertEqual([m[3] for m in marks], [0])
        # A mapped crossing off the race road is not painted on it.
        self.assertEqual(crossings([(10.0, -1030.0)], [], self.lap, self.hw), [])

    def test_bins_beside_shelters_and_benches(self):
        street = empty()
        street['bus_stop'].append([0.0, -980.0, 0.0])
        street['bench'] += [[100.0 * i, -950.0, 0.0] for i in range(6)]
        bins(street, self.ok)
        self.assertEqual(len(street['bin']), 3)          # the shelter, benches 0 and 3
        self.assertAlmostEqual(street['bin'][0][0], 2.4)
        street2 = empty()
        street2['bus_stop'].append([0.0, -980.0, 0.0])
        street2['bin'].append([1.0, -980.0, 0.0])
        bins(street2, self.ok)
        self.assertEqual(len(street2['bin']), 1)

    def test_benches_along_a_footway_away_from_traffic(self):
        walk = ({'highway': 'footway'}, [(-300.0, -970.0), (300.0, -970.0)])
        street = empty()
        benches(street, [walk], self.lap, self.hw, self.roads, self.ok)
        rows = street['bench']
        self.assertGreater(len(rows), 10)
        for x, z, yaw, inferred in rows:
            self.assertGreater(z, -970.0)                 # the side away from the race road
            self.assertLess(facing(yaw)[1], -0.9)         # facing the walkway (north)
        xs = sorted(r[0] for r in rows)
        self.assertTrue(all(b - a >= 34.9 for a, b in zip(xs, xs[1:])))

    def test_bollards_across_a_pedestrian_street_entry(self):
        plaza = ({'highway': 'pedestrian'}, [(300.0, -1009.0), (300.0, -1060.0)])
        street = empty()
        bollards(street, [plaza], self.roads, self.lap, 250.0, self.ok)
        rows = street['bollard']
        self.assertEqual(len(rows), 3)
        self.assertTrue(all(z < -1009.0 - 1.9 for _, z, _, _ in rows))
        self.assertAlmostEqual(max(r[0] for r in rows) - min(r[0] for r in rows), 3.2, places=2)

    def test_fill_respects_the_filter(self):
        street = empty()
        marks = fill(street, [self.primary], [], self.lap, self.hw, self.roads, lambda k, x, z: False, 250.0)
        self.assertEqual(sum(len(v) for v in street.values()), 0)
        self.assertEqual(len(marks), 1)                   # paint needs no free kerb


if __name__ == '__main__':
    unittest.main()
