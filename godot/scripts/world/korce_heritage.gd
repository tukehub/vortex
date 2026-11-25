class_name KorceHeritage
extends Node3D
## Korçë's school house and the warrior on the cathedral square: original
## interpretations after photographs.
##   "mesonjetorja"      Mësonjëtorja, the first Albanian-language school
##       (opened 7 March 1887 in Diamanti Tërpo's house), now the National
##       Museum of Education: a two-storey house of rubble limestone laced
##       with timber bands, dressed quoins, dark wooden windows (barred below,
##       six-paned above), a white plastered oriel over the door on two
##       wooden posts, a low hipped roof of clay tiles on deep dark eaves; a
##       paved forecourt behind a black iron railing and arched gate, the
##       museum's stone, the marble plaque by the door and the flag.
##   "national_warrior"  Luftëtari Kombëtar (Odhise Paskali, 1932): a bronze
##       warrior with his rifle on a tall stepped stone pedestal.
## Local frame: both face -Z (the house its oriel front, toward Bulevardi
## Republika). Walls and plinths reach down to the terrain.

const REACH := 2200.0

const HALF := Vector2(8.8, 5.8)        # the house, 17.6 x 11.6 m
const FLOOR := 3.75                    # upper floor level
const EAVE := 7.3
const OVERHANG := 0.8
const PITCH := 0.42                    # roof rise per metre (about 23 degrees)
## The oriel: across x, out from the front wall, from its soffit to the eave.
const ORIEL_X := Vector2(0.2, 3.8)
const ORIEL_OUT := 1.25
const ORIEL_SOFFIT := 3.25
const YARD := 12.6                     # the railing, metres in front of the facade's centre line

const RUBBLE := Color("#f3f1ec")
const QUOIN := Color("#dcd8d0")
const PLINTH := Color("#b8b2a7")
const TIMBER := Color("#8e6a48")
const FRAME := Color("#3a2a20")
const DOOR := Color("#3b2518")
const PLASTER := Color("#f7f6f2")
const GLASS := Color("#263039")
const IRON := Color("#16181a")
const SOFFIT := Color("#3d3029")
const TILE := Color("#f0e6e0")
const TILE_RIDGE := Color("#d9b9a6")
const BRONZE := Color("#5a5240")

var _terrain: Terrain
var _rubble: SurfaceTool
var _trim: SurfaceTool
var _wood: SurfaceTool
var _glass: SurfaceTool
var _roof: SurfaceTool
var _yard: SurfaceTool
## Counts for tests: windows and railing bars built.
var windows := 0
var bars := 0


func build(landmark_id: String, terrain: Terrain) -> void:
	_terrain = terrain
	match landmark_id:
		"mesonjetorja":
			_school()
		"national_warrior":
			_warrior()


func _ground(x: float, z: float) -> float:
	var parent := get_parent() as Node3D
	if _terrain == null or parent == null:
		return 0.0
	var world := parent.transform * Vector3(x, 0.0, z)
	return _terrain.height_at(world.x, world.z) - parent.position.y


# ================================================================== the school

func _school() -> void:
	_rubble = ArchKit.begin()
	_trim = ArchKit.begin()
	_wood = ArchKit.begin()
	_glass = ArchKit.begin()
	_roof = ArchKit.begin()
	_yard = ArchKit.begin()
	var low := minf(minf(_ground(-HALF.x, -HALF.y), _ground(HALF.x, -HALF.y)), minf(_ground(-HALF.x, HALF.y), _ground(HALF.x, HALF.y))) - 0.6
	# Each face: corner a, unit along, outward normal, length, openings.
	var faces := [
		[Vector3(-HALF.x, 0, -HALF.y), Vector3.RIGHT, Vector3.FORWARD, HALF.x * 2.0, _front_openings()],
		[Vector3(HALF.x, 0, -HALF.y), Vector3.BACK, Vector3.RIGHT, HALF.y * 2.0, _side_openings()],
		[Vector3(HALF.x, 0, HALF.y), Vector3.LEFT, Vector3.BACK, HALF.x * 2.0, _back_openings()],
		[Vector3(-HALF.x, 0, HALF.y), Vector3.FORWARD, Vector3.LEFT, HALF.y * 2.0, _side_openings()],
	]
	for f in faces:
		_face(f[0], f[1], f[2], f[3], f[4], low)
	_quoins(low)
	_oriel()
	_door()
	_roof_and_eaves()
	_forecourt()
	_railing()
	_plaques()
	_flag(Vector3(9.6, _ground(9.6, -YARD + 1.0), -YARD + 1.0))
	var rubble := ArchKit.material(preload("res://assets/textures/rubble_wall_diff.jpg"),
		preload("res://assets/textures/rubble_wall_nor.jpg"), preload("res://assets/textures/rubble_wall_arm.jpg"),
		2.4, Color(1.06, 1.1, 1.13))
	var trim := ArchKit.material(preload("res://assets/textures/stucco_diff.jpg"),
		preload("res://assets/textures/stucco_nor.jpg"), preload("res://assets/textures/stucco_arm.jpg"), 2.0,
		Color(1.05, 1.05, 1.04), 0.6)
	var roof := ArchKit.material(preload("res://assets/textures/clay_roof_diff.jpg"),
		preload("res://assets/textures/clay_roof_nor.jpg"), preload("res://assets/textures/clay_roof_arm.jpg"),
		3.0, Color(1.0, 0.86, 0.8))
	var yard := ArchKit.material(preload("res://assets/textures/promenade_paving_diff.jpg"),
		preload("res://assets/textures/promenade_paving_nor.jpg"), preload("res://assets/textures/promenade_paving_arm.jpg"), 2.6)
	add_child(ArchKit.node(_rubble, rubble, "SchoolRubbleWalls", REACH))
	add_child(ArchKit.node(_trim, trim, "SchoolDressedStoneAndPlaster", REACH))
	add_child(ArchKit.node(_wood, LandmarkKit.material(0.72, 0.0), "SchoolTimberAndIron", 900.0))
	add_child(ArchKit.node(_glass, LandmarkKit.material(0.16, 0.35), "SchoolGlass", 900.0))
	add_child(ArchKit.node(_roof, roof, "SchoolRoof", REACH))
	var court := ArchKit.node(_yard, yard, "SchoolForecourt", 700.0)
	court.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(court)


