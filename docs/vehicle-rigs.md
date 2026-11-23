# Vehicle visual rigs

The garage, race and points arena pass the selected `Data.CARS` entry to `CarVisual.setup`. Its `visual` dictionary selects the chassis independently of its saved ID, price, paint and driving statistics. Race contact uses the fixed clipped footprint in `sim/race.gd`. Arena contact uses the two circles in `sim/arena_car.gd`. Imported collision objects are rejected before scene attachment.

## Asset contract

Use metres, +Y up, the nose toward −Z and the left wheels at negative X. Place the origin on the ground between the axles. Export one unscaled chassis root with these direct children.

```text
CarRoot
  Body
  Glass
  Interior
  Wheel_FL
  Wheel_FR
  Wheel_RL
  Wheel_RR
  Headlights
  BrakeLights
  Nitro_L
  Nitro_R
```

`Body` is the painted MeshInstance3D used for livery bounds. Keep painted surfaces in its local coordinates. Each wheel can be a mesh or a Node3D pivot containing meshes. Put its origin on the axle and orient its geometry at rest. Steering acts around chassis Y and rolling around chassis X. Lamps can contain multiple lens meshes. Place the nitro markers at the exhaust outlets with local +Z pointing along the exhaust plume.

| Visual field | Runtime use |
| --- | --- |
| `model_path` | Base imported PackedScene, typically a GLB. |
| `visual_scale` | Positive uniform scale on the rendered chassis. |
| `wheel_radius`, `wheelbase` | Positive model-space distances. Scale is applied once to spin and steering calculations. |
| `wheel_offsets` | Optional absolute pivot positions in CarRoot space keyed by canonical wheel name. Empty uses authored positions. |
| `material_slots` | Imported material name to runtime role. Canonical names work directly. Required roles are paint, glass, interior, tyre, rim, light_front and light_rear. |
| `light_nodes` | CarRoot-relative paths for front and rear lamp assemblies. Bounds locate the beams and glows. |
| `nitro_sockets` | CarRoot-relative paths for left and right exhaust markers. |
| `lod_models` | Optional low, medium and high replacement paths selected at spawn. Each uses the same rig contract. Godot mesh LODs handle camera distance within each model. |

Create a profile alongside the existing profiles in `vehicle_rig.gd` and reference it from the car data. The loader reports the model path and missing parts, wheel pivots, sockets and material roles. It tries the base rig if a preset model fails validation, then the public GT. The legacy GT adapter also handles the optional encrypted sport payload staged by the existing private-car tools. Other profiles keep their own bodywork in a private build.

## Provenance and mobile import

| Model | Provenance and commercial use |
| --- | --- |
| Vortex GT | Existing adaptation of **Car Concept** by Darmstadt Graphics Group GmbH and Eric Chadwick, licensed CC BY 4.0. Attribution and modifications are recorded in the in-game credits. |
| Hatch and Estate | Original first-party procedural vehicle assets created for commercial distribution with VORTEX. The dimensions, profiles, lamps, cabin, rails and wheel layouts are defined in `tools/build_original_cars.py`, using the project's original loft and wheel builders in `tools/gen_cars.py`. All geometry is generated locally without a third-party mesh, logo, scan or texture. |

Rebuild the two original GLBs with `python tools/build_original_cars.py`. Each shares a single wheel mesh across four wheel instances, merges disconnected parts by material, and ships without embedded textures. Both use Godot's generated mesh LODs and shadow meshes. The shared livery atlas uses mipmaps and VRAM compression, including ETC2 on Mobile. Record the author, source, commercial rights and required attribution before adding another model. Private payloads and keys stay in the existing ignored staging directory.

After importing a new chassis, run the catalog and binding checks with Godot 4.4.1.

```sh
godot --headless --path godot --import
godot --headless --path godot res://tests/vehicle_rigs.tscn
```
