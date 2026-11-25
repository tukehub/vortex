class_name VloreInfill
extends Node3D
## Apartment blocks (pallate) along the side streets west of Vlorë's
## boulevard, behind the Muradie Mosque and Teatri Petro Marko, where the
## mapped city is thin: infill.json from tools/pipeline/vlore_infill.py.
## Each block: plastered walls with the city facade shader's window grid and
## CC0 window module (shaders/facade.gdshader, as in the other cities'
## buildings), a ground floor of shopfronts, a flat roof behind a parapet
## with a stair-and-lift housing. Heights follow the ground.

const DATA := "res://assets/cities/%s/infill.json"
const FLOOR_H := 3.1
const GROUND_FLOOR := 3.6
const PARAPET := 0.9
const REACH := 1600.0
## Plaster colours seen across Vlorë's blocks: cream, ochre, salmon, white,
## pale yellow, grey-blue.
const TINTS := [Color(0.93, 0.86, 0.72), Color(0.9, 0.73, 0.52), Color(0.92, 0.67, 0.57),
	Color(0.95, 0.94, 0.9), Color(0.95, 0.88, 0.62), Color(0.78, 0.82, 0.85)]

var blocks := 0
var facade_mat: ShaderMaterial


static func path_for(city_id: String) -> String:
	return DATA % city_id


func build(city_id: String, terrain: Terrain) -> void:
	name = "VloreInfill"
	var path := path_for(city_id)
	if not FileAccess.file_exists(path):
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var roofs := ArchKit.begin()
	for b: Array in data.get("blocks", []):
		_block(walls, roofs, b, terrain)
		blocks += 1
	if blocks == 0:
		return
	facade_mat = ShaderMaterial.new()
	facade_mat.shader = Buildings.FACADE_SHADER
	facade_mat.set_shader_parameter("tex_facade", load("res://assets/textures/urban_facade_tile.png"))
	facade_mat.set_shader_parameter("tex_facade_small", load("res://assets/textures/urban_facade_small.png"))
	facade_mat.set_shader_parameter("tex_facade_double", load("res://assets/textures/urban_facade_double.png"))
	facade_mat.set_shader_parameter("tex_plaster", load("res://assets/textures/plaster_diff.jpg"))
	facade_mat.set_shader_parameter("tex_plaster_n", load("res://assets/textures/plaster_nor.jpg"))
	facade_mat.set_shader_parameter("tex_concrete", load("res://assets/textures/concrete_wall_diff.jpg"))
	facade_mat.set_shader_parameter("floor_h", FLOOR_H)
	facade_mat.set_shader_parameter("tint_amount", 0.8)
	var wall_node := MeshInstance3D.new()
	wall_node.name = "InfillWalls"
	wall_node.mesh = walls.commit()
	wall_node.material_override = facade_mat
	wall_node.visibility_range_end = REACH
	add_child(wall_node)
	var roof_mat := ArchKit.material(preload("res://assets/textures/concrete_diff.jpg"),
		preload("res://assets/textures/concrete_nor.jpg"), null, 3.0, Color(0.82, 0.8, 0.77), 0.5)
	roof_mat.roughness = 0.92
	roofs.generate_tangents()
	add_child(ArchKit.node(roofs, roof_mat, "InfillRoofs", REACH))


func set_env(night: float, wet: float) -> void:
	if facade_mat != null:
		facade_mat.set_shader_parameter("night", night)
		facade_mat.set_shader_parameter("wetness", wet)


