class_name BeratCastle
extends RozafaCastle
## Berat castle (Kalaja e Beratit) on its hill over Mangalem and the Osum,
## from castle.json (tools/pipeline/berat_castle.py; data (c) OpenStreetMap
## contributors). Built with Rozafa's wall and tower kit:
##   wall      the 1.6 km curtain wall round the hilltop: battered talus,
##             grey limestone faces, a crenellated parapet with arrow slits,
##             following the ground
##   lines     the inner citadel and cross walls, and the wall that runs
##             down toward Mangalem, crenellated, open-ended
##   towers    flanking towers projecting from the curtain, square or round
##   gate      the main gate, its arched portals
##   churches  the Byzantine churches of the Kala quarter in stone banded
##             with brick, under tiled roofs, the domed ones with a drum and
##             dome; St Michael's on the cliff; the Red and White mosques'
##             roofless ruins and the Red Mosque's minaret stump
## The flag flies over the southern spur above Mangalem. The quarter's
## houses are built by OldQuarter.

const BERAT_DATA := "res://assets/cities/berat/castle.json"
const BRICK := Color("#b4674c")
const LIMESTONE := Color("#d9d2c4")
const LIMESTONE_DARK := Color("#bdb4a3")

var churches := 0
var domes := 0
var towers := 0
var wall_lines := 0


func build(terrain: Terrain) -> bool:
	_terrain = terrain
	if not FileAccess.file_exists(BERAT_DATA):
		return false
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BERAT_DATA))
	_stone = LandmarkKit.begin()
	_roof = LandmarkKit.begin()
	_curtain_wall(_points(data.wall))
	built["wall"] = 1
	for line: Array in data.lines:
		var pts := _points(line)
		if pts.size() >= 2:
			_wall_line(pts)
			wall_lines += 1
	for t: Dictionary in data.towers:
		var at := Vector2(float(t.at[0]), float(t.at[1]))
		var out := Vector2(float(t.out[0]), float(t.out[1])).normalized()
		var size := float(t.size)
		var ring := _tower_ring(at + out * size * 0.28, out, size, bool(t.get("round", false)))
		_tower(ring, 12.5 if size > 6.5 else 10.5, STONE if towers % 2 == 0 else STONE_DARK, size > 6.5)
		towers += 1
	built["tower"] = towers
	if data.get("gate") is Dictionary:
		_gate(_points(data.gate.ring))
		built["gate"] = 1
	for c: Dictionary in data.churches:
		_berat_church(c)
	var stone_mat := LandmarkKit.material(0.93)
	stone_mat.albedo_texture = preload("res://assets/textures/castle_wall_diff.jpg")
	stone_mat.albedo_color = Color(0.98, 0.95, 0.9)
	stone_mat.normal_enabled = true
	stone_mat.normal_texture = preload("res://assets/textures/castle_wall_nor.jpg")
	stone_mat.roughness_texture = preload("res://assets/textures/castle_wall_arm.jpg")
	stone_mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	stone_mat.roughness = 1.0
	stone_mat.uv1_triplanar = true
	stone_mat.uv1_scale = Vector3.ONE * 0.32
	add_child(LandmarkKit.mesh_node(_stone, stone_mat, "CastleMasonry", REACH))
	var roof_mat := LandmarkKit.material(0.85)
	roof_mat.albedo_texture = preload("res://assets/textures/old_roof_diff.jpg")
	roof_mat.normal_enabled = true
	roof_mat.normal_texture = preload("res://assets/textures/old_roof_nor.jpg")
	roof_mat.uv1_triplanar = true
	roof_mat.uv1_scale = Vector3.ONE * 0.38
	add_child(LandmarkKit.mesh_node(_roof, roof_mat, "ChurchRoofs", REACH))
	var f := Vector2(float(data.flag[0]), float(data.flag[1]))
	flag_top = Vector3(f.x, _ground(f) + 9.6, f.y)
	_flag(flag_top)
	return true


## A tower's footprint: a square turned to the wall, or a 12-sided round one.
func _tower_ring(c: Vector2, out: Vector2, size: float, round_tower: bool) -> PackedVector2Array:
	var ring := PackedVector2Array()
	if round_tower:
		for k in 12:
			var a := -TAU * k / 12.0
			ring.append(c + Vector2(cos(a), sin(a)) * size * 0.5)
		return ring
	var side := Vector2(-out.y, out.x)
	var h := size * 0.5
	for p in [c - side * h - out * h, c - side * h + out * h, c + side * h + out * h, c + side * h - out * h]:
		ring.append(p)
	if _signed_area(ring) < 0.0:
		ring.reverse()
	return ring


