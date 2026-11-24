class_name SeaRocks
extends Node3D
## Rock armour along the shore beside the race road (the seafront by Vlorë's
## waterfront courts): angular ochre limestone boulders, two staggered rows
## along the baked waterline, wet and dark where the waves reach; and spray
## thrown up off the rocks near the camera. After photographs of that shore.
##
## The waterline is the water mask's 127/128 contour (tools/pipeline/water.py),
## traced by marching squares in a window around each anchor, kept only where
## it runs within ROAD_REACH metres of the race road.

const SHADER := preload("res://shaders/sea_rock.gdshader")
const SPACING := 1.5           # metres between stones along the waterline
const ROAD_REACH := 140.0
const MAX_WALK := 30.0         # metres inland from the mask to the real waterline
const TOE := 1.6               # the pile runs this far out into the water
const PILE_MIN := 2.0
const PILE_MAX := 9.0          # metres up the bank, at most
const CREST := 3.0             # the pile stops this high above the water
const ROW_STEP := 1.15
const CHUNK := 96.0
const NEAR_LOD := 75.0        # chunk-centre distance where stones go coarse
const VISIBLE := 420.0
const VARIANTS := 4
const SPRAY_POOL := 3
const SPRAY_NEAR := 18.0
const SPRAY_FAR := 120.0
## Landmark id -> half-size (m) of the shore window armoured around it.
const ANCHORS := {"waterfront_courts": 420.0}

var stones := 0
## Every stone placed (MultiMesh data is not kept by the headless renderer).
var placed: Array[Transform3D] = []
## World positions of the outer-row stones, where spray can rise.
var spray_points := PackedVector3Array()
var _spray: Array[GPUParticles3D] = []
var _spray_t := 0.0
var _rng := RandomNumberGenerator.new()
var _mat: ShaderMaterial
var _multimeshes: Array[MultiMesh] = []


## `anchors`: [{x, z, radius}] windows of shore to armour.
func build(terrain: Terrain, track: RaceTrack, anchors: Array) -> void:
	_rng.seed = 7311
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("water_y", terrain.water_surface + 0.0)
	_mat.set_shader_parameter("grain", preload("res://assets/textures/limestone_diff.jpg"))
	_mat.set_shader_parameter("grain_n", preload("res://assets/textures/limestone_nor.jpg"))
	_mat.set_shader_parameter("grain_arm", preload("res://assets/textures/limestone_arm.jpg"))
	_mat.set_shader_parameter("detail", Quality.preset != "low")
	var meshes: Array[ArrayMesh] = []
	var far_mesh := _stone_mesh(0, 3, 5)
	for v in VARIANTS:
		meshes.append(_stone_mesh(v, 4, 7))
	var transforms := {}
	var level := _waterline_level(terrain)
	for anchor: Dictionary in anchors:
		for seg in _contour(terrain, Vector2(float(anchor.x), float(anchor.z)), float(anchor.radius)):
			_line_of_stones(seg[0], seg[1], terrain, track, level, transforms)
	# Keep shape variation close up. At distance the existing per-stone
	# rotations and scales vary one coarse shape in one draw per grid cell.
	var batches := transforms.duplicate()
	for key: Vector3i in transforms:
		var cell := Vector3i(-1, key.y, key.z)
		if not batches.has(cell):
			batches[cell] = []
		batches[cell].append_array(transforms[key])
		stones += transforms[key].size()
	for key: Vector3i in batches:
		var list: Array = batches[key]
		# Shuffled, so a reduced instance budget thins the pile evenly.
		var order := range(list.size())
		var shuffle := RandomNumberGenerator.new()
		shuffle.seed = hash(key)
		for i in range(order.size() - 1, 0, -1):
			var j := shuffle.randi_range(0, i)
			var tmp: int = order[i]
			order[i] = order[j]
			order[j] = tmp
		var centre := Vector3((key.y + 0.5) * CHUNK, 0.0, (key.z + 0.5) * CHUNK)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[key.x] if key.x >= 0 else far_mesh
		mm.instance_count = list.size()
		for i in list.size():
			var xf: Transform3D = list[order[i]]
			# Instances are placed relative to the chunk centre, so the
			# node sits there and visibility ranges measure from it.
			mm.set_instance_transform(i, Transform3D(xf.basis, xf.origin - centre))
		var node := MultiMeshInstance3D.new()
		node.name = "Stones_%d_%d_%d_%s" % [key.x, key.y, key.z, "near" if key.x >= 0 else "far"]
		node.multimesh = mm
		node.position = centre
		node.material_override = _mat
		if key.x >= 0:
			node.visibility_range_end = NEAR_LOD
			node.visibility_range_end_margin = 10.0
		else:
			node.visibility_range_begin = NEAR_LOD
			node.visibility_range_begin_margin = 10.0
			node.visibility_range_end = VISIBLE
			node.visibility_range_end_margin = 40.0
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_multimeshes.append(mm)
	if not Quality.budget_changed.is_connected(_apply_budget):
		Quality.budget_changed.connect(_apply_budget)
	_apply_budget()
	_make_spray()


