extends Node3D
## Boulevard furniture outside the race barriers, in a few spatial batches.
const Showcase := preload("res://scripts/world/tirana_showcase.gd")


func build(track: RaceTrack, reverse: bool, terrain: Terrain) -> void:
	var benches := []
	var posts := []
	var direction := -1.0 if reverse else 1.0
	for at: float in [42.0, 126.0, 181.0, 231.0, 316.0, 354.0, 422.0]:
		for side: float in [-1.0, 1.0]:
			var place := _placement(track, at, direction, side, 2.9)
			var p := place.origin
			if terrain.height_at(p.x, p.z) < p.y + 0.25:
				benches.append(place)
	for at: float in [Showcase.CROSSINGS.x, Showcase.CROSSINGS.y, Showcase.CROSSINGS.z]:
		for side: float in [-1.0, 1.0]:
			posts.append(_placement(track, at - side * 3.7, direction, side, 1.0))
	_add_batches(_bench(), benches, "BoulevardBenches")
	_add_batches(_crossing_post(), posts, "CrossingPosts")


func _placement(track: RaceTrack, at: float, direction: float, side: float, gap: float) -> Transform3D:
	var s := at * direction
	var tangent := track.tangent(s) * direction
	var right := Vector3(-tangent.z, 0, tangent.x).normalized()
	var street_side := right * side
	var position_on_walk := track.pos(s, direction * side * (track.half_w + gap))
	position_on_walk.y += 0.10 if gap > 2.0 else 0.07
	return Transform3D(Basis.looking_at(street_side if gap > 2.0 else tangent, Vector3.UP, true), position_on_walk)


func _add_batches(mesh: Mesh, placements: Array, label: String) -> void:
	for start in range(0, placements.size(), 6):
		var count := mini(6, placements.size() - start)
		var origin: Vector3 = placements[start + floori(count * 0.5)].origin
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = count
		for i in count:
			var placement: Transform3D = placements[start + i]
			placement.origin -= origin
			mm.set_instance_transform(i, placement)
		var node := MultiMeshInstance3D.new()
		node.name = label
		node.position = origin
		node.multimesh = mm
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visibility_range_end = 130.0 if Quality.preset == "low" else 210.0
		node.visibility_range_end_margin = 18.0
		add_child(node, true)


func _bench() -> ArrayMesh:
	var mesh := LandmarkKit.begin()
	var iron := Color("#303736")
	var timber := Color("#82603f")
	for x in [-0.72, 0.72]:
		LandmarkKit.box(mesh, Vector3(x, 0.22, 0.0), Vector3(0.085, 0.44, 0.39), iron)
		LandmarkKit.box(mesh, Vector3(x, 0.65, 0.20), Vector3(0.065, 0.47, 0.07), iron)
	for i in 4:
		LandmarkKit.box(mesh, Vector3(0.0, 0.46, -0.18 + i * 0.10),
			Vector3(1.82, 0.055, 0.088), timber.lightened(0.025 * i))
	for i in 3:
		LandmarkKit.box(mesh, Vector3(0.0, 0.62 + i * 0.10, 0.235),
			Vector3(1.82, 0.081, 0.045), timber)
	mesh.set_material(LandmarkKit.material())
	return mesh.commit()


func _crossing_post() -> ArrayMesh:
	var mesh := LandmarkKit.begin()
	var steel := Color("#737c7e")
	LandmarkKit.tube(mesh, Vector3.ZERO, Vector3.UP * 2.54, 0.037, 0.033, steel, 6)
	LandmarkKit.box(mesh, Vector3(0, 2.24, 0), Vector3(0.62, 0.62, 0.052), Color("#245686"))
	var pale := Color("#e6e8dc")
	for side: float in [-1.0, 1.0]:
		var z := side * 0.028
		var facing := Vector3(0, 0, side)
		# A blue crossing plate with a white triangle and pedestrian pictogram.
		LandmarkKit.quad_facing(mesh, Vector3(-0.24, 2.02, z), Vector3(0.24, 2.02, z),
			Vector3(0, 2.47, z), Vector3(0, 2.47, z), pale, facing)
		z += side * 0.004
		var ink := Color("#23272a")
		LandmarkKit.box(mesh, Vector3(0.02, 2.31, z), Vector3(0.067, 0.067, 0.009), ink)
		LandmarkKit.box(mesh, Vector3(0, 2.215, z), Vector3(0.045, 0.123, 0.01), ink,
			Basis(Vector3.BACK, -0.29))
		for leg: float in [-1.0, 1.0]:
			LandmarkKit.box(mesh, Vector3(leg * 0.034, 2.10, z), Vector3(0.03, 0.13, 0.01), ink,
				Basis(Vector3.BACK, leg * 0.43))
	mesh.set_material(LandmarkKit.material(0.66))
	return mesh.commit()
