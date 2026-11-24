class_name RoundaboutRing
extends Node3D
## A roundabout the race drives through (track.json "roundabouts": [x, z,
## ring radius, entry radius]): each pass swings round the island on the
## ring (tools/pipeline/build_city.py roundabout_pass). This dresses it as a
## real one: the circulating carriageway paved all the way round with its
## lane line, kerbed splitter islands where each pair of entry and exit
## lanes parts, give-way teeth across every entry, and blue roundabout and
## give-way signs. The race road leaves its island-side kerb and barrier
## out inside the ring (open_edges) so the ring reads as one surface.

const ASPHALT := Color(0.33, 0.33, 0.34)
const KERB := Color(0.80, 0.78, 0.72)
const VERGE := Color(0.39, 0.46, 0.25)
const PAINT := Color(0.93, 0.93, 0.90)
## The island side of the race road is open within ring + this.
const OPEN_REACH := 15.0
## Splitter islands run from just outside the ring to where the two
## carriageways close up into the divider.
const SPLIT_FROM := 2.2
const SPLIT_TO := 17.0

static var _sign_tex: Array[Texture2D] = []


## Lap stretches where the island side of the road stays open:
## [[start s, length m, side], ...], side +1 when the island is on the
## driver's right (RaceTrack normals), -1 on the left.
static func open_edges(track: RaceTrack, rings: Array) -> Array:
	var out := []
	for ring: Array in rings:
		var at := Vector2(float(ring[0]), float(ring[1]))
		var reach := float(ring[2]) + OPEN_REACH
		var start := -1
		var side := 0.0
		var first := 0
		while first < track.M and Vector2(track.X[first], track.Z[first]).distance_to(at) < reach:
			first += 1
		for k in track.M + 1:
			var i := (first + k) % track.M
			var p := Vector2(track.X[i], track.Z[i])
			var inside := k < track.M and p.distance_to(at) < reach
			if inside and start < 0:
				start = first + k
				side = signf((at - p).dot(Vector2(track.NX[i], track.NZ[i])))
			elif not inside and start >= 0:
				out.append([track.mod_s(start * track.ds), (first + k - start) * track.ds, side])
				start = -1
	return out


