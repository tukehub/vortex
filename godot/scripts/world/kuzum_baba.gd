class_name KuzumBaba
extends Node3D
## Kuzum Baba, the Bektashi hill above Vlorë (Kodra e Kuzum Babait, 88 m):
## interpretations after photographs, at their OSM positions.
##   "kuzum_baba_tekke"  the temple on the summit: a yellow two-storey hall
##       between two tall green towers, arched windows in white surrounds, a
##       green cornice, a green-roofed pergola at the entrance; in front, a
##       retaining wall of crazy-paved stone under a white balustrade; cypresses.
##   "kuzum_baba_turbe"  the tomb on the western brow: a grey stone block
##       with crenellations and arched openings under a green dome and lantern.
## Local frame: the facade faces -Z (west, toward the boulevard). Walls and
## plinths reach down to the terrain, which falls away to the west.

const YELLOW := Color("#e4cf78")
const GREEN := Color("#33aa4c")
const GREEN_DARK := Color("#21733a")
const WHITE := Color("#f0eee7")
const WINDOW := Color("#2c3438")
const STONE := Color("#b1ab9c")
const PAVING := [Color("#cdb88c"), Color("#a99b7f"), Color("#dacca8"), Color("#8f8471"), Color("#bea77b"), Color("#9c9584")]
const CYPRESS := Color("#2c4a2e")
const REACH := 2600.0

## Temple hall: 27.5 m along the facade, 22 m deep (OSM way 1222923149).
const HALL := Vector3(27.5, 8.2, 22.0)
const TOWER := Vector3(5.2, 13.0, 5.2)

var _terrain: Terrain


func build(landmark_id: String, terrain: Terrain) -> void:
	_terrain = terrain
	match landmark_id:
		"kuzum_baba_tekke":
			_tekke()
		"kuzum_baba_turbe":
			_turbe()


## Local height of the ground under local point (x, z); 0 without terrain.
func _ground(x: float, z: float) -> float:
	var parent := get_parent() as Node3D
	if _terrain == null or parent == null:
		return 0.0
	var world := parent.transform * Vector3(x, 0.0, z)
	return _terrain.height_at(world.x, world.z) - parent.position.y


