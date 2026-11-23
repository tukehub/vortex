"""Bake three original broadleaf silhouettes and matching impostors for Tirana.

Uses the repository's NumPy GLB writer and Pillow. Bark colour and normal are
from Poly Haven Tree Small 02 (CC0). Sprays, branching and silhouettes are
generated here. No network or DCC project is required.
"""
import argparse
from pathlib import Path
import math
import random

import numpy as np
from PIL import Image, ImageDraw

from glb import GLB

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "godot/assets/foliage"
OUT = SOURCE / "tirana"
# Descriptors are artistic interpretations: broad plane, upright linden, open acacia.
SPECIES = ("plane", "linden", "acacia")
SPRAY_SIZE = 128
TILE = (128, 160)
WIDTH, HEIGHT = 8.6, 11.0
LEAF_UV = ((0, 1), (1, 1), (1, 0), (0, 0))


def unit(a):
    return a / max(np.linalg.norm(a), 1e-9)


def lerp(a, b, t):
    return a + (b - a) * t


def sprays():
    """Paint three padded twig swatches with stems, leaf venation and tonal variety."""
    atlas = Image.new("RGBA", (SPRAY_SIZE * 4, SPRAY_SIZE))
    for species in range(3):
        rng = random.Random(329 + species)
        base = ((76, 103, 45), (68, 98, 48), (78, 106, 52))[species]
        # Keep the RGB border foliage-coloured for the coverage-preserving mip chain.
        tile = Image.new("RGBA", (256, 256), (*base, 0))
        draw = ImageDraw.Draw(tile)
        root = np.array((127, 224))
        for j in range(9):
            angle = math.radians(201 + j * 17 + rng.uniform(-7, 7))
            axis = np.array((math.cos(angle), math.sin(angle)))
            tip = root + axis * rng.uniform(114, 204 if 2 < j < 7 else 156)
            tip = np.clip(tip, 26, 230)
            draw.line([tuple(root), tuple(tip)], fill=(100, 102, 53, 255), width=3)
            for k in range(10 if species == 2 else 8):
                where = lerp(root, tip, (k + 1) / (11 if species == 2 else 9))
                for side in (-1, 1):
                    heading = angle + side * rng.uniform(.52, 1.37)
                    forward = np.array((math.cos(heading), math.sin(heading)))
                    across = np.array((-forward[1], forward[0]))
                    length = rng.uniform(19, 32) * (1 - .24 * k / 9)
                    width = length * (.49, .43, .29)[species]
                    color = tuple(int(c * rng.uniform(.85, 1.20)) for c in base)
                    # Pointed, asymmetric leaves with a lightly shaded fold.
                    points = [where]
                    for fraction, extent in ((.20, .72), (.49, 1.), (.79, .56), (1., 0.)):
                        points.append(where + forward * length * fraction + across * width * extent)
                    for fraction, extent in ((.78, -.63), (.43, -.92), (.16, -.61)):
                        points.append(where + forward * length * fraction + across * width * extent)
                    draw.polygon([tuple(point) for point in points], fill=(*color, 255))
                    draw.line([tuple(where), tuple(where + forward * length * .82)],
                              fill=(*(min(255, int(c * 1.13)) for c in color), 255))
        tile = tile.resize((SPRAY_SIZE, SPRAY_SIZE), Image.Resampling.LANCZOS)
        atlas.paste(tile, (species * SPRAY_SIZE, 0))
    return atlas


class Surface:
    def __init__(self):
        self.pos = []
        self.nrm = []
        self.uv = []
        self.col = []
        self.idx = []

    def add(self, vertices, normals, uvs, colors, faces):
        offset = len(self.pos)
        self.pos.extend(vertices)
        self.nrm.extend(normals)
        self.uv.extend(uvs)
        self.col.extend(colors)
        self.idx.extend(tuple(i + offset for i in face) for face in faces)

    def primitive(self, material):
        return {key: np.asarray(getattr(self, key)) for key in ("pos", "nrm", "uv", "col", "idx")} | {"mat": material}


