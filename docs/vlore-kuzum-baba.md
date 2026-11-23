# Vlorë: Kuzum Baba and the start/finish line

![Kuzum Baba temple and tomb, the new start/finish and the grid](images/vlore-kuzum-baba.webp)

## Kuzum Baba

The Bektashi hill above the boulevard (Kodra e Kuzum Babait, 88 m), built
as procedural interpretations after photographs at the OSM positions
(`scripts/world/kuzum_baba.gd`, one draw call each):

- **Temple** (`kuzum_baba_tekke`, OSM way 1222923149, 22 × 27.5 m, turned
  7.8°): a yellow two-storey hall with arched windows in white surrounds and
  a green cornice, between two 13 m green towers with dark pyramid roofs; a
  green-roofed pergola and an Albanian flag at the entrance; in front, a
  crazy-paved retaining wall under a white balustrade, following the slope;
  cypresses on the summit. Its facade faces west, down the hill.
- **Tomb** (`kuzum_baba_turbe`, OSM node 6436869917): grey coursed stone with
  crenellations and an arched opening on each face, under a drum, a green
  dome, a lantern and a finial, on a stone terrace stepped into the brow.

The mapped temple block is taken out of `buildings.glb` (it would sit inside
the model) and the trees inside both keepouts are cleared, as a full rebuild
does through `landmark_buildings` and `clear_half` in `cities.py`.

Where the race sees it: the tomb on the brow is abreast of the road 60 m
after the line; the temple, behind the brow from the boulevard below, shows
on the return pass east of the hill (≈ 8.6 km) and its towers above the
rooftops further out.

## Start/finish

Before: Sheshi i Flamurit, inside the square's turn (tightest radius ≈ 28 m
within 40 m of the line). Now: on the straight Bulevardi Ismail Qemali,
**102 m before** the road passes the Kuzum Baba park, with no bend tighter
than 212 m over the grid behind the line and the run past it. The lap now
opens past Petro Marko and closes through the old town, the town hall,
Sheshi i Flamurit, the Vlora house and the Muradie Mosque.

`tools/pipeline/finish_line.py` rotates the closed lap so it starts the asked
distance before the point of the circuit nearest a landmark, and refuses a
spot where any 12 m of the grid or run-out bends tighter than 150 m:

```sh
python3 tools/pipeline/finish_line.py vlore       # cities.py: 'finish_before'
python3 tools/pipeline/landmark_anchors.py vlore  # add new landmarks + keepouts
python3 tools/pipeline/glb_cut.py vlore 1222923149
```

All three only touch the processed data they name (track.json order,
props.json rows, the temple's index triangles in buildings.glb) and are
idempotent; `build_city.py` applies the same placement on a full rebuild.
Everything else in the city (tunnel, old-town paving, median, turnaround,
crossings, furniture) is located by world position, so it is unaffected.

Tests: `tests/vlore_kuzum_baba` (line on a straight in both directions,
100 ± 12 m before the park, landmarks built and facing west, no building
inside the temple, no trees in the keepouts), `tools/pipeline/test_finish_line.py`,
and `tests/city_worlds` with the new lap order.
