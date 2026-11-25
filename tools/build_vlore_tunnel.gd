extends SceneTree
## Bake the race spline's original bore and a terrain-backed limestone cut.
##   godot --headless --path godot --script ../tools/build_vlore_tunnel.gd
## The tool is visual only. No scene node carries a physics body or collider.
## See docs/vlore-out-and-back.md for the source scan and vertex bake.

const OUT := "res://assets/cities/vlore/tunnel.glb"
const SPRING := 3.5          # wall height before the arch (matches the old bore)
const RISE := 3.4            # arch rise: 6.9 m crown above the road
const ARCH := 16             # arch segments
const COLLAR := 1.4          # collar ring thickness
const COLLAR_DEPTH := 1.8    # how far each collar stands out of the cliff face
const DETAIL := preload("res://scripts/world/terrain_detail.gd")
const OFFSETS := [20., 18., 16., 14.8, 13.9, 13.1, 12.1, 11.3, 10.3, 9.45, 8.5, 7.3,
	5.6, 3.1, 0., -3., -6., -9.5, -13., -17., -22., -28., -34., -41., -49., -58., -68., -78.]
const BEDS := [0., 0., .028, .115, .155, .32, .36, .535, .60, .77, .82, 1.]
const FIRST_INLAND := 18
const SHELL_STEP := 1.8
const BORE_STEP := 3.0
const MAX_TRIS := 12000

var track: RaceTrack
## The game's near terrain grid, water carved as Terrain does it (no Terrain
## node: --script runs without the Quality autoload it reads).
var grid := {}
var heights := PackedFloat32Array()
var water_surface := 0.0
var origin := Vector3.ZERO
var half := 0.0
var clouds := FastNoiseLite.new()
var cells := FastNoiseLite.new()
var tris := 0
var entrance := 0.0
var run := 0.0
var detail := DETAIL.new()


func _initialize() -> void:
	track = RaceTrack.load_city("vlore", false)
	_load_ground()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cities/vlore/track.json"))
	var start := track.locate_xz(data.tunnel[0][0], data.tunnel[0][1]).x
	var length := track.mod_s(track.locate_xz(data.tunnel[1][0], data.tunnel[1][1]).x - start)
	entrance = start
	run = length
	half = track.half_w + 1.18
	origin = track.pos(start, 0.0)
	clouds.noise_type = FastNoiseLite.TYPE_SIMPLEX
	clouds.frequency = 0.045
	clouds.fractal_octaves = 3
	clouds.seed = 7
	cells.noise_type = FastNoiseLite.TYPE_CELLULAR
	cells.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	cells.frequency = 0.09
	cells.seed = 11

	var root := Node3D.new()
	root.name = "UjiIFtohte"
	# glTF import drops the scene root's transform: the offset goes on each
	# placed mesh node instead.
	var rock := _material("cliff_rock", Color(0.78, 0.75, 0.70), 0.9)
	var masonry := _material("portal_masonry", Color(0.72, 0.70, 0.66), 0.86)
	var interior := _material("tunnel_interior", Color(0.46, 0.45, 0.43), 0.8)
	var lights := _material("ceiling_lights", Color(1.0, 0.86, 0.62), 0.5)
	lights.emission_enabled = true
	lights.emission = Color(1.0, 0.80, 0.52)
	lights.emission_energy_multiplier = 2.4
	var scrub := _material("scrub", Color(0.20, 0.27, 0.13), 0.95)

	var cliff := ArrayMesh.new()
	_add(cliff, _shell(start, length), rock)
	for end in 2:
		var s := start if end == 0 else start + length
		_add(cliff, _portal_face(s, end == 0), rock)
		_add(cliff, _approach(s, end == 0), rock)
	_child(root, "Cliff", cliff)
	var portals := ArrayMesh.new()
	for end in 2:
		_add(portals, _collar(start if end == 0 else start + length, end == 0), masonry)
	_child(root, "Portals", portals)
	var wing_walls := ArrayMesh.new()
	for end in 2:
		_add(wing_walls, _wing_wall(start if end == 0 else start + length, end == 0), masonry)
	_child(root, "WingWalls", wing_walls)
	var bore := ArrayMesh.new()
	_add(bore, _bore(start, length), interior)
	_add(bore, _light_strips(start, length), lights)
	_child(root, "TunnelBore", bore)
	for i in 2:
		var bush := ArrayMesh.new()
		_add(bush, _bush(i), scrub)
		_child(root, "Scrub%d" % i, bush)

	_scatter(root, cliff, start, length)

	print("TUNNEL: %.1f m bore, %d triangles" % [length, tris])
	if tris > MAX_TRIS:
		printerr("over the %d triangle budget" % MAX_TRIS)
		quit(1)
		return
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	if err == OK:
		err = doc.write_to_filesystem(state, OUT)
	print("TUNNEL: wrote ", OUT, " (", error_string(err), ")")
	root.free()
	quit(0 if err == OK else 1)


