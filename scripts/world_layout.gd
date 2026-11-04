## The static world, shared by the server and every client: the same seed gives the same pillars everywhere, so the
## simulation (collision) and the visuals agree exactly. Later this becomes level data loaded from a file.
class_name WorldLayout

## A pillar: centre x, z, half sizes hx, hz, and height h (it stands on the ground, y from 0 to h).
class Box:
	var cx := 0.0
	var cz := 0.0
	var hx := 0.0
	var hz := 0.0
	var h := 0.0

static var _boxes: Array = []


static func boxes() -> Array:
	if _boxes.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 20261104
		for i in 60:
			var b := Box.new()
			b.h = rng.randf_range(1.0, 7.0)
			b.hx = rng.randf_range(0.8, 2.5) / 2.0
			b.hz = rng.randf_range(0.8, 2.5) / 2.0
			var r := rng.randf_range(15.0, Config.WORLD_HALF - 10.0)
			var a := rng.randf() * TAU
			b.cx = cos(a) * r
			b.cz = sin(a) * r
			_boxes.append(b)
		# three steps near the spawn, to try jumping onto things
		for spec in [[6.0, -6.0, 1.0, 1.0, 0.9], [9.0, -9.0, 1.2, 1.2, 1.9], [12.5, -12.5, 1.4, 1.4, 3.0]]:
			var s := Box.new()
			s.cx = spec[0]; s.cz = spec[1]; s.hx = spec[2]; s.hz = spec[3]; s.h = spec[4]
			_boxes.append(s)
	return _boxes


## Height of the surface under (x, z) at or below y: the top of a pillar or step, or the ground (0). For shadows and
## animation (on the ground or in the air).
static func ground_height(x: float, z: float, y: float) -> float:
	var best := 0.0
	for b: Box in boxes():
		if absf(x - b.cx) <= b.hx + Sim.RADIUS and absf(z - b.cz) <= b.hz + Sim.RADIUS and b.h <= y + 0.05 and b.h > best:
			best = b.h
	return best


## Distance along a ray (origin o, unit direction d) to the first box it enters, or INF. For the camera.
static func ray_hit(o: Vector3, d: Vector3, max_t: float) -> float:
	var best := INF
	for b: Box in boxes():
		var lo := Vector3(b.cx - b.hx, 0.0, b.cz - b.hz)
		var hi := Vector3(b.cx + b.hx, b.h, b.cz + b.hz)
		var t0 := 0.0
		var t1 := max_t
		var hit := true
		for k in 3:
			if absf(d[k]) < 1e-9:
				if o[k] < lo[k] or o[k] > hi[k]:
					hit = false
					break
			else:
				var a := (lo[k] - o[k]) / d[k]
				var c := (hi[k] - o[k]) / d[k]
				t0 = maxf(t0, minf(a, c))
				t1 = minf(t1, maxf(a, c))
				if t0 > t1:
					hit = false
					break
		if hit and t0 < best:
			best = t0
	return best
