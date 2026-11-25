class_name RockField
extends Node3D
## One shared set of scan meshes. Each occupied chunk holds a batch per shape;
## distance swaps the mesh and thins the smallest stones, preserving transforms.

const LIBRARY := "res://assets/cities/vlore/rock_scans.glb"
const CHUNK := 56.0
const NEAR := 52.0
const MIDDLE := 136.0
const REACH := 390.0
const VARIANTS := 8
const MIN_ROCK := .23
const GRAVEL := .10
const GRAVEL_BATCH := VARIANTS
const GRAVEL_SHAPE := 1

static var _scans: Array[Array] = []
var placed: Array[Transform3D] = []
var _groups := {}
var chunks := {}
var _terrain: Terrain
var _material: ShaderMaterial
var _elapsed := 0.0


func start(terrain: Terrain) -> void:
	_terrain = terrain
	if _scans.is_empty():
		var library: PackedScene = load(LIBRARY)
		var root := library.instantiate()
		for shape in VARIANTS:
			var levels := []
			for lod in 3:
				var model := root.get_node("Rock%d_L%d" % [shape, lod]) as MeshInstance3D
				levels.append(model.mesh)
			_scans.append(levels)
		root.free()
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/sea_rock.gdshader")
	_material.set_shader_parameter("water_y", terrain.water_surface)
	_material.set_shader_parameter("grain", preload("res://assets/textures/limestone_diff.jpg"))
	_material.set_shader_parameter("grain_n", preload("res://assets/textures/limestone_nor.jpg"))
	_material.set_shader_parameter("grain_arm", preload("res://assets/textures/limestone_arm.jpg"))
	terrain.wetness_changed.connect(_set_wet)


## Shore clusters have an elongated footprint along the bank. Coarse
## blocks lead, fractured pieces settle around them, and gravel fans out.
func cluster(at: Vector2, strike: Vector2, radius: float, max_width: float, splash: float,
		allowed: Callable, rng: RandomNumberGenerator) -> int:
	var before := placed.size()
	var across := Vector2(-strike.y, strike.x)
	var palette := rng.randi_range(0, VARIANTS - 1)
	var tone := rng.randf_range(.21, .81)
	var blocks: Array[Vector2] = []
	for i in rng.randi_range(2, 4):
		var along := rng.randf_range(-.68, .68) * radius if i > 0 else 0.0
		var offset := rng.randf_range(-.30, .34) * radius if i > 0 else 0.0
		var q := at + strike * along + across * offset
		var width := rng.randf_range(max_width * .61, max_width)
		if allowed.call(q, width):
			blocks.append(q)
			_bank_rock((palette + i) % VARIANTS, q, strike, width, tone, splash, rng)
	if blocks.is_empty():
		return 0
	# Erosion leaves a fan of smaller fragments around each block, with
	# gravel scattered farther outward into the bare bank.
	for group in 2:
		var count := rng.randi_range(4, 8) if group == 0 else rng.randi_range(6, 12)
		for i in count:
			var phi := rng.randf() * TAU
			var spread := max_width * rng.randf_range(.28, .82 + .42*group)
			var q := blocks[i % blocks.size()] + spread * (strike * cos(phi) + across * sin(phi) * .66)
			var width := rng.randf_range(MIN_ROCK, maxf(.38, max_width*.47)) if group == 0 else rng.randf_range(GRAVEL, .22)
			if allowed.call(q, width):
				_bank_rock((palette + rng.randi_range(0, 4)) % VARIANTS, q, strike, width, tone, splash, rng)
	return placed.size() - before


func _bank_rock(shape: int, q: Vector2, strike: Vector2, width: float,
		tone: float, splash: float, rng: RandomNumberGenerator) -> void:
	var y := _terrain.surface_height_at(q.x, q.y)
	var slope := _land_normal(q, maxf(.55, width*.64))
	_place(shape, Vector3(q.x, y, q.y), slope, strike, width, tone, splash, rng)


## Tunnel talus locations and normals come from the baked cliff triangle.
func add_talus(site: Transform3D, rng: RandomNumberGenerator) -> void:
	var width := site.basis.x.length()
	var strike := Vector2(site.basis.x.x, site.basis.x.z).normalized()
	_place(rng.randi_range(0, VARIANTS - 1), site.origin, site.basis.y.normalized(), strike,
		width, rng.randf_range(.30, .74), .16, rng)


func _land_normal(p: Vector2, range_m: float) -> Vector3:
	var dx := _terrain.surface_height_at(p.x + range_m, p.y) - _terrain.surface_height_at(p.x - range_m, p.y)
	var dz := _terrain.surface_height_at(p.x, p.y + range_m) - _terrain.surface_height_at(p.x, p.y - range_m)
	return Vector3(-dx, 2.0 * range_m, -dz).normalized()