## An open run of wall following the ground: both faces, the wall-walk and
## merlons along one edge.
func _wall_line(line: PackedVector2Array) -> void:
	var pts := _densify_open(line, 4.0)
	var thick := 2.0
	var s := 0.0
	var next_merlon := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var e := (b - a)
		var length := e.length()
		if length < 0.05:
			continue
		var n := Vector2(-e.y, e.x) / length * thick * 0.5
		var ga := _ground(a)
		var gb := _ground(b)
		var ta := ga + 6.8 + 1.0 * _wave(s, 1.3)
		var tb := gb + 6.8 + 1.0 * _wave(s + length, 1.3)
		var col := STONE if _hash(i, 3) > 0.35 else STONE_DARK
		for sgn: float in [-1.0, 1.0]:
			var o: Vector2 = n * sgn
			LandmarkKit.quad_facing(_stone, _v3(a + o, ga - 2.5), _v3(b + o, gb - 2.5), _v3(b + o, tb), _v3(a + o, ta), col, _v3(o, 0.0))
		LandmarkKit.quad_facing(_stone, _v3(a - n, ta), _v3(b - n, tb), _v3(b + n, tb), _v3(a + n, ta), STONE_DARK, Vector3.UP)
		while next_merlon < s + length:
			var t := (next_merlon - s) / length
			var at := a.lerp(b, t) + n * 0.7
			LandmarkKit.box(_stone, _v3(at, lerpf(ta, tb, t) + MERLON.y * 0.5), MERLON, col, _along(e))
			next_merlon += MERLON_STEP
		s += length


func _densify_open(line: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var k := maxi(1, ceili(a.distance_to(b) / step))
		for j in k:
			out.append(a.lerp(b, float(j) / k))
	out.append(line[line.size() - 1])
	return out


## A Byzantine church of the castle: stone walls banded with brick, a tiled
## hipped roof; a drum and dome over the domed ones. Mosques: ruins.
func _berat_church(c: Dictionary) -> void:
	var ring := _points(c.ring)
	if ring.size() < 3:
		return
	if _signed_area(ring) < 0.0:
		ring.reverse()
	var kind := str(c.kind)
	var seed := int(c.id)
	if kind == "mosque_ruin":
		_ruin(ring, 2.2, 5.6, 0.9, ILLYRIAN, seed)
		if str(c.name).contains("Kuqe"):
			var cc := _centroid(ring)
			var corner := ring[0].lerp(cc, 0.15)
			var g := _ground(corner)
			LandmarkKit.tube(_stone, _v3(corner, g - 0.5), _v3(corner, g + 7.5), 1.25, 1.1, BRICK.darkened(0.15), 10)
		built["ruin"] = int(built.get("ruin", 0)) + 1
		return
	var low := _ground_min(ring) - 1.2
	var floor_y := _ground_max(ring)
	var eaves := floor_y + 6.2
	_prism(_stone, ring, low, eaves, LIMESTONE)
	# Courses of brick laid between the stone, as on Berat's churches.
	for y in [floor_y + 1.4, floor_y + 3.0, floor_y + 4.6, eaves - 0.3]:
		_prism(_stone, ring, y, y + 0.16, BRICK, 0.02)
	# Small arched windows on the long sides, and the west door.
	var signed := _signed_area(ring)
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var length := a.distance_to(b)
		if length < 4.0:
			continue
		var out := _outward(a, b, signed)
		var count := int(length / 3.2)
		for k in count:
			var at := a.lerp(b, (k + 0.5) / count) + out * 0.05
			_arch(_stone, at, (b - a).normalized(), out, floor_y + 2.6, 0.75, 1.2, OPENING, false)
	var roof_ring := Geometry2D.offset_polygon(ring, 0.35)
	_hip(_roof, roof_ring[0] if not roof_ring.is_empty() else ring, eaves, 1.9, TILE)
	if kind == "domed":
		var cc := _centroid(ring)
		var r := clampf(sqrt(_area(ring)) * 0.17, 1.6, 2.8)
		var base := eaves + 1.2
		LandmarkKit.tube(_stone, _v3(cc, eaves), _v3(cc, base + 2.4), r, r, LIMESTONE, 8)
		LandmarkKit.tube(_stone, _v3(cc, base + 1.0), _v3(cc, base + 1.15), r + 0.05, r + 0.05, BRICK, 8)
		for k in 8:
			var a := TAU * k / 8.0
			var d := Vector2(cos(a), sin(a))
			_arch(_stone, cc + d * (r + 0.03), Vector2(-d.y, d.x), d, base + 0.6, 0.5, 0.9, OPENING, false)
		LandmarkKit.sphere(_roof, _v3(cc, base + 2.4), Vector3(r + 0.25, r * 0.85, r + 0.25), TILE, 6, 12)
		LandmarkKit.tube(_stone, _v3(cc, base + 2.4 + r * 0.85), _v3(cc, base + 3.4 + r * 0.85), 0.05, 0.05, Color("#d8c27a"), 4)
		domes += 1
	churches += 1
	built["church"] = int(built.get("church", 0)) + 1