def tube(mesh, points, radii, sides, shade=1.0, twist=0.0):
    """Continuous tapered cross sections with smooth normals and a bark seam."""
    points = np.asarray(points)
    vertices, normals, uvs, indices = [], [], [], []
    orientation = unit(points[-1] - points[0])
    right = unit(np.cross(orientation, (0, 0, 1)))
    if np.linalg.norm(right) < .1:
        right = unit(np.cross(orientation, (1, 0, 0)))
    length = 0.
    stride = sides + 1
    for j, p in enumerate(points):
        axis = unit(points[min(j + 1, len(points) - 1)] - points[max(j - 1, 0)])
        local_right = unit(right - axis * np.dot(right, axis))
        around = np.cross(axis, local_right)
        if j:
            length += np.linalg.norm(p - points[j - 1])
        for i in range(stride):
            angle = math.tau * i / sides + twist
            radial = local_right * math.cos(angle) + around * math.sin(angle)
            # Taper-shifted normals avoid horizontal bands at the forks.
            normals.append(unit(radial + axis * .09))
            vertices.append(p + radial * radii[j] * (1 + .08 * math.sin(i % sides * 2.71 + j)))
            uvs.append((i / sides, length * .68))
    for j in range(len(points) - 1):
        for i in range(sides):
            a = j * stride + i
            b = a + stride
            indices.extend(((a, a + 1, b), (a + 1, b + 1, b)))
    end = (len(points) - 1) * stride
    for i in range(1, sides - 1):
        indices.append((end, end + i, end + i + 1))
    mesh.add(vertices, normals, uvs, [(shade, shade, shade, 1.)] * len(vertices), indices)


def foliage(mesh, center, size, angle, pitch, up_bias, species, shade):
    right = np.array((math.cos(angle), 0., math.sin(angle)))
    up = np.array((-right[2] * math.sin(pitch), math.cos(pitch), right[0] * math.sin(pitch)))
    corners = [center - right * size[0] - up * size[1], center + right * size[0] - up * size[1],
               center + right * size[0] + up * size[1], center - right * size[0] + up * size[1]]
    # Artificial normals follow the rounded lobe; they are independent of card facing.
    normals = [unit(up_bias + (p - center) * .36) for p in corners]
    uvs = [((species * SPRAY_SIZE + 5 + u * (SPRAY_SIZE - 10)) / 512,
            (5 + v * (SPRAY_SIZE - 10)) / SPRAY_SIZE) for u, v in LEAF_UV]
    mesh.add(corners, normals, uvs, [(shade, shade, shade, 1.)] * 4, ((0, 1, 2), (0, 2, 3)))


