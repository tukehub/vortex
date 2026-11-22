"""Bake the Flag Square bronze group from the project's Renderpeople study mesh.

Run with the dependencies in tools/pipeline/requirements.txt. Coordinates in
the figure workshop face +Z. The finished monument faces local -Z in Godot.
"""
import json
import struct
from pathlib import Path

import numpy as np
from scipy.ndimage import maximum_filter
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from scipy.spatial.transform import Rotation

from pipeline.glb import GLB

ASSETS = Path(__file__).resolve().parents[1] / 'godot/assets'
SOURCE = ASSETS / 'models/crowd/rp_nathan_animated_003_walking_opt.glb'


def study_mesh():
    data = SOURCE.read_bytes()
    length = struct.unpack_from('<I', data, 12)[0]
    doc = json.loads(data[20:20 + length])
    binary = data[28 + length:]

    def array(index, dtype, width):
        acc = doc['accessors'][index]
        view = doc['bufferViews'][acc['bufferView']]
        offset = view.get('byteOffset', 0) + acc.get('byteOffset', 0)
        return np.frombuffer(binary, dtype, acc['count'] * width, offset).reshape(-1, width)

    prim = doc['meshes'][0]['primitives'][0]
    vertices, weld = np.unique(np.round(array(prim['attributes']['POSITION'], '<f4', 3), 5),
                               axis=0, return_inverse=True)
    faces = weld[array(prim['indices'], '<u2', 1)].reshape(-1, 3)
    edges = faces[:, [0, 1, 1, 2, 2, 0]].reshape(-1, 2)
    graph = coo_matrix((np.ones(len(edges)), edges.T), shape=(len(vertices), ) * 2).tocsr()
    # Flood the connected surface below the shoulders and groin. Hands that
    # overlap a trouser leg in silhouette still belong to the correct arm.
    groups = {}
    for kind, height in [('arm', 1.32), ('leg', 0.72)]:
        indices = np.flatnonzero(vertices[:, 1] < height)
        count, labels = connected_components(graph[indices][:, indices], directed=False)
        for label in range(count):
            group = indices[labels == label]
            x = vertices[group, 0].mean()
            if len(group) > 60 and (kind == 'leg' or abs(x) > .14):
                groups[kind, np.sign(x)] = group
    return vertices, faces, groups


def between(points, a, b, c, d):
    """Place a limb segment from a–b on c–d, retaining its cross section."""
    axis, target = b - a, d - c
    length = np.linalg.norm(axis)
    axis = axis / length
    direction = target / np.linalg.norm(target)
    cross = np.cross(axis, direction)
    angle = np.arctan2(np.linalg.norm(cross), np.dot(axis, direction))
    rotation = Rotation.from_rotvec(cross * angle / max(np.linalg.norm(cross), 1e-8))
    t = (points - a) @ axis / length
    return c + t[:, None] * target + rotation.apply(points - a - t[:, None] * (b - a))


def bend(points, indices, a, b, c, elbow, hand):
    a, b, c, elbow, hand = np.array([a, b, c, elbow, hand])
    source = points[indices]
    upper = between(source, a, b, a, elbow)
    lower = between(source, b, c, elbow, hand)
    weight = np.clip((b[1] + .05 - source[:, 1]) / .1, 0, 1)[:, None]
    points[indices] = upper * (1 - weight) + lower * weight


