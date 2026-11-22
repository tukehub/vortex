"""Regression: street furniture stays off the race road, out of buildings and
landmarks, steps out to a kerb from where OSM maps it, and faces the road."""
import math
import unittest

from street_props import Buildings, KERB_GAP, Roads, TRACK_KERB, Track, from_osm, kind_of, place


def facing(yaw):
    """Unit direction a -Z-facing model looks at after `yaw`."""
    return -math.sin(yaw), -math.cos(yaw)


class StreetPropsTest(unittest.TestCase):
    def setUp(self):
        # Race road: a 2 km square loop, half width 10, along x and z axes.
        pts = []
        for i in range(200):
            pts.append([-1000.0 + i * 10.0, 0.0, -1000.0])
        for i in range(200):
            pts.append([1000.0, 0.0, -1000.0 + i * 10.0])
        for i in range(200):
            pts.append([1000.0 - i * 10.0, 0.0, 1000.0])
        for i in range(200):
            pts.append([-1000.0, 0.0, 1000.0 - i * 10.0])
        self.track = Track(pts, 10.0)
        # A side road running north from the track's south edge at x = 0
        # (half width 4), and one building east of it.
        self.roads = Roads([(0.0, -1000.0, 0.0, -800.0, 4.0)])
        self.buildings = Buildings([[(20.0, -900.0), (40.0, -900.0), (40.0, -880.0), (20.0, -880.0)]])
        self.clear = 10.0 + TRACK_KERB

    def run_place(self, items, **kw):
        return place(items, self.track, self.roads, self.buildings, **kw)

    def test_kinds_from_tags(self):
        self.assertEqual(kind_of({'highway': 'traffic_signals'}), 'traffic_light')
        self.assertEqual(kind_of({'public_transport': 'platform', 'bus': 'yes'}), 'bus_stop')
        self.assertEqual(kind_of({'amenity': 'waste_basket'}), 'bin')
        self.assertIsNone(kind_of({'amenity': 'cafe'}))
        self.assertIsNone(kind_of(None))

    def test_signal_on_race_road_moves_behind_its_kerb(self):
        out = self.run_place([('traffic_light', 0.0, -1000.0, (0.0, 1.0))])
        self.assertEqual(len(out['traffic_light']), 1)
        x, z, _ = out['traffic_light'][0]
        self.assertGreaterEqual(self.track.nearest(x, z)[0], self.clear)

    def test_signal_on_side_road_goes_to_right_kerb(self):
        # Mapped on the centreline, road heading north (-z): right is +x.
        out = self.run_place([('traffic_light', 0.0, -850.0, (0.0, -1.0))])
        x, z, yaw = out['traffic_light'][0]
        self.assertAlmostEqual(x, 4.0 + KERB_GAP['traffic_light'], places=2)
        self.assertAlmostEqual(z, -850.0, places=2)
        fx, fz = facing(yaw)
        self.assertGreater(fz, 0.9)  # head looks back at approaching traffic

    def test_bus_stop_beside_road_keeps_side_and_faces_road(self):
        out = self.run_place([('bus_stop', -7.0, -870.0, None)])
        x, z, yaw = out['bus_stop'][0]
        self.assertLess(x, -4.0)
        fx, fz = facing(yaw)
        self.assertGreater(fx, 0.9)  # open front toward the road (east)

    def test_small_items_dropped_on_race_road_and_in_buildings(self):
        out = self.run_place([('bench', 5.0, -1003.0, None), ('bin', 30.0, -890.0, None),
                              ('bollard', 0.0, -995.0, None)])
        self.assertEqual(out['bench'], [])
        self.assertEqual(out['bin'], [])
        self.assertEqual(out['bollard'], [])

    def test_bench_on_carriageway_steps_onto_pavement_and_faces_road(self):
        out = self.run_place([('bench', 1.5, -900.0, None)])
        x, z, yaw = out['bench'][0]
        self.assertAlmostEqual(x, 4.0 + KERB_GAP['bench'], places=2)
        fx, _ = facing(yaw)
        self.assertLess(fx, -0.9)

    def test_reach_keepouts_anchors_water_and_spacing(self):
        items = [('bin', 0.0, 0.0, None),                   # 1000 m from the track
                 ('bin', -500.0, -900.0, None),             # inside a keepout
                 ('bin', -300.0, -900.0, None),             # beside a landmark
                 ('bin', 500.0, -900.0, None),              # in the sea
                 ('bin', 700.0, -900.0, None), ('bin', 700.3, -900.0, None)]
        out = self.run_place(items, keepouts=[(-510.0, -910.0, -490.0, -890.0)],
                             anchors=[(-290.0, -900.0)], water=lambda x, z: 450.0 < x < 550.0)
        self.assertEqual(out['bin'], [[700.0, -900.0, 0.0]])

    def test_from_osm_reads_items_roads_and_buildings(self):
        elements = [
            {'type': 'node', 'id': 1, 'lat': 0.0, 'lon': 0.0},
            {'type': 'node', 'id': 2, 'lat': 0.001, 'lon': 0.0, 'tags': {'highway': 'traffic_signals'}},
            {'type': 'node', 'id': 3, 'lat': 0.002, 'lon': 0.0},
            {'type': 'node', 'id': 4, 'lat': 0.0005, 'lon': 0.0003, 'tags': {'amenity': 'bench'}},
            {'type': 'way', 'id': 10, 'nodes': [1, 2, 3], 'tags': {'highway': 'secondary'}},
            {'type': 'way', 'id': 11, 'nodes': [1, 3, 2, 1], 'tags': {'building': 'yes'}},
            {'type': 'way', 'id': 12, 'nodes': [1, 3], 'tags': {'highway': 'footway'}},
        ]

        class P:
            def to_xz(self, lat, lon):
                return lon * 100000.0, -lat * 100000.0
        items, segments, rings = from_osm(elements, P())
        kinds = {it[0]: it for it in items}
        self.assertEqual(set(kinds), {'traffic_light', 'bench'})
        self.assertIsNotNone(kinds['traffic_light'][3])     # on the secondary road
        self.assertIsNone(kinds['bench'][3])
        self.assertEqual(len(segments), 2)                  # the footway carries no cars
        self.assertEqual(len(rings), 1)


if __name__ == '__main__':
    unittest.main()
