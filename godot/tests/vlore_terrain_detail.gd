extends Node3D

const DETAIL := preload("res://scripts/world/terrain_detail.gd")
const TILE_SPAN := 120.0
var failures := 0


func _ready() -> void:
	Quality.set_preset("medium")
	var terrain := Terrain.new()
	add_child(terrain)
	terrain.load_city("vlore", null)
	check(terrain.detail.tiles.size() == 35 and terrain.detail_chunks.size() == 35, "localized bake loaded in all three hillside areas")
	check(terrain.chunks.size() == 225 and terrain.detail.tiles.size() * TILE_SPAN * TILE_SPAN < .01 * 9000.0 * 9000.0, "existing grid remains and detail covers less than 1%")
	var maximum_cut := 0.0
	var maximum_raise := 0.0
	var maximum_seam := 0.0
	var maximum_prop_error := 0.0
	var checked := 0
	for key: Vector2i in terrain.detail.tiles:
		var h: PackedFloat32Array = terrain.detail.tiles[key]
		var origin := terrain.detail.tile_origin(key)
		var chunk := terrain.detail_chunks[checked]
		check((chunk.get_aabb().size - Vector3(TILE_SPAN, chunk.get_aabb().size.y, TILE_SPAN)).length() < .01, "boundary of each independent culling chunk")
		check(chunk.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "detail uses the terrain shadow budget")
		var mesh_arrays := chunk.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = mesh_arrays[Mesh.ARRAY_VERTEX]
		check(vertices.size() == DETAIL.STRIDE * DETAIL.STRIDE, "full 1.875 m vertex grid")
		for j in range(0, DETAIL.STRIDE, 4):
			for i in range(0, DETAIL.STRIDE, 4):
				var at := origin + Vector2(i, j) * TILE_SPAN / DETAIL.CELLS
				var ground := reference_height(terrain, at)
				var delta := h[j*DETAIL.STRIDE+i] - ground
				maximum_cut = maxf(maximum_cut, -delta)
				maximum_raise = maxf(maximum_raise, delta)
				for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					if (i != 0 or offset.x != -1) and (i != DETAIL.CELLS or offset.x != 1) and (j != 0 or offset.y != -1) and (j != DETAIL.CELLS or offset.y != 1):
						continue
					if not terrain.detail.tiles.has(key + offset):
						maximum_seam = maxf(maximum_seam, absf(delta))
					else:
						var neighbor: PackedFloat32Array = terrain.detail.tiles[key + offset]
						var k := (j-offset.y*DETAIL.CELLS)*DETAIL.STRIDE + i-offset.x*DETAIL.CELLS
						maximum_seam = maxf(maximum_seam, absf(h[j*DETAIL.STRIDE+i]-neighbor[k]))
		var p := origin + Vector2(28.21, 64.17)
		var uv := (p-origin) / (TILE_SPAN / DETAIL.CELLS)
		var cell := Vector2i(uv.floor())
		var t := uv - Vector2(cell)
		var a := cell.y * DETAIL.STRIDE + cell.x
		var expected := vertices[a].y + t.x*(vertices[a+1].y-vertices[a].y) + t.y*(vertices[a+DETAIL.STRIDE].y-vertices[a].y)
		check(t.x + t.y < 1., "sample point is in the northwest triangle")
		maximum_prop_error = maxf(maximum_prop_error, absf(terrain.height_at(p.x, p.y)-expected))
		checked += 1
	check(maximum_seam < .001, "both internal tile seams and the outer DEM rim share elevations")
	check(maximum_raise > 2.0 and maximum_cut > 3.0, "ledges and erosion change real geometry")
	check(maximum_prop_error < .001, "environment sampling matches the rendered triangles")

	var near_indices := Terrain._lod_indices(DETAIL.CELLS, 1)
	var medium_indices := Terrain._lod_indices(DETAIL.CELLS, 4)
	var far_indices := Terrain._lod_indices(DETAIL.CELLS, 8)
	check(near_indices.size() == 24576 and medium_indices.size() < near_indices.size()/8 and far_indices.size() < medium_indices.size(), "LOD triangle budgets")
	for lod in [medium_indices, far_indices]:
		var referenced := {}
		for i in lod:
			referenced[i] = true
		for i in DETAIL.STRIDE:
			check(referenced.has(i) and referenced.has(i+DETAIL.CELLS*DETAIL.STRIDE)
				and referenced.has(i*DETAIL.STRIDE) and referenced.has(i*DETAIL.STRIDE+DETAIL.CELLS), "mixed LODs keep all four rim vertices")

	# The neighboring 600 m base chunk keeps all 15 m samples along a cut
	# even when its interior drops to the 60 m LOD.
	var base_lod := Terrain._lod_indices(Terrain.CHUNK, 4, {Vector2i.ONE: true})
	var used := {}
	for index in base_lod:
		used[index] = true
	var stride := Terrain.CHUNK + 1
	for i in range(8, 17):
		check(used.has(i*stride+8) and used.has(i*stride+16)
			and used.has(8*stride+i) and used.has(16*stride+i), "base LOD keeps every cut rim vertex")

	# The race track is independent of visual relief. Check both directions,
	# including the joint lanes, shoulders and both approaches to the bore.
	var max_road_delta := 0.0
	for reverse in [false, true]:
		var track := RaceTrack.load_city("vlore", reverse)
		for i in range(0, ceili(track.L), 3):
			for d in [-track.edge_left(i)-7.1, 0.0, track.edge_right(i)+7.1]:
				var p := track.pos(i, d)
				var y := terrain.detail.height_at(p.x, p.z)
				if not is_nan(y):
					max_road_delta = maxf(max_road_delta, absf(y-reference_height(terrain, Vector2(p.x,p.z))))
	check(max_road_delta < .002, "race and shoulder corridor relief is zero")
	var before := terrain.detail_chunks[0].lod_bias
	Quality.set_pressure_stage(3)
	check(terrain.detail_chunks[0].lod_bias < before, "thermal pressure brings coarse LOD closer")
	print("VLORE DETAIL: %d chunks, %+0.2f/%+0.2f m relief, seam %.5f m, road %.5f m, prop %.5f m"
		% [checked, maximum_raise, -maximum_cut, maximum_seam, max_road_delta, maximum_prop_error])
	get_tree().quit(1 if failures else 0)


func reference_height(terrain: Terrain, at: Vector2) -> float:
	var g := terrain.near
	return DETAIL._height(terrain.near_h, int(g.n),
		(at.x-float(g.x0))/float(g.cell), (at.y-float(g.z0))/float(g.cell))


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("CHECK FAILED: " + message)
