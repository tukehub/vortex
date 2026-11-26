extends Node
## Central game data: cities, cars, power-ups, drivers, difficulty.
## Everything race-balance related lives here or in sim/race.gd so a new car
## or city is a data change only. Text the player reads is not here: it lives
## in strings_sq.gd under keys built from these ids ("pw.eagle.name",
## "city.tirane.name", "env.day") and is read through t().

const GAME_NAME := "Vortex"
const Strings := preload("res://scripts/data/strings_sq.gd")

## The active language's table (plan 9.2 swaps it for another language).
var strings: Dictionary = Strings.T

# ---------------------------------------------------------------- environments
# Lighting/weather presets. sun_dir points *towards* the sun (Godot world space,
# x east, z south). Colours are sRGB hex. Fog in metres. Every city has a
# default env; the player can override weather/time in the race setup.
const ENV := {
	"night": {"icon": "☾", "sun_dir": Vector3(0.35, 0.55, -0.45), "sun_col": "#8ea6ff", "sun_i": 0.35,
		"sky_top": "#02030a", "sky_hor": "#1d1538", "ground": "#0a0810", "ambient": 0.35, "fog": "#120e22", "fog_density": 0.0028,
		"win": 1.0, "lamps": true, "stars": true, "moon": true, "exposure": 1.1, "bloom": 1.05, "wet": false, "rain": false, "snow": false},
	"dusk": {"icon": "◐", "sun_dir": Vector3(-0.75, 0.12, 0.4), "sun_col": "#ff9a6a", "sun_i": 1.2,
		"sky_top": "#121842", "sky_hor": "#e06c5a", "ground": "#2a1e22", "ambient": 0.45, "fog": "#4e3150", "fog_density": 0.0022,
		"win": 0.85, "lamps": true, "stars": true, "moon": false, "exposure": 1.05, "bloom": 0.9, "wet": false, "rain": false, "snow": false},
	"sunset": {"icon": "◒", "sun_dir": Vector3(0.8, 0.14, -0.3), "sun_col": "#ffb26e", "sun_i": 2.0,
		"sky_top": "#22336e", "sky_hor": "#ffaa62", "ground": "#3a2c26", "ambient": 0.5, "fog": "#c98a6a", "fog_density": 0.0016,
		"win": 0.5, "lamps": true, "stars": false, "moon": false, "exposure": 1.0, "bloom": 0.75, "wet": false, "rain": false, "snow": false},
	"day": {"icon": "☀", "sun_dir": Vector3(0.4, 0.85, 0.3), "sun_col": "#fff4dc", "sun_i": 2.6,
		"sky_top": "#3e7fd8", "sky_hor": "#c4e2f4", "ground": "#6c6a52", "ambient": 0.5, "fog": "#c6def0", "fog_density": 0.0010,
		"win": 0.0, "lamps": false, "stars": false, "moon": false, "exposure": 0.90, "bloom": 0.25, "wet": false, "rain": false, "snow": false},
	"golden": {"icon": "☀", "sun_dir": Vector3(-0.6, 0.33, 0.5), "sun_col": "#ffd6a0", "sun_i": 2.4,
		"sky_top": "#3a78c8", "sky_hor": "#f4d0a0", "ground": "#5c5240", "ambient": 0.55, "fog": "#dcc29a", "fog_density": 0.0012,
		"win": 0.1, "lamps": false, "stars": false, "moon": false, "exposure": 0.95, "bloom": 0.5, "wet": false, "rain": false, "snow": false},
	"rain": {"icon": "☂", "sun_dir": Vector3(0.3, 0.8, 0.2), "sun_col": "#9fb0c8", "sun_i": 0.3,
		"sky_top": "#07090f", "sky_hor": "#262e3c", "ground": "#101214", "ambient": 0.55, "fog": "#181d27", "fog_density": 0.0045,
		"win": 1.0, "lamps": true, "stars": false, "moon": false, "exposure": 1.15, "bloom": 1.05, "wet": true, "rain": true, "snow": false},
	"rainy": {"icon": "☂", "sun_dir": Vector3(0.3, 0.8, 0.2), "sun_col": "#cdd5df", "sun_i": 0.65,
		"sky_top": "#5a6472", "sky_hor": "#9aa3ad", "ground": "#3c4046", "ambient": 0.55, "fog": "#8e98a4", "fog_density": 0.0060,
		"win": 0.0, "lamps": false, "stars": false, "moon": false, "exposure": 0.85, "bloom": 0.15, "wet": true, "rain": true, "snow": false, "dark": false},
	"snow": {"icon": "❄", "sun_dir": Vector3(-0.5, 0.3, 0.6), "sun_col": "#ffd8b8", "sun_i": 0.9,
		"sky_top": "#161d33", "sky_hor": "#5e6584", "ground": "#4a4e5a", "ambient": 0.6, "fog": "#3e445c", "fog_density": 0.0040,
		"win": 0.95, "lamps": true, "stars": false, "moon": false, "exposure": 1.1, "bloom": 0.95, "wet": true, "rain": false, "snow": true},
}
const ENV_ORDER := ["night", "dusk", "sunset", "day", "golden", "rainy", "rain", "snow"]

