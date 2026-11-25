extends Node3D
## Vlorë seafront by the waterfront courts: rock armour along the waterline
## beside the race road, wet stone at the water, spray gated by quality.

var failures := 0


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("CHECK FAILED: " + message)


func _ready() -> void:
	Quality.set_preset("medium")
	var terrain := Terrain.new()
	add_child(terrain)
	terrain.load_city("vlore", null)
	check(terrain.has_water, "Vlorë has a baked sea")
	var sea := Sea.new()
	add_child(sea)
	check(sea.build(terrain, true), "sea accepts the shoreline grid")
	for preset in ["low", "medium", "high"]:
		Quality.set_preset(preset)
		check(sea.mesh.get_faces().size() / 3 == (2056 if preset == "high" else 2), "water triangle budget on " + preset)
	Quality.set_pressure_stage(1)
	check(sea.mesh == sea.flat_grid, "pressure drops vertex waves")
	Quality.set_preset("medium")
	var track := RaceTrack.load_city("vlore", false)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cities/vlore/props.json"))
	var anchors := []
	var courts := Vector2.ZERO
	var courts_yaw := 0.0
	for lm: Dictionary in data.landmarks:
		if SeaRocks.ANCHORS.has(lm.id):
			anchors.append({"x": lm.x, "z": lm.z, "yaw": lm.yaw, "radius": SeaRocks.ANCHORS[lm.id]})
			courts_yaw = deg_to_rad(float(lm.yaw))
			courts = Vector2(lm.x, lm.z)
	check(anchors.size() == 1, "the waterfront courts anchor the rock armour")
	var rocks := SeaRocks.new()
	add_child(rocks)
	rocks.build(terrain, track, anchors)
	check(rocks.stones > 300, "a revetment of stones lines the shore (%d)" % rocks.stones)
	check(rocks.stones == rocks.placed.size(), "every stone is recorded")
	check(RockField._scans.size() == 8 and rocks.field.chunks.size() > 4, "eight scans across independently culled chunks")
	var on_road := 0
	var far := 0
	var off_shore := 0
	var water := terrain.water_surface
	var tilted := 0
	var buried := 0
	var gravel := 0
	var in_footing := 0
	for xf in rocks.placed:
		var p := xf.origin
		var d := track.dist_to(p.x, p.z)
		tilted += int(xf.basis.y.normalized().dot(Vector3.UP) < .996)
		buried += int(p.y < terrain.surface_height_at(p.x, p.z))
		var width := xf.basis.x.length()
		gravel += int(width < RockField.MIN_ROCK)
		in_footing += int(SeaRocks.COURTS.overlaps_footing((Vector2(p.x, p.z) - courts).rotated(courts_yaw), width*.76))
		if d < track.half_w + 2.0:
			on_road += 1
		if d > SeaRocks.ROAD_REACH + 1.0:
			far += 1
		if absf(p.y - water) > 6.0 or Vector2(p.x, p.z).distance_to(courts) > SeaRocks.ANCHORS.waterfront_courts * 1.5:
			off_shore += 1
	check(on_road == 0 and in_footing == 0, "race road and court footings remain clear")
	check(far == 0, "stones only where the road runs by the sea (%d too far)" % far)
	check(off_shore == 0, "stones sit at the waterline near the courts (%d astray)" % off_shore)
	check(rocks.spray_points.size() > 35, "waves can break along the irregular revetment")
	check(buried == rocks.stones and tilted > 20 and gravel > 80, "scans settle into the slope among smaller gravel")
	terrain.set_env(.85, 0., 0.)
	check(is_equal_approx(rocks.field._material.get_shader_parameter("wetness"), .85), "weather reaches the common rock material")
	# Spray: bursts near the camera on medium, none on low (fx_extras off).
	var cam := rocks.spray_points[0] + Vector3(30, 3, 0)
	var bursts := 0
	for i in 40:
		if rocks.update(cam, 0.25):
			bursts += 1
	check(bursts > 0, "waves break into spray near the camera")
	for levels: Array in RockField._scans:
		var tris := []
		for mesh: ArrayMesh in levels:
			tris.append(mesh.get_faces().size() / 3)
		check(tris.size() == 3 and tris[0] <= 425 and tris[0] > tris[1] and tris[1] > tris[2] and tris[2] <= 108,
			"each scan has three budgeted meshes")
		var occlusion: PackedColorArray = levels[0].surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		check(Array(occlusion).any(func(c: Color) -> bool: return c.r < .78), "baked contact shading on each scan")
	# The same batch and transforms remain while its mesh and density change.
	var chunk: Dictionary = rocks.field.chunks.values()[0]
	var at: Vector2 = chunk.centre
	var probe: MultiMeshInstance3D = chunk.nodes[0].node
	var mm := probe.multimesh
	var lods := []
	for travel in [0., 101., 205.]:
		rocks.field.update_lods(Vector3(at.x + travel, 3., at.y))
		lods.append(chunk.lod)
		check(probe.multimesh == mm and mm.custom_aabb.has_volume() and mm.use_custom_data, "one bounded instanced draw per shape and chunk")
		check(probe.visibility_range_end == RockField.REACH, "chunk distance culling")
	check(lods == [0, 1, 2], "three distance LODs selected")
	rocks.field.update_lods(Vector3(at.x, 3., at.y))
	var full := mm.visible_instance_count
	var gravel_batches := 0
	for cell: Dictionary in rocks.field.chunks.values():
		for batch: Dictionary in cell.nodes:
			if batch.gravel:
				gravel_batches += 1
				check(batch.node.multimesh.mesh.get_faces().size() / 3 <= 40, "gravel uses the low-poly scan even up close")
	check(gravel_batches <= rocks.field.chunks.size(), "one coarse gravel batch per chunk")
	Quality.set_preset("low")
	var thinned := false
	for batch: Dictionary in chunk.nodes:
		var mesh_batch: MultiMeshInstance3D = batch.node
		thinned = thinned or mesh_batch.multimesh.visible_instance_count < mesh_batch.multimesh.instance_count
	check(thinned and full == mm.instance_count, "low quality drops gravel first")
	var low := 0
	for i in 40:
		if rocks.update(cam, 0.25):
			low += 1
	check(low == 0, "no spray when quality turns extras off")
	print("SEA ROCKS: stones=%d spray=%d failures=%d" % [rocks.stones, rocks.spray_points.size(), failures])
	get_tree().quit(1 if failures else 0)