def tree(species, near):
    """Both meshes share major forks and crown lobes; fine branches and sprays decimate separately."""
    bark, leaf = Surface(), Surface()
    rng = random.Random(7032 + species * 73)
    full_height = (8.15, 9.0, 7.5)[species]
    spread = (2.55, 1.73, 3.0)[species]
    lean = np.array((.24, 0., -.18)) * (species + 1) / 2
    stem = [np.array((0., y * full_height, 0.)) + lean * y * y
            for y in (0., .18, .39, .57, .72, .85)]
    tube(bark, stem if near else [stem[i] for i in (0, 2, 4, 5)],
         ([.34, .27, .235, .155, .082, .021] if near else [.34, .235, .082, .021]),
         8 if near else 5, twist=.18)
    # Roots merge into the lower trunk, adding depth at wheel-height cameras.
    if near:
        for i in range(4):
            a = i * math.tau / 4 + .35
            tip = np.array((math.cos(a) * .53, -.03, math.sin(a) * .53))
            tube(bark, ((0, .29, 0), tip), (.16, .055), 5)
    lobes = [(stem[-1], np.array((0., 1., .14)), .94)]
    for i in range(6):
        a = i * 2.399 + rng.uniform(-.24, .24)
        radial = np.array((math.cos(a), 0., math.sin(a)))
        stem_index = 2 + i % 3
        start = stem[stem_index]
        outer = spread * (1.02 - (stem_index - 2) * .13) * rng.uniform(.79, 1.13)
        rise = full_height * (.22 if species == 2 else .27)
        split = start + radial * outer * .58 + np.array((0., rise * .58, 0.))
        end = start + radial * outer + np.array((0., rise, 0.))
        tube(bark, (start, split, end) if near else (start, end),
             (.135, .078, .026) if near else (.135, .026), 6 if near else 4, .84 + .022 * i, a)
        lobes.append((end, unit(radial * .79 + np.array((0, .71, 0))), 1.))
        side = np.array((-radial[2], 0., radial[0])) * (-1 if i % 2 else 1)
        fork = split + side * (.55 + .12 * species) + radial * .31 + np.array((0., .87, 0.))
        if near:
            tube(bark, (split, fork), (.065, .014), 5, .88, a)
        lobes.append((fork, unit(side * .55 + radial * .35 + np.array((0, .77, 0))), .72))
    details = random.Random(904 + species)
    # Flatten the spreading acacia clusters, lift the linden clusters.
    squash = (.87, 1.14, .68)[species]
    for center, normal, scale in lobes:
        card_count = 7 if near else 3
        for i in range(card_count):
            azimuth = i * math.pi / card_count + details.uniform(-.15, .15)
            offset = np.array((math.cos(azimuth), details.uniform(-.85, .85), math.sin(azimuth)))
            position = center + offset * scale * (.4 if near else .22)
            size = scale * (details.uniform(.80, 1.24) if near else details.uniform(1.20, 1.54))
            bias = unit(normal * .72 + offset * .47 + np.array((0., .39, 0.)))
            lower = .80 if i % 3 == 0 else 1.0
            foliage(leaf, position, (size, size * squash), azimuth, details.uniform(-.85, .85),
                    bias, species, details.uniform(.79, 1.) * lower)
    return bark, leaf


