"""vlore_boulevard.py: the stretch line and the occupancy grid."""
import unittest

import numpy as np

import vlore_boulevard as vb
from common import Proj


class BoulevardTest(unittest.TestCase):
    def test_raster_marks_triangle_cells_only(self):
        grid = np.zeros((10, 10), np.uint8)
        tri = np.array([[[1.0, 0, 1.0], [8.0, 0, 1.0], [1.0, 0, 8.0]]])
        vb._raster(grid, tri, 0.0, 0.0, 1.0, vb.ROAD)
        self.assertEqual(grid[2, 2], vb.ROAD)
        self.assertEqual(grid[8, 8], 0)
        self.assertEqual(grid[0, 0], 0)

    def test_edge_on_wall_marks_its_line(self):
        grid = np.zeros((10, 10), np.uint8)
        wall = np.array([[[1.0, 0, 5.0], [8.0, 0, 5.0], [8.0, 6, 5.0]]])
        vb._raster(grid, wall, 0.0, 0.0, 1.0, vb.BUILDING)
        self.assertTrue((grid[5, 2:8] & vb.BUILDING).all())

    def test_rle_round_trip(self):
        row = np.array([0, 0, 1, 1, 1, 0, 2], np.uint8)
        runs = vb._rle(row)
        out = []
        for v, n in zip(runs[::2], runs[1::2]):
            out += [v] * n
        self.assertEqual(out, row.tolist())

    def test_stretch_takes_the_short_way_round(self):
        proj = Proj(40.0, 19.0)
        pts = [[float(x), 0.0, 0.0] for x in range(0, 100, 5)]
        a = proj.to_ll(10.0, 0.0)
        b = proj.to_ll(30.0, 0.0)
        line = vb.stretch_line(pts, proj, {'from': a, 'to': b})
        self.assertEqual(len(line), 5)
        self.assertAlmostEqual(line[0][0], 10.0)
        self.assertAlmostEqual(line[-1][0], 30.0)


if __name__ == '__main__':
    unittest.main()
