extends Node3D
## Fixed-camera render captures for before/after graphics comparisons.
## Rendered only (needs Vulkan; lavapipe works):
##   SHOTS=/abs/dir godot --path godot --rendering-method mobile \
##       --resolution 1280x720 res://tests/render_compare.tscn -- --env=day
## Writes <env>_<quality>_<view>.png. The race is built but never stepped, so
## every run frames the same cars, road and sky.

const VIEWS := ["chase", "road_far", "car"]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Sfx.enabled = false
	Quality.adaptive_enabled = false
	var env := "day"
	var qualities := ["medium", "high"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--env="):
			env = a.substr(6)
		elif a.begins_with("--qualities="):
			qualities = Array(a.substr(12).split(","))
	Quality.set_preset("medium")
	Game.race_opts.city = "tirane"
	Game.race_opts.env = env
	Game.race_opts.laps = 1
	Game.race_opts.reverse = false
	var scene := RaceScene.new()
	add_child(scene)
	scene.set_process(false)
	scene._ui_layer.visible = false
	var track := scene.track
	var player := scene.player
	var player_visual: CarVisual = scene.cars[scene.race.cars.find(player)]
	# The longest gentle straight ahead of the grid, for distant markings.
	var straight := _straight(track)
	var out := OS.get_environment("SHOTS")
	for q in qualities:
		Quality.set_preset(q)
		for view in VIEWS:
			var cam := Camera3D.new()
			add_child(cam)
			cam.fov = 60.0
			match view:
				"chase":
					scene.cam.intro = false
					scene.cam._snap = true
					for i in 30:
						scene.cam.follow(player, 1.0 / 60.0)
					cam.global_transform = scene.cam.global_transform
					cam.fov = scene.cam.fov
				"road_far":
					var eye := track.pos(straight, 2.5) + Vector3(0, 1.2, 0)
					cam.look_at_from_position(eye, track.pos(straight + 120.0, 2.5) + Vector3(0, 1.0, 0), Vector3.UP)
				"car":
					var c := player_visual.global_position
					var fwd := -player_visual.global_basis.z
					var side := player_visual.global_basis.x
					cam.look_at_from_position(c + fwd * 4.2 + side * 3.0 + Vector3(0, 1.3, 0), c + Vector3(0, 0.55, 0), Vector3.UP)
					cam.fov = 45.0
			cam.current = true
			for i in 14:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/%s_%s_%s.png" % [out, env, q, view])
			cam.queue_free()
	print("RENDER COMPARE: done ", env)
	get_tree().quit()


func _straight(track: RaceTrack) -> float:
	var best := 0.0
	var best_k := INF
	var s := 50.0
	while s < track.L - 250.0:
		var k := 0.0
		var t := 0.0
		while t < 200.0:
			k += absf(track.curv(s + t))
			t += 10.0
		if k < best_k:
			best_k = k
			best = s
		s += 25.0
	return best
