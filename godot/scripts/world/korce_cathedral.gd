class_name KorceCathedral
extends Node3D
## Katedralja Ngjallja e Krishtit, the Orthodox Cathedral of the Resurrection
## in Korçë (1992-1995): an original interpretation after photographs, at its
## OSM outline (way 1165161082), facing its square and Bulevardi Republika.
##
##   podium   a stone platform with a broad flight of steps to the square,
##            cheek walls and two steel handrails;
##   rotunda  the round church, coursed cream ashlar between banded piers,
##            three iron-grilled arched doors in the curved portico between
##            the towers, tall arched windows round the sides, a white frieze
##            and cornice, and a conical clay-tile roof;
##   domes    a broad front dome on a drum of sixteen arched windows (red and
##            white voussoirs), the higher main dome behind it on a tall drum,
##            two small side domes and the apse with its half-cone roof;
##   towers   twin bell towers at the front corners: a tall stone base, three
##            set-back stages with white cornices, quoin pilasters and paired
##            arched windows, an open round belfry of eight columns, a white
##            cupola and a cross;
##   square   the paved square in front, in bands of buff and rose stone.
##
## Materials (Poly Haven CC0): sandstone_blocks_05 ashlar for the walls,
## white_stucco for trim, clay_roof_tiles_02 for every roof and dome, the
## precast paving for the square; window glass, iron and crosses are vertex
## colour. Ashlar, trim, tiles, glass and crosses are drawn to 2.8 km; the
## carved trim (window and door surrounds, dentils) and the ironwork only
## within 650 m, where they read. Local frame: the facade faces -Z, x across it.

const REACH := 2800.0
## Carved trim and ironwork: seen near only (a phone's draw budget).
const NEAR := 650.0

## Rotunda radius and levels (metres above the ground at the anchor).
const R := 14.0
const PODIUM := 2.4
const EAVE := PODIUM + 8.2
const FRIEZE := EAVE - 1.1
## Bell towers at the front corners of the round church.
const TOWER_X := 11.8
const TOWER_Z := -8.0
## The front dome over the nave, and the main dome behind it.
const FRONT := Vector3(0.0, 0.0, -3.0)
const MAIN := Vector3(0.0, 0.0, 7.0)

const STONE := Color("#fffaf2")
const STONE_WARM := Color("#fbefe0")
const STONE_DARK := Color("#e6d8c6")
const WHITE := Color("#f6f2ea")
const CREAM := Color("#ece2cf")
const BRICK := Color("#b25a3c")
const STEP := Color("#ddd5c8")
const GLASS := Color("#2b3a45")
const IRON := Color("#1e2124")
const STEEL := Color("#b9bec2")
const CROSS := Color("#f3efe4")
const TILE := Color("#ffffff")
const TILE_RIM := Color("#e7dccb")

var _terrain: Terrain
var _stone: SurfaceTool
var _trim: SurfaceTool
var _roof: SurfaceTool
var _detail: SurfaceTool
var _fine: SurfaceTool
var _cross: SurfaceTool
var _glass: SurfaceTool
var _paving: SurfaceTool
## Counts for tests and the README: openings and bell-tower stages built.
var doors := 0
var windows := 0
var domes := 0
var tower_tops: Array[Vector3] = []


