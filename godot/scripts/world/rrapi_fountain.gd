class_name RrapiFountain
extends Node3D
## Rrapi, Vlorë: where Dhimitër Konomi comes down to the shore road, the
## two carriageways part (track.json "splits") with an island between them,
## and on it a lion fountain (an interpretation; the place is named for the
## great plane tree that stands there):
##   island    from where the carriageways part to where they are 36 m
##             apart: granite kerbs round a lawn, a paved ring round the
##             fountain
##   fountain  a round limestone basin, and in it a stele with a cornice
##             carrying a lion's head (CC0 "Lion Head", Poly Haven, reduced
##             by tools/build_lion_head.gd) with water arcing from its mouth
##             into the basin (shaders/fountain_water.gdshader)
## The plane tree is the "rrapi_tree" anchor (plane_tree()).
## Local frame: the lion looks toward -Z, up the shore road at the traffic
## coming down from Lungomare.

const LION := "res://assets/landmarks/lion_head.res"
const LION_SCALE := 3.4
const BASIN_R := 3.3
const BASIN_H := 0.62
const RIM := 0.36
const STELE := Vector3(1.6, 3.4, 1.0)
const GAP_MAX := 36.0
const KERB_H := 0.16
const RING_R := 6.2
const REACH := 1400.0
const TREE := "res://assets/foliage/tree_small_02_mobile.glb"

var island_area := 0.0
var island_points := 0
var mouth := Vector3.ZERO
var built_lion := false


## The island round the anchor, fitted between the two passes that part
## there, then the fountain on it. `xf`: the anchor's transform (world).
func build(track: RaceTrack, xf: Transform3D) -> void:
	name = "RrapiFountain"
	var top := 0.0
	if track != null:
		var ring := island_ring(track, Vector2(xf.origin.x, xf.origin.z))
		if ring.size() >= 3:
			top = _island(track, ring, xf)
	_fountain(top)


## The island's outline (world xz): the inner kerb line of each pass where
## the two have parted and are at most GAP_MAX apart, one along the lap and
## the other back, which closes the loop.
static func island_ring(track: RaceTrack, at: Vector2) -> PackedVector2Array:
	var runs := {}
	var near := PackedInt32Array()
	for k in track.M:
		if Vector2(track.X[k], track.Z[k]).distance_to(at) < 140.0 + GAP_MAX:
			near.append(k)
	for k in near:
		var p := Vector2(track.X[k], track.Z[k])
		if p.distance_to(at) > 140.0 or (track.PAIR.size() == track.M and track.PAIR[k] >= 0):
			continue
		# The other pass: the nearest sample far along the lap.
		var best := -1
		var bd := INF
		for j in near:
			var gap := absi(j - k)
			if mini(gap, track.M - gap) * track.ds < 80.0:
				continue
			var d := p.distance_squared_to(Vector2(track.X[j], track.Z[j]))
			if d < bd:
				bd = d
				best = j
		if best < 0 or sqrt(bd) > RoadMesh.ISLAND_GAP:
			continue
		var q := Vector2(track.X[best], track.Z[best])
		var n := Vector2(track.NX[k], track.NZ[k])
		var side := 1.0 if (q - p).dot(n) > 0.0 else -1.0
		var edge := p + n * side * (track.half_w + 0.02)
		# Group by pass: a run is consecutive samples.
		var key := -1
		for r: int in runs:
			var last: int = runs[r].last
			if posmod(k - last, track.M) <= 2:
				key = r
		if key < 0:
			key = k
			runs[key] = {"pts": PackedVector2Array(), "last": k}
		runs[key].pts.append(edge)
		runs[key].last = k
	var keys := runs.keys()
	if keys.size() != 2:
		return PackedVector2Array()
	var ring := PackedVector2Array()
	for r in keys:
		ring.append_array(runs[r].pts)
	if Geometry2D.is_polygon_clockwise(ring):
		ring.reverse()
	return ring


