# Tirana boulevard showcase

The showcase follows the first 450 m of the forward Tirana lap. Reverse races
use the same physical stretch and crossings. The new visuals sit on the
existing lap, mapped building footprints, terrain and race boundaries.
Facade relief, road treatments, upgraded lamp geometry and street furniture
are concentrated here. The sky grade and pooled tree improvements apply to
Tirana as a whole so the lighting and vegetation read continuously around the
lap.

| Area | What ships |
| --- | --- |
| Buildings | The city pipeline selects street-facing elevations 11.9–49 m from the centreline. Ten frontages get layered plaster, limestone bases, recessed glass, mullions, sills, shop awnings and selected projecting balconies. Two opaque batches have 6,156 triangles combined and preset-dependent draw distances. The existing city mesh supplies the background and directional shadow casters. |
| Road | Mipmapped aggregate drives subtle patch edges and paint wear. Three crossings at 86, 273 and 391 m break the white lane paint. Neutral kerbs, concrete barriers and a batched paved sidewalk tie the road to the shoulder. Wet asphalt retains textured wheel paths and uses roughness variation and sky radiance. |
| Lighting | Day, sunset, night and rain have separate exposure, fill, shadow and haze settings. Sunset reuses a panorama already shipped on Android. Mobile High in Tirana uses two shadow cascades over 155 m and a 2048 atlas. The existing night light pool supplies warm spill under the lamp heads. Rain streaks use a shorter exposure and ground splashes stay inside the local road width. |
| Street detail | Window-height views gain timber benches, crossing signs and tapered lamp heads. Near trees use clustered leaf cards in the existing MultiMesh pools, with 12/22/32 detailed trees on Low/Medium/High. The Clock Tower gains ashlar, a roof, clock faces and an open gallery. Plaza Tower uses inset, varied glazing. |

Regenerate the facade overlay from the shipped city assets with
`python3 tools/pipeline/showcase_facades.py`. The full Tirana build calls the
same baker. The overlay uses the existing plaster map and adds no facade
textures. The overlay is built separately from the mapped city mesh.

## Capture and measurement

The capture scene builds the production Tirana world without a race or HUD.
All four conditions use the same camera at 300 m. After 24 warm-up frames,
the scene saves a PNG under `user://shots` and records a moving camera from
20 to 400 m. Daylight and rain use 90 measurement frames. Sunset and night
use 30 and activate six pooled street lights for each captured frame. The `SHOWCASE` report gives wall-clock FPS, p95
frame time and average submitted draw calls and primitives. These counts
include render passes and depend on the view. The timed sample represents
the terrain, road, buildings, props, rain and lamps from a standalone camera.
The device workflow below measures the full race workload.

```sh
godot --headless --editor --import --path godot
godot --path godot --rendering-method mobile --rendering-driver vulkan \
  --audio-driver Dummy --disable-vsync res://tests/tirana_showcase_visual.tscn \
  -- env=day quality=high tag=after
```

Use `sunset`, `night` and `rainy` for the remaining lighting conditions.
Pass `samples=30` for the sunset and night measurements.
Use a fullscreen 1364 × 1024 display to match these captures. The baseline is
`914bdba` with the capture scene added.

Measured on Linux with Godot 4.4.1, Mobile High, Vulkan llvmpipe (LLVM
19.1.7) and a two-CPU container quota. The screenshots are 1364 × 1024.
Each row reads before → after.

| Condition | Captures | Mean FPS | p95 frame ms | Draw calls/frame | Primitives/frame |
| --- | --- | ---: | ---: | ---: | ---: |
| Daylight | [Before](tirana-showcase-captures/before-day.webp) · [After](tirana-showcase-captures/after-day.webp) | 1.08 → 1.13 | 1,088 → 1,030 | 218.9 → 220.1 | 438,068 → 428,002 |
| Sunset | [Before](tirana-showcase-captures/before-sunset.webp) · [After](tirana-showcase-captures/after-sunset.webp) | 0.67 → 0.88 | 2,156 → 1,534 | 230.8 → 228.3 | 452,371 → 436,803 |
| Night | [Before](tirana-showcase-captures/before-night.webp) · [After](tirana-showcase-captures/after-night.webp) | 0.86 → 0.99 | 2,031 → 1,132 | 218.7 → 220.9 | 444,628 → 431,949 |
| Rain | [Before](tirana-showcase-captures/before-rainy.webp) · [After](tirana-showcase-captures/after-rainy.webp) | 1.17 → 1.13 | 931 → 996 | 219.3 → 221.5 | 453,929 → 444,986 |

These wall-clock measurements describe CPU software rendering. Daylight,
sunset, night and rain each rendered on the Mobile path. Use the draw and
primitive counts to track scene submission changes and measure the 60 FPS
target on the devices below.

## Automated verification

- Godot 4.4.1 passed all 45 launches in `tools/run_tests.py`. These include
  the six production city worlds, road geometry, route readability, rendering
  budgets and weather transitions on Mobile and Forward+.
- All 23 city-pipeline tests and three Android export-tool unit tests passed.
  A repeat facade bake matched the checked-in GLB byte for byte.
- A focused headless check verified that all three crossing positions align
  in reverse, Vlorë omits the Tirana pavement, and Low and High set the
  expected facade visibility ranges. Rain also rendered on Mobile Low and
  Medium in additional visual smoke runs.

## Physical Android validation

The 60 FPS target remains unverified on Android. Install a profile build
using the [README device workflow](../README.md#profiling-on-the-target-phones).
For fixed conditions, set `--city=tirane --env=<preset> --seed=7` in the
local profile export launch arguments. Run sustained laps on the A56
(Medium), S25 FE (Medium) and S25 Ultra (High), then cover Low on the A56.
Record mean and p95 frame times, GPU render time, dropped frames, memory and thermal
behaviour over several laps. Include populated races with mirror on and
off, night lamp and headlight overlap, rain and the day-to-rain transition.
Check paint and chevron visibility at speed from both directions, along
with shadow transitions and foliage distance changes on the phone display.

## Vlorë Lungomare follow-up

Vlorë already has a paved median, promenade, palm batches, coastal tunnel
and a shoreline-distance water mask. Keep the route and work in one
350 m stretch from roughly 1.85 to 2.20 km along the current forward lap,
just past the Lungomare gateway, after the Tirana device pass.

1. Adapt the road wear, gutter wetness and sidewalk profiles to the coast.
   Match the existing median and mapped pedestrian access to the promenade,
   and carry the wetness update into its paving material.
2. Use the facade baker on the street- and sea-facing apartment blocks.
   Select pale stucco and stone, deep terraces, shutters and balcony
   rails. Reuse the recessed glass technique and retain the baked footprints.
3. Keep palms batched by location. Add a small near-player crown and trunk
   tier with varied crowns, and use low-poly silhouettes for the rest.
4. Grade the existing sea with the shoreline mask. Add restrained sunset
   glints, varied foamy shallows and stronger distance filtering while
   retaining the opaque single-plane Mobile implementation.
