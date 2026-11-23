"""Out-and-back circuits (Vlorë): the far loop merges into the return
carriageway without touching the outbound one, the build refuses a lap whose
passes share road, and seafront dressing follows the first (sea-side) pass."""
import math
import unittest

import numpy as np

from build_city import _merge_join, _resample_open, check_carriageways_apart, SAMPLE
from seafront import _first_pass

HW = 4.5


def line(a, b):
    return _resample_open(np.array([a, b], float), SAMPLE)


class MergeJoinTest(unittest.TestCase):
    def setUp(self):
        # Shore road running north (-z) at x = 0; outbound 6 m west of it
        # heading south, return 6 m east heading north.
        self.outbound = line((-6.0, -400.0), (-6.0, 0.0))
        self.back = line((6.0, 0.0), (6.0, -400.0))

    def _check(self, loop):
        joined, back, info = _merge_join(loop, self.back, self.outbound, HW)
        path = np.vstack([joined, back])
        steps = np.linalg.norm(np.diff(path, axis=0), axis=1)
        self.assertLess(steps.max(), SAMPLE * 1.6, 'the join is continuous')
        # Heading never reverses and the road never folds.
        tangents = np.diff(path, axis=0) / steps[:, None]
        self.assertTrue(np.all(np.sum(tangents[1:] * tangents[:-1], axis=1) > 0.9))
        gap = min(np.min(np.linalg.norm(self.outbound - p, axis=1)) for p in joined)
        self.assertGreaterEqual(gap, 2 * HW + 1.0, 'the merge stays off the outbound carriageway')
        self.assertGreaterEqual(info['radius'], 12.0)
        return info

    def test_shallow_merge_from_the_inland_road(self):
        # Dhimitër Konomi: comes up from the south-east at a shallow angle.
        loop = np.vstack([line((500.0, 900.0), (120.0, 260.0)), line((120.0, 260.0), (40.0, 60.0))])
        info = self._check(loop)
        self.assertEqual(info['cut'], 0.0, 'a clear approach is kept whole')

    def test_road_converging_on_the_outbound_is_cut_back(self):
        # An incoming road that would run into the outbound carriageway.
        loop = np.vstack([line((500.0, 900.0), (160.0, 120.0)), line((160.0, 120.0), (-2.0, 20.0))])
        info = self._check(loop)
        self.assertGreater(info['cut'], 0.0)

    def test_impossible_merge_raises(self):
        with self.assertRaises(ValueError):
            # Comes in on the far side of the outbound carriageway.
            _merge_join(np.vstack([line((-300.0, 900.0), (-30.0, 50.0)), line((-30.0, 50.0), (-8.0, 10.0))]),
                        self.back, self.outbound, HW)


class CarriagewaysApartTest(unittest.TestCase):
    def lap(self, gap):
        # Out 600 m, a hairpin of radius gap/2, back alongside: 2 m samples.
        t = np.linspace(0.0, math.pi, int(math.pi * gap / 4) + 2)[1:-1]
        out = np.column_stack([np.zeros(301), np.linspace(0.0, 600.0, 301)])
        arc = np.column_stack([gap / 2 - gap / 2 * np.cos(t), 600.0 + gap / 2 * np.sin(t)])
        return np.vstack([out, arc, out[::-1] + [gap, 0.0]])

    def test_divided_lap_passes(self):
        check_carriageways_apart(self.lap(12.0), HW)

    def test_touching_carriageways_fail(self):
        with self.assertRaises(ValueError):
            check_carriageways_apart(self.lap(8.0), HW)


class FirstPassTest(unittest.TestCase):
    def test_first_pass_wins_over_the_nearer_return(self):
        out = np.column_stack([np.full(100, -6.0), np.arange(100.0) * 2])
        back = np.column_stack([np.full(100, 6.0), np.arange(100.0)[::-1] * 2])
        xz = np.vstack([out, back])
        k = _first_pass(xz, np.array([5.0, 100.0]))
        self.assertLess(k, 100, 'the outbound pass, though the return runs nearer')
        self.assertAlmostEqual(xz[k][1], 100.0, delta=2.0)


if __name__ == '__main__':
    unittest.main()