# ---------------------------------------------------------------- cities
# Track geometry comes from assets/cities/<id>/ (built by tools/pipeline).
# horizon: "flat" | "mountains" | "sea" picks the HDRI family and far terrain treatment.
# stars: Tirana cup stars that open the city (Progress.city_open). A city whose
# track.json is not in this build (left out of the APK) is not offered at all.
const POINTS_CITIES := ["tirane", "vlore"]
const CITIES := [
	{"id": "tirane", "env": "day", "laps": 2, "neon": "#ff2d6f", "horizon": "flat", "hdri": "day", "stars": 0},
	{"id": "vlore", "env": "sunset", "laps": 1, "sprint": true, "neon": "#ffd23a", "horizon": "sea", "hdri": "sunset", "stars": 4},
	{"id": "shkoder", "env": "golden", "laps": 2, "neon": "#4ee0ff", "horizon": "mountains", "hdri": "golden", "stars": 7},
	{"id": "korce", "env": "day", "laps": 2, "neon": "#e8423f", "horizon": "mountains", "hdri": "day", "stars": 10},
	{"id": "berat", "env": "golden", "laps": 2, "neon": "#ffb347", "horizon": "mountains", "hdri": "golden", "stars": 12},
	{"id": "gjirokaster", "env": "rain", "laps": 2, "neon": "#3d9dff", "horizon": "mountains", "hdri": "rain", "stars": 14},
	{"id": "tetove", "env": "day", "laps": 2, "neon": "#ff5fc8", "horizon": "mountains", "hdri": "day", "stars": 16},
]

# ---------------------------------------------------------------- cars
# The cars: a chassis and how it drives. Every car is the player's from the
# start (garage tab "Makina"); paint, rims and livery fit every car.
# vmax: top speed (m/s); acc: acceleration (m/s², before the race's own
# multiplier); grip: cornering grip; hp: armour (health); mass: weight in
# contact (heavier pushes harder and is pushed less). Rivals drive them too.
# The contact footprint (size, wheel_r) is the same for every car, so a car
# changes how it drives, never how it fits on the road.
const MODEL_DEFAULT := "gt"
const MODELS := [
	{"id": "gt", "vmax": 58.0, "acc": 8.0, "grip": 1.05, "hp": 115.0, "mass": 1.1, "visual": VehicleRig.GT},
	{"id": "sprint", "vmax": 55.5, "acc": 9.0, "grip": 1.12, "hp": 100.0, "mass": 0.95, "visual": VehicleRig.HATCH},
	{"id": "kombi", "vmax": 56.5, "acc": 7.3, "grip": 0.99, "hp": 145.0, "mass": 1.35, "visual": VehicleRig.ESTATE},
	{"id": "gepard", "vmax": 61.0, "acc": 8.5, "grip": 1.1, "hp": 92.0, "mass": 1.0, "visual": VehicleRig.CHEETAH},
]
## The garage's stat bars, in order.
const MODEL_STATS := ["vmax", "acc", "grip", "hp", "mass"]
const CAR_SIZE := Vector3(1.94, 1.38, 4.62)
const CAR_WHEEL_R := 0.36