func _material(slot: String, color: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = slot
	m.albedo_color = color
	m.roughness = rough
	return m


func _child(root: Node3D, node_name: String, mesh: ArrayMesh) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	if not node_name.begins_with("Scrub"):
		mi.position = origin
	root.add_child(mi)
	mi.owner = root
	# Boulder* and Scrub* are props at the root's origin: the game takes
	# their meshes for MultiMeshes and does not place the nodes.


func _add(mesh: ArrayMesh, st: SurfaceTool, material: Material) -> void:
	st.generate_normals()
	st.generate_tangents()
	var arrays := st.commit_to_arrays()
	var index = arrays[Mesh.ARRAY_INDEX]
	tris += (index.size() if index != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)


## World point at lap position s, d metres right of the centreline, y up from
## the road, relative to the root.
func _at(s: float, d: float, y: float) -> Vector3:
	return track.pos(s, d) + Vector3.UP * y - origin


func _load_ground() -> void:
	var dir := "res://assets/cities/vlore/"
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir + "terrain.json"))
	grid = meta.near
	heights = FileAccess.get_file_as_bytes(dir + "terrain_near.bin").to_float32_array()
	var mask := FileAccess.get_file_as_bytes(dir + "water_near.bin")
	water_surface = float(meta.water.surface)
	var bed := water_surface - 3.0   # Terrain.SEABED_DROP
	var floor_h := water_surface + 0.25  # Terrain.LAND_CLEARANCE
	for i in heights.size():
		heights[i] = minf(heights[i], bed) if mask[i] >= 128 else maxf(heights[i], floor_h)
	detail.load_bake(dir, grid, heights)
	detail.release_mesh_data()


## Height of the actual visual triangles, including localized hillside tiles.
func _height(x: float, z: float) -> float:
	var visual := detail.height_at(x, z)
	if not is_nan(visual):
		return visual
	return DETAIL._height(heights, int(grid.n), (x - float(grid.x0)) / float(grid.cell),
		(z - float(grid.z0)) / float(grid.cell))


## Indexed grid of rows x cols, every cell's triangles wound to face `toward`
## (a callable: cell centre -> direction). Shared vertices: smooth normals.
func _grid(rows: Array, toward: Callable, paint := Callable()) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols: int = (rows[0] as PackedVector3Array).size()
	for r in rows.size():
		for c in cols:
			var p: Vector3 = rows[r][c]
			st.set_uv(Vector2(p.x + p.y * 0.3, p.z + p.y * 0.3) * 0.12)
			if paint.is_valid():
				st.set_color(paint.call(r, c, p))
			st.add_vertex(p)
	for r in rows.size() - 1:
		for c in cols - 1:
			var ia := r * cols + c
			var ib := ia + 1
			var id := ia + cols
			var ic := id + 1
			var a: Vector3 = rows[r][c]
			var b: Vector3 = rows[r][c + 1]
			var d: Vector3 = rows[r + 1][c]
			var centre := (a + b + d + (rows[r + 1][c + 1] as Vector3)) * 0.25
			# Godot draws clockwise triangles as front faces.
			var n := (b - a).cross(d - a)
			var flip: bool = n.dot(toward.call(centre)) < 0.0
			for t in ([ia, ic, ib, ia, id, ic] if not flip else [ia, ib, ic, ia, ic, id]):
				st.add_index(t)
	return st