func _place(shape: int, surface: Vector3, slope: Vector3, strike: Vector2, width: float,
		tone: float, splash: float, rng: RandomNumberGenerator) -> void:
	var gravel := width < MIN_ROCK
	var source := GRAVEL_SHAPE if gravel else shape
	var bounds: AABB = _scans[source][0].get_aabb()
	var up := Vector3.UP.lerp(slope, rng.randf_range(.33, .72)).normalized()
	var bearing := Vector3(strike.x, 0., strike.y).rotated(Vector3.UP, rng.randf_range(-.86, .86))
	var axis := (bearing - up * bearing.dot(up)).normalized()
	var height_scale := rng.randf_range(.79, 1.18)
	var scale := Vector3(width, width * height_scale, width * rng.randf_range(.86, 1.06))
	var basis := Basis(axis * scale.x, up * scale.y, axis.cross(up) * scale.z)
	# All scans share the same normalized foot plane at y=0. The embed
	# depth accounts for the actual rock height and the local slope.
	var rock_height := bounds.size.y * scale.y
	var bury := rock_height * rng.randf_range(.22, .37) + width * (1.0 - slope.y) * .17
	var xf := Transform3D(basis, surface - Vector3.UP * bury)
	var cell := Vector2i(floori(surface.x / CHUNK), floori(surface.z / CHUNK))
	var group := Vector3i(cell.x, cell.y, GRAVEL_BATCH if gravel else shape)
	if not _groups.has(group):
		_groups[group] = []
	var variations := Color(clampf(tone + rng.randf_range(-.15, .15), 0., 1.),
		splash * rng.randf_range(.55, 1.), rng.randf_range(.23, .96), rng.randf())
	_groups[group].append([xf, variations, width])
	placed.append(xf)


func finish() -> void:
	for key: Vector3i in _groups:
		var cell := Vector2i(key.x, key.y)
		var centre := (Vector2(cell) + Vector2(.5, .5)) * CHUNK
		var entries: Array = _groups[key]
		entries.sort_custom(func(a: Array, b: Array) -> bool: return a[2] > b[2])
		var gravel := key.z == GRAVEL_BATCH
		var shape := GRAVEL_SHAPE if gravel else key.z
		var mesh: Mesh = _scans[shape][2 if gravel else 0]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = entries.size()
		var box := AABB()
		var counts := Vector3i.ZERO
		for i in entries.size():
			var xf: Transform3D = entries[i][0]
			xf.origin -= Vector3(centre.x, 0., centre.y)
			mm.set_instance_transform(i, xf)
			mm.set_instance_custom_data(i, entries[i][1])
			var local := xf * mesh.get_aabb()
			box = local if i == 0 else box.merge(local)
			var width: float = entries[i][2]
			counts += Vector3i(1, int(width >= MIN_ROCK), int(width >= .55))
		mm.custom_aabb = box.grow(.20)
		var node := MultiMeshInstance3D.new()
		node.name = "Rock_%d_%d_%d" % [key.x, key.y, key.z]
		node.position = Vector3(centre.x, 0., centre.y)
		node.multimesh = mm
		node.material_override = _material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visibility_range_end = REACH
		node.set_instance_shader_parameter("close_detail", true)
		add_child(node)
		if not chunks.has(cell):
			chunks[cell] = {"centre": centre, "lod": 0, "nodes": []}
		chunks[cell].nodes.append({"node": node, "shape": shape, "counts": counts, "gravel": gravel})
	_groups.clear()
	Quality.budget_changed.connect(_apply_budget)
	_apply_budget()


func _process(delta: float) -> void:
	_elapsed -= delta
	if _elapsed > 0.0:
		return
	_elapsed = .20
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		update_lods(camera.global_position)


func update_lods(camera: Vector3) -> void:
	var cheap := Quality.preset == "low" or Quality.pressure_stage >= 2
	var near := NEAR * (.73 if cheap else 1.0)
	var mid := MIDDLE * (.77 if cheap else 1.0)
	for chunk: Dictionary in chunks.values():
		var offset := (Vector2(camera.x, camera.z) - (chunk.centre as Vector2)).abs()
		var distance := (offset - Vector2.ONE * (CHUNK * .5)).max(Vector2.ZERO).length()
		var lod: int = chunk.lod
		var margin := -4.0 if lod == 0 else 4.0
		var next := 0 if distance < near - margin else (1 if distance < mid + (4.0 if lod <= 1 else -4.0) else 2)
		if next != lod:
			chunk.lod = next
			_apply_chunk(chunk, cheap)


func _apply_budget() -> void:
	var cheap := Quality.preset == "low" or Quality.pressure_stage >= 2
	for chunk: Dictionary in chunks.values():
		_apply_chunk(chunk, cheap)


func _apply_chunk(chunk: Dictionary, cheap: bool) -> void:
	var lod: int = chunk.lod
	for batch: Dictionary in chunk.nodes:
		var node: MultiMeshInstance3D = batch.node
		var mm := node.multimesh
		var counts: Vector3i = batch.counts
		var mesh: Mesh = _scans[batch.shape][2 if batch.gravel else lod]
		if mm.mesh != mesh:
			mm.mesh = mesh
		mm.visible_instance_count = counts[mini(2, lod + int(cheap))]
		node.set_instance_shader_parameter("close_detail", lod == 0 and not cheap and not batch.gravel)


func _set_wet(value: float) -> void:
	_material.set_shader_parameter("wetness", value)
