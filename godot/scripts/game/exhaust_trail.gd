extends MultiMeshInstance3D
## Paired exhaust ribbons. Each history entry stores both outlets in world space.
## The newest segment follows the sockets between fixed-rate history samples.
const SAMPLES := 5
const INTERVAL := 0.025
const MAX_LENGTH := 3.0
var owner_id := -1
var left := PackedVector3Array()
var right := PackedVector3Array()
var count := 0
var elapsed := 0.0
var index := 0

func _init(quad: QuadMesh) -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = SAMPLES * 2
	left.resize(SAMPLES)
	right.resize(SAMPLES)
	clear()

func clear() -> void:
	owner_id = -1
	count = 0
	elapsed = 0.0
	multimesh.visible_instance_count = 0
	hide()

func follow(id: int, car: CarVisual, dt: float) -> void:
	var a := car.nitro_jets[0].to_global(Vector3.BACK * 0.68)
	var b := car.nitro_jets[1].to_global(Vector3.BACK * 0.68)
	if id != owner_id or dt > 0.12 or left[index].distance_squared_to(a) > 64.0:
		clear()
		owner_id = id
	var outlet_l := a
	var outlet_r := b
	global_position = (a + b) * 0.5
	elapsed += dt
	var width_axis := car.global_basis.x.normalized()
	var drawn := 0
	for age in count:
		var j := posmod(index - age, SAMPLES)
		var distance_m := outlet_l.distance_to(left[j])
		if distance_m > MAX_LENGTH:
			break
		var opacity := 0.46 * (1.0 - (age + minf(1.0, elapsed / INTERVAL)) / SAMPLES)
		opacity *= 1.0 - smoothstep(1.2, MAX_LENGTH, distance_m)
		drawn += 2
		_segment(age * 2, a, left[j], width_axis, opacity)
		_segment(age * 2 + 1, b, right[j], width_axis, opacity)
		a = left[j]
		b = right[j]
	multimesh.visible_instance_count = drawn
	visible = drawn > 0
	if elapsed >= INTERVAL or count == 0:
		index = (index + 1) % SAMPLES
		left[index] = outlet_l
		right[index] = outlet_r
		count = mini(SAMPLES, count + 1)
		elapsed = fmod(elapsed, INTERVAL)

func _segment(i: int, a: Vector3, b: Vector3, across: Vector3, opacity: float) -> void:
	var length_axis := b - a
	var basis := Basis(across * (0.06 + 0.18 * opacity), length_axis, Vector3.UP)
	multimesh.set_instance_transform(i, Transform3D(basis, (a + b) * 0.5 - global_position))
	multimesh.set_instance_color(i, Color(0.08, 0.43, 1.0, opacity))