# Paints. `model` is the car a rival drives in this colour; the player's own
# car is chosen in the garage and wears any paint. Shop paints (6.3) are
# bought with fans; paints without a price are every player's from the start.
const PAINTS := [
	{"id": "benxi", "color": "#e63138", "model": "gt"},
	{"id": "uragani", "color": "#246be8", "model": "gt"},
	{"id": "kercyesi", "color": "#e9eff5", "model": "sprint"},
	{"id": "shigjeta", "color": "#536476", "model": "sprint"},
	{"id": "gelendvagen", "color": "#f6c82a", "model": "kombi"},
	{"id": "sprinteri", "color": "#26b69b", "model": "kombi"},
	{"id": "ari", "color": "#c9a227", "price": 600, "model": "gt"},
	{"id": "smerald", "color": "#0f7a4f", "price": 500, "model": "sprint"},
	{"id": "nata", "color": "#45526e", "price": 700, "model": "gt"},
	{"id": "bakri", "color": "#b8653a", "price": 600, "model": "kombi"},
	{"id": "neoni", "color": "#ff2d8f", "price": 900, "model": "sprint"},
	{"id": "akulli", "color": "#9fd7f2", "price": 800, "model": "kombi"},
]
## Every paint on its rivals' car: what CarState, CarVisual and the shop
## read (id = the paint, model = the car, the car's specs and visual).
var CARS: Array[Dictionary] = []
## Paint + car combinations built on request, by "paint/model".
var _car_defs := {}


func _init() -> void:
	for paint: Dictionary in PAINTS:
		CARS.append(_car_def(paint, model(str(paint.model))))


func _car_def(paint: Dictionary, spec: Dictionary) -> Dictionary:
	var def := {"id": paint.id, "color": paint.color, "model": spec.id, "kind": "coupe",
		"vmax": spec.vmax, "acc": spec.acc, "grip": spec.grip, "hp": spec.hp, "mass": spec.mass,
		"visual": spec.visual, "size": CAR_SIZE, "wheel_r": CAR_WHEEL_R}
	if paint.has("price"):
		def.price = paint.price
	return def


# Shop (6.3). Rims colour the wheel rims; liveries are drawn in a second
# colour from assets/cars/livery_atlas.png (tile = column in the atlas, -1
# for none). Items without a price are owned from the start.
const RIMS := [
	{"id": "silver", "price": 0, "color": "#7a7f87", "metal": 0.7, "rough": 0.38},
	{"id": "black", "price": 250, "color": "#1b1c20", "metal": 0.45, "rough": 0.42},
	{"id": "white", "price": 300, "color": "#e4e6ea", "metal": 0.2, "rough": 0.35},
	{"id": "red", "price": 350, "color": "#b3121b", "metal": 0.5, "rough": 0.32},
	{"id": "bronze", "price": 400, "color": "#8a5a2b", "metal": 0.85, "rough": 0.3},
	{"id": "gold", "price": 500, "color": "#d4a531", "metal": 0.95, "rough": 0.22},
]
const LIVERIES := [
	{"id": "none", "price": 0, "tile": -1},
	{"id": "stripes", "price": 400, "tile": 0},
	{"id": "arrow", "price": 600, "tile": 1},
	{"id": "checker", "price": 800, "tile": 2},
	{"id": "split", "price": 500, "tile": 3},
]
const SHOP_KINDS := ["paint", "rim", "livery"]