func build(terrain: Terrain) -> void:
	_terrain = terrain
	_stone = ArchKit.begin()
	_trim = ArchKit.begin()
	_roof = ArchKit.begin()
	_detail = ArchKit.begin()
	_fine = ArchKit.begin()
	_cross = ArchKit.begin()
	_glass = ArchKit.begin()
	_paving = ArchKit.begin()
	_podium()
	_stairs()
	_rotunda()
	_portico()
	_drums_and_domes()
	_apse()
	for side: float in [-1.0, 1.0]:
		_tower(side)
	_square()
	var stone := ArchKit.material(preload("res://assets/textures/ashlar_buff_diff.jpg"),
		preload("res://assets/textures/ashlar_buff_nor.jpg"), preload("res://assets/textures/ashlar_buff_arm.jpg"),
		2.6, Color(1.32, 1.27, 1.2))
	var trim := ArchKit.material(preload("res://assets/textures/stucco_diff.jpg"),
		preload("res://assets/textures/stucco_nor.jpg"), preload("res://assets/textures/stucco_arm.jpg"), 2.0,
		Color(1.04, 1.03, 1.0), 0.5)
	var roof := ArchKit.material(preload("res://assets/textures/clay_roof_diff.jpg"),
		preload("res://assets/textures/clay_roof_nor.jpg"), preload("res://assets/textures/clay_roof_arm.jpg"),
		3.2, Color(1.0, 0.9, 0.86))
	var paving := ArchKit.material(preload("res://assets/textures/promenade_paving_diff.jpg"),
		preload("res://assets/textures/promenade_paving_nor.jpg"), preload("res://assets/textures/promenade_paving_arm.jpg"), 3.0)
	var detail := LandmarkKit.material(0.5, 0.35)
	var glass := LandmarkKit.material(0.14, 0.4)
	add_child(ArchKit.node(_stone, stone, "CathedralAshlar", REACH))
	add_child(ArchKit.node(_trim, trim, "CathedralTrim", REACH))
	add_child(ArchKit.node(_roof, roof, "CathedralTiles", REACH))
	add_child(ArchKit.node(_glass, glass, "CathedralGlass", REACH))
	add_child(ArchKit.node(_cross, LandmarkKit.material(0.45, 0.2), "CathedralCrosses", REACH))
	# Window and door surrounds, dentils, grilles and rails: seen near only.
	var fine := ArchKit.node(_fine, trim, "CathedralCarvedTrim", NEAR)
	fine.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fine)
	var iron := ArchKit.node(_detail, detail, "CathedralIronwork", NEAR)
	iron.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(iron)
	var square := ArchKit.node(_paving, paving, "CathedralSquare", 900.0)
	square.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(square)


# ------------------------------------------------------------------ ground

## Local height of the ground under local (x, z); 0 without terrain.
func _ground(x: float, z: float) -> float:
	var parent := get_parent() as Node3D
	if _terrain == null or parent == null:
		return 0.0
	var world := parent.transform * Vector3(x, 0.0, z)
	return _terrain.height_at(world.x, world.z) - parent.position.y


func _low(points: Array[Vector2]) -> float:
	var low := INF
	for p in points:
		low = minf(low, _ground(p.x, p.y))
	return low


## Unit vector at azimuth a (0 = -Z, the facade; increasing toward +X).
func _dir(a: float) -> Vector3:
	return Vector3(sin(a), 0.0, -cos(a))


# ------------------------------------------------------------------ podium and steps

func _podium() -> void:
	var foot := _low([Vector2(0, -R - 3), Vector2(R + 1, 0), Vector2(-R - 1, 0), Vector2(0, R + 6)]) - 1.0
	# Round platform under the church, its face in ashlar, a light coping.
	ArchKit.ring_wall(_stone, Vector3.ZERO, R + 1.2, foot, PODIUM - 0.18, STONE_DARK, 64)
	ArchKit.ring_wall(_trim, Vector3.ZERO, R + 1.32, PODIUM - 0.18, PODIUM, CREAM, 64)
	ArchKit.disc(_trim, Vector3.ZERO, R + 1.32, PODIUM, STEP, 64, R - 0.2)
	# Front landing between the towers, out to the head of the steps.
	var landing := Vector3(0.0, 0.0, -R - 1.6)
	ArchKit.box(_stone, landing + Vector3(0, (foot + PODIUM - 0.18) * 0.5, 0), Vector3(19.6, PODIUM - 0.18 - foot, 4.4), STONE_DARK)
	ArchKit.box(_trim, landing + Vector3(0, PODIUM - 0.09, 0), Vector3(19.8, 0.18, 4.6), STEP)


