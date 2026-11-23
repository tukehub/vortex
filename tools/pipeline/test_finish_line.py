"""Regression: the start/finish goes on a straight the asked distance before
a landmark, or placement refuses rather than putting it in a turn."""
import math
import unittest

import numpy as np

from finish_line import MIN_RADIUS, place_finish_before, tightest_radius


def stadium(straight=400.0, radius=60.0, step=6.0):
    """A closed loop: two straights joined by half circles, driven anticlockwise."""
    pts = []
    x = 0.0
    while x < straight:
        pts.append([x, 0.0, 0.0])
        x += step
    for k in range(int(math.pi * radius / step)):
        a = -math.pi / 2 + k * step / radius
        pts.append([straight + radius * math.cos(a), 0.0, radius + radius * math.sin(a)])
    x = straight
    while x > 0:
        pts.append([x, 0.0, 2 * radius])
        x -= step
    for k in range(int(math.pi * radius / step)):
        a = math.pi / 2 + k * step / radius
        pts.append([radius * math.cos(a), 0.0, radius + radius * math.sin(a)])
    return pts


class FinishLineTest(unittest.TestCase):
    def setUp(self):
        self.pts = stadium()

    def test_line_lands_the_distance_before_the_landmark_on_a_straight(self):
        pts, info = place_finish_before(self.pts, np.array([300.0, -40.0]), 100.0)
        self.assertAlmostEqual(pts[0][0], 200.0, delta=6.0)
        self.assertEqual(pts[0][2], 0.0)
        self.assertAlmostEqual(info['metres_before'], 100.0, delta=6.0)
        self.assertGreaterEqual(info['tightest_radius_m'], MIN_RADIUS)
        self.assertEqual(len(pts), len(self.pts))

    def test_refuses_a_line_in_a_turn(self):
        # 100 m before a landmark beside the far bend's exit is in the bend.
        with self.assertRaises(ValueError):
            place_finish_before(self.pts, np.array([440.0, 150.0]), 100.0)

    def test_idempotent(self):
        once, _ = place_finish_before(self.pts, np.array([300.0, -40.0]), 100.0)
        twice, _ = place_finish_before(once, np.array([300.0, -40.0]), 100.0)
        self.assertEqual(once, twice)

    def test_radius_measure(self):
        xz = np.array([[p[0], p[2]] for p in self.pts])
        self.assertGreater(tightest_radius(xz, 30), 1e5)          # mid-straight
        bend = min(range(len(self.pts)), key=lambda i: (self.pts[i][0] - 460) ** 2 + (self.pts[i][2] - 60) ** 2)
        self.assertLess(tightest_radius(xz, bend), 70.0)          # in the 60 m bend


if __name__ == '__main__':
    unittest.main()
