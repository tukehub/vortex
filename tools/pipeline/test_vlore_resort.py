"""Vlorë's resort strip (vlore_resort.py): models face the road the way the
game turns landmarks (local -Z forward, yaw about +Y)."""
import math
import unittest

import numpy as np

from vlore_resort import _footprint, _yaw_facing


class FacingTest(unittest.TestCase):
    def test_yaw_points_local_minus_z_along_the_direction(self):
        for d in ((1.0, 0.0), (0.0, 1.0), (-0.6, 0.8)):
            yaw = math.radians(_yaw_facing(np.array(d)))
            forward = (-math.sin(yaw), -math.cos(yaw))   # Basis(UP, yaw) * (0, 0, -1)
            self.assertAlmostEqual(forward[0], d[0], places=6)
            self.assertAlmostEqual(forward[1], d[1], places=6)

    def test_footprint_is_the_turned_rectangle(self):
        corners = _footprint(10.0, 20.0, 90.0, 30.0, 12.0)
        self.assertAlmostEqual(np.ptp(corners[:, 0]), 12.0, places=6)
        self.assertAlmostEqual(np.ptp(corners[:, 1]), 30.0, places=6)
        self.assertTrue(np.allclose(corners.mean(axis=0), (10.0, 20.0)))


if __name__ == '__main__':
    unittest.main()
