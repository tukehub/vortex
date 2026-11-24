extends Node3D
## Vlorë's two carriageways are one road: no kerb, barrier or shoulder
## between them, a level surface across, room to drive on the other side,
## contact with cars coming the other way, and along Lungomare a rounded
## 10 cm median the cars ride over.

var failures := 0


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("CHECK FAILED: " + message)


func _ready() -> void:
	Quality.set_preset("medium")
	var track := RaceTrack.load_city("vlore", false)
	var hw := track.half_w
	var joined_m := 0.0
	var median_m := 0.0
	var worst_level := 0.0
	var interior := -1
	var plain := -1
	for i in track.M:
		if track.PAIR[i] < 0:
			check(is_equal_approx(track.EDGE_L[i], hw) and is_equal_approx(track.EDGE_R[i], hw), "a single carriageway keeps its own edges")
			continue
		joined_m += track.ds
		check(track.JOIN[i] < 0.0 and absf(track.JOIN[i]) > 5.5 and absf(track.JOIN[i]) < 6.6, "the other carriageway joins on the driver's left, 6 m to the middle")
		if track.MEDIAN[i] > 0.0:
			median_m += track.ds
		var open := track.EDGE_L[i] >= hw + 2.0 * absf(track.JOIN[i]) - 0.01
		if open:
			worst_level = maxf(worst_level, absf(track.Y[i] - track.Y[track.PAIR[i]]))
			if interior < 0 and track.MEDIAN[i] >= 1.0:
				interior = i
			if plain < 0 and track.MEDIAN[i] <= 0.0 and i * track.ds > 300.0:
				plain = i
	check(joined_m > 5500.0, "most of the lap is one road both ways (%.0f m)" % joined_m)
	check(worst_level < 0.05, "the two halves are level across (%.3f m)" % worst_level)
	check(absf(median_m - 2.0 * 912.0) < 80.0, "Lungomare's median on both passes (%.0f m)" % median_m)
	check(interior >= 0 and plain >= 0, "a median stretch and a plain stretch to test")

	# The median: 10 cm at its crown, rounded down to the road 1 m either side.
	var s := interior * track.ds
	var middle := track.join_offset(s)
	check(absf(track.median_lift(s, middle) - 0.10) < 0.002, "the crown is 10 cm up")
	check(track.median_lift(s, middle + 0.7) > 0.02 and track.median_lift(s, middle + 0.7) < 0.09, "its shoulders are curved")
	check(track.median_lift(s, middle + 1.05) == 0.0 and track.median_lift(s, 0.0) == 0.0, "and the lanes are flat")
	check(track.median_lift(plain * track.ds, track.join_offset(plain * track.ds)) == 0.0, "no median off Lungomare")

	# Walls: the far edge of the other carriageway where joined, own edge otherwise.
	var race := Race.new(track, {"seed": 7})
	race.started = true
	var c := race.player
	var sp := plain * track.ds
	_place(c, sp, -10.0, 25.0)
	for k in 30:
		race.physics(c, 1.0 / 60.0)
	check(c.d < -9.0, "a car can drive on the other half of the road (d %.1f)" % c.d)
	_place(c, sp, -30.0, 25.0)
	race.physics(c, 1.0 / 60.0)
	check(absf(c.d + (track.edge_left(c.s) - 1.1)) < 0.05, "the far edge is still a wall (d %.1f)" % c.d)
	_place(c, sp, 10.0, 25.0)
	race.physics(c, 1.0 / 60.0)
	check(c.d <= hw - 1.1 + 0.001, "the outer edge is where it was")
	var single := 0
	while track.PAIR[single] >= 0:
		single += 1
	_place(c, single * track.ds + 1.0, -10.0, 25.0)
	race.physics(c, 1.0 / 60.0)
	check(c.d >= -(hw - 1.1) - 0.001, "where the passes split, the island side is a wall again")

	# Riding over the median scrubs a little speed; the flat road does not.
	_place(c, s, middle + 0.75, 30.0)
	c.yaw = 0.0
	race.physics(c, 1.0 / 60.0)
	var on_median := c.v
	_place(c, s, middle + 2.5, 30.0)
	race.physics(c, 1.0 / 60.0)
	check(on_median < c.v - 0.01 and on_median > c.v - 0.2, "the median is felt, not a wall (%.3f vs %.3f)" % [on_median, c.v])

	# A car on the far side meets one coming the other way.
	var other := race.cars[0] if race.cars[0] != c else race.cars[1]
	var j := track.PAIR[plain]
	# Noses 0.4 m into each other, as on the first frame of a head-on.
	var world := track.pos(sp + 4.0, -12.0)
	var there := track.locate_xz(world.x, world.z)
	_place(c, sp, -12.0, 30.0)
	_place(other, there.x, there.y, 30.0)
	check(absf(track.wrap_s(other.s - j * track.ds)) < 6.0, "the oncoming car is on the other pass")
	race.collisions(1.0 / 60.0)
	check(c.v < 10.0 and other.v < 10.0, "head-on contact across the passes stops both (%.1f, %.1f)" % [c.v, other.v])
	check(c.health < c.max_hp and other.health < other.max_hp, "and damages both")

	# The road: no barrier, kerb or shoulder on the joined side, a median mesh.
	Game.race_opts.city = "vlore"
	Game.race_opts.env = "day"
	Game.race_opts.laps = 1
	Game.race_opts.reverse = false
	var scene := RaceScene.new()
	add_child(scene)
	scene.set_process(false)
	var road := scene.road
	var barriers: PackedVector3Array = (road.get_node("RoadsideBarriers") as MeshInstance3D).mesh.get_faces()
	var in_middle := 0
	for v in barriers:
		if Props.in_joined_road(track, v.x, v.z):
			in_middle += 1
	check(in_middle == 0, "no barrier stands in the joined road (%d vertices)" % in_middle)
	var median_node := road.get_node_or_null("LungomarePavedMedian") as MeshInstance3D
	check(median_node != null, "Lungomare has its median")
	if median_node != null:
		var top := -INF
		for v in median_node.mesh.get_faces():
			var at := track.locate_xz(v.x, v.z)
			top = maxf(top, v.y - track.height(at.x))
		check(top > 0.09 and top < 0.12, "the median stands 10 cm proud (%.3f m)" % top)
	for lamp: Array in scene.props.track_lamps:
		check(not Props.in_joined_road(track, float(lamp[0]), float(lamp[2])), "no lamp post stands in the road")
	var signs := road.get_node("RouteSigns")
	var boards: PackedVector3Array = signs.band.mesh.get_faces()
	var boards_in_road := 0
	for v in boards:
		if Props.in_joined_road(track, v.x, v.z):
			boards_in_road += 1
	check(boards_in_road == 0, "corner boards stand off the joined road (%d)" % boards_in_road)
	# A car with its left wheels on the crown rolls and rises.
	var visual: CarVisual = scene.cars[0]
	var car := scene.race.cars[0]
	_place(car, s, middle + 0.8, 20.0)
	for k in 30:
		visual.apply_state(car, track, 1.0 / 60.0)
	check(visual.median_heave > 0.03 and visual.median_roll < -0.03, "the car rides up the median (%.3f m, %.3f rad)" % [visual.median_heave, visual.median_roll])
	scene.queue_free()
	await get_tree().process_frame

	# Reverse laps join on the right instead.
	var back := RaceTrack.load_city("vlore", true)
	var right := 0
	for i in back.M:
		if back.PAIR[i] >= 0:
			check(back.JOIN[i] > 0.0, "reverse: the other carriageway is on the right")
			right += 1
	check(right * back.ds > 5500.0, "reverse keeps the one road")
	# Other cities are untouched.
	var tirana := RaceTrack.load_city("tirane", false)
	var joined_tirana := 0
	for i in tirana.M:
		if tirana.PAIR[i] >= 0:
			joined_tirana += 1
	check(joined_tirana == 0, "two-way cities have no joined passes")
	print("VLORE ONE ROAD: %.0f m joined, %.0f m of median, level within %.3f m, failures %d" % [joined_m, median_m, worst_level, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _place(car: CarState, s: float, d: float, v: float) -> void:
	car.s = s
	car.progress = s
	car.d = d
	car.v = v
	car.yaw = 0.0
	car.lat_v = 0.0
	car.wreck_t = 0.0