## Builds the island; returns the lawn's height (local) at the anchor.
func _island(track: RaceTrack, ring: PackedVector2Array, xf: Transform3D) -> float:
	var inv := xf.affine_inverse()
	var local := PackedVector2Array()
	var heights := PackedFloat32Array()
	for q in ring:
		var p := inv * Vector3(q.x, 0, q.y)
		local.append(Vector2(p.x, p.z))
		var k := track.nearest(q.x, q.y, 30.0)
		heights.append((track.Y[k] if k >= 0 else xf.origin.y) - xf.origin.y)
	island_points = local.size()
	var tris := Geometry2D.triangulate_polygon(local)
	var lawn := ArchKit.begin()
	var kerb := ArchKit.begin()
	var paving := ArchKit.begin()
	var h := func(i: int) -> float: return heights[i] + KERB_H
	for t in range(0, tris.size(), 3):
		var v: Array[Vector3] = []
		for o in 3:
			var i := tris[t + o]
			v.append(Vector3(local[i].x, h.call(i), local[i].y))
		ArchKit.wall_quad(lawn, v[0], v[1], v[2], v[2], Color.WHITE, Vector3.UP)
		island_area += absf((local[tris[t + 1]] - local[tris[t]]).cross(local[tris[t + 2]] - local[tris[t]])) * 0.5
	# Granite kerb round the edge: its face down to the road, a top band.
	for i in local.size():
		var j := (i + 1) % local.size()
		var a := Vector3(local[i].x, heights[i] - 0.05, local[i].y)
		var b := Vector3(local[j].x, heights[j] - 0.05, local[j].y)
		var e := Vector2(local[j] - local[i])
		if e.length() < 0.01:
			continue
		var out := Vector3(e.y, 0, -e.x).normalized()
		ArchKit.wall_quad(kerb, a, b, b + Vector3.UP * (KERB_H + 0.07), a + Vector3.UP * (KERB_H + 0.07), Color.WHITE, out)
		var a2 := a + Vector3.UP * (KERB_H + 0.07)
		var b2 := b + Vector3.UP * (KERB_H + 0.07)
		ArchKit.wall_quad(kerb, a2, b2, b2 - out * 0.35, a2 - out * 0.35, Color.WHITE, Vector3.UP)
	# A paved ring round the fountain, at the lawn's height there: the edge
	# heights weighted by nearness (the two roads beside it differ in level).
	var wsum := 0.0
	var y := 0.0
	for i in local.size():
		var w := 1.0 / maxf(local[i].length_squared(), 1.0)
		wsum += w
		y += float(h.call(i)) * w
	y /= wsum
	ArchKit.disc(paving, Vector3.ZERO, RING_R, y + 0.012, Color.WHITE, 48, BASIN_R + RIM - 0.05)
	var granite := ArchKit.material(preload("res://assets/textures/square_granite_diff.jpg"),
		preload("res://assets/textures/square_granite_nor.jpg"), preload("res://assets/textures/square_granite_arm.jpg"), 1.2, Color(0.92, 0.92, 0.94), 0.6)
	add_child(_node(kerb, granite, "IslandKerb"))
	var paved := ArchKit.material(preload("res://assets/textures/promenade_paving_diff.jpg"),
		preload("res://assets/textures/promenade_paving_nor.jpg"), preload("res://assets/textures/promenade_paving_arm.jpg"), 2.0, Color(0.92, 0.9, 0.88), 0.8)
	add_child(_node(paving, paved, "FountainRing"))
	var grass := ArchKit.material(preload("res://assets/textures/grass_diff.jpg"),
		preload("res://assets/textures/grass_nor.jpg"), null, 2.2, Color(0.8, 0.92, 0.7), 0.7)
	grass.roughness = 0.95
	add_child(_node(lawn, grass, "IslandLawn"))
	return y


func _node(st: SurfaceTool, mat: Material, node_name: String) -> MeshInstance3D:
	st.generate_tangents()
	var n := ArchKit.node(st, mat, node_name, REACH)
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


