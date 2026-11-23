# Driving VFX on Godot Mobile

The captures use the Vlorë race scene, the Mobile renderer in Godot 4.4.1 and a software Vulkan device. The camera follows the player at 22 m/s. The capture scene supplies repeatable drift, boost and wall-contact inputs. Each timestamp is elapsed simulation time.

**Normal speed** · [Frames 10, 14 and 18](normal.webp)

**Quarter speed** · [Frames 10, 14 and 18](slow.webp)

**Tyre slip and wall contact** · [Frames 36, 40 and 44](contact.webp)

## Budgets

| Preset | Boost | Nearby cars with driving particles | Severe contact debris |
| --- | --- | ---: | --- |
| Low | Two socket flames, one shared mesh surface per outlet | 0 | Off |
| Medium | Flames, outlet glows, ribbons and four ignition particles per selected car | 2 | Off |
| High | Same exhaust components | 3 | Three chips for the player |

Each selected car can emit seven smoke particles per rear tyre on dry pavement, or five spray particles per rear tyre on wet pavement. A wall strike emits five sparks. Ignition and contact bursts fire once per activation. Each ribbon pair uses one MultiMesh draw and at most ten quads. Samples stop at three metres. The shared driving pools provide 99 transparent particle slots and three opaque debris slots across the whole scene, including overlapping tails. The existing pressure governor reduces the nearby-car allowance. These figures describe effect capacity. Device frame times depend on the handset.

## Reproduce the captures

From the repository root, run each command with Godot 4.4.1. The full-resolution PNGs land in `user://shots/driving-vfx/`.

```sh
godot --path godot --rendering-method mobile --fixed-fps 60 --audio-driver Dummy res://tests/driving_vfx_capture.tscn -- --seed=31
godot --path godot --rendering-method mobile --fixed-fps 60 --audio-driver Dummy res://tests/driving_vfx_capture.tscn -- --seed=31 --slow
godot --path godot --rendering-method mobile --fixed-fps 60 --audio-driver Dummy res://tests/driving_vfx_capture.tscn -- --seed=31 --contact
```