func _stairs() -> void:
	var top_z := -R - 3.8
	var foot_y := _ground(0.0, top_z - 6.0)
	var rise := PODIUM - foot_y
	var count := maxi(6, roundi(rise / 0.16))
	var h := rise / count
	var tread := 0.42
	var half := 8.2
	for i in count:
		var y_top := PODIUM - h * i
		var z := top_z - tread * (i + 0.5)
		# Each step a block down to the one below: tread on top, riser in front.
		ArchKit.box(_trim, Vector3(0, y_top - h * 0.5 - 0.3, z), Vector3(half * 2.0, h + 0.6, tread), STEP.darkened(0.04 * (i % 2)))
	var bottom_z := top_z - tread * count
	# Cheek walls stepping down beside the flight, ashlar with a brick coping.
	for side: float in [-1.0, 1.0]:
		var x: float = side * (half + 0.45)
		var a := Vector3(x, PODIUM + 0.55, top_z)
		var b := Vector3(x, foot_y + 0.75, bottom_z)
		var segs := 8
		for k in segs:
			var t0 := float(k) / segs
			var t1 := float(k + 1) / segs
			var p0 := a.lerp(b, t0)
			var p1 := a.lerp(b, t1)
			var low := minf(_ground(x, p1.z), foot_y) - 0.8
			var mid_z := (p0.z + p1.z) * 0.5
			var top := (p0.y + p1.y) * 0.5
			ArchKit.box(_stone, Vector3(x, (low + top) * 0.5, mid_z), Vector3(0.9, top - low, absf(p1.z - p0.z) + 0.02), STONE_DARK)
			ArchKit.box(_trim, Vector3(x, top + 0.07, mid_z), Vector3(1.04, 0.14, absf(p1.z - p0.z) + 0.03), BRICK)
		# Steel handrails dividing the flight into three.
		var rx: float = side * 2.9
		var r0 := Vector3(rx, PODIUM + 0.95, top_z + 0.2)
		var r1 := Vector3(rx, foot_y + 0.95, bottom_z + 0.3)
		var along := (r1 - r0).normalized()
		var rail := Basis(Vector3.RIGHT, along, Vector3.RIGHT.cross(along).normalized())
		ArchKit.box(_detail, (r0 + r1) * 0.5, Vector3(0.06, r0.distance_to(r1), 0.06), STEEL, rail)
		for k in 6:
			var p := r0.lerp(r1, k / 5.0)
			ArchKit.box(_detail, p - Vector3(0, 0.47, 0), Vector3(0.05, 0.95, 0.05), STEEL)


# ------------------------------------------------------------------ the round church

## Azimuths of the piers round the rotunda, outside the portico.
func _pier_azimuths() -> Array[float]:
	var out: Array[float] = []
	for deg: float in [70.0, 88.0, 106.0, 124.0, 142.0, 160.0]:
		out.append(deg_to_rad(deg))
		out.append(deg_to_rad(-deg))
	return out