## Openings on a face: [x centre, sill y, width, height, kind]; kind is
## "upper" (six panes), "lower" (barred), "small" or "door".
func _front_openings() -> Array:
	var out := []
	for x: float in [-6.4, -3.6, -1.0, 5.3, 7.5]:
		out.append([x + HALF.x, FLOOR + 0.6, 1.2, 2.15, "upper"])
	for x: float in [-6.4, -3.6, 5.3, 7.5]:
		out.append([x + HALF.x, 0.95, 1.15, 1.6, "lower"])
	out.append([-1.15 + HALF.x, 1.5, 0.75, 0.85, "small"])
	out.append([3.35 + HALF.x, 1.5, 0.7, 0.85, "small"])
	out.append([2.0 + HALF.x, 0.12, 1.45, 2.5, "door"])
	return out


func _side_openings() -> Array:
	var out := []
	for z: float in [-3.3, 0.0, 3.3]:
		out.append([z + HALF.y, FLOOR + 0.6, 1.15, 2.1, "upper"])
		out.append([z + HALF.y, 0.95, 1.1, 1.55, "lower"])
	return out


func _back_openings() -> Array:
	var out := []
	for x: float in [-6.6, -3.3, 0.0, 3.3, 6.6]:
		out.append([x + HALF.x, FLOOR + 0.6, 1.15, 2.1, "upper"])
		if absf(x) > 1.0:
			out.append([x + HALF.x, 0.95, 1.1, 1.55, "lower"])
	return out


## One wall: rubble between the openings, the timber bands that lace it
## (broken by the openings), lintels and the openings themselves.
func _face(a: Vector3, along: Vector3, out: Vector3, length: float, openings: Array, low: float) -> void:
	var p := func(x: float, y: float, depth: float) -> Vector3: return a + along * x + Vector3.UP * y + out * depth
	# The wall, in vertical strips split at the openings' edges, each strip
	# leaving out the openings' heights.
	var cuts: Array[float] = [0.0, length]
	for o in openings:
		cuts.append(float(o[0]) - float(o[2]) * 0.5)
		cuts.append(float(o[0]) + float(o[2]) * 0.5)
	cuts.sort()
	for i in cuts.size() - 1:
		var x0 := cuts[i]
		var x1 := cuts[i + 1]
		if x1 - x0 < 0.005:
			continue
		var mid := (x0 + x1) * 0.5
		var spans: Array = [[low, EAVE]]
		for o in openings:
			if absf(mid - float(o[0])) < float(o[2]) * 0.5:
				var y0: float = o[1]
				var y1: float = float(o[1]) + float(o[3])
				var next: Array = []
				for s in spans:
					if y1 <= s[0] or y0 >= s[1]:
						next.append(s)
						continue
					if y0 > s[0]:
						next.append([s[0], y0])
					if y1 < s[1]:
						next.append([y1, s[1]])
				spans = next
		for s in spans:
			ArchKit.wall_quad(_rubble, p.call(x0, s[0], 0.0), p.call(x1, s[0], 0.0), p.call(x1, s[1], 0.0), p.call(x0, s[1], 0.0), RUBBLE, out)
	# A plinth course of larger dressed stones at the foot.
	ArchKit.box(_trim, (p.call(0.0, 0.0, 0.0) + p.call(length, 0.0, 0.0)) * 0.5 + Vector3.UP * (low + 0.55) * 0.5 + out * 0.04,
		Vector3(length + 0.08, 0.55 - low, 0.1), PLINTH, Basis(along, Vector3.UP, out))
	# Timber bands about every 0.95 m, set just proud of the stone.
	for y: float in [1.0, 1.95, 2.9, FLOOR - 0.05, 4.6, 5.55, 6.5]:
		var segs: Array = [[0.25, length - 0.25]]
		for o in openings:
			if float(y) > float(o[1]) - 0.2 and float(y) < float(o[1]) + float(o[3]) + 0.25:
				var g0: float = float(o[0]) - float(o[2]) * 0.5 - 0.12
				var g1: float = float(o[0]) + float(o[2]) * 0.5 + 0.12
				var next: Array = []
				for s in segs:
					if g1 <= s[0] or g0 >= s[1]:
						next.append(s)
						continue
					if g0 > s[0]:
						next.append([s[0], g0])
					if g1 < s[1]:
						next.append([g1, s[1]])
				segs = next
		for s in segs:
			var w: float = s[1] - s[0]
			if w > 0.08:
				ArchKit.box(_wood, p.call((s[0] + s[1]) * 0.5, y, 0.02), Vector3(w, 0.1, 0.05), TIMBER.darkened(0.06 * (int(y * 3.0) % 3)), Basis(along, Vector3.UP, out))
	for o in openings:
		_opening(p.call(float(o[0]), float(o[1]), 0.0), along, out, float(o[2]), float(o[3]), str(o[4]))
	# A rainwater pipe down the front.
	if out == Vector3.FORWARD:
		var pipe: Vector3 = p.call(HALF.x - 2.3, 0.0, 0.14)
		LandmarkKit.tube(_wood, pipe + Vector3.UP * low, pipe + Vector3.UP * (EAVE - 0.1), 0.055, 0.055, Color("#7d7f80"), 6)
		for y: float in [1.5, 3.5, 5.5]:
			ArchKit.box(_wood, pipe + Vector3.UP * y - out * 0.07, Vector3(0.14, 0.04, 0.14), Color("#5e6062"), Basis(along, Vector3.UP, out))


