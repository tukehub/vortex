extends SceneTree
## Converts the supplied "Traffic Light - Complex" FBX (Urban Mini Props Pack)
## into the mesh StreetProps draws near the camera:
##   godot --headless --path godot --script tools/build_traffic_light.gd -- \
##       "raw_assets/traffic_light/Traffic Light - Complex.fbx"
## Output: godot/assets/props/traffic_light/traffic_light.res
##
## - Feet on the ground (y = 0) at the pole, mast arm along +X (over the road)
##   and heads facing -Z (toward approaching traffic): StreetProps' convention.
##   The source has its arm along +Z and its lenses facing +X: a quarter turn
##   about the pole, (x, y, z) -> (z, y, -x).
## - Source colours become vertex colours in one surface; each head's lenses
##   are split into thirds by height: red and amber dark, green lit (a second,
##   emissive surface). The source's two image textures (Concrete030) were not
##   supplied and are not needed.
## - Simplified with Godot's mesh LOD generator to about TARGET_TRIS.

const OUT := "res://assets/props/traffic_light/traffic_light.res"
var TARGET_TRIS := int(OS.get_environment("TL_TRIS")) if OS.get_environment("TL_TRIS") != "" else 6000
const GLASS := ["Glass", "Glass.001", "Lights.001"]
## Corners whose faces meet at more than this keep separate normals.
const CREASE_DEGREES := 40.0

var body := {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray()}
var lamp := {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray()}
var source_tris := 0
var flipped := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		printerr("Expected the source FBX path")
		quit(2)
		return
	var doc := FBXDocument.new()
	var state := FBXState.new()
	if doc.append_from_file(args[0], state) != OK:
		printerr("Could not read ", args[0])
		quit(1)
		return
	var root := doc.generate_scene(state)
	var parts := []
	_collect(root, Transform3D.IDENTITY, parts)
	# Ground: the lowest point of the pole.
	var ground := INF
	for part in parts:
		for v: Vector3 in part.v:
			ground = minf(ground, v.y)
	for part in parts:
		_add(part, ground)
	var mesh := _build()
	root.free()
	var dir := ProjectSettings.globalize_path(OUT.get_base_dir())
	DirAccess.make_dir_recursive_absolute(dir)
	var err := ResourceSaver.save(mesh, OUT, ResourceSaver.FLAG_COMPRESS)
	print("TRAFFIC LIGHT: %d source triangles (%d parts rewound) -> %d (%d lit); aabb %s; saved %s (%s)" % [
		source_tris, flipped, _tris(mesh, 0), _tris(mesh, 1) if mesh.get_surface_count() > 1 else 0, mesh.get_aabb(), OUT, error_string(err)])
	quit(0 if err == OK else 1)


## World-space triangles of every mesh surface, with their material.
func _collect(node: Node, parent: Transform3D, parts: Array) -> void:
	var xf := parent
	if node is Node3D:
		xf = parent * (node as Node3D).transform
	# A runtime FBXDocument scene holds ImporterMeshInstance3D nodes; an
	# imported one holds MeshInstance3D. Read either.
	var mesh: Variant = null
	if node is MeshInstance3D:
		mesh = (node as MeshInstance3D).mesh
	elif node is ImporterMeshInstance3D:
		mesh = (node as ImporterMeshInstance3D).mesh
	if mesh != null:
		var nb := xf.basis.inverse().transposed()
		for s in mesh.get_surface_count():
			var a: Array = mesh.surface_get_arrays(s) if mesh is Mesh else mesh.get_surface_arrays(s)
			var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				idx.resize(verts.size())
				for i in verts.size():
					idx[i] = i
			var mat: Material = mesh.surface_get_material(s) if mesh is Mesh else mesh.get_surface_material(s)
			var part := {"node": str(node.name), "mat": mat.resource_name if mat else "", "v": PackedVector3Array(), "n": PackedVector3Array(),
				"color": (mat as BaseMaterial3D).albedo_color if mat is BaseMaterial3D else Color(0.5, 0.5, 0.5)}
			for i in idx:
				part.v.append(_turn(xf * verts[i]))
				part.n.append(_turn((nb * norms[i]).normalized()) if not norms.is_empty() else Vector3.UP)
			source_tris += idx.size() / 3
			parts.append(part)
	for child in node.get_children():
		_collect(child, xf, parts)


func _turn(p: Vector3) -> Vector3:
	return Vector3(p.z, p.y, -p.x)


func _add(part: Dictionary, ground: float) -> void:
	var verts: PackedVector3Array = part.v
	var norms: PackedVector3Array = part.n
	var glass: bool = part.mat in GLASS
	var lo := INF
	var hi := -INF
	if glass:
		for v in verts:
			lo = minf(lo, v.y)
			hi = maxf(hi, v.y)
	var col := _tone(part.mat, part.color)
	# Godot's front face of (a, b, c) is the side ((c - a) x (b - a)) points
	# to. This source's normals point inward, so a part whose winding agrees
	# with them is turned over (checked in renders: otherwise the lenses are
	# culled and each housing shows inside out). Normals are rebuilt from the
	# final winding in _crease, so the source's are not kept.
	var agree := 0
	for t in range(0, verts.size(), 3):
		var fn := (verts[t + 2] - verts[t]).cross(verts[t + 1] - verts[t])
		agree += 1 if fn.dot(norms[t] + norms[t + 1] + norms[t + 2]) >= 0.0 else -1
	var order := [0, 2, 1] if agree >= 0 else [0, 1, 2]
	flipped += 1 if agree >= 0 else 0
	for t in range(0, verts.size(), 3):
		var target := body
		var c := col
		if glass:
			var y := (verts[t].y + verts[t + 1].y + verts[t + 2].y) / 3.0
			var k := (y - lo) / maxf(hi - lo, 1e-4)
			if k < 0.333:
				target = lamp
				c = Color(0.02, 0.55, 0.22)
			elif k < 0.666:
				c = Color(0.22, 0.13, 0.02)
			else:
				c = Color(0.24, 0.03, 0.02)
		for j in order:
			target.v.append(verts[t + j] - Vector3(0, ground, 0))
			target.n.append(norms[t + j])
			target.c.append(c)


