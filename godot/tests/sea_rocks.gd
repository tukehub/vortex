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
	var track := RaceTrack.load_city("vlore", false)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cities/vlore/props.json"))
	var anchors := []
	var courts := Vector2.ZERO
	for lm: Dictionary in data.landmarks:
		if SeaRocks.ANCHORS.has(lm.id):
			anchors.append({"x": lm.x, "z": lm.z, "radius": SeaRocks.ANCHORS[lm.id]})
			courts = Vector2(lm.x, lm.z)
	check(anchors.size() == 1, "the waterfront courts anchor the rock armour")
	var rocks := SeaRocks.new()
	add_child(rocks)
	rocks.build(terrain, track, anchors)
	check(rocks.stones > 300, "a revetment of stones lines the shore (%d)" % rocks.stones)
	check(rocks.stones == rocks.placed.size(), "every stone is recorded")
	check(rocks.get_child_count() >= SeaRocks.VARIANTS, "stone variants and the spray pool are built")
	var on_road := 0
	var far := 0
	var off_shore := 0
	var water := terrain.water_surface
	for xf in rocks.placed:
		var p := xf.origin
		var d := track.dist_to(p.x, p.z)
		if d < track.half_w + 2.0:
			on_road += 1
		if d > SeaRocks.ROAD_REACH + 1.0:
			far += 1
		if absf(p.y - water) > 6.0 or Vector2(p.x, p.z).distance_to(courts) > SeaRocks.ANCHORS.waterfront_courts * 1.5:
			off_shore += 1
	check(on_road == 0, "no stone on the race road (%d)" % on_road)
	check(far == 0, "stones only where the road runs by the sea (%d too far)" % far)
	check(off_shore == 0, "stones sit at the waterline near the courts (%d astray)" % off_shore)
	check(rocks.spray_points.size() > 50, "waves can break on the outer stones")
	# Spray: bursts near the camera on medium, none on low (fx_extras off).
	var cam := rocks.spray_points[0] + Vector3(30, 3, 0)
	var bursts := 0
	for i in 40:
		if rocks.update(cam, 0.25):
			bursts += 1
	check(bursts > 0, "waves break into spray near the camera")
	# Two levels of detail per chunk: the detailed stones only up close.
	var near_tris := 0
	var far_tris := 0
	for child in rocks.get_children():
		if child is MultiMeshInstance3D:
			var mmi := child as MultiMeshInstance3D
			if mmi.name.ends_with("near"):
				near_tris += mmi.multimesh.mesh.get_faces().size() / 3
				check(mmi.visibility_range_end <= SeaRocks.NEAR_LOD + 0.1, "detailed stones only near the camera")
			else:
				far_tris += mmi.multimesh.mesh.get_faces().size() / 3
				check(mmi.visibility_range_begin >= SeaRocks.NEAR_LOD - 0.1, "coarse stones take over further out")
				check(mmi.multimesh.mesh.get_faces().size() / 3 <= 40, "a coarse stone is a handful of triangles")
	check(near_tris > 0 and far_tris > 0, "both levels of detail are built")
	Quality.set_preset("low")
	var thinned := 0
	for child in rocks.get_children():
		if child is MultiMeshInstance3D:
			var mm := (child as MultiMeshInstance3D).multimesh
			if mm.visible_instance_count >= 0 and mm.visible_instance_count < mm.instance_count:
				thinned += 1
	check(thinned > 0, "low quality draws a thinner pile")
	var low := 0
	for i in 40:
		if rocks.update(cam, 0.25):
			low += 1
	check(low == 0, "no spray when quality turns extras off")
	print("SEA ROCKS: stones=%d spray=%d failures=%d" % [rocks.stones, rocks.spray_points.size(), failures])
	get_tree().quit(1 if failures else 0)