## A window or the door: a reveal in shadow, a dark timber frame, glass and
## glazing bars (or iron bars below), a timber lintel and sill.
func _opening(foot: Vector3, along: Vector3, out: Vector3, w: float, h: float, kind: String) -> void:
	var b := Basis(along, Vector3.UP, out)
	# Reveal: the wall's thickness round the opening, in dressed stone.
	for side: float in [-1.0, 1.0]:
		ArchKit.box(_trim, foot + along * side * (w * 0.5 - 0.06) + Vector3.UP * h * 0.5 - out * 0.15, Vector3(0.12, h, 0.3), QUOIN.darkened(0.08), b)
	ArchKit.box(_wood, foot + Vector3.UP * (h + 0.09) + out * 0.02, Vector3(w + 0.5, 0.18, 0.1), TIMBER.darkened(0.12), b)
	ArchKit.box(_trim, foot + Vector3.UP * (h - 0.06) - out * 0.15, Vector3(w, 0.12, 0.3), QUOIN.darkened(0.12), b)
	if kind == "door":
		return
	ArchKit.box(_trim, foot + Vector3.UP * 0.05 - out * 0.15, Vector3(w, 0.1, 0.3), QUOIN.darkened(0.08), b)
	ArchKit.box(_trim, foot - Vector3.UP * 0.05 + out * 0.04, Vector3(w + 0.16, 0.1, 0.16), QUOIN, b)
	var back := foot - out * 0.22
	ArchKit.wall_quad(_glass, back - along * w * 0.5, back + along * w * 0.5, back + along * w * 0.5 + Vector3.UP * h, back - along * w * 0.5 + Vector3.UP * h, GLASS, out)
	var f := 0.09
	var frame_at := foot - out * 0.17
	for side: float in [-1.0, 1.0]:
		ArchKit.box(_wood, frame_at + along * side * (w * 0.5 - f * 0.5) + Vector3.UP * h * 0.5, Vector3(f, h, 0.1), FRAME, b)
	for y: float in [f * 0.5, h - f * 0.5]:
		ArchKit.box(_wood, frame_at + Vector3.UP * y, Vector3(w, f, 0.1), FRAME, b)
	match kind:
		"upper":
			ArchKit.box(_wood, frame_at + Vector3.UP * h * 0.5, Vector3(0.07, h, 0.08), FRAME, b)
			for t: float in [0.36, 0.68]:
				ArchKit.box(_wood, frame_at + Vector3.UP * h * t, Vector3(w, 0.05, 0.07), FRAME, b)
		"lower", "small":
			ArchKit.box(_wood, frame_at + Vector3.UP * h * 0.5, Vector3(0.06, h, 0.08), FRAME, b)
			var n := 5 if kind == "lower" else 3
			for k in n:
				var x := -w * 0.5 + w * (k + 0.5) / n
				ArchKit.box(_wood, foot - out * 0.06 + along * x + Vector3.UP * h * 0.5, Vector3(0.03, h - 0.04, 0.03), IRON, b)
			ArchKit.box(_wood, foot - out * 0.06 + Vector3.UP * h * 0.5, Vector3(w - 0.04, 0.03, 0.03), IRON, b)
	windows += 1


## Dressed quoins at the four corners, long and short in turn.
func _quoins(low: float) -> void:
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			var c := Vector3(cx * HALF.x, 0, cz * HALF.y)
			var y := 0.55
			var k := 0
			while y < EAVE - 0.2:
				var hgt := 0.34
				var long := k % 2 == 0
				var lx := 0.62 if long else 0.34
				var lz := 0.34 if long else 0.62
				ArchKit.box(_trim, c + Vector3(-cx * lx * 0.5 + cx * 0.025, y + hgt * 0.5, -cz * lz * 0.5 + cz * 0.025),
					Vector3(lx, hgt - 0.03, lz), QUOIN.darkened(0.05 * (k % 3)))
				y += hgt
				k += 1


