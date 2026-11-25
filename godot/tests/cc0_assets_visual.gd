extends Node
## Optional rendered check of the CC0 surfaces (tools/fetch_cc0_assets.py):
## Vlorë's beach sand, limestone sea armour and tunnel portal, Lungomare
## paving and palm bark; Shkodër's Rozafa masonry; Tirana's street benches and
## signal poles; and the overcast rain-night sky. Needs a real or software
## Vulkan device. Captures go to user://shots/cc0_<city>_<view>.png.
##   godot --path godot --rendering-method mobile res://tests/cc0_assets_visual.tscn -- --city=vlore [--env=rain]

var scene: RaceScene
var camera: Camera3D
var views: Array = []
var frame := 0
var city := "vlore"
var env := "day"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--city="):
			city = arg.trim_prefix("--city=")
		elif arg.begins_with("--env="):
			env = arg.trim_prefix("--env=")
	Quality.set_preset("medium")
	Game.race_opts.city = city
	Game.race_opts.env = env
	scene = load("res://scenes/race.tscn").instantiate()
	add_child(scene)
	match city:
		"vlore":
			if scene.sea_rocks != null and not scene.sea_rocks.placed.is_empty():
				var rock: Vector3 = scene.sea_rocks.placed[scene.sea_rocks.placed.size() / 2].origin
				_frame_point("rocks", rock, 7.0, 2.0)
			_frame_node("tunnel", scene.road.find_child("Cliff", true, false), 0.6)
			var palms := scene.props.get_node_or_null("Palms")
			if palms != null:
				var trunks := palms.get_node("PalmTrunks") as MultiMeshInstance3D
				var t := trunks.multimesh.get_instance_transform(trunks.multimesh.instance_count / 2)
				var p := trunks.to_global(t.origin)
				_frame_point("palm", p + Vector3(0, 2.5, 0), 5.0, 0.5)
				_frame_point("paving", p, 6.0, 1.6, Vector3(0, -1.2, 0))
			var sand := _beach_point()
			if sand != Vector3.INF:
				_frame_point("sand", sand, 9.0, 2.2, Vector3(0, -1.5, 0))
		"shkoder":
			_frame_node("rozafa", scene.find_child("CastleMasonry", true, false), 0.35)
		"tirane":
			var street: StreetProps = scene.props.street
			for kind in ["bench", "traffic_light"]:
				if street != null and not (street.placed.get(kind, []) as Array).is_empty():
					var at: Transform3D = street.placed[kind][0]
					_frame_point(kind, at.origin + Vector3(0, 0.6 if kind == "bench" else 3.0, 0), 3.2 if kind == "bench" else 9.0, 0.8)
	var road := Vector3(scene.track.X[0], scene.track.Y[0], scene.track.Z[0])
	var ahead := Vector3(scene.track.X[60], scene.track.Y[60], scene.track.Z[60])
	views.append({"name": "sky", "eye": road + Vector3(0, 2.5, 0), "at": ahead + Vector3(0, 45, 0)})
	print("CC0 VISUAL: %s/%s %d views" % [city, env, views.size()])
	camera = Camera3D.new()
	camera.far = 6000.0
	scene.add_child(camera)
	camera.make_current()


func _frame_point(view_name: String, at: Vector3, dist: float, height: float, look_offset := Vector3.ZERO) -> void:
	var from_road := Vector3(scene.track.X[scene.track.nearest(at.x, at.z, 400.0)], at.y, scene.track.Z[scene.track.nearest(at.x, at.z, 400.0)])
	var dir := (from_road - at)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.BACK
	views.append({"name": view_name, "eye": at + dir * dist + Vector3(0, height, 0), "at": at + look_offset})


func _frame_node(view_name: String, node: Node, fill: float) -> void:
	if node == null or not node is MeshInstance3D:
		print("CC0 VISUAL: no node for ", view_name)
		return
	var mi := node as MeshInstance3D
	var box := mi.global_transform * mi.get_aabb()
	var c := box.get_center()
	var road := Vector3(scene.track.X[scene.track.nearest(c.x, c.z, 2000.0)], c.y, scene.track.Z[scene.track.nearest(c.x, c.z, 2000.0)])
	var dir := (road - c)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.BACK
	var r := box.size.length() * 0.5 * fill
	views.append({"name": view_name, "eye": c + dir * r + Vector3(0, r * 0.25, 0), "at": c})


## A dry beach point a few metres from the water, near the middle of the shore.
func _beach_point() -> Vector3:
	for i in range(scene.track.M / 2, scene.track.M, 7):
		var p := Vector3(scene.track.X[i], scene.track.Y[i], scene.track.Z[i])
		for a in 16:
			var dir := Vector3(cos(a * TAU / 16.0), 0.0, sin(a * TAU / 16.0))
			for r in range(20, 160, 4):
				var q := p + dir * r
				if scene.terrain.is_water(q.x, q.z):
					var land := p + dir * (r - 10)
					return Vector3(land.x, scene.terrain.height_at(land.x, land.z), land.z)
	return Vector3.INF


func _process(_dt: float) -> void:
	frame += 1
	scene.set_process(false)
	camera.make_current()
	var view_i := (frame - 20) / 10
	if frame < 20 or view_i >= views.size():
		if view_i >= views.size():
			print("CC0 VISUAL: done; renderer=", RenderingServer.get_current_rendering_method())
			get_tree().quit()
		return
	var v: Dictionary = views[view_i]
	camera.position = v.eye
	camera.look_at(v.at)
	if (frame - 20) % 10 == 9:
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("user://shots")
		get_viewport().get_texture().get_image().save_png("user://shots/cc0_%s_%s_%s.png" % [city, env, v.name])
