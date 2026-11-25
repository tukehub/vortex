class_name CityRiver
extends Node3D
## A river through the city, from river.json (tools/pipeline/river.py): the
## Osum through Berat.
##   water        a ribbon at the baked level, wide as mapped and narrowed
##                where a road runs beside it, its ripples carried downstream
##                (shaders/river.gdshader);
##   banks        gravel (CC0 river pebbles) from under the water's edge up to
##                the ground, or, where the road runs close, a riprap
##                embankment of rubble stone up to a paved walk;
##   race bridges where the race road crosses: a concrete deck under the
##                road, parapets with a rail, piers in the river;
##   footbridges  the mapped footbridges over it: an Ottoman stone bridge of
##                arches (Ura e Goricës) or a light suspension bridge.
## Scenery only: the race road and driving are unchanged.

const SHADER := preload("res://shaders/river.gdshader")
const CHUNK := 70                 # river samples per water mesh (350 m)
const GRAVEL := 16.0              # metres of gravel bank beyond the water
const REACH := 3600.0

var sample := 5.0
var pts := PackedVector2Array()
var tan := PackedVector2Array()
var surface := PackedFloat32Array()
var wl := PackedFloat32Array()
var wr := PackedFloat32Array()
var bank_l := PackedInt32Array()
var bank_r := PackedInt32Array()
var top_l := PackedFloat32Array()
var top_r := PackedFloat32Array()
var data: Dictionary = {}
var water_mat: ShaderMaterial
## For tests: water meshes, embankment metres, bridges and arches built.
var water_chunks := 0
var wall_metres := 0.0
var race_bridges := 0
var arches := 0
var footbridges := 0

var _terrain: Terrain


static func path_for(city_id: String) -> String:
	return "res://assets/cities/%s/river.json" % city_id


func build(city_id: String, terrain: Terrain, track: RaceTrack) -> bool:
	if not FileAccess.file_exists(path_for(city_id)):
		return false
	name = "River"
	_terrain = terrain
	data = JSON.parse_string(FileAccess.get_file_as_string(path_for(city_id)))
	sample = float(data.get("sample", 5.0))
	for i in data.x.size():
		pts.append(Vector2(float(data.x[i]), float(data.z[i])))
		surface.append(float(data.surface[i]))
		wl.append(float(data.wl[i]))
		wr.append(float(data.wr[i]))
		bank_l.append(int(data.bank_l[i]))
		bank_r.append(int(data.bank_r[i]))
		top_l.append(float(data.top_l[i]))
		top_r.append(float(data.top_r[i]))
	for i in pts.size():
		var t := pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]
		tan.append(t.normalized())
	_water()
	_banks()
	for bridge: Dictionary in data.get("bridges", []):
		_race_bridge(bridge, track)
	for foot: Dictionary in data.get("footbridges", []):
		if str(foot.structure) == "arch":
			_stone_bridge(foot)
		else:
			_light_bridge(foot)
	return true


func set_env(wet: float, night: float) -> void:
	if water_mat != null:
		water_mat.set_shader_parameter("wetness", wet)
		water_mat.set_shader_parameter("night", night)


## Left of the flow, in xz.
func _left(i: int) -> Vector2:
	return Vector2(-tan[i].y, tan[i].x)


func _ground(x: float, z: float) -> float:
	return _terrain.height_at(x, z) if _terrain != null else 0.0


