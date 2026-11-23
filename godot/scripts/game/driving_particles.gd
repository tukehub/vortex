extends RefCounted
## Fixed GPU emitter pools owned by FxVisual. Continuous effects read the
## rendered car pose and simulation state; they never write to the simulation.

const Trail = preload("res://scripts/game/exhaust_trail.gd")
var trails: Array[Trail] = []
const KINDS := ["smoke", "exhaust", "spray", "scrape", "debris"]
const AMOUNTS := {"smoke": 7, "exhaust": 4, "spray": 5, "scrape": 5, "debris": 3}
const LIFETIMES := {"smoke": 0.52, "exhaust": 0.16, "spray": 0.4, "scrape": 0.19, "debris": 0.32}
var pools := {}
var allocated := 0
var _idle := true

func _init(parent: Node3D, caps: Dictionary, texture: Texture2D) -> void:
	var ribbon := QuadMesh.new()
	var ribbon_mat := ShaderMaterial.new()
	ribbon_mat.shader = preload("res://shaders/exhaust_ribbon.gdshader")
	ribbon.size = Vector2.ONE
	ribbon.material = ribbon_mat
	for i in int(caps.exhaust):
		var trail := Trail.new(ribbon)
		parent.add_child(trail)
		trails.append(trail)
		allocated += 1
	for kind in KINDS:
		pools[kind] = []
		var mesh: PrimitiveMesh = QuadMesh.new()
		match kind:
			"smoke": mesh.size = Vector2.ONE * 0.85
			"scrape":
				mesh = BoxMesh.new()
				mesh.size = Vector3(0.019, 0.19, 0.019)
			"debris":
				mesh = BoxMesh.new()
				mesh.size = Vector3(0.055, 0.032, 0.08)
			_: mesh.size = Vector2.ONE * 0.18
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if kind in ["exhaust", "scrape"] else BaseMaterial3D.BLEND_MODE_MIX
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.vertex_color_use_as_albedo = true
		mat.albedo_texture = texture
		if kind == "smoke":
			mat.albedo_texture = _smoke_texture()
		if kind in ["scrape", "debris"]:
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
			mat.albedo_texture = null
		if kind == "debris":
			mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		mesh.material = mat
		var process := ParticleProcessMaterial.new()
		process.direction = Vector3(0, 0.15, 1)
		process.spread = 30.0
		process.initial_velocity_min = 1.0 if kind == "smoke" else 3.0
		process.initial_velocity_max = 3.0 if kind == "smoke" else 6.0
		process.gravity = Vector3(0, 0.9 if kind == "smoke" else -2.0, 0)
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		process.emission_box_extents = Vector3(0.08, 0.02, 0.06)
		if kind == "exhaust":
			process.emission_box_extents *= 0.4
		if kind in ["scrape", "debris"]:
			process.gravity = Vector3.DOWN * 11.0
			process.direction = Vector3(0, 0.35, 1)
			process.initial_velocity_max = 9.0
		if kind == "smoke":
			var expansion := CurveTexture.new()
			expansion.curve = Curve.new()
			expansion.curve.add_point(Vector2(0.0, 0.32))
			expansion.curve.add_point(Vector2(1.0, 1.0))
			process.scale_curve = expansion
		if kind == "scrape":
			process.particle_flag_align_y = true
		if kind == "debris":
			process.particle_flag_rotate_y = true
			process.angle_max = 180.0
			process.angular_velocity_max = 240.0
			process.angular_velocity_min = -240.0
		process.scale_min = 0.5
		process.scale_max = 1.5
		var color := Color(0.65, 0.68, 0.72, 0.44)
		match kind:
			"exhaust": color = Color(0.4, 1.4, 3.0, 0.85)
			"debris": color = Color(0.32, 0.29, 0.26)
			"spray": color = Color(0.72, 0.83, 0.93, 0.35)
			"scrape": color = Color(3.0, 1.4, 0.25, 1.0)
		var gradient := Gradient.new()
		gradient.set_color(0, Color(color, 0.0))
		gradient.set_color(1, Color(color, 0.0))
		gradient.add_point(0.12, color)
		var ramp := GradientTexture1D.new()
		ramp.gradient = gradient
		process.color_ramp = ramp
		for i in int(caps[kind]):
			var emitter := GPUParticles3D.new()
			emitter.name = kind + str(i)
			emitter.emitting = false
			emitter.visible = false
			emitter.amount = int(AMOUNTS[kind])
			emitter.one_shot = kind in ["scrape", "exhaust", "debris"]
			emitter.explosiveness = 0.95 if emitter.one_shot else 0.0
			emitter.lifetime = float(LIFETIMES[kind])
			emitter.local_coords = false
			emitter.fixed_fps = 30
			emitter.interpolate = true
			emitter.visibility_aabb = AABB(Vector3(-8, -4, -8), Vector3(16, 12, 24))
			emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			emitter.process_material = process
			emitter.draw_pass_1 = mesh
			parent.add_child(emitter)
			pools[kind].append({"node": emitter, "key": "", "claimed": false, "tail": 0.0})
			allocated += 1

## Bake a small irregular puff once for all wheel emitters. Filtering the
## opacity here keeps the particle fragment pass to one texture lookup.
static func _smoke_texture() -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.seed = 17
	noise.frequency = 0.075
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var radius := Vector2(x - 31.5, y - 31.5).length() / 31.5
			var cloud := noise.get_noise_2d(x, y)
			var density := 1.0 - smoothstep(0.10, 1.0, radius + cloud * 0.22)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, density * (0.7 + 0.3 * cloud)))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func reset() -> void:
	if _idle:
		return
	_idle = true
	for trail in trails:
		trail.clear()
	for kind in KINDS:
		for slot: Dictionary in pools[kind]:
			var emitter: GPUParticles3D = slot.node
			emitter.emitting = false
			emitter.hide()
			slot.key = ""
			slot.tail = 0.0
			slot.claimed = false

