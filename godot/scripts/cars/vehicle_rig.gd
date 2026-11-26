class_name VehicleRig
extends RefCounted
## Asset-space metres, +Y up, nose -Z. Wheel axle is CarRoot's X axis.

const GT := {
	"model_path": "res://assets/cars/vortex_gt.glb", "legacy": true, "allow_private": true,
	"visual_scale": 1.0, "wheel_radius": 0.0, "wheelbase": 0.0, "wheel_offsets": {},
	"material_slots": {}, "light_nodes": {}, "nitro_sockets": {}, "lod_models": {},
}
const WHEELS := ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]
const LIGHTS := {"front": "Headlights", "rear": "BrakeLights"}
const SOCKETS := {"left": "Nitro_L", "right": "Nitro_R"}
## Optional brake calipers, one per wheel, as CarRoot children placed on the
## wheel's axle: they steer with the front wheels but do not spin.
const CALIPERS := {"Wheel_FL": "Caliper_FL", "Wheel_FR": "Caliper_FR", "Wheel_RL": "Caliper_RL", "Wheel_RR": "Caliper_RR"}

const HATCH := {
	"model_path": "res://assets/cars/hatch.glb", "visual_scale": 1.0,
	"wheel_radius": .32, "wheelbase": 2.5296, "wheel_offsets": {},
	"material_slots": {}, "light_nodes": LIGHTS, "nitro_sockets": SOCKETS, "lod_models": {},
}
## mk2design's "Generic Supercar Cheetah" (CC BY 4.0), converted by
## tools/import_cheetah.py at the source's scale (0.383 m tyres, which the tyre
## and rim shaders expect); visual_scale fits it to the game's footprint.
## `driver_offset` moves the driver down and back into the low cabin.
const CHEETAH := {
	"model_path": "res://assets/cars/cheetah.glb", "visual_scale": 0.78,
	"wheel_radius": .3832, "wheelbase": 2.996, "wheel_offsets": {},
	"material_slots": {}, "light_nodes": LIGHTS, "nitro_sockets": SOCKETS, "lod_models": {},
	"driver_offset": Vector3(0.0, -0.26, 0.12),
}
const ESTATE := {
	"model_path": "res://assets/cars/estate.glb", "visual_scale": 1.0,
	"wheel_radius": .35, "wheelbase": 2.868, "wheel_offsets": {},
	"material_slots": {}, "light_nodes": LIGHTS, "nitro_sockets": SOCKETS, "lod_models": {},
}


static func root(scene: Node3D) -> Node3D:
	var child := scene.get_node_or_null("CarRoot") as Node3D
	return child if child else scene


static func validate(rig: Node3D, profile: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if profile.get("legacy", false):
		for part in ["body", "wheel_fl", "wheel_fr", "wheel_rl", "wheel_rr"]:
			var mesh := rig.get_node_or_null(part) as MeshInstance3D
			if mesh == null or mesh.mesh == null:
				errors.append("missing legacy mesh or wheel pivot " + part)
		return errors
	for part in ["Body", "Glass", "Interior"]:
		if not rig.get_node_or_null(part) is Node3D:
			errors.append("missing part " + part)
	var body := rig.get_node_or_null("Body") as MeshInstance3D
	if body == null or body.mesh == null:
		errors.append("Body must be a paintable mesh")
	for wheel in WHEELS:
		var pivot := rig.get_node_or_null(wheel) as Node3D
		if pivot == null or ((not pivot is MeshInstance3D or not pivot.mesh) and pivot.find_children("*", "MeshInstance3D", true, false).is_empty()):
			errors.append("missing wheel pivot or wheel mesh " + wheel)
	for role in LIGHTS:
		var path := str(profile.get("light_nodes", {}).get(role, LIGHTS[role]))
		if not rig.get_node_or_null(path) is Node3D:
			errors.append("missing light node " + path)
	for role in SOCKETS:
		var path := str(profile.get("nitro_sockets", {}).get(role, SOCKETS[role]))
		if not rig.get_node_or_null(path) is Node3D:
			errors.append("missing nitro socket " + path)
	var found := {}
	var slots: Dictionary = profile.get("material_slots", {})
	for mesh: MeshInstance3D in rig.find_children("*", "MeshInstance3D", true, false):
		if not mesh.mesh:
			continue
		for i in mesh.mesh.get_surface_count():
			var mat := mesh.mesh.surface_get_material(i)
			if mat:
				found[slots.get(mat.resource_name, mat.resource_name)] = true
	for role in ["paint", "glass", "interior", "light_front", "light_rear", "tyre", "rim"]:
		if not found.has(role):
			errors.append("missing material slot " + role)
	if float(profile.get("visual_scale", 1.0)) <= 0 or float(profile.get("wheel_radius", 0)) <= 0 or float(profile.get("wheelbase", 0)) <= 0:
		errors.append("visual_scale, wheel_radius and wheelbase must be positive")
	return errors
