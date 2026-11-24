class_name LandmarkKit
extends RefCounted
## Small mesh-building helpers for the procedural landmarks: vertex-coloured
## boxes, quads, tapered cylinders and spheres appended to a SurfaceTool, so a
## whole building in one material is one draw call. Also the Albanian flag
## texture (red field, black double-headed eagle).

static var _flag: Texture2D


static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Every vertex carries a UV (quads set real ones; tubes and spheres reuse
	# the last), so mixed primitives share one vertex format.
	st.set_uv(Vector2.ZERO)
	return st


static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, uv_scale := 1.0) -> void:
	var n := (b - a).cross(d - a).normalized()
	st.set_color(col)
	st.set_normal(n)
	var w := a.distance_to(b) * uv_scale
	var h := a.distance_to(d) * uv_scale
	# UV in (scaled) metres from corner a: x along a->b, y along a->d.
	for p in [[a, Vector2(0, 0)], [c, Vector2(w, h)], [b, Vector2(w, 0)], [a, Vector2(0, 0)], [d, Vector2(0, h)], [c, Vector2(w, h)]]:
		st.set_uv(p[1])
		st.add_vertex(p[0])


## A quad seen from the side `toward` points to, whatever order the corners
## come in (a, b along the bottom, d above a).
static func quad_facing(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, toward: Vector3) -> void:
	if (b - a).cross(d - a).dot(toward) < 0.0:
		quad(st, b, a, d, c, col)
	else:
		quad(st, a, b, c, d, col)


## Axis-aligned box in the node's frame (optionally turned by `basis`).
static func box(st: SurfaceTool, centre: Vector3, size: Vector3, col: Color, basis := Basis.IDENTITY) -> void:
	var h := size * 0.5
	var c := func(x: float, y: float, z: float) -> Vector3: return centre + basis * Vector3(x * h.x, y * h.y, z * h.z)
	# +X, -X, +Y, -Y, +Z, -Z faces, wound so the normal points outward.
	quad(st, c.call(1, -1, 1), c.call(1, -1, -1), c.call(1, 1, -1), c.call(1, 1, 1), col)
	quad(st, c.call(-1, -1, -1), c.call(-1, -1, 1), c.call(-1, 1, 1), c.call(-1, 1, -1), col)
	quad(st, c.call(-1, 1, 1), c.call(1, 1, 1), c.call(1, 1, -1), c.call(-1, 1, -1), col)
	quad(st, c.call(-1, -1, -1), c.call(1, -1, -1), c.call(1, -1, 1), c.call(-1, -1, 1), col)
	quad(st, c.call(-1, -1, 1), c.call(1, -1, 1), c.call(1, 1, 1), c.call(-1, 1, 1), col)
	quad(st, c.call(1, -1, -1), c.call(-1, -1, -1), c.call(-1, 1, -1), c.call(1, 1, -1), col)


## A tapered tube between two points, closed at the top.
static func tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, col: Color, sides := 8) -> void:
	var axis := (b - a).normalized()
	var u := axis.cross(Vector3.FORWARD if absf(axis.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var v := axis.cross(u)
	st.set_color(col)
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		for p in [[a + d0 * ra, d0], [b + d1 * rb, d1], [b + d0 * rb, d0], [a + d0 * ra, d0], [a + d1 * ra, d1], [b + d1 * rb, d1]]:
			st.set_normal(p[1])
			st.add_vertex(p[0])
		st.set_normal(axis)
		for p in [b, b + d0 * rb, b + d1 * rb]:
			st.add_vertex(p)


static func sphere(st: SurfaceTool, centre: Vector3, r: Vector3, col: Color, rings := 6, sides := 8) -> void:
	st.set_color(col)
	for i in rings:
		for k in sides:
			var pts := []
			for c in [[i, k], [i, k + 1], [i + 1, k + 1], [i + 1, k]]:
				var th: float = PI * c[0] / rings
				var ph: float = TAU * c[1] / sides
				pts.append(Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph)))
			for j in [0, 2, 1, 0, 3, 2]:
				st.set_normal(pts[j])
				st.add_vertex(centre + pts[j] * r)


static func mesh_node(st: SurfaceTool, material: Material, node_name: String, reach := 1800.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = st.commit()
	node.material_override = material
	node.visibility_range_end = reach
	return node


static func material(rough := 0.85, metal := 0.0, cull := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	# Colours here are written as sRGB, like the photographs they come from.
	m.vertex_color_is_srgb = true
	m.roughness = rough
	m.metallic = metal
	if not cull:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## The flag of Albania: a red field with the black double-headed eagle, at
## the official 5:7 proportion. The eagle is the state's vector drawing
## (public domain), rasterised by tools/build_albanian_flag.py.
static func albanian_flag() -> Texture2D:
	if _flag == null:
		_flag = load("res://assets/textures/albanian_flag.png")
	return _flag