func update(cars: Array, visuals: Dictionary, focus: Vector3, dt: float, running: bool, wet: bool, contacts := {}) -> void:
	if int(Quality.p.driving_cars) <= 0 or not running:
		reset()
		return
	_idle = false
	var candidates: Array[CarState] = []
	for c: CarState in cars:
		var visual: CarVisual = visuals.get(c)
		if is_instance_valid(visual) and visual.is_visible_in_tree() and c.wreck_t <= 0.0 and not c.finished and visual.global_position.distance_squared_to(focus) < 65.0 * 65.0:
			candidates.append(c)
	candidates.sort_custom(func(a: CarState, b: CarState):
		if a.is_player != b.is_player:
			return a.is_player
		return (visuals[a] as CarVisual).global_position.distance_squared_to(focus) < (visuals[b] as CarVisual).global_position.distance_squared_to(focus))
	_update_trails(candidates, visuals, dt)
	for kind in KINDS:
		for slot: Dictionary in pools[kind]:
			slot.was_claimed = slot.claimed
			slot.claimed = false
		var cars_used := 0
		for c in candidates:
			var grounded := c.hop < 0.15
			var moving := absf(c.v) > 10.0
			var slip := absf(c.lat) if c is ArenaCar else absf(c.lat_v)
			var active := false
			match kind:
				"smoke": active = grounded and moving and (c.drift > 0.45 or slip > 5.5) and not wet
				"exhaust": active = c.nitro_t > 0.0
				"spray": active = grounded and moving and wet
				"scrape": active = grounded and moving and c.scrape > 0.3
				"debris": active = grounded and moving and c.scrape > 0.72 and c.is_player and int(Quality.p.driving_cars) == 3
			if kind in ["scrape", "debris"] and c is ArenaCar and not contacts.has(c):
				continue
			if not active:
				continue
			var visual: CarVisual = visuals[c]
			for side in ([-1, 1] if kind in ["smoke", "spray"] else [0]):
				var pose := _source_pose(kind, c, visual, side, contacts)
				_claim(kind, "%d:%d" % [c.id, side], pose)
			cars_used += 1
			if cars_used >= int(Quality.p.driving_cars):
				break
		for slot: Dictionary in pools[kind]:
			var emitter: GPUParticles3D = slot.node
			if not slot.claimed:
				emitter.emitting = false
				slot.tail = maxf(0.0, float(slot.tail) - dt)
				emitter.visible = slot.tail > 0.0

func _source_pose(kind: String, c: CarState, visual: CarVisual, side: int, contacts: Dictionary) -> Transform3D:
	if kind == "exhaust":
		return visual.nitro_jets[posmod(c.id, 2)].global_transform.orthonormalized()
	var pose := visual.global_transform
	if side != 0:
		var wheel: Node3D = visual.wheels.get("wheel_rl" if side < 0 else "wheel_rr")
		var fallback := Vector3(side * float(c.def.size.x) * 0.36, 0.3, float(c.def.size.z) * 0.33)
		pose.origin = wheel.global_position if wheel else visual.to_global(fallback)
		var height_offset := 0.12 if kind == "smoke" else 0.0
		pose.origin -= visual.global_basis.y * (visual.visual_wheel_radius * 0.8 - height_offset)
	else:
		var flank := Vector3(signf(c.d) * float(c.def.size.x) * 0.5, 0.35, 0.0)
		pose.origin = contacts.get(c, visual.to_global(flank))
	return pose

func _claim(kind: String, key: String, pose: Transform3D) -> void:
	var chosen: Dictionary = {}
	for slot: Dictionary in pools[kind]:
		if slot.key == key and not slot.claimed:
			chosen = slot
			break
	if chosen.is_empty():
		for slot: Dictionary in pools[kind]:
			if not slot.claimed:
				chosen = slot
				break
	if chosen.is_empty():
		return
	var emitter: GPUParticles3D = chosen.node
	# Drop stale world-space trails on slot reuse or teleport/respawn.
	var reset_trail: bool = chosen.key != key or emitter.global_position.distance_squared_to(pose.origin) > 20.0 * 20.0
	emitter.global_transform = pose
	if emitter.one_shot:
		if reset_trail or not chosen.was_claimed:
			emitter.restart()
			emitter.emitting = true
	elif reset_trail or not emitter.emitting:
		emitter.restart()
		emitter.emitting = true
	emitter.show()
	chosen.key = key
	chosen.claimed = true
	chosen.tail = emitter.lifetime

func snapshot() -> Dictionary:
	var counts := {}
	for kind in KINDS:
		counts[kind] = 0
		for slot: Dictionary in pools[kind]:
			if (slot.node as GPUParticles3D).emitting:
				counts[kind] += 1
	return counts

func _update_trails(candidates: Array[CarState], visuals: Dictionary, dt: float) -> void:
	var active: Array[int] = []
	for c in candidates:
		if c.nitro_t > 0.0:
			active.append(c.id)
			if active.size() == int(Quality.p.driving_cars):
				break
	for trail in trails:
		if trail.owner_id != -1 and not active.has(trail.owner_id):
			trail.clear()
	for c in candidates:
		if not active.has(c.id):
			continue
		var available: Trail
		for trail in trails:
			if trail.owner_id == c.id:
				available = trail
				break
			if trail.owner_id == -1:
				available = trail
		available.follow(c.id, visuals[c], dt)
