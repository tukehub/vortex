extends SceneTree
## Bakes the Uji i Ftohtë coastal tunnel into one mobile glTF:
##   godot --headless --path godot --script ../tools/build_vlore_tunnel.gd
## Reads  the race spline (RaceTrack, track.json "tunnel" portals) and the
##        baked Vlorë terrain, so the bore, portals and cliff sit exactly on
##        the road the cars drive.
## Writes res://assets/cities/vlore/tunnel.glb, world coordinates under one
##        root placed at the southern-approach portal:
##   Cliff        cliff_rock       smooth limestone mass over the bore, its
##                                 inland foot buried in the hillside, its
##                                 portal faces round both collars
##   Portals      portal_masonry   arched cast-concrete collars, 1.8 m deep
##   TunnelBore   tunnel_interior  arched concrete lining
##                ceiling_lights   warm emissive strips along the crown
##   Boulder0..3  cliff_rock       angular shoreline boulders (MultiMesh use)
##   Scrub0..1    scrub            low Mediterranean bushes (MultiMesh use)
## No Blender: subdivided cross-sections, FastNoiseLite displacement (clouds
## plus Voronoi cells and bedding) and smoothed normals stand in for the
## Subdivision / Displace / Auto Smooth stack. Budget: under 12k triangles.

const OUT := "res://assets/cities/vlore/tunnel.glb"
const SPRING := 3.5          # wall height before the arch (matches the old bore)
const RISE := 3.4            # arch rise: 6.9 m crown above the road
const ARCH := 16             # arch segments
const COLLAR := 1.4          # collar ring thickness
const COLLAR_DEPTH := 1.8    # how far each collar stands out of the cliff face
const SEA_FOOT := 13.0       # metres from the centreline, sea side
const LAND_FOOT := 34.0      # inland, where the cliff has sunk into the hill
const SHELL_COLS := 30
const SHELL_STEP := 2.0      # metres between cliff cross-sections
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


func _initialize() -> void:
	track = RaceTrack.load_city("vlore", false)
	_load_ground()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cities/vlore/track.json"))
	var start := track.locate_xz(data.tunnel[0][0], data.tunnel[0][1]).x
	var length := track.mod_s(track.locate_xz(data.tunnel[1][0], data.tunnel[1][1]).x - start)
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
		_add(cliff, _portal_face(start if end == 0 else start + length, end == 0), rock)
	_child(root, "Cliff", cliff)
	var portals := ArrayMesh.new()
	for end in 2:
		_add(portals, _collar(start if end == 0 else start + length, end == 0), masonry)
	_child(root, "Portals", portals)
	var bore := ArrayMesh.new()
	_add(bore, _bore(start, length), interior)
	_add(bore, _light_strips(start, length), lights)
	_child(root, "TunnelBore", bore)
	for i in 4:
		var boulder := ArrayMesh.new()
		_add(boulder, _boulder(i), rock)
		_child(root, "Boulder%d" % i, boulder)
	for i in 2:
		var bush := ArrayMesh.new()
		_add(bush, _bush(i), scrub)
		_child(root, "Scrub%d" % i, bush)

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
	if not (node_name.begins_with("Boulder") or node_name.begins_with("Scrub")):
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


## Terrain height (world) at world x, z: bilinear, as Terrain.height_at.
func _height(x: float, z: float) -> float:
	var n := int(grid.n)
	var fx := (x - float(grid.x0)) / float(grid.cell)
	var fz := (z - float(grid.z0)) / float(grid.cell)
	var ix := clampi(int(fx), 0, n - 2)
	var iz := clampi(int(fz), 0, n - 2)
	var tx := clampf(fx - ix, 0.0, 1.0)
	var tz := clampf(fz - iz, 0.0, 1.0)
	return lerpf(lerpf(heights[iz * n + ix], heights[iz * n + ix + 1], tx),
		lerpf(heights[(iz + 1) * n + ix], heights[(iz + 1) * n + ix + 1], tx), tz)


## Terrain height under a root-relative point, relative to the road there.
func _ground(p: Vector3) -> float:
	var w := p + origin
	return _height(w.x, w.z) - track.pos(track.locate_xz(w.x, w.z).x, 0.0).y


## Indexed grid of rows x cols, every cell's triangles wound to face `toward`
## (a callable: cell centre -> direction). Shared vertices: smooth normals.
func _grid(rows: Array, toward: Callable) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols: int = (rows[0] as PackedVector3Array).size()
	for row: PackedVector3Array in rows:
		for p in row:
			st.set_uv(Vector2(p.x + p.y * 0.3, p.z + p.y * 0.3) * 0.12)
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


## Rock offset (metres, along the surface normal) at a world point: rolling
## clouds, Voronoi blocks breaking along their edges, and bedding bands.
func _rock(p: Vector3) -> float:
	var w := p + origin
	var cloud := clouds.get_noise_3dv(w)
	var block := cells.get_noise_3dv(w)
	var bedding := 0.35 * sin(w.y * 1.7 + cloud * 3.0)
	return cloud * 1.3 + block * 0.9 + bedding


