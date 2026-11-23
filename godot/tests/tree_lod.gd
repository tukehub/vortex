extends Node3D
## Deterministic timestamps exercise real pool state without waiting on wall time.

func _ready() -> void:
	Quality.set_preset("high")
	var trees := TiranaTrees.new()
	add_child(trees)
	trees.build([[12, 0, 0, 1], [68, 0, 0, 1], [104, 0, 0, 1],
		[172, 0, 0, 1], [1000, 0, 0, 1]], null)
	assert(trees.update_focus(Vector3.ZERO, Vector3.RIGHT, false, 0))
	assert(_lods(trees) == [0, 0, 1, 2, 2])
	assert(trees.pool_count(0) == 2 and trees.pool_count(1) == 1)
	assert(not trees.update_focus(Vector3(1.0, 0, 0), Vector3.RIGHT, false, 20))
	assert(trees.update_focus(Vector3(6, 0, 0), Vector3.RIGHT, false, 36))
	assert(trees.last_candidates < trees.entries.size(), "the remote cell was not rescanned")
	trees.update_focus(Vector3(-13, 0, 0), Vector3.RIGHT, false, 120)
	assert(trees.entries[1].lod == 1 and trees.entries[1].from == 0)
	assert(trees.pool_count(0) == 2, "the outgoing near model survives the dither interval")
	trees.update_focus(Vector3(-13, 0, 0), Vector3.RIGHT, false, 305)
	assert(trees.entries[1].from == -1 and trees.pool_count(0) == 1)
	trees.update_focus(Vector3(1000, 0, 0), Vector3.LEFT, false, 310)
	assert(_lods(trees) == [2, 2, 2, 2, 0])
	assert(trees.pool_count(0) == 1 and trees.pool_count(1) == 0)
	trees.exclude(4)
	assert(trees.entries[4].excluded and trees.pool_count(0) == 0)
	trees.update_focus(Vector3(20, 0, 0), Vector3.RIGHT, true, 400)
	assert(trees.entries[3].lod == 1)
	trees.update_focus(Vector3(0, 0, 0), Vector3.RIGHT, false, 490)
	assert(trees.entries[3].lod == 2 and trees.entries[3].from == 1)
	trees.update_focus(Vector3.ZERO, Vector3.RIGHT, false, 680)
	assert(trees.entries[3].from == -1)
	Quality.set_preset("low")
	trees.update_focus(Vector3.ZERO, Vector3.RIGHT, true, 700)
	assert(_lods(trees) == [0, 1, 2, 2, 2] and Quality.p.tree_wind_m == 0.0)
	Quality.set_preset("high")
	Quality.set_pressure_stage(2)
	assert(Quality.p.tree_wind_m == 0.0 and not Quality.p.tree_near_shadows)
	assert(Quality.p.tree_near_m < 70.0 and Quality.p.tree_mid_limit < 144)
	Quality.set_pressure_stage(0)
	assert(Quality.p.tree_wind_m > 0.0 and Quality.p.tree_near_shadows)

	var dense := TiranaTrees.new()
	add_child(dense)
	var rows := []
	for id in 600:
		var a := float(id) * 2.39996
		var radius := 6 + float(id % 155)
		rows.append([cos(a) * radius, 0, sin(a) * radius, 1.0])
	dense.build(rows, null)
	dense.update_focus(Vector3.ZERO, Vector3.RIGHT, true, 1)
	assert(dense.pool_count(0) == Quality.p.tree_near_limit)
	assert(dense.pool_count(1) == Quality.p.tree_mid_limit)
	var species := {}
	var materials := {}
	for pool in dense._pools:
		assert(pool.node.multimesh.mesh.get_surface_count() == 2)
		for i in 2:
			var mesh := pool.node.multimesh.mesh
			materials[mesh.surface_get_material(i).get_instance_id()] = true
		for id in pool.ids:
			species[dense.entries[id].species] = true
	assert(species.size() == 3 and materials.size() == 2 and dense._materials.size() == 3)
	# Verify actual element counts, separately from projected coverage.
	assert(_triangles(dense._pools[0].node.multimesh.mesh) == 566)
	assert(_triangles(dense._pools[3].node.multimesh.mesh) == 171)
	var saved: Transform3D = dense.entries[125].world
	dense.update_focus(Vector3(8, 0, 0), Vector3.RIGHT, false, 45)
	assert(dense._fades.size() <= TiranaTrees.MAX_CHANGES)
	assert(dense.entries[125].world.is_equal_approx(saved))
	print("TREE LOD: three tiers, local scans, dither lifetime, snap, pressure, shared materials and caps passed")
	get_tree().quit()


func _lods(trees: TiranaTrees) -> Array:
	return trees.entries.map(func(entry: Dictionary): return int(entry.lod))


func _triangles(mesh: Mesh) -> int:
	var count := 0
	for surface in mesh.get_surface_count():
		count += mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX].size()
	return roundi(count / 3.0)
