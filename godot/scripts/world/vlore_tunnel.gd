extends Node3D
## The Uji i Ftohtë tunnel: the baked mesh from tools/build_vlore_tunnel.gd
## (cliff, portal collars, lined bore with emissive light strips; world
## coordinates on the race spline), its materials, a breakwater of boulders
## along the sea side of both approaches, and scrub where the cliff meets the
## hillside. No real-time lights: the strips are emissive.

const MODEL := preload("res://assets/cities/vlore/tunnel.glb")
const ROCK := Color("#a3a098")
## Breakwater: boulders between the coastal wall and the water, per metre of
## each approach; scrub and loose rock along the inland seam.
const BREAKWATER_REACH := 95.0
const BOULDER_EVERY := 1.6
const SCRUB_COUNT := 26
const SEAM_ROCKS := 12


func build(track: RaceTrack, portals: Array, reverse: bool, terrain: Terrain) -> void:
	var a: Array = portals[1 if reverse else 0]
	var b: Array = portals[0 if reverse else 1]
	var start := track.locate_xz(a[0], a[1]).x
	var length := track.mod_s(track.locate_xz(b[0], b[1]).x - start)
	var inland := 1.0 if reverse else -1.0
	var model := MODEL.instantiate()
	var materials := _materials(terrain)
	var props := {}
	for child: Node in model.get_children():
		var mesh_node := child as MeshInstance3D
		if mesh_node == null:
			continue
		var at := (model as Node3D).transform * mesh_node.transform
		model.remove_child(mesh_node)
		mesh_node.owner = null
		if String(mesh_node.name).begins_with("Boulder") or String(mesh_node.name).begins_with("Scrub"):
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
	model.free()
	_seawall(track, start, length, -inland, terrain)
	_breakwater(track, start, length, -inland, terrain, props, materials)
	_seam(track, start, length, inland, terrain, props, materials)


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
	var masonry := StandardMaterial3D.new()
	masonry.resource_name = "portal_masonry"
	masonry.albedo_texture = preload("res://assets/textures/concrete_wall_diff.jpg")
	masonry.albedo_color = Color(0.86, 0.83, 0.78)
	masonry.roughness = 0.86
	masonry.uv1_triplanar = true
	masonry.uv1_world_triplanar = true
	masonry.uv1_scale = Vector3.ONE * 0.35
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
	scrub.vertex_color_use_as_albedo = false
	scrub.albedo_texture = preload("res://assets/textures/grass_diff.jpg")
	scrub.albedo_color = Color(0.42, 0.50, 0.30)
	scrub.roughness = 0.95
	scrub.uv1_triplanar = true
	scrub.uv1_world_triplanar = true
	scrub.uv1_scale = Vector3.ONE * 0.8
	return {"cliff_rock": rock, "portal_masonry": masonry, "tunnel_interior": lining,
		"ceiling_lights": strips, "shoreline": shore, "scrub": scrub}


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


## Scrub and a few loose rocks where the cliff's inland foot meets the hill.
func _seam(track: RaceTrack, start: float, length: float, inland: float, terrain: Terrain, props: Dictionary, materials: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7311
	var bushes := [[], []]
	var rocks := []
	for i in SCRUB_COUNT + SEAM_ROCKS:
		var s := start - 12.0 + rng.randf() * (length + 24.0)
		var p := track.pos(s, inland * rng.randf_range(26.0, 46.0))
		p.y = terrain.height_at(p.x, p.z) - 0.1
		var scale := rng.randf_range(0.8, 1.3)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(scale, scale * rng.randf_range(0.8, 1.2), scale))
		if i < SCRUB_COUNT:
			bushes[i % 2].append(Transform3D(basis, p))
		else:
			rocks.append(Transform3D(basis.scaled(Vector3.ONE * 0.55), p))
	for i in 2:
		_batch("SeamScrub%d" % i, props.get("Scrub%d" % i), bushes[i], materials.scrub, 380.0)
	_batch("SeamRocks", props.get("Boulder0"), rocks, materials.cliff_rock, 380.0)


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