## Low quality and heavy pressure draw a thinner pile (the shuffled share).
func _apply_budget() -> void:
	var share := 0.55 if Quality.preset == "low" or Quality.pressure_stage >= 2 else 1.0
	for mm in _multimeshes:
		mm.visible_instance_count = -1 if share >= 1.0 else int(mm.instance_count * share)


func _exit_tree() -> void:
	if Quality.budget_changed.is_connected(_apply_budget):
		Quality.budget_changed.disconnect(_apply_budget)


func set_wet(w: float) -> void:
	if _mat:
		_mat.set_shader_parameter("wetness", w)


## The sea surface sits a little under the lowest land; the stones sit on it.
func _waterline_level(terrain: Terrain) -> float:
	return terrain.water_surface


## Waterline segments (pairs of world XZ points) in a square window.
func _contour(terrain: Terrain, centre: Vector2, radius: float) -> Array:
	var segs := []
	var n := int(terrain.near.n)
	var cell := float(terrain.near.cell)
	var x0 := float(terrain.near.x0)
	var z0 := float(terrain.near.z0)
	var i0 := clampi(int((centre.x - radius - x0) / cell), 0, n - 2)
	var i1 := clampi(int((centre.x + radius - x0) / cell), 0, n - 2)
	var j0 := clampi(int((centre.y - radius - z0) / cell), 0, n - 2)
	var j1 := clampi(int((centre.y + radius - z0) / cell), 0, n - 2)
	var mask := terrain.water_mask
	var code := func(i: int, j: int) -> float: return float(mask[j * n + i]) - 127.5
	for j in range(j0, j1):
		for i in range(i0, i1):
			var c := [code.call(i, j), code.call(i + 1, j), code.call(i + 1, j + 1), code.call(i, j + 1)]
			var corners := [Vector2(i, j), Vector2(i + 1, j), Vector2(i + 1, j + 1), Vector2(i, j + 1)]
			var cross := []
			for e in 4:
				var a: float = c[e]
				var b: float = c[(e + 1) % 4]
				if (a < 0.0) != (b < 0.0):
					var t := a / (a - b)
					var g: Vector2 = (corners[e] as Vector2).lerp(corners[(e + 1) % 4], t)
					cross.append(Vector2(x0 + g.x * cell, z0 + g.y * cell))
			if cross.size() == 2:
				segs.append([cross[0], cross[1]])
			elif cross.size() == 4:
				segs.append([cross[0], cross[1]])
				segs.append([cross[2], cross[3]])
	return segs


func _line_of_stones(a: Vector2, b: Vector2, terrain: Terrain, track: RaceTrack, level: float, transforms: Dictionary) -> void:
	var length := a.distance_to(b)
	if length < 0.01:
		return
	var dir := (b - a) / length
	var count := maxi(1, int(length / SPACING))
	for k in count:
		var p := a.lerp(b, (k + _rng.randf()) / count)
		var road := track.dist_to(p.x, p.y)
		if road > ROAD_REACH:
			continue
		# Inland is toward the road. The mask's waterline sits on the dropped
		# seabed: walk in to where the bank actually leaves the water.
		var n := track.nearest(p.x, p.y, ROAD_REACH + 20.0)
		if n < 0:
			continue
		var inland := (Vector2(track.X[n], track.Z[n]) - p).normalized()
		var edge := -1.0
		var m := 0.0
		while m < minf(MAX_WALK, road - track.half_w - 4.0):
			var q := p + inland * m
			if terrain.height_at(q.x, q.y) >= level:
				edge = m
				break
			m += 0.5
		if edge < 0.0:
			continue
		var base := p + inland * edge
		# The bank's crest: where it stops climbing, at most PILE_MAX inland.
		var width := PILE_MIN
		while width < PILE_MAX:
			var q := base + inland * (width + 1.0)
			if terrain.height_at(q.x, q.y) - level > CREST or track.dist_to(q.x, q.y) < track.half_w + 3.0:
				break
			width += 1.0
		var rows := maxi(2, int(ceil((width + TOE) / ROW_STEP)))
		for row in rows:
			var t := float(row) / float(rows - 1)
			# Armour is piled: two layers over the toe and the lower bank.
			var layers := 2 if t < 0.35 else 1
			for layer in layers:
				var along := _rng.randf_range(-0.4, 0.4) * SPACING + (0.5 * SPACING if (row + layer) % 2 else 0.0)
				var q := base + inland * (-TOE + t * (width + TOE) + _rng.randf_range(-0.3, 0.3)) + dir * along
				if track.dist_to(q.x, q.y) < track.half_w + 2.5:
					continue
				var ground := terrain.height_at(q.x, q.y)
				var size := _rng.randf_range(0.9, 1.6) * lerpf(1.2, 0.85, t)
				var y := maxf(ground, level - 0.7) + size * (_rng.randf_range(0.2, 0.32) + 0.42 * layer)
				var basis := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _rng.randf_range(-0.5, 0.5)) * Basis(Vector3.FORWARD, _rng.randf_range(-0.4, 0.4))
				basis = basis.scaled(Vector3(size * _rng.randf_range(1.0, 1.35), size * _rng.randf_range(0.8, 1.1), size))
				var xf := Transform3D(basis, Vector3(q.x, y, q.y))
				var key := Vector3i(_rng.randi() % VARIANTS, floori(q.x / CHUNK), floori(q.y / CHUNK))
				if not transforms.has(key):
					transforms[key] = []
				transforms[key].append(xf)
				placed.append(xf)
			if row == 0:
				var tip := base + inland * -TOE
				spray_points.append(Vector3(tip.x, level + 0.3, tip.y))


