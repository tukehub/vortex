class_name SeaRocks
extends Node3D
## Real shoreline traces seed limestone revetment clusters and wave spray.
const ROAD_REACH := 140.0
const MAX_WALK := 30.0
const SPRAY_POOL := 3
const SPRAY_NEAR := 18.0
const SPRAY_FAR := 120.0
## Landmark id -> half-size (m) of the shore window armoured around it.
const ANCHORS := {"waterfront_courts": 420.0}
const COURTS := preload("res://scripts/world/vlore_sports_courts.gd")

var stones := 0
## Every stone placed (MultiMesh data is not kept by the headless renderer).
var placed: Array[Transform3D] = []
## World positions of the outer-row stones, where spray can rise.
var spray_points := PackedVector3Array()
var _spray: Array[GPUParticles3D] = []
var _spray_t := 0.0
var _rng := RandomNumberGenerator.new()
var field: RockField


## Anchor windows along the seawall near the courts. Preserve the real
## shoreline coverage while leaving gaps between irregular rock clusters.
func build(terrain: Terrain, track: RaceTrack, anchors: Array) -> void:
	_rng.seed = 7311
	field = RockField.new()
	field.name = "RockField"
	add_child(field)
	field.start(terrain)
	var occupied := {}
	var surge := FastNoiseLite.new()
	surge.seed = 147
	surge.frequency = .037
	for anchor: Dictionary in anchors:
		var centre := Vector2(float(anchor.x), float(anchor.z))
		var yaw := deg_to_rad(float(anchor.get("yaw", 0.0)))
		for seg in _contour(terrain, centre, float(anchor.radius)):
			_seed_segment(seg[0], seg[1], terrain, track, occupied, surge, centre, yaw)
	field.finish()
	placed = field.placed
	stones = placed.size()
	_make_spray()


func _seed_segment(a: Vector2, b: Vector2, terrain: Terrain, track: RaceTrack,
		occupied: Dictionary, surge: FastNoiseLite, courts: Vector2, yaw: float) -> void:
	var length := a.distance_to(b)
	if length < .1:
		return
	var strike := (b-a) / length
	var level := terrain.water_surface
	var count := ceili(length / 5.8)
	for i in count:
		var p := a.lerp(b, (i + _rng.randf_range(.08,.92)) / count)
		var strength := surge.get_noise_2dv(p)
		if _rng.randf() > .76 + strength * .53:
			continue
		var road := track.dist_to(p.x, p.y)
		if road > ROAD_REACH:
			continue
		var n := track.nearest(p.x, p.y, ROAD_REACH + 20.0)
		if n < 0:
			continue
		var inland := (Vector2(track.X[n], track.Z[n]) - p).normalized()
		var walk := 0.0
		var limit := minf(MAX_WALK, road - track.half_w - 4.0)
		while walk < limit and terrain.surface_height_at(p.x + inland.x*walk, p.y + inland.y*walk) < level:
			walk += .55
		if walk >= limit:
			continue
		var bank := p + inland*walk
		var key := Vector2i((bank / 4.25).floor())
		if occupied.has(key):
			continue
		occupied[key] = true
		var at := bank + inland * _rng.randf_range(1.15, 4.45)
		var allowed := func(q: Vector2, width: float) -> bool:
			var g := terrain.surface_height_at(q.x, q.y) - level
			var reach := (q-bank).dot(inland)
			var distance := track.dist_to(q.x, q.y)
			return (g > -3.1 and g < 3.4 and reach > -3.2 and reach < 9.4
				and distance >= track.half_w + 2.7 + width*.68 and distance <= ROAD_REACH
				and not COURTS.overlaps_footing((q-courts).rotated(yaw), width*.76))
		var radius := _rng.randf_range(2.1, 5.8)
		var width := _rng.randf_range(1.3, 2.42) * (1. + strength*.28)
		if field.cluster(at, strike, radius, width, .96, allowed, _rng) > 0:
			var toe := bank - inland * 1.1
			spray_points.append(Vector3(toe.x, level + .25, toe.y))


## Waterline segments (pairs of world XZ points) in a square window.
func _contour(terrain: Terrain, centre: Vector2, radius: float) -> Array:
	var segs := []
	var n := int(terrain.near.n)
	var cell := float(terrain.near.cell)
	var x0 := float(terrain.near.x0)
	var z0 := float(terrain.near.z0)
	var i0 := clampi(int((centre.x - radius - x0) / cell), 0, n - 2)
	var i1 := clampi(int((centre.x + radius - x0) / cell), 0, n - 2)
	var j0 := clampi(int((centre.y - radius - z0) / cell), 0, n - 2)
	var j1 := clampi(int((centre.y + radius - z0) / cell), 0, n - 2)
	var mask := terrain.water_mask
	var code := func(i: int, j: int) -> float: return float(mask[j * n + i]) - 127.5
	for j in range(j0, j1):
		for i in range(i0, i1):
			var c := [code.call(i, j), code.call(i + 1, j), code.call(i + 1, j + 1), code.call(i, j + 1)]
			var corners := [Vector2(i, j), Vector2(i + 1, j), Vector2(i + 1, j + 1), Vector2(i, j + 1)]
			var cross := []
			for e in 4:
				var a: float = c[e]
				var b: float = c[(e + 1) % 4]
				if (a < 0.0) != (b < 0.0):
					var t := a / (a - b)
					var g: Vector2 = (corners[e] as Vector2).lerp(corners[(e + 1) % 4], t)
					cross.append(Vector2(x0 + g.x * cell, z0 + g.y * cell))
			if cross.size() == 2:
				segs.append([cross[0], cross[1]])
			elif cross.size() == 4:
				segs.append([cross[0], cross[1]])
				segs.append([cross[2], cross[3]])
	return segs


func _make_spray() -> void:
	if spray_points.is_empty():
		return
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.6
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 38.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	pm.damping_min = 0.5
	pm.damping_max = 1.5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.9))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	var fade := GradientTexture1D.new()
	fade.gradient = ramp
	pm.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.85, 0.9, 0.92)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = FxVisual._glow_texture()
	quad.material = mat
	for i in SPRAY_POOL:
		var p := GPUParticles3D.new()
		p.name = "Spray%d" % i
		p.amount = 70
		p.lifetime = 1.3
		p.one_shot = true
		p.explosiveness = 0.85
		p.emitting = false
		p.process_material = pm
		p.draw_pass_1 = quad
		p.visibility_aabb = AABB(Vector3(-6, -2, -6), Vector3(12, 10, 12))
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		_spray.append(p)


## Every frame with the camera position: now and then a wave bursts on a
## stone in view. Off on low quality and under pressure (fx_extras).
## Returns true when a burst started.
func update(camera: Vector3, dt: float) -> bool:
	if _spray.is_empty() or not bool(Quality.p.get("fx_extras", true)):
		return false
	_spray_t -= dt
	if _spray_t > 0.0:
		return false
	_spray_t = _rng.randf_range(0.45, 1.1)
	for attempt in 12:
		var at := spray_points[_rng.randi() % spray_points.size()]
		var d := at.distance_to(camera)
		if d > SPRAY_NEAR and d < SPRAY_FAR:
			var p := _spray[_rng.randi() % _spray.size()]
			if p.emitting:
				continue
			p.global_position = at
			p.restart()
			return true
	return false
