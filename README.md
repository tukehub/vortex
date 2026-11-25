# Vortex

Vortex is an Android arcade combat racer set on real Albanian streets. Drift through Tirana, race along the Vlorë waterfront, loop central Shkodër, race past Korçë's cathedral, or battle for points around either city’s central monument. The native game uses Godot 4.4.1 and GDScript, with the Mobile renderer on phones and Forward+ on desktop.

[Download the Android APK](https://github.com/tukehub/rruga-e-kombit/releases/latest/download/rruga-e-kombit.apk)

## Play

- **Tirana Cup.** Learn the controls in the tutorial, then earn stars from race finishes and event goals. Four stars unlock Vlorë, seven unlock Shkodër and ten unlock Korçë. Race fans buy cosmetic paints, rims and liveries for the Vortex GT.
- **Vlorë.** A 9.5 km out-and-back on one wide road: the two one-way carriageways run side by side with nothing between them, and a rounded 10 cm median you can drive over runs down Lungomare. It starts on the straight Bulevardi Ismail Qemali, 100 m before the Kuzum Baba hill (its Bektashi temple on the summit, the green-domed tomb on the brow), runs past Flamurtari stadium, round the Sheshi Pavarsia island and down Lungomare past the rock-armoured shore by the sports courts, through the Uji i Ftohtë tunnel and back up Dhimitër Konomi. It merges into Lungomare again and returns the same way, round Sheshi Pavarsia’s other side, to the turning island at Sheshi i Flamurit. [The out-and-back road and the sea](docs/vlore-out-and-back.md) · [Kuzum Baba and the line](docs/vlore-kuzum-baba.md)
- **Shkodër.** A 7.7 km loop from the centre round Rozafa's hill, on Tirana's road, facades and street trees. It starts on Rruga Teuta, 100 m before Sheshi Demokracia and Teatri Migjeni, runs south-west down Rruga Studenti, Bulevardi Zogu I, Rruga Mbreti Gent and Rruga Pazarit to the roundabout at the castle's foot by the Buna bridge, along Rruga Bexhene under the south walls beside the Drin, over the castle saddle and up Rruga 9 Nuset and Rruga e Terzive, then east along Bulevardi Mehmet Pashë Plaku to Sheshi Perash and back north up Rruga Edith Durham, Bulevardi Skënderbeu and Rruga Teuta past the Ebu Bekr mosque.
- **Korçë.** A 3.1 km loop through the centre. It starts on Bulevardi Republika, 100 m before the cathedral square, and runs past Mësonjëtorja, the first Albanian school (1887), and the Resurrection Cathedral with its twin bell towers and tiled domes. It rounds the roundabout onto Bulevardi Fan Noli, runs north-west past the Old Bazaar, along Rruga Edit Durham and Sheshi i Teatrit by the Çajupi theatre, up Rruga Midhi Kostani, briefly along Rruga Teli Samsuri, then back by Rruga 1 Maji and Rruga Raqi Qirinxhi to Republika. [The cathedral, Mësonjëtorja and the loop](docs/korce.md)
- **Points mode.** Choose **Mënyra → Pikë**, then pick Tirana’s Skanderbeg Square or Vlorë’s Sheshi i Flamurit. Score with rams and weapons in a two- or three-minute round. [See the Independence Monument in the Vlorë arena](docs/images/vlore-pike.webp)
- **Same-Wi-Fi multiplayer.** One player hosts from **Online** and shares the displayed IP address. Friends join directly, and the host can fill the remaining grid slots with bots. Tap a stored item to select it or tap the active slot to cycle. Selection and firing use the same synchronized input stream on every phone.

Choose touch or tilt steering in **Cilësimet**. **GJUAJ** fires forward and **PRAPA** fires backward. [Mobile controls](docs/mobile-controls.md) · [Combat and recovery](docs/combat-recovery.md)

## Develop and test

Open `godot/project.godot` in Godot 4.4.1, or run from the repository root.

```sh
godot --headless --path godot --editor --import
python3 tools/run_tests.py --godot godot
godot --path godot
```

The suite covers the race and arena simulations, city loading, controls, UI, render settings and LAN play. Run the two-peer LAN regression or render the Vlorë landmark views individually with these commands.

```sh
godot --headless --path godot res://tests/online_flow.tscn
godot --path godot --rendering-method mobile res://tests/vlore_landmarks_visual.tscn
SHOTS=$PWD godot --path godot --rendering-method mobile res://tests/korce_landmarks_visual.tscn
```

Keep simulation code in `godot/scripts/sim/` deterministic and node-free. Drive visuals from simulation events, use `Quality.p` for render budgets, and add player-facing strings to `strings_sq.gd`. Include regression coverage in `godot/tests/` and migrations for saved-data changes.

## Android APK

Install JDK 17, Android SDK platform 34, platform-tools, build-tools 34.0.0 and the matching Godot export templates, including `android_source.zip`. Set `JAVA_HOME` and `ANDROID_HOME`. Choose a version code higher than the installed build.

```sh
python3 tools/export_android.py --godot godot --version-code 123
adb install -r rruga-e-kombit.apk
```

Every 3D texture ships VRAM-compressed with mipmaps; `tools/run_tests.py` fails if one is imported lossless or without mipmaps (`python3 tools/texture_budget.py --fix` repairs the `.import` files). [Heat and package size](docs/visual-performance.md#heat-and-package-size)

Updates use package `al.tukehub.rruga` and the existing signing key at `android/app/rruga.jks`. On pushes to `main`, GitHub Actions tests the native project, signs and verifies the APK, and publishes the release. The older Capacitor project is retained as a reference. [Build workflow](.github/workflows/apk.yml)

## Profiling on the target phones

The [Tirana boulevard showcase](docs/tirana-showcase.md) includes paired Mobile-renderer captures, measurements and the Lungomare follow-up. The [Tirana vegetation report](docs/tirana-trees.md) covers the three tree LODs and their render cost.

Build a benchmark APK with `--profile-seconds 60 --quality medium` and read its `PROFILE:` output with `adb logcat -s godot`. Measure the Galaxy A56 and S25 FE at Medium and the S25 Ultra at High with rain and combat active. The A56 Medium target is a p95 frame time under 16 ms. Physical-device results are pending. [Visual performance](docs/visual-performance.md)

## City data and credits

The APK includes Tirana, Vlorë, Shkodër and Korçë. The repository also carries datasets for Berat, Gjirokastër and Tetovë. Rebuild an individual city from OpenStreetMap streets, street furniture and Copernicus elevation with network access.

```sh
python3 -m pip install -r tools/pipeline/requirements.txt
python3 tools/pipeline/build_all.py vlore
python3 -m unittest discover -s tools/pipeline
```

Raw downloads go to `tools/cache/` and processed cities to `godot/assets/cities/`. The GT uses *Car Concept* © 2024 Darmstadt Graphics Group GmbH and Eric Chadwick (CC BY 4.0). [Asset credits](godot/assets/CREDITS.txt) · [Architecture and licensing](docs/PLAN.md)

## Changes to be made

### Fix next

- [ ] Restore touch controls after a LAN race resumes. Close the session on Quit and verify that the next solo race starts offline.
- [ ] Clear cup settings when entering free-race setup so the displayed lap count matches the race.
- [ ] Make Vlorë’s sunset selectable, include its sky in the Android build, and align the sun with the bay.
- [ ] Group streetlamps by neighborhood so nearby poles stay visible on Medium.
- [ ] Play a full three-minute Vlorë Pikë round on the target phones. Check frame times during six-car collisions and inspect the monument from the chase camera on Low and High.

### Build and playtest the Vlorë coastal sprint

- [ ] Create a 90–120 second Skelë–Uji i Ftohtë rival event that new players can try. Keep the full circuit for endurance races.
- [ ] Dress the waterfront with local shopfronts, balconies, paving and palm variants. Check landmark visibility from the chase camera in both directions.
- [ ] Give the tunnel distinct portal rock, warm reflected light and engine echo. Fade rain and spray under cover.
- [ ] Place a repair-versus-boost choice before the coastal straight. Have rivals choose lanes based on the item they need and the cost of reaching it.
- [ ] Playtest the current damage rule against gradual top-speed losses capped at 6% and 10%. Compare repair use and how often damaged drivers recover positions.
- [ ] Check touch assists through the Sheshi i Flamurit turn and the Dhimitër Konomi merge on both laps. Measure cold loading and sustained frame times on the target phones with six cars, rain and combat.

### Expand after the sprint

- [ ] Separate lap records by route version, direction and rules. Add personal ghosts, sector times and repeatable weekly challenges.
- [ ] Validate and package the remaining city circuits, starting with a distinct event and recognizable landmarks for each.
- [ ] Add race music, engine shifts and localized voice and text.
- [ ] Support reconnecting to a LAN race, then add relay rooms for friends on different networks.

[Graphics progress](docs/section-3-progress.md) · [Detailed milestone history](https://github.com/tukehub/vortex/blob/e0a93e4/README.md#changes-to-be-made)
