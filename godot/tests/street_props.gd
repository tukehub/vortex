extends Node3D
## Plan 3.4: OSM street furniture. Every mapped item is drawn once, off the
## race road, on the ground; meshes stay low-poly; chunks cull by range; low
## quality and pressure keep only lights and stops.

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("CHECK FAILED: " + message)


func _ready() -> void:
	Settings.adaptive_quality = false
	Quality.configure_from_settings()
	Quality.set_preset("medium")
	var builder := StreetProps.new()
	add_child(builder)
	for kind in StreetProps.KINDS:
		var mesh := builder.make_mesh(kind)
		var tris := StreetProps.triangles(mesh)
		check(tris > 0 and tris < StreetProps.MAX_TRIANGLES, "%s mesh is low-poly (%d triangles)" % [kind, tris])
		var box := mesh.get_aabb()
		check(box.position.y >= -0.01 and box.size.y < 6.5, "%s stands on its origin" % kind)
	builder.queue_free()

	for city_id in ["tirane", "vlore"]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cities/%s/props.json" % city_id))
		var street: Dictionary = data.get("street", {})
		var total := 0
		for kind in StreetProps.KINDS:
			total += (street.get(kind, []) as Array).size()
		check(total > 0, "%s has mapped street furniture (%d)" % [city_id, total])
		# What OSM maps near each circuit (nothing is invented): Tirana has
		# every kind; Vlorë maps bus stops and a few benches, no signals.
		var expected: Array = StreetProps.KINDS if city_id == "tirane" else ["bus_stop"]
		for kind in expected:
			check((street.get(kind, []) as Array).size() > 0, "%s has mapped %s" % [city_id, kind])
		var track := RaceTrack.load_city(city_id)
		var tj: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cities/%s/track.json" % city_id))
		var clear := float(tj.hw) + 2.0 - 0.05
		for kind in StreetProps.KINDS:
			for row in street.get(kind, []):
				var d := track.dist_to(float(row[0]), float(row[1]))
				if d < clear:
					check(false, "%s %s at %.1f, %.1f stands %.1f m from the centreline" % [city_id, kind, row[0], row[1], d])
					break
		var terrain := Terrain.new()
		add_child(terrain)
		terrain.load_city(city_id, null)
		var props := Props.new()
		add_child(props)
		props.load_city(city_id, terrain)
		var furniture := props.street
		check(furniture != null and furniture.get_parent() == props, "%s props build the street furniture" % city_id)
		if furniture == null:
			continue
		var nodes := []
		for kind in StreetProps.KINDS:
			var rows: Array = street.get(kind, [])
			check(int(furniture.counts.get(kind, 0)) == rows.size(), "%s draws every mapped %s once" % [city_id, kind])
			var drawn := 0
			for node: MultiMeshInstance3D in furniture.chunks[kind]:
				nodes.append(node)
				drawn += node.multimesh.instance_count
				check(node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "street props cast no shadows")
				check(node.visibility_range_end > 0.0 and node.visibility_range_end <= float(Quality.p.props_dist) + StreetProps.CHUNK * 0.71 + 0.01, "%s chunks cull by range" % kind)
			check(drawn == rows.size(), "%s chunks hold every %s" % [city_id, kind])
			var placed: Array = furniture.placed[kind]
			check(placed.size() == rows.size(), "%s places every %s" % [city_id, kind])
			for i in placed.size():
				var at: Vector3 = (placed[i] as Transform3D).origin
				if absf(at.x - float(rows[i][0])) > 0.01 or absf(at.z - float(rows[i][1])) > 0.01 or absf(at.y - terrain.height_at(at.x, at.z)) > 0.01:
					check(false, "%s %s %d stands where mapped, on the ground" % [city_id, kind, i])
					break
		Quality.set_preset("low")
		for kind in StreetProps.KINDS:
			for node: MultiMeshInstance3D in furniture.chunks[kind]:
				check(node.visible == not kind in StreetProps.SMALL, "low keeps only lights and stops (%s)" % kind)
				check(node.visibility_range_end <= float(Quality.p.props_dist) + StreetProps.CHUNK * 0.71 + 0.01, "low shortens every range")
		Quality.set_preset("high")
		Quality.set_pressure_stage(2)
		for node: MultiMeshInstance3D in furniture.chunks.bench:
			check(not node.visible, "pressure drops benches")
		Quality.set_pressure_stage(0)
		var after := []
		for kind in StreetProps.KINDS:
			for node: MultiMeshInstance3D in furniture.chunks[kind]:
				after.append(node)
				check(node.visible, "high shows every kind")
		check(after == nodes, "budget changes reuse the same chunks")
		Quality.set_preset("medium")
		props.queue_free()
		terrain.queue_free()
		await get_tree().process_frame
	print("STREET PROPS: failures=%d" % failures)
	get_tree().quit(1 if failures else 0)
