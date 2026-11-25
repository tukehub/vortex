class_name ArchKit
extends RefCounted
## Textured architecture on SurfaceTools, for landmarks that carry real
## surface textures (coursed ashlar, rubble, clay tiles) rather than flat
## vertex colour. Every vertex has a normal, a vertex colour (a tint over the
## texture) and a UV in metres laid out the way the material runs on a
## building: walls get u along the wall and v down from the sky, so courses
## of stone stay level and line up from face to face at the same height;
## roofs and domes get v down the slope, so rows of tiles run from the ridge
## or crown to the eaves. A material's uv1_scale turns metres into texture
## repeats (see material()).

const UP := Vector3.UP


static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## A textured PBR material for these meshes: albedo times the vertex colour,
## OpenGL normal map, roughness from the ARM map's green channel. `metres`
## is the size one texture repeat covers.
static func material(diff: Texture2D, nor: Texture2D, arm: Texture2D, metres: float, tint := Color.WHITE, normal_strength := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_texture = diff
	m.albedo_color = tint
	if nor != null:
		m.normal_enabled = true
		m.normal_texture = nor
		m.normal_scale = normal_strength
	if arm != null:
		m.roughness_texture = arm
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.roughness = 1.0
	m.uv1_scale = Vector3(1.0 / metres, 1.0 / metres, 1.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


static func node(st: SurfaceTool, mat: Material, node_name: String, reach: float) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.name = node_name
	n.mesh = st.commit()
	n.material_override = mat
	n.visibility_range_end = reach
	return n


# ------------------------------------------------------------------ triangles

static func _vertex(st: SurfaceTool, p: Vector3, n: Vector3, uv: Vector2, col: Color) -> void:
	st.set_color(col)
	st.set_normal(n)
	st.set_uv(uv)
	st.add_vertex(p)


## A quad with its own UVs: a, b along the bottom, c above b, d above a.
## Seen from the side `toward` points to (or from the a->b x a->d side).
static func quad_uv(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, col: Color, toward := Vector3.ZERO) -> void:
	var n := (b - a).cross(d - a)
	if n.length_squared() < 1e-12:
		n = (c - b).cross(d - b)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	if toward != Vector3.ZERO and n.dot(toward) < 0.0:
		# Mirror the winding: b, a along the bottom, c over b becomes d over a.
		var t: Vector3 = a
		a = b
		b = t
		t = c
		c = d
		d = t
		var tu: Vector2 = ua
		ua = ub
		ub = tu
		tu = uc
		uc = ud
		ud = tu
		n = -n
	for k in [[a, ua], [c, uc], [b, ub], [a, ua], [d, ud], [c, uc]]:
		_vertex(st, k[0], n, k[1], col)


## Wall UV for a point: u along the horizontal direction `along`, v = -y.
static func wall_uv(p: Vector3, along: Vector3) -> Vector2:
	return Vector2(p.dot(along), -p.y)


## A flat quad whose UVs follow the wall rule (level courses, metres).
static func wall_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, toward := Vector3.ZERO) -> void:
	var n := (b - a).cross(d - a)
	var along := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if absf(n.normalized().y) > 0.7 or along.length_squared() < 1e-8:
		# Near-horizontal faces: plan UVs.
		quad_uv(st, a, b, c, d, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z), Vector2(d.x, d.z), col, toward)
		return
	along = along.normalized()
	quad_uv(st, a, b, c, d, wall_uv(a, along), wall_uv(b, along), wall_uv(c, along), wall_uv(d, along), col, toward)


## A box (optionally turned by `basis`) with wall/plan UVs on its faces.
## `skip_bottom` leaves out the face nobody sees.
static func box(st: SurfaceTool, centre: Vector3, size: Vector3, col: Color, basis := Basis.IDENTITY, skip_bottom := true) -> void:
	var h := size * 0.5
	var c := func(x: float, y: float, z: float) -> Vector3: return centre + basis * Vector3(x * h.x, y * h.y, z * h.z)
	wall_quad(st, c.call(1, -1, 1), c.call(1, -1, -1), c.call(1, 1, -1), c.call(1, 1, 1), col, basis.x)
	wall_quad(st, c.call(-1, -1, -1), c.call(-1, -1, 1), c.call(-1, 1, 1), c.call(-1, 1, -1), col, -basis.x)
	wall_quad(st, c.call(-1, -1, 1), c.call(1, -1, 1), c.call(1, 1, 1), c.call(-1, 1, 1), col, basis.z)
	wall_quad(st, c.call(1, -1, -1), c.call(-1, -1, -1), c.call(-1, 1, -1), c.call(1, 1, -1), col, -basis.z)
	wall_quad(st, c.call(-1, 1, -1), c.call(1, 1, -1), c.call(1, 1, 1), c.call(-1, 1, 1), col, basis.y)
	if not skip_bottom:
		wall_quad(st, c.call(-1, -1, 1), c.call(1, -1, 1), c.call(1, -1, -1), c.call(-1, -1, -1), col, -basis.y)


