class_name RoadMesh
extends Node3D
## Builds the race road from a RaceTrack: asphalt surface with UV (u across,
## v along), kerbs, a skirt down to the terrain, and start/finish line.

const Showcase := preload("res://scripts/world/tirana_showcase.gd")
const ROAD_SHADER := preload("res://shaders/road.gdshader")
const KERB_H := 0.14
const KERB_W := 0.5
const BARRIER_H := 0.5
const SKIRT := 6.0
const KERB_RED := Color(0.58, 0.075, 0.055)
const KERB_WHITE := Color(0.72, 0.72, 0.68)

var surface_mat: ShaderMaterial
var kerb_mat: StandardMaterial3D
var skirt_mat: StandardMaterial3D
var surface: MeshInstance3D
var pavement_mat: StandardMaterial3D
var _showcase := false
var _reverse := false
var length := 0.0
var barrier_mat: StandardMaterial3D
var _terrain_height := Callable()
## Samples on a city street (VloreBoulevard.street_samples; set before
## build): 1 where the street's own granite kerbs and sidewalks replace the
## race kerbs, barriers and shoulder.
var street := PackedByteArray()
## Per sample: the side (-1, 1) facing the island where the passes part at a
## split (RaceTrack.splits); 0 elsewhere. The island has its own kerb there.
var split_side := PackedFloat32Array()


func build(track: RaceTrack, hw: float, wet: float, terrain_height := Callable(), reverse := false) -> void:
	length = track.L
	_showcase = track.id == "tirane"
	_reverse = reverse
	_terrain_height = terrain_height
	surface_mat = ShaderMaterial.new()
	surface_mat.shader = ROAD_SHADER
	surface_mat.set_shader_parameter("tex_asphalt", load("res://assets/textures/asphalt_diff.jpg"))
	surface_mat.set_shader_parameter("tex_asphalt_n", load("res://assets/textures/asphalt_nor.jpg"))
	surface_mat.set_shader_parameter("tex_asphalt_r", load("res://assets/textures/asphalt_arm.jpg"))
	surface_mat.set_shader_parameter("half_w", hw)
	surface_mat.set_shader_parameter("track_len", track.L)
	# A sprint finishes beside the start: the chequer across the other carriageway too.
	surface_mat.set_shader_parameter("finish_s", track.finish_s if track.sprint else -1.0)
	surface_mat.set_shader_parameter("wetness", wet)
	if _showcase:
		surface_mat.set_shader_parameter("showcase_length", Showcase.LENGTH)
		surface_mat.set_shader_parameter("showcase_direction", -1.0 if _reverse else 1.0)

	kerb_mat = StandardMaterial3D.new()
	kerb_mat.vertex_color_use_as_albedo = true
	kerb_mat.roughness = 0.86
	skirt_mat = StandardMaterial3D.new()
	skirt_mat.albedo_color = Color(0.46, 0.44, 0.40)
	skirt_mat.albedo_texture = load("res://assets/textures/concrete_diff.jpg")
	skirt_mat.roughness = 0.95

	split_side = split_sides(track)
	_build_surface(track, hw)
	_build_kerbs(track, hw)
	_build_edge_barriers(track, hw)
	_build_skirt(track, hw)
	if _showcase:
		_build_showcase_pavement(track, hw)
	set_wet(wet)
	surface_mat.set_shader_parameter("crossing_map", ImageTexture.create_from_image(crossing_lookup(PackedVector2Array(), track.L)))
	apply_quality()
	if not Quality.budget_changed.is_connected(apply_quality):
		Quality.budget_changed.connect(apply_quality)