## Lap s values every `step` m where the centreline is within `reach` of
## `centre` (a few hundred instead of the whole lap).
static func near_s(track: RaceTrack, centre: Vector2, reach: float, step := 1.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var r2 := reach * reach
	for i in track.M:
		if Vector2(track.X[i], track.Z[i]).distance_squared_to(centre) < r2:
			var k := 0.0
			while k < track.ds:
				out.append(i * track.ds + k)
				k += step
	return out


static func edge_open(edges: Array, track: RaceTrack, s: float, side: float) -> bool:
	for e: Array in edges:
		if float(e[2]) == side and track.mod_s(s - float(e[0])) < float(e[1]):
			return true
	return false


func build(track: RaceTrack, ring: Array, island: float, height_at := Callable()) -> void:
	var centre := Vector2(float(ring[0]), float(ring[1]))
	var radius := float(ring[2])
	var hw := track.half_w
	var i0 := track.nearest(centre.x, centre.y, radius + 30.0)
	var base_y := track.Y[i0] if i0 >= 0 else 0.0
	position = Vector3(centre.x, base_y, centre.y)
	var paving := LandmarkKit.begin()
	var marks := LandmarkKit.begin()
	var kerbs := LandmarkKit.begin()
	_paving(paving, marks, track, centre, island + 0.05, radius + hw + 0.6, radius)
	for split in _splitters(track, centre, radius + hw + SPLIT_FROM, radius + SPLIT_TO):
		_splitter(kerbs, split)
	for entry in _entries(track, centre, radius + hw + 1.2):
		_give_way(marks, track, float(entry.s), entry.side)
		_signs(float(entry.s), entry.side, track)
	var asphalt := LandmarkKit.material(0.92)
	asphalt.albedo_texture = preload("res://assets/textures/asphalt_diff.jpg")
	asphalt.uv1_triplanar = true
	asphalt.uv1_scale = Vector3.ONE * 0.25
	var ground := LandmarkKit.mesh_node(paving, asphalt, "CirculatingCarriageway", 700.0)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	var paint := LandmarkKit.mesh_node(marks, LandmarkKit.material(0.7), "RingMarkings", 380.0)
	paint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(paint)
	add_child(LandmarkKit.mesh_node(kerbs, LandmarkKit.material(0.88), "SplitterIslands", 600.0))


## The ring paved all the way round, a few cm under the race road, and its
## dashed lane line where the race road does not draw one.
func _paving(st: SurfaceTool, marks: SurfaceTool, track: RaceTrack, centre: Vector2, inner: float, outer: float, lane: float) -> void:
	var steps := 96
	for k in steps:
		var a0 := TAU * k / steps
		var a1 := TAU * (k + 1) / steps
		var row := []
		for a: float in [a0, a1]:
			var dir := Vector3(cos(a), 0.0, sin(a))
			row.append([dir * inner + Vector3.UP * _ground(track, centre, dir * inner),
				dir * outer + Vector3.UP * _ground(track, centre, dir * outer)])
		LandmarkKit.quad_facing(st, row[0][0], row[1][0], row[1][1], row[0][1], ASPHALT, Vector3.UP)
		if k % 2 == 0:
			var dir0 := Vector3(cos(a0), 0.0, sin(a0))
			var dir1 := Vector3(cos(a0 + TAU / steps * 0.75), 0.0, sin(a0 + TAU / steps * 0.75))
			var y0 := _ground(track, centre, dir0 * lane) + 0.012
			var y1 := _ground(track, centre, dir1 * lane) + 0.012
			LandmarkKit.quad_facing(marks, dir0 * (lane - 0.07) + Vector3.UP * y0, dir1 * (lane - 0.07) + Vector3.UP * y1,
				dir1 * (lane + 0.07) + Vector3.UP * y1, dir0 * (lane + 0.07) + Vector3.UP * y0, PAINT, Vector3.UP)


## Height (local) for the paving at a local offset: just under the nearest
## race road, so the driven arcs cover it.
func _ground(track: RaceTrack, centre: Vector2, local: Vector3) -> float:
	var i := track.nearest(centre.x + local.x, centre.y + local.z, 80.0)
	return (track.Y[i] if i >= 0 else position.y) - position.y - 0.035


## Pairs of island-side road edges (an entry and the exit beside it), each
## [entry points, exit points] ordered outward, local coordinates.
func _splitters(track: RaceTrack, centre: Vector2, r_min: float, r_max: float) -> Array:
	var runs := []
	var run := []
	var run_side := 0.0
	var samples := near_s(track, centre, r_max + 10.0)
	var last := -INF
	for k in samples.size() + 1:
		var s := samples[k] if k < samples.size() else INF
		var keep := false
		var edge := Vector3.ZERO
		var side := 0.0
		if k < samples.size() and s - last < 1.5:
			var p := track.pos(s, 0.0)
			side = signf((centre - Vector2(p.x, p.z)).dot(Vector2(track.normal(s).x, track.normal(s).z)))
			edge = track.pos(s, side * (track.half_w + 0.15))
			var r := Vector2(edge.x, edge.z).distance_to(centre)
			keep = r >= r_min and r <= r_max
		if keep:
			if run.is_empty():
				run_side = side
			run.append(edge - position)
		elif not run.is_empty():
			runs.append({"points": run, "side": run_side})
			run = []
		last = s
		if k < samples.size() and not keep and run.is_empty():
			continue
	# Each run is an entry (heading in) or an exit (heading out); order all
	# outward and pair each entry with the nearest exit by bearing.
	var entries := []
	var exits := []
	for item: Dictionary in runs:
		var pts: Array = item.points
		if pts.size() < 3:
			continue
		var inward := Vector2(pts[0].x, pts[0].z).length() > Vector2(pts[-1].x, pts[-1].z).length()
		if inward:
			pts.reverse()
			entries.append(pts)
		else:
			exits.append(pts)
	var pairs := []
	for e: Array in entries:
		var best: Array = []
		var best_d := INF
		for x: Array in exits:
			var d := Vector2(e[-1].x, e[-1].z).distance_to(Vector2(x[-1].x, x[-1].z))
			if d < best_d:
				best_d = d
				best = x
		if not best.is_empty() and best_d < 14.0:
			pairs.append([e, best])
	return pairs


## A kerbed island between an entry and its neighbouring exit, closing up
## into the divider: paved border, verge on top.
func _splitter(st: SurfaceTool, pair: Array) -> void:
	var a: Array = pair[0]
	var b: Array = pair[1]
	var n := 14
	var left: Array[Vector3] = []
	var right: Array[Vector3] = []
	for k in n + 1:
		var t := float(k) / n
		left.append(_along(a, t))
		right.append(_along(b, t))
	var top := 0.16
	for k in n:
		for pair_side in [[left, right], [right, left]]:
			var p: Array[Vector3] = pair_side[0]
			var q: Array[Vector3] = pair_side[1]
			var out_dir := (p[k] - q[k]).normalized()
			LandmarkKit.quad_facing(st, p[k], p[k + 1], p[k + 1] + Vector3.UP * top, p[k] + Vector3.UP * top, KERB.darkened(0.08), out_dir)
		var la := left[k] + Vector3.UP * top
		var lb := left[k + 1] + Vector3.UP * top
		var ra := right[k] + Vector3.UP * top
		var rb := right[k + 1] + Vector3.UP * top
		var inset_a := la.lerp(ra, 0.18)
		var inset_b := lb.lerp(rb, 0.18)
		var inset_c := rb.lerp(lb, 0.18)
		var inset_d := ra.lerp(la, 0.18)
		LandmarkKit.quad_facing(st, la, lb, inset_b, inset_a, KERB, Vector3.UP)
		LandmarkKit.quad_facing(st, rb, ra, inset_d, inset_c, KERB, Vector3.UP)
		LandmarkKit.quad_facing(st, inset_a, inset_b, inset_c, inset_d, VERGE.lightened(0.05 * sin(k * 1.7)), Vector3.UP)
	# Nose facing the ring.
	LandmarkKit.quad_facing(st, left[0], right[0], right[0] + Vector3.UP * top, left[0] + Vector3.UP * top, KERB, -(left[1] - left[0]).normalized())


static func _along(points: Array, t: float) -> Vector3:
	var f := t * (points.size() - 1)
	var i := mini(int(f), points.size() - 2)
	return (points[i] as Vector3).lerp(points[i + 1], f - i)


## Where each pass crosses into the ring (lap s, island side).
func _entries(track: RaceTrack, centre: Vector2, r_entry: float) -> Array:
	var out := []
	var prev := INF
	var last := -INF
	for s in near_s(track, centre, r_entry + 10.0):
		var p := track.pos(s, 0.0)
		var r := Vector2(p.x, p.z).distance_to(centre)
		if s - last > 1.5:
			prev = INF
		last = s
		if prev > r_entry and r <= r_entry:
			var side := signf((centre - Vector2(p.x, p.z)).dot(Vector2(track.normal(s).x, track.normal(s).z)))
			out.append({"s": s, "side": side})
		prev = r
	return out


## A row of give-way triangles across the carriageway, points toward the
## approaching driver.
func _give_way(st: SurfaceTool, track: RaceTrack, s: float, _side: float) -> void:
	var teeth := 9
	var width := track.half_w * 2.0 - 0.6
	for k in teeth:
		var d0 := -width * 0.5 + width * k / teeth + 0.1
		var d1 := -width * 0.5 + width * (k + 1) / teeth - 0.1
		var a := track.pos(s, d0) - position + Vector3.UP * 0.02
		var b := track.pos(s, d1) - position + Vector3.UP * 0.02
		var tip := track.pos(s - 1.3, (d0 + d1) * 0.5) - position + Vector3.UP * 0.02
		LandmarkKit.quad_facing(st, a, b, tip, tip, PAINT, Vector3.UP)


## On the driver's outer side at the entry: the blue roundabout sign over
## the red-bordered give-way triangle.
func _signs(s: float, side: float, track: RaceTrack) -> void:
	var foot := track.pos(s - 4.0, -side * (track.half_w + 2.3)) - position
	var st := LandmarkKit.begin()
	LandmarkKit.tube(st, foot, foot + Vector3.UP * 3.1, 0.05, 0.05, Color(0.55, 0.56, 0.57), 8)
	add_child(LandmarkKit.mesh_node(st, LandmarkKit.material(0.5, 0.6), "SignPost", 300.0))
	var facing := -track.tangent(s)
	facing.y = 0.0
	var basis := Basis.looking_at(-facing.normalized())
	for k in 2:
		var plate := MeshInstance3D.new()
		plate.name = "RoundaboutSign" if k == 0 else "GiveWaySign"
		var quad := QuadMesh.new()
		quad.size = Vector2(0.9, 0.9)
		plate.mesh = quad
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = _signs_textures()[k]
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.roughness = 0.5
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		plate.material_override = mat
		plate.transform = Transform3D(basis, foot + Vector3.UP * (2.6 if k == 0 else 1.65) + facing.normalized() * 0.07)
		plate.visibility_range_end = 300.0
		add_child(plate)


## The two sign faces, drawn once: a blue disc with three white arrows
## chasing round it, and a white triangle (point down) with a red border.
static func _signs_textures() -> Array[Texture2D]:
	if not _sign_tex.is_empty():
		return _sign_tex
	var n := 128
	var blue := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var give := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n, n) * 0.5
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5) - c
			var r := p.length() / (n * 0.5)
			var col := Color(0, 0, 0, 0)
			if r <= 0.97:
				col = Color(0.93, 0.93, 0.93) if r > 0.91 else Color(0.05, 0.32, 0.66)
				var ang := fposmod(atan2(p.y, p.x), TAU / 3.0) / (TAU / 3.0)
				# Arrow shafts on a ring, each ending in a head.
				if r > 0.40 and r < 0.56 and ang < 0.62:
					col = Color.WHITE
				var head := ang >= 0.62 and ang < 0.86 and absf(r - 0.48) < 0.20 * (0.86 - ang) / 0.24
				if head:
					col = Color.WHITE
			blue.set_pixel(x, y, col)
			# Inverted triangle: top edge at y = 0.1 n, point at y = 0.92 n.
			var v := (y + 0.5) / n
			var u := (x + 0.5) / n - 0.5
			var half := (0.92 - v) / 0.82 * 0.47
			var tri := Color(0, 0, 0, 0)
			if v >= 0.10 and v <= 0.92 and absf(u) <= half:
				var inner := v >= 0.20 and v <= 0.74 and absf(u) <= half - 0.10
				tri = Color.WHITE if inner else Color(0.80, 0.08, 0.08)
			give.set_pixel(x, y, tri)
	for img in [blue, give]:
		img.generate_mipmaps()
		_sign_tex.append(ImageTexture.create_from_image(img))
	return _sign_tex