## Vertical cylinder wall round `centre` (its y ignored), radius r, from y0 to
## y1, over azimuths a0..a1 (radians, 0 = -Z, increasing toward +X), smooth
## normals facing out (or in). u runs round the circumference in metres.
static func ring_wall(st: SurfaceTool, centre: Vector3, r: float, y0: float, y1: float, col: Color,
		segments := 48, a0 := 0.0, a1 := TAU, inward := false) -> void:
	for k in segments:
		var t0 := a0 + (a1 - a0) * k / segments
		var t1 := a0 + (a1 - a0) * (k + 1) / segments
		var d0 := Vector3(sin(t0), 0.0, -cos(t0))
		var d1 := Vector3(sin(t1), 0.0, -cos(t1))
		var p0 := Vector3(centre.x, 0.0, centre.z) + d0 * r
		var p1 := Vector3(centre.x, 0.0, centre.z) + d1 * r
		var u0 := t0 * r
		var u1 := t1 * r
		var n0 := -d0 if inward else d0
		var n1 := -d1 if inward else d1
		var quad := [[p0 + UP * y0, n0, Vector2(u0, -y0)], [p1 + UP * y0, n1, Vector2(u1, -y0)],
			[p1 + UP * y1, n1, Vector2(u1, -y1)], [p0 + UP * y1, n0, Vector2(u0, -y1)]]
		var order := [0, 1, 2, 0, 2, 3] if not inward else [0, 2, 1, 0, 3, 2]
		for i: int in order:
			_vertex(st, quad[i][0], quad[i][1], quad[i][2], col)


## A sloping ring (cone frustum) from radius r0 at y0 to r1 at y1 round
## `centre`, normals up-and-out. UV: u round the lower edge, v down the slope
## from the upper edge, so tile rows run downhill.
static func frustum(st: SurfaceTool, centre: Vector3, r0: float, y0: float, r1: float, y1: float, col: Color,
		segments := 48, a0 := 0.0, a1 := TAU) -> void:
	var slant := Vector2(r0 - r1, y1 - y0).length()
	var ny := (r0 - r1) / slant
	var nr := (y1 - y0) / slant
	for k in segments:
		var t0 := a0 + (a1 - a0) * k / segments
		var t1 := a0 + (a1 - a0) * (k + 1) / segments
		var d0 := Vector3(sin(t0), 0.0, -cos(t0))
		var d1 := Vector3(sin(t1), 0.0, -cos(t1))
		var c := Vector3(centre.x, 0.0, centre.z)
		var n0 := (d0 * nr + UP * ny).normalized()
		var n1 := (d1 * nr + UP * ny).normalized()
		var lo0 := [c + d0 * r0 + UP * y0, n0, Vector2(t0 * r0, slant)]
		var lo1 := [c + d1 * r0 + UP * y0, n1, Vector2(t1 * r0, slant)]
		var hi1 := [c + d1 * r1 + UP * y1, n1, Vector2(t1 * r0, 0.0)]
		var hi0 := [c + d0 * r1 + UP * y1, n0, Vector2(t0 * r0, 0.0)]
		for v in [lo0, lo1, hi1, lo0, hi1, hi0]:
			_vertex(st, v[0], v[1], v[2], col)


## A flat disc (or ring between r_in and r) at height y, facing up.
static func disc(st: SurfaceTool, centre: Vector3, r: float, y: float, col: Color, segments := 32, r_in := 0.0, down := false) -> void:
	var n := Vector3.DOWN if down else UP
	for k in segments:
		var t0 := TAU * k / segments
		var t1 := TAU * (k + 1) / segments
		var d0 := Vector3(sin(t0), 0.0, -cos(t0))
		var d1 := Vector3(sin(t1), 0.0, -cos(t1))
		var c := Vector3(centre.x, y, centre.z)
		var pts := [c + d0 * r_in, c + d0 * r, c + d1 * r, c + d1 * r_in]
		var order := [0, 1, 2, 0, 2, 3] if not down else [0, 2, 1, 0, 3, 2]
		for i: int in order:
			var p: Vector3 = pts[i]
			_vertex(st, p, n, Vector2(p.x, p.z), col)