## Lungomare's mountable median down the middle of the joined road: 2 m
## across, rounded shoulders up to a 10 cm crown (RaceTrack.median_lift, the
## same profile the cars ride over). Off a joined road it follows the
## centreline.
func add_paved_median(track: RaceTrack, start: float, length_m: float) -> void:
	var mesh := LandmarkKit.begin()
	var steps := maxi(1, ceili(length_m / 2.0))
	var across := [-1.0, -0.84, -0.68, -0.54, -0.45, 0.45, 0.54, 0.68, 0.84, 1.0]
	var curb := Color("#cec5ac")
	var brick := Color("#b1a18a")
	var previous: Array[Vector3] = []
	for i in steps + 1:
		var a := length_m * i / steps
		var at := start + a
		var ease := smoothstep(0.0, RaceTrack.MEDIAN_EASE, minf(a, length_m - a))
		var middle := track.join_offset(at) if track.joined(at) else 0.0
		var lift_y := pair_rise(track, at)
		var row: Array[Vector3] = []
		for x: float in across:
			var profile := RaceTrack.MEDIAN_H * ease * (1.0 - smoothstep(RaceTrack.MEDIAN_TOP, RaceTrack.MEDIAN_HALF, absf(x)))
			row.append(track.pos(at, middle + x) + Vector3.UP * (lift_y + maxf(0.006, profile)))
		if not previous.is_empty():
			for j in across.size() - 1:
				var top := absf(across[j]) < RaceTrack.MEDIAN_TOP + 0.01 and absf(across[j + 1]) < RaceTrack.MEDIAN_TOP + 0.01
				var color := brick.lerp(brick.darkened(0.08), 0.5 + 0.5 * sin(i * 2.1)) if top else curb.darkened(0.05 * absf(across[j]))
				LandmarkKit.quad_facing(mesh, previous[j], row[j], row[j + 1], previous[j + 1], color, Vector3.UP)
		previous = row
	var mat := LandmarkKit.material(0.89)
	mat.albedo_texture = preload("res://assets/textures/cobble_diff.jpg")
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3.ONE * 1.6
	var median := LandmarkKit.mesh_node(mesh, mat, "LungomarePavedMedian", 1400.0)
	median.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(median)


## Rise from this pass's centreline to the middle of the joined road at `s`
## (half the height step to the other pass; ~0 once the passes are levelled).
static func pair_rise(track: RaceTrack, s: float) -> float:
	var k := posmod(roundi(s / track.ds), track.M)
	return (track.Y[track.PAIR[k]] - track.Y[k]) * 0.5 if track.PAIR[k] >= 0 else 0.0


## Zebra crossings (plan 3.5) from props.json "road_marks": world [x, z,
## width, inferred] rows, projected onto this lap (either direction). Where
## the two passes are one road (Vlorë), a crossing is painted on both halves.
## At most MAX_CROSSINGS, nearest the start first; returns the (s, width)
## pairs used.
const MAX_CROSSINGS := 48

func set_crossings(track: RaceTrack, rows: Array, include_showcase := false) -> PackedVector2Array:
	var marks := PackedVector2Array()
	var mirrors := PackedVector2Array()
	for row in rows:
		if marks.size() >= MAX_CROSSINGS:
			break
		var x := float(row[0])
		var z := float(row[1])
		if track.dist_to(x, z) > track.half_w + 1.0:
			continue
		var at := track.locate_xz(x, z)
		if track.hidden(at.x):
			continue
		marks.append(Vector2(at.x, float(row[2])))
		var k := posmod(roundi(at.x / track.ds), track.M)
		if track.PAIR.size() == track.M and track.PAIR[k] >= 0:
			# Antiparallel: forward along this pass is back along the other.
			mirrors.append(Vector2(track.mod_s(track.PAIR[k] * track.ds - (at.x - k * track.ds)), float(row[2])))
	for mirror in mirrors:
		if marks.size() >= MAX_CROSSINGS:
			break
		# The other half may have its own mapped node for the same crossing.
		var clear := true
		for mark in marks:
			if absf(track.wrap_s(mark.x - mirror.x)) <= 55.0:
				clear = false
				break
		if clear:
			marks.append(mirror)
	if include_showcase and _showcase:
		var direction := -1.0 if _reverse else 1.0
		for distance: float in [Showcase.CROSSINGS.x, Showcase.CROSSINGS.y, Showcase.CROSSINGS.z]:
			if marks.size() >= MAX_CROSSINGS:
				break
			var at := track.mod_s(distance * direction)
			var clear := true
			for mark in marks:
				if absf(track.wrap_s(mark.x - at)) <= 55.0:
					clear = false
					break
			if clear:
				marks.append(Vector2(at, 3.4))
	var padded := marks.duplicate()
	padded.resize(MAX_CROSSINGS)
	surface_mat.set_shader_parameter("crossings", padded)
	surface_mat.set_shader_parameter("crossing_count", marks.size())
	crossing_map = crossing_lookup(marks, track.L)
	surface_mat.set_shader_parameter("crossing_map", ImageTexture.create_from_image(crossing_map))
	return marks


