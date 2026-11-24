class_name VloreResort
extends Node3D
## The shore road before the Uji i Ftohtë tunnel, after photographs from the
## bay (props.json "resort", tools/pipeline/vlore_resort.py): modern white
## hotels stepped up the hillside on the land side, and on the sea side a
## beach club, a long infinity pool on a stone deck lined with white
## loungers and parasols, cabanas along the road, palms, and steps down to
## the rocks. Unbranded. Each model's front is local -Z, toward the road.

const WHITE := Color("#eeece6")
const WHITE_SHADE := Color("#d9d6ce")
const GLASS := Color("#30434f")
const GLASS_LIGHT := Color("#5f7a88")
const RAIL := Color("#8fa3ab")
const STONE := Color("#e2dccd")
const TILE := Color("#d4ccb8")
const WATER := Color("#36b7c9")
const CANVAS := Color("#f4f2ea")
const TEAK := Color("#9a7655")
const FLOOR_H := 3.2

## The beach club's deck centre (world), for the rock armour in front of it.
var club_anchor := {}


func build(data: Dictionary, terrain: Terrain = null) -> void:
	var walls := LandmarkKit.begin()
	var glass := LandmarkKit.begin()
	for h: Array in data.get("hotels", []):
		var basis := Basis(Vector3.UP, deg_to_rad(float(h[3])))
		var origin := Vector3(float(h[0]), float(h[1]), float(h[2]))
		match int(h[7]):
			1:
				_tower(walls, glass, origin, basis, float(h[4]), float(h[5]), int(h[6]))
			2:
				_slab(walls, glass, origin, basis, float(h[4]), float(h[5]), int(h[6]))
			_:
				_terraced(walls, glass, origin, basis, float(h[4]), float(h[5]), int(h[6]))
	var wall_node := LandmarkKit.mesh_node(walls, LandmarkKit.material(0.78), "HotelWalls", 1700.0)
	add_child(wall_node)
	var glazing := LandmarkKit.material(0.12, 0.35)
	var glass_node := LandmarkKit.mesh_node(glass, glazing, "HotelGlazing", 1500.0)
	glass_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glass_node)
	var club: Dictionary = data.get("club", {})
	if not club.is_empty():
		_club(club, terrain)


## Foundations run down into the slope so no hotel floats over the hill.
func _footing(st: SurfaceTool, origin: Vector3, basis: Basis, width: float, depth: float) -> void:
	LandmarkKit.box(st, origin + basis * Vector3(0, -4.0, 0), Vector3(width, 8.2, depth), WHITE_SHADE.darkened(0.12), basis)


## White blocks whose upper floors step back into terraces, each floor a
## band of dark glass behind a white slab edge and a glass balustrade, with
## white fins between bays (the stepped blocks left of the photograph).
func _terraced(st: SurfaceTool, glass: SurfaceTool, origin: Vector3, basis: Basis, width: float, depth: float, floors: int) -> void:
	_footing(st, origin, basis, width, depth)
	var bays := maxi(3, int(width / 4.2))
	var built := 0
	for f in floors:
		var recess := 2.4 * floori(f / 2.0)
		var d := depth - recess
		if d < 7.0:
			break
		built = f + 1
		var y := f * FLOOR_H
		var front := -depth * 0.5 + recess
		var centre_z := front + d * 0.5
		# Floor slab and a solid back half behind the glazing.
		LandmarkKit.box(st, origin + basis * Vector3(0, y + 0.15, centre_z), Vector3(width, 0.3, d), WHITE, basis)
		LandmarkKit.box(st, origin + basis * Vector3(0, y + FLOOR_H * 0.5, centre_z + 1.2), Vector3(width - 0.4, FLOOR_H, d - 2.4), WHITE_SHADE, basis)
		# Glazed front, set back behind the balconies.
		var gz := front + 1.3
		_pane(glass, origin, basis, Vector3(-width * 0.5 + 0.3, y + 0.3, gz), Vector3(width * 0.5 - 0.3, y + FLOOR_H - 0.1, gz), GLASS if f % 2 == 0 else GLASS_LIGHT.darkened(0.25))
		# Balcony edge and its glass rail.
		LandmarkKit.box(st, origin + basis * Vector3(0, y + 0.42, front + 0.12), Vector3(width, 0.26, 0.24), WHITE, basis)
		_pane(glass, origin, basis, Vector3(-width * 0.5 + 0.2, y + 0.55, front + 0.05), Vector3(width * 0.5 - 0.2, y + 1.55, front + 0.05), RAIL)
		for b in bays + 1:
			var x := -width * 0.5 + width * b / bays
			LandmarkKit.box(st, origin + basis * Vector3(x, y + FLOOR_H * 0.5, front + 0.65), Vector3(0.36, FLOOR_H, 1.3), WHITE, basis)
	# Roof edge, on the last floor that fits the stepped section.
	var top := built * FLOOR_H
	var last := 2.4 * floori((built - 1) / 2.0)
	LandmarkKit.box(st, origin + basis * Vector3(0, top + 0.35, (last) * 0.5), Vector3(width, 0.7, depth - last), WHITE, basis)