func _rotunda() -> void:
	# Ashlar drum of the church with a projecting base course.
	ArchKit.ring_wall(_stone, Vector3.ZERO, R, PODIUM - 0.2, FRIEZE, STONE, 96)
	ArchKit.ring_wall(_stone, Vector3.ZERO, R + 0.16, PODIUM - 0.05, PODIUM + 0.55, STONE_DARK, 96)
	ArchKit.frustum(_trim, Vector3.ZERO, R + 0.16, PODIUM + 0.55, R, PODIUM + 0.7, CREAM, 96)
	# White frieze, a dentil course and the cornice with its soffit.
	ArchKit.ring_wall(_trim, Vector3.ZERO, R + 0.04, FRIEZE, EAVE, WHITE, 96)
	ArchKit.ring_wall(_trim, Vector3.ZERO, R + 0.12, FRIEZE - 0.05, FRIEZE + 0.12, CREAM, 96)
	for k in 220:
		var a := TAU * k / 220.0
		var d := _dir(a)
		ArchKit.box(_fine, d * (R + 0.2) + Vector3.UP * (EAVE - 0.12), Vector3(0.18, 0.2, 0.3), WHITE, Basis(Vector3.UP, -a))
	ArchKit.disc(_trim, Vector3.ZERO, R + 0.95, EAVE, CREAM, 96, R, true)
	ArchKit.ring_wall(_trim, Vector3.ZERO, R + 0.95, EAVE, EAVE + 0.28, WHITE, 96)
	# The conical tile roof up to the drums, a clay rim at the eaves.
	ArchKit.frustum(_roof, Vector3.ZERO, R + 1.05, EAVE + 0.28, 8.4, EAVE + 3.4, TILE, 96)
	ArchKit.ring_wall(_roof, Vector3.ZERO, R + 1.05, EAVE + 0.16, EAVE + 0.3, TILE_RIM, 96)
	ArchKit.disc(_roof, Vector3.ZERO, 8.4, EAVE + 3.4, TILE, 48)
	# Piers, and between them tall arched windows with red and white arches.
	for a in _pier_azimuths():
		_pier(a, PODIUM + 0.55, FRIEZE - 0.05, 1.1, 0.32)
	for deg: float in [79.0, 97.0, 115.0, 133.0, 151.0]:
		for side: float in [-1.0, 1.0]:
			_rotunda_window(deg_to_rad(deg) * side, PODIUM + 2.1, 1.25, 2.6)
	# Two brick chimneys on the front slope, as on the building.
	for side: float in [-1.0, 1.0]:
		var d := _dir(deg_to_rad(34.0) * side)
		var p := d * (R - 1.6)
		var roof_y := EAVE + 0.28 + (R + 1.05 - (R - 1.6)) / (R + 1.05 - 8.4) * 3.12
		ArchKit.box(_trim, p + Vector3.UP * (roof_y + 0.55), Vector3(0.62, 1.5, 0.62), BRICK, Basis(Vector3.UP, -deg_to_rad(34.0) * side))
		ArchKit.box(_trim, p + Vector3.UP * (roof_y + 1.35), Vector3(0.8, 0.12, 0.8), CREAM, Basis(Vector3.UP, -deg_to_rad(34.0) * side))


## A banded pier on the rotunda: ashlar shaft with a white capital.
func _pier(a: float, y0: float, y1: float, w: float, depth: float) -> void:
	var d := _dir(a)
	var b := Basis(Vector3.UP, -a)
	var c := d * (R + depth * 0.5 - 0.02)
	ArchKit.box(_stone, c + Vector3.UP * (y0 + y1) * 0.5, Vector3(w, y1 - y0, depth), STONE_WARM, b)
	ArchKit.box(_trim, c + d * 0.04 + Vector3.UP * (y1 - 0.18), Vector3(w + 0.16, 0.36, depth + 0.1), WHITE, b)
	ArchKit.box(_stone, c + d * 0.02 + Vector3.UP * (y0 + 0.3), Vector3(w + 0.12, 0.6, depth + 0.06), STONE_DARK, b)


## A tall window on the rotunda at azimuth a: dark glass, a white stone
## surround, an arch of alternating red brick and white stone, a sill.
func _rotunda_window(a: float, sill: float, w: float, rise: float) -> void:
	var d := _dir(a)
	var right := Vector3.UP.cross(d).normalized() * -1.0
	var foot := d * (R + 0.02) + Vector3.UP * sill
	_window(foot, right, d, w, rise)


