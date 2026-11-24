extends SceneTree
## Reduces the Poly Haven props fetched by tools/fetch_cc0_assets.py to Mobile
## meshes, keeping their imported (VRAM-compressed) textures:
##   godot --headless --path godot --script ../tools/build_cc0_props.gd
## Reads  res://assets/props/<key>/<key>.glb   (import first: --editor --import)
## Writes res://assets/props/<key>/<key>_mobile.res, one ArrayMesh, feet on
## y = 0, centred on the footprint, front toward -Z (StreetProps' convention).
##
## Simplification uses Godot's own LOD generator (as tools/build_traffic_light.gd
## does) and keeps the first LOD under each prop's triangle budget.

const PROPS := {
	# key: [triangle budget, scale, turn so the front faces -Z (radians about Y)]
	"bench": [480, Vector3(1.5, 1.0, 1.0), 0.0],
	"street_bin": [800, Vector3.ONE, 0.0],
	"promenade_lamp": [1500, Vector3.ONE, 0.0],
	"utility_box": [900, Vector3.ONE, 0.0],
}
const NORMAL_MERGE := 60.0
const NORMAL_SPLIT := 25.0


func _initialize() -> void:
	var failed := 0
	for key: String in PROPS:
		if not _build(key, PROPS[key]):
			failed += 1
	quit(1 if failed > 0 else 0)


func _build(key: String, spec: Array) -> bool:
	var path := "res://assets/props/%s/%s.glb" % [key, key]
	if not ResourceLoader.exists(path):
		printerr("missing ", path, " (run fetch_cc0_assets.py --download and import)")
		return false
	var root: Node = (load(path) as PackedScene).instantiate()
	var parts := []
	_collect(root, Transform3D.IDENTITY, parts)
	root.free()
	if parts.is_empty():
		printerr(key, ": no meshes")
		return false
	# Feet on the ground, centred on the footprint, scaled and turned.
	var box := AABB(parts[0].arrays[Mesh.ARRAY_VERTEX][0], Vector3.ZERO)
	for part in parts:
		for v: Vector3 in part.arrays[Mesh.ARRAY_VERTEX]:
			box = box.expand(v)
	var place := Transform3D(Basis(Vector3.UP, float(spec[2])).scaled(spec[1]), Vector3.ZERO)
	place = place * Transform3D(Basis.IDENTITY, -Vector3(box.get_center().x, box.position.y, box.get_center().z))
	var src_tris := 0
	var out := ArrayMesh.new()
	var budget := int(spec[0])
	var total := 0
	for part in parts:
		src_tris += part.arrays[Mesh.ARRAY_INDEX].size() / 3
	for part in parts:
		var arrays: Array = _transformed(part.arrays, place)
		var share := float(arrays[Mesh.ARRAY_INDEX].size() / 3) / float(src_tris)
		var indices := _simplified(arrays, maxi(int(budget * share), 12))
		arrays[Mesh.ARRAY_INDEX] = indices
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, part.material)
		total += indices.size() / 3
	var dst := "res://assets/props/%s/%s_mobile.res" % [key, key]
	var err := ResourceSaver.save(out, dst, ResourceSaver.FLAG_COMPRESS)
	print("PROP %s: %d -> %d triangles (budget %d), %d surfaces, aabb %s -> %s (%s)" % [
		key, src_tris, total, budget, out.get_surface_count(), out.get_aabb(), dst, error_string(err)])
	return err == OK and total <= budget


func _collect(node: Node, parent: Transform3D, parts: Array) -> void:
	var xf := parent
	if node is Node3D:
		xf = parent * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh := (node as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			if arrays[Mesh.ARRAY_INDEX] == null:
				var idx := PackedInt32Array()
				idx.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
				for i in idx.size():
					idx[i] = i
				arrays[Mesh.ARRAY_INDEX] = idx
			var mat: Material = (node as MeshInstance3D).get_active_material(s)
			parts.append({"arrays": _transformed(arrays, xf), "material": mat})
	for child in node.get_children():
		_collect(child, xf, parts)


func _transformed(arrays: Array, xf: Transform3D) -> Array:
	var a := arrays.duplicate()
	var nb := xf.basis.inverse().transposed()
	var verts: PackedVector3Array = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	for i in verts.size():
		verts[i] = xf * verts[i]
	a[Mesh.ARRAY_VERTEX] = verts
	if a[Mesh.ARRAY_NORMAL] != null:
		var norms: PackedVector3Array = (a[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate()
		for i in norms.size():
			norms[i] = (nb * norms[i]).normalized()
		a[Mesh.ARRAY_NORMAL] = norms
	if a[Mesh.ARRAY_TANGENT] != null:
		var tan: PackedFloat32Array = (a[Mesh.ARRAY_TANGENT] as PackedFloat32Array).duplicate()
		for i in range(0, tan.size(), 4):
			var t := (xf.basis * Vector3(tan[i], tan[i + 1], tan[i + 2])).normalized()
			tan[i] = t.x
			tan[i + 1] = t.y
			tan[i + 2] = t.z
		a[Mesh.ARRAY_TANGENT] = tan
	return a


## The coarsest-but-in-budget index list Godot's LOD generator offers: the
## first LOD at or under `budget` triangles, or the smallest one.
func _simplified(arrays: Array, budget: int) -> PackedInt32Array:
	var full: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if full.size() / 3 <= budget:
		return full
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	im.generate_lods(NORMAL_MERGE, NORMAL_SPLIT, [])
	var best := full
	for lod in im.get_surface_lod_count(0):
		var idx := im.get_surface_lod_indices(0, lod)
		if idx.size() / 3 <= budget:
			return idx
		if idx.size() < best.size():
			best = idx
	return best