func _v(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


# ------------------------------------------------------------------ water

func _water() -> void:
	water_mat = ShaderMaterial.new()
	water_mat.shader = SHADER
	var lanes := [-1.0, -0.6, -0.25, 0.0, 0.25, 0.6, 1.0]
	var start := 0
	while start < pts.size() - 1:
		var end := mini(start + CHUNK, pts.size() - 1)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(start, end):
			for j in lanes.size() - 1:
				var quad := []
				for c in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
					var k: int = c[0]
					var f: float = lanes[c[1]]
					var lat := f * (wl[k] if f > 0.0 else wr[k])
					var p := pts[k] + _left(k) * lat
					quad.append([_v(p, surface[k]), Vector2(lat, k * sample), 1.0 - absf(f), tan[k]])
				for idx: int in [0, 1, 2, 0, 2, 3]:
					var q: Array = quad[idx]
					var flow: Vector2 = q[3]
					st.set_color(Color(q[2], flow.x * 0.5 + 0.5, flow.y * 0.5 + 0.5))
					st.set_normal(Vector3.UP)
					st.set_uv(q[1])
					st.add_vertex(q[0])
		var mi := MeshInstance3D.new()
		mi.name = "Water%d" % water_chunks
		mi.mesh = st.commit()
		mi.material_override = water_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = REACH
		add_child(mi)
		water_chunks += 1
		start = end


# ------------------------------------------------------------------ banks

func _banks() -> void:
	var gravel := SurfaceTool.new()
	gravel.begin(Mesh.PRIMITIVE_TRIANGLES)
	var riprap := SurfaceTool.new()
	riprap.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walk := SurfaceTool.new()
	walk.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [1.0, -1.0]:
		for i in pts.size() - 1:
			var j := i + 1
			var walled_i := (bank_l[i] if side > 0.0 else bank_r[i]) > 0
			var walled_j := (bank_l[j] if side > 0.0 else bank_r[j]) > 0
			if walled_i and walled_j:
				_embankment(riprap, walk, i, j, side)
			elif not walled_i and not walled_j:
				_gravel(gravel, i, j, side)
	var pebbles := ArchKit.material(preload("res://assets/textures/river_pebbles_diff.jpg"),
		preload("res://assets/textures/river_pebbles_nor.jpg"), preload("res://assets/textures/river_pebbles_arm.jpg"), 3.0,
		Color(1.02, 1.0, 0.96))
	var stones := ArchKit.material(preload("res://assets/textures/castle_wall_diff.jpg"),
		preload("res://assets/textures/castle_wall_nor.jpg"), preload("res://assets/textures/castle_wall_arm.jpg"), 2.6,
		Color(1.12, 1.1, 1.06))
	var paving := ArchKit.material(preload("res://assets/textures/promenade_paving_diff.jpg"),
		preload("res://assets/textures/promenade_paving_nor.jpg"), preload("res://assets/textures/promenade_paving_arm.jpg"), 2.4)
	for part in [[gravel, pebbles, "GravelBanks"], [riprap, stones, "Embankment"], [walk, paving, "RiverWalk"]]:
		var st: SurfaceTool = part[0]
		st.generate_normals()
		var mi := ArchKit.node(st, part[1], part[2], REACH)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


## Gravel from just under the water to the ground beyond, draped over the
## carved terrain and never below the water.
func _gravel(st: SurfaceTool, i: int, j: int, side: float) -> void:
	var offs := [-1.6, 0.5, 3.0, 6.5, 10.5, GRAVEL]
	var rows := []
	for k in [i, j]:
		var w: float = wl[k] if side > 0.0 else wr[k]
		var row := []
		for n in offs.size():
			var o: float = offs[n]
			var p := pts[k] + _left(k) * side * (w + o)
			var y := surface[k] - 0.14 if n == 0 else maxf(_ground(p.x, p.y) + 0.07, surface[k] + 0.05 + maxf(o, 0.0) * 0.05)
			if n == offs.size() - 1:
				y = _ground(p.x, p.y) + 0.04
			row.append(_v(p, y))
		rows.append(row)
	for n in offs.size() - 1:
		var quad := [rows[0][n], rows[1][n], rows[1][n + 1], rows[0][n + 1]]
		_strip(st, quad, Color(1, 1, 1) if n > 0 else Color(0.82, 0.84, 0.8))


## A stone retaining wall from under the water up to the road's level, a
## coping along its top and a paved riverside walk back to the road.
func _embankment(stones: SurfaceTool, walk: SurfaceTool, i: int, j: int, side: float) -> void:
	var rows := []
	for k in [i, j]:
		var w: float = wl[k] if side > 0.0 else wr[k]
		var top: float = top_l[k] if side > 0.0 else top_r[k]
		var l := _left(k) * side
		rows.append([_v(pts[k] + l * w, surface[k] - 2.2), _v(pts[k] + l * w, top + 0.2),
			_v(pts[k] + l * (w + 0.55), top + 0.2), _v(pts[k] + l * (w + 0.55), top),
			_v(pts[k] + l * (w + 7.4), top + 0.05)])
	# The wall face, toward the water (UV: wall courses).
	var a: Vector3 = rows[0][0]
	var b: Vector3 = rows[1][0]
	var out := Vector3(-_left(i).x * side, 0, -_left(i).y * side)
	ArchKit.wall_quad(stones, a, b, rows[1][1], rows[0][1], Color(1, 1, 1), out)
	ArchKit.quad_uv(stones, rows[0][1], rows[1][1], rows[1][2], rows[0][2], Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.3), Vector2(0, 0.3),
		Color(1.1, 1.08, 1.04), Vector3.UP)
	_strip(walk, [rows[0][3], rows[1][3], rows[1][4], rows[0][4]], Color(1, 1, 1))
	wall_metres += pts[i].distance_to(pts[j])