## The tall glass-fronted hotel in the middle: a curtain wall between white
## bands, a glazed lift shaft rising beside it.
func _tower(st: SurfaceTool, glass: SurfaceTool, origin: Vector3, basis: Basis, width: float, depth: float, floors: int) -> void:
	_footing(st, origin, basis, width, depth)
	var h := floors * FLOOR_H
	var front := -depth * 0.5
	LandmarkKit.box(st, origin + basis * Vector3(0, h * 0.5, 0.6), Vector3(width, h, depth - 1.2), WHITE_SHADE, basis)
	_pane(glass, origin, basis, Vector3(-width * 0.5, 0.2, front + 1.15), Vector3(width * 0.5, h, front + 1.15), GLASS)
	for f in floors + 1:
		var y := f * FLOOR_H
		LandmarkKit.box(st, origin + basis * Vector3(0, y, front + 0.9), Vector3(width + 0.4, 0.34, 1.0), WHITE, basis)
		if f > 0 and f < floors:
			_pane(glass, origin, basis, Vector3(-width * 0.5, y + 0.2, front + 0.42), Vector3(width * 0.5, y + 1.15, front + 0.42), RAIL)
	for x: float in [-width * 0.5, width * 0.5]:
		LandmarkKit.box(st, origin + basis * Vector3(x, h * 0.5, front + 0.9), Vector3(0.9, h + 0.4, 1.2), WHITE, basis)
	# Lift shaft on the end, a storey above the roof.
	var shaft := Vector3(width * 0.5 + 2.2, 0, front + 3.0)
	_pane(glass, origin, basis, shaft + Vector3(-1.8, 0.2, -1.8), shaft + Vector3(1.8, h + FLOOR_H, -1.8), GLASS_LIGHT)
	LandmarkKit.box(st, origin + basis * (shaft + Vector3(0, (h + FLOOR_H) * 0.5, 0.4)), Vector3(3.6, h + FLOOR_H, 3.6), WHITE_SHADE, basis)
	LandmarkKit.box(st, origin + basis * Vector3(0, h + 0.6, 0.4), Vector3(width + 0.6, 1.2, depth - 0.4), WHITE, basis)


## A cream slab with continuous balconies on every floor, an arcaded ground
## floor (the hotel right of the photograph).
func _slab(st: SurfaceTool, glass: SurfaceTool, origin: Vector3, basis: Basis, width: float, depth: float, floors: int) -> void:
	_footing(st, origin, basis, width, depth)
	var h := floors * FLOOR_H
	var front := -depth * 0.5
	var cream := Color("#ece3cf")
	LandmarkKit.box(st, origin + basis * Vector3(0, h * 0.5, 0.8), Vector3(width, h, depth - 1.6), cream, basis)
	var bays := maxi(4, int(width / 3.6))
	for f in floors:
		var y := f * FLOOR_H
		for b in bays:
			var x := -width * 0.5 + width * (b + 0.5) / bays
			_pane(glass, origin, basis, Vector3(x - width / bays * 0.36, y + 0.35, front + 1.55), Vector3(x + width / bays * 0.36, y + FLOOR_H - 0.45, front + 1.55), GLASS if f > 0 else GLASS_LIGHT)
		if f > 0:
			LandmarkKit.box(st, origin + basis * Vector3(0, y + 0.12, front + 0.8), Vector3(width, 0.24, 1.6), cream.lightened(0.2), basis)
			_pane(glass, origin, basis, Vector3(-width * 0.5, y + 0.3, front + 0.04), Vector3(width * 0.5, y + 1.3, front + 0.04), RAIL)
		for b in bays + 1:
			var x := -width * 0.5 + width * b / bays
			LandmarkKit.box(st, origin + basis * Vector3(x, y + FLOOR_H * 0.5, front + 1.2), Vector3(0.3, FLOOR_H, 0.7), cream, basis)
	LandmarkKit.box(st, origin + basis * Vector3(0, h + 0.4, 0.8), Vector3(width + 0.4, 0.8, depth - 1.2), cream.lightened(0.1), basis)


