class_name OldQuarter
extends Node3D
## The houses of a city's traditional quarters, from houses.json
## (tools/pipeline/old_quarters.py): Berat's Mangalem, Gorica and the
## inhabited castle, the "city of a thousand windows".
##
## Every mapped house on its own footprint, stacked up the slope as mapped:
##   a ground floor of rubble limestone (CC0 Stone Wall) reaching down to
##   the lowest ground, so downhill sides show a tall stone base; small
##   shuttered windows in it;
##   one or two whitewashed upper floors (CC0 White Stucco), the front one
##   often jutting out over a dark timber beam on brackets;
##   close rows of tall windows on the side that looks down the valley,
##   fewer on the others: quads from the Berat window atlas (dark timber
##   frames from CC0 Dark Wooden Planks, glass that takes the sky, curtains,
##   closed boards; lit from inside at night);
##   a low hipped roof of weathered tiles (CC0 Roof 09) on deep eaves with
##   dark timber fascias and soffits, ridge tiles, whitewashed chimneys.
## Houses are merged per 300 m block: five draw calls a block.

const CHUNK := 300.0
const STONE_FLOOR := 2.7       # ground floor above the highest ground
const FLOOR := 2.95
const EAVE := 0.8
const PITCH := 0.46
const JUT := 0.55
const REACH := 3600.0
const WIN := Vector2(0.84, 1.66)
const WIN_SHADER := preload("res://shaders/old_window.gdshader")

const PLASTER := [Color("#fbfaf6"), Color("#f6f3ec"), Color("#f2efe6"), Color("#fbf8f2"), Color("#efeae0")]
const STONE := [Color("#ffffff"), Color("#f2efe8"), Color("#e6e2da")]
const TIMBER := Color("#ffffff")

var houses := 0
var windows := 0
var blocks := 0
var _terrain: Terrain
var _mats := {}


static func path_for(city_id: String) -> String:
	return "res://assets/cities/%s/houses.json" % city_id


func build(city_id: String, terrain: Terrain) -> bool:
	if not FileAccess.file_exists(path_for(city_id)):
		return false
	name = "OldQuarters"
	_terrain = terrain
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path_for(city_id)))
	_materials()
	var groups := {}
	for h: Dictionary in data.houses:
		var c := Vector2.ZERO
		for p: Array in h.ring:
			c += Vector2(float(p[0]), float(p[1]))
		c /= h.ring.size()
		var key := Vector2i(floori(c.x / CHUNK), floori(c.y / CHUNK))
		if not groups.has(key):
			groups[key] = []
		groups[key].append(h)
	for key: Vector2i in groups:
		var tools := {"stone": ArchKit.begin(), "plaster": ArchKit.begin(), "roof": ArchKit.begin(),
			"timber": ArchKit.begin(), "windows": ArchKit.begin()}
		for h: Dictionary in groups[key]:
			_house(tools, h)
			houses += 1
		for part: String in tools:
			var st: SurfaceTool = tools[part]
			st.index()
			var mi := ArchKit.node(st, _mats[part], "Block%d_%d_%s" % [key.x, key.y, part], REACH)
			if part == "windows":
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
		blocks += 1
	return true


func set_night(night: float) -> void:
	if _mats.has("windows"):
		(_mats.windows as ShaderMaterial).set_shader_parameter("night", night)