## Terraced seaward face, irregular roof and a long inland tie-in. Dips and
## fault offsets deform the beds together instead of embossing each section.
func _cliff_row(s: float) -> PackedVector3Array:
	var row := PackedVector3Array()
	var q := s - entrance
	var road_y := track.height(s)
	var fault := smoothstep(-1.2, 1.2, q - 33.0) - smoothstep(-1.8, 1.8, q - 67.0)
	var crest := 15.2 + 3.8 * clouds.get_noise_2d(q, 19.0) + 2.6 * fault + 1.6 * sin(q * .075 + .6)
	var face_setback := 1.3 * sin(q * .092) + 2.3 * clouds.get_noise_2d(q, 80.0) + 1.45 * fault
	for c in OFFSETS.size():
		var d: float = OFFSETS[c]
		var shifting := smoothstep(3.0, 8.0, d) * (1.0 - smoothstep(14.0, 20.0, d))
		d += shifting * face_setback
		var p := _terrain_point(s, d)
		var ground := _height(p.x + origin.x, p.z + origin.z)
		var crest_notch := -3.6 * smoothstep(.25, .68, clouds.get_noise_2d(q * 1.6, d * 2.1 + 166.0))
		var rock := crest + crest_notch + _relief(p, crest + road_y) * 1.55
		var y := rock + road_y
		if c < BEDS.size():
			# The low bench widens at bedding planes and drops under the sea
			# floor at the toe; the upper bench can flare out under the crown.
			var bed: float = BEDS[c]
			var toe := minf(ground, water_surface) - .9
			y = lerpf(toe, y, bed)
			y += sin(bed * PI) * _relief(p, y) * 1.55
		else:
			var back := maxf(0., -d)
			var uplift := 2.7 * smoothstep(2., 17., back) + 1.1 * sin(d * .31 + q * .045)
			var saddle := road_y + rock + .16 * back + uplift + _relief(p, y)
			var edge := smoothstep(25., 78., back)
			y = lerpf(saddle, ground - .65, edge)
		p.y = y - origin.y
		row.append(p)
	return row


func _terrain_point(s: float, d: float) -> Vector3:
	var p := _at(s, d, 0.0)
	# On the deep inland skirt, gradually stop following the tightly
	# curving road normal. This prevents offset cross-sections folding.
	var weight := smoothstep(22.0, 72.0, -d)
	var shore_axis := track.normal(entrance + run * .52)
	return p.lerp(track.pos(s, 0.0) - origin + d * shore_axis, weight)


func _relief(p: Vector3, y: float) -> float:
	var w := Vector3(p.x + origin.x, y, p.z + origin.z)
	var warp := clouds.get_noise_3dv(w)
	var joint := 1.0 + cells.get_noise_3dv(Vector3(w.x, w.y * .52, w.z))
	return 1.15 * warp - .66 * (1.0 - smoothstep(.015, .21, joint)) + .22 * sin(y * 1.65 + .075 * w.x - .12 * w.z + warp * 3.6)


func _shell(start: float, length: float) -> SurfaceTool:
	var rings := ceili(length / SHELL_STEP)
	var rows := []
	for i in rings + 1:
		rows.append(_cliff_row(start + length * i / rings))
	return _grid(rows, func(_p: Vector3) -> Vector3: return Vector3.UP, _coat.bind(rows, 0))


