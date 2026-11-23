class_name RozafaCastle
extends Node3D
## Rozafa castle on its hill above Shkodër, built from the castle's mapped
## outlines (assets/cities/shkoder/rozafa.json, baked by
## tools/pipeline/rozafa.py; data (c) OpenStreetMap contributors).
##   wall     the 920 m curtain wall round the hilltop: a battered talus,
##            rubble faces, a wall-walk behind a crenellated parapet with
##            arrow slits, following the ground.
##   gate     the Barbakan: a crenellated gatehouse with arched portals and
##            dressed-stone voussoirs, outside and into the first courtyard.
##   tower    flanking and courtyard towers, round or square as mapped, with
##            a cordon, slit windows, corbels under the parapet and merlons.
##   citadel  the Venetian complex round Don Zhon's tower: high broken walls.
##   church   St Stephen's church-mosque: roofless walls with tall arched
##            windows; "minaret" is the stump of its minaret.
##   museum   the Venetian arsenal, the one roofed building: dressed stone,
##            two rows of windows, an arched door and a hipped tile roof.
##   cistern  low vaulted cisterns.  ruin  broken walls of houses, barracks,
##            the palace, the hammam and the prison, roofless.
## The Albanian flag flies over the Venetian citadel tower.
## Local frame: metres from the landmark anchor, x east, z south.

const DATA := "res://assets/cities/shkoder/rozafa.json"
## The lap passes 1.3-2 km away: everything stays drawn that far.
const REACH := 4200.0
const STONE := Color("#e4ddcf")
const STONE_DARK := Color("#c8c0b0")
const ILLYRIAN := Color("#b9b1a2")
const VENETIAN := Color("#eee6d6")
const OTTOMAN := Color("#e2d4bb")
const DRESSED := Color("#fbf5e8")
const OPENING := Color("#1c1a17")
const TILE := Color("#b0603f")

const WALL_THICK := 2.6
const PARAPET := 0.6
const PARAPET_H := 1.0
const MERLON := Vector3(1.3, 0.95, PARAPET)
const MERLON_STEP := 2.3

var _terrain: Terrain
var _stone: SurfaceTool
var _roof: SurfaceTool
var flag_top := Vector3.ZERO
## Counts for tests: merlons and arrow slits on the curtain wall, parts built.
var merlons := 0
var slits := 0
var built := {}


func build(terrain: Terrain) -> bool:
	_terrain = terrain
	if not FileAccess.file_exists(DATA):
		return false
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	_stone = LandmarkKit.begin()
	_roof = LandmarkKit.begin()
	_curtain_wall(_points(data.wall))
	for part: Dictionary in data.parts:
		var ring := _points(part.ring)
		var kind := str(part.kind)
		var seed := int(part.id)
		match kind:
			"gate":
				_gate(ring)
			"tower":
				var big := _area(ring) > 70.0
				_tower(ring, 15.0 if big else 11.5, VENETIAN if seed == 319905502 else STONE, big)
				if seed == 319905502:
					var c := _centroid(ring)
					flag_top = Vector3(c.x, _ground_max(ring) + 11.5 + PARAPET_H, c.y)
			"citadel":
				_ruin(ring, 6.5, 10.5, 1.4, VENETIAN, seed)
			"church":
				_church(ring)
			"minaret":
				_minaret(ring)
			"museum":
				_museum(ring)
			"cistern":
				_cistern(ring)
			_:
				var col := ILLYRIAN if str(part.name).contains("Illyria") else OTTOMAN
				_ruin(ring, 1.4, 4.6, 0.8, col, seed)
		built[kind] = int(built.get(kind, 0)) + 1
	var stone_mat := LandmarkKit.material(0.93)
	# Grey rubble limestone: the cobble photograph reads as coursed rubble.
	stone_mat.albedo_texture = preload("res://assets/textures/cobble_diff.jpg")
	stone_mat.uv1_triplanar = true
	stone_mat.uv1_scale = Vector3.ONE * 0.32
	add_child(LandmarkKit.mesh_node(_stone, stone_mat, "CastleMasonry", REACH))
	var roof_mat := LandmarkKit.material(0.8)
	roof_mat.albedo_texture = preload("res://assets/textures/rooftiles_diff.jpg")
	roof_mat.uv1_triplanar = true
	roof_mat.uv1_scale = Vector3.ONE * 0.35
	add_child(LandmarkKit.mesh_node(_roof, roof_mat, "MuseumRoof", REACH))
	if flag_top != Vector3.ZERO:
		_flag(flag_top)
	return true


