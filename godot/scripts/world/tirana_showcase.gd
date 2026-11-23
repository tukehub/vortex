extends RefCounted
## Distances are measured in metres from Tirana's forward start line.
## Keep the endpoint in sync with tools/pipeline/showcase_facades.py.
const LENGTH := 450.0
const CROSSINGS := Vector3(86.0, 273.0, 391.0)


static func forward_s(track: RaceTrack, at: float, reverse: bool) -> float:
	return track.mod_s(-at if reverse else at)


static func crossing_distance(forward_at: float) -> float:
	return minf(absf(forward_at - CROSSINGS.x),
		minf(absf(forward_at - CROSSINGS.y), absf(forward_at - CROSSINGS.z)))
