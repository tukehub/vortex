class_name Sea
extends MeshInstance3D
## Opaque water at the city's baked sea level. The shoreline distance map
## stays in world coordinates as the high-detail grid follows the camera.

const SHADER := preload("res://shaders/sea.gdshader")
## Plane edge in metres: covers the chase camera's 6 km far plane from anywhere
## on the near grid.
const SIZE := 26000.0

var mat: ShaderMaterial
var detailed_grid: Mesh
var flat_grid: PlaneMesh
var horizon: MeshInstance3D


## Builds the water for `terrain`; returns false (and builds nothing) for a
## city without baked water.
func build(terrain: Terrain, bay := false) -> bool:
	if not terrain.has_water:
		return false
	name = "Sea"
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE, SIZE)
	plane.subdivide_width = 0
	plane.subdivide_depth = 0
	mesh = plane
	position = Vector3(0.0, terrain.water_surface, 0.0)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	# CC0 wave ripples (tools/build_wave_normals.py).
	mat.set_shader_parameter("wave_nor", preload("res://assets/textures/water_waves_nor.png"))
	mat.set_shader_parameter("use_waves", true)
	mat.set_shader_parameter("shore", terrain.shore_tex)
	mat.set_shader_parameter("shore_origin", Vector2(float(terrain.near.x0), float(terrain.near.z0)))
	mat.set_shader_parameter("shore_size", float(terrain.near.cell) * (int(terrain.near.n) - 1))
	mat.set_shader_parameter("shore_span", terrain.water_span)
	material_override = mat
	if bay:
		flat_grid = plane
		detailed_grid = _water_grid()
		_build_horizon()
		Quality.budget_changed.connect(_quality)
		_quality()
	else:
		# Lake surfaces stay fixed, including when built before entering the tree.
		process_mode = Node.PROCESS_MODE_DISABLED
	return true


func set_env(wet: float, night: float) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("wetness", wet)
	mat.set_shader_parameter("night", night)

# A 128 m grid and four coplanar trapezoids share the same water material.
# Boundary vertices stay at sea level, including along the outer quads.
func _water_grid() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cells := 32
	for z in cells:
		for x in cells:
			for corner in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.RIGHT, Vector2i.ONE, Vector2i.DOWN]:
				st.add_vertex(Vector3((x + corner.x) * 4 - 64, 0, (z + corner.y) * 4 - 64))
	for side in 4:
		var rotation_basis := Basis(Vector3.UP, side * PI / 2.0)
		var half_size := SIZE * 0.5
		var a := Vector3(-64, 0, -64)
		var b := Vector3(64, 0, -64)
		var c := Vector3(-half_size, 0, -half_size)
		var d := Vector3(half_size, 0, -half_size)
		for point in [c, d, a, d, b, a]:
			st.add_vertex(rotation_basis * point)
	st.index()
	return st.commit()

func _quality() -> void:
	var tier := maxi(0, ["low", "medium", "high"].find(Quality.preset) - Quality.pressure_stage)
	mat.set_shader_parameter("tier", tier)
	if tier == 2:
		mesh = detailed_grid
	else:
		mesh = flat_grid

func _process(_dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		position.x = snappedf(cam.global_position.x, 4.0)
		position.z = snappedf(cam.global_position.z, 4.0)
		horizon.global_position = Vector3(cam.global_position.x, position.y, cam.global_position.z)

func _build_horizon() -> void:
	# Angular relief compressed inside the chase camera's far clip. Sazan is
	# detached to the northwest; Karaburun rises across the western bay.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for profile in [[-40, -37, -32, -29, -24, -20], [-18, -12, -3, 8, 20, 32, 45, 60]]:
		var heights := [0, 19, 51, 59, 35, 0] if profile.size() == 6 else [0, 32, 72, 95, 154, 178, 130, 45]
		for i in range(profile.size() - 1):
			var a := Vector3(-cos(deg_to_rad(profile[i])), 0, sin(deg_to_rad(profile[i]))) * 3000
			var b := Vector3(-cos(deg_to_rad(profile[i+1])), 0, sin(deg_to_rad(profile[i+1]))) * 3000
			for point in [a + Vector3.DOWN * 20, b + Vector3.DOWN * 20, a + Vector3.UP * heights[i], b + Vector3.DOWN * 20, b + Vector3.UP * heights[i+1], a + Vector3.UP * heights[i]]:
				st.add_vertex(point)
	horizon = MeshInstance3D.new()
	horizon.mesh = st.commit()
	var haze := StandardMaterial3D.new()
	haze.cull_mode = BaseMaterial3D.CULL_DISABLED
	haze.albedo_color = Color("#77929b")
	horizon.material_override = haze
	horizon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(horizon)
