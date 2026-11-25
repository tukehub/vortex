class_name VloreBoulevard
extends Node3D
## The boulevard from Sheshi i Flamurit past the Muradie Mosque to Teatri
## Petro Marko as a city street rather than a circuit: from boulevard.json
## (tools/pipeline/vlore_boulevard.py) the race kerbs, barriers and shoulder
## give way (RoadMesh.street) to
##   kerbs     granite kerbstones along both outer edges, dropped at the
##             mouths of the side roads
##   sidewalks paving (CC0 Promenade Paving) out to SIDEWALK metres, or up
##             to a building's wall where one stands nearer
##   verge     a planted strip of lawn beyond (CC0 grass) with a clipped
##             hedge along its back, broken for paths; none over the side
##             roads, the buildings or the landmark plots (the mosque
##             garden, the monument square)
##   palms     a row of palms down the verge
##   benches   on the sidewalk's back edge facing the road, with bins
## Visual only: the cars keep the road's own boundary.

const DATA := "res://assets/cities/%s/boulevard.json"
const ROAD := 1
const BUILDING := 2
const LANDMARK := 4
const KERB_W := 0.32
const SIDEWALK := 5.0
const VERGE := 9.0
## A side road whose ribbon ends within this far beyond the sidewalk's
## width makes a junction mouth: asphalt out to it, no kerb or sidewalk.
const MOUTH_REACH := 4.0
const PALM_EVERY := 15.0
const BENCH_EVERY := 30.0
const HEDGE_H := 0.85
const HEDGE_W := 0.8
const REACH := 900.0

var kerb_m := 0.0
var sidewalk_m := 0.0
var verge_m := 0.0
var palms := 0
var benches := 0
var mouths := 0

var _data: Dictionary
var _grid := PackedByteArray()
var _gx0 := 0.0
var _gz0 := 0.0
var _cell := 1.0
var _gw := 0
var _gh := 0


static func load_data(city_id: String) -> Dictionary:
	var path := DATA % city_id
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


## 1 for every sample of either pass within the stretch's radius of its line.
static func street_samples(track: RaceTrack, data: Dictionary) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(track.M)
	var line := PackedVector2Array()
	var box := Rect2()
	for p: Array in data.get("line", []):
		var q := Vector2(float(p[0]), float(p[1]))
		box = Rect2(q, Vector2.ZERO) if line.is_empty() else box.expand(q)
		line.append(q)
	if line.size() < 2:
		return out
	var r := float(data.get("radius", 15.0))
	box = box.grow(r)
	for k in track.M:
		var q := Vector2(track.X[k], track.Z[k])
		if not box.has_point(q):
			continue
		for i in line.size() - 1:
			if q.distance_to(Geometry2D.get_closest_point_to_segment(q, line[i], line[i + 1])) < r:
				out[k] = 1
				break
	return out


