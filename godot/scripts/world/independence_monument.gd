class_name IndependenceMonument
extends Node3D
## Monumenti i Pavarësisë, Sheshi i Flamurit, Vlorë: an interpretation after
## photographs. A tall, tapering pylon clad in dark granite slabs carrying
## "1912" near its top; a bronze flag-bearer standing on it with a great
## furled flag; a group of bronze figures at its foot (frock-coated
## statesmen, a fighter with raised fist, a kneeling fighter, men in plis
## caps) on a round drum of polished granite over four round granite steps.
## In the city (build_square) the steps stand in a paved granite square with
## a darker granite border and inlaid ring, white stone spheres round the
## steps and flags on tall poles behind, clipped clear of the boulevard's
## sidewalk. Granite: CC0 Granite Tile and Granite Tile 03 (Poly Haven).
## Local frame: the "1912" face and the group look toward -Z.
## The figures and period garments are baked by tools/build_independence_bronze.py.

const STONE := Color("#999e9c")
const STONE_LIGHT := Color(0.50, 0.50, 0.49)
const BRONZE := Color("#514e42")
const PLINTH_TOP := 2.1
const PYLON_TOP := 14.7
## Face the opening grid on the diagonal of the points arena.
const ARENA_YAW := 222.0
const FIGURES_PATH := "res://assets/landmarks/independence_bronze.glb"
## The round base: its centre (local z), the steps [radius, top] from the
## ground up, and the polished drum the group stands on.
const BASE_Z := -0.4
const STEPS := [[12.4, 0.32], [11.5, 0.64], [10.6, 0.96], [9.7, 1.28]]
const DRUM_R := 8.6
const SQUARE_R := 27.0
const SPHERE_R := 0.42
const FLAG_POLES := 7

var square_area := 0.0
var spheres := 0
var flags := 0
var _granite_dark: StandardMaterial3D


func _ready() -> void:
	_stone()
	_bronze()
	_inscription()


func _dark_granite(metres: float) -> StandardMaterial3D:
	return ArchKit.material(preload("res://assets/textures/dark_granite_diff.jpg"),
		preload("res://assets/textures/dark_granite_nor.jpg"), preload("res://assets/textures/dark_granite_arm.jpg"), metres, Color.WHITE, 0.7)