## A graded inland cut with talus at its toe and offset limestone shelves.
## The outer and far edges are buried in the sampled hillside.
func _approach(s: float, entry: bool) -> SurfaceTool:
	var rows := []
	var direction := -1.0 if entry else 1.0
	var reach := 46.0 if entry else 52.0
	for i in 23:
		var t := float(i) / 22.0
		var at := s + direction * reach * t
		var depth := _cliff_row(at)
		var row := PackedVector3Array()
		var toe_d := -9.15 - 5.4 * t - 1.6 * sin(t*PI) * clouds.get_noise_2d(at, 28.0)
		var toe := _terrain_point(at, toe_d)
		toe.y = _height(toe.x + origin.x, toe.z + origin.z) - origin.y - .55
		var setback := smoothstep(0., .48, t) * (5.1 + 2.2 * sin(at*.13))
		var crown: Vector3 = depth[FIRST_INLAND]
		var retain := 1.0 - smoothstep(.015, 1.0, t)
		for j in 5:
			var width: float = [0., .21, .39, .73, .91][j]
			var height: float = [0., .17, .29, .57, .74][j]
			var p := _terrain_point(at, lerpf(toe_d, -13.0-setback, width))
			var ground := _height(p.x + origin.x, p.z + origin.z) - origin.y
			p.y = lerpf(ground - .55, lerpf(toe.y, crown.y, height) + width * _relief(p, crown.y + origin.y), retain)
			row.append(p)
		for c in range(FIRST_INLAND, depth.size()):
			var p: Vector3 = depth[c]
			var u := smoothstep(0., 6., c - FIRST_INLAND)
			var bent := _terrain_point(at, OFFSETS[c] - setback * (1.0-u))
			p.x = bent.x
			p.z = bent.z
			var ground := _height(p.x + origin.x, p.z + origin.z) - origin.y
			p.y = lerpf(ground - .7, p.y, retain)
			row.append(p)
		rows.append(row)
	return _grid(rows, func(_p: Vector3) -> Vector3: return Vector3.UP, _coat.bind(rows, FIRST_INLAND - 5))


## Bake a local horizon on the triangulated height surface into vertex R.
## G controls exposed rock versus scrub/soil and B carries fracture depth.
func _coat(r: int, c: int, p: Vector3, rows: Array, first: int) -> Color:
	var horizon := 0.0
	for offset in [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
			Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]:
		var angle := 0.0
		for step in [1, 3, 6]:
			var nr := clampi(r + offset.y * step, 0, rows.size() - 1)
			var nc := clampi(c + offset.x * step, 0, rows[nr].size() - 1)
			var delta: Vector3 = rows[nr][nc] - p
			angle = maxf(angle, maxf(0., delta.y) / maxf(delta.length(), .01))
		horizon += angle
	var d: float = OFFSETS[c + first]
	var exposed := (1.0 - smoothstep(33.0, 69.0, -d)) * (1.0 - smoothstep(15.0, 20.0, d))
	if first > 0:
		exposed *= smoothstep(0., 2., c) * (1.0 - smoothstep(.50, 1., float(r) / (rows.size() - 1)))
	var gap := 1.0 + cells.get_noise_3dv((p + origin) * Vector3(1.0, .48, 1.0))
	var fracture := 1.0 - smoothstep(.018, .26, gap)
	return Color(clampf(1.0 - horizon * .092, .58, 1.0), exposed, fracture)