## The oriel over the door: white plaster on a dark timber floor beam, two
## front windows and one each side, a skirt arched over the doorway, and two
## wooden posts down to the ground.
func _oriel() -> void:
	var x0 := ORIEL_X.x - HALF.x * 0.0
	var x1 := ORIEL_X.y
	var zf := -HALF.y - ORIEL_OUT
	var zb := -HALF.y
	var y0 := ORIEL_SOFFIT
	var top := EAVE
	var white := PLASTER
	# Box walls: front and two sides, from the floor beam to the eave.
	var fy := FLOOR - 0.1
	var openings_front := [[(x1 - x0) * 0.5 - 0.62, 0.92], [(x1 - x0) * 0.5 + 0.62, 0.92]]
	_plaster_wall(Vector3(x0, 0, zf), Vector3.RIGHT, Vector3.FORWARD, x1 - x0, fy, top, openings_front)
	_plaster_wall(Vector3(x1, 0, zf), Vector3.BACK, Vector3.RIGHT, ORIEL_OUT, fy, top, [[ORIEL_OUT * 0.5, 0.62]])
	_plaster_wall(Vector3(x0, 0, zb), Vector3.FORWARD, Vector3.LEFT, ORIEL_OUT, fy, top, [[ORIEL_OUT * 0.5, 0.62]])
	# The skirt under the floor beam, its lower edge arched over the door.
	var steps := 12
	for k in steps:
		var t0 := float(k) / steps
		var t1 := float(k + 1) / steps
		var xa := lerpf(x0, x1, t0)
		var xb := lerpf(x0, x1, t1)
		var arch := func(t: float) -> float: return y0 - 0.75 + 0.75 * sqrt(maxf(0.0, 1.0 - pow(2.0 * t - 1.0, 2.0)))
		ArchKit.wall_quad(_trim, Vector3(xa, arch.call(t0), zf), Vector3(xb, arch.call(t1), zf), Vector3(xb, fy, zf), Vector3(xa, fy, zf), white, Vector3.FORWARD)
		# Soffit of the skirt, following the arch back to the wall.
		ArchKit.wall_quad(_trim, Vector3(xa, arch.call(t0), zf), Vector3(xb, arch.call(t1), zf), Vector3(xb, arch.call(t1), zb), Vector3(xa, arch.call(t0), zb), white.darkened(0.12), Vector3.DOWN)
	for side: float in [0, 1]:
		var x := x0 if side == 0 else x1
		var n := Vector3.LEFT if side == 0 else Vector3.RIGHT
		ArchKit.wall_quad(_trim, Vector3(x, y0 - 0.75, zf), Vector3(x, y0 - 0.75, zb), Vector3(x, fy, zb), Vector3(x, fy, zf), white, n)
	# Dark floor beam round the oriel and corner battens up to the eave.
	ArchKit.box(_wood, Vector3((x0 + x1) * 0.5, fy + 0.08, zf - 0.04), Vector3(x1 - x0 + 0.16, 0.16, 0.1), FRAME)
	for x: float in [x0, x1]:
		ArchKit.box(_wood, Vector3(x, fy + 0.08, (zf + zb) * 0.5), Vector3(0.1, 0.16, ORIEL_OUT + 0.1), FRAME)
		ArchKit.box(_wood, Vector3(x, (fy + top) * 0.5, zf - 0.03), Vector3(0.12, top - fy, 0.12), FRAME)
	# Two turned posts from the ground to the skirt.
	for x: float in [x0 + 0.12, x1 - 0.12]:
		var g := _ground(x, zf + 0.15)
		LandmarkKit.tube(_wood, Vector3(x, g, zf + 0.15), Vector3(x, y0 - 0.75, zf + 0.15), 0.1, 0.09, FRAME, 8)
		ArchKit.box(_wood, Vector3(x, g + 0.1, zf + 0.15), Vector3(0.28, 0.2, 0.28), PLINTH.darkened(0.3))
		ArchKit.box(_wood, Vector3(x, y0 - 0.82, zf + 0.15), Vector3(0.26, 0.12, 0.26), FRAME)
	# The oriel's windows.
	for o in openings_front:
		_opening(Vector3(x0 + float(o[0]), fy + 0.55, zf), Vector3.RIGHT, Vector3.FORWARD, o[1], 2.1, "upper")
	_opening(Vector3(x1, fy + 0.55, zf + ORIEL_OUT * 0.5), Vector3.BACK, Vector3.RIGHT, 0.62, 2.1, "upper")
	_opening(Vector3(x0, fy + 0.55, zf + ORIEL_OUT * 0.5), Vector3.FORWARD, Vector3.LEFT, 0.62, 2.1, "upper")


## A plastered wall strip from y0 to y1 with window gaps [[x, w], ...] from
## its sill (y0 + 0.55) to y0 + 2.65.
func _plaster_wall(a: Vector3, along: Vector3, out: Vector3, length: float, y0: float, y1: float, gaps: Array) -> void:
	var sill := y0 + 0.55
	var head := sill + 2.1
	var cuts: Array[float] = [0.0, length]
	for g in gaps:
		cuts.append(float(g[0]) - float(g[1]) * 0.5)
		cuts.append(float(g[0]) + float(g[1]) * 0.5)
	cuts.sort()
	for i in cuts.size() - 1:
		var x0 := cuts[i]
		var x1 := cuts[i + 1]
		var mid := (x0 + x1) * 0.5
		var in_gap := false
		for g in gaps:
			if absf(mid - float(g[0])) < float(g[1]) * 0.5:
				in_gap = true
		var spans := [[y0, sill], [head, y1]] if in_gap else [[y0, y1]]
		for s in spans:
			ArchKit.wall_quad(_trim, a + along * x0 + Vector3.UP * s[0], a + along * x1 + Vector3.UP * s[0],
				a + along * x1 + Vector3.UP * s[1], a + along * x0 + Vector3.UP * s[1], PLASTER, out)


