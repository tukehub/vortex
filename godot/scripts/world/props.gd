class_name Props
extends Node3D
## Street lamps, trees and landmark placeholders from <city>/props.json.
## Lamps along the track get real OmniLights (nearest N to the player, from
## the quality preset); the rest are emissive meshes only.

const TREE_CHUNK_SIZE := 400.0
## Cities whose mapped trees use the three-LOD street trees shared with Tirana.
const STREET_TREE_CITIES := ["tirane", "vlore", "shkoder"]
var track_lamps: Array = []          # [x,y,z,yaw]
var lights: Array[OmniLight3D] = []
var light_slots := 0
var lamp_emis: StandardMaterial3D
var night := 1.0
var _tirana := false
var _showcase_lamp_heads := {}
const TIRANA_LAMP_REACH := 2.3
const Showcase := preload("res://scripts/world/tirana_showcase.gd")
var landmarks: Array = []
## OSM street furniture (3.4); null when the city has none.
var street: StreetProps
## props.json "road_marks": {"crossings": [[x, z, width, inferred], ...]}.
var road_marks := {}

var vegetation: TiranaTrees


func load_city(city_id: String, terrain: Terrain, track: RaceTrack = null, reverse := false) -> void:
	var path := "res://assets/cities/%s/props.json" % city_id
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		return
	var p: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	_tirana = city_id == "tirane"
	track_lamps = p.get("track_lamps", [])
	if track != null and track.PAIR.size() == track.M:
		# The baked lamps down a divider, or between a roundabout's
		# carriageways, now stand on open tarmac (Vlorë): keep it clear.
		track_lamps = track_lamps.filter(func(l: Array) -> bool: return not in_open_road(track, float(l[0]), float(l[2])))
	landmarks = p.get("landmarks", [])
	road_marks = p.get("road_marks", {})
	var models := Landmarks.new()
	add_child(models)
	models.load_anchors(landmarks, terrain)
	# Café terraces wherever the city's props list them (Blloku, Lungomare).
	var cafes: Array = p.get("cafes", [])
	if not cafes.is_empty():
		var terraces := preload("res://scripts/world/blloku_cafes.gd").new()
		terraces.name = "BllokuCafes"
		add_child(terraces)
		terraces.build(cafes)
	# Palms along a seafront promenade (Vlorë's Lungomare).
	var palms: Array = p.get("palms", [])
	if not palms.is_empty():
		var grove := Palms.new()
		add_child(grove)
		grove.build(palms)
	# Lungomare's paving and lawns.
	var front: Dictionary = p.get("seafront", {})
	if not front.is_empty():
		var promenade := SeafrontPromenade.new()
		add_child(promenade)
		var clear := []
		for anchor in landmarks:
			clear.append([float(anchor.x), float(anchor.z)])
		promenade.build(front, terrain, clear)
	_build_lamps(p.get("lamps", []), track_lamps, track if _tirana else null, reverse)
	var furniture: Dictionary = p.get("street", {})
	if not furniture.is_empty():
		street = StreetProps.new()
		street.name = "StreetProps"
		add_child(street)
		street.build(furniture, terrain.height_at)
	var trees: Array = p.get("trees", [])
	if city_id == "vlore" and p.has("tree_exclusions"):
		# Indices are baked in ascending order. Removing from the end keeps
		# the original mapped anchors available for future road/building bakes.
		trees = trees.duplicate()
		var excluded: Array = p.tree_exclusions
		for i in range(excluded.size() - 1, -1, -1):
			trees.remove_at(int(excluded[i]))
	_build_trees(trees, terrain, city_id)
	if city_id == "vlore":
		var cover := preload("res://scripts/world/coastal_cover.gd").new()
		cover.name = "CoastalVegetation"
		add_child(cover)
		cover.build(terrain)
	if _tirana and track != null and terrain != null:
		var showcase_street := preload("res://scripts/world/showcase_street_props.gd").new()
		showcase_street.name = "TiranaStreetProps"
		add_child(showcase_street)
		showcase_street.build(track, reverse, terrain, furniture.get("bench", []))
		RaceReflections.hide_detail(showcase_street)
	light_slots = int(Quality.p.lamp_lights)
	for i in light_slots:
		var l := OmniLight3D.new()
		l.light_color = Color("#ffe2b5") if _tirana else Color(1.0, 0.82, 0.55)
		l.light_energy = 0.0
		l.omni_range = 18.5 if _tirana else 22.0
		l.omni_attenuation = 1.25 if _tirana else 1.6
		l.shadow_enabled = false
		l.light_specular = 0.6
		add_child(l)
		lights.append(l)
	Quality.budget_changed.connect(_apply_light_budget)


