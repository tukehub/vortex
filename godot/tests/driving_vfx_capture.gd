extends Node3D
## Render with --fixed-fps 60. Pass -- --slow for quarter-speed playback.
var scene: RaceScene
var car: CarVisual
var clock := 0.0
var frame := 0
var slow := false
var contact := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	contact = "--contact" in OS.get_cmdline_user_args()
	slow = "--slow" in OS.get_cmdline_user_args()
	Sfx.enabled = false
	Quality.adaptive_enabled = false
	Quality.set_preset("high")
	Game.race_opts.city = "vlore"
	Game.race_opts.env = "day"
	Game.race_opts.event = ""
	Game.race_opts.car = "benxi"
	Game.race_opts.reverse = false
	scene = RaceScene.new()
	add_child(scene)
	scene.set_process(false)
	scene.effects.set_process(false)
	scene._ui_layer.hide()
	scene.race.started = true
	scene.race.wet = false
	car = scene.cars[scene.race.cars.find(scene.player)]
	for other in scene.cars:
		other.visible = other == car
	Engine.time_scale = 0.25 if slow else 1.0

func _process(dt: float) -> void:
	clock += dt
	var c := scene.player
	c.v = 22.0
	c.s = 500.0 + clock * c.v
	c.d = scene.track.half_w - 1.1
	c.yaw = 0.12
	c.drift = 0.85
	c.nitro_t = 1.0 if frame >= 6 and not contact else 0.0
	c.scrape = 0.9 if frame >= (32 if contact else 8) else 0.0
	car.apply_state(c, scene.track, dt)
	var target := car.global_position
	var basis := car.global_basis.orthonormalized()
	scene.cam.global_position = target + basis * (Vector3(0.65, 1.8, 6.5) if contact else Vector3(-3.05, 1.65, 5.2))
	scene.cam.look_at(target + basis * Vector3(0, 0.58, 0.8))
	scene.cam.fov = 52
	scene.sky.follow(scene.cam.global_position)
	scene.effects._process(dt)
	frame += 1
	var shots := [36, 40, 44] if contact else [10, 14, 18]
	if frame in shots:
		await RenderingServer.frame_post_draw
		var directory := "user://shots/driving-vfx"
		DirAccess.make_dir_recursive_absolute(directory)
		var label := "contact" if contact else ("slow" if slow else "normal")
		var path := "%s/%s-%02d.png" % [directory, label, frame]
		var error := get_viewport().get_texture().get_image().save_png(path)
		assert(error == OK)
		print("VFX capture ", path, " time=", clock, " emitters=", scene.effects.driving.snapshot())
	if frame == shots.back():
		set_process(false)
		Engine.time_scale = 1.0
		scene.queue_free()
		await get_tree().process_frame
		Sfx.stop_all()
		get_tree().quit()