func _stone() -> void:
	# The round steps and the drum, in dark granite with UVs in metres.
	var base := ArchKit.begin()
	var c := Vector3(0, 0, BASE_Z)
	var y0 := -1.6
	for step: Array in STEPS:
		var r := float(step[0])
		var top := float(step[1])
		ArchKit.ring_wall(base, c, r, y0, top, Color(0.80, 0.80, 0.80), 72)
		ArchKit.disc(base, c, r, top, Color(0.88, 0.87, 0.86), 72, DRUM_R - 0.2)
		y0 = top - 0.02
	ArchKit.ring_wall(base, c, DRUM_R, y0, PLINTH_TOP - 0.12, Color(0.62, 0.62, 0.64), 72)
	ArchKit.ring_wall(base, c, DRUM_R + 0.08, PLINTH_TOP - 0.12, PLINTH_TOP, Color(0.75, 0.75, 0.76), 72)
	ArchKit.disc(base, c, DRUM_R + 0.08, PLINTH_TOP, Color(0.7, 0.7, 0.7), 72)
	var polished := _dark_granite(1.4)
	polished.roughness = 0.75
	_granite_dark = polished
	add_child(ArchKit.node(base, polished, "MonumentBase", 2200.0))
	# The pylon: a tapering block whose top is cut on a slant, high at the back.
	var st := LandmarkKit.begin()
	var b0 := Vector2(1.9, 1.35)   # half sizes at the foot (x, z)
	var b1 := Vector2(1.25, 0.95)  # at the top
	var cz := 1.2                  # set back behind the group
	var py0 := PLINTH_TOP
	# Recess each horizontal bed joint and catch the sunlight on the chamfered corners.
	var outline := [Vector2(-0.91, -1), Vector2(0.91, -1), Vector2(1, -0.88), Vector2(1, 0.88),
		Vector2(0.91, 1), Vector2(-0.91, 1), Vector2(-1, 0.88), Vector2(-1, -0.88)]
	for course in 8:
		var bottom := float(course) / 8.0
		var top := float(course + 1) / 8.0
		var rings := []
		for t: float in [bottom, bottom + 0.002, top - 0.002, top]:
			var inset := 0.022 if t == bottom or t == top else 0.0
			var half_size := b0.lerp(b1, t) - Vector2.ONE * inset
			var ring := PackedVector3Array()
			for uv: Vector2 in outline:
				ring.append(Vector3(uv.x * half_size.x, lerpf(py0, PYLON_TOP - 0.6 + 0.6 * uv.y, t), cz + uv.y * half_size.y))
			rings.append(ring)
		for row in 3:
			for i in outline.size():
				var j := (i + 1) % outline.size()
				var face: Vector2 = outline[i] + outline[j]
				LandmarkKit.quad_facing(st, rings[row][i], rings[row][j], rings[row + 1][j], rings[row + 1][i],
					Color(1, 1, 1).darkened(0.1 + 0.05 * (course % 3)), Vector3(face.x, 0, face.y))
		if course == 7:
			var lid: PackedVector3Array = rings[3]
			for corner in [1, 3, 5]:
				LandmarkKit.quad_facing(st, lid[0], lid[corner], lid[corner + 1], lid[corner + 2], Color.WHITE, Vector3.UP)
	# A raised panel framing the date.
	LandmarkKit.box(st, Vector3(0, PYLON_TOP - 3.4, cz - 1.08), Vector3(2.2, 1.25, 0.12), Color.WHITE)
	# Granite slabs on the pylon (triplanar: its faces lean as they taper).
	var cladding := LandmarkKit.material(0.8)
	cladding.albedo_texture = preload("res://assets/textures/dark_granite_diff.jpg")
	cladding.albedo_color = Color(0.92, 0.9, 0.88)
	cladding.normal_enabled = true
	cladding.normal_texture = preload("res://assets/textures/dark_granite_nor.jpg")
	cladding.normal_scale = 0.6
	cladding.roughness_texture = preload("res://assets/textures/dark_granite_arm.jpg")
	cladding.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	cladding.roughness = 1.0
	cladding.uv1_triplanar = true
	cladding.uv1_scale = Vector3.ONE / 1.6
	add_child(LandmarkKit.mesh_node(st, cladding, "MonumentStone", 2200.0))


## Weathered bronze: a dark brown patina, metallic enough to take the sky.
static func bronze_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.21, 0.15)
	m.metallic = 0.78
	m.roughness = 0.46
	m.metallic_specular = 0.55
	return m


