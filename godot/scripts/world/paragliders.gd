class_name Paragliders
extends Node3D
## Paragliders circling high over Lungomare and the shore road (landmark
## "lungomare_paragliders"; local +X runs down the coast, +Z out over the
## bay). Each is a ram-air wing of coloured cells, its lines and a pilot in a
## harness, one mesh, drifting round a slow thermal and banking into it.
## Purely visual; animated from the frame clock.

const WING_SPAN := 10.5
const CHORD := 2.7
const LINES := 7.2
const CELLS := 14
const SCHEMES := [
	[Color("#d62d2d"), Color("#f2f0ea")],
	[Color("#f2c418"), Color("#2853a6")],
	[Color("#f07a1d"), Color("#262626")],
	[Color("#2b9e5b"), Color("#f2f0ea")],
	[Color("#7a3fb0"), Color("#f2c418")],
	[Color("#1f8fd1"), Color("#f2f0ea")],
]
## Per glider: [x along the coast, z seaward, height m, thermal radius m,
## speed m/s, phase].
const FLIGHTS := [
	[-640.0, -40.0, 135.0, 70.0, 9.5, 0.0],
	[-360.0, 70.0, 95.0, 55.0, 9.0, 1.7],
	[-80.0, -70.0, 150.0, 80.0, 10.0, 3.1],
	[200.0, 40.0, 110.0, 60.0, 9.2, 4.4],
	[470.0, -30.0, 165.0, 85.0, 10.4, 2.2],
	[730.0, 80.0, 85.0, 50.0, 8.8, 5.3],
]

var gliders: Array[MeshInstance3D] = []
var _t := 0.0


func build() -> void:
	for i in FLIGHTS.size():
		var glider := MeshInstance3D.new()
		glider.name = "Paraglider%d" % i
		glider.mesh = _glider_mesh(SCHEMES[i % SCHEMES.size()])
		glider.material_override = LandmarkKit.material(0.7, 0.0, false)
		glider.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glider.visibility_range_end = 3200.0
		add_child(glider)
		gliders.append(glider)
	_place(0.0)


func _process(dt: float) -> void:
	_t += dt
	_place(_t)


func _place(t: float) -> void:
	for i in gliders.size():
		var f: Array = FLIGHTS[i]
		var radius := float(f[3])
		var speed := float(f[4])
		var a := float(f[5]) + t * speed / radius
		var drift := Vector3(12.0 * sin(t * 0.021 + i), 0.0, 9.0 * cos(t * 0.017 + i * 2.0))
		var centre := Vector3(float(f[0]), float(f[2]) + 6.0 * sin(t * 0.05 + i), float(f[1])) + drift
		var at := centre + Vector3(cos(a) * radius, 0.0, sin(a) * radius)
		var heading := Vector3(-sin(a), 0.0, cos(a))
		# Coordinated turn: bank = atan(v^2 / (g r)), into the circle.
		var bank := atan(speed * speed / (9.81 * radius))
		var basis := Basis.looking_at(heading, Vector3.UP)
		basis = basis.rotated(heading, bank)
		gliders[i].transform = Transform3D(basis, at)


## Wing above the pilot: an arc of cells with anhedral, top and bottom skins,
## nose open; lines from the wing's underside to the pilot; pilot seated in
## the harness under it. Local -Z is the direction of flight.
static func _glider_mesh(colors: Array) -> ArrayMesh:
	var st := LandmarkKit.begin()
	var arc := 1.05   # radians of the span's arc
	var radius := WING_SPAN / arc
	var top: Array[Vector3] = []
	for k in CELLS + 1:
		var ang := -arc * 0.5 + arc * k / CELLS
		top.append(Vector3(sin(ang) * radius, cos(ang) * radius - radius + LINES, 0.0))
	for k in CELLS:
		var col: Color = colors[0] if (k / 2) % 2 == 0 else colors[1]
		var a := top[k]
		var b := top[k + 1]
		var taper_a := 1.0 - 0.35 * absf(float(k) / CELLS * 2.0 - 1.0)
		var taper_b := 1.0 - 0.35 * absf(float(k + 1) / CELLS * 2.0 - 1.0)
		var lead_a := a + Vector3(0, 0, -CHORD * 0.45 * taper_a)
		var lead_b := b + Vector3(0, 0, -CHORD * 0.45 * taper_b)
		var trail_a := a + Vector3(0, -0.12, CHORD * 0.55 * taper_a)
		var trail_b := b + Vector3(0, -0.12, CHORD * 0.55 * taper_b)
		var under := Vector3(0, -0.32, 0)
		LandmarkKit.quad_facing(st, lead_a, lead_b, trail_b, trail_a, col, a.normalized() + Vector3.UP)
		LandmarkKit.quad_facing(st, lead_a + under, lead_b + under, trail_b, trail_a, col.darkened(0.25), -(a.normalized() + Vector3.UP))
		LandmarkKit.quad_facing(st, lead_a, lead_b, lead_b + under, lead_a + under, col.darkened(0.45), Vector3.FORWARD)
	# Lines: risers from the carabiners fanning to the wing.
	var harness := Vector3(0, 0.25, 0)
	var line_col := Color(0.25, 0.25, 0.25)
	for k in range(0, CELLS + 1, 2):
		for z: float in [-CHORD * 0.25, CHORD * 0.25]:
			var tip := top[k] + Vector3(0, -0.3, z)
			var dir := (tip - harness).normalized()
			var side := dir.cross(Vector3.FORWARD).normalized() * 0.03
			LandmarkKit.quad(st, harness - side, harness + side, tip + side, tip - side, line_col)
	# Pilot: harness pod, torso, helmet.
	LandmarkKit.box(st, Vector3(0, -0.35, 0.15), Vector3(0.55, 0.45, 1.2), Color("#2c3036"))
	LandmarkKit.box(st, Vector3(0, 0.15, 0.25), Vector3(0.5, 0.75, 0.38), colors[0].darkened(0.3))
	LandmarkKit.sphere(st, Vector3(0, 0.68, 0.22), Vector3(0.17, 0.19, 0.19), Color("#e8e4dc"), 4, 6)
	return st.commit()