## A flat pane between two local corners (constant z), facing -Z.
func _pane(st: SurfaceTool, origin: Vector3, basis: Basis, lo: Vector3, hi: Vector3, col: Color) -> void:
	var a := origin + basis * Vector3(lo.x, lo.y, lo.z)
	var b := origin + basis * Vector3(hi.x, lo.y, lo.z)
	var c := origin + basis * Vector3(hi.x, hi.y, lo.z)
	var d := origin + basis * Vector3(lo.x, hi.y, lo.z)
	LandmarkKit.quad_facing(st, a, b, c, d, col, basis * Vector3.FORWARD)


func _club(club: Dictionary, terrain: Terrain) -> void:
	var root := Node3D.new()
	root.name = "BeachClub"
	add_child(root)
	root.position = Vector3(float(club.x), float(club.y), float(club.z))
	root.rotation.y = deg_to_rad(float(club.yaw))
	club_anchor = {"x": float(club.x), "z": float(club.z)}
	var length := float(club.length)
	var depth := float(club.depth)
	var pool: Array = club.pool
	var pl := float(pool[0])
	var pw := float(pool[1])
	var st := LandmarkKit.begin()
	var water := LandmarkKit.begin()
	var canvas := LandmarkKit.begin()
	# Deck down to the shore, its sea face a stepped stone wall.
	LandmarkKit.box(st, Vector3(0, -2.2, 0), Vector3(length, 4.4, depth), TILE.darkened(0.08))
	var pool_z := -depth * 0.5 + 5.8 + pw * 0.5
	var rim := 0.35
	# Deck top in four strips round the pool.
	var x0 := -pl * 0.5 - rim
	var x1 := pl * 0.5 + rim
	var z0 := pool_z - pw * 0.5 - rim
	var z1 := pool_z + pw * 0.5 + rim
	_slab_top(st, -length * 0.5, length * 0.5, -depth * 0.5, z0, STONE)
	_slab_top(st, -length * 0.5, length * 0.5, z1, depth * 0.5, STONE)
	_slab_top(st, -length * 0.5, x0, z0, z1, STONE)
	_slab_top(st, x1, length * 0.5, z0, z1, STONE)
	# Coping and the basin: pale tiles under bright water.
	for side: float in [-1.0, 1.0]:
		LandmarkKit.box(st, Vector3(0, 0.04, pool_z + side * (pw * 0.5 + rim * 0.5)), Vector3(pl + rim * 2.0, 0.12, rim), Color.WHITE)
		LandmarkKit.box(st, Vector3(side * (pl * 0.5 + rim * 0.5), 0.04, pool_z), Vector3(rim, 0.12, pw), Color.WHITE)
	LandmarkKit.box(st, Vector3(0, -1.0, pool_z), Vector3(pl, 0.1, pw), Color("#9fdde4"))
	LandmarkKit.quad_facing(water, Vector3(-pl * 0.5, -0.12, pool_z - pw * 0.5), Vector3(pl * 0.5, -0.12, pool_z - pw * 0.5),
		Vector3(pl * 0.5, -0.12, pool_z + pw * 0.5), Vector3(-pl * 0.5, -0.12, pool_z + pw * 0.5), WATER, Vector3.UP)
	# Steps down the sea face to the rocks.
	for k in 6:
		var w := length * 0.36
		LandmarkKit.box(st, Vector3(length * 0.18, -0.25 - k * 0.32, depth * 0.5 + 0.45 + k * 0.6), Vector3(w, 0.3, 0.6), TILE)
	# Loungers in pairs along both long sides, a parasol between each pair.
	var spacing := 3.3
	var count := int(pl / spacing)
	for side: float in [-1.0, 1.0]:
		var row_z := pool_z + side * (pw * 0.5 + 2.4)
		for k in count:
			var x := -pl * 0.5 + spacing * (k + 0.5)
			for pair: float in [-0.55, 0.55]:
				_lounger(st, Vector3(x + pair, 0.0, row_z), side)
			if k % 2 == 0:
				_parasol(st, canvas, Vector3(x, 0.0, row_z + side * 0.2), 1.55)
	# Cabanas along the road side of the deck, palms between them.
	var cabanas := 6
	var palms := []
	for k in cabanas:
		var x := -length * 0.5 + length * (k + 0.5) / cabanas
		_cabana(st, canvas, Vector3(x, 0.0, -depth * 0.5 + 2.6))
		if k < cabanas - 1:
			palms.append([x + length / cabanas * 0.5, 0.0, -depth * 0.5 + 2.2, 0.85 + 0.15 * sin(k * 2.1), k * 1.7])
	# The seaward rail.
	for k in 22:
		var x := -length * 0.5 + length * (k + 0.5) / 22.0
		if x > length * 0.0 and x < length * 0.36:
			continue
		LandmarkKit.box(st, Vector3(x, 0.55, depth * 0.5 - 0.2), Vector3(0.06, 1.1, 0.06), RAIL)
	_pane_local(canvas, Vector3(-length * 0.5, 0.25, depth * 0.5 - 0.2), Vector3(0.0, 1.05, depth * 0.5 - 0.2), Color(0.75, 0.86, 0.9))
	var deck := LandmarkKit.mesh_node(st, LandmarkKit.material(0.8), "PoolDeck", 1200.0)
	root.add_child(deck)
	var pool_mat := StandardMaterial3D.new()
	pool_mat.vertex_color_use_as_albedo = true
	pool_mat.vertex_color_is_srgb = true
	pool_mat.roughness = 0.04
	pool_mat.metallic = 0.25
	pool_mat.emission_enabled = true
	pool_mat.emission = Color("#1e7f91")
	pool_mat.emission_energy_multiplier = 0.35
	var basin := LandmarkKit.mesh_node(water, pool_mat, "PoolWater", 1200.0)
	basin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(basin)
	root.add_child(LandmarkKit.mesh_node(canvas, LandmarkKit.material(0.9, 0.0, false), "ParasolsAndCanopies", 800.0))
	var grove := Palms.new()
	grove.name = "ClubPalms"
	root.add_child(grove)
	grove.build(palms)