## The basin, the stele, the lion and the water, standing at local height y0.
func _fountain(y0: float) -> void:
	var stone := ArchKit.begin()
	var c := Vector3.ZERO
	# Basin: an outer wall, a moulded rim, the inner wall down to the water.
	ArchKit.ring_wall(stone, c, BASIN_R + RIM, y0 - 0.8, y0 + BASIN_H, Color(0.92, 0.9, 0.86), 56)
	ArchKit.disc(stone, Vector3(0, 0, 0), BASIN_R + RIM + 0.06, y0 + BASIN_H + 0.1, Color.WHITE, 56, BASIN_R - 0.04)
	ArchKit.ring_wall(stone, c, BASIN_R + RIM + 0.06, y0 + BASIN_H, y0 + BASIN_H + 0.1, Color.WHITE, 56)
	ArchKit.ring_wall(stone, c, BASIN_R - 0.04, y0 + 0.2, y0 + BASIN_H + 0.1, Color(0.8, 0.78, 0.74), 56, 0.0, TAU, true)
	# The stele at the back of the basin, a plinth and cornice.
	var back := BASIN_R * 0.55
	var sz := STELE
	ArchKit.box(stone, Vector3(0, y0 + 0.25, back), Vector3(sz.x + 0.5, 0.5, sz.z + 0.4), Color(0.9, 0.88, 0.84))
	ArchKit.box(stone, Vector3(0, y0 + 0.5 + sz.y * 0.5, back), sz, Color.WHITE)
	ArchKit.box(stone, Vector3(0, y0 + 0.5 + sz.y + 0.12, back), Vector3(sz.x + 0.36, 0.24, sz.z + 0.3), Color(0.95, 0.94, 0.9))
	ArchKit.box(stone, Vector3(0, y0 + 0.5 + sz.y + 0.42, back), Vector3(sz.x * 0.6, 0.36, sz.z * 0.7), Color(0.9, 0.88, 0.84))
	var limestone := ArchKit.material(preload("res://assets/textures/ashlar_buff_diff.jpg"),
		preload("res://assets/textures/ashlar_buff_nor.jpg"), preload("res://assets/textures/ashlar_buff_arm.jpg"), 2.2, Color(1.0, 0.98, 0.95), 0.8)
	var mesh := ArchKit.node(stone, limestone, "FountainStone", REACH)
	add_child(mesh)
	# The lion's head on the stele's face, its mouth over the water.
	var face_z := back - sz.z * 0.5
	var head_y := y0 + 1.55
	if ResourceLoader.exists(LION):
		var lion := MeshInstance3D.new()
		lion.name = "LionHead"
		lion.mesh = load(LION)
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://assets/props/lion_head/lion_head_lion_head_diff.jpg")
		m.normal_enabled = true
		m.normal_texture = load("res://assets/props/lion_head/lion_head_lion_head_nor_gl.jpg")
		m.roughness_texture = load("res://assets/props/lion_head/lion_head_lion_head_metal-lion_head_rough.jpg")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.roughness = 1.0
		m.albedo_color = Color(0.96, 0.94, 0.9)
		lion.material_override = m
		lion.scale = Vector3.ONE * LION_SCALE
		lion.position = Vector3(0, head_y, face_z + 0.02)
		lion.visibility_range_end = 600.0
		add_child(lion)
		built_lion = true
	mouth = Vector3(0, head_y + 0.16 * LION_SCALE, face_z - 0.2 * LION_SCALE)
	var water_y := y0 + BASIN_H - 0.08
	_water(water_y)
	_stream(mouth, Vector3(0, water_y, mouth.z - 1.25))


func _water(y: float) -> void:
	var disc := ArchKit.begin()
	ArchKit.disc(disc, Vector3.ZERO, BASIN_R, y, Color.WHITE, 48)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/fountain_water.gdshader")
	mat.set_shader_parameter("pool", true)
	var n := ArchKit.node(disc, mat, "BasinWater", 500.0)
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(n)


