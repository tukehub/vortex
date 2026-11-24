# Vlorë coastal chase profile

Godot 4.4.1 Mobile on Vulkan llvmpipe (LLVM 19.1.7). Each preset started in a fresh process with seed 31, daylight, the same road position and a 42 m/s chase-camera approach. The capture holds the final pose, with the HUD hidden. Captures are 1364 × 1024. Frame times are eight-frame means following warm-up, with screenshot readback excluded.

| Preset | 3D scale | Draws | Objects | Primitives | Frame ms | Process ms | Render CPU ms | Vulkan ms | Video MiB | Texture MiB | Emitting slots | Shadow m |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Low | 0.70 | 135 | 135 | 419,702 | 304.7 | 328.4 | 0.77 | 297.9 | 174.9 | 96.1 | 0 | 70 |
| Medium | 0.90 | 145 | 145 | 462,084 | 546.5 | 557.1 | 0.88 | 525.0 | 240.4 | 157.0 | 0 | 80 |
| High | 1.00 | 150 | 150 | 478,394 | 825.3 | 812.8 | 0.81 | 795.9 | 245.0 | 161.1 | 0 | 155 |

Draws, objects and primitives are the main viewport’s visible-pass counters. Godot reports primitives without a separate triangle counter. Process time is Godot’s main-loop monitor and can include rendering waits. Render CPU is the viewport submission time. Vulkan timestamps here measure software rendering. These timings overlap. Video memory includes texture memory. Emitting slots sum the configured capacities of visible, emitting 3D particle systems. Godot does not expose an exact GPU live-particle count. These dry, boost-free frames exercise steady-state scenery.

[Low](low.webp) · [Medium](medium.webp) · [High](high.webp)

All three frames keep the hillside continuous behind the left-hand buildings and the black chevrons readable along the right barrier. At Low, distant lane markings and roof edges look softer and the car casts a lighter contact shadow. Medium resolves the sign borders and the road surface more clearly. High adds shadow reach and finer shoreline and hillside detail. Medium to High adds five visible draws and 16,310 primitives at this camera.

The terrain uses one mesh per chunk with a coarse index buffer that keeps every boundary vertex. The renderer selects detail on screen and each preset adjusts the selection bias. The distant shoreline uses one coarse rock batch per occupied cell. The close batches retain four stone shapes. The shared sign and concrete textures use ETC2 on Mobile with mipmaps and anisotropic filtering. The sun uses conventional directional shadows and the bay uses the existing sky and reflection probes.

To reproduce, run once per preset with an existing writable SHOTS directory and substitute low, medium or high for PRESET.

```sh
SHOTS=/tmp/shots godot --path godot --rendering-method mobile --fixed-fps 60 --audio-driver Dummy res://tests/render_compare.tscn -- --seed=31 --city=vlore --env=day --qualities=PRESET --views=bay_race --profile-frame
```

The Android target is 60 fps (16.67 ms total). Sustained frame time and thermal behaviour on a physical device remain unmeasured.