## The shader's per-pixel crossing lookup: one R8 texel per CROSSING_CELL
## metres of lap holding the index + 1 of the crossing whose paint (and the
## stop lines 2.2 m beyond it) reaches that cell, or 0. Crossings are at
## least 55 m apart, so no cell needs two.
const CROSSING_CELL := 8.0
var crossing_map: Image

static func crossing_lookup(marks: PackedVector2Array, lap: float) -> Image:
	var cells := maxi(1, ceili(lap / CROSSING_CELL))
	var data := PackedByteArray()
	data.resize(cells)
	data.fill(0)
	for i in marks.size():
		var reach := marks[i].y * 0.5 + 3.0
		var c0 := floori((marks[i].x - reach) / CROSSING_CELL)
		var c1 := floori((marks[i].x + reach) / CROSSING_CELL)
		for c in range(c0, c1 + 1):
			data[posmod(c, cells)] = i + 1
	return Image.create_from_data(cells, 1, false, Image.FORMAT_R8, data)


## Lanes per carriageway and whether traffic is one-way (track.json
## "lanes" / "one_way"): an out-and-back circuit races each direction on its
## own two-lane carriageway, marked with a dashed white centre.
var lane_count := 4

func set_layout(lanes: int, one_way: bool) -> void:
	lane_count = maxi(1, lanes)
	surface_mat.set_shader_parameter("lane_count", float(lane_count))
	surface_mat.set_shader_parameter("one_way", one_way)


## The shader's sin-free cell hash (road.gdshader cell_hash).
static func cell_hash(c: float, salt: float) -> float:
	var p3 := Vector3(fposmod(c * 0.1031, 1.0), fposmod(salt * 0.1031, 1.0), fposmod(c * 0.1031, 1.0))
	var d := p3.dot(Vector3(p3.y, p3.z, p3.x) + Vector3.ONE * 33.33)
	p3 += Vector3.ONE * d
	return fposmod((p3.x + p3.y) * p3.z, 1.0)


## Where road.gdshader sets hardware between lap positions s0 and s1:
## [{"kind": "manhole" | "gully", "s": metres, "d": metres across}].
## Mirrors the shader's cell rules; lane_count is the shader default (4).
static func hardware_near(s0: float, s1: float, hw: float, lane_count := 4.0) -> Array:
	var out := []
	var lane_w := 2.0 * hw / lane_count
	for c in range(floori(s0 / 22.0), floori(s1 / 22.0) + 1):
		if cell_hash(c, 6.1) < 0.5:
			var lane := floorf(cell_hash(c, 3.7) * lane_count)
			out.append({"kind": "manhole", "s": (c + 0.2 + 0.6 * cell_hash(c, 2.2)) * 22.0, "d": -hw + lane_w * (lane + 0.5)})
	for c in range(floori(s0 / 24.0), floori(s1 / 24.0) + 1):
		if cell_hash(c, 7.3) < 0.85:
			var side := -1.0 if cell_hash(c, 1.9) < 0.5 else 1.0
			out.append({"kind": "gully", "s": (c + 0.5) * 24.0, "d": side * (hw - 0.86)})
	return out.filter(func(h): return float(h.s) >= s0 and float(h.s) <= s1)


