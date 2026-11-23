# Section 3 graphics progress

Working branch: `codex/section-3-graphics`. Base: `1314c9a`.

## Checkpoint: work started (2026-11-16)

Read the README and current renderer/visual tests; section 3 was pending at
the start. Implement items in README order, keeping simulation code node-free
and deterministic. Commit and push each tested checkpoint to this branch.
Current status:

- **3.1 — implemented and tested:** masked clearcoat/metallic flakes and
  budgeted bot headlights, preserving player headlights and emissive lamps.
- **3.2 — implemented and tested:** pooled GPU driving particles and a
  quality-aware speed post effect, with regression coverage for state changes
  and bounded allocation.
- **3.3–3.8 — pending:** reflections, OSM dressing, road decals, facade depth,
  baked lighting/culling, and colour grading.

Validation: `godot --headless --path godot --editor --import`, then
`python3 tools/run_tests.py --godot godot`. Rendered checks should exercise
Mobile and Forward+ where Vulkan is available. Physical phone frame-time
claims remain blocked on measurements from the actual devices.

Resume by reading this file, `README.md` section 3, and `git log`/`git status`.
Do not merge to `main`; the user requested a separate branch.

## Checkpoint: 3.1 (2026-11-16)

- Atlas paint now uses metallic 0.6 / roughness 0.25, masked clearcoat and
  procedural flake normals that fade below a pixel. The public GLB's separate
  paint surfaces get the same finish and a shared procedural normal texture.
- Damage dulls the finish; repair restores it. Flakes disable on low or under
  sustained pressure through `Quality.p.paint_flakes`.
- All six cars have emissive lamps. The nearest eligible bots share at most
  `Quality.p.fx_light_limit` spots, within 70 m. Two player spots are reserved;
  total spots stay below Mobile's eight-per-mesh ceiling. Existing omni-light
  shares are unchanged. Lights are allocated once and reassigned in place.
- **Passed:** complete `tools/run_tests.py` suite on Godot 4.4.1, including the
  new `car_paint_lights` scene on Mobile and Forward+. The Mobile software
  Vulkan car-close render also passed and was visually inspected; phone
  profiling remains pending.
- Environment: `godot` on PATH is 4.6.3, so use
  `/workspace/godot441/Godot_v4.4.1-stable_linux.x86_64`. Scratch wrapper
  `work/godot` sets writable `XDG_CONFIG_HOME`, `XDG_DATA_HOME` and
  `XDG_CACHE_HOME` under `work/`. This is untracked machine-local setup.

## Checkpoint: 3.2 implementation (2026-11-16)

- `FxVisual.POOL_CAPS` now also bounds 6 smoke, 3 exhaust, 6 spray and 3 scrape
  GPU emitters (438 particles maximum). `driving_particles.gd` builds them
  once, using shared meshes/process materials. No runtime emitter creation.
- Medium draws effects on up to two nearby cars; high on three, with the
  player first. Low and pressure stages 2/3 disable them. World-space trails
  follow rendered rear-wheel/exhaust/side positions; wet roads replace smoke
  with spray. Stopping, jumping, wrecking, distance, teleport/reuse and finish
  are handled without changing simulation state or its RNG.
- A peripheral radial blur, vignette and slight chromatic offset use speed
  ratio and nitro. The screen-texture pass sits below HUD, controls and the
  mirror, ignores input, and disables on low/pressure, pause, wreck and finish.
  Retry creates a fresh inactive pass.
- **Passed so far:** dedicated Mobile `speed_feedback` regression and the
  existing combined visual-performance stress test. Full runner and rendered
  Mobile/Forward+ checks are running; inspect their results before marking
  this checkpoint fully validated.
- Render check: `godot --path godot --rendering-method mobile --fixed-fps 60
  res://tests/graphics_visual.tscn` (repeat with `forward_plus`). It exercises
  production race/HUD integration, the atlas paint shader, drift, wet boost
  and low quality, and writes screenshots to `user://shots/`.
- On this machine the test display is Xorg `:97`; software Vulkan uses
  `VK_ICD_FILENAMES=/workspace/setup/lavapipe.json`. Scratch logs are in
  `work/section-3.2-tests.log`, `work/graphics-mobile.log`, and
  `work/graphics-forward.log`.

## Validation and handoff (2026-11-16)

- The full Godot 4.4.1 runner passed: **26 scene launches**, including all
  existing simulations, city/race flow, controls, string-table and performance
  checks; paint/lights, speed feedback, renderer truth and profile launches
  run on both Mobile and Forward+. No unexpected runtime errors.
- Both software Vulkan render paths completed drift, wet-boost and low
  captures. Paint/atlas shaders compile, particles appear, and UI stays sharp.
  Low reports zero driving emitters and zero post strength. Final repeats
  also check the shader's low-quality branch (flake calculations are skipped).
- Fixed the optional visual harness to resume after window focus loss; the
  production game's focus-loss pause remains intact. Render logs from the
  final shader check use `work/graphics-{mobile,forward}-final.log`.
- The initial plan, tested 3.1 and implemented 3.2 were pushed separately
  (`b544d46`, `c087cc0`, `aa2f42e`). A final validation/docs checkpoint follows.
- **Next: 3.3 reflections.** `Quality.p.probe` already exists, but race probes
  are not implemented. Start with a probe that follows the player, landmark
  probes on high, HDRI/probe garage and ambient-floor adjustment. Read
  `sky_env.gd`, `menu.gd`, `race_scene.gd` and the renderer-budget tests first.
  Items 3.3–3.8 remain pending; no phone performance claim or release was made.

