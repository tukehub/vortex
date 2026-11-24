extends Node
## Load each real city through the production race scene, including terrain and GLBs.

func _ready() -> void:
	Quality.set_preset("low")
	Game.race_opts.reverse = false
	var count := 0
	for city in Data.CITIES:
		if not FileAccess.file_exists("res://assets/cities/%s/track.json" % city.id):
			continue
		Game.race_opts.city = city.id
		var scene: RaceScene = load("res://scenes/race.tscn").instantiate()
		add_child(scene)
		scene.set_process(false)
		assert(scene.cars.size() == 6 and scene.track.L > 1000)
		assert(scene.terrain != null and scene.buildings != null and scene.road != null)
		assert(scene.road.get_node_or_null("RoadsideBarriers") != null, "road edges should be visible")
		var pines := scene.get_node_or_null("PineForest") as Node3D
		assert(pines != null and pines.get_script() != null, "race scene should contain the scripted pine forest")
		var planted: Array = pines.get("planted_transforms")
		if city.id == "tirane":
			assert(planted.size() > 0 and planted.size() <= 16, "low quality should plant a bounded number of mapped pines")
			print("PINE FOREST: ", planted.size(), " mapped trees, low quality")
			for transform: Transform3D in planted:
				var p := transform.origin
				assert(scene.track.dist_to(p.x, p.z) >= scene.track.half_w + 14.5, "pines must remain outside the road and barriers")
				assert(absf(p.y - scene.terrain.height_at(p.x, p.z)) < 0.1, "pines must stand on terrain")
			var landmark_root: Node = null
			for child in scene.props.get_children():
				if child is Landmarks:
					landmark_root = child
					break
			assert(landmark_root != null)
			assert(landmark_root.get_node_or_null("skanderbeg/SkanderbegBronze") != null, "the square needs its detailed equestrian monument")
			var stadium := landmark_root.get_node_or_null("air_albania/AirAlbaniaStadium/AirAlbaniaArchitecture") as MeshInstance3D
			assert(stadium != null and stadium.mesh != null, "the Air Albania stadium must load in Tirana")
			assert(stadium.mesh.get_aabb().size.y >= 111.0, "the stadium's corner tower should be visible at realistic height")
			var plaza := landmark_root.get_node_or_null("plaza_tower/PlazaTower/PlazaTowerArchitecture") as MeshInstance3D
			assert(plaza != null and plaza.mesh != null, "Plaza hotel must load in Tirana")
			assert(plaza.mesh.get_aabb().size.y >= 84.0, "Plaza tower should have its approximately 85m height")
			assert(landmark_root.get_node_or_null("namazgja/ReligiousLandmark") != null, "Namazgja mosque must load in Tirana")
			assert(landmark_root.get_node_or_null("cathedral/ReligiousLandmark") != null, "Orthodox cathedral must load in Tirana")
			assert(landmark_root.get_node_or_null("prime_minister/CivicLandmark") != null, "Prime minister's office must load in Tirana")
			var mosaic := landmark_root.get_node_or_null("national_museum/CivicLandmark/MuseumMosaic") as MeshInstance3D
			assert(mosaic != null and mosaic.material_override != null, "Museum and mosaic must load in Tirana")
			assert((mosaic.mesh as QuadMesh).size.is_equal_approx(Vector2(37, 11)) and mosaic.position.z > 34.0, "Museum mosaic should keep its real proportions on the projecting frontage")
			var windows := landmark_root.get_node_or_null("national_museum/CivicLandmark/MuseumRecessedWindows") as MultiMeshInstance3D
			var piers := landmark_root.get_node_or_null("national_museum/CivicLandmark/MuseumPorticoPiers") as MultiMeshInstance3D
			var marble := landmark_root.get_node_or_null("national_museum/CivicLandmark/MuseumSideMasonry") as MultiMeshInstance3D
			assert(windows != null and windows.multimesh.instance_count == 22, "Museum's two side elevations should have recessed windows")
			assert(piers != null and piers.multimesh.instance_count == 7, "Museum should have a recessed columned entrance")
			assert(marble != null and marble.multimesh.mesh != null, "Museum side masonry must load")
			var stone := marble.multimesh.mesh.surface_get_material(0) as StandardMaterial3D
			assert(stone != null and stone.albedo_texture != null and stone.normal_enabled and stone.roughness_texture != null, "Museum marble needs color, normal and roughness maps")
			assert(scene.props.get_node_or_null("BllokuCafes") != null, "The Blloku route needs its café terraces")
			var trees: TiranaTrees = scene.props.vegetation
			var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cities/tirane/props.json"))
			assert(trees.entries.size() == int(data.trees.size() * float(Quality.p.tree_mul)))
			var replaced := trees.entries.filter(func(entry: Dictionary): return entry.excluded)
			assert(replaced.size() == planted.size(), "pine replacements take exactly one broadleaf slot each")
			assert(trees.get_child_count() > 6 and trees.get_child_count() < 100,
				"the city keeps local batches and six moving tree pools")
		else:
			assert(planted.is_empty(), "the Tirana pilot must not change other cities")
		if FileAccess.file_exists("res://assets/cities/%s/water_near.bin" % city.id):
			# Open water: under the whole road and every edge of it, seabed
			# beneath it, land above it.
			assert(scene.sea != null and scene.sea.get_parent() == scene, "a city with baked water needs its sea")
			var surface := scene.terrain.water_surface
			assert(is_equal_approx(scene.sea.position.y, surface))
			for i in range(0, scene.track.M, 4):
				var x := scene.track.X[i]
				var z := scene.track.Z[i]
				assert(scene.track.Y[i] > surface + 0.3, "the road must stay above the sea")
				for side in [-1.0, 1.0]:
					var ex: float = x + scene.track.NX[i] * side * (scene.track.half_w + 8.0)
					var ez: float = z + scene.track.NZ[i] * side * (scene.track.half_w + 8.0)
					assert(not scene.terrain.is_water(ex, ez), "no open water beside the road")
					assert(scene.terrain.height_at(ex, ez) > surface, "the road's ground must stay dry")
			var wet := 0
			for k in scene.terrain.water_mask.size():
				if scene.terrain.water_mask[k] >= 128:
					wet += 1
					assert(scene.terrain.near_h[k] <= surface - 2.9, "seabed must sit well under the surface")
				else:
					assert(scene.terrain.near_h[k] >= surface + 0.24, "land must stay above the surface")
			assert(wet > 0)
			print("SEA: ", city.id, " surface ", surface, " m, ", wet, " water cells")
		if city.id == "shkoder":
			# The centre loop shares Tirana's street trees and city facades.
			var street_trees := scene.props.vegetation
			assert(street_trees != null and street_trees.name == "StreetTrees", "Shkodër plants the shared street trees")
			assert(street_trees.entries.size() > 0)
			assert(scene.buildings.facade_mat.shader == Buildings.FACADE_SHADER, "Shkodër uses the shared city facades")
			assert(scene.track.L > 3000.0 and scene.track.L < 4000.0, "the centre loop is about 3.5 km")
			var shk_marks: Node = null
			for child in scene.props.get_children():
				if child is Landmarks:
					shk_marks = child
			for id in ["mosque", "flagpole"]:
				var at := (shk_marks.get_node(id) as Node3D).global_position
				assert(scene.track.dist_to(at.x, at.z) > scene.track.half_w + 8.0, "landmark off the road: " + id)
			print("SHKODER: ", snappedf(scene.track.L, 1.0), " m lap, ", street_trees.entries.size(), " street trees")
		if city.id == "vlore":
			# Lungomare: palms on the sea side, on dry ground and clear of the
			# road; café terraces on the land side.
			var grove := scene.props.get_node_or_null("Palms")
			assert(grove != null, "Lungomare needs its palms")
			var mm := (grove.get_node("PalmTrunks") as MultiMeshInstance3D).multimesh
			assert(mm.instance_count >= 40, "a promenade's worth of palms")
			var baked: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cities/vlore/props.json"))
			assert(mm.instance_count == baked.palms.size())
			# Headless rendering does not retain individual MultiMesh transforms.
			for palm in baked.palms:
				var at := Vector3(palm[0], palm[1], palm[2])
				assert(not scene.terrain.is_water(at.x, at.z), "palms stand on dry ground")
				assert(scene.track.dist_to(at.x, at.z) >= scene.track.half_w + 2.0, "palms stay off the road")
				assert(at.y > scene.terrain.water_surface, "palms stand above the sea")
			assert(scene.props.get_node_or_null("BllokuCafes") != null, "Lungomare needs its café terraces")
			print("LUNGOMARE: ", mm.instance_count, " palms")
			var ground := scene.props.get_node_or_null("SeafrontPromenade/PromenadeGround") as MeshInstance3D
			assert(ground != null and ground.mesh != null and ground.mesh.get_surface_count() == 1, "Lungomare needs its paving and lawns")
			# The landmarks: each model loads, stands off the road, and is in
			# sight of it (within 70 m of the race line).
			var marks: Node = null
			for child in scene.props.get_children():
				if child is Landmarks:
					marks = child
			var expected := {"flamurtari": "FlamurtariStadium", "independence": "IndependenceMonument",
				"independence_museum": "IndependenceHouse", "flagpole_big": "GreatFlag",
				"vlora_house": "VloreHeritage/VloraHouseFacade", "muradie_mosque": "VloreHeritage/MuradieMasonry",
				"petro_marko": "VloreCivic/PetroMarkoTheatre", "skela_roundabout": "VloreCivic/SkelaPlantedIsland",
				"lungomare_gateway": "VloreCivic/LungomareTwinWings", "waterfront_courts": "WaterfrontCourts/CourtSurfacesAndFixtures",
				"vlore_municipality": "VloreCivic/MunicipalityFacade", "lungomare_paragliders": "Paragliders/Paraglider0"}
			for id: String in expected:
				var root := marks.get_node(id) as Node3D
				assert(root.get_node_or_null(str(expected[id])) != null, "Vlorë landmark model missing: " + id)
			var facade := marks.get_node("flamurtari/FlamurtariStadium/MainFacade") as Node3D
			var front := facade.global_transform * Vector3(FlamurtariStadium.FRONT, 0, 0)
			var gap := scene.track.dist_to(front.x, front.z)
			assert(gap > scene.track.half_w + 30.0 and gap < 70.0, "the stadium facade faces the boulevard across its plaza")
			for id in ["independence", "independence_museum", "flagpole_big"]:
				var at := (marks.get_node(id) as Node3D).global_position
				var d := scene.track.dist_to(at.x, at.z)
				# The great flag stands on Flag Square, beside the run back onto it.
				var off := 8.0 if id == "flagpole_big" else 20.0
				assert(d > scene.track.half_w + off and d < 70.0, "landmark off the road and in sight of it: " + id)
			# The great flag: the national flag's texture (5:7) on a rippling cloth.
			var flag := marks.get_node("flagpole_big/GreatFlag") as MeshInstance3D
			var cloth := flag.material_override as ShaderMaterial
			var eagle := cloth.get_shader_parameter("flag_tex") as Texture2D
			assert(eagle != null and absf(float(eagle.get_width()) / eagle.get_height() - 1.4) < 0.01, "the great flag shows the eagle at 5:7")
			assert(is_equal_approx(float(cloth.get_shader_parameter("width")) / float(cloth.get_shader_parameter("height")), 1.4))
			# Paragliders circle high over the seafront and move.
			var flock := marks.get_node("lungomare_paragliders/Paragliders") as Paragliders
			assert(flock.gliders.size() >= 5, "paragliders over Lungomare")
			var before := flock.gliders[0].global_position
			flock._place(30.0)
			assert(flock.gliders[0].global_position.distance_to(before) > 20.0, "the paragliders fly")
			for glider in flock.gliders:
				var g := glider.global_position
				assert(g.y - scene.terrain.height_at(g.x, g.z) > 60.0, "paragliders fly high")
				assert(scene.track.dist_to(g.x, g.z) < 700.0, "paragliders in sight of the road")
			_test_vlore_resort(scene)
			_test_vlore_circuit(scene, marks)
			print("VLORE LANDMARKS: stadium facade ", snappedf(gap, 0.1), " m from the race line")
		elif not FileAccess.file_exists("res://assets/cities/%s/water_near.bin" % city.id):
			assert(scene.sea == null, "inland cities have no sea")
		await get_tree().process_frame
		print("CITY WORLD: ", city.id, " loaded with six cars")
		Sfx.stop_all()
		scene.queue_free()
		await get_tree().process_frame
		count += 1
	print("CITY WORLDS: ", count, " loaded")
	get_tree().quit()