## The front door: two panelled leaves in a frame of brown dressed stones.
func _door() -> void:
	var x := 2.0
	var w := 1.45
	var h := 2.5
	var z := -HALF.y
	var b := Basis.IDENTITY
	var foot := Vector3(x, 0.12, z)
	# Dressed-stone surround, blocks of alternating length.
	var stone := Color("#a8906f")
	var y := 0.12
	var k := 0
	while y < h + 0.1:
		for side: float in [-1.0, 1.0]:
			var lx := 0.5 if (k + int(side > 0.0)) % 2 == 0 else 0.32
			ArchKit.box(_trim, foot + Vector3(side * (w * 0.5 + lx * 0.5), y - 0.12 + 0.17, -0.03), Vector3(lx - 0.02, 0.32, 0.08), stone.darkened(0.06 * (k % 3)), b)
		y += 0.34
		k += 1
	ArchKit.box(_trim, foot + Vector3(0, h + 0.2, -0.03), Vector3(w + 1.0, 0.36, 0.08), stone.darkened(0.04), b)
	ArchKit.box(_trim, Vector3(x, 0.06, z - 0.45), Vector3(w + 0.9, 0.12, 0.9), PLINTH, b)
	# The leaves, set back, with raised panels.
	var back := z + 0.1
	for side: float in [-1.0, 1.0]:
		var c := Vector3(x + side * w * 0.25, 0.12 + h * 0.5, back)
		ArchKit.box(_wood, c, Vector3(w * 0.5 - 0.02, h, 0.06), DOOR, b)
		for py: float in [0.55, 1.45, 2.15]:
			ArchKit.box(_wood, Vector3(c.x, 0.12 + py, back - 0.04), Vector3(w * 0.5 - 0.22, 0.5 if py < 2.0 else 0.4, 0.03), DOOR.lightened(0.08), b)
		ArchKit.box(_wood, Vector3(x + side * 0.08, 0.12 + 1.15, back - 0.06), Vector3(0.03, 0.18, 0.04), Color("#a68b4c"), b)


## Low hipped roof of clay tiles on deep eaves with dark boards and soffit;
## a small hip roof over the oriel, ridge and hip tiles.
func _roof_and_eaves() -> void:
	var ex := HALF.x + OVERHANG
	var ez := HALF.y + OVERHANG
	var rise := ez * PITCH
	var ridge := ex - ez
	var y := EAVE + 0.05
	var a := Vector3(-ex, y, -ez)
	var b := Vector3(ex, y, -ez)
	var c := Vector3(ex, y, ez)
	var d := Vector3(-ex, y, ez)
	var r0 := Vector3(-ridge, y + rise, 0)
	var r1 := Vector3(ridge, y + rise, 0)
	_roof_plane([a, b, r1, r0], TILE)
	_roof_plane([c, d, r0, r1], TILE)
	_roof_plane([d, a, r0, r0], TILE)
	_roof_plane([b, c, r1, r1], TILE)
	# Ridge and hip tiles.
	_roll(r0, r1)
	for corner in [[a, r0], [b, r1], [c, r1], [d, r0]]:
		_roll(corner[0], corner[1])
	# Fascia boards and the dark soffit under the eaves.
	for e in [[a, b], [b, c], [c, d], [d, a]]:
		var p: Vector3 = e[0]
		var q: Vector3 = e[1]
		var along := (q - p).normalized()
		var out := Vector3.UP.cross(along) * -1.0
		ArchKit.box(_wood, (p + q) * 0.5 - Vector3.UP * 0.1, Vector3(p.distance_to(q) + 0.1, 0.24, 0.06), FRAME, Basis(along, Vector3.UP, out))
	ArchKit.wall_quad(_wood, Vector3(-ex, EAVE - 0.08, -ez), Vector3(ex, EAVE - 0.08, -ez), Vector3(ex, EAVE - 0.08, ez), Vector3(-ex, EAVE - 0.08, ez), SOFFIT, Vector3.DOWN)
	# The oriel's own roof, hipped out of the front slope.
	var ox0 := ORIEL_X.x - 0.6
	var ox1 := ORIEL_X.y + 0.6
	var oz := -HALF.y - ORIEL_OUT - 0.65
	var ob := -ez + 0.4
	var oy := EAVE + 0.12
	var o_rise := (ob - oz) * PITCH * 1.2
	var mid := (ox0 + ox1) * 0.5
	# The oriel's ridge runs back until it dies into the main front slope.
	var apex_y := oy + o_rise + 0.05
	var apex := Vector3(mid, apex_y, -ez + (apex_y - y) / PITCH)
	var p0 := Vector3(ox0, oy, oz)
	var p1 := Vector3(ox1, oy, oz)
	var p2 := Vector3(ox1, oy + 0.05, ob)
	var p3 := Vector3(ox0, oy + 0.05, ob)
	var front_ridge := Vector3(mid, oy + o_rise * 0.8, oz + (ox1 - ox0) * 0.42)
	_roof_plane([p0, p1, front_ridge, front_ridge], TILE)
	_roof_plane([p1, p2, apex, front_ridge], TILE)
	_roof_plane([p3, p0, front_ridge, apex], TILE)
	_roll(front_ridge, apex)
	_roll(p0, front_ridge)
	_roll(p1, front_ridge)
	ArchKit.box(_wood, Vector3(mid, oy - 0.1, oz), Vector3(ox1 - ox0 + 0.1, 0.24, 0.06), FRAME)
	for x: float in [ox0, ox1]:
		ArchKit.box(_wood, Vector3(x, oy - 0.1, (oz + ob) * 0.5), Vector3(0.06, 0.24, ob - oz), FRAME)
	ArchKit.wall_quad(_wood, Vector3(ox0, oy - 0.2, oz), Vector3(ox1, oy - 0.2, oz), Vector3(ox1, oy - 0.2, ob), Vector3(ox0, oy - 0.2, ob), SOFFIT, Vector3.DOWN)


