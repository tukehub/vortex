extends Node3D
## Matched, fixed daylight architectural views in the production world.

const VIEWS := {
	"flag-square": [Vector3(23, 9.4, -2980), Vector3(26, 10, -3011)],
	"lungomare": [Vector3(-244, 5.8, -1207), Vector3(-184, 20, -1265)],
}
var camera := Camera3D.new()
var world := CaptureWorld.new()
var frame := 0


func _ready() -> void:
	Quality.set_preset("medium")
	Quality.apply_viewport(get_viewport())
	world.city_id = "vlore"
	world.env_id = "day"
	add_child(world)
	add_child(camera)
	camera.fov = 65
	camera.far = 4500
	camera.make_current()


func _process(_delta: float) -> void:
	var name_tag: String = VIEWS.keys()[frame / 12]
	var view: Array = VIEWS[name_tag]
	camera.position = view[0]
	camera.look_at(view[1])
	world.sky.follow(camera.position)
	world.props.update_vegetation(camera.position, -camera.basis.z)
	frame += 1
	if frame % 12 == 0:
		if frame == 12 * VIEWS.size():
			set_process(false)
		await RenderingServer.frame_post_draw
		var path := "user://shots/" + name_tag + ".png"
		DirAccess.make_dir_recursive_absolute("user://shots")
		if get_viewport().get_texture().get_image().save_png(path) != OK:
			get_tree().quit(1)
			return
		if frame == 12 * VIEWS.size():
			get_tree().quit()


class CaptureWorld extends RaceScene:
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
		_build_world()