func _materials() -> void:
	_mats.stone = ArchKit.material(preload("res://assets/textures/rubble_wall_diff.jpg"),
		preload("res://assets/textures/rubble_wall_nor.jpg"), preload("res://assets/textures/rubble_wall_arm.jpg"), 2.4,
		Color(1.08, 1.06, 1.02))
	_mats.plaster = ArchKit.material(preload("res://assets/textures/stucco_diff.jpg"),
		preload("res://assets/textures/stucco_nor.jpg"), preload("res://assets/textures/stucco_arm.jpg"), 2.2,
		Color(1.06, 1.06, 1.05), 0.7)
	_mats.roof = ArchKit.material(preload("res://assets/textures/old_roof_diff.jpg"),
		preload("res://assets/textures/old_roof_nor.jpg"), preload("res://assets/textures/old_roof_arm.jpg"), 2.6,
		Color(0.92, 0.86, 0.82))
	_mats.timber = ArchKit.material(preload("res://assets/textures/dark_timber_diff.jpg"),
		preload("res://assets/textures/dark_timber_nor.jpg"), preload("res://assets/textures/dark_timber_arm.jpg"), 2.0,
		Color(0.85, 0.8, 0.76))
	var win := ShaderMaterial.new()
	win.shader = WIN_SHADER
	win.set_shader_parameter("atlas", preload("res://assets/textures/berat_windows.png"))
	_mats.windows = win


func _ground(p: Vector2) -> float:
	return _terrain.height_at(p.x, p.y) if _terrain != null else 0.0


func _v(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


func _hash(seed: int, salt: int) -> float:
	return float(absi(hash(seed * 7919 + salt * 104729)) % 10000) / 10000.0


func _house(t: Dictionary, h: Dictionary) -> void:
	var ring := PackedVector2Array()
	for p: Array in h.ring:
		ring.append(Vector2(float(p[0]), float(p[1])))
	var n := ring.size()
	var seed := int(h.seed)
	var lo := float(h.lo)
	var hi := float(h.hi)
	var floors := int(h.floors)
	var front := int(h.front)
	# The stone base reaches the ground, but a road cut below a house does
	# not make it a tower: at most 6 m under the floor.
	var base := maxf(lo, hi - 6.0) - 1.5
	var y1 := hi + STONE_FLOOR
	var eave := y1 + floors * FLOOR
	var plaster_col: Color = PLASTER[seed % PLASTER.size()]
	var stone_col: Color = STONE[seed % STONE.size()]
	# The front (valley side) of the upper floors juts out on most houses.
	var jut := JUT if seed % 3 != 0 else 0.0
	var upper := ring.duplicate()
	var fa := ring[front]
	var fb := ring[(front + 1) % n]
	var fout := _outward(fa, fb)
	if jut > 0.0:
		upper[front] = fa + fout * jut
		upper[(front + 1) % n] = fb + fout * jut
	var down := fout
	# Stone ground floor with small shuttered windows; whitewashed floors above.
	for i in n:
		var a := ring[i]
		var b := ring[(i + 1) % n]
		var out := _outward(a, b)
		var o3 := Vector3(out.x, 0, out.y)
		ArchKit.wall_quad(t.stone, _v(a, base), _v(b, base), _v(b, y1), _v(a, y1), stone_col, o3)
		var length := a.distance_to(b)
		var faces_valley := out.dot(down) > -0.3
		if length > 3.2 and faces_valley:
			var count := int((length - 1.0) / 3.2)
			for k in count:
				var p := a.lerp(b, (k + 0.5 + 0.3 * (_hash(seed, i * 13 + k) - 0.5)) / count)
				var sill := maxf(_ground(p) + 0.8, y1 - 1.9)
				if sill + 1.1 < y1 - 0.25:
					_window(t, p, out, sill, Vector2(0.7, 1.05), 3 if _hash(seed, k + i) > 0.4 else 0, seed + k)
	for i in n:
		var a := upper[i]
		var b := upper[(i + 1) % n]
		var out := _outward(ring[i], ring[(i + 1) % n])
		var o3 := Vector3(out.x, 0, out.y)
		ArchKit.wall_quad(t.plaster, _v(a, y1), _v(b, y1), _v(b, eave), _v(a, eave), plaster_col, o3)
		var length := a.distance_to(b)
		var on_front := i == front
		var faces_valley := out.dot(down) > -0.3
		if length < 1.5 or not faces_valley:
			continue
		var spacing := 1.24 if on_front else 2.3
		var count := maxi(1 if on_front or length > 3.0 else 0, int((length - 0.5) / spacing))
		for f in floors:
			var sill := y1 + f * FLOOR + 0.72
			for k in count:
				var p := a.lerp(b, (k + 0.5) / count)
				var variant := 0
				var r := _hash(seed, f * 31 + k + i * 7)
				if r > 0.86:
					variant = 3
				elif r > 0.7:
					variant = 2
				elif r > 0.55:
					variant = 1
				_window(t, p, out, sill, WIN, variant, seed * 3 + f * 17 + k)
	# The jutting floor: plaster underside, a dark beam and brackets.
	if jut > 0.0:
		ArchKit.quad_uv(t.plaster, _v(fa, y1), _v(fb, y1), _v(upper[(front + 1) % n], y1), _v(upper[front], y1),
			Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), plaster_col.darkened(0.18), Vector3.DOWN)
		var along := (fb - fa).normalized()
		var basis := Basis(Vector3(along.x, 0, along.y), Vector3.UP, Vector3(fout.x, 0, fout.y))
		var mid := (fa + fb) * 0.5 + fout * jut
		ArchKit.box(t.timber, _v(mid, y1 + 0.09), Vector3(fa.distance_to(fb) + 0.1, 0.2, 0.14), TIMBER, basis)
		var nb := int(fa.distance_to(fb) / 1.6)
		for k in nb:
			var p := fa.lerp(fb, (k + 0.5) / nb) + fout * jut * 0.5
			var tilt := Basis(Vector3(along.x, 0, along.y), -0.7) * basis
			ArchKit.box(t.timber, _v(p, y1 - 0.35), Vector3(0.12, 0.85, 0.12), TIMBER, tilt)
	# Roof over the upper floors' rectangle, deep eaves.
	_roof(t, upper, eave, seed)


