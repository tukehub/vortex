extends Node3D
## Fixed-camera render captures for before/after graphics comparisons.
## Rendered only (needs Vulkan; lavapipe works):
##   SHOTS=/abs/dir godot --path godot --rendering-method mobile \
##       --resolution 1280x720 res://tests/render_compare.tscn -- --env=day
## Writes <env>_<quality>_<view>.png. The race is built but never stepped, so
## every run frames the same cars, road and sky.

const VIEWS := ["chase", "road_far", "car"]
## Vehicle close-ups (--views=car,car_rear,wheel,car_front): the player's car
## from the front three-quarter, the rear while braking, the front-right
## wheel, and low in front at headlight height.
const CAR_VIEWS := ["car", "car_rear", "wheel", "car_front"]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Sfx.enabled = false
	Quality.adaptive_enabled = false
	var env := "day"
	var qualities := ["medium", "high"]
	var views: Array = VIEWS
	var city := "tirane"
	# --eye=x,y,z --look=x,y,z for the "custom" view; y is metres above ground.
	var hide := ""   # --hide=NodeName: that child of the race scene hidden, for A/B costs
	var eye_at := Vector3.ZERO
	var look_at := Vector3.ZERO
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--env="):
			env = a.substr(6)
		elif a.begins_with("--views="):
			views = Array(a.substr(8).split(","))
		elif a.begins_with("--hide="):
			hide = a.substr(7)
		elif a.begins_with("--eye="):
			var v := a.substr(6).split_floats(",")
			eye_at = Vector3(v[0], v[1], v[2])
		elif a.begins_with("--look="):
			var v := a.substr(7).split_floats(",")
			look_at = Vector3(v[0], v[1], v[2])
		elif a.begins_with("--city="):
			city = a.substr(7)
		elif a.begins_with("--qualities="):
			qualities = Array(a.substr(12).split(","))
	Quality.set_preset("medium")
	Game.race_opts.city = city
	Game.race_opts.env = env
	Game.race_opts.laps = 1
	Game.race_opts.reverse = false
	var scene := RaceScene.new()
	add_child(scene)
	scene.set_process(false)
	scene._ui_layer.visible = false
	var track := scene.track
	if hide != "" and scene.get_node_or_null(hide) != null:
		(scene.get_node(hide) as Node3D).visible = false
	var player := scene.player
	var player_visual: CarVisual = scene.cars[scene.race.cars.find(player)]
	# The longest gentle straight ahead of the grid, for distant markings.
	var straight := _straight(track)
	var out := OS.get_environment("SHOTS")
	for q in qualities:
		Quality.set_preset(q)
		for view in views:
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
				"car_rear":
					player.braking = true
					player_visual.apply_state(player, track, 1.0 / 60.0)
					var c := player_visual.global_position
					var fwd := -player_visual.global_basis.z
					var side := player_visual.global_basis.x
					cam.look_at_from_position(c - fwd * 5.0 - side * 2.6 + Vector3(0, 1.35, 0), c + Vector3(0, 0.6, 0), Vector3.UP)
					cam.fov = 45.0
				"wheel":
					var w: Node3D = player_visual.wheels.get("wheel_fr", player_visual)
					var at := w.global_position
					var side := player_visual.global_basis.x
					var fwd := -player_visual.global_basis.z
					cam.look_at_from_position(at + side * 1.5 + fwd * 0.55 + Vector3(0, 0.25, 0), at, Vector3.UP)
					cam.fov = 40.0
				"car_front":
					# The grid puts a rival right ahead: only the player's car here.
					for other in scene.cars:
						other.visible = other == player_visual
					var c := player_visual.global_position
					var fwd := -player_visual.global_basis.z
					cam.look_at_from_position(c + fwd * 9.0 + player_visual.global_basis.x * 1.2 + Vector3(0, 0.9, 0), c + Vector3(0, 0.5, 0), Vector3.UP)
					cam.fov = 50.0
				"custom":
					var e := eye_at + Vector3(0, scene.terrain.height_at(eye_at.x, eye_at.z), 0)
					var l := look_at + Vector3(0, scene.terrain.height_at(look_at.x, look_at.z), 0)
					cam.look_at_from_position(e, l, Vector3.UP)
					cam.far = 4000.0
				"seafront":
					# Vlorë: from the kerb by the waterfront courts, out over
					# the rock armour, with a wave breaking on it.
					var rocks: SeaRocks = scene.sea_rocks
					var best := rocks.spray_points[0]
					var best_d := INF
					for p in rocks.spray_points:
						var rd := track.dist_to(p.x, p.z)
						if rd < best_d:
							best_d = rd
							best = p
					var n := track.nearest(best.x, best.z, 200.0)
					var road := Vector3(track.X[n], best.y, track.Z[n])
					var dir := (best - road).normalized()
					var tangent := Vector3(-dir.z, 0, dir.x)
					var eye := best - dir * 3.5 + Vector3(0, 2.6, 0)
					cam.look_at_from_position(eye, best + dir * 9.0 + tangent * 22.0 + Vector3(0, -0.8, 0), Vector3.UP)
					cam.fov = 62.0
					rocks._spray_t = 0.0
					rocks.update(eye + dir * 30.0, 0.0)
			cam.current = true
			for i in 14:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/%s_%s_%s.png" % [out, env, q, view])
			var vp := get_viewport().get_viewport_rid()
			print("RENDER STATS %s %s %s: %d primitives, %d draw calls" % [env, q, view,
				RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
				RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)])
			cam.queue_free()
			player.braking = false
			for other in scene.cars:
				other.visible = true
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
