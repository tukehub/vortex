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
				"vlore_municipality": "VloreCivic/MunicipalityFacade"}
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
				assert(d > scene.track.half_w + 20.0 and d < 70.0, "landmark off the road and in sight of it: " + id)
			var flag := marks.get_node("flagpole_big/GreatFlag") as MeshInstance3D
			assert((flag.material_override as ShaderMaterial).get_shader_parameter("use_tex"), "the great flag shows the eagle")
			_test_vlore_circuit(scene, marks)
			print("VLORE LANDMARKS: stadium facade ", snappedf(gap, 0.1), " m from the race line")
		else:
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
	var prior := 0.0
	assert(track.L < 11200.0, "the compact Vlorë circuit must stay near 11 km")
	# The start/finish is on Bulevardi Ismail Qemali, 100 m before the road
	# passes Kuzum Baba (cities.py finish_before), so the lap opens past
	# Petro Marko and closes through Flag Square, the Vlora house and the
	# Muradie Mosque.
	for landmark in ["petro_marko", "flamurtari", "skela_roundabout",
			"independence_museum", "lungomare_gateway", "waterfront_courts"]:
		var at := (marks.get_node(landmark) as Node3D).position
		var s := track.locate_xz(at.x, at.z).x
		assert(s > prior, "Vlorë outbound landmarks must be passed in order: " + landmark)
		prior = s
	var entry := track.locate_xz(data.tunnel[0][0], data.tunnel[0][1]).x
	var exit := track.locate_xz(data.tunnel[1][0], data.tunnel[1][1]).x
	var old_town := track.locate_xz(data.stone_street[0][0], data.stone_street[0][1]).x
	var turn := track.locate_xz(data.turnaround[0][0], data.turnaround[0][1]).x
	var city_hall := (marks.get_node("vlore_municipality") as Node3D).position
	var hall_s := track.locate_xz(city_hall.x, city_hall.z).x
	assert(prior < entry and entry + 70.0 < exit and exit < turn and turn < old_town and old_town < hall_s)
	assert(hall_s > track.L - 1100.0, "town hall should be on the final approach to Flag Square")
	var run_in := []
	for landmark in ["independence", "vlora_house", "muradie_mosque"]:
		var at := (marks.get_node(landmark) as Node3D).position
		run_in.append(track.locate_xz(at.x, at.z).x)
	assert(hall_s < run_in[0] and run_in[0] < run_in[1] and run_in[1] < run_in[2] and run_in[2] < track.L,
		"the run to the line passes Flag Square, the Vlora house and the Muradie Mosque")
	var approach := track.tangent(turn)
	var turn_dot := 1.0
	for after in range(25, 170, 5):
		turn_dot = minf(turn_dot, approach.dot(track.tangent(turn + after)))
	assert(turn_dot < -0.85, "the road reverses heading after the southern portal")
	assert(scene.road.get_node_or_null("UjiIFtohteTunnel/TunnelBore") != null)
	var median := scene.road.get_node_or_null("LungomarePavedMedian") as MeshInstance3D
	assert(median != null and median.mesh.get_aabb().size.length() < 900.0, "Lungomare needs a short raised median")
	assert(scene.road.get_node_or_null("MuradieStreet/MuradieStreetFronts") != null)
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