## A broken limestone boulder about 1 m across: a noisy sphere with a few
## flat fracture faces; normals half faceted, half rounded, so it reads as
## weathered stone rather than a gem.
func _stone_mesh(variant: int, rings := 5, sides := 8) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = 91 + variant * 17
	noise.frequency = 1.4
	var cuts: Array[Plane] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 400 + variant
	for c in 3:
		var nrm := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1.0), rng.randf_range(-1, 1)).normalized()
		cuts.append(Plane(nrm, rng.randf_range(0.3, 0.4)))
	var pts := []
	for i in rings + 1:
		var row := []
		for k in sides:
			var th := PI * i / rings
			var ph := TAU * k / sides + (0.35 if i % 2 else 0.0)
			var dir := Vector3(sin(th) * cos(ph), cos(th) * 0.85, sin(th) * sin(ph))
			var r := 0.52 * (0.84 + 0.3 * noise.get_noise_3dv(dir * 1.2))
			if dir.y < -0.25:
				r *= 0.78
			var v := dir * r
			# Fracture faces: clip to a few planes.
			for cut in cuts:
				var over := cut.distance_to(v)
				if over > 0.0:
					v -= cut.normal * over
			row.append(v)
		pts.append(row)
	var palette := [Color("#a8834a"), Color("#8f6c3f"), Color("#b8976a"), Color("#7b5c3a"), Color("#9a8c76"), Color("#a07c4c")]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rings:
		for k in sides:
			var a: Vector3 = pts[i][k]
			var b: Vector3 = pts[i][(k + 1) % sides]
			var c: Vector3 = pts[i + 1][(k + 1) % sides]
			var d: Vector3 = pts[i + 1][k]
			var tone: Color = palette[(i * 3 + k * 2 + variant) % palette.size()]
			for tri in [[a, c, b], [a, d, c]]:
				var face: Vector3 = ((tri[1] as Vector3) - tri[0]).cross((tri[2] as Vector3) - tri[0])
				if face.length_squared() < 1e-10:
					continue
				face = face.normalized()
				var shade := tone.lerp(Color("#5a4329"), clampf(-face.y, 0.0, 1.0) * 0.45)
				for v: Vector3 in tri:
					st.set_normal((face + v.normalized()).normalized())
					st.set_color(shade)
					st.add_vertex(v)
	return st.commit()


func _make_spray() -> void:
	if spray_points.is_empty():
		return
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.6
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 38.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	pm.damping_min = 0.5
	pm.damping_max = 1.5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.9))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	var fade := GradientTexture1D.new()
	fade.gradient = ramp
	pm.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.85, 0.9, 0.92)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = FxVisual._glow_texture()
	quad.material = mat
	for i in SPRAY_POOL:
		var p := GPUParticles3D.new()
		p.name = "Spray%d" % i
		p.amount = 70
		p.lifetime = 1.3
		p.one_shot = true
		p.explosiveness = 0.85
		p.emitting = false
		p.process_material = pm
		p.draw_pass_1 = quad
		p.visibility_aabb = AABB(Vector3(-6, -2, -6), Vector3(12, 10, 12))
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		_spray.append(p)


## Every frame with the camera position: now and then a wave bursts on a
## stone in view. Off on low quality and under pressure (fx_extras).
## Returns true when a burst started.
func update(camera: Vector3, dt: float) -> bool:
	if _spray.is_empty() or not bool(Quality.p.get("fx_extras", true)):
		return false
	_spray_t -= dt
	if _spray_t > 0.0:
		return false
	_spray_t = _rng.randf_range(0.45, 1.1)
	for attempt in 12:
		var at := spray_points[_rng.randi() % spray_points.size()]
		var d := at.distance_to(camera)
		if d > SPRAY_NEAR and d < SPRAY_FAR:
			var p := _spray[_rng.randi() % _spray.size()]
			if p.emitting:
				continue
			p.global_position = at
			p.restart()
			return true
	return false
