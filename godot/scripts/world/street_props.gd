class_name StreetProps
extends Node3D
## Street furniture from OpenStreetMap (plan 3.4): traffic lights, bus stops,
## benches, bins and bollards from props.json "street"
## (tools/pipeline/street_props.py). Each kind is one small procedural mesh
## (vertex colours, original, under MAX_TRIANGLES) drawn by one
## MultiMeshInstance3D per CHUNK-metre square, so the visibility range culls
## what is out of reach instead of a whole city's worth at once.
##
## Traffic lights are the exception: a supplied model (DETAILED_MESH, built
## by tools/build_traffic_light.gd) within NEAR_RANGE, the procedural
## stand-in beyond, one node pair per pole.
##
## Models look down -Z: the pipeline's yaw turns that front toward the road.
## Low quality and pressure stage 2+ keep only the lights and stops
## (Quality.p.street_small); every range is capped by Quality.p.props_dist.

const KINDS: Array[String] = ["traffic_light", "bus_stop", "bench", "bin", "bollard"]
## Small kinds disappear first under pressure.
const SMALL: Array[String] = ["bench", "bin", "bollard"]
const CHUNK := 250.0
const MAX_TRIANGLES := 500
## How far each kind is drawn, before the quality cap.
const RANGE := {"traffic_light": 450.0, "bus_stop": 350.0, "bench": 160.0, "bin": 140.0, "bollard": 140.0}
## Kinds drawn from a supplied model near the camera and the procedural
## stand-in beyond NEAR_RANGE, one node pair per item (few, tall, and seen
## from far away, so per-item ranges beat 250 m chunks switching at once).
const DETAILED_MESH := {"traffic_light": "res://assets/props/traffic_light/traffic_light.res"}
const NEAR_RANGE := 130.0
const NEAR_MAX_TRIANGLES := 8000

var counts := {}
## kind -> [Transform3D] in world space, as placed (headless renderers keep no
## MultiMesh data to read back).
var placed := {}
## kind -> [MultiMeshInstance3D]
var chunks := {}
## kind -> [{"near": MeshInstance3D, "far": MeshInstance3D}] for DETAILED_MESH kinds.
var detailed := {}
var meshes := {}
var near_meshes := {}
var _body: StandardMaterial3D
var _glass: StandardMaterial3D
var _lamp: StandardMaterial3D


func _ready() -> void:
	Quality.budget_changed.connect(_apply_budget)


