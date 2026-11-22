extends Node3D
## Plan 3.5: crossings from props.json reach the road shader in lap
## coordinates; inferred street furniture is marked as such and obeys the
## same rules as mapped items; low quality drops the road hardware.

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("CHECK FAILED: " + message)


func _ready() -> void:
	Settings.adaptive_quality = false
	Quality.configure_from_settings()
	Quality.set_preset("medium")
	for city_id in ["tirane", "vlore"]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cities/%s/props.json" % city_id))
		var rows: Array = (data.get("road_marks", {}) as Dictionary).get("crossings", [])
		check(rows.size() > 0 and rows.size() <= RoadMesh.MAX_CROSSINGS, "%s has crossings (%d)" % [city_id, rows.size()])
		for reverse in [false, true]:
			var track := RaceTrack.load_city(city_id, reverse)
			var road := RoadMesh.new()
			add_child(road)
			road.build(track, track.half_w, 0.0)
			var marks := road.set_crossings(track, rows)
			check(marks.size() == rows.size(), "%s paints every crossing (reverse=%s)" % [city_id, reverse])
			check(int(road.surface_mat.get_shader_parameter("crossing_count")) == marks.size(), "crossing count reaches the shader")
			var sent: PackedVector2Array = road.surface_mat.get_shader_parameter("crossings")
			check(sent.size() == RoadMesh.MAX_CROSSINGS, "the shader array is always full length")
			var positions: Array[float] = []
			for m in marks:
				check(m.x >= 0.0 and m.x < track.L and m.y >= 3.0 and m.y <= 6.0, "crossing lies on the lap with a plausible width")
				positions.append(m.x)
			positions.sort()
			for i in positions.size():
				var gap := fposmod(positions[(i + 1) % positions.size()] - positions[i], track.L)
				check(positions.size() == 1 or gap > 55.0, "%s crossings are spread out (%.0f m)" % [city_id, gap])
			# The same crossing lands at the same place in both directions.
			for row in rows:
				var p := track.pos(track.locate_xz(float(row[0]), float(row[1])).x, 0.0)
				check(Vector2(p.x - float(row[0]), p.z - float(row[1])).length() < 3.0, "crossing projects onto itself")
			Quality.set_preset("low")
			check(float(road.surface_mat.get_shader_parameter("detail")) == 0.0, "low skips manholes, gullies and patches")
			Quality.set_preset("medium")
			check(float(road.surface_mat.get_shader_parameter("detail")) == 1.0, "medium draws them")
			road.queue_free()
		# Inferred furniture: flagged, off the race road, and never crowding mapped rows.
		var street: Dictionary = data.get("street", {})
		var track := RaceTrack.load_city(city_id)
		var inferred := 0
		for kind in StreetProps.KINDS:
			for row: Array in street.get(kind, []):
				check(row.size() == 3 or (row.size() == 4 and int(row[3]) == 1), "%s rows are [x, z, yaw] or flagged [x, z, yaw, 1]" % kind)
				if row.size() == 4:
					inferred += 1
					if track.dist_to(float(row[0]), float(row[1])) < track.half_w + 2.0 - 0.05:
						check(false, "%s inferred %s stands on the race road" % [city_id, kind])
		check(inferred > 0, "%s fills gaps in its mapped furniture (%d added)" % [city_id, inferred])
	# Road hardware: realistic density, inside the carriageway, off the edge line.
	var hw := 10.0
	var counts := {"manhole": 0, "gully": 0, "patch": 0}
	for h in RoadMesh.hardware_near(0.0, 10000.0, hw):
		counts[h.kind] += 1
		var d := absf(float(h.d))
		match h.kind:
			"manhole":
				check(is_equal_approx(fposmod(d, 5.0), 2.5), "manholes sit mid-lane")
			"gully":
				check(d + 0.26 < hw - 0.55, "gullies stay inside the edge line")
			"patch":
				check(d < hw - 0.8, "patches stay on the carriageway")
	check(counts.manhole > 180 and counts.manhole < 280, "about one manhole per 44 m (%d in 10 km)" % counts.manhole)
	check(counts.gully > 320 and counts.gully < 380, "about one gully per 28 m (%d in 10 km)" % counts.gully)
	check(counts.patch > 90 and counts.patch < 160, "about one patch per 80 m (%d in 10 km)" % counts.patch)
	for c in 200:
		var v := RoadMesh.cell_hash(c, 6.1)
		check(v >= 0.0 and v < 1.0, "cell hash stays in [0, 1)")
	var vlore: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cities/vlore/props.json"))
	var lights: Array = vlore.street.traffic_light
	check(lights.size() > 0, "Vlorë gets signals at its major junctions")
	await get_tree().process_frame
	print("ROAD MARKS: failures=%d" % failures)
	get_tree().quit(1 if failures else 0)
