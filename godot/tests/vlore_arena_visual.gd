extends Node
## Optional rendered check of the Vlorë points arena (needs a real or software
## Vulkan device): the bowl, the wall and the backdrop from the chase camera
## and from above. Captures go to user://shots/arena_*.png. Pass -- --city=tirane
## for Skanderbeg Square.
##   godot --path godot --rendering-method mobile res://tests/vlore_arena_visual.tscn

var scene: ArenaScene
var views: Array = []
var frame := 0


func _ready() -> void:
	Quality.set_preset("medium")
	Game.race_opts.city = "vlore"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--city="):
			Game.race_opts.city = arg.substr(7)
	Game.race_opts.mode = "points"
	scene = load("res://scenes/arena.tscn").instantiate()
	add_child(scene)
	scene.set_process(false)
	var bound := Vector2(Arena.HALF_X, Arena.HALF_Z)
	views = [
		{"name": "over", "eye": Vector3(0, 260, bound.y * 1.9), "at": Vector3.ZERO},
		{"name": "east_wall", "eye": Vector3(bound.x * 0.55, 3.5, 0), "at": Vector3(bound.x + 40, 4, 0)},
		{"name": "north_wall", "eye": Vector3(0, 3.5, bound.y * 0.4), "at": Vector3(0, 4, bound.y + 60)},
		{"name": "south_wall", "eye": Vector3(30, 3.5, -bound.y * 0.4), "at": Vector3(30, 4, -bound.y - 60)},
		{"name": "west_corner", "eye": Vector3(-bound.x * 0.5, 3.5, -bound.y * 0.4), "at": Vector3(-bound.x - 40, 4, -bound.y - 40)},
		{"name": "bank", "eye": Vector3(bound.x - 34.0, 2.2, -16.0), "at": Vector3(bound.x - 6.0, 1.0, 14.0)},
		{"name": "chase", "eye": Vector3(), "at": Vector3()},
	]


func _process(_dt: float) -> void:
	frame += 1
	var index := frame / 12
	if index >= views.size():
		get_tree().quit()
		return
	var view: Dictionary = views[index]
	if view.name == "bank" and frame % 12 == 0:
		# The player parked across the bank, by the east wall.
		scene.player.x = Arena.HALF_X - 7.0
		scene.player.z = 10.0
		scene.player.h = PI
		scene.cars[0].apply_world(scene.player, 0.016)
	if view.name != "chase":
		scene.cam.global_position = view.eye
		scene.cam.look_at(view.at, Vector3.UP)
	else:
		scene._follow_camera(0.016)
	if frame % 12 == 11:
		DirAccess.make_dir_recursive_absolute("user://shots")
		var path := "user://shots/arena_%s_%s.png" % [str(Game.race_opts.city), view.name]
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT ", ProjectSettings.globalize_path(path))
