extends Node
## Rendered Vlorë views for review (needs a real or software Vulkan device).
## Views come from a JSON file: [{"name", "eye": [x, y, z], "at": [x, y, z]}
## or {"name", "s": metres along the lap, "back": m, "up": m, "ahead": m}].
##   godot --path godot --rendering-method mobile res://tests/vlore_views.tscn -- --views=/abs/views.json --out=/abs/dir

var scene: RaceScene
var camera: Camera3D
var views: Array = []
var out_dir := "user://shots"
var frame := 0


func _ready() -> void:
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--views="):
			path = arg.substr(8)
		elif arg.begins_with("--out="):
			out_dir = arg.substr(6)
	Quality.set_preset("medium")
	Game.race_opts.city = "vlore"
	Game.race_opts.env = "day"
	Game.race_opts.reverse = false
	scene = load("res://scenes/race.tscn").instantiate()
	add_child(scene)
	var spec: Array = JSON.parse_string(FileAccess.get_file_as_string(path))
	for v: Dictionary in spec:
		if v.has("s"):
			var s := float(v.s)
			var back := float(v.get("back", 0.0))
			var eye := scene.track.pos(s - back, float(v.get("side", 0.0))) + Vector3.UP * float(v.get("up", 2.4))
			var at := scene.track.pos(s + float(v.get("ahead", 18.0)), 0.0) + Vector3.UP * float(v.get("look_up", 1.0))
			views.append({"name": v.name, "eye": eye, "at": at})
		else:
			views.append({"name": v.name, "eye": Vector3(v.eye[0], v.eye[1], v.eye[2]), "at": Vector3(v.at[0], v.at[1], v.at[2])})
	camera = Camera3D.new()
	camera.far = 6000.0
	camera.fov = 70.0
	scene.add_child(camera)
	for layer in scene.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	DirAccess.make_dir_recursive_absolute(out_dir)


func _process(_dt: float) -> void:
	frame += 1
	scene.set_process(false)
	camera.make_current()
	if frame < 20:
		return
	var view_i := (frame - 20) / 10
	if view_i >= views.size():
		print("VLORE VIEWS: ", views.size())
		get_tree().quit()
		return
	var v: Dictionary = views[view_i]
	camera.position = v.eye
	camera.look_at(v.at)
	if (frame - 20) % 10 == 9:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, v.name])