## The bore's cross-section: walls, the arch, and back down.
func _bore_profile(s: float, grow := 0.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	var h := half + grow
	out.append(_at(s, -h, -0.3))
	out.append(_at(s, -h, 1.4))
	for k in ARCH + 1:
		var a := PI * (1.0 - float(k) / ARCH)
		out.append(_at(s, cos(a) * h, SPRING + (RISE + grow) * sin(a)))
	out.append(_at(s, h, 1.4))
	out.append(_at(s, h, -0.3))
	return out


func _bore(start: float, length: float) -> SurfaceTool:
	var rings := ceili(length / BORE_STEP)
	var rows := []
	for i in rings + 1:
		rows.append(_bore_profile(start + length * i / rings))
	return _grid(rows, func(p: Vector3) -> Vector3:
		var s := track.locate_xz(p.x + origin.x, p.z + origin.z).x
		return (_at(s, 0.0, 2.6) - p).normalized())


## Two warm strips either side of the crown, 4 m long every 6 m.
func _light_strips(start: float, length: float) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := start + 3.0
	while s + 4.0 < start + length - 2.0:
		for side: float in [-0.75, 0.75]:
			var y := SPRING + RISE * sqrt(maxf(0.0, 1.0 - pow(side / half, 2.0))) - 0.06
			var a := _at(s, side - 0.14, y)
			var b := _at(s + 4.0, side - 0.14, y)
			var c := _at(s + 4.0, side + 0.14, y)
			var d := _at(s, side + 0.14, y)
			var n := (b - a).cross(d - a)
			var order := [a, b, c, a, c, d] if n.y > 0.0 else [a, c, b, a, d, c]
			for p: Vector3 in order:
				st.set_uv(Vector2.ZERO)
				st.add_vertex(p)
		s += 6.0
	st.index()
	return st


## Cast-concrete collar: soffit, front face and outer band round the arch.
func _collar(s: float, entry: bool) -> SurfaceTool:
	var out_dir := -1.0 if entry else 1.0
	var back := _bore_profile(s)
	var front := _bore_profile(s + out_dir * COLLAR_DEPTH)
	var front_outer := _bore_profile(s + out_dir * COLLAR_DEPTH, COLLAR)
	var back_outer := _bore_profile(s - out_dir * 0.6, COLLAR)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var axis := _at(s, 0.0, 2.6)
	var outward := track.tangent(s) * out_dir
	for band: Array in [[back, front, "in"], [front, front_outer, "face"], [front_outer, back_outer, "out"]]:
		var p0: PackedVector3Array = band[0]
		var p1: PackedVector3Array = band[1]
		for k in p0.size() - 1:
			var a := p0[k]
			var b := p0[k + 1]
			var c := p1[k + 1]
			var d := p1[k]
			var toward := outward
			if band[2] == "in":
				toward = (axis - (a + b) * 0.5).normalized()
			elif band[2] == "out":
				toward = ((a + b) * 0.5 - axis).normalized()
			var n := (b - a).cross(d - a)
			var order := [a, c, b, a, d, c] if n.dot(toward) >= 0.0 else [a, b, c, a, c, d]
			var recess := 1.0 if band[2] == "in" else (.33 if band[2] == "out" else 0.0)
			for p: Vector3 in order:
				_concrete_vertex(st, p, s, recess)
	st.index()
	return st


## Jagged quarry-like face around each unchanged collar opening.
func _portal_face(s: float, entry: bool) -> SurfaceTool:
	var out_dir := -1.0 if entry else 1.0
	var shell := _cliff_row(s)
	var rim := _resample(_bore_profile(s, COLLAR + .06), shell.size())
	var rows := []
	var layers := 8
	var tangent := track.tangent(s) * out_dir
	for l in layers + 1:
		var t := float(l) / layers
		var row := PackedVector3Array()
		for c in shell.size():
			var p := rim[c].lerp(shell[c], t)
			var world := p + origin
			var wave := _relief(p, world.y)
			var bedding := sin(world.y * 1.38 + world.x*.11 - world.z*.15 + wave*.70)
			var gash := smoothstep(.08,.56,clouds.get_noise_3dv(world*1.24))
			var ledge := -.8 + wave * 2.45 + bedding * 1.0 - gash * 3.4
			p += tangent * sin(t * PI) * ledge
			if c >= FIRST_INLAND and c < FIRST_INLAND + 3:
				# Dipping foot beds close the corner behind the retaining wing.
				p.y -= sin(t * PI) * (1.8 + absf(wave)) * (1.0 - (c-FIRST_INLAND)/3.0)
			row.append(p)
		rows.append(row)
	var paint := func(r: int, c: int, p: Vector3) -> Color:
		var ao := _coat(r, c, p, rows, 0)
		ao.r *= lerpf(.66, 1.0, smoothstep(0.0, 4.0, r))
		ao.g = 1.0 if c < FIRST_INLAND else ao.g
		return ao
	return _grid(rows, func(_p: Vector3) -> Vector3: return tangent, paint)


## Poured-concrete abutment on the inland approach. The battered face
## and cap stay behind the shoulder and butt into the rock above it.
func _wing_wall(s: float, entry: bool) -> SurfaceTool:
	var direction := -1.0 if entry else 1.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 8:
		var edge := PackedVector3Array()
		for j in [i, i + 1]:
			var t := float(j) / 8.0
			var at := s + direction * (1.0 + 13.0 * t)
			var d := lerpf(-half - .94, -half - 4.2, t)
			var top := maxf(.32, 4.55 * pow(1.0 - t, .69))
			edge.append_array(PackedVector3Array([_at(at, d + .14, -.62), _at(at, d, top), _at(at, d - .78, top)]))
		_concrete_quad(st, edge[0], edge[3], edge[4], edge[1], track.normal(s), s, .0)
		_concrete_quad(st, edge[1], edge[4], edge[5], edge[2], Vector3.UP, s, .5)
		if i == 7:
			_concrete_quad(st, edge[3], _at(s + direction * 14.0, -half - 4.98, -.62),
				edge[5], edge[4], track.tangent(s) * direction, s, .15)
	st.index()
	return st


func _concrete_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		facing: Vector3, s: float, recess: float) -> void:
	var n := (b - a).cross(d - a)
	var order := [a, c, b, a, d, c] if n.dot(facing) >= 0.0 else [a, b, c, a, c, d]
	for p: Vector3 in order:
		_concrete_vertex(st, p, s, recess)