func _test_vlore_circuit(scene: RaceScene, marks: Node) -> void:
	var track := scene.track
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cities/vlore/track.json"))
	assert(track.L > 10000.0 and track.L < 11200.0, "the Vlorë out-and-back stays near 10.6 km")
	# Out and back on the seafront road: two one-way carriageways of two
	# lanes, a divider between them.
	assert(bool(data.get("one_way", false)) and int(data.get("lanes", 0)) == 2, "Vlorë is raced on one-way carriageways")
	assert(is_equal_approx(track.half_w, 4.5), "each carriageway is 9 m wide")
	assert(scene.road.surface_mat.get_shader_parameter("one_way") == true, "no yellow centre line on a one-way carriageway")
	# Outbound, from the line on Bulevardi Ismail Qemali past Kuzum Baba
	# down to the waterfront courts; back the same way after the far loop.
	var outbound := ["petro_marko", "flamurtari", "skela_roundabout", "independence_museum",
		"lungomare_gateway"]
	var prior := 0.0
	var first := {}
	for landmark: String in outbound:
		var at := (marks.get_node(landmark) as Node3D).position
		var passes := _passes(track, at)
		assert(passes.size() == 2, "the lap passes %s twice (%d)" % [landmark, passes.size()])
		assert(passes[0] > prior, "Vlorë outbound landmarks must be passed in order: " + landmark)
		prior = passes[0]
		first[landmark] = passes
	# The sports courts and their rock-armoured shore are on the far loop,
	# past the merge, before the tunnel.
	var courts := _passes(track, (marks.get_node("waterfront_courts") as Node3D).position)
	assert(courts.size() == 1 and courts[0] > prior, "the far loop passes the waterfront courts once")
	prior = courts[0]
	var entry := track.locate_xz(data.tunnel[0][0], data.tunnel[0][1]).x
	var exit := track.locate_xz(data.tunnel[1][0], data.tunnel[1][1]).x
	var turn := track.locate_xz(data.turnaround[0][0], data.turnaround[0][1]).x
	assert(prior < entry and entry + 70.0 < exit and exit < turn, "the far loop: tunnel, then the turnaround")
	var back := turn
	outbound.reverse()
	for landmark: String in outbound:
		var second: float = first[landmark][1]
		assert(second > back, "Vlorë return passes the landmarks in reverse order: " + landmark)
		back = second
	# Up past the Muradie Mosque, off the boulevard and up through Muradie
	# with the Bashkia on the right, across the top and down Rruga Demokracia
	# onto Flag Square by the Independence Monument, then down past the
	# mosque again to the line.
	var mosque := _passes(track, (marks.get_node("muradie_mosque") as Node3D).position)
	var bashkia_at := (marks.get_node("vlore_municipality") as Node3D).position
	var bashkia := _passes(track, bashkia_at)
	var square := _passes(track, (marks.get_node("independence") as Node3D).position)
	assert(mosque.size() == 2 and bashkia.size() == 1, "the near loop passes the Bashkia once")
	assert(back < mosque[0] and mosque[0] < bashkia[0] and bashkia[0] < square[-1] and square[-1] < mosque[1] and mosque[1] < track.L,
		"the run to the line: Muradie, the Bashkia, Flag Square, the mosque")
	var by_bashkia := track.pos(bashkia[0], 0.0)
	var to_bashkia := Vector2(bashkia_at.x - by_bashkia.x, bashkia_at.z - by_bashkia.z)
	var right := Vector2(track.normal(bashkia[0]).x, track.normal(bashkia[0]).z)
	assert(to_bashkia.dot(right) > 0.0, "the Bashkia is on the right coming from Muradie")
	assert(to_bashkia.length() < 60.0, "the Bashkia stands by the road")
	var corner := INF
	for k in range(int((mosque[0] + 60.0) / track.ds), int((mosque[1] - 60.0) / track.ds)):
		var kappa := absf(track.curv(k * track.ds))
		if kappa > 1e-4:
			corner = minf(corner, 1.0 / kappa)
	assert(corner > 30.0, "the near loop has no tight turn (tightest %.0f m)" % corner)
	# The two passes never share road: wherever the lap comes back past
	# itself, the carriageways stay a divider apart.
	var tight := INF
	var grid := {}
	var pts := PackedVector2Array()
	for k in track.M:
		var p := track.pos(k * track.ds, 0.0)
		pts.append(Vector2(p.x, p.z))
		var cell := Vector2i(floori(p.x / 10.0), floori(p.z / 10.0))
		if not grid.has(cell):
			grid[cell] = []
		grid[cell].append(k)
	var apart := int(60.0 / track.ds)
	for k in track.M:
		var c := Vector2i(floori(pts[k].x / 10.0), floori(pts[k].y / 10.0))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for other: int in grid.get(c + Vector2i(dx, dz), []):
					var gap := absi(other - k)
					if mini(gap, track.M - gap) > apart:
						tight = minf(tight, pts[k].distance_to(pts[other]))
	assert(tight >= 2.0 * track.half_w + 0.4, "the carriageways never touch (closest %.1f m)" % tight)
	# Sheshi Pavarsia is a real roundabout: each pass circles the island on
	# the ring, kerbed splitters between the entries and exits, and the
	# field slows for it.
	var rings: Array = data.get("roundabouts", [])
	assert(rings.size() == 1, "Sheshi Pavarsia is a roundabout")
	var ring: Array = rings[0]
	var on_ring := 0
	for k in track.M:
		var p := track.pos(k * track.ds, 0.0)
		if absf(Vector2(p.x - float(ring[0]), p.z - float(ring[1])).length() - float(ring[2])) < 1.0:
			on_ring += 1
	assert(on_ring * track.ds > 70.0, "both passes drive the ring (%.0f m on it)" % (on_ring * track.ds))
	var dressing := scene.road.get_node("Roundabout") as RoundaboutRing
	assert(dressing.get_node("CirculatingCarriageway") != null and dressing.get_node("SplitterIslands") != null)
	assert(not scene.road.open_edges.is_empty(), "the island side of the ring stays open")
	assert(track.slow_zones.size() == 2, "the field slows round Sheshi Pavarsia on both passes")
	var slow := INF
	for zone: Array in track.slow_zones:
		slow = minf(slow, track.slow_speed(float(zone[0]) + 5.0, Race.SLOW_ZONE_DECEL, 240.0))
	assert(slow * 3.6 < 60.0, "AI target speed in the roundabout (%.0f km/h)" % (slow * 3.6))
	var baked: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cities/vlore/props.json"))
	for anchor: Dictionary in baked.landmarks:
		if not anchor.has("radius"):
			continue
		var clear := track.dist_to(anchor.x, anchor.z) - track.half_w
		var least := 15.0 if anchor.id == "skela_roundabout" else 6.0
		assert(float(anchor.radius) >= least, "%s: a real island (%.1f m)" % [anchor.id, anchor.radius])
		assert(clear >= float(anchor.radius) + 0.5, "%s: the island clears the road (%.1f m)" % [anchor.id, clear])
	var approach := track.tangent(turn)
	var turn_dot := 1.0
	for after in range(25, 170, 5):
		turn_dot = minf(turn_dot, approach.dot(track.tangent(turn + after)))
	assert(turn_dot < -0.85, "the road reverses heading after the southern portal")
	assert(scene.road.get_node_or_null("UjiIFtohteTunnel/TunnelBore") != null)
	print("VLORE OUT-AND-BACK: %.0f m, carriageways at least %.1f m apart" % [track.L, tight])
	for i in track.M * 4:
		var s := i * track.ds * 0.25
		for side: float in [-1.0, 1.0]:
			var d := side * (track.half_w + 0.7)
			var at := track.pos(s, d)
			var next := track.pos(s + track.ds * 0.25, d)
			assert((next - at).dot(track.tangent(s)) > 0.0, "Vlorë road edge folds at %.1f m" % s)
	for s in range(int(entry) - 5, int(exit) + 5, 2):
		var at := track.pos(s, 0.0)
		assert(at.y > scene.terrain.height_at(at.x, at.z), "tunnel road must clear the cut terrain")
	var reverse := RaceTrack.load_city("vlore", true)
	var tunnel := preload("res://scripts/world/vlore_tunnel.gd").new()
	add_child(tunnel)
	tunnel.build(reverse, data.tunnel, true, scene.terrain)
	var bore := tunnel.get_node("TunnelBore") as MeshInstance3D
	assert(bore.mesh.get_aabb().size.length() < 145.0, "reverse race must build the same short bore")
	tunnel.queue_free()