func _apply_light_budget() -> void:
	for i in lights.size():
		if i >= int(Quality.p.lamp_lights):
			lights[i].visible = false


func _lamp_mesh(tuned: bool) -> ArrayMesh:
	# pole (thin box) + head (emissive box), built as two surfaces
	var st := LandmarkKit.begin()
	if tuned:
		var steel := Color(0.21, 0.24, 0.24)
		LandmarkKit.tube(st, Vector3.ZERO, Vector3(0, 7.65, 0), 0.11, 0.052, steel, 6)
		LandmarkKit.tube(st, Vector3(0, 7.59, 0), Vector3(0, 8.0, 0.63), 0.053, 0.046, steel, 6)
		LandmarkKit.tube(st, Vector3(0, 8.0, 0.60), Vector3(0, 8.0, TIRANA_LAMP_REACH), 0.046, 0.035, steel, 6)
		LandmarkKit.box(st, Vector3(0, 7.98, TIRANA_LAMP_REACH), Vector3(0.49, 0.18, 0.83), steel)
		LandmarkKit.box(st, Vector3(0, 0.25, 0), Vector3(0.29, 0.5, 0.29), steel)
	else:
		_box(st, Vector3(0, 4.0, 0), Vector3(0.14, 8.0, 0.14), Color(0.25, 0.26, 0.28))
		_box(st, Vector3(0, 8.0, 1.2), Vector3(0.12, 0.12, 2.4), Color(0.25, 0.26, 0.28))
	var pole_mat := StandardMaterial3D.new()
	pole_mat.vertex_color_use_as_albedo = true
	pole_mat.roughness = 0.5
	pole_mat.metallic = 0.6
	st.set_material(pole_mat)
	var mesh := st.commit()
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	if tuned:
		LandmarkKit.box(st2, Vector3(0, 7.88, TIRANA_LAMP_REACH), Vector3(0.39, 0.045, 0.69), Color.WHITE)
	else:
		_box(st2, Vector3(0, 7.9, 2.3), Vector3(0.5, 0.22, 0.9), Color.WHITE)
	if lamp_emis == null:
		lamp_emis = StandardMaterial3D.new()
		lamp_emis.albedo_color = Color(0.9, 0.85, 0.7)
		lamp_emis.emission_enabled = true
		lamp_emis.emission = Color(1.0, 0.82, 0.55)
		lamp_emis.emission_energy_multiplier = 6.0
	st2.set_material(lamp_emis)
	st2.commit(mesh)
	return mesh


static func _box(st: SurfaceTool, c: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3(0, 0, 1), [Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]],
		[Vector3(0, 0, -1), [Vector3(1, -1, -1), Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1)]],
		[Vector3(1, 0, 0), [Vector3(1, -1, 1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1)]],
		[Vector3(-1, 0, 0), [Vector3(-1, -1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1)]],
		[Vector3(0, 1, 0), [Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(-1, 1, -1)]],
		[Vector3(0, -1, 0), [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, -1, 1)]],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var vs: Array = f[1]
		var quad: Array[Vector3] = []
		for v in vs:
			quad.append(c + Vector3(v.x * h.x, v.y * h.y, v.z * h.z))
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(quad[0])
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(quad[1])
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(quad[2])
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(quad[0])
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(quad[2])
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(quad[3])