## Outward normal of edge a->b for a counter-clockwise ring (x east, z south).
func _outward(a: Vector2, b: Vector2) -> Vector2:
	var e := (b - a).normalized()
	return Vector2(e.y, -e.x)


## A window quad from the atlas, just proud of the wall at p (centre of the
## sill line), facing `out`.
func _window(t: Dictionary, p: Vector2, out: Vector2, sill: float, size: Vector2, variant: int, seed: int) -> void:
	var right := Vector2(-out.y, out.x)
	var c := p + out * 0.035
	var a := _v(c - right * size.x * 0.5, sill)
	var b := _v(c + right * size.x * 0.5, sill)
	var u0 := variant * 0.25
	var u1 := u0 + 0.25
	var home := 1.0 if _hash(seed, 3) > 0.45 else 0.0
	ArchKit.quad_uv(t.windows, a, b, b + Vector3.UP * size.y, a + Vector3.UP * size.y,
		Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0), Vector2(u0, 0), Color(_hash(seed, 9), home, 0.0), Vector3(out.x, 0, out.y))
	windows += 1


## A hipped roof of weathered tiles over the footprint's best-fit rectangle,
## eaves EAVE beyond the walls, dark fascia and soffit, ridge tiles, and on
## some houses a whitewashed chimney.
func _roof(t: Dictionary, ring: PackedVector2Array, eave: float, seed: int) -> void:
	# Long axis: the footprint's longest edge.
	var longest := 0
	for i in ring.size():
		if ring[i].distance_to(ring[(i + 1) % ring.size()]) > ring[longest].distance_to(ring[(longest + 1) % ring.size()]):
			longest = i
	var u := (ring[(longest + 1) % ring.size()] - ring[longest]).normalized()
	var v := Vector2(-u.y, u.x)
	var c := Vector2.ZERO
	for p in ring:
		c += p
	c /= ring.size()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in ring:
		var q := Vector2((p - c).dot(u), (p - c).dot(v))
		lo = lo.min(q)
		hi = hi.max(q)
	lo -= Vector2.ONE * EAVE
	hi += Vector2.ONE * EAVE
	var corner := func(x: float, y: float) -> Vector2: return c + u * x + v * y
	var y := eave + 0.05
	var half_w := (hi.y - lo.y) * 0.5
	var rise := half_w * PITCH
	var mid_y := (hi.y + lo.y) * 0.5
	var r0x := minf(lo.x + half_w, (lo.x + hi.x) * 0.5)
	var r1x := maxf(hi.x - half_w, (lo.x + hi.x) * 0.5)
	var a: Vector2 = corner.call(lo.x, lo.y)
	var b: Vector2 = corner.call(hi.x, lo.y)
	var cc: Vector2 = corner.call(hi.x, hi.y)
	var d: Vector2 = corner.call(lo.x, hi.y)
	var r0 := _v(corner.call(r0x, mid_y), y + rise)
	var r1 := _v(corner.call(r1x, mid_y), y + rise)
	var tint := Color(1, 1, 1).darkened(0.12 * _hash(seed, 77))
	_roof_plane(t.roof, [_v(a, y), _v(b, y), r1, r0], tint)
	_roof_plane(t.roof, [_v(cc, y), _v(d, y), r0, r1], tint)
	_roof_plane(t.roof, [_v(d, y), _v(a, y), r0, r0], tint)
	_roof_plane(t.roof, [_v(b, y), _v(cc, y), r1, r1], tint)
	# Ridge tiles.
	if r0.distance_to(r1) > 0.2:
		var dir := (r1 - r0).normalized()
		ArchKit.box(t.roof, (r0 + r1) * 0.5 + Vector3.UP * 0.06, Vector3(0.26, 0.12, r0.distance_to(r1) + 0.3), tint.darkened(0.1),
			Basis(dir.cross(Vector3.UP).normalized(), Vector3.UP, dir))
	# Dark timber fascia round the eaves and the soffit under them.
	var corners := [a, b, cc, d]
	for i in 4:
		var p: Vector2 = corners[i]
		var q: Vector2 = corners[(i + 1) % 4]
		var out := _outward(p, q)
		ArchKit.wall_quad(t.timber, _v(p, y - 0.22), _v(q, y - 0.22), _v(q, y + 0.02), _v(p, y + 0.02), TIMBER, Vector3(out.x, 0, out.y))
	ArchKit.quad_uv(t.timber, _v(a, y - 0.2), _v(b, y - 0.2), _v(cc, y - 0.2), _v(d, y - 0.2), a, b, cc, d, TIMBER.darkened(0.25), Vector3.DOWN)
	# A chimney on about half the houses.
	if seed % 2 == 0:
		var p := c + u * (hi.x - lo.x) * 0.18 + v * half_w * 0.25
		var top := y + rise * 0.6 + 1.2
		ArchKit.box(t.plaster, _v(p, (y + top) * 0.5), Vector3(0.62, top - y, 0.62), Color(0.96, 0.95, 0.92))
		ArchKit.box(t.roof, _v(p, top + 0.12), Vector3(0.9, 0.12, 0.9), tint)


func _roof_plane(st: SurfaceTool, pts: Array, col: Color) -> void:
	var a: Vector3 = pts[0]
	var b: Vector3 = pts[1]
	var c: Vector3 = pts[2]
	var d: Vector3 = pts[3]
	var along := (b - a).normalized()
	var n := (b - a).cross(c - a).normalized()
	if n.y < 0.0:
		n = -n
	var up_slope := n.cross(along).normalized()
	if up_slope.y < 0.0:
		up_slope = -up_slope
	var uv := func(p: Vector3) -> Vector2: return Vector2((p - a).dot(along), -(p - a).dot(up_slope))
	ArchKit.quad_uv(st, a, b, c, d, uv.call(a), uv.call(b), uv.call(c), uv.call(d), col, n)
