extends Node3D
## The Uji i Ftohtë tunnel, after photographs from the beach: the road runs
## through a limestone headland that drops from the hillside into the bay.
## A concrete headwall with a moulded arch stands at each portal in a
## natural rock face; pale cliffs with vertical weathering, maquis and a few
## pines on top; a rock cut beside each approach on the inland side; the
## seaward cliff wrapped by a pier walk on pillars; a seawall by the beach.
## The bore follows the race centreline.

const ARCH_STEPS := 16
const SPRING := 3.5
const RISE := 3.4
const RING := 2.0          # metres between rock cross-sections
const WING_IN := 44.0      # the inland rock cut runs this far past each portal
const WING_SEA := 20.0     # and the seaward cliff this far
const WALL_TOP := 9.4      # the portal headwall, above the road
const SEA_FACE := 8.1      # the seaward cliff stands behind the seawall
const MAX_PINES := 6
const ROCK := Color("#aa9b81")
const LIMESTONE := Color("#bdb6a8")
const OCHRE := Color("#b39a74")
const CREVICE := Color("#6f685c")
const MAQUIS := Color("#4f5d33")
const MAQUIS_DARK := Color("#3a4628")
const CONCRETE := Color("#bdbcb6")
## Across the headland: q (m, + inland of the road centre) and height above
## the road. The seaward cliff falls into the water at q = -36, the back
## runs into the hillside.
const PROFILE := [[-39.0, -5.0], [-36.5, -0.5], [-34.0, 5.5], [-31.5, 11.0], [-28.0, 14.5], [-23.0, 16.8],
	[-17.0, 18.0], [-12.0, 18.8], [-SEA_FACE, 19.3], [-4.0, 19.8], [0.0, 20.3], [4.0, 20.9], [7.6, 21.3],
	[12.0, 21.9], [17.0, 22.5], [23.0, 22.8], [30.0, 22.3], [38.0, 21.0], [46.0, 20.0], [55.0, 20.6],
	[64.0, 22.0], [74.0, 24.0]]
const CUT_Q := 7.6          # the inland rock cut beside the approach
const STEP_Q := 2.2         # cross-section resolution

var _lights: Array[OmniLight3D] = []
var _track: RaceTrack
var _terrain: Terrain
var _inland := -1.0
var _start := 0.0
var _end := 0.0
var _shrubs: Array[Transform3D] = []
## PROFILE resampled every STEP_Q metres (keeping both face positions).
var _profile: Array = []
var _cut := 0
var _sea := 0
var _pines: Array[Transform3D] = []
var _maquis: MultiMesh


func build(track: RaceTrack, portals: Array, reverse: bool, terrain: Terrain) -> void:
	_track = track
	_terrain = terrain
	var a: Array = portals[1 if reverse else 0]
	var b: Array = portals[0 if reverse else 1]
	var start := track.locate_xz(a[0], a[1]).x
	var length := track.mod_s(track.locate_xz(b[0], b[1]).x - start)
	_start = start
	_end = start + length
	_inland = 1.0 if reverse else -1.0
	position = track.pos(start, 0.0)
	_resample_profile()
	_bore(start, length)
	_headland(start, length)
	_headwalls(start, length)
	_seawall(track, start, length, -_inland, terrain)
	_pier(start, length)
	_vegetation()