func build(track: RaceTrack, data: Dictionary, street: PackedByteArray, terrain: Terrain) -> void:
	name = "VloreBoulevard"
	_data = data
	_decode(data.grid)
	var hw := track.half_w
	var kerb := ArchKit.begin()
	var paving := ArchKit.begin()
	var lawn := ArchKit.begin()
	var hedge := ArchKit.begin()
	var apron := ArchKit.begin()
	var palm_rows: Array = []
	var bench_rows: Array = []
	var bin_rows: Array = []
	var ground := func(p: Vector3) -> float: return terrain.height_at(p.x, p.z) if terrain != null else p.y - 0.1
	for side: float in [-1.0, 1.0]:
		# Sidewalk and verge widths per sample on this side.
		var walk := PackedFloat32Array()
		var green := PackedFloat32Array()
		var mouth_to := PackedFloat32Array()
		walk.resize(track.M)
		green.resize(track.M)
		mouth_to.resize(track.M)
		for k in track.M:
			if street[k] == 0:
				continue
			var at := Vector2(track.X[k], track.Z[k])
			var n := Vector2(track.NX[k], track.NZ[k]) * side
			var side_road := _reach(at, n, hw + KERB_W, SIDEWALK + MOUTH_REACH, ROAD)
			mouth_to[k] = side_road if side_road < SIDEWALK + MOUTH_REACH else -1.0
			walk[k] = _reach(at, n, hw + KERB_W, SIDEWALK, ROAD | BUILDING)
			if walk[k] >= SIDEWALK - 0.01:
				green[k] = _reach(at, n, hw + KERB_W + SIDEWALK, VERGE, ROAD | BUILDING | LANDMARK)
		var along := 0.0
		var next_palm := PALM_EVERY * 0.5
		var next_bench := BENCH_EVERY * 0.5
		for i in track.M:
			var j := (i + 1) % track.M
			if street[i] == 0 or street[j] == 0 or RoadMesh.open_side(track, i, side):
				continue
			if mouth_to[i] >= 0.0 or mouth_to[j] >= 0.0:
				_mouth(apron, track, i, j, side, hw, maxf(mouth_to[i], mouth_to[j]), ground)
				mouths += 1
				continue
			var ends: Array[Dictionary] = []
			for k: int in [i, j]:
				var p := Vector3(track.X[k], track.Y[k], track.Z[k])
				var n := Vector3(track.NX[k], 0.0, track.NZ[k]) * side
				ends.append({"p": p, "n": n, "w": walk[k], "v": green[k]})
			_kerb_and_walk(kerb, paving, ends, hw, ground)
			var seg := Vector3(track.X[j] - track.X[i], 0, track.Z[j] - track.Z[i]).length()
			kerb_m += seg
			sidewalk_m += seg
			var a: Dictionary = ends[0]
			var b: Dictionary = ends[1]
			var verge_ok := float(a.v) >= 2.5 and float(b.v) >= 2.5
			if verge_ok:
				_verge(lawn, hedge, ends, hw, ground, int(along / 6.0) % 5 == 4)
				verge_m += seg
			# Palms down the verge, benches on the sidewalk's back edge.
			while next_palm < along + seg:
				var t := (next_palm - along) / seg
				var p: Vector3 = (a.p as Vector3).lerp(b.p, t)
				var n: Vector3 = (a.n as Vector3).lerp(b.n, t).normalized()
				if verge_ok:
					var at := p + n * (hw + KERB_W + SIDEWALK + 1.9)
					var h := 0.95 + 0.22 * fposmod(sin(at.x * 12.9898 + at.z * 78.233) * 43758.5, 1.0)
					palm_rows.append([at.x, float(ground.call(at)) + 0.05, at.z, h, fposmod(at.x * 0.37 + at.z * 0.11, TAU)])
					palms += 1
				next_palm += PALM_EVERY
			while next_bench < along + seg:
				var t := (next_bench - along) / seg
				var p: Vector3 = (a.p as Vector3).lerp(b.p, t)
				var n: Vector3 = (a.n as Vector3).lerp(b.n, t).normalized()
				var w := lerpf(float(a.w), float(b.w), t)
				if w >= SIDEWALK - 0.2:
					var at := p + n * (hw + KERB_W + w - 0.75)
					var yaw := atan2(n.x, n.z)  # -Z (the seat's front) toward the road
					bench_rows.append([at.x, at.z, yaw])
					var tangent := Vector3(-n.z, 0, n.x)
					var bin := at + tangent * 1.5
					bin_rows.append([bin.x, bin.z, yaw])
					benches += 1
				next_bench += BENCH_EVERY
			along += seg
	var granite := ArchKit.material(preload("res://assets/textures/square_granite_diff.jpg"),
		preload("res://assets/textures/square_granite_nor.jpg"), preload("res://assets/textures/square_granite_arm.jpg"), 1.2, Color(0.92, 0.92, 0.94), 0.6)
	add_child(_node(kerb, granite, "GraniteKerbs"))
	var paving_mat := ArchKit.material(preload("res://assets/textures/promenade_paving_diff.jpg"),
		preload("res://assets/textures/promenade_paving_nor.jpg"), preload("res://assets/textures/promenade_paving_arm.jpg"), 2.4, Color(0.86, 0.86, 0.88), 0.8)
	add_child(_node(paving, paving_mat, "Sidewalks"))
	var asphalt := ArchKit.material(preload("res://assets/textures/asphalt_diff.jpg"),
		preload("res://assets/textures/asphalt_nor.jpg"), preload("res://assets/textures/asphalt_arm.jpg"), 4.0, Color(0.92, 0.92, 0.92), 0.5)
	add_child(_node(apron, asphalt, "JunctionMouths"))
	var lawn_mat := ArchKit.material(preload("res://assets/textures/grass_diff.jpg"),
		preload("res://assets/textures/grass_nor.jpg"), null, 2.2, Color(0.82, 0.92, 0.72), 0.7)
	lawn_mat.roughness = 0.95
	add_child(_node(lawn, lawn_mat, "Verge"))
	var hedge_mat := ArchKit.material(preload("res://assets/textures/grass_diff.jpg"),
		preload("res://assets/textures/grass_nor.jpg"), null, 0.9, Color(0.48, 0.62, 0.40), 1.0)
	hedge_mat.roughness = 0.9
	add_child(_node(hedge, hedge_mat, "Hedges"))
	if not palm_rows.is_empty():
		var p := Palms.new()
		add_child(p)
		p.build(palm_rows)
		p.name = "BoulevardPalms"
	if not bench_rows.is_empty():
		var furniture := StreetProps.new()
		furniture.name = "BoulevardFurniture"
		add_child(furniture)
		var top := func(x: float, z: float) -> float:
			var n := track.nearest(x, z, 30.0)
			return (track.Y[n] if n >= 0 else 0.0) + RoadMesh.KERB_H + 0.02
		furniture.build({"bench": bench_rows, "bin": bin_rows}, top)