## A window opening on a face: `foot` the centre of its sill on the face.
func _window(foot: Vector3, right: Vector3, out: Vector3, w: float, rise: float, arch_a := BRICK, arch_b := WHITE, frame := WHITE) -> void:
	var r := w * 0.5
	# Surround: jambs and sill in white stone.
	ArchKit.box(_fine, foot + out * 0.06 + right * (r + 0.11) + Vector3.UP * rise * 0.5, Vector3(0.22, rise, 0.12), frame, Basis(right, Vector3.UP, out))
	ArchKit.box(_fine, foot + out * 0.06 - right * (r + 0.11) + Vector3.UP * rise * 0.5, Vector3(0.22, rise, 0.12), frame, Basis(right, Vector3.UP, out))
	ArchKit.box(_fine, foot + out * 0.1 - Vector3.UP * 0.07, Vector3(w + 0.6, 0.14, 0.22), frame, Basis(right, Vector3.UP, out))
	ArchKit.voussoirs(_fine, foot + Vector3.UP * rise + out * 0.01, right, out, r, 0.24, 0.12, arch_a, arch_b, 9)
	# Recessed glass with a mullion and a transom.
	ArchKit.arch_panel(_glass, foot, right, out, w, rise, GLASS, 0.03, 10)
	ArchKit.box(_detail, foot + out * 0.07 + Vector3.UP * (rise + r * 0.5) * 0.5, Vector3(0.05, rise + r * 0.5, 0.04), WHITE.darkened(0.1), Basis(right, Vector3.UP, out))
	ArchKit.box(_detail, foot + out * 0.07 + Vector3.UP * rise, Vector3(w, 0.05, 0.04), WHITE.darkened(0.1), Basis(right, Vector3.UP, out))
	windows += 1


# ------------------------------------------------------------------ portico and doors

func _portico() -> void:
	# The curved front between the towers: four banded piers, three doors.
	for deg: float in [-31.5, -10.8, 10.8, 31.5]:
		_pier(deg_to_rad(deg), PODIUM, FRIEZE - 0.05, 1.35, 0.5)
	for deg: float in [-21.2, 0.0, 21.2]:
		_door(deg_to_rad(deg))
	# A cross in relief over the middle door, in the frieze.
	ArchKit.cross(_cross, _dir(0.0) * (R + 0.08) + Vector3.UP * (FRIEZE + 0.12), 0.85, _dir(0.0), Color("#c9a85a"))


## An arched doorway: a stone arch of voussoirs, a recessed iron-grilled
## glass door in two leaves under a fanlight, and a stone threshold.
func _door(a: float) -> void:
	var d := _dir(a)
	var right := Vector3.UP.cross(d).normalized() * -1.0
	var w := 2.6
	var r := w * 0.5
	var rise := 3.6
	var foot := d * (R + 0.02) + Vector3.UP * PODIUM
	var b := Basis(right, Vector3.UP, d)
	# Reveal: the opening's depth in shadow, then the door set back in it.
	ArchKit.arch_panel(_glass, foot, right, d, w + 0.24, rise, Color("#1a1d20"), 0.02, 12)
	ArchKit.voussoirs(_fine, foot + Vector3.UP * rise + d * 0.02, right, d, r + 0.12, 0.42, 0.18, CREAM, Color("#f9f4ea"), 11)
	for side: float in [-1.0, 1.0]:
		ArchKit.box(_fine, foot + right * side * (r + 0.33) + d * 0.09 + Vector3.UP * rise * 0.5, Vector3(0.42, rise, 0.18), CREAM, b)
	ArchKit.box(_fine, foot + d * 0.35 - Vector3.UP * 0.05, Vector3(w + 0.9, 0.12, 0.8), STEP, b)
	# Iron grille over the glass: a frame, uprights, rails and a ring motif.
	var g := foot + d * 0.05
	for i in 9:
		var x := -r + 0.18 + i * (w - 0.36) / 8.0
		ArchKit.box(_detail, g + right * x + Vector3.UP * rise * 0.5, Vector3(0.045, rise, 0.05), IRON, b)
	for y: float in [0.15, 0.95, 1.85, 2.75, rise - 0.05]:
		ArchKit.box(_detail, g + Vector3.UP * y, Vector3(w, 0.07, 0.06), IRON, b)
	ArchKit.box(_detail, g + Vector3.UP * rise * 0.5, Vector3(0.1, rise, 0.07), IRON, b)
	for side: float in [-1.0, 1.0]:
		var c := g + right * side * r * 0.5 + Vector3.UP * 2.3
		for k in 10:
			var t0 := TAU * k / 10.0
			var t1 := TAU * (k + 1) / 10.0
			var p0 := c + (right * cos(t0) + Vector3.UP * sin(t0)) * 0.42
			var p1 := c + (right * cos(t1) + Vector3.UP * sin(t1)) * 0.42
			var mid := (p0 + p1) * 0.5
			var seg := (p1 - p0)
			ArchKit.box(_detail, mid + d * 0.01, Vector3(seg.length() + 0.02, 0.05, 0.05), IRON,
				Basis(seg.normalized(), d.cross(seg.normalized()), d))
	# Fanlight spokes in the arch.
	for k in 7:
		var t := PI * (k + 0.5) / 7.0
		var radial := right * cos(t) + Vector3.UP * sin(t)
		ArchKit.box(_detail, g + Vector3.UP * rise + radial * r * 0.5, Vector3(0.04, r, 0.05), IRON, Basis(d.cross(radial), radial, d))
	doors += 1


