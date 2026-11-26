extends Node
## The cars (Data.MODELS): each drives differently, every one is open from
## the start, any paint fits any car, and the chosen car reaches the race,
## the points arena, an online grid and the save file. Rivals keep their own
## cars.

const STEP := 1.0 / 60.0
const SettingsScript = preload("res://scripts/game/settings.gd")
const MenuScript = preload("res://scripts/ui/menu.gd")
const SETTINGS_FILE := "user://settings_car_models_test.cfg"

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("CHECK FAILED: " + message)


## Seconds from standstill to `speed` m/s at full throttle on a straight
## road (curvature flattened, as tests/driving_dynamics does).
func time_to(straight: RaceTrack, model_id: String, speed: float) -> float:
	var race := Race.new(straight, {"seed": 1, "player_car": "benxi", "player_model": model_id})
	race.started = true
	var car := race.player
	car.d = 0.0
	car.yaw = 0.0
	car.v = 0.0
	car.ctrl.gas = true
	var t := 0.0
	while car.v < speed and t < 20.0:
		race.physics(car, STEP)
		t += STEP
	return t


func _ready() -> void:
	# The garage clicks: silent, so no sound is still playing at exit.
	var sound := Sfx.enabled
	Sfx.enabled = false
	# The catalogue.
	var ids := {}
	for m: Dictionary in Data.MODELS:
		ids[m.id] = true
		check(Data.has_model(str(m.id)) and Data.model(str(m.id)) == m, "car %s can be found" % m.id)
		check(Data.has_text("model.%s.name" % m.id) and Data.has_text("model.%s.desc" % m.id), "car %s has a name and a line" % m.id)
		check(Data.model_name(str(m.id)).begins_with(Data.GAME_NAME), "car names lead with the game's: " + Data.model_name(str(m.id)))
		check(ResourceLoader.exists(str(m.visual.model_path)), "car %s has its chassis" % m.id)
		for stat: String in Data.MODEL_STATS:
			var bar := Data.model_stat(str(m.id), stat)
			check(bar >= 0.2 and bar <= 1.0, "stat bars stay in range: %s %s" % [m.id, stat])
	check(ids.size() == Data.MODELS.size() and Data.MODELS.size() >= 4, "four or more cars, each its own id")
	check(Data.MODELS[0].id == Data.MODEL_DEFAULT and Data.model("nope").id == Data.MODEL_DEFAULT and Data.model_id("nope") == Data.MODEL_DEFAULT, "an unknown car is the default car")
	for stat: String in Data.MODEL_STATS:
		var values := {}
		for m: Dictionary in Data.MODELS:
			values[m[stat]] = true
		check(values.size() >= 3, "the cars differ in " + stat)
	var fastest: Dictionary = Data.MODELS[0]
	var toughest: Dictionary = Data.MODELS[0]
	for m: Dictionary in Data.MODELS:
		fastest = m if float(m.vmax) > float(fastest.vmax) else fastest
		toughest = m if float(m.hp) > float(toughest.hp) else toughest
	check(fastest.id == "gepard" and is_equal_approx(Data.model_stat("gepard", "vmax"), 1.0), "the Gepard race car is the fastest")
	check(toughest.id == "kombi" and float(Data.model("gepard").hp) < float(Data.model("gt").hp), "and pays for it in armour; the Kombi is the toughest")
	# No car is better at everything.
	for m: Dictionary in Data.MODELS:
		var weaker := Data.MODEL_STATS.filter(func(stat: String) -> bool:
			return stat != "mass" and Data.MODELS.any(func(o: Dictionary) -> bool: return float(o[stat]) > float(m[stat])))
		check(not weaker.is_empty(), "every car gives something up: " + str(m.id))

	# Paint on a car.
	var row := Data.car("kercyesi")
	check(row.model == "sprint" and row.visual == VehicleRig.HATCH and is_equal_approx(row.vmax, Data.model("sprint").vmax), "a paint's own row is its rivals' car")
	var combo := Data.car("kercyesi", "gepard")
	check(combo.id == "kercyesi" and combo.color == row.color and combo.model == "gepard" and combo.visual == VehicleRig.CHEETAH, "any paint goes on any car")
	for stat: String in Data.MODEL_STATS:
		check(is_equal_approx(float(combo[stat]), float(Data.model("gepard")[stat])), "and drives like that car: " + stat)
	check(combo.size == row.size and is_equal_approx(combo.wheel_r, row.wheel_r), "with the same contact footprint")
	check(Data.car("kercyesi", "gepard") == combo and Data.car("kercyesi", "sprint") == row and Data.car("kercyesi", "nope") == row, "combinations are kept; the paint's own car or an unknown one is its row")
	check(not combo.has("price") and Data.car("ari", "gepard").price == Data.car("ari").price, "a shop paint keeps its price on every car")
	check(Data.shop_items("paint") == Data.CARS and Data.CARS.size() == Data.PAINTS.size(), "the paint shop lists each paint once")

	# The save file: the chosen car is kept; an older file keeps the car its
	# paint was drawn on; nonsense is the default car.
	for suffix in ["", ".tmp"]:
		if FileAccess.file_exists(SETTINGS_FILE + suffix):
			DirAccess.remove_absolute(SETTINGS_FILE + suffix)
	var settings: Node = SettingsScript.new()
	settings.car_id = "uragani"
	settings.model_id = "gepard"
	settings.save(SETTINGS_FILE)
	var read_back: Node = SettingsScript.new()
	read_back.load_settings(SETTINGS_FILE)
	check(read_back.car_id == "uragani" and read_back.model_id == "gepard", "the chosen car and paint survive a save")
	var file := ConfigFile.new()
	file.load(SETTINGS_FILE)
	file.set_value("meta", "version", 6)
	file.erase_section_key("race", "model")
	file.set_value("race", "car", "gelendvagen")
	file.save(SETTINGS_FILE)
	var older: Node = SettingsScript.new()
	older.load_settings(SETTINGS_FILE)
	check(older.car_id == "gelendvagen" and older.model_id == "kombi", "a file from before the cars keeps the car its paint was drawn on")
	file.set_value("meta", "version", SettingsScript.VERSION)
	file.set_value("race", "model", "hovercraft")
	file.save(SETTINGS_FILE)
	var odd: Node = SettingsScript.new()
	odd.load_settings(SETTINGS_FILE)
	check(odd.model_id == Data.MODEL_DEFAULT, "an unknown saved car is the default car")
	for node: Node in [settings, read_back, older, odd]:
		node.free()
	DirAccess.remove_absolute(SETTINGS_FILE)

	# The race: the player's car is the chosen one, the rivals keep theirs.
	var track := RaceTrack.load_city("tirane")
	var race := Race.new(track, {"seed": 11, "laps": 1, "player_car": "neoni", "player_model": "kombi"})
	check(race.player.def.id == "neoni" and race.player.def.model == "kombi" and is_equal_approx(race.player.max_hp, 145.0), "the player races the chosen car in the chosen paint")
	for c in race.cars:
		if c != race.player:
			check(c.def == Data.car(str(c.def.id)), "rivals drive their paint's own car")
	var plain := Race.new(track, {"seed": 11, "laps": 1, "player_car": "neoni"})
	check(plain.player.def == Data.car("neoni"), "without a car, the paint's own car")
	check(Race.new(track, {"seed": 11, "laps": 1, "player_car": "neoni", "player_model": "gepard"}).state_hash() != race.state_hash(), "the car is part of the lockstep state")
	# It drives that way: 0-100 km/h stays a sports car's for every car, the
	# Sprint gets there first and the Kombi last.
	var straight := RaceTrack.load_city("tirane")
	straight.K.fill(0.0)
	var times := {}
	for m: Dictionary in Data.MODELS:
		times[m.id] = time_to(straight, str(m.id), 100.0 / 3.6)
		check(times[m.id] > 2.5 and times[m.id] < 6.0, "0-100 km/h in %.2f s: %s" % [times[m.id], m.id])
	check(times.sprint < times.gt and times.gt < times.kombi and times.gepard < times.gt, "acceleration follows the cars: %s" % str(times))

	# The points arena.
	var arena := Arena.new({"seed": 4, "time": 60.0, "player_car": "akulli", "player_model": "gepard"})
	check(arena.player.def.model == "gepard" and arena.player.def.id == "akulli" and is_equal_approx(float(arena.player.def.mass), 1.0), "the arena takes the chosen car")

	# Online: each phone's car travels with its paint and builds the same grid.
	var hello := NetProto.decode(NetProto.hello("Ana", "uragani", "gepard"))
	check(hello.get("model") == "gepard" and hello.get("car") == "uragani" and int(hello.version) == NetProto.VERSION, "HELLO carries the car")
	var lobby := NetProto.decode(NetProto.lobby(["Ana", "Ben"], ["uragani", "benxi"], ["gepard", "sprint"]))
	check(lobby.get("models") == ["gepard", "sprint"], "the lobby lists every phone's car")
	var humans := [{"name": "Ana", "car": "uragani", "model": "gepard"}, {"name": "Ben", "car": "benxi", "model": "sprint"}]
	var online_a := Race.new(track, {"seed": 9, "laps": 1, "humans": humans, "bots": 2})
	var online_b := Race.new(track, {"seed": 9, "laps": 1, "humans": humans.duplicate(true), "bots": 2})
	check(online_a.humans[0].def.model == "gepard" and online_a.humans[1].def.model == "sprint", "each human races their own car")
	check(online_a.state_hash() == online_b.state_hash(), "and every phone builds the same grid")

	# The garage: every car is open and chosen with one tap.
	var saved := [Game.race_opts.car, Game.race_opts.model, Settings.car_id, Settings.model_id]
	Game.race_opts.car = "benxi"
	Game.race_opts.model = "gt"
	var menu: Menu = MenuScript.new()
	add_child(menu)
	await get_tree().process_frame
	menu.show_page("car")
	check(menu._garage_tab == "model" and menu._model_btns.size() == Data.MODELS.size(), "the garage opens on the cars, one button each")
	for id: String in menu._model_btns:
		var b: Button = menu._model_btns[id]
		check(not b.disabled and b.text == Data.model_name(id), "%s is open, under its name" % id)
	check(menu._model_btns.gt.button_pressed and not menu._model_btns.gepard.button_pressed, "the chosen car is lit")
	menu._model_btns.gepard.pressed.emit()
	check(Game.race_opts.model == "gepard" and Settings.model_id == "gepard" and menu._preview.is_empty() and not menu._buy_btn.visible, "a car is chosen at once, nothing to buy")
	check(menu.garage_car.def.model == "gepard" and menu.garage_car.def.id == "benxi" and menu.garage_car.model.scene_file_path == VehicleRig.CHEETAH.model_path, "the garage shows it in the chosen paint")
	check(is_equal_approx(menu._stat_bars.vmax.value, 1.0) and menu._stat_bars.hp.value < menu._stat_bars.vmax.value, "with its stat bars")
	check(menu._top_speed.text == Data.t("garage.top_speed", roundi(61.0 * 3.6)) and menu._car_desc.text.begins_with(Data.model_name("gepard")), "its top speed and name")
	menu._show_garage_tab("paint")
	menu._shop_btns["paint:uragani"].pressed.emit()
	check(Game.race_opts.car == "uragani" and Game.race_opts.model == "gepard" and menu.garage_car.def.model == "gepard" and menu.garage_car.def.id == "uragani", "a new paint keeps the car")
	menu._model_btns.sprint.pressed.emit()
	check(menu.garage_car.model.scene_file_path == VehicleRig.HATCH.model_path and menu.garage_car.def.id == "uragani", "and a new car keeps the paint")
	menu.queue_free()
	Game.race_opts.car = saved[0]
	Game.race_opts.model = saved[1]
	Settings.car_id = saved[2]
	Settings.model_id = saved[3]
	Settings.save()
	await get_tree().create_timer(0.3).timeout
	Sfx.enabled = sound
	print("CAR MODELS: catalogue, paint on any car, save migration, race, arena, online and garage; failures=%d" % failures)
	get_tree().quit(1 if failures else 0)
