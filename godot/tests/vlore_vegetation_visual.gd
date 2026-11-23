extends "res://tests/vlore_architecture_visual.gd"
## Stable production-world views and submitted frame counters. The two street
## cameras are the same ones used in the architecture comparison.

var sites := VIEWS.duplicate()
var preset := "medium"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("quality="):
			preset = arg.substr(8)
	Quality.set_preset(preset)
	Quality.apply_viewport(get_viewport())
	world.city_id = "vlore"
	world.env_id = "day"
	add_child(world)
	add_child(camera)
	camera.fov = 65
	camera.far = 4500
	camera.make_current()
	var eye := Vector3(-226, 0, -1141)
	eye.y = world.terrain.height_at(eye.x, eye.z) + 1.8
	sites["promenade"] = [eye, eye + Vector3(54, 2.8, 27)]
	eye = Vector3(-62, 0, 829)
	eye.y = world.terrain.height_at(eye.x, eye.z) + 2.0
	sites["hillside"] = [eye, eye + Vector3(-40, 7, -34)]
	eye = Vector3(-19, 0, 823)
	eye.y = world.terrain.height_at(eye.x, eye.z) + 1.65
	sites["scrub"] = [eye, eye + Vector3(39, 8, -14)]


func _process(_dt: float) -> void:
	var key: String = sites.keys()[frame / 12]
	var view: Array = sites[key]
	camera.position = view[0]
	camera.look_at(view[1])
	world.sky.follow(camera.position)
	world.props.update_vegetation(camera.position, -camera.basis.z)
	frame += 1
	if frame % 12 != 0:
		return
	var done := frame == sites.size() * 12
	if done:
		set_process(false)
	await RenderingServer.frame_post_draw
	var dir := "user://vegetation/"
	DirAccess.make_dir_recursive_absolute(dir)
	if get_viewport().get_texture().get_image().save_png(dir + key + ".png") != OK:
		get_tree().quit(1)
		return
	var counts := _counts()
	print("VEGETATION ", JSON.stringify({"site": key, "quality": preset, "instances": counts,
		"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}))
	if done:
		get_tree().quit()


## Cover counts include every instance submitted by an intersecting batch.
## Tree counts use crown centres in the frustum and omit occlusion.
func _counts() -> Dictionary:
	var counts := {"near": 0, "middle": 0, "tree_centres": 0, "pines_planted": 0}
	var props := world.props
	if props.vegetation:
		for entry in props.vegetation.entries:
			if not entry.excluded and camera.is_position_in_frustum(entry.world.origin + Vector3.UP*4.):
				counts.tree_centres += 1
	else:
		for child in props.get_children():
			if child is MultiMeshInstance3D and str(child.name).begins_with("TreeCanopy"):
				for i in child.multimesh.instance_count:
					var pos: Vector3 = child.to_global(child.multimesh.get_instance_transform(i).origin)
					if camera.is_position_in_frustum(pos + Vector3.UP*4.):
						counts.tree_centres += 1
	var cover := props.get_node_or_null("CoastalVegetation")
	if not cover:
		return counts
	counts.pines_planted = cover.get_node("CoastalPines").planted_transforms.size()
	var planes := camera.get_frustum()
	for node in cover.get_children():
		if not node is MultiMeshInstance3D:
			continue
		var box: AABB = node.global_transform * node.multimesh.custom_aabb
		if camera.global_position.distance_to(box.get_center()) > node.visibility_range_end:
			continue
		var culled := false
		for plane in planes:
			if plane.is_point_over(box.get_support(-plane.normal)):
				culled = true
				break
		if not culled:
			var key := "middle" if node.material_override.get_shader_parameter("middle") else "near"
			counts[key] += node.multimesh.visible_instance_count
	return counts