## Cliff cross-section at s: column 0 at the sea-side foot, last column buried
## in the hillside, smooth over the bore.
func _profile(s: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var foot_sea := minf(_ground(_at(s, SEA_FOOT, 0.0)), water_surface - track.height(s)) - 1.5
	for c in SHELL_COLS:
		var u := float(c) / (SHELL_COLS - 1)
		# Denser over the bore: u -> d with an ease.
		var d := lerpf(SEA_FOOT, -LAND_FOOT, pow(u, 1.35))
		var dome := 10.5 + 2.6 * cos(clampf(d / 9.0, -1.0, 1.0) * PI * 0.5)
		var y := dome
		if d > 9.0:
			y = lerpf(dome, foot_sea, smoothstep(9.0, SEA_FOOT, d))
		elif d < -9.0:
			var hill := _ground(_at(s, d, 0.0)) - 1.2
			y = lerpf(dome, hill, smoothstep(-8.0, -LAND_FOOT, d))
		out.append(_at(s, d, y))
	return out


func _shell(start: float, length: float) -> SurfaceTool:
	var rings := ceili(length / SHELL_STEP)
	var rows := []
	for i in rings + 1:
		var s := start + length * i / rings
		var row := _profile(s)
		var n := track.normal(s)
		for c in row.size():
			var prev: Vector3 = row[maxi(0, c - 1)]
			var next: Vector3 = row[mini(row.size() - 1, c + 1)]
			var along := (next - prev).normalized()
			# Outward: perpendicular to the section, away from the bore.
			var out := along.cross(track.tangent(s)).normalized()
			if out.y < 0.0:
				out = -out
			var u := float(c) / (SHELL_COLS - 1)
			var fade := smoothstep(0.0, 0.08, u) * (1.0 - smoothstep(0.78, 1.0, u))
			row[c] += out * _rock(row[c]) * 1.4 * fade
		rows.append(row)
	return _grid(rows, func(p: Vector3) -> Vector3: return (p - _at(start + length * 0.5, 0.0, 2.0)).normalized())


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
			for p: Vector3 in order:
				st.set_uv(Vector2(p.x + p.z, p.y) * 0.25)
				st.add_vertex(p)
	st.index()
	return st


## The rock face round a portal: from the collar's outer band out to the
## cliff's cross-section, bulging gently, its sharp edge against the shell.
func _portal_face(s: float, entry: bool) -> SurfaceTool:
	var out_dir := -1.0 if entry else 1.0
	var shell := _profile(s)
	var rim := _resample(_bore_profile(s - out_dir * 0.6, COLLAR + 0.05), shell.size())
	var rows := []
	var layers := 4
	var tangent := track.tangent(s) * out_dir
	for l in layers + 1:
		var t := float(l) / layers
		var row := PackedVector3Array()
		for c in shell.size():
			var p := rim[c].lerp(shell[c], t)
			var bulge := sin(t * PI) * (0.6 + 0.5 * _rock(p))
			p += tangent * bulge
			# Inland of the collar the face settles onto the hillside just
			# outside the portal: no fin of rock standing over the approach.
			var d := (p + origin - track.pos(s, 0.0)).dot(track.normal(s))
			if d < -half - COLLAR - 1.0:
				var outside := p + tangent * 5.0
				var settle := smoothstep(half + COLLAR + 1.0, half + COLLAR + 7.0, -d)
				p.y = minf(p.y, lerpf(p.y, _ground(outside) + track.height(s) - origin.y + 0.4, settle))
			row.append(p)
		rows.append(row)
	return _grid(rows, func(_p: Vector3) -> Vector3: return tangent)


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


## An angular boulder about 1.6 m across: a jittered icosphere, faceted.
func _boulder(variant: int) -> SurfaceTool:
	var rng := RandomNumberGenerator.new()
	rng.seed = 400 + variant
	var sphere := SphereMesh.new()
	sphere.radial_segments = 7
	sphere.rings = 4
	sphere.radius = 0.8
	sphere.height = 1.25
	var faces := sphere.get_faces()
	var moved := {}
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in faces:
		var key := Vector3i((p * 100.0).round())
		if not moved.has(key):
			moved[key] = p * Vector3(rng.randf_range(0.8, 1.25), rng.randf_range(0.7, 1.1), rng.randf_range(0.8, 1.25))
		var q: Vector3 = moved[key]
		st.set_uv(Vector2(q.x + q.y, q.z) * 0.5)
		st.add_vertex(q + Vector3.UP * 0.35)
	return st


## A low rounded shrub of three overlapping lobes, 1-1.6 m tall.
func _bush(variant: int) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + variant
	for lobe in 3:
		var sphere := SphereMesh.new()
		sphere.radial_segments = 6
		sphere.rings = 3
		sphere.radius = rng.randf_range(0.5, 0.8)
		sphere.height = sphere.radius * rng.randf_range(1.2, 1.7)
		var at := Vector3(rng.randf_range(-0.5, 0.5), sphere.height * 0.42, rng.randf_range(-0.5, 0.5))
		for p in sphere.get_faces():
			st.set_uv(Vector2(p.x, p.z))
			st.add_vertex(p + at)
	return st
