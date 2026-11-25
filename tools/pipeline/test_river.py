"""River bake (river.py) and quarter houses (old_quarters.py) on synthetic data."""
import unittest
from types import SimpleNamespace

import numpy as np

import old_quarters
from river import River


def _osm(river_pts, buildings=()):
    nodes, ways = {}, {}
    nid = 1
    ids = []
    for x, z in river_pts:
        nodes[nid] = (x, z, None)
        ids.append(nid)
        nid += 1
    ways[1] = {'id': 1, 'nodes': ids, 'tags': {'waterway': 'river', 'name': 'Test'}}
    for k, ring in enumerate(buildings):
        ids = []
        for x, z in ring:
            nodes[nid] = (x, z, None)
            ids.append(nid)
            nid += 1
        ways[100 + k] = {'id': 100 + k, 'nodes': ids + [ids[0]], 'tags': {'building': 'house'}}
    osm = SimpleNamespace(nodes=nodes, ways=ways)
    osm.coords = lambda w: [(nodes[n][0], nodes[n][1]) for n in w['nodes'] if n in nodes]
    return osm


class RiverTest(unittest.TestCase):
    def setUp(self):
        n, cell = 81, 15.0
        self.nm = {'x0': -600.0, 'z0': -600.0, 'cell': cell, 'n': n}
        xs = -600.0 + np.arange(n) * cell
        gx, gz = np.meshgrid(xs, xs)
        # A valley along x falling west, the river in its floor at z = 0.
        self.near = (60.0 + gx * 0.004 + np.abs(gz) * 0.05).astype(np.float32)
        self.river = River({'way_name': 'Test', 'width': 40.0}, _osm([(-400.0 + 10 * i, 0.0) for i in range(81)]), self.near, self.nm)

    def test_flows_downhill_with_a_level_that_never_rises(self):
        r = self.river
        self.assertGreater(r.pts[0][0], r.pts[-1][0], 'ordered upstream (east) to downstream (west)')
        self.assertTrue(np.all(np.diff(r.surface) <= 1e-6), 'the water never rises downstream')

    def test_a_crossing_road_is_lifted_to_deck_level(self):
        dense = np.array([[0.0, z] for z in np.arange(-300.0, 300.0, 2.0)])
        y = np.full(len(dense), 55.0)
        lifted = self.river.lift_crossings(dense, y, 2.0)
        self.assertEqual(len(self.river._cross), 1)
        k, i = self.river._cross[0]
        self.assertGreaterEqual(lifted[k], self.river.surface[i] + 5.0)
        self.assertEqual(lifted[0], 55.0, 'far from the river the road is untouched')

    def test_carve_lowers_the_channel_below_the_water(self):
        dense = np.array([[x, 300.0] for x in np.arange(-500.0, 500.0, 2.0)])
        ref = SimpleNamespace(nearest=lambda x, z: (abs(z - 300.0), 0), xz=dense, y=np.full(len(dense), 70.0),
                              tan=np.tile([1.0, 0.0], (len(dense), 1)))
        self.river._cross = []
        self.river.fit_to_track(ref, 9.0)
        h = self.near.copy()
        carved = self.river.carve(h, ref, 9.0)
        self.assertGreater(carved, 0)
        i = len(self.river.pts) // 2
        c = self.river.pts[i]
        col, row = int((c[0] + 600) / 15), int((c[1] + 600) / 15)
        self.assertLess(h[row, col], self.river.surface[i])


class QuarterTest(unittest.TestCase):
    def test_house_front_faces_downhill(self):
        ring = [(0.0, 0.0), (12.0, 0.0), (12.0, 8.0), (0.0, 8.0)]
        osm = _osm([(0.0, 0.0), (1.0, 0.0)], [ring])
        polys = [('q', [(-50, -50), (50, -50), (50, 50), (-50, 50)])]
        picked = old_quarters.select(osm, polys)
        self.assertEqual(list(picked), [100])
        # Ground falling toward +z (south): the downhill edge is the z = 8 side.
        sample = lambda x, z: 100.0 - 0.3 * np.asarray(z, float)
        baked = old_quarters.bake(osm, picked, polys, sample)
        house = baked['houses'][0]
        r = house['ring']
        a, b = r[house['front']], r[(house['front'] + 1) % len(r)]
        self.assertAlmostEqual((a[1] + b[1]) * 0.5, 8.0)
        self.assertGreater(house['hi'] - house['lo'], 2.0)


if __name__ == '__main__':
    unittest.main()
