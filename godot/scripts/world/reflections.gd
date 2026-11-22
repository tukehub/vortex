class_name RaceReflections
extends Node3D
## Reflection probes for a race (plan 3.3). Both renderers draw them; Mobile
## blends at most Quality.REFLECTION_PROBES_PER_MESH into one mesh.
##
## - One probe follows the player (Quality.p.probe: medium and high). It is
##   UPDATE_ONCE: Godot re-renders it, one cube face a frame, only when it
##   moves, so it jumps ahead by Quality.p.probe_step metres instead of
##   sliding with the car every frame.
## - High adds static, box-projected probes beside the landmarks nearest the
##   road (Quality.p.landmark_probes), built once and toggled with the budget.
##
## Probes see the world only: cars sit on PLAYER_LAYER / CAR_LAYER, outside
## PROBE_MASK, so no car is frozen into a reflection or reflects its own roof.

const PLAYER_LAYER := RaceViews.PLAYER_LAYER
const CAR_LAYER := 3
const PROBE_MASK := 0xFFFFF & ~((1 << (PLAYER_LAYER - 1)) | (1 << (CAR_LAYER - 1)))
const FOLLOW_SIZE := Vector3(180.0, 50.0, 180.0)
const FOLLOW_HEIGHT := 3.0
const LANDMARK_SIZE := Vector3(100.0, 50.0, 100.0)
const LANDMARK_HEIGHT := 4.0
## Only landmarks this close to the centreline get a probe.
const LANDMARK_REACH := 140.0
const MAX_LANDMARK_PROBES := 6

var follow: ReflectionProbe
var landmark_probes: Array[ReflectionProbe] = []
## How many times the follow probe was moved (each move is one re-render).
var follow_moves := 0
var _has_focus := false


func _ready() -> void:
	follow = _probe(FOLLOW_SIZE, false)
	follow.name = "FollowProbe"
	follow.max_distance = 220.0
	add_child(follow)
	Quality.budget_changed.connect(_apply_budget)
	_apply_budget()


func _probe(size: Vector3, box_projection: bool) -> ReflectionProbe:
	var probe := ReflectionProbe.new()
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.size = size
	probe.box_projection = box_projection
	probe.interior = false
	probe.enable_shadows = false
	probe.cull_mask = PROBE_MASK
	probe.blend_distance = 16.0
	probe.intensity = 1.0
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	probe.max_distance = 160.0
	return probe


## Static probes at the landmarks nearest the road, closest first.
func build_landmarks(track: RaceTrack, anchors: Array) -> void:
	for probe in landmark_probes:
		probe.queue_free()
	landmark_probes.clear()
	var picks := []
	for anchor in anchors:
		var x := float(anchor.x)
		var z := float(anchor.z)
		var i := track.nearest(x, z, LANDMARK_REACH)
		if i < 0:
			continue
		var road := Vector3(track.X[i], track.Y[i], track.Z[i])
		var distance := Vector2(road.x - x, road.z - z).length()
		picks.append({"distance": distance, "road": road, "anchor": Vector3(x, road.y, z)})
	picks.sort_custom(func(a, b): return float(a.distance) < float(b.distance))
	for pick in picks:
		if landmark_probes.size() >= MAX_LANDMARK_PROBES:
			break
		# Halfway between the road and the landmark, so its box covers both.
		var at: Vector3 = ((pick.road as Vector3) + (pick.anchor as Vector3)) * 0.5
		var near := false
		for other in landmark_probes:
			if other.position.distance_to(at) < LANDMARK_SIZE.x * 0.5:
				near = true
				break
		if near:
			continue
		var probe := _probe(LANDMARK_SIZE, true)
		probe.name = "LandmarkProbe%d" % landmark_probes.size()
		probe.position = at + Vector3(0.0, LANDMARK_HEIGHT, 0.0)
		add_child(probe)
		landmark_probes.append(probe)
	_apply_budget()


func _apply_budget() -> void:
	if follow != null:
		follow.visible = bool(Quality.p.probe) and _has_focus
	var count := int(Quality.p.get("landmark_probes", 0))
	for i in landmark_probes.size():
		landmark_probes[i].visible = i < count


## Every frame with the player's position and heading. The probe moves (and so
## re-renders) only when the car is a step away from where it last rendered,
## and then lands half a step ahead, over the road still to come.
func update_focus(at: Vector3, forward: Vector3) -> void:
	if not _has_focus:
		_has_focus = true
		_apply_budget()
	if not follow.visible:
		return
	var step := float(Quality.p.probe_step)
	var flat := Vector2(at.x - follow.position.x, at.z - follow.position.z)
	if follow_moves > 0 and flat.length() < step:
		return
	var ahead := Vector3(forward.x, 0.0, forward.z).normalized() * step * 0.5
	follow.position = at + ahead + Vector3(0.0, FOLLOW_HEIGHT, 0.0)
	follow_moves += 1


## Takes a car's meshes off the probes' world layer (the player's car is on
## PLAYER_LAYER already, set by RaceViews).
static func hide_from_probes(node: Node) -> void:
	if node is GeometryInstance3D:
		var geometry := node as GeometryInstance3D
		if geometry.layers & 1:
			geometry.layers = (geometry.layers & ~1) | (1 << (CAR_LAYER - 1))
	for child in node.get_children():
		hide_from_probes(child)
