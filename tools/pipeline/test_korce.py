"""Korçë: the loop keeps its two must-see landmarks in view of the race."""
import unittest

from cities import CITIES
from common import Proj


class KorceConfigTest(unittest.TestCase):
    def setUp(self):
        self.city = CITIES['korce']
        self.proj = Proj(*self.city['origin'])
        self.marks = {lm['id']: lm for lm in self.city['landmarks']}

    def test_cathedral_and_school_replace_their_osm_footprints(self):
        # Katedralja Ngjallja e Krishtit and Muzeu Kombëtar i Arsimit.
        for way in (1165161082, 461159519):
            self.assertIn(way, self.city['landmark_buildings'])
        self.assertIn('korce_cathedral', self.marks)
        self.assertIn('mesonjetorja', self.marks)

    def test_school_is_brought_toward_the_boulevard_and_kept_open(self):
        school = self.marks['mesonjetorja']
        self.assertGreater(school.get('open_view', 0.0), 20.0, 'no corner board in front of the school')
        x, z = self.proj.to_xz(*school['ll'])
        moved = (school['offset_x'] ** 2 + school['offset_z'] ** 2) ** 0.5
        self.assertLess(moved, 50.0, 'an adaptation, not a relocation')
        # Every sight-line target the config names is one of its landmarks.
        cathedral = self.proj.to_xz(*self.marks['korce_cathedral']['ll'])
        shifted = (x + school['offset_x'], z + school['offset_z'])
        for line in self.city['sightlines']:
            for ll, _ in line['targets']:
                t = self.proj.to_xz(*ll)
                near = min(((t[0] - p[0]) ** 2 + (t[1] - p[1]) ** 2) ** 0.5 for p in (cathedral, shifted))
                self.assertLess(near, 2.0)

    def test_start_is_on_republika_before_the_square(self):
        self.assertEqual(self.city['finish_before']['metres'], 100.0)
        self.assertEqual(self.city['waypoints'][0], (40.61850, 20.78258))


if __name__ == '__main__':
    unittest.main()