# ---------------------------------------------------------------- power-ups
const PW := {
	"eagle": {"col": "#ff2b2b", "w": 15, "ammo": 1},
	"bolt": {"col": "#3aa8ff", "w": 16, "ammo": 3},
	"barge": {"col": "#b45cff", "w": 12, "ammo": 1},
	"mine": {"col": "#ff8c1a", "w": 14, "ammo": 1},
	"shock": {"col": "#ffe03a", "w": 7, "ammo": 1},
	"nitro": {"col": "#38ff6a", "w": 17, "ammo": 1},
	"shield": {"col": "#dfe9ff", "w": 10, "ammo": 1},
	"repair": {"col": "#ff5fc8", "w": 9, "ammo": 1},
}
# Points mode only: used on the car itself. Not in PW_KEYS, so no race offers it.
const ARENA_PW := {
	"ram": {"col": "#ff3d9a", "ammo": 1},
	"cluster": {"col": "#00e0c6", "ammo": 1},
	"oil": {"col": "#8b7cff", "ammo": 1},
}
const PW_KEYS := ["eagle", "bolt", "barge", "mine", "shock", "nitro", "shield", "repair"]

# ---------------------------------------------------------------- drivers
# Six drivers: the player is one, the other five drive the bots. Their names
# are proper names, the same in every language; the tag lines are text
# ("driver.<index>.tag").
# The grid's six marker colours. The player always takes the first and races
# under Settings.display_name(); the other five are bots named below.
const DRIVERS := [
	{"col": "#ff2a3d"},
	{"col": "#1fb6ff"},
	{"col": "#ffc21a"},
	{"col": "#2bff88"},
	{"col": "#c46bff"},
	{"col": "#19e6c1"},
]
## The player's name when a simulation is built without one (tests, replays).
const PLAYER_FALLBACK_NAME := "P1"

# Opponents have their own names so changing the AI lineup never changes the
# player's saved driver selection or the name displayed for that selection.
const RIVAL_NAMES := ["Arben", "Dritan", "Luan", "Bora", "Era", "Valon"]

# Rival difficulty. `speed`, `react` and `aim` set how good the bots are.
# The rest is the rubber band, applied to bots only, as fractions of top speed:
# `catch_up` is the most a bot behind the player gains and `lead_drag` the
# most a bot ahead of the player loses, both reached `band` metres away;
# `runaway_drag` is the most a leading bot loses once it is more than
# `runaway_gap` metres clear of second place (full at twice that gap).
const DIFFS := [
	{"id": 0, "speed": 0.87, "react": 1.3, "aim": 0.55,
		"catch_up": 0.06, "lead_drag": 0.05, "band": 60.0, "runaway_gap": 60.0, "runaway_drag": 0.04},
	{"id": 1, "speed": 0.935, "react": 0.9, "aim": 0.8,
		"catch_up": 0.045, "lead_drag": 0.03, "band": 80.0, "runaway_gap": 90.0, "runaway_drag": 0.03},
	{"id": 2, "speed": 1.035, "react": 0.55, "aim": 1.0,
		"catch_up": 0.03, "lead_drag": 0.015, "band": 100.0, "runaway_gap": 120.0, "runaway_drag": 0.02},
]

# Handling difficulty, separate from the rivals' difficulty above. Each value
# scales one driver aid in `Race`: `assist` the steering self-centring,
# `brake_assist` the automatic speed trim before bends (when that aid is on),
# `drift_grip` the extra grip a drift gives. Arcade is 1.0 throughout.
const HANDLING_DEFAULT := "arcade"
const HANDLING := {
	"arcade": {"assist": 1.0, "brake_assist": 1.0, "drift_grip": 1.0},
	"pro": {"assist": 0.7, "brake_assist": 0.5, "drift_grip": 0.5},
}

func pw_col(type: String) -> Color:
	if PW.has(type):
		return Color.html(PW[type].col)
	if ARENA_PW.has(type):
		return Color.html(ARENA_PW[type].col)
	return Color.WHITE


func has_pw(type: String) -> bool:
	return PW.has(type) or ARENA_PW.has(type)


# The tutorial's pickups, station by station, so each one is met in turn.
const TUTORIAL_PICKUPS := ["nitro", "bolt", "shield", "eagle", "mine", "repair", "barge", "nitro", "bolt", "nitro"]