## Two triangles facing up (UV: plan metres for gravel and paving, slope
## metres for riprap — both read the same at this scale).
func _strip(st: SurfaceTool, q: Array, col: Color) -> void:
	var a: Vector3 = q[0]
	var b: Vector3 = q[1]
	var c: Vector3 = q[2]
	var d: Vector3 = q[3]
	var n := (b - a).cross(d - a)
	var order := [a, c, b, a, d, c] if n.y > 0.0 else [a, b, c, a, c, d]
	for p: Vector3 in order:
		st.set_color(col)
		st.set_uv(Vector2(p.x, p.z + p.y * 0.7))
		st.add_vertex(p)


# ------------------------------------------------------------------ race bridges

## The race road's crossing: a deck slab under the road, fascia, parapets
## with a steel rail, and piers in the river aligned with the current.
func _race_bridge(bridge: Dictionary, track: RaceTrack) -> void:
	var a := Vector2(float(bridge.a[0]), float(bridge.a[1]))
	var b := Vector2(float(bridge.b[0]), float(bridge.b[1]))
	var s0 := track.locate_xz(a.x, a.y).x
	var s1 := track.locate_xz(b.x, b.y).x
	if s1 < s0:
		var t := s0
		s0 = s1
		s1 = t
	if s1 - s0 > 400.0:
		return
	var concrete := ArchKit.begin()
	var rail := ArchKit.begin()
	var half := track.half_w + 1.6
	var steps := maxi(2, int((s1 - s0) / 2.0))
	var prev := []
	for k in steps + 1:
		var s := lerpf(s0, s1, float(k) / steps)
		var l := track.pos(s, -half)
		var r := track.pos(s, half)
		var row := [l, r]
		if not prev.is_empty():
			var pl: Vector3 = prev[0]
			var pr: Vector3 = prev[1]
			# Underside, fascias and parapets.
			ArchKit.quad_uv(concrete, pl + Vector3.DOWN * 1.5, pr + Vector3.DOWN * 1.5, r + Vector3.DOWN * 1.5, l + Vector3.DOWN * 1.5,
				Vector2(0, 0), Vector2(2 * half, 0), Vector2(2 * half, 2), Vector2(0, 2), Color(0.86, 0.86, 0.84), Vector3.DOWN)
			for e in [[pl, l], [pr, r]]:
				var p: Vector3 = e[0]
				var q: Vector3 = e[1]
				var out := (q - p).cross(Vector3.UP).normalized()
				if out.dot(p - (pl + pr) * 0.5) < 0.0:
					out = -out
				ArchKit.wall_quad(concrete, p + Vector3.DOWN * 1.5, q + Vector3.DOWN * 1.5, q + Vector3.UP * 1.0, p + Vector3.UP * 1.0, Color(0.9, 0.9, 0.88), out)
				ArchKit.wall_quad(concrete, p - out * 0.32 + Vector3.UP * 0.05, q - out * 0.32 + Vector3.UP * 0.05,
					q - out * 0.32 + Vector3.UP * 1.0, p - out * 0.32 + Vector3.UP * 1.0, Color(0.9, 0.9, 0.88), -out)
				ArchKit.wall_quad(concrete, p + Vector3.UP * 1.0, q + Vector3.UP * 1.0, q - out * 0.32 + Vector3.UP * 1.0, p - out * 0.32 + Vector3.UP * 1.0, Color(0.95, 0.95, 0.93), Vector3.UP)
				var mid := (p + q) * 0.5 - out * 0.16 + Vector3.UP * 1.32
				ArchKit.box(rail, mid, Vector3(0.08, 0.08, p.distance_to(q) + 0.02), Color(0.72, 0.74, 0.76), Basis.looking_at((q - p).normalized(), Vector3.UP))
				if k % 2 == 0:
					ArchKit.box(rail, q - out * 0.16 + Vector3.UP * 1.16, Vector3(0.06, 0.34, 0.06), Color(0.6, 0.62, 0.64))
		prev = row
	# Piers every ~24 m where the deck is over the water.
	var i := int(bridge.river)
	var flow := Vector3(tan[i].x, 0, tan[i].y)
	var count := maxi(1, int((s1 - s0) / 24.0))
	for k in range(1, count + 1):
		var s := lerpf(s0, s1, float(k) / (count + 1))
		var c := track.pos(s, 0.0)
		var bottom := surface[i] - 1.6
		var top := c.y - 1.5
		if top - bottom < 1.0:
			continue
		var basis := Basis.looking_at(flow, Vector3.UP)
		ArchKit.box(concrete, Vector3(c.x, (bottom + top) * 0.5, c.z), Vector3(2.0 * half - 3.0, top - bottom, 1.6), Color(0.84, 0.84, 0.82), basis)
		ArchKit.box(concrete, Vector3(c.x, top - 0.3, c.z), Vector3(2.0 * half - 1.0, 0.6, 2.2), Color(0.88, 0.88, 0.86), basis)
	var cmat := ArchKit.material(preload("res://assets/textures/concrete_wall_diff.jpg"),
		preload("res://assets/textures/concrete_wall_nor.jpg"), null, 3.0, Color(1.05, 1.05, 1.04))
	add_child(ArchKit.node(concrete, cmat, "RaceBridge%d" % race_bridges, REACH))
	var rmesh := ArchKit.node(rail, LandmarkKit.material(0.4, 0.7), "RaceBridgeRail%d" % race_bridges, 900.0)
	rmesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rmesh)
	race_bridges += 1


