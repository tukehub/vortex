extends Node3D
## Vlorë: Kuzum Baba on its hill, and the start/finish on the straight
## Bulevardi Ismail Qemali 100 m before the circuit passes the Kuzum Baba park.

var failures := 0
## OSM: the Kuzum Baba park (leisure=park, way 1222923148) in local metres.
const PARK := Vector2(189.9, -2580.9)
## The temple's mapped outline (way 1222923149), now drawn by the model.
const TEMPLE_FOOTPRINT := [Vector2(293.52, -2585.59), Vector2(294.6, -2577.69), Vector2(291.9, -2577.33),
	Vector2(289.33, -2575.36), Vector2(289.79, -2570.54), Vector2(291.9, -2568.42), Vector2(295.81, -2568.94),
	Vector2(297.26, -2558.36), Vector2(319.26, -2561.34), Vector2(315.54, -2588.57)]

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("CHECK FAILED: " + message)


func _ready() -> void:
	Quality.set_preset("medium")
	for reverse in [false, true]:
		var track := RaceTrack.load_city("vlore", reverse)
		# Straight street at the line: over the grid behind it and the run past.
		var tightest := INF
		var s := -40.0
		while s <= 40.0:
			var k := absf(track.curv(s))
			tightest = minf(tightest, 1.0 / k if k > 1e-6 else INF)
			s += 2.0
		check(tightest >= 150.0, "the start/finish sits on a straight (tightest radius %.0f m, reverse=%s)" % [tightest, reverse])
		if not reverse:
			# Where the road passes the park (its centre is ~180 m off the road).
			# The lap passes it twice, out and back a carriageway apart: the
			# line belongs to the first pass.
			var dists := PackedFloat32Array()
			var best := INF
			var probe := 0.0
			while probe < track.L:
				var p := track.pos(probe, 0.0)
				dists.append(Vector2(p.x - PARK.x, p.z - PARK.y).length())
				best = minf(best, dists[-1])
				probe += 2.0
			var k := 0
			while dists[k] > best + 20.0:
				k += 1
			while k + 1 < dists.size() and dists[k + 1] < dists[k]:
				k += 1
			var at := k * 2.0
			check(at > 88.0 and at < 112.0, "the line is 100 m before the road passes Kuzum Baba (%.0f m)" % at)
			# On the outbound carriageway, 6 m west of the boulevard's mapped centre.
			var line := track.pos(0.0, 0.0)
			check(Vector2(line.x - 14.3, line.z + 2720.2).length() < 3.0, "the line is on Bulevardi Ismail Qemali")
	# The landmarks on the hill.
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cities/vlore/props.json"))
	var ids := {}
	for lm: Dictionary in data.landmarks:
		ids[lm.id] = lm
	check(ids.has("kuzum_baba_tekke") and ids.has("kuzum_baba_turbe"), "Kuzum Baba's temple and tomb are Vlorë landmarks")
	check(float(ids.kuzum_baba_tekke.y) > 75.0, "the temple stands on the summit")
	for tree: Array in data.trees:
		for id in ["kuzum_baba_tekke", "kuzum_baba_turbe"]:
			var lm: Dictionary = ids[id]
			var half := 25.0 if id == "kuzum_baba_tekke" else 9.0
			if absf(float(tree[0]) - float(lm.x)) <= half and absf(float(tree[2]) - float(lm.z)) <= half:
				check(false, "no tree grows inside %s" % id)
	var terrain := Terrain.new()
	add_child(terrain)
	terrain.load_city("vlore", null)
	var props := Props.new()
	add_child(props)
	props.load_city("vlore", terrain)
	var temple := props.find_child("KuzumBabaTemple", true, false) as MeshInstance3D
	var turbe := props.find_child("KuzumBabaTurbe", true, false) as MeshInstance3D
	check(temple != null and turbe != null, "both are built")
	if temple != null:
		var size := temple.mesh.get_aabb().size
		check(size.x > 50.0 and size.y > 13.0, "the temple, its towers and its terrace wall (%s)" % size)
		var facade := -(temple.get_parent().get_parent() as Node3D).global_basis.z
		check(facade.x < -0.95, "the temple's facade faces west, down the hill (%s)" % facade)
	# The mapped temple block is gone from the generic buildings.
	var buildings := Buildings.new()
	add_child(buildings)
	buildings.load_city("vlore")
	var inside := 0
	for mi in buildings.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		var origin := (mi as MeshInstance3D).global_position
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for t in range(0, idx.size(), 3):
				var c := (v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0 + origin
				if Geometry2D.is_point_in_polygon(Vector2(c.x, c.z), PackedVector2Array(TEMPLE_FOOTPRINT)):
					inside += 1
	check(inside == 0, "no generic building inside the temple's footprint (%d triangles)" % inside)
	print("VLORE KUZUM BABA: failures=%d" % failures)
	get_tree().quit(1 if failures else 0)