func _slab_top(st: SurfaceTool, x0: float, x1: float, z0: float, z1: float, col: Color) -> void:
	if x1 - x0 < 0.05 or z1 - z0 < 0.05:
		return
	LandmarkKit.quad_facing(st, Vector3(x0, 0.0, z0), Vector3(x1, 0.0, z0), Vector3(x1, 0.0, z1), Vector3(x0, 0.0, z1), col, Vector3.UP)


func _pane_local(st: SurfaceTool, lo: Vector3, hi: Vector3, col: Color) -> void:
	LandmarkKit.quad_facing(st, lo, Vector3(hi.x, lo.y, lo.z), hi, Vector3(lo.x, hi.y, lo.z), col, Vector3.FORWARD)


## A white sun lounger, back raised toward the pool side's outer edge.
func _lounger(st: SurfaceTool, at: Vector3, side: float) -> void:
	LandmarkKit.box(st, at + Vector3(0, 0.3, 0), Vector3(0.68, 0.12, 1.9), Color.WHITE)
	LandmarkKit.box(st, at + Vector3(0, 0.12, 0), Vector3(0.56, 0.24, 1.6), WHITE_SHADE)
	var back := Basis(Vector3.RIGHT, -side * 0.75)
	LandmarkKit.box(st, at + Vector3(0, 0.58, side * 0.72), Vector3(0.66, 0.1, 0.72), CANVAS, back)


## A white parasol: pole and an eight-panel canopy.
func _parasol(st: SurfaceTool, canvas: SurfaceTool, at: Vector3, radius: float) -> void:
	LandmarkKit.tube(st, at, at + Vector3.UP * 2.45, 0.035, 0.03, TEAK, 6)
	var apex := at + Vector3.UP * 2.75
	for k in 8:
		var a0 := TAU * k / 8.0
		var a1 := TAU * (k + 1) / 8.0
		var p0 := at + Vector3(cos(a0) * radius, 2.2, sin(a0) * radius)
		var p1 := at + Vector3(cos(a1) * radius, 2.2, sin(a1) * radius)
		LandmarkKit.quad_facing(canvas, p0, p1, apex, apex, CANVAS.darkened(0.04 * (k % 2)), Vector3.UP)


## A square cabana: four teak posts and a white canopy with a valance.
func _cabana(st: SurfaceTool, canvas: SurfaceTool, at: Vector3) -> void:
	var half := 1.7
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p := at + Vector3(c.x * half, 0.0, c.y * half)
		LandmarkKit.box(st, p + Vector3.UP * 1.25, Vector3(0.12, 2.5, 0.12), TEAK)
	LandmarkKit.box(canvas, at + Vector3.UP * 2.55, Vector3(half * 2.0 + 0.3, 0.1, half * 2.0 + 0.3), CANVAS)
	for side: float in [-1.0, 1.0]:
		LandmarkKit.box(canvas, at + Vector3(0, 2.35, side * (half + 0.15)), Vector3(half * 2.0 + 0.3, 0.4, 0.03), CANVAS.darkened(0.05))
	LandmarkKit.box(st, at + Vector3.UP * 0.35, Vector3(2.2, 0.4, 2.2), Color.WHITE)
