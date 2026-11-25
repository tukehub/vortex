extends SceneTree
## Reduces Poly Haven's CC0 "Lion Head" (Tina; 47 000 triangles,
## godot/assets/props/lion_head/lion_head.glb from tools/fetch_cc0_assets.py)
## to the mesh Vlorë's lion fountain mounts at the Konomi split:
##   godot --headless --path godot --script tools/build_lion_head.gd
## Output: godot/assets/landmarks/lion_head.res, one surface with normals,
## tangents and UVs for the model's own CC0 maps (the JPGs Godot extracts
## beside the GLB), simplified with Godot's mesh LOD generator to about
## TARGET_TRIS. Units are the source's metres (the head is 0.44 m tall);
## LionFountain scales it. The mouth faces -Z, the back is flat at z = 0.

const SRC := "res://assets/props/lion_head/lion_head.glb"
const OUT := "res://assets/landmarks/lion_head.res"
const TARGET_TRIS := 6000


func _initialize() -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(SRC), state) != OK:
		printerr("Could not read ", SRC)
		quit(1)
		return
	var root := doc.generate_scene(state)
	var found: Array = []
	_collect(root, Transform3D.IDENTITY, found)
	if found.is_empty():
		printerr("No mesh in ", SRC)
		quit(1)
		return
	var mesh: Variant = found[0][0]
	var xf: Transform3D = found[0][1]
	var arrays: Array = mesh.surface_get_arrays(0) if mesh is Mesh else mesh.get_surface_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var source := PackedInt32Array(arrays[Mesh.ARRAY_INDEX]).size() / 3
	var nb := xf.basis.inverse().transposed()
	for i in verts.size():
		verts[i] = xf * verts[i]
		norms[i] = (nb * norms[i]).normalized()
	# Which way does it face? The mouth is the side away from the flat back:
	# the vertex spread along each horizontal axis is lopsided toward it.
	var box := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		box = box.expand(v)
	var centre := box.get_center()
	var turn := Basis.IDENTITY
	var mean := Vector3.ZERO
	for v in verts:
		mean += v - centre
	mean /= verts.size()
	# The back plate holds most vertices far from the face: the face is
	# opposite the mean's offset on the thinnest horizontal axis.
	var thin_x := box.size.x < box.size.z
	var face := Vector3.ZERO
	if thin_x:
		face = Vector3(-signf(mean.x), 0, 0)
	else:
		face = Vector3(0, 0, -signf(mean.z))
	if OS.get_environment("LION_FACE") != "":
		var f := OS.get_environment("LION_FACE").split(",")
		face = Vector3(float(f[0]), 0, float(f[1]))
	turn = Basis(Vector3.UP, atan2(face.x, face.z) - atan2(0.0, -1.0))
	var back := -INF
	for i in verts.size():
		verts[i] = turn * (verts[i] - Vector3(centre.x, box.position.y, centre.z))
		norms[i] = turn * norms[i]
		back = maxf(back, verts[i].z)
	for i in verts.size():
		verts[i].z -= back
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TANGENT] = null
	var work := ImporterMesh.new()
	work.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	work.generate_lods(25.0, 60.0, [])
	var best: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for l in work.get_surface_lod_count(0):
		var idx := work.get_surface_lod_indices(0, l)
		if absi(idx.size() / 3 - TARGET_TRIS) < absi(best.size() / 3 - TARGET_TRIS):
			best = idx
	var st := SurfaceTool.new()
	var plain := arrays.duplicate()
	plain[Mesh.ARRAY_INDEX] = best
	st.create_from_arrays(plain)
	st.generate_tangents()
	var out := st.commit()
	root.free()
	var err := ResourceSaver.save(out, OUT, ResourceSaver.FLAG_COMPRESS)
	print("LION HEAD: %d source triangles -> %d; aabb %s; facing %s; saved %s (%s)" % [
		source, best.size() / 3, out.get_aabb(), face, OUT, error_string(err)])
	quit(0 if err == OK else 1)


func _collect(node: Node, parent: Transform3D, found: Array) -> void:
	var xf := parent
	if node is Node3D:
		xf = parent * (node as Node3D).transform
	if node is ImporterMeshInstance3D and (node as ImporterMeshInstance3D).mesh != null:
		found.append([(node as ImporterMeshInstance3D).mesh, xf])
	elif node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		found.append([(node as MeshInstance3D).mesh, xf])
	for child in node.get_children():
		_collect(child, xf, found)