## The jet: a ribbon tube along the arc from the mouth to the water, its
## surface running toward the basin.
func _stream(from: Vector3, to: Vector3) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 16
	var sides := 8
	var pts: Array[Vector3] = []
	for i in rows + 1:
		var t := float(i) / rows
		var p := from.lerp(to, t)
		# Out from the mouth and falling: a parabola through both ends.
		p.y += 0.35 * 4.0 * t * (1.0 - t) - 0.0
		pts.append(p)
	for i in rows:
		var a := pts[i]
		var b := pts[i + 1]
		var dir := (b - a).normalized()
		var side := dir.cross(Vector3.RIGHT).normalized()
		var up := side.cross(dir).normalized()
		var ra := lerpf(0.075, 0.12, float(i) / rows)
		var rb := lerpf(0.075, 0.12, float(i + 1) / rows)
		for k in sides:
			var a0 := TAU * k / sides
			var a1 := TAU * (k + 1) / sides
			var o0 := side * cos(a0) + up * sin(a0)
			var o1 := side * cos(a1) + up * sin(a1)
			var quad := [[a + o0 * ra, o0, Vector2(float(k) / sides, float(i) / rows)],
				[b + o0 * rb, o0, Vector2(float(k) / sides, float(i + 1) / rows)],
				[b + o1 * rb, o1, Vector2(float(k + 1) / sides, float(i + 1) / rows)],
				[a + o1 * ra, o1, Vector2(float(k + 1) / sides, float(i) / rows)]]
			for j in [0, 1, 2, 0, 2, 3]:
				st.set_normal(quad[j][1])
				st.set_uv(quad[j][2])
				st.add_vertex(quad[j][0])
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/fountain_water.gdshader")
	mat.set_shader_parameter("pool", false)
	var n := MeshInstance3D.new()
	n.name = "LionStream"
	n.mesh = st.commit()
	n.material_override = mat
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.visibility_range_end = 400.0
	add_child(n)


## Rrapi itself: a great plane tree, the city's CC0 broadleaf (Tree Small 02)
## grown to plane-tree size.
static func plane_tree() -> Node3D:
	var root := Node3D.new()
	root.name = "RrapiTree"
	var scene: PackedScene = load(TREE)
	var tree := scene.instantiate() as Node3D
	tree.scale = Vector3.ONE * 2.4
	tree.rotation.y = 0.7
	root.add_child(tree)
	tree.add_child(_canopy())
	return root


## The model is a bare skeleton of branches: leaf clumps round its crown,
## crossed cut-outs from the city's photographic tree (its crown only).
static func _canopy() -> MeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1912
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Vector3(0.45, 6.0, 1.3)
	var radii := Vector3(2.6, 2.1, 3.5)
	for n in 46:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.7, 1), rng.randf_range(-1, 1))
		if dir.length() > 1.0:
			dir = dir.normalized()
		var at := centre + dir * radii * rng.randf_range(0.55, 1.0)
		var size := rng.randf_range(1.5, 2.2)
		# The whole crown, mirrored at random: a ragged outline every time.
		var uv := Rect2(0.1, 0.02, 0.8, 0.66)
		if rng.randf() < 0.5:
			uv = Rect2(0.9, 0.02, -0.8, 0.66)
		var yaw := rng.randf() * PI
		for turn: float in [0.0, PI * 0.5]:
			var ax := Vector3(cos(yaw + turn), 0, sin(yaw + turn)) * size
			var up := Vector3.UP * size * 0.85
			var quad := [at - ax - up, at + ax - up, at + ax + up, at - ax + up]
			var uvs := [Vector2(uv.position.x, uv.end.y), uv.end, Vector2(uv.end.x, uv.position.y), uv.position]
			var nrm := (at - centre + Vector3.UP * 0.8).normalized()
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_normal(nrm)
				st.set_uv(uvs[k])
				st.add_vertex(quad[k])
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/foliage/photographic_tree.png")
	m.albedo_color = Color(0.86, 0.9, 0.8)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.35
	m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	var mi := MeshInstance3D.new()
	mi.name = "Canopy"
	mi.mesh = st.commit()
	mi.material_override = m
	return mi
