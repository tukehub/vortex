extends Node3D
## Korçë review captures (needs Vulkan; lavapipe works). Not in run_tests.
##   SHOTS=/abs/dir godot --path godot --rendering-method mobile \
##       --resolution 1280x720 res://tests/korce_landmarks_visual.tscn
## Writes korce_<view>.png: the Resurrection Cathedral down Bulevardi
## Republika from the grid and the approach (driver's eye), across its
## square, close on the portico, a bell tower and the domes, and from the
## air; Mësonjëtorja from the boulevard both ways and from its gate.
## VIEWS=<prefix>[,<prefix>...] renders only the views whose names start so.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Sfx.enabled = false
	Quality.adaptive_enabled = false
	Quality.set_preset(OS.get_environment("QUALITY") if OS.get_environment("QUALITY") != "" else "high")
	Game.race_opts.city = "korce"
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
	var cathedral: Vector3 = marks.korce_cathedral
	var school: Vector3 = marks.mesonjetorja
	var cat_s := track.locate_xz(cathedral.x, cathedral.z).x
	var school_s := track.locate_xz(school.x, school.z).x
	var yaw := deg_to_rad(59.0)
	var front := Vector3(-sin(yaw), 0, -cos(yaw))
	var across := Vector3(cos(yaw), 0, -sin(yaw))
	var syaw := deg_to_rad(-128.0)
	var sfront := Vector3(-sin(syaw), 0, -cos(syaw))
	var views := []
	# Driver's eye down Republika toward the square (grid, then the approach).
	views.append(["grid", track.pos(2.0, 0.0) + Vector3.UP * 2.3, track.pos(60.0, 0.0) + Vector3.UP * 3.0])
	for before in [260.0, 160.0, 90.0, 40.0]:
		var s: float = cat_s - float(before)
		views.append(["approach_%d" % int(before), track.pos(s, 0.0) + Vector3.UP * 2.3, track.pos(s + 40.0, 0.0) + Vector3.UP * 2.0])
	views.append(["passing", track.pos(cat_s - 10.0, -4.0) + Vector3.UP * 2.0, cathedral + Vector3.UP * 12.0])
	views.append(["square", cathedral + front * 70.0 + Vector3.UP * 2.0, cathedral + Vector3.UP * 13.0])
	views.append(["square_left", cathedral + front * 52.0 + across * 30.0 + Vector3.UP * 3.0, cathedral + Vector3.UP * 12.0])
	views.append(["portico", cathedral + front * 30.0 + across * -6.0 + Vector3.UP * 3.5, cathedral + front * 14.0 + Vector3.UP * 5.0])
	views.append(["tower", cathedral + front * 26.0 + across * 18.0 + Vector3.UP * 14.0, cathedral + front * 8.0 + across * 11.8 + Vector3.UP * 24.0])
	views.append(["domes", cathedral + front * 22.0 + across * -14.0 + Vector3.UP * 26.0, cathedral + Vector3.UP * 19.0])
	views.append(["aerial", cathedral + front * 70.0 + across * 50.0 + Vector3.UP * 60.0, cathedral + Vector3.UP * 5.0])
	views.append(["rear", cathedral - front * 45.0 + across * 25.0 + Vector3.UP * 8.0, cathedral + Vector3.UP * 12.0])
	# Mësonjëtorja from the boulevard both ways and from its gate.
	views.append(["school_south", track.pos(school_s - 70.0, 2.0) + Vector3.UP * 2.3, school + Vector3.UP * 4.0])
	views.append(["school_road", track.pos(school_s, 3.0) + Vector3.UP * 2.3, school + Vector3.UP * 3.5])
	views.append(["school_north", track.pos(school_s + 60.0, 2.0) + Vector3.UP * 2.3, school + Vector3.UP * 4.0])
	views.append(["school_gate", school + sfront * 19.0 + Vector3.UP * 1.8, school + Vector3.UP * 4.0])
	views.append(["school_close", school + sfront * 11.0 + Vector3(sfront.z, 0, -sfront.x) * 5.0 + Vector3.UP * 2.5, school + Vector3.UP * 4.5])
	views.append(["school_aerial", school + sfront * 22.0 + Vector3(sfront.z, 0, -sfront.x) * -14.0 + Vector3.UP * 18.0, school + Vector3.UP * 3.0])
	_report_meshes(scene)
	var only := OS.get_environment("VIEWS").split(",", false)
	var out := OS.get_environment("SHOTS")
	print("KORCE VISUAL: ", views.size(), " views; cathedral at %.0f m, school at %.0f m of %.0f" % [cat_s, school_s, track.L])
	for v in views:
		var wanted := only.is_empty()
		for prefix in only:
			wanted = wanted or str(v[0]).begins_with(prefix)
		if not wanted:
			continue
		var cam := Camera3D.new()
		add_child(cam)
		cam.fov = 66.0
		cam.far = 3000.0
		cam.look_at_from_position(v[1], v[2], Vector3.UP)
		cam.current = true
		scene.sky.follow(cam.global_position)
		scene.props.update_vegetation(cam.global_position, -cam.global_basis.z)
		for i in 12:
			await get_tree().process_frame
		if out != "":
			get_viewport().get_texture().get_image().save_png("%s/korce_%s.png" % [out, v[0]])
		cam.queue_free()
	print("KORCE VISUAL: done")
	get_tree().quit()


## Vertices and draw calls of the Korçë landmarks, for the phone budget.
func _report_meshes(scene: RaceScene) -> void:
	for lm: Node in scene.props.get_children():
		if not lm is Landmarks:
			continue
		for anchor: Node in lm.get_children():
			if not str(anchor.name) in ["korce_cathedral", "mesonjetorja", "national_warrior"]:
				continue
			var total := 0
			var calls := 0
			for part in anchor.get_child(0).get_children():
				if part is MeshInstance3D and part.mesh != null:
					calls += 1
					for s in part.mesh.get_surface_count():
						total += (part.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			print("KORCE MESH: ", anchor.name, " ", calls, " meshes, ", total, " vertices")