## Sheshi i Flamurit round the monument: granite paving out to SQUARE_R,
## cut back where the boulevard's sidewalk (or the road) comes nearer,
## a dark border at its edge and an inlaid ring; white stone spheres round
## the steps; flags on poles round the back. Heights follow the terrain.
func build_square(track: RaceTrack, terrain: Terrain, xf: Transform3D) -> void:
	var clear := track.half_w + VloreBoulevard.KERB_W + VloreBoulevard.SIDEWALK + 0.3
	var segs := 96
	var c := Vector2(0, BASE_Z)
	var reach := PackedFloat32Array()
	for k in segs + 1:
		var a := TAU * k / segs
		var d := Vector2(sin(a), -cos(a))
		var r := float(STEPS[0][0])
		while r < SQUARE_R:
			var w := xf * Vector3(c.x + d.x * (r + 0.5), 0, c.y + d.y * (r + 0.5))
			if track.dist_to(w.x, w.z) < clear:
				break
			r += 0.5
		reach.append(r)
	var ground := func(x: float, z: float) -> float:
		var w := xf * Vector3(x, 0, z)
		return terrain.height_at(w.x, w.z) - xf.origin.y + 0.06
	var paving := ArchKit.begin()
	var border := ArchKit.begin()
	var rings := 6
	var inner := float(STEPS[0][0]) - 0.1
	var inlay := 16.0
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var d0 := Vector2(sin(a0), -cos(a0))
		var d1 := Vector2(sin(a1), -cos(a1))
		var r0max := reach[k]
		var r1max := reach[k + 1]
		if r0max <= inner + 1.0 or r1max <= inner + 1.0:
			continue
		var radii := func(rmax: float) -> PackedFloat32Array:
			var out := PackedFloat32Array()
			var body := rmax - 0.6
			for i in rings + 1:
				out.append(lerpf(inner, body, float(i) / rings))
			out.append(rmax)
			return out
		var ra: PackedFloat32Array = radii.call(r0max)
		var rb: PackedFloat32Array = radii.call(r1max)
		for i in ra.size() - 1:
			var p := [c + d0 * ra[i], c + d1 * rb[i], c + d1 * rb[i + 1], c + d0 * ra[i + 1]]
			var v: Array[Vector3] = []
			for q: Vector2 in p:
				v.append(Vector3(q.x, float(ground.call(q.x, q.y)), q.y))
			var target := border if i == ra.size() - 2 else paving
			ArchKit.wall_quad(target, v[0], v[1], v[2], v[3], Color.WHITE, Vector3.UP)
			square_area += 0.5 * absf((p[1] - p[0]).cross(p[3] - p[0])) + 0.5 * absf((p[2] - p[1]).cross(p[3] - p[1])) if target == paving else 0.0
		# The inlaid ring where the square reaches it.
		if r0max > inlay + 1.5 and r1max > inlay + 1.5:
			var q := [c + d0 * inlay, c + d1 * inlay, c + d1 * (inlay + 0.7), c + d0 * (inlay + 0.7)]
			var v: Array[Vector3] = []
			for p: Vector2 in q:
				v.append(Vector3(p.x, float(ground.call(p.x, p.y)) + 0.012, p.y))
			ArchKit.wall_quad(border, v[0], v[1], v[2], v[3], Color.WHITE, Vector3.UP)
		# The border's outer face down into the ground.
		var e0 := c + d0 * r0max
		var e1 := c + d1 * r1max
		var g0 := float(ground.call(e0.x, e0.y))
		var g1 := float(ground.call(e1.x, e1.y))
		ArchKit.wall_quad(border, Vector3(e0.x, g0 - 0.4, e0.y), Vector3(e1.x, g1 - 0.4, e1.y), Vector3(e1.x, g1, e1.y), Vector3(e0.x, g0, e0.y),
			Color.WHITE, Vector3(d0.x, 0, d0.y))
	var rose := ArchKit.material(preload("res://assets/textures/square_granite_diff.jpg"),
		preload("res://assets/textures/square_granite_nor.jpg"), preload("res://assets/textures/square_granite_arm.jpg"), 2.4, Color(1.08, 1.0, 0.98), 0.6)
	var paved := ArchKit.node(paving, rose, "FlagSquarePaving", 1200.0)
	paved.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(paved)
	var edged := ArchKit.node(border, _granite_dark if _granite_dark != null else _dark_granite(1.4), "FlagSquareBorder", 1200.0)
	edged.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(edged)
	# White stone spheres round the steps, the front left open.
	var balls := LandmarkKit.begin()
	for k in 16:
		var a := TAU * (k + 0.5) / 16.0
		if absf(wrapf(a, -PI, PI)) < 0.45:
			continue
		var d := Vector2(sin(a), -cos(a))
		var q := c + d * (float(STEPS[0][0]) + 1.3)
		if q.distance_to(c) > reach[int(round(a / TAU * segs)) % segs] - 0.8:
			continue
		LandmarkKit.sphere(balls, Vector3(q.x, float(ground.call(q.x, q.y)) + SPHERE_R * 0.92, q.y), Vector3.ONE * SPHERE_R, Color.WHITE, 8, 12)
		spheres += 1
	var marble := LandmarkKit.material(0.35)
	marble.albedo_texture = preload("res://assets/textures/museum_marble_diff.jpg")
	marble.uv1_triplanar = true
	marble.uv1_scale = Vector3.ONE * 1.4
	add_child(LandmarkKit.mesh_node(balls, marble, "SquareSpheres", 600.0))
	_flag_poles(c, reach, segs, ground)


