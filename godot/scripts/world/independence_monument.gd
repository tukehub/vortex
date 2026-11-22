class_name IndependenceMonument
extends Node3D
## Monumenti i Pavarësisë, Sheshi i Flamurit, Vlorë: an interpretation after
## photographs. A tall, tapering dark stone pylon carrying "1912" near its top;
## a bronze flag-bearer standing on it with a great furled flag; a group of
## bronze figures at its foot (frock-coated statesmen, a fighter with raised
## fist, a kneeling fighter, men in plis caps) on a low stepped plinth.
## Local frame: the "1912" face and the group look toward -Z.
## The figures and period garments are baked by tools/build_independence_bronze.py.

const STONE := Color("#999e9c")
const STONE_LIGHT := Color(0.50, 0.50, 0.49)
const BRONZE := Color("#514e42")
const PLINTH_TOP := 2.1
const PYLON_TOP := 14.7
## Face the opening grid on the diagonal of the points arena.
const ARENA_YAW := 222.0
const FIGURES_PATH := "res://assets/landmarks/independence_bronze.glb"


func _ready() -> void:
	_stone()
	_bronze()
	_inscription()


func _stone() -> void:
	var st := LandmarkKit.begin()
	# Two broad steps and the plinth the group stands on.
	LandmarkKit.box(st, Vector3(0, -1.5, -1.0), Vector3(17.0, 3.0, 13.0), STONE_LIGHT)
	LandmarkKit.box(st, Vector3(0, 0.25, -1.0), Vector3(15.0, 0.5, 11.0), STONE_LIGHT.darkened(0.08))
	LandmarkKit.box(st, Vector3(0, 1.3, -1.0), Vector3(13.4, 1.6, 9.4), STONE.darkened(0.12))
	# The pylon: a tapering block whose top is cut on a slant, high at the back.
	var b0 := Vector2(1.9, 1.35)   # half sizes at the foot (x, z)
	var b1 := Vector2(1.25, 0.95)  # at the top
	var cz := 1.2                  # set back behind the group
	var y0 := PLINTH_TOP
	# Recess each horizontal bed joint and catch the sunlight on the chamfered corners.
	var outline := [Vector2(-0.91, -1), Vector2(0.91, -1), Vector2(1, -0.88), Vector2(1, 0.88),
		Vector2(0.91, 1), Vector2(-0.91, 1), Vector2(-1, 0.88), Vector2(-1, -0.88)]
	for course in 8:
		var bottom := float(course) / 8.0
		var top := float(course + 1) / 8.0
		var rings := []
		for t: float in [bottom, bottom + 0.002, top - 0.002, top]:
			var inset := 0.022 if t == bottom or t == top else 0.0
			var half_size := b0.lerp(b1, t) - Vector2.ONE * inset
			var ring := PackedVector3Array()
			for uv: Vector2 in outline:
				ring.append(Vector3(uv.x * half_size.x, lerpf(y0, PYLON_TOP - 0.6 + 0.6 * uv.y, t), cz + uv.y * half_size.y))
			rings.append(ring)
		for row in 3:
			for i in outline.size():
				var j := (i + 1) % outline.size()
				var face: Vector2 = outline[i] + outline[j]
				LandmarkKit.quad_facing(st, rings[row][i], rings[row][j], rings[row + 1][j], rings[row + 1][i],
					STONE.darkened(0.035 * (course % 3)), Vector3(face.x, 0, face.y))
		if course == 7:
			var lid: PackedVector3Array = rings[3]
			for corner in [1, 3, 5]:
				LandmarkKit.quad_facing(st, lid[0], lid[corner], lid[corner + 1], lid[corner + 2], STONE, Vector3.UP)
	# A raised panel framing the date.
	LandmarkKit.box(st, Vector3(0, PYLON_TOP - 3.4, cz - 1.08), Vector3(2.2, 1.25, 0.12), STONE.lightened(0.06))
	# Dark, rough-dressed stone; the steps a paler grey.
	var stone := LandmarkKit.material(0.9)
	stone.albedo_texture = preload("res://assets/textures/concrete_diff.jpg")
	stone.normal_enabled = true
	stone.normal_texture = preload("res://assets/textures/concrete_nor.jpg")
	stone.normal_scale = 0.25
	stone.uv1_triplanar = true
	stone.uv1_scale = Vector3.ONE * 0.38
	add_child(LandmarkKit.mesh_node(st, stone, "MonumentStone", 2200.0))


func _inscription() -> void:
	var date := TextMesh.new()
	date.text = Data.t("sign.independence_year")
	date.font = ThemeDB.fallback_font
	date.font_size = 96
	date.pixel_size = 0.010
	date.depth = 0.075
	var raised := MeshInstance3D.new()
	raised.name = "MonumentDate"
	raised.mesh = date
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("#b8ad93")
	metal.metallic = 0.52
	metal.roughness = 0.57
	raised.material_override = metal
	raised.rotation.y = PI
	raised.position = Vector3(0, PYLON_TOP - 3.4, -0.035)
	add_child(raised)


func _bronze() -> void:
	var cast: PackedScene = load(FIGURES_PATH)
	var figures := cast.instantiate()
	figures.name = "MonumentBronze"
	add_child(figures)
	var st := LandmarkKit.begin()
	var foot := Vector3(-0.13, PYLON_TOP - 0.5, 0.65)
	var tip := Vector3(-0.42, PYLON_TOP + 5.65, 0.20)
	LandmarkKit.tube(st, foot, tip, 0.085, 0.065, BRONZE)
	_cloth(st, tip, foot.lerp(tip, 0.41), Vector3(-1, 0.04, 0.65).normalized(), 3.35)
	add_child(LandmarkKit.mesh_node(st, LandmarkKit.material(0.54, 0.69), "CastFlag", 2200.0))


## A heavy, billowing flag: rows of panels off the pole, wavy and drooping.
func _cloth(st: SurfaceTool, top: Vector3, low: Vector3, out: Vector3, length: float) -> void:
	var cols := 16
	var rows := 9
	var grid := []
	for r in rows + 1:
		var on_pole := top.lerp(low, float(r) / rows)
		var row := []
		for c in cols + 1:
			var t := float(c) / cols
			var v := float(r) / rows
			var p := on_pole + out * (length * t * (0.78 + 0.22 * v))
			p += Vector3(0, -1.8 * t * t + v * 0.68 * t, 0) + Vector3(0.53, 0.12, 0.64) * sin(t * 10.0 + float(r) / rows * 2.6) * t
			row.append(p)
		grid.append(row)
	for r in rows:
		for c in cols:
			var a: Vector3 = grid[r][c]
			var b: Vector3 = grid[r][c + 1]
			var cc: Vector3 = grid[r + 1][c + 1]
			var d: Vector3 = grid[r + 1][c]
			# Both faces: the cloth is seen from all round.
			LandmarkKit.quad(st, a, b, cc, d, BRONZE)
			LandmarkKit.quad(st, b, a, d, cc, BRONZE)