class Sculpture:
    def __init__(self):
        self.vertices, self.faces = [], []

    def mesh(self, points, faces):
        self.faces.extend(np.asarray(faces) + len(self.vertices))
        self.vertices.extend(points)

    def rings(self, rings):
        rows, cols, _ = np.shape(rings)
        faces = []
        for row in range(rows - 1):
            for col in range(cols - 1):
                i = row * cols + col
                faces.extend([(i, i + 1, i + cols + 1), (i, i + cols + 1, i + cols)])
        self.mesh(np.reshape(rings, (-1, 3)), faces)

    def clothing(self, coat, cap, cape):
        # Hem to shoulders, with a parted front and folds pulled by the legs.
        if coat or cape:
            rings = []
            for y, rx, rz, gap in [(.42, .26, .22, .43), (.64, .225, .187, .30),
                                   (.89, .183, .156, .12), (1.02, .16, .135, .07),
                                   (1.23, .20, .148, .18), (1.39, .22, .135, .40),
                                   (1.46, .09, .10, .48)]:
                a = np.linspace(gap, 2 * np.pi - gap, 49)
                hem = max(0., (1.38 - y))
                folds = 1 + hem * (.09 * np.sin(9 * a + .8 * y) + .055 * np.sin(13 * a))
                z = .012 + rz * np.cos(a) * folds
                if cape:
                    z -= hem ** 1.6 * (.24 + .32 * (1 - np.cos(a)))
                rings.append(np.stack([.028 + rx * np.sin(a) * folds, y + .045 * hem * np.cos(3 * a), z], axis=1))
            self.rings(rings)
            for side in [-1, 1]:
                self.mesh([(.028 + side * .064, 1.455, .09), (.028 + side * .155, 1.36, .118),
                           (.028 + side * .105, 1.322, .157), (.028 + side * .128, 1.30, .15),
                           (.028 + side * .039, 1.13, .159)], [(0, 1, 2), (0, 2, 4), (2, 3, 4)])
        if cap:
            a = np.linspace(0, 2 * np.pi, 29)
            rings = []
            for y, rx, rz in [(1.642, .087, .102), (1.66, .091, .107), (1.72, .084, .099), (1.755, .06, .074), (1.767, .001, .001)]:
                rings.append(np.stack([.047 + rx * np.sin(a), y + .008 * np.sin(a), .067 + rz * np.cos(a)], axis=1))
            self.rings(rings)


def surface_tones(points, faces):
    """Bake soft contact shadows into the static cast, including between figures."""
    triangles = points[faces]
    samples = [points, triangles.mean(axis=1)]
    for edge in range(3):
        samples.append((triangles[:, edge] + triangles[:, (edge + 1) % 3]) * .5)
    samples = np.concatenate(samples)
    shaded = np.zeros(len(points))
    directions = 32
    for i in range(directions):
        # Equal solid angles over the sky hemisphere.
        elevation = (i + .5) / directions
        azimuth = i * np.pi * (3 - np.sqrt(5))
        horizontal = np.sqrt(1 - elevation ** 2)
        ray = np.array([horizontal * np.cos(azimuth), elevation, horizontal * np.sin(azimuth)])
        right = np.array([-np.sin(azimuth), 0., np.cos(azimuth)])
        up = np.cross(ray, right)
        coords = np.round(np.stack([samples @ right, samples @ up], axis=1) / .085).astype(int)
        coords -= coords.min(axis=0)
        x, y = coords.T
        depth = samples @ ray
        screen = np.full((y.max() + 1, x.max() + 1), -np.inf)
        np.maximum.at(screen, (y, x), depth)
        nearest = maximum_filter(screen, size=3)[y[:len(points)], x[:len(points)]]
        shaded += np.clip((nearest - depth[:len(points)] - .16) * 3, 0., 1.)
    shade = shaded / directions
    # Muted green in recessed folds, warmer burnished ridges on exposed bronze.
    x, y, z = points.T
    variation = .5 + .5 * np.sin(4.3 * x + np.sin(3.1 * y)) * np.cos(2.9 * z - 1.4 * y)
    patina = np.clip(.20 * variation + .68 * shade, 0, 1)[:, None]
    tint = (1 - patina) * np.array([.91, .80, .68]) + patina * np.array([.48, .70, .64])
    rgb = tint * (1. - .60 * shade[:, None])
    return np.column_stack((rgb, np.ones(len(points))))


