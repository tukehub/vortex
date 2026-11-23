extends "res://tests/tirana_showcase_visual.gd"
## Same 300 m boulevard framing as the showcase, plus a fixed existing tree
## seen from either side of the nominal transitions along the boulevard.

const TARGET := Vector2(104.8, -118.2)
const TARGET_INDEX := 1619
const POSES := ["dense", "close", "near_in", "near_out", "mid_in", "mid_out"]
const MOTION_FRAMES := 20
var selected: Array[String] = ["dense"]
var blend_shots := false
var shot_index := 0
var settle := 0
var tree_system: Node
var bench_usec := 0
var tick_usec := 0
var gpu_times: Array[float] = []


func _ready() -> void:
	for option in OS.get_cmdline_user_args():
		if option == "detail":
			selected.assign(POSES)
		elif option == "blend":
			blend_shots = true
	if blend_shots and selected.size() > 1:
		selected.insert(selected.find("near_out"), "near_blend")
		selected.insert(selected.find("mid_out"), "mid_blend")
	super._ready()
	# Keep these vegetation comparisons independent of cubemap updates.
	world.reflections.hide()
	if world.props.has_method("update_vegetation"):
		tree_system = world.props.get("vegetation")
	_frame_view(selected[0])


func place_camera(at: float) -> void:
	var origin := city_track.pos(at, -3.0)
	var target := city_track.pos(at + 33.0, 0.0)
	camera.global_position = origin + Vector3.UP * 3.7
	camera.look_at(target + Vector3.UP * 2.0)
	world.sky.follow(camera.global_position)


func _frame_view(pose: String) -> void:
	if pose == "dense":
		place_camera(300.0)
	else:
		var height := world.terrain.height_at(TARGET.x, TARGET.y)
		var trunk := Vector3(TARGET.x, height, TARGET.y)
		var direction := city_track.tangent(300.0)
		direction.y = 0
		direction = direction.normalized()
		var distance := float({"close": 13.0, "near_in": 65.0, "near_out": 78.0,
			"mid_in": 151.0, "mid_out": 175.0, "near_blend": 78.0, "mid_blend": 175.0}[pose])
		var p := trunk - direction * distance + city_track.normal(300.0) * 4.3
		p.y = world.terrain.height_at(p.x, p.z) + (3.7 if pose == "close" else 5.0)
		camera.global_position = p
		camera.look_at(trunk + Vector3.UP * 4.6)
		world.sky.follow(camera.global_position)
	if tree_system != null and pose.ends_with("_blend"):
		var now := Time.get_ticks_msec() + 100
		_refresh(false, now)
		_refresh(false, now + 90)
	else:
		_refresh(true)


func _refresh(force: bool, now := -1) -> void:
	var direction := -camera.global_transform.basis.z
	if tree_system != null:
		tree_system.call("update_focus", camera.global_position, direction, force, now)
	elif world.props.has_method("_update_tree_lod"):
		world.props.call("_update_tree_lod", camera.global_position, force, direction)
	world.props.update_lights(camera.global_position, direction)


func _process(_delta: float) -> void:
	if shot_index < selected.size():
		settle += 1
		if settle < (12 if shot_index == 0 else 5):
			return
		var pose := selected[shot_index]
		var image := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute("user://tree-shots")
		var path := "user://tree-shots/%s-%s-%s-%s.png" % [tag, quality, mode, pose]
		assert(image.save_png(path) == OK)
		var report := _tree_counts()
		if tree_system != null:
			var entry: Dictionary = tree_system.get("entries")[TARGET_INDEX]
			report.target_lod = entry.lod
			report.target_previous = entry.from
		print("TREE_SHOT ", pose, " ", JSON.stringify(report), " ", ProjectSettings.globalize_path(path))
		shot_index += 1
		settle = 0
		if shot_index < selected.size():
			_frame_view(selected[shot_index])
		else:
			place_camera(295.0)
			_refresh(true)
		return
	var now := Time.get_ticks_usec()
	if bench_usec == 0:
		bench_usec = now
		tick_usec = now
		return
	frame_times.append((now - tick_usec) / 1000.0)
	tick_usec = now
	draw_total += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	triangle_total += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	if gpu_ms > 0.0:
		gpu_times.append(gpu_ms)
	if frame_times.size() == MOTION_FRAMES:
		frame_times.sort()
		gpu_times.sort()
		print("TREE_BENCH ", JSON.stringify({
			"fps": MOTION_FRAMES * 1000000.0 / (now - bench_usec),
			"p95_ms": frame_times[ceili(0.95 * MOTION_FRAMES) - 1],
			"scene_draws": draw_total / MOTION_FRAMES, "scene_primitives": triangle_total / MOTION_FRAMES,
			"gpu_p50_ms": null if gpu_times.is_empty() else gpu_times[mini(gpu_times.size() - 1, gpu_times.size() / 2)],
			"renderer": RenderingServer.get_current_rendering_method(),
		}))
		get_tree().quit()
		return
	if frame_times.size() == 1:
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	place_camera(295.0 + 155.0 * frame_times.size() / MOTION_FRAMES)
	_refresh(false)


# Frustum-centre visibility excludes occlusion and counts tree models, rather
# than shadow/probe render passes. Draws estimate the intersecting batches.
func _tree_counts() -> Dictionary:
	var visible_lods := [0, 0, 0]
	var estimated_draws := 0
	if tree_system != null:
		for entry: Dictionary in tree_system.get("entries"):
			var pose: Transform3D = entry.world
			if not entry.excluded and _in_view(pose.origin):
				visible_lods[entry.lod] += 1
	else:
		var marked: Array = world.props.get("_near_marked")
		for node: Node in world.props.get_children():
			if node is MultiMeshInstance3D and str(node.name).begins_with("TreeCanopy"):
				var mm: MultiMesh = node.multimesh
				for i in mm.instance_count:
					var pose := mm.get_instance_transform(i)
					if pose.basis.x.length_squared() > 0.01 and _in_view(pose.origin + node.global_position):
						visible_lods[2] += 1
		for entry: Dictionary in marked:
			var pose: Transform3D = entry.world
			if _in_view(pose.origin):
				visible_lods[0] += 1
	var root := tree_system if tree_system != null else world.props
	for node: Node in root.get_children():
		if node is MultiMeshInstance3D and _is_tree_batch(node):
			var instance: MultiMeshInstance3D = node
			var mm := instance.multimesh
			if mm.visible_instance_count != 0 and _bounds_in_view(instance):
				estimated_draws += mm.mesh.get_surface_count()
	return {"visible": visible_lods, "candidate_draws": estimated_draws}


func _in_view(p: Vector3) -> bool:
	return p.distance_squared_to(camera.global_position) < pow(float(Quality.p.props_dist) * 1.3, 2) and camera.is_position_in_frustum(p + Vector3.UP * 4.5)


func _is_tree_batch(node: Node) -> bool:
	return tree_system != null or str(node.name).begins_with("Tree")


func _bounds_in_view(node: MultiMeshInstance3D) -> bool:
	var bounds := node.global_transform * node.get_aabb()
	if node.visibility_range_end > 0 and bounds.get_center().distance_to(camera.global_position) > node.visibility_range_end + node.visibility_range_end_margin:
		return false
	for plane in camera.get_frustum():
		var test := bounds.get_support(-plane.normal)
		if plane.is_point_over(test):
			return false
	return true