## An elliptical dome: base radius rx at y, rising ry, over `rings` x
## `segments` facets (it stops `top_cut` short of the crown for a lantern).
## UV: u round the base in metres, v down the meridian from the crown.
static func dome(st: SurfaceTool, centre: Vector3, rx: float, ry: float, y: float, col: Color,
		segments := 32, rings := 10, top_cut := 0.0) -> void:
	var pt := func(e: float, a: float) -> Vector3:
		return Vector3(centre.x + sin(a) * cos(e) * rx, y + sin(e) * ry, centre.z - cos(a) * cos(e) * rx)
	var nrm := func(e: float, a: float) -> Vector3:
		return Vector3(sin(a) * cos(e) / rx, sin(e) / ry, -cos(a) * cos(e) / rx).normalized()
	var top := PI * 0.5 - top_cut
	# Arc length from the crown down each ring, for v.
	var arc: Array[float] = []
	var acc := 0.0
	arc.resize(rings + 1)
	arc[rings] = 0.0
	for i in range(rings, 0, -1):
		var e0 := top * i / rings
		var e1 := top * (i - 1) / rings
		acc += (pt.call(e0, 0.0) as Vector3).distance_to(pt.call(e1, 0.0))
		arc[i - 1] = acc
	for i in rings:
		var e0 := top * i / rings
		var e1 := top * (i + 1) / rings
		for k in segments:
			var a0 := TAU * k / segments
			var a1 := TAU * (k + 1) / segments
			var v := [[e0, a0], [e0, a1], [e1, a1], [e1, a0]]
			var uv := [Vector2(a0 * rx, arc[i]), Vector2(a1 * rx, arc[i]), Vector2(a1 * rx, arc[i + 1]), Vector2(a0 * rx, arc[i + 1])]
			for j: int in [0, 1, 2, 0, 2, 3]:
				_vertex(st, pt.call(v[j][0], v[j][1]), nrm.call(v[j][0], v[j][1]), uv[j], col)


## A round-headed opening on a flat face: the rectangle from `foot` (centre of
## the sill) up `rise`, then a semicircle of radius w/2. `right` runs along
## the face, `out` is its outward normal. Drawn `lift` in front of the face.
static func arch_panel(st: SurfaceTool, foot: Vector3, right: Vector3, out: Vector3, w: float, rise: float, col: Color, lift := 0.02, steps := 10) -> void:
	var r := w * 0.5
	var o := foot + out * lift
	var along := right.normalized()
	wall_quad(st, o - along * r, o + along * r, o + along * r + UP * rise, o - along * r + UP * rise, col, out)
	var centre := o + UP * rise
	for k in steps:
		var a0 := PI * k / steps
		var a1 := PI * (k + 1) / steps
		var p0 := centre + (along * cos(a0) + UP * sin(a0)) * r
		var p1 := centre + (along * cos(a1) + UP * sin(a1)) * r
		var n := out.normalized()
		var tri := [centre, p0, p1]
		if (p0 - centre).cross(p1 - centre).dot(n) > 0.0:
			tri = [centre, p1, p0]
		for p: Vector3 in tri:
			_vertex(st, p, n, wall_uv(p, along), col)


## The ring of an arch (voussoirs) round a semicircle of radius r: `count`
## stones `depth` deep and `width` wide, alternating colours a and b (a red
## brick and white stone arch, say). Built as boxes on `st`.
static func voussoirs(st: SurfaceTool, centre: Vector3, right: Vector3, out: Vector3, r: float, width: float, depth: float,
		col_a: Color, col_b: Color, count := 9) -> void:
	var along := right.normalized()
	var n := out.normalized()
	for k in count:
		var a := PI * (k + 0.5) / count
		var radial := along * cos(a) + UP * sin(a)
		var p := centre + radial * (r + width * 0.5) + n * depth * 0.5
		var tangent := n.cross(radial).normalized()
		var size := Vector3(width, PI * (r + width * 0.5) / count * 0.94, depth)
		box(st, p, size, col_a if k % 2 == 0 else col_b, Basis(radial, tangent, n))


## A Latin cross standing on `base`, `h` tall, facing `out`.
static func cross(st: SurfaceTool, base: Vector3, h: float, out: Vector3, col: Color) -> void:
	var side := UP.cross(out).normalized()
	var b := Basis(side, UP, out.normalized())
	var t := h * 0.09
	box(st, base + UP * h * 0.5, Vector3(t, h, t), col, b)
	box(st, base + UP * h * 0.7, Vector3(h * 0.56, t, t), col, b)
