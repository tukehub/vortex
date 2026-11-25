extends Node3D
## Route-side seeds are baked against the shipped Vlorë geometry. A stable
## shuffled prefix in each cell controls density as the mobile budget changes.

const CELL := 64.
const PINE := 3
var _batches: Array[MultiMeshInstance3D] = []
var _materials: Array[ShaderMaterial] = []
var _pine_sites: Array[Transform3D] = []
var _pines := PineForestMultiMesh.new()
var _pine_count := -1


func build(terrain: Terrain = null) -> void:
	var sites := FileAccess.get_file_as_bytes("res://assets/cities/vlore/ground_cover.bin").to_float32_array()
	var groups := {}
	for i in range(0, sites.size(), 4):
		var at := Vector3(sites[i], sites[i+1], sites[i+2])
		var kind := int(sites[i+3])
		if terrain != null and kind != 2: # Promenade lawns sit on their own mesh.
			var ground := terrain.detail.height_at(at.x, at.z)
			if not is_nan(ground):
				at.y = ground
		var phase := fposmod(i * .1545085, 1.)
		var scale := .76 + .5 * fposmod(i * .1035534, 1.)
		var basis := Basis(Vector3.UP, phase * TAU)
		if kind == PINE:
			# Broader, open maritime crown and modest height beside the palms.
			basis = basis.scaled(Vector3(1.07, .82, 1.07) * scale)
			_pine_sites.append(Transform3D(basis, at))
			continue
		if kind == 2:
			basis = basis.scaled(Vector3(.84, .52, .84))
		var key := Vector3i(floori(at.x/CELL), int(kind == 1), floori(at.z/CELL))
		at -= Vector3(key.x+.5, 0, key.z+.5)*CELL
		if not groups.has(key):
			groups[key] = []
		groups[key].append([Transform3D(basis.scaled(Vector3.ONE * scale), at), Color(phase, scale-.5, float(kind == 2))])
	for tier in 2:
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/coastal_cover.gdshader")
		mat.set_shader_parameter("middle", tier == 1)
		mat.set_shader_parameter("sprays", preload("res://assets/foliage/tirana/leaf_sprays.png"))
		_materials.append(mat)
		var meshes := [_tuft(tier), _scrub(tier)]
		for key: Vector3i in groups:
			var items: Array = groups[key]
			# The cheaper tier is also more widely spaced.
			var count := items.size() if tier == 0 else ceili(items.size() * .28)
			var mm := TiranaTrees.make_batch_mesh(meshes[key.y], count)
			var box := AABB(items[0][0].origin, Vector3.ZERO)
			for j in count:
				mm.set_instance_transform(j, items[j][0])
				mm.set_instance_custom_data(j, items[j][1])
				box = box.expand(items[j][0].origin)
			mm.custom_aabb = box.grow(1.6)
			var node := MultiMeshInstance3D.new()
			node.position = Vector3(key.x+.5, 0, key.z+.5)*CELL
			node.multimesh = mm
			node.material_override = mat
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.visibility_range_end = (27. if tier == 0 else 80.) + mm.custom_aabb.size.length()*.5
			node.visibility_range_end_margin = 0.
			add_child(node)
			RaceReflections.hide_detail(node)
			_batches.append(node)
	_pines.name = "CoastalPines"
	add_child(_pines)
	Quality.budget_changed.connect(_apply_budget)
	_apply_budget()


func _apply_budget() -> void:
	var fraction := float(Quality.p.tree_mul) / (1. + .45 * Quality.pressure_stage)
	for mat in _materials:
		mat.set_shader_parameter("wind_m", Quality.p.tree_wind_m)
	for node in _batches:
		node.multimesh.visible_instance_count = roundi(node.multimesh.instance_count * fraction)
	var count := roundi(_pine_sites.size() * fraction)
	if count != _pine_count:
		_pines.build_forest(_pine_sites.slice(0, count))
		RaceReflections.hide_detail(_pines)
		_pine_count = count


static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, base: Color, tip: Color) -> void:
	# Upward-biased normals give slender foliage consistent two-sided lighting.
	st.set_normal(Vector3.UP)
	st.set_color(base)
	st.add_vertex(a)
	st.add_vertex(b)
	st.set_color(tip)
	st.add_vertex(c)


static func _tuft(tier: int) -> ArrayMesh:
	var st := LandmarkKit.begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = 734
	for i in (21 if tier == 0 else 7):
		var dir := Vector3(cos(i*2.4), 0, sin(i*2.4))
		var root := dir * rng.randf_range(.02,.24) - Vector3.UP*.025
		var half_width := dir.cross(Vector3.UP) * (.023 if tier == 0 else .048)
		var h := rng.randf_range(.17,.49)
		var end := root + Vector3.UP*h + dir*rng.randf_range(.12,.27)
		var leaf := Color(.078,.15,.045).lerp(Color(.37,.30,.12), rng.randf()*.6)
		if tier == 0:
			var bend := root + Vector3.UP*h*.7 + dir*.062
			_triangle(st, root-half_width, root+half_width, bend+half_width*.6, leaf.darkened(.52), leaf)
			_triangle(st, root-half_width, bend+half_width*.6, bend-half_width*.6, leaf.darkened(.35), leaf)
			_triangle(st, bend-half_width*.6, bend+half_width*.6, end, leaf, leaf.lightened(.12))
		else:
			_triangle(st, root-half_width, root+half_width, end, leaf.darkened(.42), leaf)
	return st.commit()


static func _scrub(tier: int) -> ArrayMesh:
	var st := LandmarkKit.begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = 881
	for i in (16 if tier == 0 else 5):
		# Tilted sprays overlap in depth to form low, irregular maquis crowns.
		var axis := Vector3(cos(i*2.4), 0, sin(i*2.4))
		var root := axis*rng.randf_range(.02,.18) - Vector3.UP*.02
		var tip := root + axis*rng.randf_range(.18,.49) + Vector3.UP*rng.randf_range(.34,.71)
		var span := axis.cross(Vector3.UP) * (.23 if tier == 0 else .37)
		var vertices := [root-span, root+span, tip+span, tip-span]
		var u := .5 if i%3 else .0
		var uvs := [Vector2(u+.002,.99), Vector2(u+.248,.99),
			Vector2(u+.248,.01), Vector2(u+.002,.01)]
		st.set_normal((Vector3.UP + axis*.32).normalized())
		st.set_color(Color(.68,.74,.55).lerp(Color(.91,.96,.78), rng.randf()))
		for j in [0, 2, 1, 0, 3, 2]:
			st.set_uv(uvs[j])
			st.add_vertex(vertices[j])
	return st.commit()