## Manholes and gullies cost a few ALU ops a pixel; low skips them.
func apply_quality() -> void:
	surface_mat.set_shader_parameter("detail", 1.0 if bool(Quality.p.get("road_detail", true)) else 0.0)


func set_wet(w: float) -> void:
	surface_mat.set_shader_parameter("wetness", w)
	var wet := clampf(w, 0.0, 1.0)
	kerb_mat.roughness = lerpf(0.86, 0.67, wet)
	kerb_mat.albedo_color = Color.WHITE.darkened(wet * 0.12)
	skirt_mat.albedo_color = Color(0.46, 0.44, 0.40).darkened(wet * 0.16)
	skirt_mat.roughness = lerpf(0.95, 0.82, wet)
	if pavement_mat != null:
		pavement_mat.roughness = lerpf(0.91, 0.69, wet)
		pavement_mat.albedo_color = Color.WHITE.darkened(wet * 0.24)
	if barrier_mat != null:
		barrier_mat.roughness = lerpf(0.88, 0.7, wet)
		barrier_mat.albedo_color = Color.WHITE.darkened(wet * 0.1)


func _build_surface(track: RaceTrack, hw: float) -> void:
	var M := track.M
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Cross sections of 7 verts: shoulder, its middle, -hw, 0, hw, middle,
	# shoulder. Where the other pass runs alongside (Vlorë), that side runs on
	# to the middle of the joined road instead, and tucks 15 cm past it, 3 cm
	# down, under the other pass's half: one surface, no seam to see through.
	# UV2 tells the shader: x = side joined (-1 left, 1 right, 0), y = metres
	# from the centreline to the road's middle.
	var shoulder := KERB_W + 0.6
	var ring := 7
	for i in M + 1:
		var k := i % M
		var s := i * track.ds
		var p := Vector3(track.X[k], track.Y[k], track.Z[k])
		var nx := track.NX[k]
		var nz := track.NZ[k]
		var up := Vector3(track.TX[k], track.TY[k], track.TZ[k]).cross(Vector3(nx, 0.0, nz)).normalized()
		if up.y < 0.0:
			up = -up
		var side_joined := joined_side(track, k)
		var side_isle := isle_side(track, k) if side_joined == 0.0 else 0.0
		var mid := absf(track.JOIN[k]) if side_joined != 0.0 else hw + shoulder
		# The two passes meet half way between their centres' heights.
		var mid_dy := pair_rise(track, k * track.ds)
		var cols: Array[Vector3] = []   # across, rise, alpha
		for side: float in [-1.0, 1.0]:
			var pair: Array[Vector3]
			if side == side_joined:
				pair = [Vector3(side * (mid + 0.15), mid_dy - 0.03, 1.0), Vector3(side * mid, mid_dy, 1.0)]
			elif side == side_isle:
				# Toward a roundabout island: level asphalt, then the apron.
				pair = [Vector3(side * (hw + 0.8), -0.01, 1.0), Vector3(side * (hw + 0.4), 0.0, 1.0)]
			else:
				pair = [Vector3(side * (hw + shoulder), -0.02, 0.0), Vector3(side * (hw + shoulder * 0.5), -0.01, 0.5)]
			if side > 0.0:
				pair.reverse()
				cols.append_array([Vector3(-hw, 0.0, 1.0), Vector3(0.0, 0.0, 1.0), Vector3(hw, 0.0, 1.0)])
			cols.append_array(pair)
		for col in cols:
			st.set_normal(up)
			st.set_uv(Vector2(col.x, s))
			# Island side: no edge line or gutter, and no centre line (far y).
			st.set_uv2(Vector2(side_joined, mid) if side_isle == 0.0 else Vector2(side_isle, 1000.0))
			st.set_color(Color(1, 1, 1, col.z))
			st.add_vertex(p + Vector3(nx, 0.0, nz) * col.x + Vector3(0, col.y, 0))
	for i in M:
		if hidden_segment(track, i):
			continue
		var a := i * ring
		var b := (i + 1) * ring
		for xi in ring - 1:
			# clockwise = front face in Godot
			st.add_index(a + xi)
			st.add_index(b + xi)
			st.add_index(a + xi + 1)
			st.add_index(a + xi + 1)
			st.add_index(b + xi)
			st.add_index(b + xi + 1)
	st.generate_tangents()
	surface = MeshInstance3D.new()
	surface.mesh = st.commit()
	surface.material_override = surface_mat
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)


