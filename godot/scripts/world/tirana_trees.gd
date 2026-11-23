class_name TiranaTrees
extends Node3D
## Shared species meshes, fixed-size camera pools and spatially batched impostors.

const SPECIES := ["plane", "linden", "acacia"]
const ASSET := preload("res://assets/foliage/tirana/broadleaf_trees.glb")
const SEARCH_CELL := 76.0
const FAR_CELL := 320.0
const FADE_MS := 180
const MAX_CHANGES := 24
const EXTRA_SLOTS := 24
const MAX_MID := 144
const MAX_NEAR := 30
const FAR := 2

var entries: Array[Dictionary] = []
var _grid := {}
var _pools: Array[TreePool] = []
var _far_batches: Array[MultiMeshInstance3D] = []
var _detailed := {}
var _fades := {}
var _materials: Array[ShaderMaterial] = []
var _foliage: ShaderMaterial
var _focus := Vector3.INF
var _heading := Vector3.ZERO
var _next_scan := -1
var _last_scan := -1
var _budget_dirty := true
var _scan_pending := false
var _near_radius := 0.0
var _mid_radius := 0.0
var _near_limit := 0
var _mid_limit := 0
var last_candidates := 0


func build(rows: Array, terrain: Terrain) -> void:
	_create_meshes()
	var far_groups := {}
	for i in rows.size():
		var row: Array = rows[i]
		var p := Vector3(row[0], row[1], row[2])
		if terrain != null:
			p.y = terrain.height_at(p.x, p.z)
		var seed_value := float(posmod(i * 7411 + 5623, 65521)) / 65521.0
		@warning_ignore("integer_division")
		var species := posmod(i * 179 + i / 19, SPECIES.size())
		var breadth := lerpf(0.88, 1.12, seed_value)
		var stretch := lerpf(0.94, 1.10, fposmod(seed_value * 13.71, 1.0))
		var scale := float(row[3])
		var basis := Basis(Vector3.UP, fposmod(i * 2.39996, TAU)).scaled(Vector3(breadth, stretch, 2.0 - breadth) * scale)
		var cell := _cell(p, SEARCH_CELL)
		var far_cell := _cell(p, FAR_CELL)
		var world := Transform3D(basis, p)
		entries.append({"world": world, "species": species, "seed": seed_value,
			"lod": FAR, "from": -1, "excluded": false})
		if not _grid.has(cell):
			_grid[cell] = PackedInt32Array()
		_grid[cell].append(i)
		if not far_groups.has(far_cell):
			far_groups[far_cell] = PackedInt32Array()
		far_groups[far_cell].append(i)
	for key: Vector2i in far_groups:
		_build_far_chunk(key, far_groups[key])
	Quality.budget_changed.connect(_apply_budget)
	_apply_budget()


func _create_meshes() -> void:
	var bark := ShaderMaterial.new()
	bark.shader = preload("res://shaders/tree_bark.gdshader")
	bark.set_shader_parameter("bark_color", preload("res://assets/foliage/tirana/bark.jpg"))
	bark.set_shader_parameter("bark_normal", preload("res://assets/foliage/tirana/bark_normal.png"))
	_foliage = ShaderMaterial.new()
	_foliage.shader = preload("res://shaders/tree_crown.gdshader")
	_foliage.set_shader_parameter("sprays", preload("res://assets/foliage/tirana/leaf_sprays.png"))
	var far := ShaderMaterial.new()
	far.shader = preload("res://shaders/tree_impostor.gdshader")
	far.set_shader_parameter("impostors", preload("res://assets/foliage/tirana/impostors.png"))
	_materials.assign([bark, _foliage, far])
	var source := ASSET.instantiate()
	for lod in 2:
		for species in SPECIES:
			var item := source.find_child("%s_lod%d" % [species, lod], true, false) as MeshInstance3D
			var node := MultiMeshInstance3D.new()
			node.name = "%s_lod%d" % [species, lod]
			var mesh := item.mesh.duplicate() as ArrayMesh
			mesh.surface_set_material(0, bark)
			mesh.surface_set_material(1, _foliage)
			# A snap can exchange pools while some old slots are still present.
			var capacity := (MAX_NEAR + EXTRA_SLOTS if lod == 0
				else MAX_MID + MAX_NEAR + EXTRA_SLOTS * 2)
			node.multimesh = make_batch_mesh(mesh, capacity)
			# Dynamic bounds cover all possible positions in the current pool.
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(node)
			RaceReflections.hide_detail(node)
			_pools.append(TreePool.new(node))
	source.free()