func _tekke() -> void:
	var st := LandmarkKit.begin()
	var hx := HALL.x * 0.5
	var hz := HALL.z * 0.5
	# A plinth that reaches the slope under the whole hall.
	var low := minf(minf(_ground(-hx, -hz), _ground(hx, -hz)), minf(_ground(-hx, hz), _ground(hx, hz)))
	LandmarkKit.box(st, Vector3(0, (low - 1.0) * 0.5, 0), Vector3(HALL.x + 1.0, -low + 1.0, HALL.z + 1.0), PAVING[3])
	LandmarkKit.box(st, Vector3(0, HALL.y * 0.5, 0), HALL, YELLOW)
	# Green cornice and a white string course between the floors.
	LandmarkKit.box(st, Vector3(0, HALL.y + 0.25, 0), Vector3(HALL.x + 0.5, 0.5, HALL.z + 0.5), GREEN)
	LandmarkKit.box(st, Vector3(0, 4.1, 0), Vector3(HALL.x + 0.14, 0.18, HALL.z + 0.14), WHITE)
	LandmarkKit.box(st, Vector3(0, HALL.y + 0.56, 0), Vector3(HALL.x - 1.0, 0.14, HALL.z - 1.0), Color("#8d8f88"))
	# Arched windows on the facade and the sides, two floors.
	for floor_y in [1.1, 5.0]:
		for i in 6:
			var x := -hx + 7.2 + i * 2.6
			_arch_window(st, Vector3(x, floor_y, -hz), 1.15, 2.2, Basis.IDENTITY)
		for i in 5:
			var z := -hz + 3.4 + i * 3.8
			_arch_window(st, Vector3(-hx, floor_y, z), 1.15, 2.2, Basis(Vector3.UP, -PI / 2))
			_arch_window(st, Vector3(hx, floor_y, z), 1.15, 2.2, Basis(Vector3.UP, PI / 2))
	# Entrance: a white door frame under the pergola.
	LandmarkKit.box(st, Vector3(0, 1.5, -hz - 0.05), Vector3(2.6, 3.0, 0.1), WHITE)
	LandmarkKit.box(st, Vector3(0, 1.35, -hz - 0.12), Vector3(1.9, 2.7, 0.06), Color("#5a4632"))
	# Two green towers at the ends of the facade, standing slightly forward.
	for side in [-1.0, 1.0]:
		var c := Vector3(side * (hx - TOWER.x * 0.5 + 0.4), 0, -hz + TOWER.z * 0.5 - 0.6)
		LandmarkKit.box(st, c + Vector3(0, TOWER.y * 0.5, 0), TOWER, GREEN)
		LandmarkKit.box(st, c + Vector3(0, TOWER.y + 0.2, 0), Vector3(TOWER.x + 0.5, 0.4, TOWER.z + 0.5), GREEN_DARK)
		# Tall slit windows high on each face.
		for face in 4:
			var b := Basis(Vector3.UP, face * PI / 2)
			for k in [-1.0, 1.0]:
				LandmarkKit.box(st, c + b * Vector3(k * 1.0, 10.4, -TOWER.z * 0.5 - 0.02), Vector3(0.6, 1.5, 0.06), WINDOW, b)
			LandmarkKit.box(st, c + b * Vector3(0, 6.6, -TOWER.z * 0.5 - 0.02), Vector3(0.7, 1.2, 0.06), WINDOW, b)
	# The pergola: four white posts under a low green pyramid roof.
	var pg := Vector3(0, 0, -hz - 3.4)
	for px in [-1.9, 1.9]:
		for pz in [-1.9, 1.9]:
			LandmarkKit.box(st, pg + Vector3(px, 1.45, pz), Vector3(0.24, 2.9, 0.24), WHITE)
	LandmarkKit.box(st, pg + Vector3(0, 3.0, 0), Vector3(4.6, 0.22, 4.6), WHITE)
	_pyramid(st, pg + Vector3(0, 3.1, 0), 2.6, 1.1, GREEN_DARK)
	for side in [-1.0, 1.0]:
		var c := Vector3(side * (hx - TOWER.x * 0.5 + 0.4), TOWER.y + 0.4, -hz + TOWER.z * 0.5 - 0.6)
		_pyramid(st, c, TOWER.x * 0.5 + 0.2, 1.6, GREEN_DARK)
	# Retaining wall with a white balustrade in front of the temple, and its
	# returns along both sides.
	var wall_z := -hz - 9.0
	_wall(st, Vector3(-27.0, 0, wall_z), Vector3(27.0, 0, wall_z))
	_wall(st, Vector3(-27.0, 0, wall_z), Vector3(-27.0, 0, hz + 2.0))
	_wall(st, Vector3(27.0, 0, wall_z), Vector3(27.0, 0, hz + 2.0))
	# Cypresses on the summit.
	for p in [Vector2(-22, 6), Vector2(-20, -2), Vector2(22, 8), Vector2(18, 15), Vector2(-15, 15), Vector2(5, 17)]:
		var g := _ground(p.x, p.y)
		LandmarkKit.tube(st, Vector3(p.x, g, p.y), Vector3(p.x, g + 1.2, p.y), 0.2, 0.18, Color("#4b3b2b"), 5)
		LandmarkKit.sphere(st, Vector3(p.x, g + 5.2, p.y), Vector3(1.25, 4.6, 1.25), CYPRESS, 5, 7)
	add_child(LandmarkKit.mesh_node(st, LandmarkKit.material(0.82), "KuzumBabaTemple", REACH))
	_flag(Vector3(-3.4, 0, -hz - 1.2))


