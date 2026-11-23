extends Node

func _ready() -> void:
	var cover := preload("res://scripts/world/coastal_cover.gd").new()
	add_child(cover)
	Quality.set_preset("low")
	cover.build()
	var previous := 0
	var mesh_ids := {}
	for preset in ["low", "medium", "high"]:
		Quality.set_preset(preset)
		var total := 0
		for batch in cover._batches:
			var mm := batch.multimesh
			total += mm.visible_instance_count
			mesh_ids[mm.mesh.get_instance_id()] = true
			assert(mm.visible_instance_count <= mm.instance_count)
			assert(batch.visibility_range_end > 0. and mm.custom_aabb.has_volume())
			assert(batch.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		assert(total > previous)
		previous = total
		print("COASTAL COVER ", preset, " enabled tier instances=", total, " pines=", cover._pine_count)
	assert(mesh_ids.size() == 4, "two tuft/brush meshes per tier across all chunks")
	assert(cover._pine_count == cover._pine_sites.size())
	Quality.set_pressure_stage(2)
	assert(cover._materials[0].get_shader_parameter("wind_m") == 0.)
	assert(cover._pine_count < cover._pine_sites.size())
	get_tree().quit()