func _block(walls: SurfaceTool, roofs: SurfaceTool, b: Array, terrain: Terrain) -> void:
	var c := Vector2(float(b[0]), float(b[1]))
	var yaw := float(b[2])
	var w := float(b[3])
	var d := float(b[4])
	var floors := int(b[5])
	var tint: Color = TINTS[int(b[6]) % TINTS.size()]
	var t := Vector2(cos(yaw), sin(yaw))
	var n := Vector2(-t.y, t.x)
	var corners: Array[Vector2] = [c - t * w * 0.5 - n * d * 0.5, c + t * w * 0.5 - n * d * 0.5,
		c + t * w * 0.5 + n * d * 0.5, c - t * w * 0.5 + n * d * 0.5]
	var lo := INF
	var hi := -INF
	for q in corners:
		var g := terrain.height_at(q.x, q.y) if terrain != null else 0.0
		lo = minf(lo, g)
		hi = maxf(hi, g)
	# The ground floor stands on the highest corner; the walls reach down past
	# the lowest so no corner floats.
	var floor_y := hi + 0.15
	var foot := lo - 0.8
	var top := floor_y + GROUND_FLOOR + (floors - 1) * FLOOR_H
	var u := 0.0
	for i in 4:
		var a := corners[i]
		var e := corners[(i + 1) % 4]
		var length := a.distance_to(e)
		var mid2 := (a + e) * 0.5 - c
		var normal := Vector3(mid2.x, 0, mid2.y).normalized()
		# UV: metres along, metres up from the ground floor (the shader's
		# shopfront row is the first FLOOR_H); a hashed offset per block.
		var quad := [[Vector3(a.x, foot, a.y), Vector2(u, foot - floor_y)], [Vector3(e.x, foot, e.y), Vector2(u + length, foot - floor_y)],
			[Vector3(e.x, top, e.y), Vector2(u + length, top - floor_y)], [Vector3(a.x, top, a.y), Vector2(u, top - floor_y)]]
		var pa: Vector3 = quad[0][0]
		var pb: Vector3 = quad[1][0]
		var pd: Vector3 = quad[3][0]
		var order := [0, 2, 1, 0, 3, 2] if (pb - pa).cross(pd - pa).dot(normal) > 0.0 else [0, 1, 2, 0, 2, 3]
		for k: int in order:
			walls.set_normal(normal)
			walls.set_color(Color(tint.r, tint.g, tint.b, 0.0))
			walls.set_uv(quad[k][1])
			walls.add_vertex(quad[k][0])
		u += length
	# Flat roof inside a parapet, and the stair-and-lift housing.
	var inset := 0.3
	var r: Array[Vector3] = []
	for q in corners:
		var toward := (c - q).normalized() * inset
		r.append(Vector3(q.x + toward.x, top + 0.02, q.y + toward.y))
	ArchKit.wall_quad(roofs, r[0], r[1], r[2], r[3], Color.WHITE, Vector3.UP)
	for i in 4:
		var a := Vector3(corners[i].x, top, corners[i].y)
		var e := Vector3(corners[(i + 1) % 4].x, top, corners[(i + 1) % 4].y)
		var mid := (a + e) * 0.5
		var out := Vector3(mid.x - c.x, 0, mid.z - c.y).normalized()
		ArchKit.wall_quad(roofs, a, e, e + Vector3.UP * PARAPET, a + Vector3.UP * PARAPET, Color(0.95, 0.93, 0.9), out)
		ArchKit.wall_quad(roofs, a + Vector3.UP * PARAPET, e + Vector3.UP * PARAPET, r[(i + 1) % 4] + Vector3.UP * (PARAPET - 0.02), r[i] + Vector3.UP * (PARAPET - 0.02), Color(0.9, 0.9, 0.9), Vector3.UP)
		ArchKit.wall_quad(roofs, r[(i + 1) % 4], r[i], r[i] + Vector3.UP * (PARAPET - 0.02), r[(i + 1) % 4] + Vector3.UP * (PARAPET - 0.02), Color(0.85, 0.85, 0.85), -out)
	var basis := Basis(Vector3.UP, -yaw)
	ArchKit.box(roofs, Vector3(c.x, top + 1.4, c.y) + basis * Vector3(w * 0.18, 0, 0), Vector3(4.2, 2.8, 3.4), Color(0.92, 0.9, 0.86), basis)
