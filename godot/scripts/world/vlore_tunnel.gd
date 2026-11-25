extends Node3D
## Uji i Ftohtë's baked limestone cut, concrete portals and original bore.
## Both directions share the same baked surfaces and decorative placements.

const MODEL := preload("res://assets/cities/vlore/tunnel.glb")
const ROCK := Color("#a3a098")
## Breakwater: boulders between the coastal wall and the water, per metre of
## each approach; scrub and loose rock along the inland seam.
const BREAKWATER_REACH := 95.0
const BOULDER_EVERY := 1.6
var _shadow_near: Array[MeshInstance3D] = []
var _shadow_high: Array[MeshInstance3D] = []


func build(track: RaceTrack, portals: Array, reverse: bool, terrain: Terrain) -> void:
	var a: Array = portals[1 if reverse else 0]
	var b: Array = portals[0 if reverse else 1]
	var start := track.locate_xz(a[0], a[1]).x
	var length := track.mod_s(track.locate_xz(b[0], b[1]).x - start)
	var inland := 1.0 if reverse else -1.0
	var model := MODEL.instantiate()
	var materials := _materials(terrain)
	var props := {}
	var talus := []
	var maquis := [[], []]
	var shrub_index := 0
	for child: Node3D in model.get_children():
		var at := (model as Node3D).transform * child.transform
		if String(child.name).begins_with("TalusSite"):
			talus.append(at)
			continue
		if String(child.name).begins_with("MaquisSite"):
			maquis[shrub_index % 2].append(at)
			shrub_index += 1
			continue
		var mesh_node := child as MeshInstance3D
		if mesh_node == null:
			continue
		model.remove_child(mesh_node)
		mesh_node.owner = null
		if String(mesh_node.name).begins_with("Boulder") or String(mesh_node.name).begins_with("Scrub") or mesh_node.name == "TalusScan":
			props[String(mesh_node.name)] = mesh_node.mesh
			mesh_node.free()
			continue
		mesh_node.transform = at
		for i in mesh_node.mesh.get_surface_count():
			var slot := mesh_node.mesh.surface_get_material(i).resource_name
			mesh_node.set_surface_override_material(i, materials.get(slot, materials.cliff_rock))
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_node.visibility_range_end = 620.0 if mesh_node.name == "TunnelBore" else 1100.0
		add_child(mesh_node)
		if mesh_node.name == "Portals":
			_shadow_near.append(mesh_node)
		elif mesh_node.name == "WingWalls":
			_shadow_high.append(mesh_node)
	model.free()
	_seawall(track, start, length, -inland, terrain)
	_breakwater(track, start, length, -inland, terrain, props, materials)
	for i in 2:
		_batch("SeamScrub%d" % i, props.get("Scrub%d" % i), maquis[i], materials.scrub, 210.0)
	_batch("SeamRocks", props.get("TalusScan"), talus, materials.debris, 250.0)
	Quality.budget_changed.connect(_update_shadows)
	_update_shadows()


func _update_shadows() -> void:
	var portal_mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if Quality.preset != "low" and Quality.pressure_stage < 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var wing_mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if Quality.preset == "high" and Quality.pressure_stage == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for mesh in _shadow_near:
		mesh.cast_shadow = portal_mode
	for mesh in _shadow_high:
		mesh.cast_shadow = wing_mode