## A roof face (a quad, or a triangle with its last two corners equal): the
## tile texture runs down the slope, u along the eave a->b.
func _roof_plane(pts: Array, col: Color) -> void:
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
	ArchKit.quad_uv(_roof, a, b, c, d, uv.call(a), uv.call(b), uv.call(c), uv.call(d), col, n)


## Rounded ridge (or hip) tiles from p to q.
func _roll(p: Vector3, q: Vector3) -> void:
	var dir := (q - p)
	var span := dir.length()
	if span < 0.05:
		return
	dir /= span
	var side := dir.cross(Vector3.UP).normalized()
	var up := side.cross(dir).normalized()
	if up.y < 0.0:
		up = -up
	ArchKit.box(_roof, (p + q) * 0.5 + up * 0.07, Vector3(0.24, 0.12, span), TILE_RIDGE, Basis(side, up, dir))


# ------------------------------------------------------------------ forecourt

func _forecourt() -> void:
	var size := 1.5
	var x := -10.5
	while x < 10.49:
		var z := -YARD
		while z < -HALF.y - 0.01:
			var z1 := minf(z + size, -HALF.y)
			var pts: Array[Vector3] = []
			for p: Vector2 in [Vector2(x, z), Vector2(x + size, z), Vector2(x + size, z1), Vector2(x, z1)]:
				pts.append(Vector3(p.x, _ground(p.x, p.y) + 0.07, p.y))
			ArchKit.quad_uv(_yard, pts[0], pts[1], pts[2], pts[3], Vector2(pts[0].x, pts[0].z), Vector2(pts[1].x, pts[1].z),
				Vector2(pts[2].x, pts[2].z), Vector2(pts[3].x, pts[3].z), Color("#e8e4dc"), Vector3.UP)
			z += size
		x += size
	# Two benches against the wall, as in front of the museum.
	for bx: float in [-6.0, 5.6]:
		var g := _ground(bx, -HALF.y - 1.2)
		ArchKit.box(_wood, Vector3(bx, g + 0.45, -HALF.y - 1.2), Vector3(1.8, 0.07, 0.42), Color("#5b4130"))
		ArchKit.box(_wood, Vector3(bx, g + 0.78, -HALF.y - 1.0), Vector3(1.8, 0.4, 0.05), Color("#5b4130"))
		for sx: float in [-0.8, 0.8]:
			ArchKit.box(_wood, Vector3(bx + sx, g + 0.22, -HALF.y - 1.2), Vector3(0.06, 0.44, 0.45), IRON)


