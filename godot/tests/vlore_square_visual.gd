extends Node3D
## Review captures of Sheshi i Flamurit and the Muradie street (needs Vulkan;
## lavapipe works). Not in run_tests.
##   SHOTS=/abs/dir godot --path godot --rendering-method mobile \
##       --resolution 1280x720 res://tests/vlore_square_visual.tscn
## VIEWS=a,b limits the run to views whose names start with those prefixes.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Sfx.enabled = false
	Quality.adaptive_enabled = false
	Quality.set_preset("high")
	Game.race_opts.city = "vlore"
	Game.race_opts.env = OS.get_environment("ENV") if OS.get_environment("ENV") != "" else "day"
	Game.race_opts.laps = 1
	Game.race_opts.reverse = false
	var scene := RaceScene.new()
	add_child(scene)
	scene.set_process(false)
	scene._ui_layer.visible = false
	for c in scene.cars:
		c.visible = false
	var track := scene.track
	var marks := {}
	for lm: Dictionary in scene.props.landmarks:
		marks[lm.id] = Vector3(float(lm.x), float(lm.y), float(lm.z))
	var mon: Vector3 = marks.independence
	var mosque: Vector3 = marks.muradie_mosque
	var yaw := deg_to_rad(-44.3)
	var front := Vector3(-sin(yaw), 0, -cos(yaw))
	var side := Vector3(cos(yaw), 0, -sin(yaw))
	var views := []
	var ms := track.locate_xz(mon.x, mon.z).x
	views.append(["monument_road", track.pos(ms - 90.0, 0.0) + Vector3.UP * 2.3, mon + Vector3.UP * 8.0])
	views.append(["monument_front", mon + front * 24.0 + Vector3.UP * 3.0, mon + Vector3.UP * 7.5])
	views.append(["monument_close", mon + front * 11.0 + side * 6.0 + Vector3.UP * 2.6, mon + Vector3.UP * 4.0])
	views.append(["monument_three_quarter", mon + front * 20.0 - side * 22.0 + Vector3.UP * 6.0, mon + Vector3.UP * 9.0])
	views.append(["monument_top", mon + front * 14.0 + Vector3.UP * 16.0, mon + Vector3.UP * 14.0])
	var qs := track.locate_xz(mosque.x, mosque.z).x
	for d in [-120.0, -50.0, 0.0, 60.0]:
		views.append(["muradie_%d" % int(d), track.pos(qs + d, 0.0) + Vector3.UP * 2.3, track.pos(qs + d + 40.0, 0.0) + Vector3.UP * 2.0])
	views.append(["muradie_back", track.pos(qs + 40.0, 0.0) + Vector3.UP * 2.3, track.pos(qs - 20.0, 0.0) + Vector3.UP * 2.0])
	views.append(["muradie_side", track.pos(qs, track.half_w + 2.0) + Vector3.UP * 1.7, mosque + Vector3.UP * 4.0])
	views.append(["muradie_aerial", mosque + Vector3(60, 70, 60), mosque])
	# The Konomi split: from the shore road heading for the tunnel, and above.
	var split := Vector3(292.0, 0.0, -128.0)
	var so := track.locate_xz(split.x, split.z).x
	for back in [120.0, 60.0]:
		views.append(["split_%d" % int(back), track.pos(so - back, 0.0) + Vector3.UP * 2.3, track.pos(so + 30.0, 0.0) + Vector3.UP * 1.5])
	var lion: Vector3 = marks.rrapi_lion
	var sh := Vector3(split.x, scene.terrain.height_at(split.x, split.z), split.z)
	views.append(["split_aerial", sh + Vector3(-90, 110, -40), lion + Vector3(10, 0, -20)])
	var fountain := scene.props.get_node("Landmarks/rrapi_lion/RrapiFountain") as Node3D if scene.props.has_node("Landmarks/rrapi_lion/RrapiFountain") else null
	if fountain == null:
		for n in scene.props.find_children("RrapiFountain", "", true, false):
			fountain = n
	var fx := fountain.global_transform
	var mouth_w: Vector3 = fx * (fountain as RrapiFountain).mouth
	views.append(["split_fountain", fx * ((fountain as RrapiFountain).mouth + Vector3(7, 1.6, -9)), mouth_w + Vector3.DOWN * 0.4])
	views.append(["split_lion", fx * ((fountain as RrapiFountain).mouth + Vector3(1.6, 0.4, -2.6)), fx * ((fountain as RrapiFountain).mouth + Vector3(0, -0.3, 0.8))])
	views.append(["split_lion_side", fx * ((fountain as RrapiFountain).mouth + Vector3(-3.4, 0.2, 0.9)), fx * ((fountain as RrapiFountain).mouth + Vector3(0, -0.35, 0.9))])
	# The line at Sheshi i Flamurit, and the boulevard's back blocks.
	views.append(["finish_grid", track.pos(-60.0, 0.0) + Vector3.UP * 4.0, track.pos(40.0, 0.0) + Vector3.UP * 1.0])
	if track.sprint:
		views.append(["finish_line", track.pos(track.finish_s - 70.0, 0.0) + Vector3.UP * 2.3, track.pos(track.finish_s + 20.0, 0.0) + Vector3.UP * 1.0])
	views.append(["finish_aerial", mon + Vector3(140, 110, 120), mon + Vector3(40, 0, 60)])
	views.append(["infill_theatre", mosque + Vector3(260, 260, 420), mosque + Vector3(-120, 0, 300)])
	views.append(["infill_mosque", mosque + Vector3(220, 200, -60), mosque + Vector3(-160, 0, 40)])
	var only := OS.get_environment("VIEWS").split(",", false)
	var out := OS.get_environment("SHOTS")
	for v in views:
		var wanted := only.is_empty()
		for prefix in only:
			wanted = wanted or str(v[0]).begins_with(prefix)
		if not wanted:
			continue
		var cam := Camera3D.new()
		add_child(cam)
		cam.fov = 66.0
		cam.far = 4000.0
		cam.look_at_from_position(v[1], v[2], Vector3.UP)
		cam.current = true
		scene.sky.follow(cam.global_position)
		scene.props.update_vegetation(cam.global_position, -cam.global_basis.z)
		for i in 12:
			await get_tree().process_frame
		if out != "":
			get_viewport().get_texture().get_image().save_png("%s/vlore_%s.png" % [out, v[0]])
		cam.queue_free()
	print("VLORE SQUARE VISUAL: done")
	get_tree().quit()
