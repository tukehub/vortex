extends RefCounted
## Local visual height tiles. Bounds are quantized to 8 parent-grid cells so
## both the coarse terrain and the detailed tile can keep the same edge.

const BASE_CELLS := 8
const SUBDIVISIONS := 8
const CELLS := BASE_CELLS * SUBDIVISIONS
const STRIDE := CELLS + 1
const RECORD_BYTES := 5

var tiles := {} # Vector2i -> PackedFloat32Array of final elevations
var _offsets := {}
var _data: PackedByteArray
var _near := {}
var _base: PackedFloat32Array
var _span := 0.0
var _step := 0.0


func load_bake(dir: String, ground: Dictionary, base: PackedFloat32Array) -> void:
	if not FileAccess.file_exists(dir + "terrain_detail.json"):
		return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + "terrain_detail.json"))
	if not manifest is Dictionary or manifest.get("version", 0) != 1 or not manifest.get("tiles") is Array:
		push_warning("Ignoring unreadable terrain detail manifest")
		return
	var tile_bytes := STRIDE * STRIDE * RECORD_BYTES
	var count := (int(ground.n) - 1) / BASE_CELLS
	if manifest.tiles.is_empty():
		return
	if manifest.tiles.size() > count * count or not FileAccess.file_exists(dir + "terrain_detail.bin"):
		push_warning("Ignoring incomplete terrain detail bake")
		return
	var expected: int = manifest.tiles.size() * tile_bytes
	var raw := FileAccess.get_file_as_bytes(dir + "terrain_detail.bin").decompress(expected, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != expected:
		push_warning("Ignoring incomplete terrain detail bake")
		return
	var offsets := {}
	for i in manifest.tiles.size():
		var item: Variant = manifest.tiles[i]
		if not item is Array or item.size() != 2:
			push_warning("Ignoring terrain detail bake with invalid tile coordinates")
			return
		var key := Vector2i(int(item[0]), int(item[1]))
		if key.x < 0 or key.y < 0 or key.x >= count or key.y >= count or offsets.has(key):
			push_warning("Ignoring terrain detail bake with invalid tile coordinates")
			return
		offsets[key] = i * tile_bytes
	_data = raw
	_offsets = offsets
	_near = ground
	_base = base
	_step = float(ground.cell) / SUBDIVISIONS
	_span = _step * CELLS
	for key: Vector2i in _offsets:
		var h := PackedFloat32Array()
		h.resize(STRIDE * STRIDE)
		var offset: int = _offsets[key]
		for z in STRIDE:
			for x in STRIDE:
				var i := z * STRIDE + x
				var gx := (key.x * CELLS + x) / float(SUBDIVISIONS)
				var gz := (key.y * CELLS + z) / float(SUBDIVISIONS)
				h[i] = _height(_base, int(_near.n), gx, gz) + .01 * _data.decode_s16(offset + i * RECORD_BYTES)
		tiles[key] = h


func release_mesh_data() -> void:
	_data = PackedByteArray()
	_base = PackedFloat32Array()
	_offsets.clear()


func tile_origin(key: Vector2i) -> Vector2:
	return Vector2(float(_near.x0), float(_near.z0)) + Vector2(key) * _span


func height_at(x: float, z: float) -> float:
	if tiles.is_empty():
		return NAN
	var local := Vector2(x - float(_near.x0), z - float(_near.z0)) / _span
	var key := Vector2i(local.floor())
	if not tiles.has(key):
		return NAN
	var uv := (local - Vector2(key)) * CELLS
	return _height(tiles[key], STRIDE, uv.x, uv.y)


static func _height(data: PackedFloat32Array, stride: int, fx: float, fz: float) -> float:
	var x := mini(int(fx), stride - 2)
	var z := mini(int(fz), stride - 2)
	var i := z * stride + x
	var u := fx - x
	var v := fz - z
	var a := data[i]
	var b := data[i+1]
	var c := data[i+stride]
	var d := data[i+stride+1]
	return a + u*(b-a) + v*(c-a) + maxf(u+v-1.0, 0.0)*(d-b-c+a)


func _base_normal(gx: int, gz: int) -> Vector3:
	var n := int(_near.n)
	var dx := _base[gz*n + mini(gx+1, n-1)] - _base[gz*n + maxi(gx-1, 0)]
	var dz := _base[mini(gz+1, n-1)*n + gx] - _base[maxi(gz-1, 0)*n + gx]
	return Vector3(-dx, 2.0 * float(_near.cell), -dz).normalized()


func _transition_normal(key: Vector2i, x: int, z: int) -> Vector3:
	var fx := (key.x * CELLS + x) / float(SUBDIVISIONS)
	var fz := (key.y * CELLS + z) / float(SUBDIVISIONS)
	var n := int(_near.n)
	var gx := mini(int(fx), n-2)
	var gz := mini(int(fz), n-2)
	var u := fx - gx
	var v := fz - gz
	var a := _base_normal(gx, gz)
	var b := _base_normal(gx+1, gz)
	var c := _base_normal(gx, gz+1)
	var d := _base_normal(gx+1, gz+1)
	return (a + u*(b-a) + v*(c-a) + maxf(u+v-1., 0.)*(d-b-c+a)).normalized()


func _edge_height(key: Vector2i, h: PackedFloat32Array, x: int, z: int, dir: Vector2i) -> float:
	var px := x + dir.x
	var pz := z + dir.y
	if px >= 0 and px <= CELLS and pz >= 0 and pz <= CELLS:
		return h[pz*STRIDE + px]
	var neighbor: PackedFloat32Array = tiles.get(key + dir, h)
	if not tiles.has(key + dir):
		return h[z*STRIDE + x]
	return neighbor[(pz-dir.y*CELLS)*STRIDE + px-dir.x*CELLS]


func make_mesh(key: Vector2i, indices: PackedInt32Array, lods: Dictionary) -> ArrayMesh:
	var world := tile_origin(key)
	var h: PackedFloat32Array = tiles[key]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uv := PackedVector2Array()
	var colors := PackedColorArray()
	var tangent := PackedFloat32Array()
	verts.resize(h.size())
	norms.resize(h.size())
	uv.resize(h.size())
	colors.resize(h.size())
	tangent.resize(h.size()*4)
	var offset: int = _offsets[key]
	for z in STRIDE:
		for x in STRIDE:
			var i := z*STRIDE + x
			var wx := x*_step
			var wz := z*_step
			verts[i] = Vector3(wx-_span*.5, h[i], wz-_span*.5)
			uv[i] = world + Vector2(wx, wz)
			var p := offset + i*RECORD_BYTES
			var blend := _data[p+4] / 255.0
			colors[i] = Color(_data[p+2]/255.0, _data[p+3]/255.0, 0.0)
			# Centered differences cross tile boundaries, including at mixed LODs.
			var dx := _edge_height(key, h, x, z, Vector2i.RIGHT) - _edge_height(key, h, x, z, Vector2i.LEFT)
			var dz := _edge_height(key, h, x, z, Vector2i.DOWN) - _edge_height(key, h, x, z, Vector2i.UP)
			var normal := Vector3(-dx, 2.0*_step, -dz).normalized()
			norms[i] = _transition_normal(key, x, z).lerp(normal, blend).normalized() if blend < 1.0 else normal
			var tx := Vector3(norms[i].y, -norms[i].x, 0.).normalized()
			tangent[i*4] = tx.x
			tangent[i*4+1] = tx.y
			tangent[i*4+2] = tx.z
			tangent[i*4+3] = -1.
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TANGENT] = tangent
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods)
	return mesh