## Flags on tall poles in an arc behind the monument.
func _flag_poles(c: Vector2, reach: PackedFloat32Array, segs: int, ground: Callable) -> void:
	var poles := LandmarkKit.begin()
	var at: Array[Vector3] = []
	var r := 21.5
	for k in FLAG_POLES:
		var a := PI + (float(k) / (FLAG_POLES - 1) - 0.5) * PI * 0.8
		if reach[int(round(fposmod(a, TAU) / TAU * segs)) % segs] < r + 1.0:
			continue
		var d := Vector2(sin(a), -cos(a))
		var q := c + d * r
		var foot := Vector3(q.x, float(ground.call(q.x, q.y)), q.y)
		LandmarkKit.tube(poles, foot + Vector3.DOWN * 0.2, foot + Vector3.UP * 9.0, 0.09, 0.06, Color(0.82, 0.83, 0.84), 8)
		LandmarkKit.sphere(poles, foot + Vector3.UP * 9.08, Vector3.ONE * 0.11, Color(0.85, 0.7, 0.3), 4, 6)
		at.append(foot + Vector3.UP * 7.75)
	if at.is_empty():
		return
	add_child(LandmarkKit.mesh_node(poles, LandmarkKit.material(0.35, 0.7), "SquareFlagPoles", 1200.0))
	var cloth := QuadMesh.new()
	cloth.size = Vector2(2.4, 1.7)
	cloth.subdivide_width = 10
	cloth.subdivide_depth = 4
	cloth.center_offset = Vector3(1.2, 0, 0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = cloth
	mm.instance_count = at.size()
	for i in at.size():
		# The wind off the bay: every flag streams the same way.
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, 0.6), at[i]))
		mm.set_instance_custom_data(i, Color(0, 0, 0, float(i) * 0.37))
		flags += 1
	var inst := MultiMeshInstance3D.new()
	inst.name = "SquareFlags"
	inst.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/flag_wave.gdshader")
	mat.set_shader_parameter("use_tex", true)
	mat.set_shader_parameter("flag_tex", LandmarkKit.albanian_flag())
	mat.set_shader_parameter("wave", 1.6)
	inst.material_override = mat
	inst.visibility_range_end = 900.0
	add_child(inst)


func _inscription() -> void:
	var date := TextMesh.new()
	date.text = Data.t("sign.independence_year")
	date.font = ThemeDB.fallback_font
	date.font_size = 96
	date.pixel_size = 0.010
	date.depth = 0.075
	var raised := MeshInstance3D.new()
	raised.name = "MonumentDate"
	raised.mesh = date
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("#b8ad93")
	metal.metallic = 0.52
	metal.roughness = 0.57
	raised.material_override = metal
	raised.rotation.y = PI
	raised.position = Vector3(0, PYLON_TOP - 3.4, -0.035)
	add_child(raised)


func _bronze() -> void:
	var cast: PackedScene = load(FIGURES_PATH)
	var figures := cast.instantiate()
	figures.name = "MonumentBronze"
	add_child(figures)
	var bronze := bronze_material()
	for part in figures.find_children("*", "MeshInstance3D", true, false):
		(part as MeshInstance3D).material_override = bronze
	var st := LandmarkKit.begin()
	var foot := Vector3(-0.13, PYLON_TOP - 0.5, 0.65)
	var tip := Vector3(-0.42, PYLON_TOP + 5.65, 0.20)
	LandmarkKit.tube(st, foot, tip, 0.085, 0.065, BRONZE)
	_cloth(st, tip, foot.lerp(tip, 0.41), Vector3(-1, 0.04, 0.65).normalized(), 3.35)
	var flag := LandmarkKit.mesh_node(st, bronze, "CastFlag", 2200.0)
	add_child(flag)


## A heavy, billowing flag: rows of panels off the pole, wavy and drooping.
func _cloth(st: SurfaceTool, top: Vector3, low: Vector3, out: Vector3, length: float) -> void:
	var cols := 16
	var rows := 9
	var grid := []
	for r in rows + 1:
		var on_pole := top.lerp(low, float(r) / rows)
		var row := []
		for c in cols + 1:
			var t := float(c) / cols
			var v := float(r) / rows
			var p := on_pole + out * (length * t * (0.78 + 0.22 * v))
			p += Vector3(0, -1.8 * t * t + v * 0.68 * t, 0) + Vector3(0.53, 0.12, 0.64) * sin(t * 10.0 + float(r) / rows * 2.6) * t
			row.append(p)
		grid.append(row)
	for r in rows:
		for c in cols:
			var a: Vector3 = grid[r][c]
			var b: Vector3 = grid[r][c + 1]
			var cc: Vector3 = grid[r + 1][c + 1]
			var d: Vector3 = grid[r + 1][c]
			# Both faces: the cloth is seen from all round.
			LandmarkKit.quad(st, a, b, cc, d, BRONZE)
			LandmarkKit.quad(st, b, a, d, cc, BRONZE)