# ------------------------------------------------------------------ drums and domes

func _drums_and_domes() -> void:
	# Front dome: a drum of sixteen arched windows, a cornice, a tiled dome.
	_drum(FRONT, 7.2, EAVE + 1.6, EAVE + 6.0, 16, 0.95, 2.0)
	_dome_on(FRONT, 7.4, 5.2, EAVE + 6.0, 1.6)
	# The main dome stands higher behind it on a tall drum.
	_drum(MAIN, 5.3, EAVE + 1.2, EAVE + 12.8, 12, 0.85, 2.6)
	_dome_on(MAIN, 5.75, 4.6, EAVE + 12.8, 1.9)
	# Two small side domes over the transepts.
	for side: float in [-1.0, 1.0]:
		var c := Vector3(side * 9.6, 0.0, 3.4)
		_drum(c, 2.7, EAVE + 0.6, EAVE + 3.4, 6, 0.6, 1.2)
		_dome_on(c, 3.0, 2.2, EAVE + 3.4, 0.9)


## A round drum at `c` from y0 to y1 with `count` arched windows near the top,
## thin piers between them, a red brick string course and a white cornice.
func _drum(c: Vector3, r: float, y0: float, y1: float, count: int, w: float, rise: float) -> void:
	ArchKit.ring_wall(_stone, c, r, y0, y1 - 0.3, STONE, 64)
	ArchKit.ring_wall(_trim, c, r + 0.05, y0 + 0.4, y0 + 0.6, BRICK, 64)
	var sill := y1 - 0.75 - rise - w * 0.5
	for k in count:
		var a := TAU * (k + 0.5) / count
		var d := _dir(a)
		var right := Vector3.UP.cross(d).normalized() * -1.0
		_window(c + d * (r + 0.02) + Vector3.UP * sill, right, d, w, rise)
		var pa := TAU * k / count
		var pd := _dir(pa)
		ArchKit.box(_stone, c + pd * (r + 0.1) + Vector3.UP * (y0 + y1 - 0.3) * 0.5, Vector3(0.5, y1 - 0.3 - y0, 0.24), STONE_WARM, Basis(Vector3.UP, -pa))
	ArchKit.ring_wall(_trim, c, r + 0.04, y1 - 0.62, y1 - 0.3, WHITE, 64)
	ArchKit.frustum(_trim, c, r + 0.04, y1 - 0.3, r + 0.42, y1 - 0.12, CREAM, 64)
	ArchKit.ring_wall(_trim, c, r + 0.42, y1 - 0.12, y1, WHITE, 64)