## The black iron railing on a stone kerb round the forecourt, with an arched
## double gate before the door and stone gate piers.
func _railing() -> void:
	var gate_x := 2.0
	var gate_w := 2.6
	var z := -YARD
	var runs := [[Vector3(-10.5, 0, z), Vector3(gate_x - gate_w * 0.5 - 0.35, 0, z)],
		[Vector3(gate_x + gate_w * 0.5 + 0.35, 0, z), Vector3(10.5, 0, z)],
		[Vector3(-10.5, 0, z), Vector3(-10.5, 0, -HALF.y)],
		[Vector3(10.5, 0, z), Vector3(10.5, 0, -HALF.y)]]
	for run in runs:
		var p: Vector3 = run[0]
		var q: Vector3 = run[1]
		var along := (q - p).normalized()
		var length := p.distance_to(q)
		var out := along.cross(Vector3.UP).normalized()
		var basis := Basis(along, Vector3.UP, out)
		var n := maxi(1, int(length / 0.5))
		for k in n:
			var c := p.lerp(q, (k + 0.5) / n)
			var g := _ground(c.x, c.z)
			ArchKit.box(_trim, Vector3(c.x, g + 0.18, c.z), Vector3(length / n + 0.01, 0.62, 0.42), PLINTH, basis)
		var g0 := _ground((p.x + q.x) * 0.5, (p.z + q.z) * 0.5)
		var base := g0 + 0.5
		ArchKit.box(_wood, (p + q) * 0.5 + Vector3.UP * (base + 0.12), Vector3(length, 0.05, 0.05), IRON, basis)
		ArchKit.box(_wood, (p + q) * 0.5 + Vector3.UP * (base + 1.42), Vector3(length, 0.05, 0.05), IRON, basis)
		var count := int(length / 0.13)
		for k in count:
			var c := p.lerp(q, (k + 0.5) / count)
			var tall := 1.55 if k % 2 == 0 else 1.5
			ArchKit.box(_wood, Vector3(c.x, base + tall * 0.5, c.z), Vector3(0.022, tall, 0.022), IRON, basis)
			bars += 1
		for k in int(length / 2.6) + 1:
			var c := p.lerp(q, minf(1.0, k * 2.6 / length))
			ArchKit.box(_wood, Vector3(c.x, base + 0.85, c.z), Vector3(0.07, 1.7, 0.07), IRON, basis)
			LandmarkKit.sphere(_wood, Vector3(c.x, base + 1.75, c.z), Vector3(0.06, 0.06, 0.06), IRON, 3, 6)
	# Gate piers and the arched double gate.
	for side: float in [-1.0, 1.0]:
		var px: float = gate_x + side * (gate_w * 0.5 + 0.2)
		var g := _ground(px, z)
		ArchKit.box(_trim, Vector3(px, g + 1.0, z), Vector3(0.42, 2.0 + 0.2, 0.42), QUOIN)
		ArchKit.box(_trim, Vector3(px, g + 2.15, z), Vector3(0.56, 0.12, 0.56), PLINTH)
	var gb := _ground(gate_x, z) + 0.1
	var r := gate_w * 0.5
	for k in 15:
		var x := -r + gate_w * (k + 0.5) / 15.0
		var top := 2.0 + 0.45 * sqrt(maxf(0.0, 1.0 - pow(x / r, 2.0)))
		ArchKit.box(_wood, Vector3(gate_x + x, gb + top * 0.5, z), Vector3(0.025, top, 0.025), IRON)
		bars += 1
	for y: float in [0.15, 0.95, 1.95]:
		ArchKit.box(_wood, Vector3(gate_x, gb + y, z), Vector3(gate_w, 0.05, 0.05), IRON)
	ArchKit.box(_wood, Vector3(gate_x, gb + 1.15, z), Vector3(0.06, 2.3, 0.06), IRON)
	for k in 12:
		var t0 := PI * k / 12.0
		var t1 := PI * (k + 1) / 12.0
		var p0 := Vector3(gate_x + cos(t0) * r, gb + 2.0 + sin(t0) * 0.45, z)
		var p1 := Vector3(gate_x + cos(t1) * r, gb + 2.0 + sin(t1) * 0.45, z)
		var seg := p1 - p0
		ArchKit.box(_wood, (p0 + p1) * 0.5, Vector3(seg.length() + 0.02, 0.05, 0.05), IRON, Basis(seg.normalized(), Vector3.FORWARD.cross(seg.normalized()), Vector3.FORWARD))
	for side: float in [-1.0, 1.0]:
		var c := Vector3(gate_x + side * r * 0.5, gb + 1.45, z)
		for k in 10:
			var t0 := TAU * k / 10.0
			var t1 := TAU * (k + 1) / 10.0
			var p0 := c + Vector3(cos(t0), sin(t0), 0) * 0.3
			var p1 := c + Vector3(cos(t1), sin(t1), 0) * 0.3
			var seg := p1 - p0
			ArchKit.box(_wood, (p0 + p1) * 0.5, Vector3(seg.length() + 0.02, 0.04, 0.04), IRON, Basis(seg.normalized(), Vector3.FORWARD.cross(seg.normalized()), Vector3.FORWARD))


## The museum's stone by the gate and the marble plaque by the door.
func _plaques() -> void:
	var sx := 5.2
	var sz := -YARD - 0.6
	var g := _ground(sx, sz)
	ArchKit.box(_wood, Vector3(sx, g + 0.75, sz), Vector3(0.75, 1.5, 0.3), Color("#3a3634"))
	ArchKit.box(_trim, Vector3(sx, g + 0.06, sz), Vector3(1.0, 0.12, 0.55), PLINTH)
	var label := Label3D.new()
	label.name = "MuseumStone"
	label.text = Data.t("sign.korce_museum")
	label.font_size = 40
	label.pixel_size = 0.0042
	label.modulate = Color("#e9e4d8")
	label.outline_size = 0
	label.position = Vector3(sx, g + 1.0, sz - 0.16)
	label.rotation.y = PI
	label.visibility_range_end = 80.0
	add_child(label)
	ArchKit.box(_trim, Vector3(-0.25, 2.05, -HALF.y - 0.04), Vector3(0.72, 0.56, 0.06), Color("#efece6"))
	var plaque := Label3D.new()
	plaque.name = "SchoolPlaque"
	plaque.text = Data.t("sign.mesonjetorja")
	plaque.font_size = 24
	plaque.pixel_size = 0.0022
	plaque.modulate = Color("#2b2723")
	plaque.outline_size = 0
	plaque.position = Vector3(-0.25, 2.05, -HALF.y - 0.08)
	plaque.rotation.y = PI
	plaque.visibility_range_end = 60.0
	add_child(plaque)


func _flag(at: Vector3) -> void:
	var st := LandmarkKit.begin()
	LandmarkKit.tube(st, at, at + Vector3(0, 7.5, 0), 0.06, 0.045, Color("#d4d6d8"), 8)
	LandmarkKit.sphere(st, at + Vector3(0, 7.55, 0), Vector3(0.09, 0.09, 0.09), Color("#c9a85a"), 4, 6)
	add_child(LandmarkKit.mesh_node(st, LandmarkKit.material(0.4, 0.6), "SchoolFlagPole", REACH))
	var cloth := QuadMesh.new()
	cloth.size = Vector2(2.0, 1.4)
	cloth.subdivide_width = 10
	cloth.subdivide_depth = 4
	var flag := MeshInstance3D.new()
	flag.name = "SchoolFlag"
	flag.mesh = cloth
	flag.position = at + Vector3(1.05, 6.7, 0)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/flag_wave.gdshader")
	mat.set_shader_parameter("use_tex", true)
	mat.set_shader_parameter("flag_tex", LandmarkKit.albanian_flag())
	mat.set_shader_parameter("wave", 3.0)
	flag.material_override = mat
	flag.visibility_range_end = 1400.0
	add_child(flag)


