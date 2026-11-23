extends Node3D
## All street-level detail shares a small library of bay meshes. Partition
## instances spatially so a camera sees only a few MultiMesh draws per style.

const CITY := "res://assets/cities/vlore/"
const CELL := 48.0
var material := ShaderMaterial.new()


func _ready() -> void:
	material.shader = preload("res://shaders/vlore_facade.gdshader")
	material.set_shader_parameter("atlas", preload("res://assets/cities/vlore/facade_atlas.png"))
	material.set_shader_parameter("detail", true)
	var library := preload("res://assets/cities/vlore/facade_modules.glb").instantiate()
	var batches := {}
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string(CITY + "frontages.json"))
	for row: Array in rows:
		var family := int(row[0])
		var start := Vector3(row[1], row[2], row[3])
		if family >= 4:
			_append(batches, "Roof%d" % (family - 4), Transform3D(Basis.IDENTITY, start), Color.WHITE, Color(0, 0, 0))
			continue
		var axis := Vector3(row[4], 0, row[5])
		var width := float(row[6])
		var height := float(row[7])
		var basis := Basis(axis * width, Vector3.UP * height, axis.cross(Vector3.UP))
		var tint := Color(row[10] / 255., row[11] / 255., row[12] / 255.)
		for column in int(row[8]):
			for floor_index in int(row[9]):
				var variant := (2 if column % 3 == 0 else 1) if floor_index == 0 else 0
				var position := start + axis * (column * width) + Vector3.UP * (floor_index * height)
				_append(batches, "Bay%d_%d" % [family, variant], Transform3D(basis, position), tint, Color(family, variant, 0))
	for key: Array in batches:
		var instances: Array = batches[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = (library.get_node(key[1]) as MeshInstance3D).mesh
		mm.instance_count = instances.size()
		var cell: Vector2i = key[0]
		var origin := Vector3(cell.x + .5, 0, cell.y + .5) * CELL
		for i in instances.size():
			var transform: Transform3D = instances[i][0]
			transform.origin -= origin
			mm.set_instance_transform(i, transform)
			mm.set_instance_color(i, instances[i][1])
			mm.set_instance_custom_data(i, instances[i][2])
		var batch := MultiMeshInstance3D.new()
		batch.position = origin
		batch.multimesh = mm
		batch.material_override = material
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		batch.visibility_range_end = 180.
		add_child(batch)
	library.free()


func _append(batches: Dictionary, module: String, transform: Transform3D, color: Color, tile: Color) -> void:
	var p := transform.origin
	var key := [Vector2i(floori(p.x / CELL), floori(p.z / CELL)), module]
	if not batches.has(key):
		batches[key] = []
	batches[key].append([transform, color, tile])