func _turbe() -> void:
	var st := LandmarkKit.begin()
	var half := 3.2
	var low := minf(minf(_ground(-half, -half), _ground(half, -half)), minf(_ground(-half, half), _ground(half, half)))
	# A stone terrace, stepped into the slope below the tomb.
	LandmarkKit.box(st, Vector3(0, (low - 0.6) * 0.5, 0), Vector3(half * 2 + 1.6, -low + 0.6, half * 2 + 1.6), STONE.darkened(0.3))
	if low < -1.5:
		LandmarkKit.box(st, Vector3(0, (low - 0.6) * 0.5 - 0.5, -half - 1.4), Vector3(half * 2 + 1.0, -low - 0.6, 1.2), STONE.darkened(0.38))
	LandmarkKit.box(st, Vector3(0, 0.15, 0), Vector3(half * 2 + 1.2, 0.3, half * 2 + 1.2), STONE.lightened(0.1))
	LandmarkKit.box(st, Vector3(0, 2.3, 0), Vector3(half * 2, 4.3, half * 2), STONE)
	# Coursed stone: darker bed joints.
	for y in [1.0, 1.9, 2.8, 3.7]:
		LandmarkKit.box(st, Vector3(0, y, 0), Vector3(half * 2 + 0.04, 0.06, half * 2 + 0.04), STONE.darkened(0.18))
	for face in 4:
		var b := Basis(Vector3.UP, face * PI / 2)
		# An arched opening on every face.
		_arch_window(st, b * Vector3(0, 0.4, -half), 1.5, 2.6, b, STONE.lightened(0.15))
		# Merlons along the parapet.
		for k in 5:
			var x := -half + 0.45 + k * (half * 2 - 0.9) / 4.0
			LandmarkKit.box(st, b * Vector3(x, 4.75, -half + 0.2), Vector3(0.55, 0.6, 0.4), STONE.lightened(0.06), b)
	# Drum, green dome and lantern.
	LandmarkKit.tube(st, Vector3(0, 4.4, 0), Vector3(0, 5.4, 0), 2.1, 2.05, STONE.lightened(0.08), 12)
	LandmarkKit.sphere(st, Vector3(0, 5.35, 0), Vector3(2.15, 1.95, 2.15), GREEN, 8, 14)
	LandmarkKit.tube(st, Vector3(0, 7.15, 0), Vector3(0, 7.9, 0), 0.42, 0.38, GREEN, 8)
	LandmarkKit.tube(st, Vector3(0, 7.9, 0), Vector3(0, 8.3, 0), 0.5, 0.05, GREEN_DARK, 8)
	LandmarkKit.tube(st, Vector3(0, 8.3, 0), Vector3(0, 8.75, 0), 0.04, 0.03, Color("#c9a64a"), 4)
	add_child(LandmarkKit.mesh_node(st, LandmarkKit.material(0.85), "KuzumBabaTurbe", REACH))


## A window (or doorway) of width w and height h with a round head, set in a
## white surround, centred on `base` at the foot of the opening, facing -Z
## of `basis`.
func _arch_window(st: SurfaceTool, base: Vector3, w: float, h: float, basis: Basis, frame := WHITE) -> void:
	var out := basis * Vector3(0, 0, -1)
	var r := w * 0.5
	var rect := h - r
	LandmarkKit.box(st, base + basis * Vector3(0, rect * 0.5 + 0.0, -0.03), Vector3(w + 0.3, rect + 0.15, 0.06), frame, basis)
	LandmarkKit.box(st, base + basis * Vector3(0, rect * 0.5, -0.07), Vector3(w, rect, 0.04), WINDOW, basis)
	var top := base + basis * Vector3(0, rect, -0.07)
	for k in 6:
		var a0 := PI * k / 6.0
		var a1 := PI * (k + 1) / 6.0
		var p0 := top + basis * Vector3(cos(a0) * r, sin(a0) * r, 0)
		var p1 := top + basis * Vector3(cos(a1) * r, sin(a1) * r, 0)
		LandmarkKit.quad_facing(st, top, top, p1, p0, WINDOW, out)
		var q0 := top + basis * Vector3(cos(a0) * (r + 0.15), sin(a0) * (r + 0.15), 0.04)
		var q1 := top + basis * Vector3(cos(a1) * (r + 0.15), sin(a1) * (r + 0.15), 0.04)
		LandmarkKit.quad_facing(st, p0, p1, q1, q0, frame, out)


