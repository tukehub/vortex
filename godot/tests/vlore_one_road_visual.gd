extends Node3D
## Vlorë's carriageways as one road: captures for review (needs Vulkan;
## lavapipe works). Not part of tools/run_tests.py.
##   SHOTS=/abs/dir godot --path godot --rendering-method mobile \
##       --resolution 1280x720 res://tests/vlore_one_road_visual.tscn
## Writes one_road_<view>.png: the boulevard from the driver's height, the
## Lungomare median from beside it and from above, a car crossing it, and the
## road splitting round Sheshi Pavarsia.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Sfx.enabled = false
	Quality.adaptive_enabled = false
	Quality.set_preset("medium")
	Game.race_opts.city = "vlore"
	Game.race_opts.env = "day"
	Game.race_opts.laps = 1
	Game.race_opts.reverse = false
	var scene := RaceScene.new()
	add_child(scene)
	scene.set_process(false)
	scene._ui_layer.visible = false
	var track := scene.track
	var player := scene.player
	var visual: CarVisual = scene.cars[scene.race.cars.find(player)]
	var median := _median_middle(track)
	var split := _split_before(track, median)
	var out := OS.get_environment("SHOTS")
	for view in ["boulevard", "median_side", "median_top", "median_car", "split"]:
		var cam := Camera3D.new()
		add_child(cam)
		cam.fov = 62.0
		var s := 600.0
		match view:
			"boulevard":
				cam.look_at_from_position(track.pos(s, 2.0) + Vector3.UP * 1.25, track.pos(s + 60.0, -3.0) + Vector3.UP * 1.0, Vector3.UP)
			"median_side":
				s = median
				var mid := track.join_offset(s)
				cam.look_at_from_position(track.pos(s, mid + 3.5) + Vector3.UP * 0.7, track.pos(s + 18.0, mid) + Vector3.UP * 0.05, Vector3.UP)
			"median_top":
				s = median
				var mid := track.join_offset(s)
				cam.look_at_from_position(track.pos(s - 14.0, mid + 1.0) + Vector3.UP * 9.0, track.pos(s + 10.0, mid), Vector3.UP)
			"median_car":
				s = median
				var mid := track.join_offset(s)
				player.s = s
				player.progress = s
				player.d = mid + 0.6
				player.v = 20.0
				for i in 20:
					visual.apply_state(player, track, 1.0 / 60.0)
				cam.look_at_from_position(track.pos(s - 9.0, mid + 4.0) + Vector3.UP * 2.2, visual.global_position + Vector3.UP * 0.5, Vector3.UP)
				print("MEDIAN CAR heave %.3f m roll %.1f deg" % [visual.median_heave, rad_to_deg(visual.median_roll)])
			"split":
				s = split
				cam.look_at_from_position(track.pos(s - 40.0, -1.0) + Vector3.UP * 6.0, track.pos(s + 30.0, track.join_offset(s - 20.0)), Vector3.UP)
		cam.current = true
		scene.sky.follow(cam.global_position)
		scene.props.update_vegetation(cam.global_position, -cam.global_basis.z)
		for i in 12:
			await get_tree().process_frame
		if out != "":
			get_viewport().get_texture().get_image().save_png("%s/one_road_%s.png" % [out, view])
		cam.queue_free()
	print("VLORE ONE ROAD VISUAL: done")
	get_tree().quit()


## Middle of the first median stretch along the lap.
static func _median_middle(track: RaceTrack) -> float:
	var first := -1
	var last := -1
	for i in track.M:
		if track.MEDIAN[i] >= 1.0:
			if first < 0:
				first = i
			last = i
		elif first >= 0:
			break
	return (first + last) * 0.5 * track.ds


## Lap position just before the joined road last split ahead of `before`.
static func _split_before(track: RaceTrack, before: float) -> float:
	var i := int(before / track.ds)
	while i > 0 and track.PAIR[i] >= 0:
		i -= 1
	while i > 0 and track.PAIR[i] < 0:
		i -= 1
	return i * track.ds