## A tiled dome of base radius r and height h on a drum top at y, with a clay
## rim, a small lantern knob and a white cross of height `cross_h`.
func _dome_on(c: Vector3, r: float, h: float, y: float, cross_h: float) -> void:
	ArchKit.ring_wall(_roof, c, r, y - 0.02, y + 0.16, TILE_RIM, 48)
	ArchKit.dome(_roof, c + Vector3.UP * 0.0, r, h, y + 0.14, TILE, 40, 12, 0.08)
	var top := c + Vector3.UP * (y + 0.14 + h)
	ArchKit.ring_wall(_trim, c, r * 0.11, y + 0.14 + h - 0.2, y + 0.14 + h + 0.2, WHITE, 12)
	ArchKit.disc(_trim, c, r * 0.11, y + 0.34 + h, WHITE, 12)
	ArchKit.cross(_cross, top + Vector3.UP * 0.2, cross_h, Vector3.FORWARD, CROSS)
	domes += 1


# ------------------------------------------------------------------ apse

func _apse() -> void:
	var c := Vector3(0.0, 0.0, 12.6)
	var a0 := deg_to_rad(90.0)
	var a1 := deg_to_rad(270.0)
	var top := PODIUM + 6.8
	var foot := _low([Vector2(0, 17.6), Vector2(4.8, 12.6), Vector2(-4.8, 12.6)]) - 1.0
	ArchKit.ring_wall(_stone, c, 5.1, foot, PODIUM, STONE_DARK, 32, a0, a1)
	ArchKit.disc(_trim, c, 5.1, PODIUM, STEP, 32, 4.7)
	ArchKit.ring_wall(_stone, c, 4.8, PODIUM - 0.2, top - 0.9, STONE, 32, a0, a1)
	ArchKit.ring_wall(_trim, c, 4.84, top - 0.9, top, WHITE, 32, a0, a1)
	ArchKit.frustum(_roof, c, 5.5, top + 0.1, 0.4, top + 2.6, TILE, 32, a0, a1)
	ArchKit.ring_wall(_trim, c, 5.5, top - 0.05, top + 0.12, CREAM, 32, a0, a1)
	for deg: float in [140.0, 180.0, 220.0]:
		var a := deg_to_rad(deg)
		var d := _dir(a)
		var right := Vector3.UP.cross(d).normalized() * -1.0
		_window(c + d * 4.82 + Vector3.UP * (PODIUM + 1.8), right, d, 1.0, 2.2)


# ------------------------------------------------------------------ bell towers