## -1 or 1: the side of sample k on which the other pass runs alongside as
## one road (no kerb, barrier or shoulder there); 0: none.
static func joined_side(track: RaceTrack, k: int) -> float:
	if track.PAIR.size() != track.M or track.PAIR[k] < 0:
		return 0.0
	return -1.0 if track.JOIN[k] < 0.0 else 1.0


## -1 or 1: the side of sample k facing a roundabout island; 0: none.
static func isle_side(track: RaceTrack, k: int) -> float:
	return track.ISLE[k] if track.ISLE.size() == track.M else 0.0


## Which side of each sample faces a split's island: within reach of a
## split, unpaired, with the other pass within ISLAND_GAP (far along the lap).
const ISLAND_GAP := 36.0

static func split_sides(track: RaceTrack) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(track.M)
	if track.splits.is_empty():
		return out
	for sp: Vector3 in track.splits:
		var near := PackedInt32Array()
		for k in track.M:
			if Vector2(track.X[k], track.Z[k]).distance_to(Vector2(sp.x, sp.y)) < sp.z + 140.0:
				near.append(k)
		for k in near:
			if track.PAIR.size() == track.M and track.PAIR[k] >= 0:
				continue
			var p := Vector2(track.X[k], track.Z[k])
			var best := -1
			var bd := ISLAND_GAP * ISLAND_GAP
			for j in near:
				var gap := absi(j - k)
				if mini(gap, track.M - gap) * track.ds < 80.0:
					continue
				var d := p.distance_squared_to(Vector2(track.X[j], track.Z[j]))
				if d < bd:
					bd = d
					best = j
			if best >= 0:
				var q := Vector2(track.X[best], track.Z[best])
				out[k] = 1.0 if (q - p).dot(Vector2(track.NX[k], track.NZ[k])) > 0.0 else -1.0
	return out


## True when the segment from sample i to the next is on a sprint's hidden
## turn (RaceTrack.HIDE): nothing of the road is drawn there.
static func hidden_segment(track: RaceTrack, i: int) -> bool:
	return track.HIDE.size() == track.M and (track.HIDE[i] == 1 or track.HIDE[(i + 1) % track.M] == 1)


## True when the segment from sample i to the next runs along a city street.
func on_street(track: RaceTrack, i: int) -> bool:
	return street.size() == track.M and street[i] == 1 and street[(i + 1) % track.M] == 1


## True when the segment from sample i to the next is open on `side`: the
## other pass joins there, or it faces a roundabout island.
static func open_side(track: RaceTrack, i: int, side: float) -> bool:
	for k: int in [i, (i + 1) % track.M]:
		if joined_side(track, k) == side or isle_side(track, k) == side:
			return true
	return false