func _materials(terrain: Terrain) -> Dictionary:
	var rock := StandardMaterial3D.new()
	rock.resource_name = "cliff_rock"
	# Limestone (marble_rock_03, 1K): world triplanar, so strata and cracks
	# run the same over every face of the cliff, never stretched.
	rock.albedo_texture = preload("res://assets/textures/marble_rock_diff.jpg")
	rock.normal_enabled = true
	rock.normal_texture = preload("res://assets/textures/marble_rock_nor.jpg")
	rock.roughness_texture = preload("res://assets/textures/marble_rock_rough.jpg")
	rock.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	rock.uv1_triplanar = true
	rock.uv1_world_triplanar = true
	rock.uv1_triplanar_sharpness = 4.0
	rock.uv1_scale = Vector3.ONE * 0.12
	var cliff := ShaderMaterial.new()
	cliff.shader = preload("res://shaders/vlore_limestone.gdshader")
	cliff.set_shader_parameter("stone_map", rock.albedo_texture)
	cliff.set_shader_parameter("rock_arm", preload("res://assets/textures/limestone_arm.jpg"))
	cliff.set_shader_parameter("scrub_map", preload("res://assets/textures/grass_diff.jpg"))
	cliff.set_shader_parameter("landscape", preload("res://assets/cities/vlore/ground_macro.png"))
	cliff.set_shader_parameter("water_y", terrain.water_surface)
	var masonry := ShaderMaterial.new()
	masonry.shader = preload("res://shaders/vlore_portal_concrete.gdshader")
	masonry.set_shader_parameter("concrete", preload("res://assets/textures/concrete_wall_diff.jpg"))
	masonry.set_shader_parameter("concrete_normal", preload("res://assets/textures/concrete_wall_nor.jpg"))
	var lining := StandardMaterial3D.new()
	lining.resource_name = "tunnel_interior"
	lining.albedo_texture = preload("res://assets/textures/concrete_diff.jpg")
	lining.albedo_color = Color(0.58, 0.57, 0.55)
	lining.roughness = 0.82
	lining.uv1_triplanar = true
	lining.uv1_world_triplanar = true
	lining.uv1_scale = Vector3.ONE * 0.25
	# The strips' warm light on the concrete, without a real light.
	lining.emission_enabled = true
	lining.emission = Color(0.42, 0.33, 0.22)
	lining.emission_energy_multiplier = 0.35
	var strips := StandardMaterial3D.new()
	strips.resource_name = "ceiling_lights"
	strips.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	strips.albedo_color = Color(1.0, 0.86, 0.62)
	strips.emission_enabled = true
	strips.emission = Color(1.0, 0.80, 0.52)
	strips.emission_energy_multiplier = 2.4
	var shore := ShaderMaterial.new()
	shore.shader = preload("res://shaders/shoreline_rock.gdshader")
	shore.set_shader_parameter("albedo_tex", rock.albedo_texture)
	shore.set_shader_parameter("normal_tex", rock.normal_texture)
	shore.set_shader_parameter("rough_tex", rock.roughness_texture)
	shore.set_shader_parameter("water_y", terrain.water_surface if terrain.has_water else -1.2)
	var scrub := StandardMaterial3D.new()
	scrub.resource_name = "scrub"
	scrub.vertex_color_use_as_albedo = true
	scrub.albedo_texture = preload("res://assets/foliage/tirana/leaf_sprays.png")
	scrub.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	scrub.alpha_scissor_threshold = .36
	scrub.cull_mode = BaseMaterial3D.CULL_DISABLED
	scrub.roughness = .95
	return {"cliff_rock": cliff, "portal_masonry": masonry, "tunnel_interior": lining,
		"ceiling_lights": strips, "shoreline": shore, "scrub": scrub, "debris": rock}


## Boulders between the coastal wall and the sea, both approaches: random Y
## turn, non-uniform 0.8-1.3 scale, settled into the seabed or beach.
func _breakwater(track: RaceTrack, start: float, length: float, coast: float, terrain: Terrain, props: Dictionary, materials: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5170
	var groups := [[], [], [], []]
	for approach: Array in [[start - BREAKWATER_REACH, start - 2.0], [start + length + 2.0, start + length + BREAKWATER_REACH]]:
		var s: float = approach[0]
		while s < float(approach[1]):
			var d := coast * (track.half_w + 3.9 + rng.randf() * 3.6)
			var p := track.pos(s + rng.randf_range(-0.5, 0.5), d)
			var scale := Vector3(rng.randf_range(0.8, 1.3), rng.randf_range(0.8, 1.3), rng.randf_range(0.8, 1.3))
			p.y = terrain.height_at(p.x, p.z) - 0.35 * scale.y
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(scale)
			groups[rng.randi() % 4].append(Transform3D(basis, p))
			s += BOULDER_EVERY
	for i in 4:
		_batch("Breakwater%d" % i, props.get("Boulder%d" % i), groups[i], materials.shoreline, 420.0)


func _batch(node_name: String, mesh: Mesh, transforms: Array, material: Material, reach: float) -> void:
	if mesh == null or transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = mm
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = reach
	add_child(node)


func _seawall(track: RaceTrack, start: float, length: float, coast_side: float, terrain: Terrain) -> void:
	var st := LandmarkKit.begin()
	for approach in [start - 62.0, start + length]:
		for i in 20:
			var s: float = approach + i * 3.1
			var inside := (track.half_w + 0.95) * coast_side
			var outside := (track.half_w + 3.25) * coast_side
			var a := track.pos(s, outside) - position
			var b := track.pos(s + 3.1, outside) - position
			var a_base := a + position
			var b_base := b + position
			a_base.y = terrain.height_at(a_base.x, a_base.z) - 0.48
			b_base.y = terrain.height_at(b_base.x, b_base.z) - 0.48
			var tint := ROCK.lightened(0.13 + 0.04 * cos(i * 2.4))
			LandmarkKit.quad_facing(st, a_base - position, b_base - position, b, a, tint, track.normal(s) * coast_side)
			LandmarkKit.quad_facing(st, a, b, track.pos(s + 3.1, inside) - position, track.pos(s, inside) - position, tint.lightened(0.15), Vector3.UP)
	var mat := LandmarkKit.material()
	mat.albedo_texture = preload("res://assets/textures/concrete_wall_diff.jpg")
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3.ONE * 0.34
	add_child(LandmarkKit.mesh_node(st, mat, "CoastalRetainingWall", 600.0))
