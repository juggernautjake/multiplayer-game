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
	var kind := ""   # "" a plain pillar, "step" / "tower" the wizard's tower, "vault" the hidden vault (drawn specially)

static var _boxes: Array = []

## The wizard's tower (Jacob 2026-11-04): a spiral of pillar steps round a tall column, each a jump higher than the
## last, up to a platform 15.6 m up where the wizard's staff lies. In sight of the spawn.
const TOWER_C := Vector2(-26.0, -34.0)
const TOWER_TOP := 15.6
const TOWER_HALF := 2.0
const TOWER_STEPS := 12
const TOWER_R := 4.6          # the steps' distance from the column's centre
## The hidden vault: a low stone block far from the spawn, its trapdoor on the far side (you have to walk round to see
## it). E at the door opens it; the magic wand sits on a shelf inside.
const VAULT_C := Vector2(54.0, 38.0)
## v0.10.0: the Duel Stone (E: a challenger steps out to fight you) and the Storm Altar (a giant round button in the
## ground; jump onto it at level 3 to call Thunderhorn), with open ground round them for the fights.
const DUEL_C := Vector2(17.0, -3.0)
const DUEL_HALF := Vector2(0.55, 0.4)
const DUEL_H := 1.7
const ALTAR_C := Vector2(0.0, 42.0)
const ARENA_R := 20.0
## v0.12.0 the Storm Altar's button is solid (for anyone at level 3, who sees it risen): a drum ALTAR_BTN_R wide whose
## top is at ALTAR_UP, or ALTAR_DOWN while pressed (the whole boss fight). `altar_pressed` is set by Net on the server
## every tick and on clients from the boss state, so client prediction stands you on the same top.
const ALTAR_BTN_R := 2.6
const ALTAR_UP := 0.6
const ALTAR_DOWN := 0.2
static var altar_pressed := false


static func altar_top() -> float:
	return ALTAR_DOWN if altar_pressed else ALTAR_UP
const VAULT_HALF := 1.8
const VAULT_H := 2.6
const VAULT_DOOR := Vector3(55.8, 0.0, 38.0)   # the middle of the door, on the vault's +x face (facing away from the spawn)
const VAULT_SHELF := Vector3(55.35, 0.55, 38.0)

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
	# v0.12.0: real apple trees round Thunderhorn's arena (centre (0, 52), radius 20), just inside its edge
	["apple", Vector3(12.7, 0.0, 64.7)], ["apple", Vector3(-12.7, 0.0, 64.7)], ["apple", Vector3(-13.5, 0.0, 40.5)],
	["apple", Vector3(13.5, 0.0, 40.5)], ["apple", Vector3(0.0, 0.0, 70.5)],
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
	[6, Vector3(-26.0, 15.6, -34.0), 1],    # the wizard's staff, on top of the tower
	[7, Vector3(55.35, 0.55, 38.0), 1],     # the magic wand, in the vault (only reachable with its door open)
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
			var c := Vector2(b.cx, b.cz)
			if c.distance_to(TOWER_C) < TOWER_R + 4.5 or c.distance_to(VAULT_C) < VAULT_HALF + 4.0                     or c.distance_to(DUEL_C) < 9.0 or c.distance_to(ALTAR_C + Vector2(0, 10)) < ARENA_R:
				continue   # keep the tower, the vault, the Duel Stone's ground and the boss's arena clear
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
		# the wizard's tower: the column, then the steps spiralling up from the side facing the spawn
		var col := Box.new()
		col.cx = TOWER_C.x; col.cz = TOWER_C.y; col.hx = TOWER_HALF; col.hz = TOWER_HALF; col.h = TOWER_TOP; col.kind = "tower"
		_boxes.append(col)
		var a0 := atan2(-TOWER_C.y, -TOWER_C.x)
		for i in TOWER_STEPS:
			var st := Box.new()
			var a := a0 + deg_to_rad(32.0) * i
			st.cx = TOWER_C.x + cos(a) * TOWER_R
			st.cz = TOWER_C.y + sin(a) * TOWER_R
			st.hx = 0.85; st.hz = 0.85
			st.h = 1.1 + 1.2 * i
			st.kind = "step"
			_boxes.append(st)
		var v := Box.new()
		v.cx = VAULT_C.x; v.cz = VAULT_C.y; v.hx = VAULT_HALF; v.hz = VAULT_HALF; v.h = VAULT_H; v.kind = "vault"
		var ds := Box.new()   # the Duel Stone: a standing stone you can't walk through
		ds.cx = DUEL_C.x; ds.cz = DUEL_C.y; ds.hx = DUEL_HALF.x; ds.hz = DUEL_HALF.y; ds.h = DUEL_H; ds.kind = "duel"
		_boxes.append(ds)
		_boxes.append(v)
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