## Asphalt from each roundabout island's kerb out under the road around it,
## so the road runs round a circle with nothing but the kerb at its edge.
## Built with the road's own material, 2.5 cm under its surface.
func add_island_aprons(track: RaceTrack) -> void:
	if track.islands.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bins := 240
	for isle: Vector3 in track.islands:
		var c := Vector2(isle.x, isle.y)
		var r := isle.z
		var reach := PackedFloat32Array()
		for k in bins + 1:
			reach.append(apron_reach(track, c, r, TAU * k / bins))
		# Far from the road's frame: no lane marks, no edge or centre line.
		var off := Vector2(4000.0 - c.x, track.L * 0.5 - c.y)
		for k in bins:
			var a := TAU * k / bins
			var b := TAU * (k + 1) / bins
			var ua := Vector2(cos(a), sin(a))
			var ub := Vector2(cos(b), sin(b))
			var rings := [r, (r + minf(reach[k], reach[k + 1])) * 0.5]
			for ring_i in 2:
				var r0: float = rings[ring_i]
				var a1: float = rings[1] if ring_i == 0 else reach[k]
				var b1: float = rings[1] if ring_i == 0 else reach[k + 1]
				var quad := [c + ua * r0, c + ua * a1, c + ub * b1, c + ub * r0]
				for index in [0, 1, 2, 0, 2, 3]:
					var q: Vector2 = quad[index]
					st.set_normal(Vector3.UP)
					st.set_uv(q + off)
					st.set_uv2(Vector2(1.0, 0.0))
					st.set_color(Color(1, 1, 1, 1))
					st.add_vertex(Vector3(q.x, _apron_height(track, q, isle) - 0.025, q.y))
	st.generate_tangents()
	var apron := MeshInstance3D.new()
	apron.name = "RoundaboutAprons"
	apron.mesh = st.commit()
	apron.material_override = surface_mat
	apron.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(apron)


## Metres from an island's centre, along `angle`, to just under the road
## around it: a carriageway, or the joined middle where the passes meet (the
## gores between them). The island's radius (no apron) where nothing is hit.
static func apron_reach(track: RaceTrack, centre: Vector2, radius: float, angle: float) -> float:
	var u := Vector2(cos(angle), sin(angle))
	var t := radius
	while t < 85.0:
		var q := centre + u * t
		var n := track.nearest(q.x, q.y, track.half_w + 8.0)
		if n >= 0:
			var off := (q - Vector2(track.X[n], track.Z[n])).dot(Vector2(track.NX[n], track.NZ[n]))
			var along := absf((q - Vector2(track.X[n], track.Z[n])).dot(Vector2(-track.NZ[n], track.NX[n])))
			if along < track.ds * 1.5:
				if absf(off) < track.half_w:
					return t + 0.6
				if track.PAIR.size() == track.M and track.PAIR[n] >= 0 and absf(off - track.JOIN[n]) < absf(track.JOIN[n]) - track.half_w + 0.2:
					return t + 0.6
		t += 0.75
	return radius


static func _apron_height(track: RaceTrack, q: Vector2, isle: Vector3) -> float:
	var n := track.nearest(q.x, q.y, 40.0)
	if n < 0:
		n = track.nearest(isle.x, isle.y, 120.0)
	return track.Y[n] if n >= 0 else 0.0