# Cups: a run of fixed races. Every event can be played at any time; stars are
# 1 for the top three, 2 for a win, 3 for a win that also meets the event's
# goal. Goal kinds: "clean" (not wrecked), "hits", "wrecks" (rivals wrecked),
# "fans" (fans earned in the race). Names and goal texts are in the string
# table under cup.event.<id>.name and cup.goal.<kind>.
const CUPS := {
	"tirana": [
		# The first event teaches the game: rivals that do not fire, fixed
		# pickups and instructions along the lap. It can be left at any time.
		{"id": "tirana_0", "laps": 1, "env": "day", "diff": 0, "reverse": false, "tutorial": true, "goal": {"kind": "clean", "n": 0}},
		{"id": "tirana_1", "laps": 1, "env": "day", "diff": 0, "reverse": false, "goal": {"kind": "clean", "n": 0}},
		{"id": "tirana_2", "laps": 1, "env": "rainy", "diff": 0, "reverse": false, "goal": {"kind": "hits", "n": 3}},
		{"id": "tirana_3", "laps": 2, "env": "day", "diff": 1, "reverse": true, "goal": {"kind": "wrecks", "n": 1}},
		{"id": "tirana_4", "laps": 2, "env": "golden", "diff": 1, "reverse": false, "goal": {"kind": "fans", "n": 700}},
		{"id": "tirana_5", "laps": 3, "env": "dusk", "diff": 2, "reverse": false, "goal": {"kind": "clean", "n": 0}},
	],
}


func cup_event(id: String) -> Dictionary:
	for cup: String in CUPS:
		for event: Dictionary in CUPS[cup]:
			if event.id == id:
				return event
	return {}


## `outcome`: finished, place, hits, takedowns, wrecks, fans.
func cup_goal_met(event: Dictionary, outcome: Dictionary) -> bool:
	var goal: Dictionary = event.get("goal", {})
	var n := int(goal.get("n", 0))
	match str(goal.get("kind", "")):
		"clean":
			return int(outcome.get("wrecks", 0)) == 0
		"hits":
			return int(outcome.get("hits", 0)) >= n
		"wrecks":
			return int(outcome.get("takedowns", 0)) >= n
		"fans":
			return int(outcome.get("fans", 0)) >= n
	return false


func cup_stars(event: Dictionary, outcome: Dictionary) -> int:
	if event.is_empty() or not bool(outcome.get("finished", false)):
		return 0
	var place := int(outcome.get("place", 99))
	if place == 1:
		return 3 if cup_goal_met(event, outcome) else 2
	return 1 if place <= 3 else 0


func cup_goal_text(event: Dictionary) -> String:
	var goal: Dictionary = event.get("goal", {})
	var kind := str(goal.get("kind", ""))
	return t("cup.goal.clean") if kind == "clean" else t("cup.goal.%s" % kind, int(goal.get("n", 0)))


func shop_items(kind: String) -> Array:
	match kind:
		"paint":
			return CARS
		"rim":
			return RIMS
		"livery":
			return LIVERIES
	return []


func shop_item(kind: String, id: String) -> Dictionary:
	for item: Dictionary in shop_items(kind):
		if item.id == id:
			return item
	return {}


func shop_price(kind: String, id: String) -> int:
	return int(shop_item(kind, id).get("price", 0))


## Ids every player owns from the start.
func shop_free(kind: String) -> Array[String]:
	var ids: Array[String] = []
	for item: Dictionary in shop_items(kind):
		if int(item.get("price", 0)) == 0:
			ids.append(str(item.id))
	return ids


func shop_name(kind: String, id: String) -> String:
	return car_name(id) if kind == "paint" else t("%s.%s.name" % [kind, id])


func handling_id(id: String) -> String:
	return id if HANDLING.has(id) else HANDLING_DEFAULT


func city(id: String) -> Dictionary:
	for c in CITIES:
		if c.id == id:
			return c
	return CITIES[0]


## True when this build carries the city's data (the APK may leave cities out).
func city_available(id: String) -> bool:
	return FileAccess.file_exists("res://assets/cities/%s/track.json" % id)


## Ids of the cities this build carries, in menu order.
func available_cities() -> Array[String]:
	var ids: Array[String] = []
	for c in CITIES:
		if city_available(str(c.id)):
			ids.append(str(c.id))
	return ids


