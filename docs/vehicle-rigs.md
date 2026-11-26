# Vehicle visual rigs

## The cars

Every car in `Data.MODELS` is the player's from the start. The garage's first tab, **Makina**, picks one, and the paint, rims and livery fit every car. Each car has its own driving statistics. Rivals drive the car their paint names in `Data.PAINTS`, so the grid still shows the GT, Sprint and Kombi.

| Car | Chassis | Top speed | Acceleration | Grip | Armour | Mass | 0–100 km/h (sim, straight road) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Vortex GT | `VehicleRig.GT` | 58.0 m/s (209 km/h) | 8.0 | 1.05 | 115 | 1.10 | 3.5 s |
| Vortex Sprint | `VehicleRig.HATCH` | 55.5 m/s (200 km/h) | 9.0 | 1.12 | 100 | 0.95 | 3.1 s |
| Vortex Kombi | `VehicleRig.ESTATE` | 56.5 m/s (203 km/h) | 7.3 | 0.99 | 145 | 1.35 | 3.8 s |
| Vortex Gepard | `VehicleRig.CHEETAH` | 61.0 m/s (220 km/h) | 8.5 | 1.10 | 92 | 1.00 | 3.2 s |

Top speed and acceleration feed `Race.physics` and the arena's driving. Grip sets cornering and corner-speed planning. Armour is the car's health, and mass sets how hard it pushes and is pushed in contact. Every car keeps the same contact footprint (`Data.CAR_SIZE`), so a car changes how it drives and never how it fits on the road. `Data.car(paint, model)` combines a paint with any car. Settings version 7 saves the car beside the paint. Older files keep the car their paint was drawn on. Online peers send their car in `HELLO`, and the protocol version is 2. `tests/car_models` covers the catalogue, the combinations, the save migration, the race, arena and online grids, and the garage.

## Rig contract

The garage, race and points arena pass the selected `Data.car()` definition to `CarVisual.setup`. Its `visual` dictionary selects the chassis independently of its saved ID, price, paint and driving statistics. Race contact uses the fixed clipped footprint in `sim/race.gd`. Arena contact uses the two circles in `sim/arena_car.gd`. Imported collision objects are rejected before scene attachment.

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
  Caliper_FL, Caliper_FR, Caliper_RL, Caliper_RR   (optional)
```

`Body` is the painted MeshInstance3D used for livery bounds. Keep painted surfaces in its local coordinates. Each wheel can be a mesh or a Node3D pivot containing meshes. Put its origin on the axle and orient its geometry at rest. Steering acts around chassis Y and rolling around chassis X. Lamps can contain multiple lens meshes. Place the nitro markers at the exhaust outlets with local +Z pointing along the exhaust plume. Optional `Caliper_*` nodes sit on their wheel's axle. They steer with the front wheels and never spin, which keeps brake calipers out of the spinning wheel meshes.

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
| `driver_offset` | Optional move of the driver figure in car space, for low cabins. |

Create a profile alongside the existing profiles in `vehicle_rig.gd` and reference it from the car data. The loader reports the model path and missing parts, wheel pivots, sockets and material roles. It tries the base rig if a preset model fails validation, then the public GT. The legacy GT adapter also handles the optional encrypted sport payload staged by the existing private-car tools. Other profiles keep their own bodywork in a private build.

## Provenance and mobile import

| Model | Provenance and commercial use |
| --- | --- |
| Vortex GT | Existing adaptation of **Car Concept** by Darmstadt Graphics Group GmbH and Eric Chadwick, licensed CC BY 4.0. Attribution and modifications are recorded in the in-game credits. |
| Vortex Gepard | Adaptation of **Generic Supercar "Cheetah"** by mk2design (https://sketchfab.com/3d-models/f5420af7b30c4e8c874be33cc58724f2), licensed CC BY 4.0. `tools/import_cheetah.py` regroups it into the rig, renames its materials to the runtime roles, drops the baked shadow and paints out the plate's EU band. Attribution and modifications are recorded in the in-game credits. |
| Hatch and Estate | Original first-party procedural vehicle assets created for commercial distribution with VORTEX. The dimensions, profiles, lamps, cabin, rails and wheel layouts are defined in `tools/build_original_cars.py`, using the project's original loft and wheel builders in `tools/gen_cars.py`. All geometry is generated locally without a third-party mesh, logo, scan or texture. |

Rebuild the Gepard from the downloaded source GLB (a Sketchfab account is needed; the script checks the pinned SHA-256) with `python3 tools/import_cheetah.py source.glb godot/assets/cars`. It needs only numpy and Pillow. The vertices keep the source's scale, so the tyres stay at the 0.38 m radius that `car_tyre.gdshader` and `car_rim.gdshader` read, and `visual_scale` 0.78 fits the car to the footprint. Its detail atlas ships as `cheetah_atlas*.png` next to the GLB, imported VRAM-compressed with mipmaps. The car has 29,200 triangles.

Rebuild the two original GLBs with `python tools/build_original_cars.py`. Each shares a single wheel mesh across four wheel instances, merges disconnected parts by material, and ships without embedded textures. Both use Godot's generated mesh LODs and shadow meshes. The shared livery atlas uses mipmaps and VRAM compression, including ETC2 on Mobile. Record the author, source, commercial rights and required attribution before adding another model. Private payloads and keys stay in the existing ignored staging directory.

After importing a new chassis, run the catalog and binding checks with Godot 4.4.1.

```sh
godot --headless --path godot --import
godot --headless --path godot res://tests/vehicle_rigs.tscn
```