## street: {kind: [[x, z, yaw], ...]}; heights from the terrain.
func build(street: Dictionary, height_at: Callable) -> void:
	_make_materials()
	for kind in KINDS:
		counts[kind] = 0
		chunks[kind] = []
		placed[kind] = []
		var rows: Array = street.get(kind, [])
		if rows.is_empty():
			continue
		meshes[kind] = make_mesh(kind)
		if DETAILED_MESH.has(kind) and ResourceLoader.exists(DETAILED_MESH[kind]):
			near_meshes[kind] = load(DETAILED_MESH[kind])
			_build_detailed(kind, rows, height_at)
			continue
		var buckets := {}
		for row in rows:
			var x := float(row[0])
			var z := float(row[1])
			var key := Vector2i(floori(x / CHUNK), floori(z / CHUNK))
			if not buckets.has(key):
				buckets[key] = []
			var basis := Basis(Vector3.UP, float(row[2]))
			var t := Transform3D(basis, Vector3(x, float(height_at.call(x, z)), z))
			buckets[key].append(t)
			placed[kind].append(t)
		var keys := buckets.keys()
		keys.sort()
		for key: Vector2i in keys:
			var origin := Vector3((key.x + 0.5) * CHUNK, 0.0, (key.y + 0.5) * CHUNK)
			var list: Array = buckets[key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = meshes[kind]
			mm.instance_count = list.size()
			var y := 0.0
			for t: Transform3D in list:
				y += t.origin.y
			origin.y = y / list.size()
			for i in list.size():
				var t: Transform3D = list[i]
				mm.set_instance_transform(i, Transform3D(t.basis, t.origin - origin))
			var node := MultiMeshInstance3D.new()
			node.name = "%s_%d_%d" % [kind, key.x, key.y]
			node.multimesh = mm
			node.position = origin
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(node)
			chunks[kind].append(node)
			counts[kind] += list.size()
	_apply_budget()


func _build_detailed(kind: String, rows: Array, height_at: Callable) -> void:
	detailed[kind] = []
	for i in rows.size():
		var row: Array = rows[i]
		var x := float(row[0])
		var z := float(row[1])
		var t := Transform3D(Basis(Vector3.UP, float(row[2])), Vector3(x, float(height_at.call(x, z)), z))
		placed[kind].append(t)
		var pair := {}
		for which in ["near", "far"]:
			var node := MeshInstance3D.new()
			node.name = "%s_%d_%s" % [kind, i, which]
			node.mesh = near_meshes[kind] if which == "near" else meshes[kind]
			node.transform = t
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(node)
			pair[which] = node
		detailed[kind].append(pair)
	counts[kind] = rows.size()


func _apply_budget() -> void:
	var cap := float(Quality.p.props_dist)
	var small := bool(Quality.p.get("street_small", true))
	for kind in chunks:
		var shown: bool = small or not kind in SMALL
		# Ranges are measured to the chunk's centre: add its half diagonal.
		var reach := minf(float(RANGE[kind]), cap) + CHUNK * 0.71
		for node: MultiMeshInstance3D in chunks[kind]:
			node.visible = shown
			node.visibility_range_end = reach
			node.visibility_range_end_margin = 30.0
	# The supplied model within NEAR_RANGE, the stand-in beyond it; low quality
	# and pressure stage 2+ draw the stand-in all the way.
	var near_ok := bool(Quality.p.get("street_detail", true))
	var shadows := bool(Quality.p.get("car_shadows", false))
	for kind in detailed:
		var far_end := minf(float(RANGE[kind]), cap)
		for pair: Dictionary in detailed[kind]:
			var near: MeshInstance3D = pair.near
			var far: MeshInstance3D = pair.far
			near.visible = near_ok
			near.visibility_range_end = NEAR_RANGE
			near.visibility_range_end_margin = 8.0
			near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			far.visibility_range_begin = NEAR_RANGE if near_ok else 0.0
			far.visibility_range_begin_margin = 8.0
			far.visibility_range_end = far_end
			far.visibility_range_end_margin = 30.0


func _make_materials() -> void:
	if _body != null:
		return
	_body = StandardMaterial3D.new()
	_body.vertex_color_use_as_albedo = true
	_body.roughness = 0.7
	# Cylinders are wound either way; these meshes are a few hundred triangles.
	_body.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glass = StandardMaterial3D.new()
	_glass.albedo_color = Color(0.62, 0.74, 0.8, 0.35)
	_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass.roughness = 0.08
	_glass.metallic_specular = 0.9
	_lamp = StandardMaterial3D.new()
	_lamp.vertex_color_use_as_albedo = true
	_lamp.emission_enabled = true
	_lamp.emission = Color(0.05, 1.0, 0.35)
	_lamp.emission_energy_multiplier = 1.8
	# Props._box winds its faces for a cull-free material, like the body's.
	_lamp.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glass.cull_mode = BaseMaterial3D.CULL_DISABLED


static func triangles(mesh: ArrayMesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		n += (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


func make_mesh(kind: String) -> ArrayMesh:
	_make_materials()
	var mesh := ArrayMesh.new()
	var body := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	var extra := SurfaceTool.new()
	extra.begin(Mesh.PRIMITIVE_TRIANGLES)
	var extra_mat: Material = null
	var steel := Color(0.22, 0.24, 0.26)
	match kind:
		"traffic_light":
			# The far stand-in for DETAILED_MESH (tools/build_traffic_light.gd):
			# its outline at the same size. Pole on the kerb, mast arm out over
			# the road (+X) at 6.3 m, two yellow-backed heads facing -Z with
			# about 5 m clearance, a low head on the pole, a street lamp on top.
			var galv := Color(0.46, 0.48, 0.5)
			var yellow := Color(0.66, 0.53, 0.0)
			var dark := Color(0.06, 0.06, 0.065)
			_cyl(body, Vector3.ZERO, 0.13, 8.0, 8, galv)
			Props._box(body, Vector3(4.35, 6.35, 0), Vector3(8.7, 0.14, 0.14), galv)
			Props._box(body, Vector3(1.5, 7.9, 0), Vector3(3.0, 0.08, 0.08), galv)
			Props._box(body, Vector3(3.05, 7.82, 0), Vector3(0.6, 0.1, 0.25), dark)
			for head in [Vector3(4.74, 5.55, 0), Vector3(8.17, 5.73, 0)]:
				Props._box(body, head + Vector3(0, 0, 0.12), Vector3(0.6, 1.1, 0.04), yellow)
				Props._box(body, head, Vector3(0.36, 0.95, 0.22), dark)
				Props._box(body, head + Vector3(0, 0.3, -0.12), Vector3(0.2, 0.2, 0.03), Color(0.35, 0.06, 0.05))
				Props._box(body, head + Vector3(0, 0.0, -0.12), Vector3(0.2, 0.2, 0.03), Color(0.35, 0.25, 0.05))
				Props._box(extra, head + Vector3(0, -0.3, -0.12), Vector3(0.2, 0.2, 0.03), Color(0.02, 0.55, 0.22))
			Props._box(body, Vector3(0, 3.4, -0.2), Vector3(0.3, 0.85, 0.24), dark)
			Props._box(extra, Vector3(0, 3.15, -0.33), Vector3(0.16, 0.16, 0.03), Color(0.02, 0.55, 0.22))
			extra_mat = _lamp
		"bus_stop":
			# Shelter open toward the road (-Z): roof, back and side glass,
			# a bench inside and a stop sign at the kerb end.
			var frame := Color(0.3, 0.33, 0.36)
			for x in [-1.6, 1.6]:
				for z in [-0.6, 0.6]:
					Props._box(body, Vector3(x, 1.25, z), Vector3(0.08, 2.5, 0.08), frame)
			Props._box(body, Vector3(0, 2.55, 0), Vector3(3.5, 0.12, 1.6), Color(0.85, 0.86, 0.88))
			Props._box(body, Vector3(0, 0.45, 0.35), Vector3(2.6, 0.06, 0.4), Color(0.55, 0.38, 0.22))
			Props._box(body, Vector3(-1.0, 0.22, 0.35), Vector3(0.06, 0.44, 0.35), frame)
			Props._box(body, Vector3(1.0, 0.22, 0.35), Vector3(0.06, 0.44, 0.35), frame)
			Props._box(body, Vector3(0, 0.03, 0), Vector3(3.6, 0.06, 1.7), Color(0.55, 0.55, 0.53))
			_cyl(body, Vector3(-2.2, 0, -0.5), 0.04, 2.6, 6, frame)
			Props._box(body, Vector3(-2.2, 2.35, -0.5), Vector3(0.5, 0.5, 0.04), Color(0.1, 0.35, 0.75))
			Props._box(body, Vector3(-2.2, 2.35, -0.53), Vector3(0.28, 0.28, 0.02), Color(0.95, 0.95, 0.95))
			Props._box(extra, Vector3(0, 1.4, 0.6), Vector3(3.2, 2.1, 0.03), Color.WHITE)
			Props._box(extra, Vector3(-1.6, 1.4, 0), Vector3(0.03, 2.1, 1.2), Color.WHITE)
			Props._box(extra, Vector3(1.6, 1.4, 0), Vector3(0.03, 2.1, 1.2), Color.WHITE)
			extra_mat = _glass
		"bench":
			# Facing -Z: seat, backrest behind (+Z), two cast-iron ends.
			var wood := Color(0.5, 0.33, 0.18)
			var iron := Color(0.13, 0.14, 0.13)
			Props._box(body, Vector3(0, 0.44, 0), Vector3(1.8, 0.05, 0.42), wood)
			Props._box(body, Vector3(0, 0.72, 0.22), Vector3(1.8, 0.09, 0.04), wood)
			Props._box(body, Vector3(0, 0.88, 0.24), Vector3(1.8, 0.09, 0.04), wood)
			for x in [-0.8, 0.8]:
				Props._box(body, Vector3(x, 0.22, 0), Vector3(0.06, 0.44, 0.44), iron)
				Props._box(body, Vector3(x, 0.66, 0.22), Vector3(0.06, 0.5, 0.05), iron)
		"bin":
			_cyl(body, Vector3.ZERO, 0.24, 0.85, 8, Color(0.16, 0.3, 0.2))
			_cyl(body, Vector3(0, 0.85, 0), 0.27, 0.06, 8, Color(0.12, 0.13, 0.13))
			_cyl(body, Vector3(0, 0, 0), 0.05, 0.02, 4, Color(0.12, 0.13, 0.13))
		"bollard":
			_cyl(body, Vector3.ZERO, 0.1, 0.9, 8, Color(0.25, 0.26, 0.27))
			_cyl(body, Vector3(0, 0.7, 0), 0.105, 0.08, 8, Color(0.95, 0.95, 0.9))
	body.commit(mesh)
	mesh.surface_set_material(0, _body)
	if extra_mat != null:
		extra.commit(mesh)
		mesh.surface_set_material(1, extra_mat)
	return mesh


## Upright closed cylinder standing on `base`.
static func _cyl(st: SurfaceTool, base: Vector3, r: float, h: float, sides: int, col: Color) -> void:
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
		var n0 := Vector3(cos(a0), 0, sin(a0))
		var n1 := Vector3(cos(a1), 0, sin(a1))
		var up := Vector3(0, h, 0)
		for v in [[p0, n0], [p1 + up, n1], [p1, n1], [p0, n0], [p0 + up, n0], [p1 + up, n1]]:
			st.set_normal(v[1])
			st.set_color(col)
			st.add_vertex(base + v[0])
		for v in [up, p1 + up, p0 + up]:
			st.set_normal(Vector3.UP)
			st.set_color(col)
			st.add_vertex(base + v)