func _pyramid(st: SurfaceTool, base: Vector3, half: float, height: float, col: Color) -> void:
	var apex := base + Vector3(0, height, 0)
	var corners := [Vector3(-half, 0, -half), Vector3(half, 0, -half), Vector3(half, 0, half), Vector3(-half, 0, half)]
	for i in 4:
		var a: Vector3 = base + corners[i]
		var b: Vector3 = base + corners[(i + 1) % 4]
		var mid := (a + b) * 0.5 - base
		LandmarkKit.quad_facing(st, a, b, apex, apex, col, Vector3(mid.x, half, mid.z))


## A crazy-paved retaining wall from a to b, standing on the slope, its top
## 1 m above the terrace, with a white balustrade along it.
func _wall(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var basis := Basis(Vector3.UP, atan2(-dir.z, dir.x))
	var panels := maxi(1, int(length / 1.3))
	var top := 1.0
	for i in panels:
		var t0 := float(i) / panels
		var t1 := float(i + 1) / panels
		var p := a.lerp(b, (t0 + t1) * 0.5)
		var g := minf(_ground(p.x, p.z), 0.0) - 1.0
		var tone: Color = PAVING[(i * 7 + int(length)) % PAVING.size()]
		LandmarkKit.box(st, Vector3(p.x, (g + top) * 0.5, p.z), Vector3(length / panels + 0.02, top - g, 0.6), tone, basis)
		# Mortar lines across the stones.
		LandmarkKit.box(st, Vector3(p.x, lerpf(g, top, 0.35 + 0.3 * ((i * 3) % 2)), p.z), Vector3(length / panels, 0.05, 0.62), Color("#e2dccd"), basis)
	# Coping, rail and balusters.
	LandmarkKit.box(st, (a + b) * 0.5 + Vector3(0, top + 0.06, 0), Vector3(length + 0.4, 0.12, 0.7), WHITE, basis)
	LandmarkKit.box(st, (a + b) * 0.5 + Vector3(0, top + 1.0, 0), Vector3(length + 0.3, 0.12, 0.32), WHITE, basis)
	var count := int(length / 0.42)
	for i in count + 1:
		var p := a.lerp(b, float(i) / count)
		var post := i % 7 == 0
		LandmarkKit.box(st, p + Vector3(0, top + 0.55, 0), Vector3(0.32, 0.9, 0.32) if post else Vector3(0.12, 0.85, 0.12), WHITE, basis)
		if post:
			LandmarkKit.box(st, p + Vector3(0, top + 1.25, 0), Vector3(0.18, 0.28, 0.18), WHITE, basis)


## The Albanian flag on a short pole by the entrance.
func _flag(at: Vector3) -> void:
	var st := LandmarkKit.begin()
	LandmarkKit.tube(st, at, at + Vector3(0, 5.0, 0), 0.05, 0.04, Color("#d8d8d8"), 6)
	add_child(LandmarkKit.mesh_node(st, LandmarkKit.material(0.4, 0.6), "KuzumBabaFlagPole", REACH))
	var flag := MeshInstance3D.new()
	flag.name = "KuzumBabaFlag"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.6, 1.12)
	flag.mesh = quad
	var m := StandardMaterial3D.new()
	m.albedo_texture = LandmarkKit.albanian_flag()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.9
	flag.material_override = m
	flag.position = at + Vector3(0.85, 4.35, 0)
	flag.visibility_range_end = 900.0
	add_child(flag)
