import json
import os
import tempfile
import unittest

import rozafa
from common import Proj

ORIGIN = (42.0, 19.5)
CITY = {'origin': ORIGIN, 'landmarks': [{'id': 'rozafa', 'll': ORIGIN}]}


def osm(ways):
    """Synthetic Overpass JSON: each way a closed ring of local (x, z) metres."""
    proj = Proj(*ORIGIN)
    elements, nid = [], 1
    for wid, tags, ring in ways:
        ids = []
        for x, z in ring:
            lat, lon = proj.to_ll(x, z)
            elements.append({'type': 'node', 'id': nid, 'lat': lat, 'lon': lon})
            ids.append(nid)
            nid += 1
        elements.append({'type': 'way', 'id': wid, 'nodes': ids + ids[:1], 'tags': tags})
    return {'elements': elements}


def square(cx, cz, half):
    return [(cx - half, cz - half), (cx + half, cz - half), (cx + half, cz + half), (cx - half, cz + half)]


class RozafaTest(unittest.TestCase):
    def bake(self, ways):
        tmp = tempfile.mkdtemp()
        path = os.path.join(tmp, 'osm.json')
        with open(path, 'w') as f:
            json.dump(osm(ways), f)
        data, origin = rozafa.bake(path, tmp, CITY)
        return data, origin, tmp

    def test_parts_are_classified_and_kept_inside_the_walls(self):
        data, _, _ = self.bake([
            (rozafa.WALL_WAY, {'barrier': 'city_wall'}, square(0, 0, 100)),
            (1, {'building': 'yes', 'historic': 'castle', 'name': 'Barbakan - Main Fortified Entrance'}, square(95, 0, 10)),
            (2, {'building': 'yes', 'man_made': 'tower'}, square(-60, -60, 4)),
            (3, {'building': 'yes', 'historic': 'ruins', 'name': 'Kisha-xhami e Shën Stefanit'}, square(0, 0, 12)),
            (4, {'building': 'yes', 'historic': 'ruins'}, square(10, 13, 2)),
            (5, {'building': 'yes', 'name': 'Historical Museum of the Castle'}, square(40, 40, 10)),
            (6, {'building': 'yes', 'historic': 'ruins', 'name': 'Saranxha- medieval Cistern no 1.'}, square(-40, 40, 5)),
            (7, {'building': 'yes'}, square(500, 500, 5)),
        ])
        kinds = {p['id']: p['kind'] for p in data['parts']}
        self.assertEqual(kinds, {1: 'gate', 2: 'tower', 3: 'church', 4: 'minaret', 5: 'museum', 6: 'cistern'})
        self.assertGreaterEqual(len(data['wall']), 4)

    def test_trees_inside_or_on_the_walls_are_cleared(self):
        data, origin, tmp = self.bake([(rozafa.WALL_WAY, {'barrier': 'city_wall'}, square(0, 0, 100))])
        props = os.path.join(tmp, 'props.json')
        trees = [[0, 0, 0, 1], [101, 0, 0, 1], [140, 0, 0, 1]]
        with open(props, 'w') as f:
            json.dump({'trees': trees}, f)
        rozafa.clear_trees(props, [tuple(p) for p in data['wall']], origin)
        kept = json.load(open(props))['trees']
        self.assertEqual(len(kept), 1)
        self.assertAlmostEqual(kept[0][0], 140, delta=0.5)


if __name__ == '__main__':
    unittest.main()
