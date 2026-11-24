extends Node3D
## Vlorë review captures (needs Vulkan; lavapipe works). Not in run_tests.
##   SHOTS=/abs/dir godot --path godot --rendering-method mobile \
##       --resolution 1280x720 res://tests/vlore_round2_visual.tscn
## Writes vlore_<view>.png: the asphalt close up, the Uji i Ftohtë portal,
## both roundabouts from above, Kuzum Baba from the return leg (four
## distances), and Teatri Petro Marko from the outbound leg.

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
	for c in scene.cars:
		c.visible = false
	print("R2: scene built")
	var track := scene.track
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cities/vlore/track.json"))
	var marks := {}
	for lm: Dictionary in scene.props.landmarks:
		marks[lm.id] = Vector3(float(lm.x), float(lm.y), float(lm.z))
	var views := []
	var only := OS.get_environment("VIEWS")
	views.append(["asphalt", track.pos(420.0, 1.5) + Vector3.UP * 1.1, track.pos(432.0, -1.0)])
	var portal := track.locate_xz(data.tunnel[0][0], data.tunnel[0][1]).x
	views.append(["tunnel", track.pos(portal - 70.0, 1.0) + Vector3.UP * 2.2, track.pos(portal, 0.0) + Vector3.UP * 4.0])
	views.append(["tunnel_side", track.pos(portal - 40.0, 14.0) + Vector3.UP * 9.0, track.pos(portal + 10.0, -8.0) + Vector3.UP * 4.0])
	for id in ["skela_roundabout", "flag_square_island"]:
		var c: Vector3 = marks[id]
		c.y = track.height(track.locate_xz(c.x, c.z).x)
		views.append([id, c + Vector3(-38.0, 34.0, 52.0), c])
	# Kuzum Baba from the return leg: the second pass by the tekke's latitude.
	var tekke: Vector3 = marks.kuzum_baba_tekke
	var passes := _passes(track, Vector3(track.X[0], 0, tekke.z))
	var back: float = passes[-1] if passes.size() > 0 else track.L - 800.0
	for before in [1000.0, 750.0, 500.0, 250.0]:
		var s: float = back - float(before)
		views.append(["kuzum_%d" % int(before), track.pos(s, 0.0) + Vector3.UP * 2.3, track.pos(s + 40.0, 0.0) + Vector3.UP * 1.6])
	# After the Flag Square turn, down to the line and on: Kuzum Baba ahead.
	for at_s in [track.L - 220.0, track.L - 120.0, track.L - 20.0, 80.0]:
		var s: float = at_s
		views.append(["final_%d" % int(at_s), track.pos(s, 0.0) + Vector3.UP * 2.3, track.pos(s + 40.0, 0.0) + Vector3.UP * 1.6])
	# Petro Marko from the outbound leg, after the line.
	var theatre: Vector3 = marks.petro_marko
	var at := 414.0
	for before in [300.0, 150.0, 60.0]:
		var s: float = at - float(before)
		views.append(["petro_%d" % int(before), track.pos(s, 0.0) + Vector3.UP * 2.3, track.pos(s + 40.0, 0.0) + Vector3.UP * 1.6])
	print("R2: ", views.size(), " views")
	var out := OS.get_environment("SHOTS")
	for v in views:
		if only != "" and not str(v[0]).begins_with(only):
			continue
		var cam := Camera3D.new()
		add_child(cam)
		cam.fov = 66.0
		cam.far = 3000.0
		cam.look_at_from_position(v[1], v[2], Vector3.UP)
		cam.current = true
		scene.sky.follow(cam.global_position)
		scene.props.update_vegetation(cam.global_position, -cam.global_basis.z)
		for i in 10:
			await get_tree().process_frame
		if out != "":
			get_viewport().get_texture().get_image().save_png("%s/vlore_%s.png" % [out, v[0]])
		cam.queue_free()
	print("VLORE ROUND2 VISUAL: done, return pass by Kuzum Baba at %.0f m, theatre at %.0f m" % [back, at])
	get_tree().quit()


## Lap positions where the centreline passes nearest `p`'s z (one per pass).
static func _passes(track: RaceTrack, p: Vector3) -> Array:
	var out := []
	var last := -1000.0
	for i in track.M:
		var a := track.Z[i]
		var b := track.Z[(i + 1) % track.M]
		if (a - p.z) * (b - p.z) <= 0.0 and absf(track.X[i] - p.x) < 200.0 and i * track.ds - last > 200.0:
			out.append(i * track.ds)
			last = i * track.ds
	return out