## Hotels up the hillside and the beach club on the shore before the tunnel.
func _test_vlore_resort(scene: RaceScene) -> void:
	var resort := scene.props.resort
	assert(resort != null, "Vlorë needs its hotels and beach club before the tunnel")
	assert(resort.get_node("HotelWalls") != null and resort.get_node("HotelGlazing") != null)
	assert(resort.get_node("BeachClub/PoolWater") != null and resort.get_node("BeachClub/ParasolsAndCanopies") != null)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cities/vlore/track.json"))
	var portal := scene.track.locate_xz(data.tunnel[0][0], data.tunnel[0][1]).x
	var baked: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cities/vlore/props.json"))
	var hotels: Array = baked.resort.hotels
	assert(hotels.size() >= 8, "a row of hotels")
	for h: Array in hotels:
		var d := scene.track.dist_to(float(h[0]), float(h[2]))
		assert(d > scene.track.half_w + 15.0, "hotels stand back from the road")
		var before := scene.track.mod_s(portal - scene.track.locate_xz(float(h[0]), float(h[2])).x)
		assert(before > 30.0 and before < 420.0, "hotels line the road before the tunnel (%.0f m)" % before)
	var club: Dictionary = baked.resort.club
	var club_at := Vector2(float(club.x), float(club.z))
	assert(scene.track.dist_to(club_at.x, club_at.y) > scene.track.half_w + 8.0, "the deck starts past the barrier")
	var into_sea := club_at + Vector2(sin(deg_to_rad(float(club.yaw))), cos(deg_to_rad(float(club.yaw)))) * (float(club.depth) * 0.5 + 12.0)
	assert(scene.terrain.is_water(into_sea.x, into_sea.y), "the beach club looks over the sea")
	print("VLORE RESORT: %d hotels, pool %.0f x %.0f m" % [hotels.size(), club.pool[0], club.pool[1]])


## Arc positions where the lap passes closest to `at`, one per pass (a pass
## within 20 m of the nearest counts), in lap order.
func _passes(track: RaceTrack, at: Vector3) -> Array:
	var best := INF
	var d := PackedFloat32Array()
	d.resize(track.M)
	for k in track.M:
		var p := track.pos(k * track.ds, 0.0)
		d[k] = Vector2(p.x - at.x, p.z - at.z).length()
		best = minf(best, d[k])
	var out := []
	var k := 0
	while k < track.M:
		if d[k] <= best + 20.0:
			var low := k
			while k < track.M and d[k] <= best + 20.0:
				if d[k] < d[low]:
					low = k
				k += 1
			out.append(low * track.ds)
		k += 1
	return out