func _build_kerbs(track: RaceTrack, hw: float) -> void:
	var M := track.M
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx := 0
	for side: float in [-1.0, 1.0]:
		for i in M:
			if open_side(track, i, side) or on_street(track, i) or hidden_segment(track, i) or split_side[i] == side or split_side[(i + 1) % track.M] == side:
				continue
			var k0 := i
			var k1 := (i + 1) % M
			var seg_col := KERB_RED if (i / 3) % 2 == 0 else KERB_WHITE
			if _showcase:
				var at := Showcase.forward_s(track, (i + 0.5) * track.ds, _reverse)
				var blend := smoothstep(0.0, 7.0, minf(at, Showcase.LENGTH - at))
				seg_col = seg_col.lerp(Color(0.66, 0.64, 0.60), blend)
			seg_col = seg_col.darkened(0.04 + 0.035 * (1.0 + sin(i * 0.37)))
			var pts: Array[Vector3] = []
			for k: int in [k0, k1]:
				var p := Vector3(track.X[k], track.Y[k], track.Z[k])
				var n := Vector3(track.NX[k], 0.0, track.NZ[k]) * side
				pts.append(p + n * hw)                                  # inner bottom
				pts.append(p + n * hw + Vector3(0, KERB_H, 0))         # inner top
				pts.append(p + n * (hw + KERB_W) + Vector3(0, KERB_H, 0))  # outer top
				pts.append(p + n * (hw + KERB_W) + Vector3(0, -0.05, 0))   # outer bottom
			# quads between cross sections 0..3 and 4..7
			for q in 3:
				var a := pts[q]
				var b := pts[q + 1]
				var c := pts[q + 5]
				var d := pts[q + 4]
				var nrm := (b - a).cross(d - a).normalized()
				if side > 0.0:
					nrm = -nrm
				for v in [a, b, c, d]:
					st.set_normal(nrm)
					st.set_color(seg_col)
					st.add_vertex(v)
				if side > 0.0:
					st.add_index(idx); st.add_index(idx + 2); st.add_index(idx + 1)
					st.add_index(idx); st.add_index(idx + 3); st.add_index(idx + 2)
				else:
					st.add_index(idx); st.add_index(idx + 1); st.add_index(idx + 2)
					st.add_index(idx); st.add_index(idx + 2); st.add_index(idx + 3)
				idx += 4
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = kerb_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_edge_barriers(track: RaceTrack, hw: float) -> void:
	# Low solid panels follow the existing road edge. They are visual only: the
	# simulation retains its existing collision boundary and handling.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx := 0
	for side: float in [-1.0, 1.0]:
		for i in track.M:
			if open_side(track, i, side) or on_street(track, i) or hidden_segment(track, i) or split_side[i] == side or split_side[(i + 1) % track.M] == side:
				continue
			var j := (i + 1) % track.M
			var color := KERB_RED if int(i * track.ds / 8.0) % 2 == 0 else KERB_WHITE
			if _showcase:
				var at := Showcase.forward_s(track, (i + 0.5) * track.ds, _reverse)
				var blend := smoothstep(0.0, 7.0, minf(at, Showcase.LENGTH - at))
				var guard := Color(0.59, 0.54, 0.49) if int(at / 8.0) % 2 == 0 else Color(0.76, 0.73, 0.67)
				color = color.lerp(guard, blend * 0.90)
			var a := Vector3(track.X[i], track.Y[i], track.Z[i]) + Vector3(track.NX[i], 0.0, track.NZ[i]) * side * (hw + KERB_W)
			var b := Vector3(track.X[j], track.Y[j], track.Z[j]) + Vector3(track.NX[j], 0.0, track.NZ[j]) * side * (hw + KERB_W)
			var normal := Vector3(track.NX[i], 0.0, track.NZ[i]) * -side
			for corner: Vector2 in [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]:
				var point := a.lerp(b, corner.x) + Vector3.UP * (corner.y * BARRIER_H)
				st.set_uv(Vector2((i + corner.x) * track.ds / 4.0, corner.y))
				st.set_color(color.darkened(0.18 if point.y < a.y + BARRIER_H * 0.5 else 0.0))
				st.set_normal(normal)
				st.add_vertex(point)
			for index in [0, 1, 2, 0, 2, 3]:
				st.add_index(idx + index)
			idx += 4
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.8
	mat.albedo_texture = preload("res://assets/textures/barrier_concrete.png")
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	barrier_mat = mat
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var barrier := MeshInstance3D.new()
	barrier.name = "RoadsideBarriers"
	barrier.mesh = st.commit()
	barrier.material_override = mat
	barrier.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(barrier)