# ------------------------------------------------------------------ footbridges

## An Ottoman stone bridge (Ura e Goricës): arches on piers with pointed
## cutwaters, spandrels to a nearly level paved deck between low parapets.
func _stone_bridge(foot: Dictionary) -> void:
	var a := Vector2(float(foot.a[0]), float(foot.a[1]))
	var b := Vector2(float(foot.b[0]), float(foot.b[1]))
	var water := float(foot.surface)
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var side := Vector2(-dir.y, dir.x)
	var half := 2.9
	var ga := _ground(a.x, a.y)
	var gb := _ground(b.x, b.y)
	var bays := clampi(int(round(length / 12.0)), 3, 9)
	var bay := length / bays
	var pier := 2.4
	var span := bay - pier
	var spring := water + 0.7
	var rise := minf(span * 0.5, 4.4)
	var bed := water - 1.6
	var deck := func(t: float) -> float:
		var level := maxf(lerpf(ga, gb, t) + 0.25, water + 6.4 + 0.35 * sin(PI * t))
		var ends := smoothstep(0.0, 0.08, t) * smoothstep(1.0, 0.92, t)
		return lerpf(lerpf(ga, gb, t) + 0.25, level, ends)
	var stone := ArchKit.begin()
	var pave := ArchKit.begin()
	# Bottom of the bridge at u metres along: the arch intrados, or the riverbed
	# under a pier (abutments at both ends reach the ground).
	var soffit := func(u: float) -> float:
		var k := floori(u / bay)
		var local := u - k * bay - pier * 0.5
		if local < 0.0 or local > span or k < 0 or k >= bays:
			return bed
		var x := (local - span * 0.5) / (span * 0.5)
		return spring + rise * sqrt(maxf(0.0, 1.0 - x * x))
	var steps := bays * 16
	for k in steps:
		var u0 := length * k / steps
		var u1 := length * (k + 1) / steps
		var p0 := a + dir * u0
		var p1 := a + dir * u1
		var d0: float = deck.call(u0 / length)
		var d1: float = deck.call(u1 / length)
		var lo0: float = maxf(soffit.call(u0), minf(_ground(p0.x, p0.y) - 0.5, d0 - 0.6)) if (u0 < 3.0 or u0 > length - 3.0) else soffit.call(u0)
		var lo1: float = maxf(soffit.call(u1), minf(_ground(p1.x, p1.y) - 0.5, d1 - 0.6)) if (u1 < 3.0 or u1 > length - 3.0) else soffit.call(u1)
		for sgn: float in [-1.0, 1.0]:
			var o := side * sgn * half
			var out := Vector3(side.x * sgn, 0, side.y * sgn)
			# Elevation: from the arch (or pier foot) up to the parapet top.
			ArchKit.wall_quad(stone, _v(p0 + o, lo0), _v(p1 + o, lo1), _v(p1 + o, d1 + 0.95), _v(p0 + o, d0 + 0.95), Color(1, 1, 1), out)
			# Parapet inside face and its coping.
			var oi := side * sgn * (half - 0.45)
			ArchKit.wall_quad(stone, _v(p0 + oi, d0), _v(p1 + oi, d1), _v(p1 + oi, d1 + 0.95), _v(p0 + oi, d0 + 0.95), Color(0.95, 0.95, 0.93), -out)
			ArchKit.quad_uv(stone, _v(p0 + oi, d0 + 0.95), _v(p1 + oi, d1 + 0.95), _v(p1 + o, d1 + 0.95), _v(p0 + o, d0 + 0.95),
				Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 0.45), Vector2(u0, 0.45), Color(1.05, 1.04, 1.0), Vector3.UP)
		# Arch barrel (intrados) across the width.
		if lo0 > bed + 0.01 and lo1 > bed + 0.01:
			ArchKit.quad_uv(stone, _v(p0 - side * half, lo0), _v(p1 - side * half, lo1), _v(p1 + side * half, lo1), _v(p0 + side * half, lo0),
				Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 2 * half), Vector2(u0, 2 * half), Color(0.82, 0.82, 0.8), Vector3.DOWN)
		# The paved deck.
		ArchKit.quad_uv(pave, _v(p0 - side * (half - 0.45), d0), _v(p1 - side * (half - 0.45), d1), _v(p1 + side * (half - 0.45), d1),
			_v(p0 + side * (half - 0.45), d0), Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 2 * half), Vector2(u0, 2 * half), Color(1, 1, 1), Vector3.UP)
	# Pointed cutwaters on both faces of every pier.
	for k in range(1, bays):
		var u := k * bay
		var c := a + dir * u
		var top: float = spring + rise * 0.55
		for sgn: float in [-1.0, 1.0]:
			var face := c + side * sgn * half
			var nose := c + side * sgn * (half + 2.0)
			var l0 := face - dir * pier * 0.5
			var r0 := face + dir * pier * 0.5
			var out := Vector3(side.x * sgn, 0, side.y * sgn)
			ArchKit.wall_quad(stone, _v(l0, bed), _v(nose, bed), _v(nose, top), _v(l0, top), Color(0.96, 0.96, 0.94), out - Vector3(dir.x, 0, dir.y))
			ArchKit.wall_quad(stone, _v(nose, bed), _v(r0, bed), _v(r0, top), _v(nose, top), Color(0.96, 0.96, 0.94), out + Vector3(dir.x, 0, dir.y))
			# A sloped stone cap over the cutwater.
			var cap := _v(face, top + 1.4)
			stone.set_color(Color(0.98, 0.98, 0.96))
			for tri in [[_v(l0, top), _v(nose, top), cap], [_v(nose, top), _v(r0, top), cap]]:
				var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
				if n.y < 0.0:
					tri = [tri[0], tri[2], tri[1]]
					n = -n
				for p: Vector3 in tri:
					stone.set_normal(n)
					stone.set_uv(Vector2(p.x + p.z, -p.y))
					stone.add_vertex(p)
		arches += 1
	arches += 1
	var smat := ArchKit.material(preload("res://assets/textures/castle_wall_diff.jpg"),
		preload("res://assets/textures/castle_wall_nor.jpg"), preload("res://assets/textures/castle_wall_arm.jpg"), 2.4,
		Color(1.18, 1.16, 1.1))
	var pmat := ArchKit.material(preload("res://assets/textures/cobble_diff.jpg"), preload("res://assets/textures/rubble_wall_nor.jpg"), null, 2.0, Color(0.95, 0.93, 0.9))
	add_child(ArchKit.node(stone, smat, "StoneBridge%d" % footbridges, REACH))
	var deck_node := ArchKit.node(pave, pmat, "StoneBridgeDeck%d" % footbridges, 900.0)
	deck_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(deck_node)
	footbridges += 1