func _node(st: SurfaceTool, mat: Material, node_name: String) -> MeshInstance3D:
	st.generate_tangents()
	var n := ArchKit.node(st, mat, node_name, REACH)
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


## Kerbstone (its road face and top) and the sidewalk behind it, falling 2 %
## to the kerb, with a face down to the ground at its back.
func _kerb_and_walk(kerb: SurfaceTool, paving: SurfaceTool, ends: Array[Dictionary], hw: float, ground: Callable) -> void:
	var a: Dictionary = ends[0]
	var b: Dictionary = ends[1]
	var top := RoadMesh.KERB_H
	var pa: Vector3 = a.p
	var pb: Vector3 = b.p
	var na: Vector3 = a.n
	var nb: Vector3 = b.n
	var up := Vector3.UP
	# Road face of the kerb, a hair proud of the asphalt's edge.
	var a0 := pa + na * hw + up * -0.04
	var b0 := pb + nb * hw + up * -0.04
	var a1 := pa + na * hw + up * top
	var b1 := pb + nb * hw + up * top
	ArchKit.wall_quad(kerb, a0, b0, b1, a1, Color.WHITE, -na)
	var a2 := pa + na * (hw + KERB_W) + up * top
	var b2 := pb + nb * (hw + KERB_W) + up * top
	ArchKit.wall_quad(kerb, a1, b1, b2, a2, Color.WHITE, up)
	var wa := float(a.w)
	var wb := float(b.w)
	var a3 := pa + na * (hw + KERB_W + wa) + up * (top + wa * 0.02)
	var b3 := pb + nb * (hw + KERB_W + wb) + up * (top + wb * 0.02)
	ArchKit.wall_quad(paving, a2, b2, b3, a3, Color.WHITE, up)
	var a4 := Vector3(a3.x, minf(float(ground.call(a3)) - 0.25, a3.y - 0.2), a3.z)
	var b4 := Vector3(b3.x, minf(float(ground.call(b3)) - 0.25, b3.y - 0.2), b3.z)
	ArchKit.wall_quad(kerb, a4, b4, b3, a3, Color(0.86, 0.86, 0.86), na)


## Asphalt from the road's edge out to a side road's ribbon (it stops short
## of the race road), easing from the road's height to the ground's.
func _mouth(st: SurfaceTool, track: RaceTrack, i: int, j: int, side: float, hw: float, reach: float, ground: Callable) -> void:
	var rows: Array = []
	var cols := 3
	for k: int in [i, j]:
		var p := Vector3(track.X[k], track.Y[k] - 0.01, track.Z[k])
		var n := Vector3(track.NX[k], 0.0, track.NZ[k]) * side
		var row: Array[Vector3] = []
		for c in cols + 1:
			var t := float(c) / cols
			var q := p + n * lerpf(hw - 0.1, hw + KERB_W + reach + 1.0, t)
			q.y = lerpf(p.y, float(ground.call(q)) + 0.03, smoothstep(0.0, 1.0, t))
			row.append(q)
		rows.append(row)
	for c in cols:
		ArchKit.wall_quad(st, rows[0][c], rows[1][c], rows[1][c + 1], rows[0][c + 1], Color.WHITE, Vector3.UP)