## True when (x, z) is on a joined road's tarmac, between the two passes.
static func in_joined_road(track: RaceTrack, x: float, z: float) -> bool:
	var at := track.locate_xz(x, z)
	var k := posmod(roundi(at.x / track.ds), track.M)
	if track.PAIR[k] < 0:
		return false
	var middle := track.JOIN[k]
	return absf(at.y - middle) < absf(middle) - track.half_w + 0.6


## True on a joined road's middle or a roundabout's apron: tarmac with no
## kerb between it and the lanes.
static func in_open_road(track: RaceTrack, x: float, z: float) -> bool:
	if in_joined_road(track, x, z):
		return true
	for isle: Vector3 in track.islands:
		var c := Vector2(isle.x, isle.y)
		var q := Vector2(x, z)
		var r := q.distance_to(c)
		if r > isle.z and r < 85.0 and r < RoadMesh.apron_reach(track, c, isle.z, (q - c).angle()) - 0.6:
			return true
	return false


func _build_lamps(lamps: Array, tl: Array, track: RaceTrack, reverse: bool) -> void:
	var basic: Array[Transform3D] = []
	var detail: Array[Transform3D] = []
	for lamp: Array in lamps + tl:
		var yaw := float(lamp[3]) if lamp.size() > 3 else 0.0
		var pos := Vector3(lamp[0], lamp[1], lamp[2])
		var transform := Transform3D(Basis(Vector3.UP, yaw), pos)
		if track != null and track.nearest(pos.x, pos.z, 34.0) >= 0:
			var at := track.locate_xz(pos.x, pos.z).x
			if Showcase.forward_s(track, at, reverse) <= Showcase.LENGTH:
				var toward := track.pos(at, 0.0) - pos
				var aim := Basis(Vector3.UP, atan2(toward.x, toward.z))
				detail.append(Transform3D(aim, pos))
				_showcase_lamp_heads[pos] = pos + aim * Vector3(0.0, 7.65, TIRANA_LAMP_REACH)
				continue
		basic.append(transform)
	_lamp_batch(_lamp_mesh(false), basic, Vector3.ZERO, float(Quality.p.props_dist), "StreetLamps")
	if not detail.is_empty():
		var origin := track.pos(Showcase.LENGTH * (-0.5 if reverse else 0.5), 0.0)
		_lamp_batch(_lamp_mesh(true), detail, origin, 405.0, "ShowcaseLamps")


func _lamp_batch(mesh: Mesh, transforms: Array[Transform3D], origin: Vector3, reach: float, label: String) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		var instance := transforms[i]
		instance.origin -= origin
		mm.set_instance_transform(i, instance)
	var node := MultiMeshInstance3D.new()
	node.name = label
	node.position = origin
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = reach
	node.visibility_range_end_margin = 60.0
	add_child(node)


func _tree_meshes() -> Array:
	# Crossed photographic cutouts provide volume at a small geometry cost.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for angle in [0.0, PI * 0.5]:
		var axis := Vector3(cos(angle), 0.0, sin(angle)) * 2.7
		var points := [-axis, axis, axis + Vector3.UP * 8.4, -axis + Vector3.UP * 8.4]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for index in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3(-sin(angle), 0.0, cos(angle)))
			st.set_uv(uvs[index])
			st.add_vertex(points[index])
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://assets/foliage/photographic_tree.png")
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.25
	# MSAA (medium/high) resolves cut-out leaf edges only through coverage.
	material.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	st.set_material(material)
	return [st.commit()]