## A light footbridge: a slender deck slung from two white pylons by cables.
func _light_bridge(foot: Dictionary) -> void:
	var a := Vector2(float(foot.a[0]), float(foot.a[1]))
	var b := Vector2(float(foot.b[0]), float(foot.b[1]))
	var water := float(foot.surface)
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var side := Vector2(-dir.y, dir.x)
	var ga := _ground(a.x, a.y)
	var gb := _ground(b.x, b.y)
	var st := LandmarkKit.begin()
	var white := Color(0.93, 0.93, 0.92)
	var deck := func(t: float) -> float: return maxf(lerpf(ga, gb, t) + 0.3, water + 4.2) * smoothstep(0.0, 0.1, t) * smoothstep(1.0, 0.9, t) + (lerpf(ga, gb, t) + 0.3) * (1.0 - smoothstep(0.0, 0.1, t) * smoothstep(1.0, 0.9, t))
	var steps := 30
	for k in steps:
		var t0 := float(k) / steps
		var t1 := float(k + 1) / steps
		var p0 := a + dir * length * t0
		var p1 := a + dir * length * t1
		var y0: float = deck.call(t0)
		var y1: float = deck.call(t1)
		var c := (_v(p0, y0) + _v(p1, y1)) * 0.5
		var basis := Basis.looking_at(_v(p1, y1) - _v(p0, y0), Vector3.UP)
		LandmarkKit.box(st, c, Vector3(2.6, 0.35, _v(p0, y0).distance_to(_v(p1, y1)) + 0.02), Color(0.7, 0.68, 0.64), basis)
		for sgn: float in [-1.0, 1.0]:
			LandmarkKit.box(st, c + Vector3(side.x, 0, side.y) * sgn * 1.25 + Vector3.UP * 1.05, Vector3(0.06, 0.06, _v(p0, y0).distance_to(_v(p1, y1)) + 0.02), white, basis)
	var tops := []
	for t: float in [0.12, 0.88]:
		var p := a + dir * length * t
		var y: float = deck.call(t)
		for sgn: float in [-1.0, 1.0]:
			var base := _v(p + side * sgn * 1.6, y - 0.5)
			LandmarkKit.tube(st, base, base + Vector3.UP * 9.0, 0.22, 0.16, white, 8)
			tops.append(base + Vector3.UP * 9.0)
	for sgn: float in [0, 1]:
		var top_a: Vector3 = tops[sgn]
		var top_b: Vector3 = tops[2 + sgn]
		var prev := top_a
		for k in range(1, 13):
			var t := float(k) / 12.0
			var p := top_a.lerp(top_b, t) + Vector3.DOWN * 6.5 * sin(PI * t)
			LandmarkKit.tube(st, prev, p, 0.05, 0.05, white, 4)
			var under := Vector2(p.x, p.z)
			var along := clampf((under - a).dot(dir) / length, 0.0, 1.0)
			LandmarkKit.tube(st, p, Vector3(p.x, deck.call(along) + 1.1, p.z), 0.02, 0.02, white, 3)
			prev = p
	add_child(LandmarkKit.mesh_node(st, LandmarkKit.material(0.45, 0.3), "Footbridge%d" % footbridges, 1800.0))
	footbridges += 1