## The lawn from the sidewalk's back out to the verge's width, on the ground,
## and the hedge along its back (a gap where `gap`).
func _verge(lawn: SurfaceTool, hedge: SurfaceTool, ends: Array[Dictionary], hw: float, ground: Callable, gap: bool) -> void:
	var a: Dictionary = ends[0]
	var b: Dictionary = ends[1]
	var inner := hw + KERB_W + SIDEWALK
	var cols := 4
	var rows: Array = []
	for e: Dictionary in ends:
		var row: Array[Vector3] = []
		for c in cols + 1:
			var p: Vector3 = e.p + (e.n as Vector3) * (inner + float(e.v) * c / cols)
			p.y = float(ground.call(p)) + 0.07
			row.append(p)
		rows.append(row)
	for c in cols:
		ArchKit.wall_quad(lawn, rows[0][c], rows[1][c], rows[1][c + 1], rows[0][c + 1], Color.WHITE, Vector3.UP)
	if gap or float(a.v) < VERGE - 0.5 or float(b.v) < VERGE - 0.5:
		return
	var na: Vector3 = a.n
	var nb: Vector3 = b.n
	var ha: Vector3 = rows[0][cols] - na * HEDGE_W
	var hb: Vector3 = rows[1][cols] - nb * HEDGE_W
	var h := Vector3.UP * HEDGE_H
	var lo := Vector3.DOWN * 0.1
	# Front, top (rounded off by a bevel), back.
	ArchKit.wall_quad(hedge, ha + lo, hb + lo, hb + h * 0.82, ha + h * 0.82, Color(0.92, 0.95, 0.9), -na)
	ArchKit.wall_quad(hedge, ha + h * 0.82, hb + h * 0.82, hb + nb * 0.12 + h, ha + na * 0.12 + h, Color.WHITE, -na + Vector3.UP)
	ArchKit.wall_quad(hedge, ha + na * 0.12 + h, hb + nb * 0.12 + h, hb + nb * HEDGE_W + h * 0.9, ha + na * HEDGE_W + h * 0.9, Color.WHITE, Vector3.UP)
	ArchKit.wall_quad(hedge, ha + na * HEDGE_W + lo, hb + nb * HEDGE_W + lo, hb + nb * HEDGE_W + h * 0.9, ha + na * HEDGE_W + h * 0.9, Color(0.85, 0.9, 0.84), na)


## Metres from `start` out along n (from the sample at `at`) before a cell
## flagged with any of `mask`, at most `limit`.
func _reach(at: Vector2, n: Vector2, start: float, limit: float, mask: int) -> float:
	var t := 0.0
	while t < limit:
		var q := at + n * (start + t + 0.25)
		if _flags(q) & mask:
			return t
		t += 0.5
	return limit


func _flags(q: Vector2) -> int:
	var cx := int(floor((q.x - _gx0) / _cell))
	var cz := int(floor((q.y - _gz0) / _cell))
	if cx < 0 or cz < 0 or cx >= _gw or cz >= _gh:
		return 0
	return _grid[cz * _gw + cx]


## Flags at a world point (tests).
func flags_at(x: float, z: float) -> int:
	return _flags(Vector2(x, z))


func _decode(grid: Dictionary) -> void:
	_gx0 = float(grid.x0)
	_gz0 = float(grid.z0)
	_cell = float(grid.cell)
	_gw = int(grid.w)
	_gh = int(grid.h)
	_grid.resize(_gw * _gh)
	var r := 0
	for row: Array in grid.rows:
		var c := r * _gw
		for i in range(0, row.size(), 2):
			var value := int(row[i])
			var run := int(row[i + 1])
			if value != 0:
				for k in run:
					_grid[c + k] = value
			c += run
		r += 1