static func make_batch_mesh(mesh: Mesh, capacity: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	return mm


static func _cell(p: Vector3, size: float) -> Vector2i:
	return Vector2i(floori(p.x / size), floori(p.z / size))


func _build_far_chunk(key: Vector2i, ids: PackedInt32Array) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(8.6, 11.0)
	quad.center_offset.y = 5.5
	var node := MultiMeshInstance3D.new()
	node.name = "Impostors_%d_%d" % [key.x, key.y]
	node.position = Vector3((key.x + 0.5) * FAR_CELL, 0, (key.y + 0.5) * FAR_CELL)
	node.multimesh = make_batch_mesh(quad, ids.size())
	node.material_override = _materials[FAR]
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	_far_batches.append(node)
	var bounds := AABB()
	for i in ids.size():
		var entry := entries[ids[i]]
		var pose: Transform3D = entry.world
		pose.origin -= node.position
		entry.far = node.multimesh
		entry.far_slot = i
		entry.local = pose
		node.multimesh.set_instance_transform(i, pose)
		node.multimesh.set_instance_custom_data(i, _instance_data(entry, 0.0, 0.0))
		bounds = AABB(pose.origin, Vector3.ZERO) if i == 0 else bounds.expand(pose.origin)
	node.multimesh.custom_aabb = bounds.grow(16.0)
	node.multimesh.visible_instance_count = ids.size()


func _apply_budget() -> void:
	_near_radius = float(Quality.p.tree_near_m)
	_mid_radius = float(Quality.p.tree_mid_m)
	_near_limit = int(Quality.p.tree_near_limit)
	_mid_limit = int(Quality.p.tree_mid_limit)
	_foliage.set_shader_parameter("wind_m", float(Quality.p.tree_wind_m))
	for i in SPECIES.size():
		_pools[i].node.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if bool(Quality.p.tree_near_shadows) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var reach := float(Quality.p.props_dist) * 1.3
	for node in _far_batches:
		node.visibility_range_end = reach + FAR_CELL * 0.71
		node.visibility_range_end_margin = 35.0
	_budget_dirty = true


## A scene landmark may replace a mapped tree without moving any other entry.
func exclude(id: int) -> void:
	var entry := entries[id]
	if entry.lod != FAR:
		_remove(id, entry.lod)
	if entry.from >= 0:
		_remove(id, entry.from)
	_fades.erase(id)
	_detailed.erase(id)
	entry.excluded = true
	entry.lod = FAR
	entry.from = -1
	_remove(id, FAR)


## Called with the actual race camera. Only a bounded local grid query rescans.
func update_focus(pos: Vector3, forward: Vector3, force := false, now := -1) -> bool:
	if now < 0:
		now = Time.get_ticks_msec()
	if not _fades.is_empty():
		_set_clock(now)
		_finish_fades(now)
	if entries.is_empty():
		return false
	var first := _last_scan < 0
	var move := Vector2(pos.x - _focus.x, pos.z - _focus.z).length_squared() if not first else INF
	var turned := forward.dot(_heading) < 0.92
	var jump := move > 46.0 * 46.0
	if not (first or force or jump or _budget_dirty):
		# Scan sooner at speed, without doing a radius query on every frame.
		var due := now >= _next_scan and (move > 0.65 * 0.65 or turned or _scan_pending or not _fades.is_empty())
		var fast := move >= 5.5 * 5.5 and now - _last_scan >= 34
		if not due and not fast:
			return false
	_focus = pos
	_heading = forward
	_last_scan = now
	_next_scan = now + 76
	var snap := first or force or jump
	_budget_dirty = false
	_scan_pending = false
	_select(pos, forward, now, snap)
	return true


func _select(pos: Vector3, forward: Vector3, now: int, snap: bool) -> void:
	var radius := _mid_radius + 9.0
	var from := _cell(pos - Vector3(radius, 0, radius), SEARCH_CELL)
	var to := _cell(pos + Vector3(radius, 0, radius), SEARCH_CELL)
	var heading := Vector2(forward.x, forward.z).normalized()
	var near_candidates: Array = []
	var mid_candidates: Array = []
	last_candidates = 0
	for x in range(from.x, to.x + 1):
		for z in range(from.y, to.y + 1):
			var ids: PackedInt32Array = _grid.get(Vector2i(x, z), PackedInt32Array())
			for id in ids:
				var entry := entries[id]
				if entry.excluded:
					continue
				last_candidates += 1
				var world: Transform3D = entry.world
				var delta := Vector2(world.origin.x - pos.x, world.origin.z - pos.z)
				var distance := delta.length()
				if distance > radius:
					continue
				var facing := delta.dot(heading) / maxf(1.0, distance)
				var score := distance - facing * minf(11.0, distance * 0.24)
				if distance <= _near_radius + (5.0 if entry.lod == 0 and not snap else 0.0):
					near_candidates.append([score - (3.0 if entry.lod == 0 and not snap else 0.0), id])
				if distance <= _mid_radius + (8.0 if entry.lod != FAR and not snap else 0.0):
					mid_candidates.append([score - (4.0 if entry.lod != FAR and not snap else 0.0), id])
	near_candidates.sort_custom(_candidate_order)
	mid_candidates.sort_custom(_candidate_order)
	var desired := {}
	for i in mini(near_candidates.size(), _near_limit):
		desired[near_candidates[i][1]] = 0
	var added := 0
	for candidate in mid_candidates:
		if not desired.has(candidate[1]):
			desired[candidate[1]] = 1
			added += 1
			if added >= _mid_limit:
				break
	# Remove or downgrade stale assignments before filling newly available slots.
	if not snap:
		_set_clock(now)
	var changes := 0
	for id: int in _detailed.keys():
		var lod := int(desired.get(id, FAR))
		if lod > entries[id].lod and _set_lod(id, lod, now, snap):
			changes += 1
			if not snap and changes >= MAX_CHANGES:
				_next_scan = now + 34
				_scan_pending = true
				return
	for id: int in desired:
		if _set_lod(id, desired[id], now, snap):
			changes += 1
			if not snap and changes >= MAX_CHANGES:
				# Continue draining this local update even if the camera stops.
				_next_scan = now + 34
				_scan_pending = true
				break


static func _candidate_order(a: Array, b: Array) -> bool:
	return a[0] < b[0] if a[0] != b[0] else a[1] < b[1]


func _set_lod(id: int, lod: int, now: int, snap: bool) -> bool:
	var entry := entries[id]
	var current: int = entry.lod
	if snap and entry.from >= 0:
		_end_fade(id)
	if current == lod or entry.from >= 0:
		return false
	if not snap and lod < FAR:
		var limit := _near_limit if lod == 0 else _mid_limit
		if pool_count(lod) >= limit + EXTRA_SLOTS:
			return false
	entry.lod = lod
	if snap:
		_remove(id, current)
		_show(id, lod, 0.0, 0.0)
		if lod == FAR:
			_detailed.erase(id)
	else:
		entry.from = current
		_fades[id] = now + FADE_MS
		var stamp := fposmod(float(now) * 0.001, 256.0)
		_show(id, current, 2.0, stamp)
		_show(id, lod, 1.0, stamp)
	if lod != FAR or not snap:
		_detailed[id] = true
	return true


func _finish_fades(now: int) -> void:
	for id: int in _fades.keys():
		if now >= int(_fades[id]):
			_end_fade(id)
			_scan_pending = true


func _end_fade(id: int) -> void:
	var entry := entries[id]
	_remove(id, entry.from)
	_show(id, entry.lod, 0.0, 0.0)
	entry.from = -1
	_fades.erase(id)
	if entry.lod == FAR:
		_detailed.erase(id)


func _set_clock(now: int) -> void:
	var value := fposmod(float(now) * 0.001, 256.0)
	for material in _materials:
		material.set_shader_parameter("tree_clock", value)


static func _instance_data(entry: Dictionary, phase: float, stamp: float) -> Color:
	return Color(float(entry.species), entry.seed, phase, stamp)


func _show(id: int, lod: int, phase: float, stamp: float) -> void:
	var entry := entries[id]
	var data := _instance_data(entry, phase, stamp)
	if lod == FAR:
		entry.far.set_instance_transform(entry.far_slot, entry.local)
		entry.far.set_instance_custom_data(entry.far_slot, data)
	else:
		_pools[lod * SPECIES.size() + entry.species].put(id, entry.world, data)


func _remove(id: int, lod: int) -> void:
	var entry := entries[id]
	if lod == FAR:
		var hidden: Transform3D = entry.local
		hidden.basis = Basis.from_scale(Vector3.ZERO)
		entry.far.set_instance_transform(entry.far_slot, hidden)
	else:
		_pools[lod * SPECIES.size() + entry.species].erase(id)


func pool_count(lod: int) -> int:
	var count := 0
	for i in SPECIES.size():
		count += _pools[lod * SPECIES.size() + i].ids.size()
	return count


class TreePool extends RefCounted:
	var node: MultiMeshInstance3D
	var ids: Array[int] = []
	var transforms: Array[Transform3D] = []
	var custom: Array[Color] = []
	var slots := {}

	func _init(instance: MultiMeshInstance3D) -> void:
		node = instance

	func put(id: int, pose: Transform3D, data: Color) -> void:
		var slot := int(slots.get(id, ids.size()))
		if not slots.has(id):
			slots[id] = slot
			ids.append(id)
			transforms.append(pose)
			custom.append(data)
			node.multimesh.set_instance_transform(slot, pose)
			node.multimesh.visible_instance_count = ids.size()
		else:
			custom[slot] = data
		node.multimesh.set_instance_custom_data(slot, data)

	func erase(id: int) -> void:
		var last := ids.size() - 1
		var slot := int(slots[id])
		if slot != last:
			ids[slot] = ids[last]
			transforms[slot] = transforms[last]
			custom[slot] = custom[last]
			slots[ids[slot]] = slot
			node.multimesh.set_instance_transform(slot, transforms[slot])
			node.multimesh.set_instance_custom_data(slot, custom[slot])
		# Clear the removed slot so distant retired instances don't enlarge bounds.
		node.multimesh.set_instance_transform(last, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
		ids.pop_back()
		transforms.pop_back()
		custom.pop_back()
		slots.erase(id)
		node.multimesh.visible_instance_count = ids.size()