func _build_trees(trees: Array, terrain: Terrain, city_id: String) -> void:
	var keep := int(trees.size() * float(Quality.p.tree_mul))
	if city_id in STREET_TREE_CITIES:
		vegetation = TiranaTrees.new()
		vegetation.name = {"tirane": "TiranaTrees", "vlore": "CoastalStreetTrees"}.get(city_id, "StreetTrees")
		add_child(vegetation)
		vegetation.build(trees.slice(0, keep), terrain)
		return
	var mesh: Mesh = _tree_meshes()[0]
	# Keep spatial batches so the renderer culls distant cutout trees.
	var chunks := {}
	for i in keep:
		var t: Array = trees[i]
		var sc := float(t[3])
		var y := float(t[1])
		if terrain:
			y = terrain.height_at(float(t[0]), float(t[2]))
		var breadth := 0.91 + 0.18 * (0.5 + 0.5 * sin(float(i) * 2.31))
		var height := 0.94 + 0.12 * (0.5 + 0.5 * sin(float(i) * 1.73))
		var basis := Basis(Vector3.UP, float(i) * 1.37).scaled(Vector3(sc * breadth, sc * height, sc * (2.0 - breadth)))
		var key := Vector2i(floori(float(t[0]) / TREE_CHUNK_SIZE), floori(float(t[2]) / TREE_CHUNK_SIZE))
		if not chunks.has(key):
			chunks[key] = []
		var origin := Vector3((key.x + 0.5) * TREE_CHUNK_SIZE, 0, (key.y + 0.5) * TREE_CHUNK_SIZE)
		var world_pos := Vector3(float(t[0]), y, float(t[2]))
		chunks[key].append(Transform3D(basis, world_pos - origin))
	for key: Vector2i in chunks:
		var origin := Vector3((key.x + 0.5) * TREE_CHUNK_SIZE, 0, (key.y + 0.5) * TREE_CHUNK_SIZE)
		_tree_chunk(mesh, chunks[key], origin, float(Quality.p.props_dist) * 1.3,
			Quality.preset == "high", "TreeCanopy")


func update_vegetation(camera_pos: Vector3, forward: Vector3) -> void:
	if vegetation != null:
		vegetation.update_focus(camera_pos, forward)


func _tree_chunk(mesh: Mesh, transforms: Array, origin: Vector3, distance: float, shadows: bool, node_name: String) -> MultiMeshInstance3D:
	if transforms.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.position = origin
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Include the chunk half-diagonal to avoid popping nearby trees at its edge.
	node.visibility_range_end = distance + TREE_CHUNK_SIZE * 0.71
	node.visibility_range_end_margin = 80.0
	add_child(node, true)
	return node


func set_night(n: float) -> void:
	night = n
	if lamp_emis:
		lamp_emis.emission_energy_multiplier = (3.3 if _tirana else 6.0) * n


## Move the real lights to the nearest lamps ahead of the player.
func update_lights(player_pos: Vector3, forward: Vector3) -> void:
	if lights.is_empty() or track_lamps.is_empty():
		return
	if night <= 0.05:
		# Daylight: the lamps are dark, so there is nothing to sort or move.
		if lights[0].visible:
			for l in lights:
				l.visible = false
		return
	var cand := []
	for l in track_lamps:
		var p := Vector3(l[0], l[1], l[2])
		var to := p - player_pos
		var dist := to.length()
		if dist > 140.0:
			continue
		# favour lamps ahead
		var ahead := to.normalized().dot(forward)
		var head: Vector3 = _showcase_lamp_heads.get(p, p + Vector3.UP * 7.7)
		cand.append([dist - ahead * 30.0, head])
	cand.sort_custom(func(a, b): return a[0] < b[0])
	for i in lights.size():
		var l := lights[i]
		if i < cand.size() and i < int(Quality.p.lamp_lights):
			var p: Vector3 = cand[i][1]
			l.global_position = p
			l.light_energy = (2.75 if _tirana else 2.2) * night
			l.visible = night > 0.05
		else:
			l.visible = false
