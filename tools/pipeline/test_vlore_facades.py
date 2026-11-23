"""Check the contracts between the Vlorë baker, imported meshes and runtime."""
import json
from pathlib import Path
import unittest

import numpy as np

from common import OUT
from vlore_facades import read_model


class VloreFacadesTest(unittest.TestCase):
    city = Path(OUT) / 'vlore'

    def test_skyline_keeps_chunk_placement_and_bounds(self):
        _, shells, shell_attribute, _ = read_model(self.city / 'buildings.glb')
        _, skyline, far_attribute, _ = read_model(self.city / 'skyline.glb')
        chunks = {node['name']: node for node in skyline['nodes']}
        self.assertEqual(set(chunks), {node['name'] for node in shells['nodes']})
        for node in shells['nodes']:
            proxy = chunks[node['name']]
            self.assertEqual(node['translation'], proxy['translation'])
            surfaces = shells['meshes'][node['mesh']]['primitives']
            merged, = skyline['meshes'][proxy['mesh']]['primitives']
            near = np.vstack([shell_attribute(p, 'POSITION') for p in surfaces])
            far = far_attribute(merged, 'POSITION')
            np.testing.assert_array_equal(near.min(axis=0), far.min(axis=0))
            np.testing.assert_array_equal(near.max(axis=0), far.max(axis=0))
            self.assertLess(len(far), len(near))

    def test_showcase_frontages_reference_shared_modules(self):
        _, modules, _, _ = read_model(self.city / 'facade_modules.glb')
        available = {node['name'] for node in modules['nodes']}
        placements = json.loads((self.city / 'frontages.json').read_text())
        reached = set()
        for row in placements:
            family, x, _, z = row[:4]
            if family >= 4:
                self.assertIn(f'Roof{family - 4}', available)
                continue
            self.assertAlmostEqual(row[4]**2 + row[5]**2, 1, places=4)
            for variant in range(3):
                self.assertIn(f'Bay{family}_{variant}', available)
            if np.hypot(x - 15, z + 3016) < 110:
                reached.add('flag-square')
            if np.hypot(x + 184, z + 1266) < 110:
                reached.add('lungomare')
        self.assertEqual(reached, {'flag-square', 'lungomare'})
