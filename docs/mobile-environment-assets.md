# Mobile environment assets

Use `tools/build_environment.py` for static Poly Haven CC0 photogrammetry models.
It produces three GLBs, one shared set of PBR images, Godot import settings
and a provenance and size report. The example builds into the ignored tools cache.

## Build

From the repository root, with Python 3.10+ and Node.js 22+ installed:

```sh
npm ci --prefix tools/environment
python3 tools/build_environment.py coast_rocks_02
```

Add an entry to `tools/environment/assets.json` or pass your own file with
`--manifest`. Set `id` to the Poly Haven asset ID and `triangles` to three
descending ceilings for LOD0 (near), LOD1 (mid), and LOD2 (far). Set
`errors` to adjust the relative simplification limits (defaults
`[0.01, 0.02, 0.04]`). Set `lock_border` for scans that need to meet at
shared tile edges. The build checks the actual triangle count for each level
and fails if the error limits prevent reaching the ceilings or if a surface
would disappear.

The default source tier is `1k`. For a major landmark surface with visible
detail loss at 1K, compare both tiers at normal driving distances and record
the scene and detail that justify `"resolution": "2k"`,
`"major_landmark": true` and a `"resolution_reason"`. Only the selected 1K
or 2K image tier is fetched. Poly Haven sometimes serves its shared geometry
buffer from a URL containing `8k`; the buffer contains geometry data.

The input must be a static, single-scene glTF with textured triangles, vertex
normals, albedo, OpenGL normal, roughness and AO. The tool reuses Poly Haven's
packed ARM image when available. For a separately mapped AO texture, it packs
red AO, green roughness and blue metallic into one image, with matching UV and
sampler settings. Material factors are retained. Unreferenced textures and
duplicate materials are removed before the GLBs are built.

## Import into Vortex

Build to a fresh directory using `--out`, or copy a completed package into
`godot/assets/environment/<asset>/` when the asset is ready for placement.
Keep the GLBs and their adjacent textures and `.import` files together so all
three levels reference the same texture resources. Archive
`environment-report.json` with asset provenance. It includes the source
URL, authors, license, input hashes, texture tier, triangle counts, and
per-file byte sizes and checksums for the GLBs and shared images.

Godot 4.4.1 imports these textures as high-quality VRAM-compressed textures
with mipmaps and writes an ASTC variant for the Android preset. Check for
`path.astc` in the texture sidecars after importing. The three GLBs are
separate scenes. Configure visibility ranges for their mesh instances when
placing the asset, then check the silhouettes, UV seams and LOD transitions
from Vortex's race camera. Select distances for the asset's footprint and
the expected approach speed. Use Vortex's Android profiling build to compare
frame time on target phones. Keep the generated example in the tools cache
until a scene uses it.

## Measured example

**Coast Rocks 02**, photography and processing by Rob Tuytel and cleanup by
Rico Cilliers, is available under CC0 1.0. The selected 1K source glTF
contains 1,260,423 triangles. [Asset](https://polyhaven.com/a/coast_rocks_02) · [License](https://polyhaven.com/license)

| Output | Triangles | Bytes |
| --- | ---: | ---: |
| LOD0 GLB | 11,995 | 341,372 |
| LOD1 GLB | 4,993 | 163,840 |
| LOD2 GLB | 1,800 | 77,160 |
| Shared 1K albedo | | 853,844 |
| Shared 1K normal | | 947,627 |
| Shared 1K ARM | | 785,725 |
| **Total GLBs and source images** | | **3,169,568** |

A Godot 4.4.1 Android test export contained three 1,398,180-byte ASTC
textures with mipmaps and three imported scenes. Their ZIP entries totaled
4,351,575 compressed bytes. The shared set uses approximately 4 MiB of
texture memory on an ASTC-capable GPU. Frame time and visual quality still
need a device check after placement.