# --------------------------------------------------------------- the bore
func _bore(start: float, length: float) -> void:
	var rings := ceili(length / 2.7)
	var half := _track.half_w + 1.18
	var bore := LandmarkKit.begin()
	var lit := LandmarkKit.begin()
	var previous := PackedVector3Array()
	for i in rings + 1:
		var s := start + length * i / rings
		var centre := _track.pos(s, 0.0) - position
		var normal := _track.normal(s)
		var inner := PackedVector3Array()
		for j in ARCH_STEPS + 1:
			var angle := PI * float(j) / ARCH_STEPS
			inner.append(centre + normal * (half * cos(angle)) + Vector3.UP * (SPRING + RISE * sin(angle)))
		inner.push_back(centre - normal * half - Vector3.UP * 2.0)
		inner.insert(0, centre + normal * half - Vector3.UP * 2.0)
		if i > 0:
			for j in inner.size() - 1:
				var toward := centre + Vector3.UP * 1.4 - (inner[j] + inner[j + 1]) * 0.5
				var interior := Color("#414247").lerp(Color("#9a907d"), 0.2 + 0.12 * cos(j * 2.1 + i * 0.67))
				LandmarkKit.quad_facing(bore, previous[j], inner[j], inner[j + 1], previous[j + 1], interior, toward)
		if i > 0 and i < rings and i % 5 == 0:
			var fixture := centre + Vector3.UP * (SPRING + RISE - 0.27)
			LandmarkKit.box(lit, fixture, Vector3(0.78, 0.08, 0.30), Color("#ffda96"), Basis.looking_at(_track.tangent(s)))
			var light := OmniLight3D.new()
			light.position = fixture - Vector3.UP * 0.32
			light.omni_range = 10.0
			light.light_color = Color("#ffe0ae")
			light.light_energy = 0.72
			light.visible = false
			add_child(light)
			_lights.append(light)
		previous = inner
	var liner := LandmarkKit.material()
	liner.albedo_texture = preload("res://assets/textures/concrete_wall_diff.jpg")
	liner.uv1_triplanar = true
	liner.uv1_scale = Vector3.ONE * 0.25
	add_child(LandmarkKit.mesh_node(bore, liner, "TunnelBore", 620.0))
	var glow := LandmarkKit.material()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	add_child(LandmarkKit.mesh_node(lit, glow, "TunnelFixtures", 420.0))


# ------------------------------------------------------------ the headland
## Crags: a few octaves of sines, incommensurate so they never line up.
static func _crag(s: float, q: float) -> float:
	var n := 1.25 * sin(s * 0.173 + q * 0.291) * sin(q * 0.137 - s * 0.083 + 1.3)
	n += 0.65 * sin(s * 0.411 - q * 0.353 + 2.1) * cos(q * 0.517 + s * 0.229)
	# Ridged, blocky breaks: limestone fractures, not dunes.
	n += 0.9 * (1.0 - absf(sin(s * 0.53 + q * 0.31 + 0.4 * sin(q * 0.9)))) - 0.45
	n += 0.45 * (1.0 - absf(sin(s * 1.37 - q * 0.83 + 1.9))) - 0.22
	return n


## World point at lap s, q metres inland of the road centre, `up` metres
## above the road there.
func _at(s: float, q: float, up: float) -> Vector3:
	return _track.pos(s, q * _inland) + Vector3.UP * up


func _ground(p: Vector3) -> float:
	return _terrain.height_at(p.x, p.z) if _terrain != null else p.y - 2.0


## The top of the rock at (s, q): the profile (scaled by `f`, 1 over the bore,
## 0 where a wing has died away), never below the hillside under it.
func _top(s: float, q: float, base_up: float, f: float) -> Vector3:
	var jitter := 0.55 * sin(s * 0.61 + q * 0.43) * clampf(absf(q) / 12.0, 0.0, 1.0)
	var p := _at(s, q + jitter, 0.0)
	var ground := _ground(p)
	var road := p.y
	var full := road + base_up + _crag(s, q) * (0.35 + 0.65 * clampf(absf(base_up) / 10.0, 0.0, 1.0))
	if q > -30.0:
		full = maxf(full, ground + 0.8)
	var sunk := minf(ground, road) - 2.2
	p.y = lerpf(sunk, full, f)
	return p


