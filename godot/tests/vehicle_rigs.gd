extends Node
## Imported asset diagnostics and visual-only overrides through the live loader.

func _ready() -> void:
	Quality.set_preset("low")
	for row in Data.MODELS:
		var spec: Dictionary = row.visual
		if spec.get("legacy", false):
			continue
		var paths: Array = [spec.model_path]
		paths.append_array(spec.lod_models.values())
		for path: String in paths:
			var scene := load(path) as PackedScene
			assert(scene != null, "missing vehicle scene " + path)
			var instance := scene.instantiate() as Node3D
			var issues := VehicleRig.validate(VehicleRig.root(instance), spec)
			assert(issues.is_empty(), "%s: %s" % [path, ", ".join(issues)])
			assert(instance.find_children("*", "CollisionObject3D", true, false).is_empty())
			instance.free()
	var def: Dictionary = Data.car("kercyesi").duplicate(true)
	var profile: Dictionary = def.visual
	var chassis := (load(profile.model_path) as PackedScene).instantiate()
	var rig := VehicleRig.root(chassis)
	assert(VehicleRig.validate(rig, profile).is_empty())
	rig.get_node("Wheel_FL").free()
	rig.get_node("Nitro_R").free()
	profile.material_slots = {"paint": "unbound"}
	var issues := " ".join(VehicleRig.validate(rig, profile))
	assert("Wheel_FL" in issues and "Nitro_R" in issues and "material slot paint" in issues)
	chassis.free()

	profile.material_slots = {}
	profile.lod_models = {"low": VehicleRig.ESTATE.model_path}
	profile.visual_scale = 1.15
	profile.wheel_offsets = {"Wheel_FL": Vector3(-.81, .35, -1.35)}
	var car := CarVisual.new()
	add_child(car)
	car.setup(def, Color.RED, true, {"rim": "gold", "livery": "checker"})
	assert(car.model.scene_file_path == VehicleRig.ESTATE.model_path)
	assert(car.wheels.wheel_fl.position == profile.wheel_offsets.Wheel_FL)
	assert(is_equal_approx(car.visual_wheel_radius, 1.15 * profile.wheel_radius))
	assert(is_equal_approx(car.visual_wheelbase, 1.15 * profile.wheelbase))
	assert(car.livery_material != null and car.mat_paint != null)
	assert(car.nitro_jets[0].get_parent() == car.rig_root.get_node("Nitro_L"))
	assert(car.nitro_jets[1].get_parent() == car.rig_root.get_node("Nitro_R"))
	assert(car.head_l.position.x < 0 and car.head_r.position.x > 0)
	var state := ArenaCar.new(0, def, "test", true, Color.RED)
	var reference := ArenaCar.new(0, Data.CARS[0], "reference", true, Color.WHITE)
	assert(state.circles() == reference.circles())
	state.v = 18.
	state.steer = .5
	state.nitro_t = 1.
	car.apply_world(state, .05)
	assert(car.nitro_jets[0].visible and absf(car.steer_vis) > 0.)
	car.free()

	# Rig calipers (the Gepard): on their wheel's axle, steering with the
	# front wheels and never spinning.
	var gepard := CarVisual.new()
	add_child(gepard)
	gepard.setup(Data.car("benxi", "gepard"), Color.RED, true)
	assert(gepard.model.scene_file_path == VehicleRig.CHEETAH.model_path, "the Gepard draws its own chassis")
	assert(gepard.rig_calipers.size() == 4, "the Gepard has four rig calipers")
	for key: String in gepard.rig_calipers:
		var caliper: Node3D = gepard.rig_calipers[key]
		assert(caliper.position.is_equal_approx(gepard.wheels[key].position) and not gepard.wheels[key].is_ancestor_of(caliper))
	var drive := ArenaCar.new(0, Data.car("benxi", "gepard"), "test", true, Color.RED)
	drive.v = 15.0
	drive.steer = 0.8
	for i in 5:
		gepard.apply_world(drive, 0.05)
	var front: Node3D = gepard.rig_calipers.wheel_fr
	var rear: Node3D = gepard.rig_calipers.wheel_rr
	assert(absf(gepard.spin) > 0.1 and absf(gepard.steer_vis) > 0.01)
	assert(is_equal_approx(front.basis.get_euler().y, gepard.steer_vis) and is_zero_approx(front.basis.get_euler().x), "front calipers steer, never spin")
	assert(rear.basis.is_equal_approx(Basis.IDENTITY), "rear calipers stay put")
	assert(gepard.finish_driver.position.y < -0.2, "the driver sits low in the Gepard's cabin")
	gepard.free()
	print("VEHICLE RIGS: diagnostics, replacement GLB, dimensions, sockets, cosmetics, calipers and footprint passed")
	get_tree().quit()