# ================================================================== the warrior

## Luftëtari Kombëtar: a bronze warrior in a long coat, his rifle grounded at
## his right side, on a stepped pedestal of grey limestone.
func _warrior() -> void:
	var stone := ArchKit.begin()
	var g := minf(minf(_ground(-2.4, -2.4), _ground(2.4, -2.4)), minf(_ground(-2.4, 2.4), _ground(2.4, 2.4)))
	for step in [[4.6, 0.3], [3.8, 0.3], [2.9, 0.35]]:
		ArchKit.box(stone, Vector3(0, g + float(step[1]) * 0.5, 0), Vector3(step[0], step[1], step[0]), Color("#d6d1c6"))
		g += float(step[1])
	ArchKit.box(stone, Vector3(0, g + 0.2, 0), Vector3(2.3, 0.4, 2.3), Color("#cfc9bd"))
	ArchKit.box(stone, Vector3(0, g + 1.95, 0), Vector3(1.9, 3.1, 1.9), Color("#e2ddd2"))
	ArchKit.box(stone, Vector3(0, g + 3.62, 0), Vector3(2.2, 0.24, 2.2), Color("#d2ccc0"))
	ArchKit.box(stone, Vector3(0, g + 3.86, 0), Vector3(1.7, 0.24, 1.7), Color("#c9c2b5"))
	# Bronze lettering band on the front.
	ArchKit.box(stone, Vector3(0, g + 2.6, -0.97), Vector3(1.3, 0.22, 0.04), Color("#4a4434"))
	var mat := ArchKit.material(preload("res://assets/textures/ashlar_buff_diff.jpg"),
		preload("res://assets/textures/ashlar_buff_nor.jpg"), preload("res://assets/textures/ashlar_buff_arm.jpg"), 2.2, Color(1.02, 1.0, 0.98))
	add_child(ArchKit.node(stone, mat, "WarriorPedestal", REACH))
	var top := g + 3.98
	var st := LandmarkKit.begin()
	var b := BRONZE
	# Legs, boots, the long coat (a flared skirt) and the belted torso.
	for x: float in [-0.17, 0.17]:
		LandmarkKit.tube(st, Vector3(x, top, 0), Vector3(x * 0.9, top + 1.15, 0.0), 0.12, 0.14, b.darkened(0.15), 8)
		LandmarkKit.box(st, Vector3(x, top + 0.08, -0.08), Vector3(0.2, 0.16, 0.36), b.darkened(0.2))
	LandmarkKit.tube(st, Vector3(0, top + 0.55, 0), Vector3(0, top + 1.35, 0), 0.48, 0.3, b, 12)
	LandmarkKit.tube(st, Vector3(0, top + 1.3, 0), Vector3(0, top + 2.05, 0), 0.3, 0.34, b.lightened(0.04), 10)
	LandmarkKit.tube(st, Vector3(0, top + 1.32, 0), Vector3(0, top + 1.42, 0), 0.32, 0.32, b.darkened(0.25), 10)
	LandmarkKit.sphere(st, Vector3(0, top + 2.05, 0), Vector3(0.42, 0.16, 0.24), b, 5, 10)
	# Head, neck and the felt cap (plis).
	LandmarkKit.tube(st, Vector3(0, top + 2.1, 0), Vector3(0, top + 2.28, 0), 0.09, 0.09, b, 8)
	LandmarkKit.sphere(st, Vector3(0, top + 2.42, -0.02), Vector3(0.14, 0.17, 0.15), b.lightened(0.05), 6, 10)
	LandmarkKit.tube(st, Vector3(0, top + 2.52, -0.01), Vector3(0, top + 2.66, -0.01), 0.15, 0.14, Color("#d9d4c6").lerp(b, 0.85), 10)
	# Left arm raised across the chest; right arm down, gripping the rifle.
	LandmarkKit.tube(st, Vector3(-0.4, top + 2.0, 0), Vector3(-0.42, top + 1.6, -0.12), 0.09, 0.08, b, 8)
	LandmarkKit.tube(st, Vector3(-0.42, top + 1.6, -0.12), Vector3(-0.1, top + 1.82, -0.28), 0.08, 0.07, b, 8)
	LandmarkKit.tube(st, Vector3(0.4, top + 2.0, 0), Vector3(0.48, top + 1.5, -0.05), 0.09, 0.08, b, 8)
	LandmarkKit.tube(st, Vector3(0.48, top + 1.5, -0.05), Vector3(0.52, top + 1.08, -0.12), 0.08, 0.07, b, 8)
	# The rifle, butt on the plinth, barrel up past the shoulder.
	LandmarkKit.box(st, Vector3(0.62, top + 0.12, -0.14), Vector3(0.1, 0.24, 0.24), b.darkened(0.3))
	LandmarkKit.tube(st, Vector3(0.62, top + 0.2, -0.14), Vector3(0.58, top + 2.35, -0.1), 0.035, 0.025, b.darkened(0.3), 6)
	add_child(LandmarkKit.mesh_node(st, LandmarkKit.material(0.42, 0.65), "WarriorBronze", REACH))