def impostors(models, bark_texture, leaf_atlas, coverage=None):
    """Orthographic z-buffer bake with four azimuths per species."""
    result = Image.new("RGBA", (512, 512))
    tile_width, tile_height = TILE
    ratios, layers = [], []
    for species, (bark, leaves) in enumerate(models):
        for angle_index in range(4):
            angle = angle_index * math.tau / 4
            right = np.array((math.cos(angle), 0., -math.sin(angle)))
            eye = np.array((math.sin(angle), 0., math.cos(angle)))
            depth = np.full((tile_height, tile_width), -np.inf)
            rgba = np.zeros((tile_height, tile_width, 4), np.uint8)
            footprint = np.zeros(depth.shape, np.uint16) if coverage else None
            accepted = np.zeros(depth.shape, np.uint16) if coverage else None
            rgba[:, :, :3] = (70, 95, 46)
            for part, texture in ((bark, bark_texture), (leaves, leaf_atlas)):
                points = np.asarray(part.pos)
                tx = texture.shape[1]
                ty = texture.shape[0]
                px = (points @ right / WIDTH + .5) * (tile_width - 8) + 4
                py = (1 - points[:, 1] / HEIGHT) * (tile_height - 8) + 4
                pz = points @ eye
                xy = np.c_[px, py]
                nrm = np.asarray(part.nrm)
                uv = np.asarray(part.uv)
                tint = np.asarray(part.col)[:, 0]
                for tri in part.idx:
                    ids = list(tri)
                    a, b, c = xy[ids]
                    x0, y0 = np.maximum(0, np.floor(np.minimum(np.minimum(a, b), c))).astype(int)
                    x1, y1 = np.minimum((tile_width, tile_height), np.ceil(np.maximum(np.maximum(a, b), c))).astype(int)
                    ab, ac = b - a, c - a
                    det = ab[0] * ac[1] - ab[1] * ac[0]
                    if abs(det) < .001 or x1 <= x0 or y1 <= y0:
                        continue
                    yy, xx = np.mgrid[y0:y1, x0:x1]
                    dx, dy = xx + .5 - a[0], yy + .5 - a[1]
                    w1 = (dx * ac[1] - dy * ac[0]) / det
                    w2 = (ab[0] * dy - ab[1] * dx) / det
                    weights = np.stack((1. - w1 - w2, w1, w2), axis=2)
                    z = weights @ pz[ids]
                    sample_uv = (weights @ uv[ids]) % 1.
                    sample = texture[(sample_uv[..., 1] * ty).astype(int), (sample_uv[..., 0] * tx).astype(int)]
                    inside = np.all(weights >= 0., axis=2)
                    opaque = inside & (sample[..., 3] >= 108)
                    if coverage and part is leaves:
                        footprint[y0:y1, x0:x1] += inside
                        accepted[y0:y1, x0:x1] += opaque
                    valid = opaque & (z > depth[y0:y1, x0:x1])
                    altitude = np.clip((weights @ nrm[ids])[..., 1], -1, 1)
                    shade = (.81 + .19 * altitude) * np.sqrt(weights @ tint[ids])
                    rgba[y0:y1, x0:x1, :3][valid] = np.clip(sample[..., :3] * shade[..., None], 0, 255)[valid]
                    rgba[y0:y1, x0:x1, 3][valid] = 255
                    depth[y0:y1, x0:x1][valid] = z[valid]
            result.paste(Image.fromarray(rgba), (angle_index * tile_width, species * tile_height))
            if coverage:
                ratios.append(accepted.sum() / max(footprint.sum(), 1))
                layers.append(accepted[accepted > 0])
    if coverage:
        all_layers = np.concatenate(layers)
        print(f"{coverage}: alpha passes {100 * np.mean(ratios):.1f}% of card fragments; "
              f"layers p50/p95/max = {np.percentile(all_layers, 50):.0f}/"
              f"{np.percentile(all_layers, 95):.0f}/{all_layers.max()}")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--coverage", action="store_true", help="report four orthographic alpha-test views per species")
    args = parser.parse_args()
    OUT.mkdir(exist_ok=True)
    leaf = sprays()
    leaf.save(OUT / "leaf_sprays.png")
    bark_files = "tree_small_02_mobile_tree_small_02_"
    bark = Image.open(SOURCE / (bark_files + "diff_1k.jpg")).convert("RGB")
    bark = bark.resize((256, 256), Image.Resampling.LANCZOS)
    bark.save(OUT / "bark.jpg", quality=92)
    normal = Image.open(SOURCE / (bark_files + "nor_gl_1k.jpg")).convert("RGB")
    normal.resize((256, 256), Image.Resampling.LANCZOS).save(OUT / "bark_normal.png")
    glb = GLB()
    bark_id, leaf_id = glb.material("Bark"), glb.material("Leaves")
    lods = [[], []]
    for species, name in enumerate(SPECIES):
        for lod in (0, 1):
            trunk, crown = tree(species, lod == 0)
            mesh_name = f"{name}_lod{lod}"
            mesh = glb.mesh(mesh_name, [trunk.primitive(bark_id), crown.primitive(leaf_id)])
            glb.node(mesh_name, mesh)
            lods[lod].append((trunk, crown))
            print(f"{mesh_name}: {len(trunk.idx)} bark + {len(crown.idx)} leaf triangles")
    glb.write(OUT / "broadleaf_trees.glb")
    bark_data, leaf_data = np.asarray(bark.convert("RGBA")), np.asarray(leaf)
    impostors(lods[1], bark_data, leaf_data, "LOD1" if args.coverage else None).save(OUT / "impostors.png")
    if args.coverage:
        impostors(lods[0], bark_data, leaf_data, "LOD0")


if __name__ == "__main__":
    main()
