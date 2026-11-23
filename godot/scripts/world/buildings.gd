class_name Buildings
extends Node3D
## Loads <city>/buildings.glb (chunked by the pipeline), swaps the two
## importer materials (facade / roof) for the facade shader and a roof
## material, and applies per-chunk visibility ranges from the quality preset.

const FACADE_SHADER := preload("res://shaders/facade.gdshader")
const SHOWCASE_SHADER := preload("res://shaders/showcase_facade.gdshader")

var frontages: Node3D
var facade_mat: ShaderMaterial
var skyline_mat: ShaderMaterial
var roof_mat: Material
var chunk_nodes: Array[MeshInstance3D] = []
var showcase_mat: ShaderMaterial
var showcase_chunks: Array[MeshInstance3D] = []


func load_city(city_id: String) -> void:
	var path := "res://assets/cities/%s/buildings.glb" % city_id
	if not ResourceLoader.exists(path):
		push_warning("no buildings for " + city_id)
		return
	facade_mat = ShaderMaterial.new()
	if city_id == "vlore":
		facade_mat.shader = preload("res://shaders/vlore_facade.gdshader")
		facade_mat.set_shader_parameter("atlas", load("res://assets/cities/vlore/facade_atlas.png"))
		frontages = load("res://scripts/world/vlore_frontages.gd").new()
		add_child(frontages)
	else:
		facade_mat.shader = FACADE_SHADER
		facade_mat.set_shader_parameter("tex_facade", load("res://assets/textures/urban_facade_tile.png"))
		facade_mat.set_shader_parameter("tex_facade_small", load("res://assets/textures/urban_facade_small.png"))
		facade_mat.set_shader_parameter("tex_facade_double", load("res://assets/textures/urban_facade_double.png"))
		facade_mat.set_shader_parameter("tex_plaster", load("res://assets/textures/plaster_diff.jpg"))
		facade_mat.set_shader_parameter("tex_plaster_n", load("res://assets/textures/plaster_nor.jpg"))
		facade_mat.set_shader_parameter("tex_concrete", load("res://assets/textures/concrete_wall_diff.jpg"))
	if frontages:
		var roof := ShaderMaterial.new()
		roof.shader = preload("res://shaders/vlore_roof.gdshader")
		roof.set_shader_parameter("tiles", preload("res://assets/textures/rooftiles_diff.jpg"))
		roof_mat = roof
	else:
		roof_mat = StandardMaterial3D.new()
		roof_mat.vertex_color_use_as_albedo = true
		roof_mat.albedo_texture = load("res://assets/textures/rooftiles_diff.jpg")
		roof_mat.uv1_triplanar = true
		roof_mat.uv1_scale = Vector3(0.12, 0.12, 0.12)
		roof_mat.roughness = 0.85

	var scene: PackedScene = load(path)
	var inst := scene.instantiate()
	add_child(inst)
	_collect(inst)
	if frontages:
		_load_vlore_skyline()
	if city_id == "tirane":
		facade_mat.set_shader_parameter("window_glow", 1.28)
		_load_showcase()
	apply_quality()
	Quality.preset_changed.connect(func(_p): apply_quality())


func _load_vlore_skyline() -> void:
	skyline_mat = ShaderMaterial.new()
	skyline_mat.shader = preload("res://shaders/vlore_skyline.gdshader")
	var scene: PackedScene = load("res://assets/cities/vlore/skyline.glb")
	var skyline := scene.instantiate()
	add_child(skyline)
	for child in skyline.find_children("*", "MeshInstance3D", true, false):
		var chunk := child as MeshInstance3D
		chunk.material_override = skyline_mat
		chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.lod_bias = .35
		var radius := chunk.get_aabb().size.length() * .5
		chunk.visibility_range_begin = maxf(0., 460. - radius)
		chunk.visibility_range_end = 2040. + radius
		chunk.visibility_range_begin_margin = 0.
		chunk.visibility_range_end_margin = 0.


func _load_showcase() -> void:
	var path := "res://assets/cities/tirane/showcase_facades.glb"
	if not ResourceLoader.exists(path):
		return
	var scene: PackedScene = load(path)
	var detail := scene.instantiate()
	add_child(detail)
	showcase_mat = ShaderMaterial.new()
	showcase_mat.shader = SHOWCASE_SHADER
	showcase_mat.set_shader_parameter("plaster_map", preload("res://assets/textures/plaster_diff.jpg"))
	for child in detail.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		mesh.material_override = showcase_mat
		# The original building volumes already cast the large directional shadows.
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		showcase_chunks.append(mesh)


func _collect(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh := mi.mesh
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i)
			var name := m.resource_name.to_lower() if m != null else ""
			if name.find("roof") >= 0:
				mi.set_surface_override_material(i, roof_mat)
			else:
				mi.set_surface_override_material(i, facade_mat)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		chunk_nodes.append(mi)
	for c in n.get_children():
		_collect(c)


func apply_quality() -> void:
	var dist := float(Quality.p.building_dist)
	for mi in chunk_nodes:
		if frontages:
			# Ranges are measured from the AABB centre. Include its radius so
			# every pixel finishes the shader handoff before engine culling.
			mi.visibility_range_end = 540. + mi.get_aabb().size.length() * .5
			mi.visibility_range_end_margin = 0.
			continue
		mi.visibility_range_end = dist
		mi.visibility_range_end_margin = dist * 0.1
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

	var detail_dist := 120.0 if Quality.preset == "low" else (175.0 if Quality.preset == "medium" else 235.0)
	for mesh in showcase_chunks:
		mesh.visibility_range_end = detail_dist
		mesh.visibility_range_end_margin = 18.0


func set_env(night: float, wet: float) -> void:
	if facade_mat:
		facade_mat.set_shader_parameter("night", night)
		facade_mat.set_shader_parameter("wetness", wet)

	if skyline_mat:
		skyline_mat.set_shader_parameter("night", night)
		skyline_mat.set_shader_parameter("wetness", wet)
	if showcase_mat:
		showcase_mat.set_shader_parameter("night", night)
		showcase_mat.set_shader_parameter("wetness", wet)
	if frontages:
		frontages.material.set_shader_parameter("night", night)
		frontages.material.set_shader_parameter("wetness", wet)