func _build_skirt(track: RaceTrack, hw: float) -> void:
	# a sloped shoulder that drops to terrain level so the road never floats
	var M := track.M
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outer := hw + KERB_W + 0.6
	var idx := 0
	for side: float in [-1.0, 1.0]:
		for i in M:
			if open_side(track, i, side) or on_street(track, i) or hidden_segment(track, i) or split_side[i] == side or split_side[(i + 1) % track.M] == side:
				continue
			var k0 := i
			var k1 := (i + 1) % M
			var pts: Array[Vector3] = []
			for k: int in [k0, k1]:
				var p := Vector3(track.X[k], track.Y[k], track.Z[k])
				var n := Vector3(track.NX[k], 0.0, track.NZ[k]) * side
				pts.append(p + n * outer + Vector3(0, -0.02, 0))
				var edge := p + n * (outer + SKIRT)
				edge.y = float(_terrain_height.call(edge.x, edge.z)) + 0.015 if _terrain_height.is_valid() else p.y - 2.2
				pts.append(edge)
			var a := pts[0]
			var b := pts[1]
			var c := pts[3]
			var d := pts[2]
			var nrm := (b - a).cross(d - a).normalized()
			if side > 0.0:
				nrm = -nrm
			if nrm.y < 0.0:
				nrm = -nrm
			for v in [a, b, c, d]:
				st.set_normal(nrm)
				st.set_uv(Vector2(v.x, v.z) * 0.25)
				st.add_vertex(v)
			if side > 0.0:
				st.add_index(idx); st.add_index(idx + 2); st.add_index(idx + 1)
				st.add_index(idx); st.add_index(idx + 3); st.add_index(idx + 2)
			else:
				st.add_index(idx); st.add_index(idx + 1); st.add_index(idx + 2)
				st.add_index(idx); st.add_index(idx + 2); st.add_index(idx + 3)
			idx += 4
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = skirt_mat
	mi.name = "RoadShoulders"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_showcase_pavement(track: RaceTrack, hw: float) -> void:
	var st := LandmarkKit.begin()
	var steps := ceili(Showcase.LENGTH / track.ds)
	var direction := -1.0 if _reverse else 1.0
	var outer := hw + KERB_W
	for side: float in [-1.0, 1.0]:
		var previous: Array[Vector3] = []
		for i in steps + 1:
			var at := Showcase.LENGTH * i / steps
			var progress := smoothstep(0.0, 10.0, minf(at, Showcase.LENGTH - at))
			var ramp := smoothstep(1.0, 4.7, Showcase.crossing_distance(at))
			var s := at * direction
			var outer_point := track.pos(s, side * (outer + 0.55 + 2.25 * progress))
			var ground := float(_terrain_height.call(outer_point.x, outer_point.z)) if _terrain_height.is_valid() else outer_point.y - 0.06
			var edge := track.pos(s, side * (outer + 0.04)) + Vector3.UP * lerpf(0.04, KERB_H - 0.015, ramp)
			# Bury the outside edge into the existing shoulder, allowing the
			# sidewalk to follow its crossfall without moving terrain or the road.
			outer_point.y = lerpf(edge.y, maxf(outer_point.y + 0.035, ground - 0.03), progress)
			var seam := edge.lerp(outer_point, 0.80)
			var row: Array[Vector3] = [edge, seam, outer_point]
			if not previous.is_empty():
				var slab := Color(0.76, 0.73, 0.66).darkened(0.065 * (0.5 + 0.5 * sin(i * 7.01)))
				LandmarkKit.quad_facing(st, previous[0], row[0], row[1], previous[1], slab, Vector3.UP)
				LandmarkKit.quad_facing(st, previous[1], row[1], row[2], previous[2], slab.darkened(0.12), Vector3.UP)
			previous = row
	pavement_mat = LandmarkKit.material(0.91)
	pavement_mat.albedo_texture = preload("res://assets/textures/cobble_diff.jpg")
	pavement_mat.uv1_triplanar = true
	pavement_mat.uv1_scale = Vector3.ONE * 0.89
	var pavement := LandmarkKit.mesh_node(st, pavement_mat, "TiranaShowcasePavement", 650.0)
	pavement.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pavement)