func _concrete_vertex(st: SurfaceTool, p: Vector3, s: float, recess: float) -> void:
	var relative := p - _at(s, 0.0, 0.0)
	var d := relative.dot(track.normal(s))
	var along := relative.dot(track.tangent(s))
	var ao := clampf(.70 + .26 * smoothstep(-.15, 2.8, relative.y) - recess * .24, .42, .98)
	st.set_uv(Vector2(d + along * .58, relative.y))
	st.set_color(Color(ao, recess, 0.0))
	st.add_vertex(p)


## n points along a polyline, evenly by arc length, from the sea-side end to
## the inland end (the bore profile runs left to right: reverse it to match).
func _resample(line: PackedVector3Array, n: int) -> PackedVector3Array:
	var pts := line.duplicate()
	pts.reverse()
	var lengths := [0.0]
	for i in range(1, pts.size()):
		lengths.append(lengths[-1] + pts[i].distance_to(pts[i - 1]))
	var out := PackedVector3Array()
	var j := 0
	for k in n:
		var target: float = lengths[-1] * k / (n - 1)
		while j < pts.size() - 2 and lengths[j + 1] < target:
			j += 1
		var span: float = lengths[j + 1] - lengths[j]
		out.append(pts[j].lerp(pts[j + 1], 0.0 if span <= 0.0 else (target - lengths[j]) / span))
	return out


## Crossed, inclinable sprays of lentisk/maquis foliage from the shared atlas.
func _bush(variant: int) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + variant
	for leaf in range(11 + variant * 2):
		var theta := float(leaf) * 2.399 + rng.randf_range(-.22, .22)
		var branch := Vector3(cos(theta), 0.0, sin(theta))
		var axis := branch.cross(Vector3.UP) * rng.randf_range(.16, .31)
		var root := branch * rng.randf_range(.04,.30)
		var tip := branch * rng.randf_range(.31,.83) + Vector3.UP * rng.randf_range(.34,.76)
		var uv_x := .50 if leaf % 3 else 0.0
		var points := [root-axis, root+axis, tip+axis, tip-axis]
		var uvs := [Vector2(uv_x+.002,.99), Vector2(uv_x+.248,.99), Vector2(uv_x+.248,.01), Vector2(uv_x+.002,.01)]
		var tint := Color(.49, .57, .34).lerp(Color(.78, .75, .49), rng.randf() * .62)
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_color(tint)
			st.set_uv(uvs[i])
			st.add_vertex(points[i])
	return st