## Checkpoint: 3.3 reflections (2026-11-22)

- `scripts/world/reflections.gd` (`RaceReflections`): one `UPDATE_ONCE`
  follow probe on medium/high that jumps half a `Quality.p.probe_step`
  (45 m medium, 30 m high) ahead of the player, so it re-renders one cube
  face a frame only after a jump; up to six static box-projected landmark
  probes on unpressured high. `Quality.REFLECTION_PROBES_PER_MESH` (8)
  bounds both. Pressure stage 2 drops landmark probes, stage 3 the follow
  probe. Budget changes toggle the same probes; restart keeps them.
- Cars live on `PLAYER_LAYER` / `CAR_LAYER`, outside `PROBE_MASK`; the race
  camera and the mirror still draw them.
- `SkyEnv.ambient_energy`: with a probe the flat fill is 85% of the preset,
  floors 0.36 day / 0.42 night; low keeps 0.45 / 0.48.
- Garage: dusk HDRI (energy 0.4), box-projected probe (90×14×90, blend 30)
  that skips the turning car, glossy non-metallic floor out to the horizon,
  aerial-perspective fog, SSR when Forward+ draws it.
- **Passed:** `tests/reflections` on Mobile and Forward+ (headless) and the
  full runner. Rendered on lavapipe (Mobile and Forward+): garage seam-free
  after widening the probe; race frames show no probe artefacts. Phone cost
  of the follow probe is unmeasured.
- **Next: 3.4 street dressing from OSM.**

## Checkpoint: 3.4 street dressing (2026-11-22)

- `tools/pipeline/street_props.py` adds props.json "street" (x, z, yaw per
  item) from OSM nodes within 250 m of the circuit: traffic lights to the
  right-hand kerb, bus stops at the kerb facing the road, benches/bins off
  the carriageway, bollards as mapped. Off the race road, buildings,
  landmark keepouts and water. 700 m tiles; Overpass first, the main OSM
  API for a tile it will not serve (`--api` for every tile).
- Tirana: 48 lights, 30 stops, 333 benches, 48 bins, 9 bollards. Vlorë:
  18 stops, 2 benches (that is all OSM maps there). Other props.json keys
  are unchanged.
- `StreetProps` (built by `Props`): procedural vertex-coloured meshes under
  500 triangles, one MultiMesh per kind per 250 m chunk, visibility ranges
  capped by `props_dist`, no shadows; `Quality.p.street_small` drops benches,
  bins and bollards on low and at pressure stage 2+.
- **Passed:** `tests/street_props` on Mobile and Forward+,
  `test_street_props.py`, the full runner. Rendered on lavapipe: shelters,
  benches and signal masts sit on the pavement at Tirana junctions.
- Parked-car slots skipped: only the six racers are on the street (2.3).
- **Next: 3.5 road decals.**

## Checkpoint: inferred furniture and 3.5 road decals (2026-11-22)

- `tools/pipeline/street_infer.py` fills gaps OSM leaves (flagged rows,
  `[x, z, yaw, 1]`): signals at major junctions, footway benches, bins by
  shelters/benches, pedestrian-entry bollards, and crossings before
  signalised junctions when none is mapped. Tirana data refetched through
  the main OSM API so crossing nodes keep their tags.
- Road shader: zebra crossings with stop lines and broken lane lines;
  cast-iron manholes, gullies and patches from a sin-free hash mirrored by
  `RoadMesh.hardware_near()`. Rendered on lavapipe and tuned: covers and
  patches were first too pale (sRGB asphalt is ~0.1 linear, and glossy
  patches mirrored the sky); gullies moved inboard of the edge line.
- Signal model raised (6.1 m pole, 4.6 m mast arm, head 4.8 m clear) and
  its lamp/glass surfaces made cull-free (the green lens was culled).
- **Passed:** `tests/road_marks`, `tests/street_props` (both renderers),
  pipeline unit tests, full runner.
- **Next: 3.6 facade depth.**

## Checkpoint: supplied traffic-light model (2026-11-23)

- Source: "Traffic Light - Complex" FBX from Urban Mini Props Pack - Free,
  supplied by the project owner; kept untracked in `raw_assets/` (the repo
  ignores third-party FBX). Its two referenced Concrete030 textures were not
  supplied and are not needed.
- `tools/build_traffic_light.gd`: FBXDocument at runtime, quarter turn
  (x, y, z) -> (z, y, -x), ground at the pole foot, vertex colours, lenses
  split by height (green lit), every part rewound (its normals point
  inward; checked with a cull-off render), weld by position+colour so
  Godot's LOD generator can simplify (44 512 -> 5 236 + 344 lit), crease
  normals at 40 degrees.
- `StreetProps`: per-pole near/far MeshInstance3D pair, switch at 130 m;
  the procedural far model now matches the outline. Shadows on high.
- **Licence of the pack not confirmed in the file**; credited in
  CREDITS.txt by name. Confirm before a store release.

## Checkpoint: Android graphics pass (2026-11-23)

Medium at 0.9 scale with MSAA 2x and mip bias -0.35 (Mobile has no FSR),
filtered road lines, one-fetch crossing lookup, the player's sun shadow on
medium, sky-tinted daylight fill, glow skipped where invisible, incremental
sky refresh during weather changes. Measurements, rejected options (AgX,
extra contrast/saturation, all-car shadows) and what still needs the phones:
[android-graphics.md](android-graphics.md).