func _resample_profile() -> void:
	_profile = []
	for k in PROFILE.size() - 1:
		var a: Array = PROFILE[k]
		var b: Array = PROFILE[k + 1]
		var steps := maxi(1, roundi((float(b[0]) - float(a[0])) / STEP_Q))
		for j in steps:
			var t := float(j) / steps
			var w := t * t * (3.0 - 2.0 * t)
			_profile.append([lerpf(a[0], b[0], t), lerpf(a[1], b[1], w)])
	_profile.append(PROFILE[-1])
	for k in _profile.size():
		if is_equal_approx(float(_profile[k][0]), CUT_Q):
			_cut = k
		if is_equal_approx(float(_profile[k][0]), -SEA_FACE):
			_sea = k


## How far past a portal the rock at q runs: a few metres beside the road
## (so the portal stands in a face across it), the whole wing out on the
## hillside and the headland.
static func _wing_reach(q: float, reach: float) -> float:
	return lerpf(3.5, reach, smoothstep(14.0, 42.0, absf(q)))


func _headland(start: float, length: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := [0]
	# Over the bore: the whole profile.
	var rings: Array = []
	var n := maxi(2, ceili(length / RING))
	for i in n + 1:
		var s := start + length * i / n
		var ring: Array[Vector3] = []
		for k in _profile.size():
			ring.append(_top(s, _profile[k][0], _profile[k][1], 1.0))
		rings.append(ring)
	_stitch(st, rings, count, true)
	# Beside each approach: the inland cut and the seaward cliff, each with
	# its face to the road, dying away from the portal.
	for end_s: float in [start, start + length]:
		var outward := -1.0 if end_s == start else 1.0
		for wing in 2:
			var reach := WING_IN if wing == 0 else WING_SEA
			var steps := ceili(reach / RING)
			var wing_rings: Array = []
			for i in steps + 1:
				var past := reach * i / steps
				var s := end_s + outward * past
				var fade := func(q: float) -> float: return sqrt(1.0 - smoothstep(0.0, _wing_reach(q, reach), past))
				var ring: Array[Vector3] = []
				if wing == 0:
					var face_q := CUT_Q
					var f_face: float = fade.call(face_q)
					ring.append(_at(s, face_q - 0.35, -0.8))
					ring.append(_at(s, face_q - 0.15, lerpf(-0.6, 6.0, f_face) + 0.4 * _crag(s, 3.0)))
					for k in range(_cut, _profile.size()):
						ring.append(_top(s, _profile[k][0], _profile[k][1], fade.call(float(_profile[k][0]))))
				else:
					for k in range(0, _sea + 1):
						ring.append(_top(s, _profile[k][0], _profile[k][1], fade.call(float(_profile[k][0]))))
					var f_face: float = fade.call(-SEA_FACE)
					ring.append(_at(s, -SEA_FACE + 0.15, lerpf(-0.6, 7.0, f_face) + 0.4 * _crag(s, -3.0)))
					ring.append(_at(s, -SEA_FACE + 0.35, -0.8))
				if outward < 0.0:
					wing_rings.push_front(ring)
				else:
					wing_rings.append(ring)
			_stitch(st, wing_rings, count, false)
	# The portal faces: natural rock above the headwall.
	for end_s: float in [start, start + length]:
		var facing := _track.tangent(end_s) * (-1.0 if end_s == start else 1.0)
		_portal_face(st, rings[0] if end_s == start else rings[-1], end_s, facing, count)
	st.generate_normals()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/headland_rock.gdshader")
	mat.set_shader_parameter("rock_tex", preload("res://assets/textures/rock_diff.jpg"))
	mat.set_shader_parameter("rock_nor", preload("res://assets/textures/rock_nor.jpg"))
	var node := MeshInstance3D.new()
	node.name = "CliffAndPortals"
	node.mesh = st.commit()
	node.material_override = mat
	node.visibility_range_end = 1900.0
	add_child(node)


## Quads between consecutive rings of equal length; colour by slope and
## height: limestone on the faces, maquis where the rock lies back.
func _stitch(st: SurfaceTool, rings: Array, count: Array, plant: bool, toward := Vector3.UP) -> void:
	var first: int = count[0]
	var width: int = (rings[0] as Array).size()
	# Wind every quad so its face looks along `toward` (the race direction
	# and the inland side swap with a reverse race).
	var mi := rings.size() / 2
	var mk := width / 2
	var across0: Vector3 = (rings[mi][mini(mk + 1, width - 1)] as Vector3) - (rings[mi][maxi(mk - 1, 0)] as Vector3)
	var along0: Vector3 = (rings[mini(mi + 1, rings.size() - 1)][mk] as Vector3) - (rings[maxi(mi - 1, 0)][mk] as Vector3)
	var flip := across0.cross(along0).dot(toward) < 0.0
	for i in rings.size():
		var ring: Array = rings[i]
		for k in width:
			var p: Vector3 = ring[k]
			var across: Vector3 = (ring[mini(k + 1, width - 1)] as Vector3) - (ring[maxi(k - 1, 0)] as Vector3)
			var along: Vector3 = (rings[mini(i + 1, rings.size() - 1)][k] as Vector3) - (rings[maxi(i - 1, 0)][k] as Vector3)
			var normal := across.cross(along).normalized()
			if normal.y < 0.0:
				normal = -normal
			var up := p.y - position.y
			var col := _stone(p, normal.y)
			st.set_color(col)
			st.set_uv(Vector2(p.x, p.z) * 0.1)
			st.add_vertex(p - position)
			if plant and normal.y > 0.72 and up > 7.0 and (i + 2 * k) % 5 == 0:
				var jitter := Vector3(sin(i * 3.1 + k), 0.0, cos(i * 1.7 + k * 2.3)) * 0.8
				var size := 2.0 + 1.3 * (0.5 + 0.5 * sin(i * 0.77 + k * 1.31))
				_shrubs.append(Transform3D(Basis(Vector3.UP, i * 0.9 + k).scaled(Vector3(size, size * 0.62, size)), p + jitter - Vector3.UP * 0.25))
				if absf(p.y - position.y) > 15.0 and (i * 7 + k * 3) % 29 == 0:
					_pines.append(Transform3D(Basis(Vector3.UP, i * 1.3).scaled(Vector3.ONE * (0.85 + 0.1 * sin(i))), p - Vector3.UP * 0.4))
	for i in rings.size() - 1:
		for k in width - 1:
			var a := first + i * width + k
			var b := a + 1
			var c := a + width
			var d := c + 1
			for index in ([a, b, c, b, d, c] if flip else [a, c, b, b, c, d]):
				st.add_index(index)
	count[0] = first + rings.size() * width


func _stone(p: Vector3, flat: float) -> Color:
	var n := 0.5 + 0.5 * sin(p.x * 0.21 + p.z * 0.17) * sin(p.y * 0.33 - p.x * 0.07)
	var stone := LIMESTONE.lerp(OCHRE, 0.45 * n)
	stone = stone.lerp(CREVICE, 0.35 * smoothstep(0.55, 0.95, 0.5 + 0.5 * sin(p.x * 0.53 - p.z * 0.61 + p.y * 0.4)))
	stone = stone.lerp(Color("#5d5a4a"), clampf((0.3 - (p.y - _terrain_water())) * 0.4, 0.0, 0.5))
	var green := smoothstep(0.62, 0.86, flat) * smoothstep(3.0, 9.0, p.y - position.y)
	return stone.lerp(MAQUIS.lerp(MAQUIS_DARK, n), green * 0.85)


func _terrain_water() -> float:
	return _terrain.water_surface if _terrain != null else -1.0


## Rock between the portal's ring and the top of the headwall, in ledges
## that step in and out of the face.
func _portal_face(st: SurfaceTool, ring: Array, s: float, facing: Vector3, count: Array) -> void:
	var rows: Array = []
	var layers := 6
	for layer in layers + 1:
		var t := float(layer) / layers
		var row: Array[Vector3] = []
		for k in range(_sea, _cut + 1):
			var top: Vector3 = ring[k]
			var bottom := _at(s, _profile[k][0], WALL_TOP)
			var p := top.lerp(bottom, t)
			var ledge := 0.9 * sin(t * PI) * sin(layer * 2.3 + k * 1.3) + 0.35 * sin(k * 2.9 + layer)
			row.append(p + facing * ledge)
		rows.append(row)
	_stitch(st, rows, count, false, facing)


# --------------------------------------------------------------- headwalls
## A concrete headwall across the road at each portal, the arch moulded in
## a projecting ring, a coping along the top.
func _headwalls(start: float, length: float) -> void:
	var st := LandmarkKit.begin()
	var half := _track.half_w + 1.18
	for end_s: float in [start, start + length]:
		var out := -1.0 if end_s == start else 1.0
		var facing := _track.tangent(end_s) * out
		var sea_edge := -SEA_FACE
		var in_edge := CUT_Q
		var front := func(q: float, up: float) -> Vector3: return _at(end_s, q, up) - position + facing * 0.05
		var back := func(q: float, up: float) -> Vector3: return _at(end_s, q, up) - position - facing * 0.9
		# Wall face: between the arch and the wall's outline, radially.
		var arch: Array[Vector3] = []
		var outline: Array[Vector3] = []
		for j in ARCH_STEPS + 1:
			var angle := PI * float(j) / ARCH_STEPS
			var across := cos(angle)
			var q := half * across * _inland_sign_of(end_s)
			arch.append(front.call(q, SPRING + RISE * sin(angle)))
			var edge := in_edge if q > 0.0 else sea_edge
			var dir := Vector2(across * _inland_sign_of(end_s), sin(angle))
			var reach := minf(absf(edge) / maxf(absf(dir.x), 1e-3), (WALL_TOP - SPRING) / maxf(dir.y, 1e-3))
			outline.append(front.call(dir.x * reach, SPRING + dir.y * reach))
		for j in ARCH_STEPS:
			LandmarkKit.quad_facing(st, arch[j], outline[j], outline[j + 1], arch[j + 1], CONCRETE, facing)
		# The wall's top corners, which fall between two radial steps.
		for corner: float in [in_edge, sea_edge]:
			var tip = front.call(corner, WALL_TOP)
			var near_j := 0
			var best := INF
			for j in ARCH_STEPS + 1:
				var dist: float = (outline[j] as Vector3).distance_to(tip)
				if dist < best:
					best = dist
					near_j = j
			for j in [near_j - 1, near_j]:
				if j >= 0 and j < ARCH_STEPS:
					LandmarkKit.quad_facing(st, outline[j], tip, outline[j + 1], outline[j + 1], CONCRETE, facing)
		# Below the springing, either side of the opening.
		for side: float in [-1.0, 1.0]:
			var edge := in_edge if side > 0.0 else sea_edge
			LandmarkKit.quad_facing(st, front.call(side * half, -0.6), front.call(side * absf(edge), -0.6),
				front.call(side * absf(edge), SPRING), front.call(side * half, SPRING), CONCRETE.darkened(0.04), facing)
		# The arch ring, standing proud of the wall, and its reveal.
		for j in ARCH_STEPS:
			var a0 := PI * float(j) / ARCH_STEPS
			var a1 := PI * float(j + 1) / ARCH_STEPS
			var r0 := Vector2(cos(a0), sin(a0))
			var r1 := Vector2(cos(a1), sin(a1))
			var sgn := _inland_sign_of(end_s)
			var i0 = front.call(half * r0.x * sgn, SPRING + RISE * r0.y)
			var i1 = front.call(half * r1.x * sgn, SPRING + RISE * r1.y)
			var o0 = front.call((half + 0.75) * r0.x * sgn, SPRING + (RISE + 0.75) * r0.y) + facing * 0.3
			var o1 = front.call((half + 0.75) * r1.x * sgn, SPRING + (RISE + 0.75) * r1.y) + facing * 0.3
			LandmarkKit.quad_facing(st, i0 + facing * 0.3, o0, o1, i1 + facing * 0.3, Color.WHITE.darkened(0.12), facing)
			LandmarkKit.quad_facing(st, o0, o0 - facing * 0.3, o1 - facing * 0.3, o1, CONCRETE.darkened(0.1), Vector3.UP)
			LandmarkKit.quad_facing(st, i0 - facing * 0.95, i0 + facing * 0.3, i1 + facing * 0.3, i1 - facing * 0.95, CONCRETE.darkened(0.2), -Vector3.UP)
		# Coping along the top, and the wall's ends.
		var c0 = front.call(sea_edge, WALL_TOP)
		var c1 = front.call(in_edge, WALL_TOP)
		var b0 = back.call(sea_edge, WALL_TOP)
		var b1 = back.call(in_edge, WALL_TOP)
		LandmarkKit.quad_facing(st, c0 + facing * 0.25, c1 + facing * 0.25, b1, b0, Color.WHITE.darkened(0.1), Vector3.UP)
		LandmarkKit.quad_facing(st, c0 + facing * 0.25 - Vector3.UP * 0.45, c1 + facing * 0.25 - Vector3.UP * 0.45,
			c1 + facing * 0.25, c0 + facing * 0.25, Color.WHITE.darkened(0.16), facing)
	var mat := LandmarkKit.material(0.9)
	mat.albedo_texture = preload("res://assets/textures/landmark_concrete.jpg")
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3.ONE * 0.3
	add_child(LandmarkKit.mesh_node(st, mat, "PortalHeadwalls", 1200.0))


## +1 when q (inland) maps to the track's right normal at s, else -1:
## the arch is symmetric, but the wall's edges are not.
func _inland_sign_of(_s: float) -> float:
	return 1.0


# ------------------------------------------------------------ the seawall
func _seawall(track: RaceTrack, start: float, length: float, coast_side: float, terrain: Terrain) -> void:
	var st := LandmarkKit.begin()
	for approach in [start - 62.0, start + length]:
		for i in 20:
			var s: float = approach + i * 3.1
			var inside := (track.half_w + 0.95) * coast_side
			var outside := (track.half_w + 3.25) * coast_side
			var a := track.pos(s, outside) - position
			var b := track.pos(s + 3.1, outside) - position
			var a_base := a + position
			var b_base := b + position
			a_base.y = terrain.height_at(a_base.x, a_base.z) - 0.48
			b_base.y = terrain.height_at(b_base.x, b_base.z) - 0.48
			var tint := ROCK.lightened(0.13 + 0.04 * cos(i * 2.4))
			LandmarkKit.quad_facing(st, a_base - position, b_base - position, b, a, tint, track.normal(s) * coast_side)
			LandmarkKit.quad_facing(st, a, b, track.pos(s + 3.1, inside) - position, track.pos(s, inside) - position, tint.lightened(0.15), Vector3.UP)
	var mat := LandmarkKit.material()
	mat.albedo_texture = preload("res://assets/textures/concrete_wall_diff.jpg")
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3.ONE * 0.34
	add_child(LandmarkKit.mesh_node(st, mat, "CoastalRetainingWall", 600.0))


# ------------------------------------------------------------ the pier walk
## A concrete walk on pillars round the foot of the seaward cliff, with a
## rail on its sea side, from the beach before the north portal to past
## the south one.
func _pier(start: float, length: float) -> void:
	var st := LandmarkKit.begin()
	var water := _terrain_water()
	var inner := 40.2
	var outer := 43.4
	var from := start - 26.0
	var to := start + length + 14.0
	var steps := ceili((to - from) / 3.0)
	var prev := []
	for i in steps + 1:
		var s := from + (to - from) * i / steps
		var deck := water + 3.1
		var a := _at(s, -inner, 0.0)
		var b := _at(s, -outer, 0.0)
		a.y = deck
		b.y = deck
		var row := [a - position, b - position]
		if i > 0:
			LandmarkKit.quad_facing(st, prev[0], row[0], row[1], prev[1], CONCRETE.lightened(0.08), Vector3.UP)
			LandmarkKit.quad_facing(st, prev[1], row[1], row[1] - Vector3.UP * 0.45, prev[1] - Vector3.UP * 0.45, CONCRETE.darkened(0.1), (b - a).normalized())
			LandmarkKit.quad_facing(st, prev[1] + Vector3.UP * 1.0, row[1] + Vector3.UP * 1.0, row[1] + Vector3.UP * 1.08, prev[1] + Vector3.UP * 1.08, Color("#9aa3a6"), (b - a).normalized())
		if i % 2 == 0:
			for p in row:
				LandmarkKit.box(st, p - Vector3.UP * 3.4, Vector3(0.55, 6.0, 0.55), CONCRETE.darkened(0.15))
			LandmarkKit.box(st, row[1] + Vector3.UP * 0.5, Vector3(0.07, 1.0, 0.07), Color("#8a9396"))
		prev = row
	add_child(LandmarkKit.mesh_node(st, LandmarkKit.material(0.85), "PierWalk", 700.0))


# ------------------------------------------------------------- vegetation
## Maquis on the headland's gentler ground and a few pines on its crest.
func _vegetation() -> void:
	if _shrubs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _shrub_mesh()
	mm.instance_count = _shrubs.size()
	for i in _shrubs.size():
		var t := _shrubs[i]
		t.origin -= position
		mm.set_instance_transform(i, t)
		mm.set_instance_color(i, Color.WHITE.darkened(0.25 * (0.5 + 0.5 * sin(i * 2.7))))
	var node := MultiMeshInstance3D.new()
	node.name = "HeadlandMaquis"
	node.multimesh = mm
	node.material_override = LandmarkKit.material(0.95)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = 700.0
	add_child(node)
	_maquis = mm
	_thin_maquis()
	Quality.budget_changed.connect(_thin_maquis)
	if not _pines.is_empty():
		# The pine model is detailed: a handful on the crest, fewer on Low.
		var pines := PineForestMultiMesh.new()
		pines.name = "HeadlandPines"
		add_child(pines)
		var local: Array[Transform3D] = []
		var cap := maxi(2, roundi(MAX_PINES * clampf(float(Quality.p.tree_mul), 0.0, 1.0)))
		var stride := maxi(1, ceili(float(_pines.size()) / cap))
		for k in range(0, _pines.size(), stride):
			local.append(Transform3D(_pines[k].basis, _pines[k].origin - position))
		pines.build_forest(local.slice(0, cap))


## The tree budget thins the maquis evenly (the sites are interleaved).
func _thin_maquis() -> void:
	if _maquis != null:
		_maquis.visible_instance_count = roundi(_maquis.instance_count * clampf(float(Quality.p.tree_mul), 0.25, 1.0))


## A low, lumpy maquis shrub about a metre across.
static func _shrub_mesh() -> ArrayMesh:
	var st := LandmarkKit.begin()
	for k in 3:
		var at := Vector3(cos(k * 2.1) * 0.34, 0.36 + 0.1 * (k % 2), sin(k * 2.1) * 0.34)
		var col := MAQUIS.lerp(Color("#6b7440"), 0.3 * (k % 3)).lightened(0.05 * k)
		LandmarkKit.sphere(st, at, Vector3(0.66, 0.52, 0.62), col, 3, 5)
	return st.commit()


func _process(_dt: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var budget := mini(2, int(Quality.p.fx_light_limit))
	var closest: OmniLight3D
	var second: OmniLight3D
	var closest_distance := 24.0 * 24.0
	var second_distance := closest_distance
	if camera != null and budget > 0:
		for light in _lights:
			var distance := light.global_position.distance_squared_to(camera.global_position)
			if distance < closest_distance:
				second = closest
				second_distance = closest_distance
				closest = light
				closest_distance = distance
			elif distance < second_distance:
				second = light
				second_distance = distance
	for light in _lights:
		light.visible = light == closest or (budget > 1 and light == second)
