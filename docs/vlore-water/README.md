# Bay of Vlorë water

Godot 4.4.1 Mobile, Vulkan llvmpipe. Counts are visible primitives and draw calls for the whole viewport. The High comparison uses the same camera with the Sea node and its horizon child hidden. Handset GPU time and thermal performance were not measured.

| View | Preset | Primitives | Draw calls |
|---|---|---:|---:|
| Day bay | Low | 358,362 | 72 |
| Day bay | Medium | 388,392 | 72 |
| Day bay | High | 390,446 | 72 |
| Day bay, water and horizon hidden | High | 388,366 | 70 |
| Sunset bay | High | 390,446 | 72 |
| Day chase, 42 m/s | High | 470,490 | 161 |

The signed shoreline distance approximates water depth over the shelf. The existing sun, sky, probes and distance fog light the opaque surface and horizon. Low uses long swells, Medium adds warped crossing ripples and High adds fine glitter and vertex displacement on a 128 m grid. The displaced surface flattens toward its boundary and shares one draw with the surrounding water. The horizon profiles approximate the angular relief of Sazan and Karaburun.

[Daylight](day_high_bay.webp) · [Sunset](sunset_high_bay.webp) · [Moving chase camera](day_high_bay_race.webp)

Use the existing render_compare scene with the Mobile renderer, a writable SHOTS directory and arguments `-- --city=vlore --env=day --qualities=high --views=bay,bay_race`. Change the environment to sunset for the evening view.
