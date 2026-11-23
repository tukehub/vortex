"""Check the shipped planting buffer against the independent race and map geometry."""
from pathlib import Path
import json
import unittest

import numpy as np
from scipy.spatial import cKDTree

from coastal_vegetation import FootprintMask, LAWN
from common import OUT


class CoastalCoverTest(unittest.TestCase):
    directory = Path(OUT)/'vlore'

    def setUp(self):
        self.seeds = np.fromfile(self.directory/'ground_cover.bin','<f4').reshape(-1,4)
        self.xz = self.seeds[:,[0,2]]

    def test_race_skirt_side_roads_and_buildings_are_clear(self):
        track = json.loads((self.directory/'track.json').read_text())
        route = np.array(track['pts'])[:,[0,2]]
        # Densify to one metre independently of the one-metre raster bake.
        delta = np.roll(route,-1,axis=0)-route
        samples = np.concatenate([route + delta*t/8 for t in range(8)])
        self.assertGreater(cKDTree(samples).query(self.xz)[0].min(), track['hw']+7.1)
        hard = FootprintMask(route)
        hard.mesh(self.directory/'buildings.glb', 1)
        hard.mesh(self.directory/'roads.glb', 0)
        self.assertTrue(hard.allows(self.xz, hard.buffered()).all())

    def test_lawn_avoids_both_diagonal_path_families(self):
        props = json.loads((self.directory/'props.json').read_text())
        front = props['seafront']
        line = np.asarray(front['line'])
        road = line[:,[0,2]]
        outer = road + line[:,3:5]*line[:,5:6]
        inner = road + line[:,3:5]*(front['hw']+12)
        arc = np.r_[0,np.cumsum(np.linalg.norm(np.diff(road,axis=0),axis=1))]
        points = self.xz[self.seeds[:,3] == LAWN]
        self.assertGreater(len(points), 100)
        tested = np.zeros(len(points),bool)
        for i in range(1,len(line)):
            corners = np.array([inner[i-1],inner[i],outer[i],outer[i-1]])
            nearby = np.flatnonzero(np.all((points>=corners.min(axis=0)) &
                                           (points<=corners.max(axis=0)),axis=1))
            if not len(nearby):
                continue
            # Invert the ribbon's two linear coordinates by interpolating
            # between its normals. Check physical path clearance in metres.
            t = np.full(len(nearby),.5)
            for _ in range(5):
                axis = road[i]-road[i-1]
                normal = line[i-1,3:5] + t[:,None]*(line[i,3:5]-line[i-1,3:5])
                offset = points[nearby]-road[i-1]
                det = axis[0]*normal[:,1] - axis[1]*normal[:,0]
                t = (offset[:,0]*normal[:,1]-offset[:,1]*normal[:,0])/det
            across = (axis[0]*offset[:,1]-axis[1]*offset[:,0])/det
            inside = (t>=0) & (t<=1) & (across>front['hw']+12) & (across<line[i-1,5]+t*(line[i,5]-line[i-1,5]))
            if not inside.any():
                continue
            u = arc[i-1] + t[inside]*(arc[i]-arc[i-1])
            v = across[inside]
            clearance = np.abs(np.mod([u+v+17,u-v+17],34)-17).min()
            self.assertGreater(clearance, 1.25)
            tested[nearby[inside]] = True
        self.assertTrue(tested.all())
