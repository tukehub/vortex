class_name RrapiFountain
extends Node3D
## Rrapi, Vlorë: where Dhimitër Konomi comes down to the shore road, the
## two carriageways part (track.json "splits") with an island between them,
## and on it a lion fountain (an interpretation; the place is named for the
## great plane tree that stands there):
##   island    from where the carriageways part to where they are 36 m
##             apart: granite kerbs round a lawn, a paved ring round the
##             fountain
##   fountain  Luani, after the city's own: a gilded lion standing on a
##             worn slab on a rock, in a low round basin of mossy concrete,
##             a thin stream from its mouth into the water
##             (shaders/fountain_water.gdshader), two plane trees behind.
##             The body, mane, legs and curled tail are modelled here; the
##             face is the CC0 "Lion Head" (Poly Haven, reduced by
##             tools/build_lion_head.gd) on the front of the mane
## The great plane tree itself is the "rrapi_tree" anchor (plane_tree()).
## Local frame: the lion looks toward -Z, up the shore road at the traffic
## coming down from Lungomare.

const LION := "res://assets/landmarks/lion_head.res"
## The standing lion: life size (1.5 m nose to rump), its body built here,
## its face the CC0 Lion Head on the front of the mane.
const LION_SCALE := 1.15
const LION_Z := 0.35
const HEAD_SCALE := 1.0
const HEAD_AT := Vector3(0, 0.95, -0.6)
const BASIN_R := 1.75
const BASIN_H := 0.5
const RIM := 0.28
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


## The basin, the rock and slab, the lion and the water, at local height y0.
func _fountain(y0: float) -> void:
	var c := Vector3.ZERO
	# A low round basin of rough concrete, mossy where the water splashes.
	var basin := ArchKit.begin()
	ArchKit.ring_wall(basin, c, BASIN_R + RIM, y0 - 0.8, y0 + BASIN_H, Color(0.86, 0.86, 0.8), 48)
	ArchKit.disc(basin, c, BASIN_R + RIM, y0 + BASIN_H, Color(0.95, 0.95, 0.92), 48, BASIN_R)
	ArchKit.ring_wall(basin, c, BASIN_R, y0 + 0.1, y0 + BASIN_H, Color(0.62, 0.68, 0.58), 48, 0.0, TAU, true)
	var concrete := ArchKit.material(preload("res://assets/textures/concrete_diff.jpg"),
		preload("res://assets/textures/concrete_nor.jpg"), null,
		1.6, Color(0.92, 0.9, 0.84), 0.9)
	add_child(ArchKit.node(basin, concrete, "FountainBasin", REACH))
	# A rough rock in the water, a worn slab on it for the lion to stand on.
	var rock := LandmarkKit.begin()
	var rock_c := Vector3(0, y0 + 0.36, LION_Z + 0.05)
	_lumpy(rock, rock_c, Vector3(0.6, 0.42, 1.15), Color(0.9, 0.88, 0.82), 7)
	var slab_top := y0 + 0.86
	LandmarkKit.box(rock, Vector3(0, slab_top - 0.07, LION_Z + 0.12), Vector3(0.62, 0.14, 2.05), Color(0.97, 0.95, 0.9))
	var rock_mat := LandmarkKit.material(0.92)
	rock_mat.albedo_texture = preload("res://assets/textures/concrete_diff.jpg")
	rock_mat.normal_enabled = true
	rock_mat.normal_texture = preload("res://assets/textures/concrete_nor.jpg")
	rock_mat.uv1_triplanar = true
	rock_mat.uv1_scale = Vector3.ONE * 0.8
	add_child(LandmarkKit.mesh_node(rock, rock_mat, "FountainRock", REACH))
	# The lion, standing on the slab, its mouth over the water.
	var lion := Node3D.new()
	lion.name = "Lion"
	lion.position = Vector3(0, slab_top, LION_Z)
	lion.scale = Vector3.ONE * LION_SCALE
	add_child(lion)
	var gold := lion_material()
	lion.add_child(_lion_body(gold))
	if ResourceLoader.exists(LION):
		var head := MeshInstance3D.new()
		head.name = "LionHead"
		head.mesh = load(LION)
		var m := gold.duplicate() as StandardMaterial3D
		m.vertex_color_use_as_albedo = false
		m.normal_enabled = true
		m.normal_texture = load("res://assets/props/lion_head/lion_head_lion_head_nor_gl.jpg")
		m.normal_scale = 1.2
		head.material_override = m
		head.scale = Vector3.ONE * HEAD_SCALE
		head.position = HEAD_AT
		head.visibility_range_end = 700.0
		lion.add_child(head)
		built_lion = true
	mouth = lion.position + (HEAD_AT + Vector3(0, 0.16 * HEAD_SCALE, -0.2 * HEAD_SCALE)) * LION_SCALE
	var water_y := y0 + BASIN_H - 0.1
	_water(water_y)
	_stream(mouth, Vector3(0, water_y, mouth.z - 0.75))
	# The plane trees the fountain stands under.
	for at: Vector3 in [Vector3(-2.9, y0, 1.9), Vector3(2.6, y0, 2.6)]:
		var tree := plane_tree()
		tree.position = at
		tree.rotation.y = at.x
		add_child(tree)


