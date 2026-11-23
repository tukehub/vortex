extends Node3D
## Fixed production-world viewpoints and a short moving-camera sample.

const WARMUP_FRAMES := 24
var world: RaceScene
var camera: Camera3D
var city_track: RaceTrack
var mode := "day"
var quality := "high"
var tag := "showcase"
var sample_frames := 90
var frame := 0
var start_usec := 0
var last_usec := 0
var frame_times: Array[float] = []
var draw_total := 0.0
var triangle_total := 0.0


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("env="):
			mode = argument.substr(4)
		elif argument.begins_with("quality="):
			quality = argument.substr(8)
		elif argument.begins_with("tag="):
			tag = argument.substr(4)
		elif argument.begins_with("samples="):
			sample_frames = maxi(1, int(argument.substr(8)))
	Quality.set_preset(quality)
	Quality.apply_viewport(get_viewport())
	Game.race_opts.reverse = false
	Game.race_opts.event = ""
	world = ShowcaseWorld.new()
	world.city_id = "tirane"
	world.env_id = mode
	add_child(world)
	city_track = world.track
	camera = Camera3D.new()
	camera.fov = 65.0
	camera.far = 4500.0
	add_child(camera)
	camera.make_current()
	place_camera(300.0)


func place_camera(at: float) -> void:
	var origin := city_track.pos(at, -3.0)
	var target := city_track.pos(at + 33.0, 0.0)
	camera.global_position = origin + Vector3.UP * 3.7
	camera.look_at(target + Vector3.UP * 2.0)
	world.sky.follow(camera.global_position)
	world.sky.set_rain_ground(city_track.pos(at, 0.0), city_track.tangent(at))
	var forward := city_track.tangent(at)
	world.props.update_lights(camera.global_position, forward)
	world.props.update_vegetation(camera.global_position, forward)


func _process(_delta: float) -> void:
	frame += 1
	if frame < WARMUP_FRAMES:
		return
	if frame == WARMUP_FRAMES:
		var image := get_viewport().get_texture().get_image()
		var path := "user://shots/%s-%s-%s.png" % [tag, quality, mode]
		DirAccess.make_dir_recursive_absolute("user://shots")
		assert(image.save_png(path) == OK)
		print("SHOT ", ProjectSettings.globalize_path(path))
		var lit := world.props.lights.filter(func(light: OmniLight3D): return light.visible and light.light_energy > 0.0)
		print("ACTIVE_LAMPS ", lit.size())
		start_usec = Time.get_ticks_usec()
		last_usec = start_usec
		return
	var now := Time.get_ticks_usec()
	frame_times.append((now - last_usec) / 1000.0)
	last_usec = now
	draw_total += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	triangle_total += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	if frame_times.size() == sample_frames:
		frame_times.sort()
		print("SHOWCASE ", JSON.stringify({
			"renderer": RenderingServer.get_current_rendering_method(), "quality": quality,
			"environment": mode, "fps": sample_frames * 1000000.0 / (now - start_usec),
			"p95_ms": frame_times[ceili(0.95 * sample_frames) - 1],
			"draws": draw_total / sample_frames, "primitives": triangle_total / sample_frames,
			"viewport": str(get_viewport().get_visible_rect().size),
		}))
		get_tree().quit()
	else:
		place_camera(20.0 + 380.0 * frame_times.size() / sample_frames)


class ShowcaseWorld extends RaceScene:
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
		_build_world()