## Source colours, nudged toward real street hardware: galvanised grey
## steel, dark heads and wires, yellow backplates kept.
func _tone(mat: String, c: Color) -> Color:
	if mat.begins_with("Glass") or mat == "Lights.001":
		return Color(0.05, 0.05, 0.05)
	if mat.begins_with("Dark") or mat in ["Material.005", "Material.008"]:
		return Color(0.05, 0.05, 0.055)
	if mat.begins_with("Body"):
		return c
	return c.darkened(0.15)


func _build() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var body_mat := StandardMaterial3D.new()
	body_mat.vertex_color_use_as_albedo = true
	body_mat.metallic = 0.35
	body_mat.roughness = 0.55
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.vertex_color_use_as_albedo = true
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(0.05, 1.0, 0.35)
	lamp_mat.emission_energy_multiplier = 1.8
	for pair in [[body, body_mat, TARGET_TRIS], [lamp, lamp_mat, 400]]:
		var src: Dictionary = pair[0]
		if src.v.is_empty():
			continue
		var arrays := _indexed(src)
		var importer := ImporterMesh.new()
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
		importer.generate_lods(25.0, 60.0, [])
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var best := idx
		for l in importer.get_surface_lod_count(0):
			var lod := importer.get_surface_lod_indices(0, l)
			print("  lod %d: %d triangles" % [l, lod.size() / 3])
			if lod.size() / 3 >= int(pair[2]) * 0.6:
				best = lod
		arrays[Mesh.ARRAY_INDEX] = best
		arrays = _crease(_compact(arrays), CREASE_DEGREES)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, pair[1])
	return mesh


## Welds identical vertices so the simplifier can collapse edges.
func _indexed(src: Dictionary) -> Array:
	var seen := {}
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()
	for i in src.v.size():
		# Position and colour only: the source is flat-shaded, and a weld that
		# kept per-face normals would leave every edge a border the simplifier
		# must not move. Normals are rebuilt after simplification (_crease).
		var key := [src.v[i].snapped(Vector3.ONE * 0.0005), src.c[i]]
		var h := str(key)
		if not seen.has(h):
			seen[h] = v.size()
			v.append(src.v[i])
			n.append(src.n[i])
			c.append(src.c[i])
		idx.append(seen[h])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = c
	arrays[Mesh.ARRAY_INDEX] = idx
	return arrays


## Drops vertices no triangle uses any more.
func _compact(arrays: Array) -> Array:
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var remap := {}
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var new_idx := PackedInt32Array()
	for i in idx:
		if not remap.has(i):
			remap[i] = v.size()
			v.append(arrays[Mesh.ARRAY_VERTEX][i])
			n.append(arrays[Mesh.ARRAY_NORMAL][i])
			c.append(arrays[Mesh.ARRAY_COLOR][i])
		new_idx.append(remap[i])
	out[Mesh.ARRAY_VERTEX] = v
	out[Mesh.ARRAY_NORMAL] = n
	out[Mesh.ARRAY_COLOR] = c
	out[Mesh.ARRAY_INDEX] = new_idx
	return out


## Per-corner normals: the average of the faces around the vertex that lie
## within `degrees` of this corner's face, so cylinders read smooth and box
## edges stay sharp. Returns a non-shared (per-corner) vertex layout.
func _crease(arrays: Array, degrees: float) -> Array:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var c: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var faces := PackedVector3Array()
	var around := {}
	for t in range(0, idx.size(), 3):
		var fn := (v[idx[t + 2]] - v[idx[t]]).cross(v[idx[t + 1]] - v[idx[t]])
		faces.append(fn.normalized() if fn.length() > 1e-12 else Vector3.UP)
		for j in 3:
			if not around.has(idx[t + j]):
				around[idx[t + j]] = []
			around[idx[t + j]].append(t / 3)
	var limit := cos(deg_to_rad(degrees))
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var ov := PackedVector3Array()
	var on := PackedVector3Array()
	var oc := PackedColorArray()
	for t in range(0, idx.size(), 3):
		var fn: Vector3 = faces[t / 3]
		for j in 3:
			var sum := Vector3.ZERO
			for f in around[idx[t + j]]:
				if faces[f].dot(fn) >= limit:
					sum += faces[f]
			ov.append(v[idx[t + j]])
			on.append(sum.normalized() if sum.length() > 1e-9 else fn)
			oc.append(c[idx[t + j]])
	out[Mesh.ARRAY_VERTEX] = ov
	out[Mesh.ARRAY_NORMAL] = on
	out[Mesh.ARRAY_COLOR] = oc
	return out


func _tris(mesh: ArrayMesh, s: int) -> int:
	return (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