## Gilded paint over the cast, a little worn: the gold catches the sky.
static func lion_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = Color(0.86, 0.66, 0.32)
	m.metallic = 0.85
	m.roughness = 0.38
	m.metallic_specular = 0.6
	return m


## The lion in its own frame (metres; it looks toward -Z, feet at y = 0):
## a lofted body from rump to neck, a shaggy mane, four legs (the near
## fore leg stepping out), paws, and the tail curling up behind.
func _lion_body(gold: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Torso: [z, centre height, half width, half height] from rump to neck.
	var torso := [[0.8, 0.86, 0.04, 0.05], [0.74, 0.85, 0.14, 0.16], [0.6, 0.84, 0.19, 0.22],
		[0.4, 0.85, 0.18, 0.2], [0.17, 0.87, 0.16, 0.18], [-0.06, 0.88, 0.19, 0.23],
		[-0.26, 0.92, 0.22, 0.27], [-0.43, 1.0, 0.21, 0.27], [-0.56, 1.08, 0.17, 0.22], [-0.63, 1.1, 0.05, 0.06]]
	var rings: Array = []
	for row: Array in torso:
		rings.append(_ring(Vector3(0, row[1], row[0]), Vector3(0, 0, -1), float(row[2]), float(row[3]), 18, 2.4))
	_loft(st, rings, Color(0.98, 0.95, 0.9))
	# The mane round the neck and shoulders, shaggy.
	_lumpy(st, Vector3(0, 1.12, -0.42), Vector3(0.28, 0.33, 0.26), Color(0.92, 0.86, 0.78), 3)
	# Legs: [hip or shoulder, knee, ankle, paw] for each.
	var legs := [
		[Vector3(-0.13, 0.86, -0.36), Vector3(-0.14, 0.5, -0.42), Vector3(-0.13, 0.14, -0.56), Vector3(-0.13, 0.05, -0.64)],
		[Vector3(0.13, 0.86, -0.36), Vector3(0.14, 0.5, -0.36), Vector3(0.13, 0.14, -0.36), Vector3(0.13, 0.05, -0.43)],
		[Vector3(-0.15, 0.8, 0.56), Vector3(-0.15, 0.52, 0.66), Vector3(-0.14, 0.22, 0.74), Vector3(-0.13, 0.05, 0.64)],
		[Vector3(0.15, 0.8, 0.56), Vector3(0.15, 0.52, 0.62), Vector3(0.14, 0.22, 0.7), Vector3(0.13, 0.05, 0.58)]]
	for i in legs.size():
		var leg: Array = legs[i]
		var hind := i >= 2
		_tube(st, [leg[0], leg[1], leg[2], leg[3]], [0.11 if hind else 0.09, 0.075, 0.055, 0.05], Color(0.9, 0.84, 0.74))
		# Paw: flattened, reaching forward.
		var paw: Vector3 = leg[3] + Vector3(0, -0.005, -0.05)
		_lumpy(st, paw, Vector3(0.07, 0.05, 0.1), Color(0.82, 0.76, 0.66), 1)
		if hind:
			# Thigh and haunch muscle over the hind leg.
			_lumpy(st, Vector3(leg[0].x * 1.05, 0.74, 0.55), Vector3(0.1, 0.22, 0.19), Color(0.97, 0.94, 0.88), 0)
		else:
			_lumpy(st, Vector3(leg[0].x * 1.1, 0.8, -0.36), Vector3(0.08, 0.17, 0.12), Color(0.97, 0.94, 0.88), 0)
	# The tail: down from the rump, then curling up behind, a tuft at its end.
	var tail := [Vector3(0, 0.88, 0.78), Vector3(0, 0.66, 0.95), Vector3(0.03, 0.46, 1.02),
		Vector3(0.05, 0.4, 1.14), Vector3(0.05, 0.52, 1.24), Vector3(0.04, 0.7, 1.22)]
	_tube(st, tail, [0.04, 0.035, 0.03, 0.028, 0.026, 0.025], Color(0.92, 0.86, 0.76))
	_lumpy(st, tail[tail.size() - 1] + Vector3(0, 0.04, -0.02), Vector3(0.055, 0.075, 0.055), Color(0.9, 0.82, 0.7), 2)
	st.index()
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "LionBody"
	mi.mesh = st.commit()
	mi.material_override = gold
	mi.visibility_range_end = 900.0
	return mi


## A superellipse cross-section round `c`, square to `along`.
static func _ring(c: Vector3, along: Vector3, rx: float, ry: float, n: int, e: float) -> PackedVector3Array:
	var side := along.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.5:
		side = Vector3.RIGHT
	var up := side.cross(along).normalized() * -1.0
	if up.y < 0.0:
		up = -up
	var out := PackedVector3Array()
	for k in n:
		var a := TAU * k / n
		var ca := cos(a)
		var sa := sin(a)
		var x := signf(ca) * pow(absf(ca), 2.0 / e) * rx
		var y := signf(sa) * pow(absf(sa), 2.0 / e) * ry
		out.append(c + side * x + up * y)
	return out


static func _loft(st: SurfaceTool, rings: Array, col: Color) -> void:
	var n: int = (rings[0] as PackedVector3Array).size()
	var mids: Array[Vector3] = []
	for r: PackedVector3Array in rings:
		var m := Vector3.ZERO
		for v in r:
			m += v
		mids.append(m / r.size())
	for i in rings.size() - 1:
		var a: PackedVector3Array = rings[i]
		var b: PackedVector3Array = rings[i + 1]
		for k in n:
			var k1 := (k + 1) % n
			for e: Array in [[a[k], i], [b[k], i + 1], [b[k1], i + 1], [a[k], i], [b[k1], i + 1], [a[k1], i]]:
				var v: Vector3 = e[0]
				st.set_color(col)
				st.set_normal((v - mids[int(e[1])]).normalized())
				st.add_vertex(v)
	# Close both ends.
	for end: int in [0, rings.size() - 1]:
		var r: PackedVector3Array = rings[end]
		var mid := Vector3.ZERO
		for v in r:
			mid += v
		mid /= r.size()
		for k in n:
			var k1 := (k + 1) % n
			var tri := [mid, r[k1], r[k]] if end == 0 else [mid, r[k], r[k1]]
			var cap := (mids[0] - mids[1]).normalized() if end == 0 else (mids[end] - mids[end - 1]).normalized()
			for v: Vector3 in tri:
				st.set_color(col)
				st.set_normal(cap)
				st.add_vertex(v)


## A smooth tube through `pts` with radii `radii`, capped at both ends.
static func _tube(st: SurfaceTool, pts: Array, radii: Array, col: Color) -> void:
	var rings: Array = []
	for i in pts.size():
		var a: Vector3 = pts[maxi(i - 1, 0)]
		var b: Vector3 = pts[mini(i + 1, pts.size() - 1)]
		var along := (b - a).normalized()
		rings.append(_ring(pts[i], along, float(radii[i]), float(radii[i]), 10, 2.0))
	_loft(st, rings, col)


## An ellipsoid with a gently lumpy surface (`shag` > 0 makes it shaggier).
static func _lumpy(st: SurfaceTool, c: Vector3, r: Vector3, col: Color, shag: int) -> void:
	var rows := 10
	var cols := 16
	var pt := func(i: int, j: int) -> Vector3:
		var th := PI * i / rows
		var ph := TAU * j / cols
		var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
		var bump := 1.0 + 0.045 * shag * sin(ph * 5.0 + th * 3.0) * sin(th * 7.0 + ph * 2.0)
		return c + d * r * bump
	for i in rows:
		for j in cols:
			var a: Vector3 = pt.call(i, j)
			var b: Vector3 = pt.call(i + 1, j)
			var cc: Vector3 = pt.call(i + 1, j + 1)
			var d: Vector3 = pt.call(i, j + 1)
			for v: Vector3 in [a, d, cc, a, cc, b]:
				st.set_color(col)
				st.set_normal(((v - c) / (r * r)).normalized())
				st.add_vertex(v)


func _water(y: float) -> void:
	var disc := ArchKit.begin()
	ArchKit.disc(disc, Vector3.ZERO, BASIN_R, y, Color.WHITE, 48)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/fountain_water.gdshader")
	mat.set_shader_parameter("pool", true)
	mat.set_shader_parameter("fall", Vector2(0.0, mouth.z - 0.75))
	var n := ArchKit.node(disc, mat, "BasinWater", 500.0)
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(n)


## The jet: a thin tube along the arc from the mouth to the water, its
## surface running toward the basin.
func _stream(from: Vector3, to: Vector3) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 16
	var sides := 6
	var pts: Array[Vector3] = []
	for i in rows + 1:
		var t := float(i) / rows
		var p := from.lerp(to, t)
		# Out of the mouth and falling: a little rise, then the drop.
		p.y += 0.12 * 4.0 * t * (1.0 - t)
		p.z += -0.15 * sin(t * PI) * (1.0 - t)
		pts.append(p)
	for i in rows:
		var a := pts[i]
		var b := pts[i + 1]
		var dir := (b - a).normalized()
		var side := dir.cross(Vector3.RIGHT).normalized()
		var up := side.cross(dir).normalized()
		var ra := lerpf(0.018, 0.03, float(i) / rows)
		var rb := lerpf(0.018, 0.03, float(i + 1) / rows)
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