func _tower(side: float) -> void:
	var c := Vector3(side * TOWER_X, 0.0, TOWER_Z)
	var low := _low([Vector2(c.x - 3.2, c.z - 3.2), Vector2(c.x + 3.2, c.z - 3.2), Vector2(c.x - 3.2, c.z + 3.2), Vector2(c.x + 3.2, c.z + 3.2)]) - 1.0
	# Stage heights (bottom, top) and widths, set back stage by stage.
	var stages := [[low, 13.2, 6.4], [13.7, 18.7, 5.4], [19.15, 23.6, 5.0], [24.05, 27.6, 4.5]]
	for i in stages.size():
		var y0: float = stages[i][0]
		var y1: float = stages[i][1]
		var w: float = stages[i][2]
		ArchKit.box(_stone, c + Vector3.UP * (y0 + y1) * 0.5, Vector3(w, y1 - y0, w), STONE if i == 0 else STONE_WARM)
		# A white cornice and a thin course under it.
		ArchKit.box(_trim, c + Vector3.UP * (y1 + 0.24), Vector3(w + 0.62, 0.48, w + 0.62), WHITE)
		ArchKit.box(_trim, c + Vector3.UP * (y1 - 0.12), Vector3(w + 0.16, 0.2, w + 0.16), CREAM)
		if i > 0:
			# White quoin pilasters at the corners of the upper stages.
			for cx: float in [-1.0, 1.0]:
				for cz: float in [-1.0, 1.0]:
					ArchKit.box(_trim, c + Vector3(cx * (w * 0.5 - 0.2), (y0 + y1) * 0.5 - 0.1, cz * (w * 0.5 - 0.2)), Vector3(0.52, y1 - y0 - 0.2, 0.52), WHITE)
		else:
			ArchKit.box(_stone, c + Vector3.UP * (PODIUM * 0.5 + low * 0.5), Vector3(w + 0.24, PODIUM - low, w + 0.24), STONE_DARK)
		for face in 4:
			var b := Basis(Vector3.UP, face * PI * 0.5)
			var out := b * Vector3.FORWARD
			var right := b * Vector3.RIGHT
			# The face against the church (toward the axis, or behind) gets fewer openings.
			var inner := out.dot(Vector3(-side, 0, 0)) > 0.5 or out.dot(Vector3.BACK) > 0.5
			var face_c := c + out * (w * 0.5 + 0.01)
			match i:
				0:
					if not inner:
						_window(face_c + Vector3.UP * 7.0, right, out, 1.5, 2.9)
						_window(face_c + Vector3.UP * 3.4, right, out, 0.9, 1.3)
				1:
					for x: float in [-0.62, 0.62]:
						_window(face_c + right * x + Vector3.UP * 14.9, right, out, 0.82, 2.0, WHITE, CREAM)
				2:
					for x: float in [-0.56, 0.56]:
						_window(face_c + right * x + Vector3.UP * 20.3, right, out, 0.74, 1.8, WHITE, CREAM)
				3:
					_window(face_c + Vector3.UP * 25.0, right, out, 1.0, 1.7, WHITE, CREAM)
	# The open round belfry: a plinth disc, eight columns round a dark core, an
	# entablature ring, a white cupola, knob and cross.
	var base := 28.08
	ArchKit.ring_wall(_trim, c, 2.1, base, base + 0.3, WHITE, 24)
	ArchKit.disc(_trim, c, 2.1, base + 0.3, CREAM, 24)
	ArchKit.ring_wall(_glass, c, 1.15, base + 0.3, base + 2.7, Color("#26221f"), 16)
	for k in 8:
		var d := _dir(TAU * k / 8.0)
		ArchKit.ring_wall(_trim, c + d * 1.72, 0.17, base + 0.3, base + 2.7, WHITE, 8)
		ArchKit.box(_trim, c + d * 1.72 + Vector3.UP * (base + 2.62), Vector3(0.46, 0.18, 0.46), WHITE)
	ArchKit.ring_wall(_trim, c, 2.2, base + 2.7, base + 3.1, WHITE, 24)
	ArchKit.disc(_trim, c, 2.2, base + 2.7, CREAM, 24, 0.0, true)
	ArchKit.frustum(_trim, c, 2.2, base + 3.1, 2.0, base + 3.2, CREAM, 24)
	ArchKit.dome(_trim, c, 2.0, 1.45, base + 3.2, WHITE, 24, 8, 0.12)
	ArchKit.ring_wall(_trim, c, 0.26, base + 4.55, base + 4.9, WHITE, 10)
	ArchKit.cross(_cross, c + Vector3.UP * (base + 4.9), 1.55, Vector3.FORWARD, CROSS)
	tower_tops.append(c + Vector3.UP * (base + 6.45))


# ------------------------------------------------------------------ square

## The paved square from the foot of the steps toward the boulevard: square
## tiles of the precast paving laid on the ground, in buff and rose bands.
func _square() -> void:
	var size := 2.0
	for zi in range(0, 12):
		for xi in range(-11, 11):
			var x0 := xi * size
			var z0 := -R - 6.6 - (zi + 1) * size
			if z0 + size > -R - 6.6 + 0.01:
				continue
			var band := Color("#e9dccb") if int(zi / 2.0) % 2 == 0 else Color("#d9b8a6")
			var pts: Array[Vector3] = []
			for p: Vector2 in [Vector2(x0, z0), Vector2(x0 + size, z0), Vector2(x0 + size, z0 + size), Vector2(x0, z0 + size)]:
				pts.append(Vector3(p.x, _ground(p.x, p.y) + 0.06, p.y))
			ArchKit.quad_uv(_paving, pts[0], pts[1], pts[2], pts[3], Vector2(pts[0].x, pts[0].z), Vector2(pts[1].x, pts[1].z),
				Vector2(pts[2].x, pts[2].z), Vector2(pts[3].x, pts[3].z), band, Vector3.UP)