def build():
    source, faces, groups = study_mesh()
    bronze = Sculpture()
    # Position across the photograph, base height, depth towards the viewer,
    # stature, body turn, costume and gesture.
    cast = [
        (-.78, 2.10, 3.9, 6.40, -8, 'coat', 'document'), (-2.45, 2.10, 2.8, 5.75, 17, 'coat_cap', 'rest'),
        (-3.03, 2.10, .94, 6.55, -14, 'cap', 'salute'), (-4.46, 2.10, 1.84, 5.50, -23, 'coat_cap', 'rest'),
        (1.07, 2.10, 3.46, 6.70, 13, 'coat', 'lapel'), (3.04, 2.10, 3.22, 6.15, -14, 'cap', 'kneel'),
        (3.95, 2.10, 1.05, 5.65, 39, 'coat_cap', 'lapel'), (1.83, 2.10, .70, 6.38, -26, 'coat', 'rest'),
        (0, 14.10, -1.2, 5.25, -8, 'cape', 'flag')]
    for x, y, z, height, yaw, outfit, gesture in cast:
        person = Sculpture()
        points = source.copy()
        arms = {}
        if gesture == 'salute':
            arms[-1] = ((-.28, 1.61, .02), (-.31, 1.94, .05))
        elif gesture == 'flag':
            arms[-1] = ((-.16, 1.13, .19), (.13, 1.21, .29))
            arms[1] = ((.37, 1.13, .17), (.19, 1.40, .29))
        elif gesture in ('document', 'lapel', 'kneel'):
            arms[1] = ((.29, 1.12, .11), (.06, 1.18 if gesture == 'lapel' else .99, .22))
        for side, (elbow, hand) in arms.items():
            shoulder = (.028 + side * .195, 1.366, .011)
            rest_elbow = (side * .21, 1.095, .068 if side == 1 else -.021)
            wrist = (side * .21, .819, .185 if side == 1 else .029)
            bend(points, groups['arm', side], shoulder, rest_elbow, wrist, elbow, hand)
        if gesture == 'kneel':
            for side in [-1, 1]:
                hip = (side * .1, .76, .012)
                knee = (side * .1, .46, .14 if side == -1 else .019)
                ankle = (side * .09, .10, -.04)
                knee_pose = (side * .12, .70, .37) if side == -1 else (side * .13, .39, -.13)
                foot_pose = (side * .12, .39, .42) if side == -1 else (side * .13, .39, -.53)
                bend(points, groups['leg', side], hip, knee, ankle, knee_pose, foot_pose)
            y -= .32 * height / 1.75
        person.mesh(points, faces)
        person.clothing('coat' in outfit, 'cap' in outfit, outfit == 'cape')
        # The source figure faces +Z. Rotate the whole composition to the
        # monument's local -Z after turning each figure towards its neighbour.
        posed = Rotation.from_euler('y', yaw, degrees=True).apply(person.vertices) * (height / 1.75)
        bronze.mesh((posed + [x, y, z]) * [-1, 1, -1], person.faces)

    pts, idx = np.array(bronze.vertices), np.array(bronze.faces)
    triangles = pts[idx]
    winds = np.cross(triangles[:, 1] - triangles[:, 0], triangles[:, 2] - triangles[:, 0])
    norms = np.zeros_like(pts)
    for corner in range(3):
        np.add.at(norms, idx[:, corner], winds)
    norms /= np.maximum(np.linalg.norm(norms, axis=1, keepdims=True), 1e-8)
    glb = GLB()
    mat = glb.material('Weathered bronze', (.092, .091, .085, 1), metallic=.62, roughness=.61, double_sided=True)
    primitive = dict(pos=pts, nrm=norms, uv=pts[:, [0, 1]],
                     col=surface_tones(pts, idx), idx=idx, mat=mat)
    mesh = glb.mesh('IndependenceFigures', [primitive])
    glb.node('IndependenceFigures', mesh=mesh)
    glb.write(ASSETS / 'landmarks/independence_bronze.glb')


if __name__ == '__main__':
    build()
