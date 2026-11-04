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

## Practice dummies near the spawn: hit them to see your damage. Target ids -1, -2, -3.
const DUMMIES := [Vector3(-4.0, 0.0, -9.0), Vector3(0.0, 0.0, -10.0), Vector3(4.0, 0.0, -9.0)]

## The yard's trees (Ecology): two fruit trees near the spawn and a ring of oaks. [kind, position]. Their trunks are
## solid (added to the boxes below).
const TREES := [
	["apple", Vector3(12.0, 0.0, 9.0)], ["pear", Vector3(17.5, 0.0, 14.0)],
	["oak", Vector3(-14.0, 0.0, 10.0)], ["oak", Vector3(-20.0, 0.0, -6.0)], ["oak", Vector3(-11.0, 0.0, -22.0)],
	["oak", Vector3(9.0, 0.0, -24.0)], ["oak", Vector3(22.0, 0.0, -10.0)], ["oak", Vector3(26.0, 0.0, 4.0)],
	["oak", Vector3(4.0, 0.0, 24.0)], ["oak", Vector3(-6.0, 0.0, 22.0)], ["oak", Vector3(30.0, 0.0, 20.0)],
	["oak", Vector3(-26.0, 0.0, 14.0)],
]
const TRUNK := { "apple": [0.22, 2.2], "pear": [0.22, 2.2], "oak": [0.38, 3.2] }   # half width, height


## Which tree's trunk a point is inside (-1 if none).
static func tree_at(pt: Vector3, margin := 0.0) -> int:
	for i in TREES.size():
		var t: Array = TREES[i]
		var tk: Array = TRUNK[t[0]]
		if absf(pt.x - t[1].x) < tk[0] + margin and absf(pt.z - t[1].z) < tk[0] + margin and pt.y < float(tk[1]) + 2.6 and pt.y > -0.1:
			return i
	return -1


## Where the weapons and ammo lie at the start (and come back 20 s after someone takes them): [item kind, position,
## count]. Kinds are Weapons.Item: CLUB, SWORD, BOW, SLING, ARROWS, ROCKS.
const ITEM_SPAWNS := [
	[0, Vector3(-7.0, 0.0, -3.0), 1], [1, Vector3(-5.5, 0.0, -1.5), 1], [2, Vector3(5.5, 0.0, -1.5), 1],
	[3, Vector3(7.0, 0.0, -3.0), 1], [4, Vector3(6.5, 0.0, 0.5), 12], [5, Vector3(8.5, 0.0, -1.0), 15],
	[4, Vector3(-2.0, 0.0, -14.0), 8], [5, Vector3(2.0, 0.0, -14.0), 10],
]


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
		for t in TREES:   # tree trunks are solid
			var tb := Box.new()
			var tk: Array = TRUNK[t[0]]
			tb.cx = t[1].x
			tb.cz = t[1].z
			tb.hx = tk[0]
			tb.hz = tk[0]
			tb.h = tk[1]
			_boxes.append(tb)
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