# ------------------------------------------------------------------ ground

## Local height of the ground under local point (x, z); 0 without terrain.
func _ground(p: Vector2) -> float:
	var parent := get_parent() as Node3D
	if _terrain == null or parent == null:
		return 0.0
	var world := parent.transform * Vector3(p.x, 0.0, p.y)
	return _terrain.height_at(world.x, world.z) - parent.position.y


func _ground_min(ring: PackedVector2Array) -> float:
	var low := INF
	for p in ring:
		low = minf(low, _ground(p))
	return low


func _ground_max(ring: PackedVector2Array) -> float:
	var high := -INF
	for p in ring:
		high = maxf(high, _ground(p))
	return high


# ------------------------------------------------------------------ polygons

func _points(rows: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for r: Array in rows:
		out.append(Vector2(float(r[0]), float(r[1])))
	return out


func _area(ring: PackedVector2Array) -> float:
	return absf(_signed_area(ring))


func _signed_area(ring: PackedVector2Array) -> float:
	var a := 0.0
	for i in ring.size():
		var p := ring[i]
		var q := ring[(i + 1) % ring.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


func _centroid(ring: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in ring:
		c += p
	return c / ring.size()


## Unit normal of edge a->b pointing out of a ring with this signed area.
func _outward(a: Vector2, b: Vector2, signed_area: float) -> Vector2:
	var e := (b - a).normalized()
	var left := Vector2(-e.y, e.x)
	return -left if signed_area > 0.0 else left


## The ring with no edge longer than `step`.
func _densify(ring: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var n := maxi(1, ceili(a.distance_to(b) / step))
		for k in n:
			out.append(a.lerp(b, float(k) / n))
	return out


func _v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


## Basis turning a box's x axis along `edge` (x, z).
func _along(edge: Vector2) -> Basis:
	return Basis(Vector3.UP, atan2(-edge.y, edge.x))


## Smooth variation in [-1, 1] along a wall, from its arc length.
func _wave(s: float, seed: float) -> float:
	return 0.6 * sin(s / 37.0 + seed) + 0.4 * sin(s / 11.3 + seed * 2.7)


func _hash(i: int, salt: int) -> float:
	return float(absi(hash(i * 7919 + salt * 104729)) % 10000) / 10000.0


# ------------------------------------------------------------------ curtain wall

func _curtain_wall(outline: PackedVector2Array) -> void:
	var ring := _densify(outline, 4.0)
	var n := ring.size()
	var signed := _signed_area(ring)
	# Per-vertex inward offset, mitred so the walk keeps its width at corners.
	var inward: Array[Vector2] = []
	for i in n:
		var a := ring[(i - 1 + n) % n]
		var p := ring[i]
		var b := ring[(i + 1) % n]
		var n0 := -_outward(a, p, signed)
		var n1 := -_outward(p, b, signed)
		var m := n0 + n1
		m = n1 if m.length() < 0.1 else m.normalized()
		inward.append(m / maxf(0.55, m.dot(n1)))
	# Ground at the outer and inner faces, and the wall-walk level.
	var g_out: Array[float] = []
	var g_in: Array[float] = []
	var walk: Array[float] = []
	var s := 0.0
	for i in n:
		g_out.append(_ground(ring[i]))
		g_in.append(_ground(ring[i] + inward[i] * WALL_THICK))
		walk.append(maxf(g_out[i], g_in[i]) + 8.6 + 1.6 * _wave(s, 0.4))
		s += ring[i].distance_to(ring[(i + 1) % n])
	var along := 0.0
	var next_merlon := 0.0
	for i in n:
		var j := (i + 1) % n
		var p := ring[i]
		var q := ring[j]
		var out_p := -inward[i]
		var out_q := -inward[j]
		var toward := _v3(-(inward[i] + inward[j]) * 0.5, 0.0)
		var col := STONE if _hash(i, 1) > 0.3 else STONE_DARK
		# Battered talus: from below the slope out at its foot to 2.5 m up.
		var tp := g_out[i] + 2.5
		var tq := g_out[j] + 2.5
		LandmarkKit.quad_facing(_stone, _v3(p + out_p * 1.5, g_out[i] - 5.0), _v3(q + out_q * 1.5, g_out[j] - 5.0),
			_v3(q, tq), _v3(p, tp), STONE_DARK, toward + Vector3.UP * 0.4)
		# Outer face up to the parapet top.
		var top_p := walk[i] + PARAPET_H
		var top_q := walk[j] + PARAPET_H
		LandmarkKit.quad_facing(_stone, _v3(p, tp), _v3(q, tq), _v3(q, top_q), _v3(p, top_p), col, toward)
		# Parapet: its top and the face toward the walk.
		var pp := p + inward[i] * PARAPET
		var pq := q + inward[j] * PARAPET
		LandmarkKit.quad_facing(_stone, _v3(p, top_p), _v3(q, top_q), _v3(pq, top_q), _v3(pp, top_p), col, Vector3.UP)
		LandmarkKit.quad_facing(_stone, _v3(pp, walk[i]), _v3(pq, walk[j]), _v3(pq, top_q), _v3(pp, top_p), col, -toward)
		# Wall-walk and the inner face down to the courtyard.
		var ip := p + inward[i] * WALL_THICK
		var iq := q + inward[j] * WALL_THICK
		LandmarkKit.quad_facing(_stone, _v3(pp, walk[i]), _v3(pq, walk[j]), _v3(iq, walk[j]), _v3(ip, walk[i]), STONE_DARK, Vector3.UP)
		LandmarkKit.quad_facing(_stone, _v3(ip, g_in[i] - 1.0), _v3(iq, g_in[j] - 1.0), _v3(iq, walk[j]), _v3(ip, walk[i]), col, -toward)
		# Merlons on the parapet, an arrow slit under every third one.
		var edge := q - p
		var length := edge.length()
		if length < 0.01:
			continue
		while next_merlon < along + length:
			var t := (next_merlon - along) / length
			var at := p.lerp(q, t)
			var normal_out := (out_p.lerp(out_q, t)).normalized()
			var y := lerpf(top_p, top_q, t)
			LandmarkKit.box(_stone, _v3(at - normal_out * PARAPET * 0.5, y + MERLON.y * 0.5),
				MERLON, col, _along(edge))
			if merlons % 3 == 1:
				var w := edge.normalized() * 0.13
				var base := _v3(at + normal_out * 0.04, y - 2.6)
				LandmarkKit.quad_facing(_stone, base - _v3(w, 0.0), base + _v3(w, 0.0), base + _v3(w, 0.0) + Vector3.UP * 1.5,
					base - _v3(w, 0.0) + Vector3.UP * 1.5, OPENING, _v3(normal_out, 0.0))
				slits += 1
			merlons += 1
			next_merlon += MERLON_STEP
		along += length


# ------------------------------------------------------------------ towers and gate

## A prism over `ring` from `bottom` to `top`, sides only, facing out.
func _prism(st: SurfaceTool, ring: PackedVector2Array, bottom: float, top: float, col: Color, grow := 0.0, inward := false) -> void:
	var signed := _signed_area(ring)
	var n := ring.size()
	for i in n:
		var a := ring[i]
		var b := ring[(i + 1) % n]
		if a.distance_to(b) < 0.05:
			continue
		var out := _outward(a, b, signed)
		a += out * grow
		b += out * grow
		LandmarkKit.quad_facing(st, _v3(a, bottom), _v3(b, bottom), _v3(b, top), _v3(a, top), col, _v3(-out if inward else out, 0.0))


## A flat cap over `ring` at height y, facing up (or down).
func _cap(st: SurfaceTool, ring: PackedVector2Array, y: float, col: Color, up := true) -> void:
	var tris := Geometry2D.triangulate_polygon(ring)
	st.set_color(col)
	for k in range(0, tris.size(), 3):
		var a := _v3(ring[tris[k]], y)
		var b := _v3(ring[tris[k + 1]], y)
		var c := _v3(ring[tris[k + 2]], y)
		var normal := (b - a).cross(c - a)
		var face_up := normal.y > 0.0
		var order := [c, b, a] if face_up == up else [a, b, c]
		st.set_normal(Vector3.UP if up else Vector3.DOWN)
		for v: Vector3 in order:
			st.set_uv(Vector2(v.x, v.z))
			st.add_vertex(v)


## Shrink a ring toward its centroid by `d` metres (for parapet insides).
func _inset(ring: PackedVector2Array, d: float) -> PackedVector2Array:
	var shrunk := Geometry2D.offset_polygon(ring, -d)
	return shrunk[0] if not shrunk.is_empty() else ring


func _tower(ring: PackedVector2Array, height: float, col: Color, big: bool) -> void:
	var low := _ground_min(ring) - 3.0
	var top := _ground_max(ring) + height
	_prism(_stone, ring, low, top + PARAPET_H, col)
	# Cordon a third of the way up, and corbels under a big tower's parapet.
	_prism(_stone, ring, top - height * 0.62, top - height * 0.62 + 0.35, DRESSED, 0.18)
	var inner := _inset(ring, PARAPET)
	_cap(_stone, inner, top, STONE_DARK)
	_prism(_stone, inner, top, top + PARAPET_H, col, 0.0, true)   # the parapet seen from the platform
	_parapet_top(ring, inner, top + PARAPET_H, col)
	var signed := _signed_area(ring)
	var dense := _densify(ring, 1.4)
	for i in dense.size():
		var a := dense[i]
		var b := dense[(i + 1) % dense.size()]
		if a.distance_to(b) < 0.3:
			continue
		var out := _outward(a, b, signed)
		var mid := (a + b) * 0.5
		if big:
			LandmarkKit.box(_stone, _v3(mid + out * 0.2, top - 0.45), Vector3(0.35, 0.7, 0.45), DRESSED, _along(b - a))
		if i % 2 == 0:
			LandmarkKit.box(_stone, _v3(mid - out * (PARAPET * 0.5), top + PARAPET_H + MERLON.y * 0.5),
				Vector3(minf(1.0, a.distance_to(b) * 0.9), MERLON.y, PARAPET), col, _along(b - a))
	# Slit windows on the longer faces (round towers: every few facets).
	var n := ring.size()
	for i in n:
		var a := ring[i]
		var b := ring[(i + 1) % n]
		if a.distance_to(b) < 2.5 and (n < 12 or i % 4 != 0):
			continue
		var out := _outward(a, b, signed)
		var mid := (a + b) * 0.5 + out * 0.05
		var w := (b - a).normalized() * 0.16
		for frac: float in [0.45, 0.78]:
			var y: float = top - height * (1.0 - frac)
			LandmarkKit.quad_facing(_stone, _v3(mid - w, y), _v3(mid + w, y), _v3(mid + w, y + 1.4), _v3(mid - w, y + 1.4), OPENING, _v3(out, 0.0))


## The strip between a ring and its inset, facing up.
func _parapet_top(outer: PackedVector2Array, inner: PackedVector2Array, y: float, col: Color) -> void:
	if outer.size() != inner.size():
		# Offsetting can change the vertex count: cap the whole outline instead.
		_cap(_stone, outer, y, col)
		return
	for i in outer.size():
		var j := (i + 1) % outer.size()
		LandmarkKit.quad_facing(_stone, _v3(outer[i], y), _v3(outer[j], y), _v3(inner[j], y), _v3(inner[i], y), col, Vector3.UP)


func _gate(ring: PackedVector2Array) -> void:
	_tower(ring, 12.5, STONE, true)
	# Portals on the face looking out of the castle and the one looking in.
	var signed := _signed_area(ring)
	var c := _centroid(ring)
	var best_out := -1
	var best_in := -1
	var score_out := -INF
	var score_in := -INF
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		if a.distance_to(b) < 5.0:
			continue
		var facing := _outward(a, b, signed).dot(c.normalized())
		if facing > score_out:
			score_out = facing
			best_out = i
		if -facing > score_in:
			score_in = -facing
			best_in = i
	for i in [best_out, best_in]:
		if i < 0:
			continue
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var out := _outward(a, b, signed)
		var mid := (a + b) * 0.5
		_arch(_stone, mid + out * 0.06, (b - a).normalized(), out, _ground(mid) - 0.2, 4.4, 4.6, OPENING, true)


## An arched opening on a wall face: a rectangle of height `rise` under a
## semicircle, `width` wide, its foot at y; with dressed voussoirs round it.
func _arch(st: SurfaceTool, at: Vector2, along: Vector2, out: Vector2, y: float, width: float, rise: float, col: Color, voussoirs: bool) -> void:
	var r := width * 0.5
	var u := _v3(along, 0.0)
	var o := _v3(at, 0.0)
	var face := _v3(out, 0.0)
	LandmarkKit.quad_facing(st, o - u * r + Vector3.UP * y, o + u * r + Vector3.UP * y,
		o + u * r + Vector3.UP * (y + rise), o - u * r + Vector3.UP * (y + rise), col, face)
	var centre := o + Vector3.UP * (y + rise)
	var steps := 10
	st.set_color(col)
	for k in steps:
		var a0 := PI * k / steps
		var a1 := PI * (k + 1) / steps
		var p0 := centre + u * cos(a0) * r + Vector3.UP * sin(a0) * r
		var p1 := centre + u * cos(a1) * r + Vector3.UP * sin(a1) * r
		var tri := [centre, p0, p1]
		if (p0 - centre).cross(p1 - centre).dot(face) < 0.0:
			tri = [centre, p1, p0]
		st.set_normal(face)
		for v: Vector3 in tri:
			st.add_vertex(v)
	if not voussoirs:
		return
	for k in steps + 1:
		var a := PI * k / steps
		var p := centre + (u * cos(a) + Vector3.UP * sin(a)) * (r + 0.35)
		var radial := u * cos(a) + Vector3.UP * sin(a)
		LandmarkKit.box(st, p + face * 0.12, Vector3(0.75, 0.42, 0.3), DRESSED,
			Basis(radial, face.cross(radial), face))
	for side in [-1.0, 1.0]:
		LandmarkKit.box(st, o + u * side * (r + 0.35) + Vector3.UP * (y + rise * 0.5) + face * 0.12,
			Vector3(0.6, rise, 0.3), DRESSED, _along(along))


# ------------------------------------------------------------------ ruins and buildings

## Broken walls along a footprint: short pieces of varying height, `thick`
## wide inside the outline, one doorway gap on the longest side.
func _ruin(ring: PackedVector2Array, h_min: float, h_max: float, thick: float, col: Color, seed: int) -> void:
	var signed := _signed_area(ring)
	var n := ring.size()
	var longest := 0
	for i in n:
		if ring[i].distance_to(ring[(i + 1) % n]) > ring[longest].distance_to(ring[(longest + 1) % n]):
			longest = i
	var piece_index := 0
	for i in n:
		var a := ring[i]
		var b := ring[(i + 1) % n]
		var length := a.distance_to(b)
		if length < 0.3:
			continue
		var inward := -_outward(a, b, signed)
		var pieces := maxi(1, ceili(length / 1.7))
		for k in pieces:
			piece_index += 1
			if i == longest and length > 5.0 and k == pieces / 2:
				continue
			var p0 := a.lerp(b, float(k) / pieces)
			var p1 := a.lerp(b, float(k + 1) / pieces)
			var mid := (p0 + p1) * 0.5 + inward * thick * 0.5
			var g := minf(_ground(p0), _ground(p1))
			var h := lerpf(h_min, h_max, 0.5 + 0.5 * _wave(piece_index * 1.7, float(seed % 97)))
			h *= 0.8 + 0.3 * _hash(seed, piece_index)
			LandmarkKit.box(_stone, _v3(mid, g - 0.6 + (h + 0.6) * 0.5), Vector3(p0.distance_to(p1) + thick * 0.5, h + 0.6, thick),
				col.darkened(0.08 * _hash(seed + 1, piece_index)), _along(b - a))


func _church(ring: PackedVector2Array) -> void:
	# St Stephen's: roofless walls 8-9 m high, tall arched windows.
	_ruin(ring, 7.6, 9.2, 1.1, VENETIAN, 319867327)
	var signed := _signed_area(ring)
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var length := a.distance_to(b)
		if length < 6.0:
			continue
		var out := _outward(a, b, signed)
		var count := int(length / 4.6)
		for k in count:
			var at := a.lerp(b, (k + 0.5) / count) + out * 0.05
			_arch(_stone, at, (b - a).normalized(), out, _ground(at) + 3.0, 1.3, 2.4, OPENING, false)


func _minaret(ring: PackedVector2Array) -> void:
	var c := _centroid(ring)
	var g := _ground(c)
	var r := sqrt(_area(ring) / PI)
	LandmarkKit.box(_stone, _v3(c, g + 0.9), Vector3(r * 2.1, 2.4, r * 2.1), VENETIAN)
	LandmarkKit.tube(_stone, _v3(c, g + 2.0), _v3(c, g + 10.5), r * 0.92, r * 0.86, DRESSED, 12)


func _museum(ring: PackedVector2Array) -> void:
	# The Venetian arsenal: two storeys of dressed stone under a tiled roof.
	var low := _ground_min(ring) - 1.5
	var floor_y := _ground_max(ring)
	var eaves := floor_y + 7.6
	_prism(_stone, ring, low, eaves, VENETIAN)
	_prism(_stone, ring, eaves - 0.35, eaves, DRESSED, 0.15)
	var signed := _signed_area(ring)
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var length := a.distance_to(b)
		var out := _outward(a, b, signed)
		var e := (b - a).normalized()
		var count := int(length / 3.2)
		for k in count:
			var at := a.lerp(b, (k + 0.5) / count) + out * 0.05
			for y: float in [floor_y + 1.4, floor_y + 4.7]:
				var w := e * 0.45
				LandmarkKit.box(_stone, _v3(at, y + 0.7), Vector3(1.2, 1.7, 0.12), DRESSED, _along(e))
				LandmarkKit.quad_facing(_stone, _v3(at + w + out * 0.04, y), _v3(at - w + out * 0.04, y),
					_v3(at - w + out * 0.04, y + 1.4), _v3(at + w + out * 0.04, y + 1.4), OPENING, _v3(out, 0.0))
		if i == 0:
			var mid := (a + b) * 0.5 + out * 0.08
			_arch(_stone, mid, e, out, _ground(mid), 2.2, 2.0, Color("#3a2a1e"), true)
	_hip(_roof, Geometry2D.offset_polygon(ring, 0.45)[0], eaves, 3.4, TILE)


func _cistern(ring: PackedVector2Array) -> void:
	var low := _ground_min(ring) - 1.0
	var top := _ground_max(ring) + 0.9
	_prism(_stone, ring, low, top, STONE_DARK)
	_hip(_stone, ring, top, minf(1.6, sqrt(_area(ring)) * 0.18), STONE)


## A hipped roof over a footprint: a ridge along its longest edge's
## direction, every eave rising to the nearest point of the ridge.
func _hip(st: SurfaceTool, ring: PackedVector2Array, y: float, rise: float, col: Color) -> void:
	var longest := 0
	for i in ring.size():
		if ring[i].distance_to(ring[(i + 1) % ring.size()]) > ring[longest].distance_to(ring[(longest + 1) % ring.size()]):
			longest = i
	var u := (ring[(longest + 1) % ring.size()] - ring[longest]).normalized()
	var v := Vector2(-u.y, u.x)
	var c := _centroid(ring)
	var a_min := INF
	var a_max := -INF
	var b_min := INF
	var b_max := -INF
	for p in ring:
		a_min = minf(a_min, (p - c).dot(u))
		a_max = maxf(a_max, (p - c).dot(u))
		b_min = minf(b_min, (p - c).dot(v))
		b_max = maxf(b_max, (p - c).dot(v))
	var half_w := (b_max - b_min) * 0.5
	var mid_b := (b_max + b_min) * 0.5
	var r0 := minf(a_min + half_w, (a_min + a_max) * 0.5)
	var r1 := maxf(a_max - half_w, (a_min + a_max) * 0.5)
	var ridge := func(p: Vector2) -> Vector3:
		var t := clampf((p - c).dot(u), r0, r1)
		return _v3(c + u * t + v * mid_b, y + rise)
	var signed := _signed_area(ring)
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		if a.distance_to(b) < 0.05:
			continue
		var toward := _v3(_outward(a, b, signed), 0.0) + Vector3.UP
		var ra: Vector3 = ridge.call(a)
		var rb: Vector3 = ridge.call(b)
		LandmarkKit.quad_facing(st, _v3(a, y), _v3(b, y), rb, ra, col, toward)


# ------------------------------------------------------------------ flag

func _flag(at: Vector3) -> void:
	var st := LandmarkKit.begin()
	LandmarkKit.tube(st, at, at + Vector3.UP * 9.0, 0.14, 0.08, Color(0.72, 0.73, 0.74), 8)
	add_child(LandmarkKit.mesh_node(st, LandmarkKit.material(0.4, 0.6), "FlagMast", REACH))
	var cloth := QuadMesh.new()
	cloth.size = Vector2(5.0, 3.5)
	cloth.subdivide_width = 12
	cloth.subdivide_depth = 4
	var flag := MeshInstance3D.new()
	flag.name = "CastleFlag"
	flag.mesh = cloth
	flag.position = at + Vector3(2.6, 7.1, 0)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/flag_wave.gdshader")
	mat.set_shader_parameter("use_tex", true)
	mat.set_shader_parameter("flag_tex", LandmarkKit.albanian_flag())
	mat.set_shader_parameter("wave", 3.0)
	flag.material_override = mat
	flag.visibility_range_end = REACH
	add_child(flag)