## Project decorative anchors onto the baked cut once, during the bake.
## The shipped scene just instances the prototypes at these fixed sites.
func _scatter(root: Node3D, cliff: ArrayMesh, start: float, length: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7341
	var faces := cliff.get_faces()
	var counts := {"TalusSite": 0, "MaquisSite": 0}
	for end in 2:
		var s := start if end == 0 else start + length
		var sign_out := -1.0 if end == 0 else 1.0
		for i in 26:
			var reach := rng.randf_range(3.5, 40.0)
			var inland := rng.randf_range(10.5, 23.5)
			var p := _at(s + reach * sign_out, -inland, 0.0)
			var contact := _scatter_contact(p, faces)
			var normal := Vector3(contact.y, contact.z, contact.w)
			var plant := i >= 13
			if plant and normal.y < .66:
				continue
			p.y = contact.x
			var width := rng.randf_range(.36, 1.12)
			if plant:
				width *= 1.25
				p.y -= .08
			_scatter_marker(root, "MaquisSite" if plant else "TalusSite", p,
				Vector3.UP if plant else normal, width, rng, counts)
			if not plant:
				for j in rng.randi_range(3, 6):
					var angle := rng.randf() * TAU
					var radial := rng.randf_range(.32, 1.15) * width
					var q := p + Vector3(cos(angle), 0., sin(angle)) * radial
					var world := q + origin
					if track.dist_to(world.x, world.z) < track.half_w + 4.6:
						continue
					var ground := _scatter_contact(q, faces)
					q.y = ground.x
					var contact_normal := Vector3(ground.y, ground.z, ground.w)
					if absf(q.y - p.y) < 1.6:
						_scatter_marker(root, "TalusSite", q, contact_normal,
							rng.randf_range(.096, .29), rng, counts)


func _scatter_marker(root: Node3D, prefix: String, p: Vector3, up: Vector3,
		width: float, rng: RandomNumberGenerator, counts: Dictionary) -> void:
	var yaw := rng.randf() * TAU
	var axis := (Vector3(cos(yaw), 0., sin(yaw)) - up * up.dot(Vector3(cos(yaw), 0., sin(yaw)))).normalized()
	var marker := Node3D.new()
	marker.name = "%s%03d" % [prefix, counts[prefix]]
	counts[prefix] += 1
	marker.transform = Transform3D(Basis(axis, up, axis.cross(up)).scaled(Vector3.ONE * width), p + origin)
	root.add_child(marker)
	marker.owner = root


func _scatter_contact(p: Vector3, faces: PackedVector3Array) -> Vector4:
	var world := p + origin
	var best := _height(world.x, world.z) - origin.y
	var normal := Vector3(_height(world.x-.6, world.z) - _height(world.x+.6, world.z),
		1.2, _height(world.x, world.z-.6) - _height(world.x, world.z+.6)).normalized()
	for i in range(0, faces.size(), 3):
		var a := faces[i]
		var b := faces[i+1]
		var c := faces[i+2]
		if p.x < minf(a.x, minf(b.x, c.x)) or p.x > maxf(a.x, maxf(b.x, c.x)) or (
				p.z < minf(a.z, minf(b.z, c.z)) or p.z > maxf(a.z, maxf(b.z, c.z))):
			continue
		var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3(p.x, 65.0, p.z), Vector3.DOWN, a, b, c)
		if hit != null and hit.y > best:
			best = hit.y
			normal = (c-a).cross(b-a).normalized()
			if normal.y < 0.0:
				normal = -normal
	return Vector4(best, normal.x, normal.y, normal.z)