func points_city(id: String) -> String:
	return id if id in POINTS_CITIES and city_available(id) else "tirane"


func square_name(id: String) -> String:
	return t("arena.square.%s" % points_city(id))


## The paint `id` on its rivals' car, or on car `model_id` when given.
func car(id: String, model_id := "") -> Dictionary:
	var row: Dictionary = CARS[0]
	for c in CARS:
		if c.id == id:
			row = c
			break
	if model_id.is_empty() or model_id == row.model or not has_model(model_id):
		return row
	var key := "%s/%s" % [row.id, model_id]
	if not _car_defs.has(key):
		var paint: Dictionary = PAINTS[car_index(str(row.id))]
		_car_defs[key] = _car_def(paint, model(model_id))
	return _car_defs[key]


func has_model(id: String) -> bool:
	return MODELS.any(func(m: Dictionary) -> bool: return m.id == id)


## A car by id; the default car for an unknown id.
func model(id: String) -> Dictionary:
	for m: Dictionary in MODELS:
		if m.id == id:
			return m
	return MODELS[0]


func model_id(id: String) -> String:
	return id if has_model(id) else MODEL_DEFAULT


## "Vortex Gepard": the car's own name after the game's.
func model_name(id: String) -> String:
	return t("model.%s.name" % model_id(id), GAME_NAME)


## A garage stat bar: `stat` of car `id` between the weakest car (0.2) and
## the strongest (1.0). Mass reads as weight: the heaviest car fills it.
func model_stat(id: String, stat: String) -> float:
	var lo := INF
	var hi := -INF
	for m: Dictionary in MODELS:
		lo = minf(lo, float(m[stat]))
		hi = maxf(hi, float(m[stat]))
	var value := float(model(id)[stat])
	return 1.0 if hi <= lo else clampf(0.2 + 0.8 * (value - lo) / (hi - lo), 0.2, 1.0)


func car_index(id: String) -> int:
	for i in PAINTS.size():
		if PAINTS[i].id == id:
			return i
	return 0


func has_text(key: String) -> bool:
	return strings.has(key)


## The text for a key; args fill its "%s" / "%d" placeholders. Pass the key
## as a literal first argument so tests/string_table can follow it.
func t(key: String, args: Variant = null) -> String:
	var text: Variant = strings.get(key)
	if not (text is String):
		push_error("No text for key: " + key)
		return key
	return text if args == null else text % args


## A list of texts (facts, ordinals, ...). Read-only: duplicate before changing.
func t_list(key: String) -> Array:
	var list: Variant = strings.get(key)
	if not (list is Array):
		push_error("No text list for key: " + key)
		return []
	return list


func env_label(id: String) -> String:
	return t("env.%s" % id)


func city_name(id: String) -> String:
	return t("city.%s.name" % id)


func car_name(id: String) -> String:
	return t("car.%s.name" % id)


func pw_name(type: String) -> String:
	return t("pw.%s.name" % type)


func pw_desc(type: String) -> String:
	return t("pw.%s.desc" % type)


## "I PARI", "I DYTI", ... for a finishing place counted from 1.
func ordinal(place: int) -> String:
	var names := t_list("results.ordinal")
	return names[clampi(place - 1, 0, names.size() - 1)]


func place_msg(place: int, n: int) -> String:
	var messages := t_list("results.place_msg")
	return messages[messages.size() - 1 if place >= n else clampi(place - 1, 0, messages.size() - 1)]


## Rivals of driver index pi (all when pi < 0), shuffled with the given RNG.
func rivals_of(pi: int, rng: RandomNumberGenerator) -> Array:
	var b := []
	for i in DRIVERS.size():
		if i != pi:
			var rival: Dictionary = DRIVERS[i].duplicate()
			rival.name = RIVAL_NAMES[i]
			b.append(rival)
	for i in range(b.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = b[i]
		b[i] = b[j]
		b[j] = t
	return b


static func col(hex: String) -> Color:
	return Color.html(hex)
