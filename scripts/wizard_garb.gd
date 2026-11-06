## Wizard garb, purely visual and worked out on every client from the player's state (no network traffic):
##   the staff (WIZARD): a wandering wizard's long, worn grey robe from the shoulders to the floor, a grey travelling
##     cloak over the shoulders falling down the back, a loose rope belt, and a tall, wide-brimmed, pointed felt hat
##     with a soft, crooked tip;
##   the wand (SHADOW): one heavy, floor-length dark robe from the head to the floor with a deep cowl hood that frames
##     and shadows the face;
##   both (BOTH): the grey wizard's garb wins (robe, cloak, hat; no hood).
## It goes when the item goes (the staff and wand go back to the tower and the vault when their holder leaves).
##
## v0.8.1: the robe is one garment over the whole body, not a skirt. It is a stack of rings: the top ones (shoulders,
## chest, waist) follow the torso as it turns, leans and breathes; the ones below are heavy cloth (Verlet particles):
## they hang from the waist ring, keep their length, spring gently back toward hanging straight in long folds, are
## pushed out of the legs, never swing more than ~60 degrees out, and stay above the ground. Heavy: damped, with a
## weighted hem, swaying slowly; it lags on turns, swings on a stop and billows a little on a dash. The cloak is an
## open sheet of the same cloth pinned across the shoulders behind the neck; it is lighter, so it lags and swings more.
## The hat is a chain of points from the brim to the tip, springing back toward a soft, bent shape (stiff at the base,
## floppy at the tip). The hood is a deep cowl whose opening sits in front of the face, with a short point at the back.
## Avatars call update() every frame with where the body is (FigureAvatar and Avatar each work that out their own way).
## v0.12.8: the body as capsules in this frame's pose (f.body, see "the body the cloth lies on"): every piece is kept
## outside it, one-sided cloth on its own side; the knight's tabard is belted at the waist; the cloth turns with a snap
## turn like it moves with a dash; drawn as one indexed mesh.
class_name WizardGarb
extends Node3D

enum Kind { NONE, WIZARD, SHADOW, BOTH, BRAWLER, KNIGHT, BARBARIAN, RANGER, SCOUT }
## v0.9.0: every weapon has its own costume, worn while it's the one in your hand (synced: the equipped weapon is in
## every snapshot, so everyone sees the same). LOOK names Pip's costume sheets (tools/make_costumes.py).
const COSTUME := { Weapons.FISTS: Kind.BRAWLER, Weapons.SWORD: Kind.KNIGHT, Weapons.CLUB: Kind.BARBARIAN,
	Weapons.BOW: Kind.RANGER, Weapons.SLING: Kind.SCOUT, Weapons.STAFF: Kind.WIZARD, Weapons.WAND: Kind.SHADOW }
const LOOK := { Kind.BRAWLER: "brawler", Kind.KNIGHT: "knight", Kind.BARBARIAN: "barbarian", Kind.RANGER: "ranger",
	Kind.SCOUT: "scout", Kind.WIZARD: "wizard", Kind.SHADOW: "shadow", Kind.BOTH: "wizard" }

const GREY := Color("6d6f73")
const GREY_CLOAK := Color("5c5f63")
const WEAR := Color("6e6458")          # dust and wear at the hem
const ROPE := Color("a8916a")
const DARK := Color("1d1824")
const DARK_EDGE := Color("2c2436")
const STRANDS := 20
const THICK := 0.02          # the cloth's thickness (m)
const CLOAK_COLS := 9
const HAT_N := 6
const TAIL_N := 3


## Which costume this player wears: the one for the weapon in their hand.
static func kind_for(st: Sim.PlayerState) -> int:
	if st == null:
		return Kind.NONE
	return COSTUME.get(st.weapon, Kind.BRAWLER)


## The robe's colour for a kind (the figure recolours its tunic, sleeves and trousers to match).
static func robe_color(k: int) -> Color:
	return DARK if k == Kind.SHADOW else GREY


static func wizard(k: int) -> bool:
	return k == Kind.WIZARD or k == Kind.BOTH


var kind := Kind.NONE
var _t := 0.0
# robe: rows of STRANDS points; rows < pinned follow the body
var _p := PackedVector3Array()
var _o := PackedVector3Array()
var _rows := 0
var _have_robe := false
var _last_anchor := Vector3.ZERO
var _robe_mesh: ArrayMesh
var _pinned_rows := 0
var _robe_len := PackedFloat32Array()   # per row: the length of cloth from the waist ring down to it
var _cloak_seg := 0.0
var _var: PackedFloat32Array        # per-strand shade variation (folds, fading)
# cloak
var _cp := PackedVector3Array()
var _co := PackedVector3Array()
var _crows := 0
var _have_cloak := false
var _cloak_mesh: ArrayMesh
# hat
var _hat_p: Array = []
var _hat_o: Array = []
var _have_hat := false
var _hat_segs: Array = []
var _brim: MeshInstance3D
var _band: MeshInstance3D
var _hat_mat: StandardMaterial3D
var _hat_built_for := -1.0
# hood
var _hood: MeshInstance3D
var _tail_p: Array = []
var _tail_o: Array = []
var _have_tail := false
var _tail_segs: Array = []
var _hood_built_for := -1.0
var _belt: MeshInstance3D


func _init() -> void:
	top_level = true   # everything here is placed in world space
	_var = PackedFloat32Array()
	for j in STRANDS:
		_var.append(randf_range(-0.05, 0.05))


func _ready() -> void:
	global_transform = Transform3D.IDENTITY


func set_kind(k: int) -> void:
	if k == kind:
		return
	kind = k
	for c in get_children():
		c.queue_free()
	_brim = null
	_band = null
	_hood = null
	_belt = null
	_hat_segs = []
	_tail_segs = []
	_have_robe = false
	_have_cloak = false
	_have_hat = false
	_have_tail = false
	_hat_built_for = -1.0
	_hood_built_for = -1.0
	_sheets = {}
	_chains = {}
	_satchel = null
	if k == Kind.NONE:
		return
	if k in [Kind.WIZARD, Kind.BOTH, Kind.SHADOW, Kind.BARBARIAN]:
		_robe_mesh = _cloth_node()   # the robe, or the barbarian's kilt
	if wizard(k) or k == Kind.RANGER:
		_cloak_mesh = _cloth_node()
	if k == Kind.KNIGHT:
		for id in ["tabard_front", "tabard_back"]:
			_sheets[id] = { "mesh": _cloth_node(), "have": false }


func _cloth_node() -> ArrayMesh:
	var im := ArrayMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var m := _cloth_mat(Color.WHITE)
	m.vertex_color_use_as_albedo = true
	mi.material_override = m
	add_child(mi)
	return im


static func _cloth_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m


## f: rings (top to bottom: [centre, basis, x radius, z radius]; the first `pinned` follow the body, the rest are the
## shape the cloth hangs toward), pinned, colliders ([[a, b, r]] capsules: legs), ground, vel, head_top, head_c,
## head_r, up, face (unit, horizontal), neck, hat_h, hat_r, brim_r, own (this client's own player: the hat goes
## see-through so it never hides the crosshair), visible.
static var busy_usec := 0   # time spent in update() so far, all players together (the cloth test reports it)


func update(delta: float, f: Dictionary) -> void:
	if kind == Kind.NONE:
		return
	var t0 := Time.get_ticks_usec()
	_update(delta, f)
	busy_usec += Time.get_ticks_usec() - t0


func _update(delta: float, f: Dictionary) -> void:
	_t += delta
	visible = bool(f.get("visible", true))
	if not visible:
		_have_robe = false
		_have_cloak = false
		_have_hat = false
		_have_tail = false
		return
	var dt := clampf(delta, 0.001, 1.0 / 30.0)
	_frame_dt = maxf(delta, 1.0 / 240.0)
	_set_body(f)
	_turn_carry(f)
	match kind:
		Kind.WIZARD, Kind.BOTH:
			_robe(f, dt)
			_cloak(f, dt)
			_hat(f, dt)
			_rope(f)
		Kind.SHADOW:
			_robe(f, dt)
			_hood_up(f, dt)
		Kind.BARBARIAN:   # the hide kilt: the robe's cloth from the waist to the knees
			_robe(f, dt)
		Kind.RANGER:
			_cloak(f, dt)
		Kind.KNIGHT:      # the tabard: a panel hanging in front and one behind, to the knees
			for id in ["tabard_front", "tabard_back"]:
				var pins: Array = f[id]
				_sheet(id, pins[0], pins[1], f[id + "_belt"], float(f.tabard_skirt), f, dt, f.accent)
		Kind.BRAWLER:     # the sash's ends and the headband's tails
			_chain("sash_a", f.sash_at, f.sash_dir, 4, 0.07, 0.035, f.accent, dt, f, f.get("front_n", Vector3.ZERO))
			_chain("sash_b", (f.sash_at as Vector3) + (f.sash_side as Vector3) * 0.05, f.sash_dir, 3, 0.07, 0.03, f.accent, dt, f, f.get("front_n", Vector3.ZERO))
			_chain("band_a", f.band_at, f.band_dir, 3, 0.06, 0.02, f.accent, dt, f, f.get("head_back", Vector3.ZERO))
			_chain("band_b", (f.band_at as Vector3) + (f.band_side as Vector3) * 0.04, f.band_dir, 3, 0.055, 0.018, f.accent, dt, f, f.get("head_back", Vector3.ZERO))
		Kind.SCOUT:       # the bandana's knot tails, and the satchel bouncing on the hip
			_chain("knot_a", f.band_at, f.band_dir, 2, 0.06, 0.02, f.accent, dt, f, f.get("head_back", Vector3.ZERO))
			_chain("knot_b", (f.band_at as Vector3) + (f.band_side as Vector3) * 0.04, f.band_dir, 2, 0.055, 0.018, f.accent, dt, f, f.get("head_back", Vector3.ZERO))
			_satchel_bounce(f, dt)


# ================================================================ v0.12: cloth keeps up with fast moves
## Cloth may lag the body by what a sprint would give it, never more: on a dash, a teleport, a frame hitch or a net
## correction the body moves far further than that in one frame, and the cloth used to be left behind and then whip
## back. `_carry(step)` is the part of the body's step to move every free point (and its previous position) along by
## before integrating, so only a run's worth of lag is left to swing.
var lag_speed := 7.0   # m/s of body motion the cloth is allowed to trail
var _frame_dt := 1.0 / 60.0


func _carry(step: Vector3, lag := -1.0) -> Vector3:
	var keep := (lag_speed if lag < 0.0 else minf(lag, lag_speed)) * _frame_dt
	var l := step.length()
	return step * ((l - keep) / l) if l > keep else Vector3.ZERO


## v0.12.8 the same for turning: the body may spin round faster than TURN_LAG (a snap turn is ~14 rad/s); the cloth
## turns along with it by all but that much, round the body's upright axis, so a quick turn swings it a little
## instead of flinging the panels out like wings.
const TURN_LAG := 3.0
var _yaw_prev := INF


func _turn_carry(f: Dictionary) -> void:
	if not f.has("yaw"):
		return
	var yaw := float(f.yaw)
	var dy := 0.0 if is_inf(_yaw_prev) else wrapf(yaw - _yaw_prev, -PI, PI)
	_yaw_prev = yaw
	var keep := TURN_LAG * _frame_dt
	var ex := dy - clampf(dy, -keep, keep)
	if absf(ex) < 1e-4 or absf(dy) > 2.5:
		return
	var c: Vector3 = f.get("center", Vector3.ZERO)
	var rot := Basis(Vector3.UP, ex)
	var turn := func(q: Vector3) -> Vector3: return c + rot * (q - c)
	if _have_robe:
		for k in range(_pinned_rows * STRANDS, _p.size()):
			_p[k] = turn.call(_p[k])
			_o[k] = turn.call(_o[k])
	if _have_cloak:
		for k in range(CLOAK_COLS, _cp.size()):
			_cp[k] = turn.call(_cp[k])
			_co[k] = turn.call(_co[k])
	for id in _sheets:
		var sh: Dictionary = _sheets[id]
		if sh.have:
			var P: PackedVector3Array = sh.p
			var O: PackedVector3Array = sh.o
			for k in range((BELT_ROW + 1) * SHEET_COLS, P.size()):
				P[k] = turn.call(P[k])
				O[k] = turn.call(O[k])
			sh.p = P
			sh.o = O
	for id in _chains:
		var ch: Dictionary = _chains[id]
		if ch.have:
			for k in range(1, (ch.p as Array).size()):
				ch.p[k] = turn.call(ch.p[k])
				ch.o[k] = turn.call(ch.o[k])
	for arr in [[_have_tail, _tail_p, _tail_o], [_have_hat, _hat_p, _hat_o]]:
		if arr[0]:
			for k in range(1, (arr[1] as Array).size()):
				arr[1][k] = turn.call(arr[1][k])
				arr[2][k] = turn.call(arr[2][k])


static func _shift(p: PackedVector3Array, o: PackedVector3Array, from: int, d: Vector3) -> void:
	if d == Vector3.ZERO:
		return
	for k in range(from, p.size()):
		p[k] += d
		o[k] += d


static func _shift_arr(p: Array, o: Array, from: int, d: Vector3) -> void:
	if d == Vector3.ZERO:
		return
	for k in range(from, p.size()):
		p[k] = (p[k] as Vector3) + d
		o[k] = (o[k] as Vector3) + d


# ================================================================ v0.12.8: the body the cloth lies on
## The avatar sends the body as capsules (f.body: [a, b, radius, flat ends, Tag], world space, this frame's pose after
## the animation). Every cloth point is kept a cloth's thickness and a hair (GAP) outside all of them, in every solver
## pass and once more after the last one, so what's drawn never cuts into the body. One-sided cloth (the cloak, the
## tabard's panels, tails behind the head) is pushed out to its own side of each capsule (`side`), never through it
## to the far side: a leg or an arm that moved a long way in one frame can't end up on the wrong side of the cloth.
## Only the capsules near each piece of cloth are tried (by bounding boxes), so it stays cheap with many players.
enum Tag { TORSO, HIPS, LEG, ARM, HEAD, GEAR }
const GAP := 0.012
const REACH := 0.3   # how far through a capsule (past its middle) a one-sided point is still taken back to its side
const LIMB_REACH := 0.1
var _body: Array = []
var _body_lo := PackedVector3Array()
var _body_hi := PackedVector3Array()
var _body_tlo := PackedVector3Array()   # the same boxes without the reach (for cloth pushed straight out: the robe)
var _body_thi := PackedVector3Array()


func _set_body(f: Dictionary) -> void:
	_body = f.get("body", [])
	_body_lo.resize(_body.size())
	_body_hi.resize(_body.size())
	_body_tlo.resize(_body.size())
	_body_thi.resize(_body.size())
	for i in _body.size():
		var c: Array = _body[i]
		var reach := LIMB_REACH if int(c[4]) == Tag.ARM or int(c[4]) == Tag.LEG else REACH
		var pad := Vector3.ONE * (float(c[2]) + THICK + GAP + reach)   # (a point on the wrong side, within reach, too)
		_body_lo[i] = (c[0] as Vector3).min(c[1]) - pad
		_body_hi[i] = (c[0] as Vector3).max(c[1]) + pad
		var tight := Vector3.ONE * (float(c[2]) + THICK + GAP)
		_body_tlo[i] = (c[0] as Vector3).min(c[1]) - tight
		_body_thi[i] = (c[0] as Vector3).max(c[1]) + tight


## The capsules (indices) whose boxes reach the box round points[from..] grown by `grow` (how far a point may move
## this frame), keeping only the tags in `tags` (empty: all).
func _near(pts, from: int, grow: float, tags := []) -> PackedInt32Array:
	var out := PackedInt32Array()
	if _body.is_empty() or pts.size() <= from:
		return out
	var lo: Vector3 = pts[from]
	var hi: Vector3 = lo
	for k in range(from, pts.size()):
		lo = lo.min(pts[k])
		hi = hi.max(pts[k])
	lo -= Vector3.ONE * grow
	hi += Vector3.ONE * grow
	var rest := PackedInt32Array()   # (the arms go first: the body always has the last word)
	for i in _body.size():
		if not tags.is_empty() and not (int((_body[i] as Array)[4]) in tags):
			continue
		var a: Vector3 = _body_lo[i]
		var b: Vector3 = _body_hi[i]
		if a.x <= hi.x and b.x >= lo.x and a.y <= hi.y and b.y >= lo.y and a.z <= hi.z and b.z >= lo.z:
			if int((_body[i] as Array)[4]) == Tag.ARM:
				out.append(i)
			else:
				rest.append(i)
	out.append_array(rest)
	return out


## `p` out of the capsules `near`: to `side` of each one (ZERO: straight out), arms to `arm_side`.
func _collide(p: Vector3, near: PackedInt32Array, side: Vector3, arm_side: Vector3) -> Vector3:
	for i in near:
		var lo: Vector3 = _body_lo[i]
		var hi: Vector3 = _body_hi[i]
		if p.x < lo.x or p.y < lo.y or p.z < lo.z or p.x > hi.x or p.y > hi.y or p.z > hi.z:
			continue
		var c: Array = _body[i]
		var tag := int(c[4])
		p = _push_side(p, c[0], c[1], float(c[2]) + THICK + GAP, c[3], arm_side if tag == Tag.ARM else side, tag == Tag.ARM or tag == Tag.LEG)
	return p


## Out of one capsule (a-b, radius r; with flat ends, only alongside it). With a side: out on that side of it (the
## side squared off against the capsule's length), whichever side the point was on; along the capsule, or with no
## side, straight out.
static func _push_side(p: Vector3, a: Vector3, b: Vector3, r: float, flat: bool, side: Vector3, limb := false) -> Vector3:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := (p - a).dot(ab) / l2 if l2 > 1e-8 else 0.0
	if flat and (t < 0.0 or t > 1.0):
		return p
	var c := a + ab * clampf(t, 0.0, 1.0)
	var d := p - c
	# well clear; on the wrong side, a point up to REACH past the capsule's middle still goes back round to its side
	var reach := LIMB_REACH if limb else REACH
	var lim := r if side == Vector3.ZERO or d.dot(side) > 0.0 else r + reach
	if absf(d.x) > lim or absf(d.y) > lim or absf(d.z) > lim:
		return p
	var np := side
	if l2 > 1e-8 and side != Vector3.ZERO:
		var ax := ab / sqrt(l2)
		np = side - ax * side.dot(ax)
	# no side, or it runs along the capsule, or (a limb held level: a knee up, an arm out) it would go up or down
	# round it: straight out (a raised knee must not flip a hanging panel up over itself)
	if np.length_squared() < 0.09 or (limb and absf(np.y) > 0.6 * np.length()):
		var dl := d.length()
		if dl >= r:
			return p
		if dl < 1e-5:
			return c + (side if side != Vector3.ZERO else Vector3.UP) * r
		return c + d * (r / dl)
	np = np.normalized()
	var s := d.dot(np)
	var lat := d - np * s
	var ll2 := lat.length_squared()
	if ll2 >= r * r:
		return p
	var need := sqrt(r * r - ll2)
	return p + np * (need - s) if s < need and s > -r - reach else p


# ================================================================ the robe
func _ring_pt(ring: Array, a: float) -> Vector3:
	return (ring[0] as Vector3) + (ring[1] as Basis) * Vector3(cos(a) * float(ring[2]), 0, sin(a) * float(ring[3]))


func _robe(f: Dictionary, dt: float) -> void:
	var rings: Array = f.rings
	var pinned := int(f.pinned)
	var rows := rings.size()
	var anchor: Vector3 = (rings[pinned - 1] as Array)[0]
	if not _have_robe or rows != _rows or anchor.distance_to(_last_anchor) > 2.5:   # start hanging still
		_rows = rows
		_p.resize(rows * STRANDS)
		_o.resize(rows * STRANDS)
		for i in rows:
			for j in STRANDS:
				_p[i * STRANDS + j] = _ring_pt(rings[i], TAU * j / STRANDS)
				_o[i * STRANDS + j] = _p[i * STRANDS + j]
		_have_robe = true
		_last_anchor = anchor
	var step := anchor - _last_anchor   # the body's own motion this frame: damping is relative to it
	_last_anchor = anchor
	var carry := _carry(step)
	_shift(_p, _o, pinned * STRANDS, carry)
	step -= carry
	var heavy := 1.0
	# v0.12.8 cloth hangs along the body's upright (the figure's own up, not the leaning torso's): straight down standing,
	# along the body lying down (it used to stand out flat from a lying body)
	var up: Vector3 = f.get("body_up", Vector3.UP)
	var vel: Vector3 = f.get("vel", Vector3.ZERO)
	var flutter := clampf((Vector2(vel.x, vel.z).length() - 5.0) / 12.0, 0.0, 1.0) * 0.35   # a little billow, fast only
	var dt2 := dt * dt
	_pinned_rows = pinned
	_robe_len.resize(rows)
	_robe_len[pinned - 1] = 0.0
	for i in range(pinned, rows):
		_robe_len[i] = _robe_len[i - 1] + ((rings[i] as Array)[0] as Vector3).distance_to((rings[i - 1] as Array)[0]) * 1.01
	for j in STRANDS:
		var a := TAU * float(j) / float(STRANDS)
		for i in pinned:
			_p[i * STRANDS + j] = _ring_pt(rings[i], a)
			_o[i * STRANDS + j] = _p[i * STRANDS + j]
		var out := ((rings[pinned] as Array)[1] as Basis) * Vector3(cos(a), 0, sin(a))
		for i in range(pinned, rows):
			var k := i * STRANDS + j
			var u := float(i - pinned + 1) / float(rows - pinned)
			var p: Vector3 = _p[k]
			var v := step * 0.99 + ((p - _o[k]) - step) * 0.8   # heavy: well damped
			_o[k] = p
			var acc := Vector3(0, -14.0, 0)
			acc += (_ring_pt(rings[i], a) - p) * lerpf(26.0, 12.0, u)   # it falls back into long straight folds
			acc += out * (sin(_t * 6.0 + float(j) * 1.7 + float(i) * 0.6)) * flutter * 6.0 * u
			_p[k] = p + v + acc * dt2
	var cols: Array = f.get("colliders", [])
	var arm_cols: Array = f.get("arm_colliders", [])
	var ground := float(f.get("ground", -100.0)) + 0.02
	var near := _near(_p, pinned * STRANDS, 0.3, [Tag.TORSO, Tag.HIPS, Tag.GEAR])
	# v0.12.8 (cheaper) each row's link length and each strand's width worked out once a frame, not per point and pass;
	# the legs and arms tried only where a point is inside their reach (a box round each)
	var want := PackedFloat32Array()
	var hw := PackedFloat32Array()
	want.resize(rows)
	hw.resize(rows * STRANDS)
	for i in range(pinned, rows):
		want[i] = ((rings[i] as Array)[0] as Vector3).distance_to((rings[i - 1] as Array)[0]) * 1.01
		for j in STRANDS:
			hw[i * STRANDS + j] = _ring_pt(rings[i], TAU * j / STRANDS).distance_to(_ring_pt(rings[i], TAU * ((j + 1) % STRANDS) / STRANDS))
	# the arms first, then the legs: [a, b, radius, reach box]
	var la := PackedVector3Array()
	var lb := PackedVector3Array()
	var llo := PackedVector3Array()
	var lhi := PackedVector3Array()
	var lr := PackedFloat32Array()
	var arms := arm_cols.size()
	for c in arm_cols + cols:
		var r := float(c[2])
		var m := Vector3.ONE * r * (1.0 if la.size() < arms else 1.5)
		la.append(c[0])
		lb.append(c[1])
		lr.append(r)
		llo.append((c[0] as Vector3).min(c[1]) - m)
		lhi.append((c[0] as Vector3).max(c[1]) + m)
	var nl := la.size()
	for it in 3:
		var last := it == 2
		for j in STRANDS:
			var jn := (j + 1) % STRANDS
			for i in range(pinned, rows):
				var k := i * STRANDS + j
				var p := _hang(_p[k - STRANDS], _p[k], want[i], up)
				var q: Vector3 = _p[i * STRANDS + jn]
				var e := q - p
				var el := e.length()
				if el > 1e-5:
					var corr := e * (0.5 * (el - hw[k]) / el) * 0.6
					p += corr
					_p[i * STRANDS + jn] = q - corr
				# v0.12.8 the arms first (cloth goes to their inner side), then the legs and the body itself, which
				# always win: the arms used to come last and tuck the cloth into the hips and thighs
				for c in nl:
					var lo := llo[c]
					var hi := lhi[c]
					if p.x < lo.x or p.y < lo.y or p.z < lo.z or p.x > hi.x or p.y > hi.y or p.z > hi.z:
						continue
					p = _push_inward(p, la[c], lb[c], lr[c], anchor) if c < arms else _push_from_leg(p, la[c], lb[c], lr[c], anchor)
				if last:
					p = _robe_body(p, near, anchor)
				if p.y < ground:
					p.y = ground
				_p[k] = p
	# last, no segment longer than its rest length (the side constraints and colliders can leave one stretched), and out
	# of the legs and the body once more
	for i in range(pinned, rows):
		for j in STRANDS:
			var k := i * STRANDS + j
			var p: Vector3 = _p[k]
			var d: Vector3 = p - _p[k - STRANDS]
			if d.length() > want[i]:
				p = _p[k - STRANDS] + d * (want[i] / d.length())
			for c in range(arms, nl):
				var lo := llo[c]
				var hi := lhi[c]
				if p.x < lo.x or p.y < lo.y or p.z < lo.z or p.x > hi.x or p.y > hi.y or p.z > hi.z:
					continue
				p = _push_from_leg(p, la[c], lb[c], lr[c], anchor)
			_p[k] = _robe_body(p, near, anchor)

	_draw_loop(_robe_mesh, _p, rows, pinned, f.get("robe_col", robe_color(kind)), true)


## A robe's point out of the body, away from the robe's middle.
func _robe_body(p: Vector3, near: PackedInt32Array, anchor: Vector3) -> Vector3:
	for i in near:
		var lo: Vector3 = _body_tlo[i]
		var hi: Vector3 = _body_thi[i]
		if p.x < lo.x or p.y < lo.y or p.z < lo.z or p.x > hi.x or p.y > hi.y or p.z > hi.z:
			continue
		var c: Array = _body[i]
		var out := Vector3(p.x - anchor.x, 0, p.z - anchor.z)
		p = _push_side(p, c[0], c[1], float(c[2]) + THICK + GAP, c[3], out.normalized() if out.length() > 1e-4 else Vector3.ZERO)
	return p


## Keep `p` `want` from `above`, no more than ~60 degrees out from hanging straight down.
static func _hang(above: Vector3, p: Vector3, want: float, up: Vector3, min_drop := 0.5) -> Vector3:
	var d := p - above
	if d.length() < 1e-5:
		return above - up * want
	var down := -up
	var dd := maxf(d.normalized().dot(down) * want, want * min_drop)   # the drop, for a segment exactly `want` long
	var hz := d - down * d.dot(down)
	var hl := sqrt(maxf(want * want - dd * dd, 0.0))
	return above + down * dd + (hz.normalized() * hl if hz.length() > 1e-5 else Vector3.ZERO)


## Keep cloth in front of a leg, never behind it: anything within the leg's reach on the body's side of it, or just
## in front, goes out past the leg, away from the body's middle (pushing it out of the nearest side of the leg let a leg
## that outran the cloth in one frame end up in front of the robe).
static func _push_from_leg(p: Vector3, a: Vector3, b: Vector3, r: float, axis: Vector3) -> Vector3:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	var c := a + ab * t
	var o := Vector3(c.x - axis.x, 0, c.z - axis.z)
	var d := p - c
	if o.length() < 0.16 or absf(d.y) > r * 1.5:   # under the body (standing): inside the robe already, no push
		return _push_out(p, a, b, r * 0.8)
	o = o.normalized()
	var flat := Vector3(d.x, 0, d.z)
	var along := flat.dot(o)
	var perp := (flat - o * along).length()
	if perp < r * 0.85 and along < r and along > -r * 1.5:   # just in front of the leg, or caught between it and the body
		return p + o * (r - along)
	return p


## Forearms and hands: cloth near them goes to their inner side (toward the body's middle), so a robe never swallows
## a hand or a swinging arm; the arm stays outside the cloth with its own sleeve.
static func _push_inward(p: Vector3, a: Vector3, b: Vector3, r: float, axis: Vector3) -> Vector3:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	var c := a + ab * t
	if p.distance_to(c) >= r:
		return p
	var inn := Vector3(axis.x - c.x, 0, axis.z - c.z)
	if inn.length() < 1e-4:
		return p
	var q := c + inn.normalized() * r
	return Vector3(q.x, p.y, q.z)


static func _push_out(p: Vector3, a: Vector3, b: Vector3, r: float) -> Vector3:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	var c := a + ab * t
	var d := p - c
	var dl := d.length()
	if dl < r and dl > 1e-5:
		return c + d * (r / dl)
	return p


## A closed tube of cloth (the robe) as triangles, with soft normals, shade varying round it (folds) and down it,
## and wear at the hem. v0.12.8: one shared vertex per cloth point (indexed, the indices made once), handed over in
## one call: it used to be ~2500 vertices sent one call at a time, every frame, the most expensive part of a robe.
static var _index_cache := {}


func _draw_loop(am: ArrayMesh, pts: PackedVector3Array, rows: int, pinned: int, body: Color, wear: bool) -> void:
	var S := STRANDS
	var n := rows * S
	var key := "loop%d_%d" % [rows, pinned]
	if not _index_cache.has(key):
		var ix := PackedInt32Array()
		for i in rows - 1:   # the outside
			for j in S:
				var jn := (j + 1) % S
				ix.append_array([i * S + j, i * S + jn, (i + 1) * S + j, i * S + jn, (i + 1) * S + jn, (i + 1) * S + j])
		for i in range(pinned, rows - 1):   # the lining
			for j in S:
				var jn := (j + 1) % S
				ix.append_array([n + i * S + j, n + (i + 1) * S + j, n + i * S + jn, n + i * S + jn, n + (i + 1) * S + j, n + (i + 1) * S + jn])
		for j in S:   # the hem's edge, from the outside to the lining
			var jn := (j + 1) % S
			ix.append_array([2 * n + j, 2 * n + S + j, 2 * n + jn, 2 * n + jn, 2 * n + S + j, 2 * n + S + jn])
		_index_cache[key] = ix
	var vx := PackedVector3Array()
	var nm := PackedVector3Array()
	var cl := PackedColorArray()
	vx.resize(2 * n + 2 * S)
	nm.resize(2 * n + 2 * S)
	cl.resize(2 * n + 2 * S)
	var lining := body.darkened(0.35)
	var hem_c := body.lerp(WEAR, 0.5) if wear else body.darkened(0.2)
	for r in rows:
		var mid := Vector3.ZERO
		for j in S:
			mid += pts[r * S + j]
		mid /= float(S)
		var u := float(r) / float(rows - 1)
		var r0 := maxi(r - 1, 0) * S
		var r1 := mini(r + 1, rows - 1) * S
		for j in S:
			var k := r * S + j
			var p: Vector3 = pts[k]
			var side: Vector3 = pts[r * S + (j + 1) % S] - pts[r * S + (j + S - 1) % S]
			var dn: Vector3 = pts[r1 + j] - pts[r0 + j]
			var nn := dn.cross(side)
			nn = nn.normalized() if nn.length_squared() > 1e-12 else Vector3.UP
			vx[k] = p
			nm[k] = nn
			var c := body * (1.0 + _var[j] - 0.1 * u)
			if wear and r == rows - 1:
				c = c.lerp(WEAR, 0.45 + _var[j] * 3.0)
			cl[k] = c
			# the cloth's thickness: the lining a little inside the outside, darker
			var inward := Vector3(mid.x - p.x, 0, mid.z - p.z)
			var ip := p + (inward.normalized() * THICK if inward.length_squared() > 1e-8 else Vector3.ZERO)
			vx[n + k] = ip
			nm[n + k] = (ip - p).normalized() if ip.distance_squared_to(p) > 1e-10 else Vector3.UP
			cl[n + k] = lining
			if r == rows - 1:
				vx[2 * n + j] = p
				vx[2 * n + S + j] = ip
				nm[2 * n + j] = Vector3.DOWN
				nm[2 * n + S + j] = Vector3.DOWN
				cl[2 * n + j] = hem_c
				cl[2 * n + S + j] = hem_c
	_commit(am, vx, nm, cl, _index_cache[key])


static func _commit(am: ArrayMesh, vx: PackedVector3Array, nm: PackedVector3Array, cl: PackedColorArray, ix: PackedInt32Array) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vx
	arrays[Mesh.ARRAY_NORMAL] = nm
	arrays[Mesh.ARRAY_COLOR] = cl
	arrays[Mesh.ARRAY_INDEX] = ix
	am.clear_surfaces()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


# ================================================================ the cloak (the wizard's)
func _cloak(f: Dictionary, dt: float) -> void:
	var rings: Array = f.rings
	var top: Array = rings[0]
	var rows := 6
	# a fixed length (from the shoulders to near the feet), never down to the ground: mid-jump it used to stretch
	var hang_len := float(f.cloak_len) if f.has("cloak_len") else ((top[0] as Vector3).y - float(f.get("feet_y", f.ground))) * 0.86
	var seg := hang_len / float(rows - 1)
	_cloak_seg = seg
	var basis: Basis = top[1]
	var up: Vector3 = f.get("body_up", Vector3.UP)
	var n := rows * CLOAK_COLS
	var anchor: Vector3 = top[0]
	if not _have_cloak:
		_cp.resize(n)
		_co.resize(n)
		for i in rows:
			for c in CLOAK_COLS:
				_cp[i * CLOAK_COLS + c] = _cloak_top(top, c) - up * seg * i + _cloak_back(top, c) * 0.03 * i
				_co[i * CLOAK_COLS + c] = _cp[i * CLOAK_COLS + c]
		_have_cloak = true
		_cloak_prev = anchor
	_crows = rows
	var step := anchor - _cloak_prev
	_cloak_prev = anchor
	if step.length() > 2.5:
		_have_cloak = false
		return
	var carry := _carry(step)
	_shift(_cp, _co, CLOAK_COLS, carry)
	step -= carry
	var vel: Vector3 = f.get("vel", Vector3.ZERO)
	var billow := clampf((Vector2(vel.x, vel.z).length() - 3.0) / 10.0, 0.0, 1.0)
	# (v0.12.8 the pins, the widths and the robe's rings worked out once a frame, not per point and pass)
	var tops := PackedVector3Array()
	var widths := PackedFloat32Array()
	for c in CLOAK_COLS:
		tops.append(_cloak_top(top, c))
	for c in CLOAK_COLS - 1:
		widths.append(tops[c].distance_to(tops[c + 1]))
	var ring_c := PackedVector3Array()
	var ring_r := PackedFloat32Array()
	for i in rows:
		var ring: Array = rings[mini(i + int(f.pinned) - 1, rings.size() - 1)]
		ring_c.append(ring[0])
		ring_r.append(maxf(float(ring[2]), float(ring[3])) * 1.05)
	var floor_y := float(f.ground) + 0.03
	for c in CLOAK_COLS:
		_cp[c] = tops[c]
		_co[c] = _cp[c]
		var back := _cloak_back(top, c)
		for i in range(1, rows):
			var k := i * CLOAK_COLS + c
			var u := float(i) / float(rows - 1)
			var p: Vector3 = _cp[k]
			var v := step * 0.99 + ((p - _co[k]) - step) * 0.8   # a little lighter than the robe: it swings a bit more
			_co[k] = p
			var rest := tops[c] - up * seg * i + back * (0.05 + 0.02 * i)
			var acc := Vector3(0, -12.0, 0) + (rest - p) * lerpf(24.0, 11.0, u)
			acc += back * billow * (0.45 + 0.3 * sin(_t * 4.0 + c)) * u   # billows out a little behind when moving fast
			_cp[k] = p + v + acc * dt * dt
	var bk: Vector3 = f.get("back_n", Vector3.ZERO)   # v0.12.8 the cloak lies behind the back, the hips, legs and arms
	var near := _near(_cp, 0, hang_len * 0.5, [Tag.TORSO, Tag.HIPS, Tag.LEG, Tag.ARM, Tag.HEAD])   # (the quiver is worn over it)
	for it in 3:
		for c in CLOAK_COLS:
			for i in range(1, rows):
				var k := i * CLOAK_COLS + c
				var p := _hang(_cp[k - CLOAK_COLS], _cp[k], seg, up)
				if c < CLOAK_COLS - 1:   # keep the width
					var q: Vector3 = _cp[k + 1]
					var want := widths[c] * (1.0 + 0.15 * float(i) / rows)
					var e := q - p
					if e.length() > 1e-5:
						var corr := e * (0.5 * (e.length() - want) / e.length()) * 0.5
						p += corr
						_cp[k + 1] = q - corr
				# never inside the robe: out past the robe's ring at that height
				var rel := p - ring_c[i]
				var flat := rel - up * rel.dot(up)
				var fl := flat.length()
				if fl < ring_r[i] and fl > 1e-4:
					p += flat * ((ring_r[i] - fl) / fl)
				if it == 2:   # (v0.12.8 the legs too: it used to push straight out of them, so a stride could flip it)
					p = _collide(p, near, bk, bk)
				if p.y < floor_y:
					p.y = floor_y
				_cp[k] = p
	for k in range(CLOAK_COLS, n):   # no segment longer than its rest length
		var d: Vector3 = _cp[k] - _cp[k - CLOAK_COLS]
		if d.length() > seg:
			_cp[k] = _cp[k - CLOAK_COLS] + d * (seg / d.length())
		_cp[k] = _collide(_cp[k], near, bk, bk)
	_draw_sheet(_cloak_mesh, _cp, rows, CLOAK_COLS, f.get("cloak_col", GREY_CLOAK))


var _cloak_prev := Vector3.ZERO


## Where cloak column c is pinned: round the back of the shoulder ring, from one shoulder to the other.
func _cloak_top(top: Array, c: int) -> Vector3:
	var a := lerpf(PI * 0.08, PI * 0.92, float(c) / float(CLOAK_COLS - 1))   # +z is the back
	return (top[0] as Vector3) + (top[1] as Basis) * Vector3(cos(a) * float(top[2]) * 1.12, 0.03, sin(a) * float(top[3]) * 1.25)


func _cloak_back(top: Array, c: int) -> Vector3:
	var a := lerpf(PI * 0.08, PI * 0.92, float(c) / float(CLOAK_COLS - 1))
	return ((top[1] as Basis) * Vector3(cos(a) * 0.4, 0, sin(a))).normalized()


## An open sheet of cloth (the cloak, the tabard's panels): the front, and the back a cloth's thickness behind it,
## darker; indexed, sent in one call (v0.12.8).
func _draw_sheet(am: ArrayMesh, pts: PackedVector3Array, rows: int, cols: int, body: Color) -> void:
	var n := rows * cols
	var key := "sheet%d_%d" % [rows, cols]
	if not _index_cache.has(key):
		var ix := PackedInt32Array()
		for i in rows - 1:
			for c in cols - 1:
				var a := i * cols + c
				ix.append_array([a, a + 1, a + cols, a + 1, a + cols + 1, a + cols])
				ix.append_array([n + a, n + a + cols, n + a + 1, n + a + 1, n + a + cols, n + a + cols + 1])
		_index_cache[key] = ix
	var vx := PackedVector3Array()
	var nm := PackedVector3Array()
	var cl := PackedColorArray()
	vx.resize(2 * n)
	nm.resize(2 * n)
	cl.resize(2 * n)
	var back := body.darkened(0.3)
	for r in rows:
		var r0 := maxi(r - 1, 0) * cols
		var r1 := mini(r + 1, rows - 1) * cols
		for c in cols:
			var k := r * cols + c
			var p: Vector3 = pts[k]
			var side: Vector3 = pts[r * cols + mini(c + 1, cols - 1)] - pts[r * cols + maxi(c - 1, 0)]
			var dn: Vector3 = pts[r1 + c] - pts[r0 + c]
			var nn := dn.cross(side)
			nn = nn.normalized() if nn.length_squared() > 1e-12 else Vector3.UP
			vx[k] = p
			nm[k] = nn
			var col := body * (1.0 + _var[c % STRANDS] - 0.08 * float(r) / rows)
			if r == rows - 1:
				col = col.lerp(WEAR, 0.4)
			cl[k] = col
			vx[n + k] = p - nn * THICK
			nm[n + k] = -nn
			cl[n + k] = back
	_commit(am, vx, nm, cl, _index_cache[key])


## The wizard's loose rope belt at the waist ring, with a short hanging end.
func _rope(f: Dictionary) -> void:
	var ring: Array = f.rings[int(f.pinned) - 1]
	if _belt == null:
		_belt = MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.92
		tm.outer_radius = 1.0
		tm.rings = 24
		tm.ring_segments = 6
		_belt.mesh = tm
		_belt.material_override = _cloth_mat(ROPE)
		add_child(_belt)
	var b: Basis = ring[1]
	_belt.global_transform = Transform3D(b * Basis.from_scale(Vector3(float(ring[2]) * 1.06, 0.25, float(ring[3]) * 1.08)), (ring[0] as Vector3) + b.y * -0.02)


# ================================================================ the hat: tall, wide-brimmed, soft and crooked
func _build_hat(f: Dictionary) -> void:
	for s in _hat_segs:
		s.queue_free()
	_hat_segs = []
	for n in [_brim, _band]:
		if n:
			n.queue_free()
	var h := float(f.hat_h)
	var r0 := float(f.hat_r)
	_hat_mat = _cloth_mat(Color("66686c"))
	_hat_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for k in HAT_N - 1:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		var u0 := float(k) / float(HAT_N - 1)
		var u1 := float(k + 1) / float(HAT_N - 1)
		cm.bottom_radius = r0 * (1.0 - u0) * (1.0 - 0.15 * u0) + 0.004
		cm.top_radius = r0 * (1.0 - u1) * (1.0 - 0.15 * u1) + 0.004
		cm.height = 1.0
		cm.radial_segments = 12
		cm.rings = 1
		mi.mesh = cm
		mi.material_override = _hat_mat
		add_child(mi)
		_hat_segs.append(mi)
	_brim = MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = float(f.brim_r)
	bm.bottom_radius = float(f.brim_r) * 1.03
	bm.height = h * 0.025
	bm.radial_segments = 24
	_brim.mesh = bm
	_brim.material_override = _hat_mat
	add_child(_brim)
	_band = MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = r0 * 0.93
	dm.bottom_radius = r0 * 1.02
	dm.height = h * 0.07
	dm.radial_segments = 16
	_band.mesh = dm
	var bandm := _cloth_mat(Color("5e5a55"))
	bandm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_band.material_override = bandm
	add_child(_band)
	_hat_built_for = h


func _hat_rest(f: Dictionary, k: int) -> Vector3:
	var up: Vector3 = f.up
	var face: Vector3 = f.face
	var side := face.cross(up).normalized()
	var u := float(k) / float(HAT_N - 1)
	var h := float(f.hat_h)
	# a soft felt hat: rising straight, then the top third slumping back and a little to one side
	return (f.head_top as Vector3) + up * (h * u * (1.0 - 0.18 * u * u)) - face * (h * 0.26 * u * u * u) + side * (h * 0.07 * u * u)


func _hat(f: Dictionary, dt: float) -> void:
	if absf(_hat_built_for - float(f.hat_h)) > 1e-4:
		_build_hat(f)
	var base: Vector3 = f.head_top
	if not _have_hat or (_hat_p[0] as Vector3).distance_to(base) > 2.5:
		_hat_p = []
		_hat_o = []
		for k in HAT_N:
			_hat_p.append(_hat_rest(f, k))
			_hat_o.append(_hat_rest(f, k))
		_have_hat = true
	var seg := float(f.hat_h) / float(HAT_N - 1)
	var step := base - (_hat_p[0] as Vector3)
	var carry := _carry(step)
	_shift_arr(_hat_p, _hat_o, 1, carry)
	step -= carry
	_hat_p[0] = base
	_hat_o[0] = base
	for k in range(1, HAT_N):
		var p: Vector3 = _hat_p[k]
		var v := step * 0.98 + ((p - (_hat_o[k] as Vector3)) - step) * 0.85
		_hat_o[k] = p
		var stiff := lerpf(1100.0, 55.0, float(k) / float(HAT_N - 1))   # stiff crown, floppy tip
		_hat_p[k] = p + v + (((_hat_rest(f, k) - p) * stiff) + Vector3(0, -7.0, 0)) * dt * dt
	for it in 2:
		for k in range(1, HAT_N):
			var a: Vector3 = _hat_p[k - 1]
			var d: Vector3 = (_hat_p[k] as Vector3) - a
			if d.length() > 1e-5:
				_hat_p[k] = a + d.normalized() * seg
	for k in HAT_N - 1:
		_place(_hat_segs[k], _hat_p[k], _hat_p[k + 1])
	var lean := ((_hat_p[1] as Vector3) - base).normalized()
	var bn := ((f.up as Vector3) * 2.0 + lean).normalized()
	_brim.global_transform = Transform3D(_basis_y(bn), base)
	_band.global_transform = Transform3D(_basis_y(lean), base + lean * float(f.hat_h) * 0.04)
	# our own hat goes see-through, so it never hides what the crosshair is on
	var a := 0.5 if bool(f.get("own", false)) else 1.0
	_hat_mat.albedo_color.a = a
	(_band.material_override as StandardMaterial3D).albedo_color.a = a


## A unit-height part from a to b (its y along the line, stretched to fit).
static func _place(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	mi.global_transform = _xf(a, b)


static func _xf(a: Vector3, b: Vector3) -> Transform3D:
	var d := b - a
	var l := maxf(d.length(), 0.001)
	var bs := _basis_y(d / l)
	return Transform3D(Basis(bs.x, bs.y * l, bs.z), (a + b) * 0.5)


static func _basis_y(y: Vector3) -> Basis:
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


# ================================================================ the deep cowl hood (the wand's)
func _build_hood(f: Dictionary) -> void:
	if _hood:
		_hood.queue_free()
	for s in _tail_segs:
		s.queue_free()
	_tail_segs = []
	var r := float(f.head_r)
	var mat := _cloth_mat(DARK)
	_hood = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r * 1.32
	sm.height = r * 1.32
	sm.is_hemisphere = true
	sm.radial_segments = 22
	sm.rings = 10
	_hood.mesh = sm
	_hood.material_override = mat
	add_child(_hood)
	for k in TAIL_N - 1:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.bottom_radius = r * 0.45 * (1.0 - float(k) / float(TAIL_N - 1)) + 0.004
		cm.top_radius = r * 0.45 * (1.0 - float(k + 1) / float(TAIL_N - 1)) + 0.004
		cm.height = 1.0
		cm.radial_segments = 8
		mi.mesh = cm
		mi.material_override = mat
		add_child(mi)
		_tail_segs.append(mi)
	_hood_built_for = r


func _hood_up(f: Dictionary, dt: float) -> void:
	var r := float(f.head_r)
	if absf(_hood_built_for - r) > 1e-4:
		_build_hood(f)
	var up: Vector3 = f.up
	var face: Vector3 = f.face
	# the cowl: a deep dome over the back and top of the head whose open rim sits in front of the face, framing it
	# and putting it in shadow; it reaches down onto the shoulders
	var back := (-face * 0.94 + up * 0.15).normalized()
	var c: Vector3 = (f.head_c as Vector3) + up * r * 0.12 + face * r * 0.3
	var hx := up.cross(back).normalized()
	var hb := Basis(hx, back, hx.cross(back).normalized())
	_hood.global_transform = Transform3D(hb * Basis.from_scale(Vector3(1.0, 1.45, 1.22)), c)
	# a soft point at the back, swinging a little
	var start := c + back * r * 1.6 - up * r * 0.1
	var seg := r * 0.35
	if not _have_tail or (_tail_p[0] as Vector3).distance_to(start) > 2.5:
		_tail_p = []
		_tail_o = []
		for k in TAIL_N:
			var q := start + back * seg * 0.4 * k - up * seg * 0.8 * k
			_tail_p.append(q)
			_tail_o.append(q)
		_have_tail = true
	var step := start - (_tail_p[0] as Vector3)
	var carry := _carry(step)
	_shift_arr(_tail_p, _tail_o, 1, carry)
	step -= carry
	_tail_p[0] = start
	_tail_o[0] = start
	for k in range(1, TAIL_N):
		var p: Vector3 = _tail_p[k]
		var v := step * 0.98 + ((p - (_tail_o[k] as Vector3)) - step) * 0.85
		_tail_o[k] = p
		var rest := start + back * seg * 0.4 * k - up * seg * 0.8 * k
		_tail_p[k] = p + v + ((rest - p) * 60.0 + Vector3(0, -9.0, 0)) * dt * dt
	var near := _near(_tail_p, 0, seg * TAIL_N, [Tag.HEAD, Tag.TORSO, Tag.GEAR])
	var hbk: Vector3 = f.get("head_back", -face)
	for it in 2:
		for k in range(1, TAIL_N):
			var a: Vector3 = _tail_p[k - 1]
			var d: Vector3 = (_tail_p[k] as Vector3) - a
			if d.length() > 1e-5:
				_tail_p[k] = a + d.normalized() * seg
			_tail_p[k] = _collide(_tail_p[k], near, hbk, hbk)
	for k in TAIL_N - 1:
		_place(_tail_segs[k], _tail_p[k], _tail_p[k + 1])


# ================================================================ v0.9.0: tabards, tails, the satchel
var _sheets := {}     # id -> { mesh, have, p, o }: hanging panels (the knight's tabard)
var _chains := {}     # id -> { p, o, segs }: short swinging tails (sash ends, headband tails, the bandana's knot)
var _satchel: MeshInstance3D
var _sat_off := Vector3.ZERO
var _sat_v := Vector3.ZERO
const SHEET_COLS := 5
const SHEET_ROWS := 7


## A cloth panel (the knight's tabard, front or back) pinned along its top edge from `left` to `right` at the chest
## and (v0.12.8) belted at the waist (`belt`: [left, right]): down to the belt it lies on the body, following the chest
## and the hips as they lean and twist (it used to hang loose from the chest, so a swing's twist wound it diagonally
## across the body and a lean swung it into the hips); below the belt it is heavy cloth hanging `skirt` long to the
## knees: damped, its rows kept their length (it never stretches, on a jump either), springing back toward hanging
## straight, never more than ~45 degrees out, and kept on its own side of the body, the legs and the arms.
const BELT_ROW := 2
func _sheet(id: String, left: Vector3, right: Vector3, belt: Array, skirt: float, f: Dictionary, dt: float, col: Color) -> void:
	var sh: Dictionary = _sheets[id]
	var up: Vector3 = f.get("body_up", Vector3.UP)
	var free_rows := SHEET_ROWS - 1 - BELT_ROW
	var seg := skirt / float(free_rows)
	var n := SHEET_ROWS * SHEET_COLS
	var front := id == "tabard_front"
	var side: Vector3 = f.get("front_n" if front else "back_n", Vector3.ZERO)
	var arm_side := -side if front else side
	var bl: Vector3 = belt[0]
	var br: Vector3 = belt[1]
	var first := (BELT_ROW + 1) * SHEET_COLS   # the first free point
	if not sh.have or (sh.p[0] as Vector3).distance_to(left) > 2.5:
		var p := PackedVector3Array()
		p.resize(n)
		for i in SHEET_ROWS:
			for c in SHEET_COLS:
				var u := float(c) / (SHEET_COLS - 1)
				p[i * SHEET_COLS + c] = bl.lerp(br, u) - up * seg * (i - BELT_ROW)
		sh.p = p
		sh.o = p.duplicate()
		sh.have = true
	sh.seg = seg
	var P: PackedVector3Array = sh.p
	var O: PackedVector3Array = sh.o
	var near := _near(P, 0, skirt + 0.3)
	# the part on the body: the chest's edge, the belt, and a row between them lying on the body
	for c in SHEET_COLS:
		var u := float(c) / (SHEET_COLS - 1)
		var top := left.lerp(right, u)
		var bt := bl.lerp(br, u)
		for i in BELT_ROW + 1:
			var q := top.lerp(bt, float(i) / BELT_ROW)
			if i > 0:
				q = _collide(q, near, side, Vector3.ZERO)
			P[i * SHEET_COLS + c] = q
			O[i * SHEET_COLS + c] = q
	var mid := (bl + br) * 0.5
	var step := mid - (sh.get("belt_prev", mid) as Vector3)
	sh.belt_prev = mid
	var carry := _carry(step, 4.5)   # a heavy panel: it trails less than light cloth
	_shift(P, O, first, carry)
	step -= carry
	for c in SHEET_COLS:
		var bt := bl.lerp(br, float(c) / (SHEET_COLS - 1))
		for i in range(BELT_ROW + 1, SHEET_ROWS):
			var k := i * SHEET_COLS + c
			var q: Vector3 = P[k]
			var v := step * 0.99 + ((q - O[k]) - step) * 0.74
			O[k] = q
			var rest := bt - up * seg * (i - BELT_ROW)
			P[k] = q + v + ((rest - q) * 34.0 + Vector3(0, -12.0, 0)) * dt * dt
	var w := bl.distance_to(br) / (SHEET_COLS - 1)
	for it in 3:
		for c in SHEET_COLS:
			for i in range(BELT_ROW + 1, SHEET_ROWS):
				var k := i * SHEET_COLS + c
				var q := _hang(P[k - SHEET_COLS], P[k], seg, up, 0.72)
				if c < SHEET_COLS - 1:
					var e: Vector3 = P[k + 1] - q
					if e.length() > 1e-5:
						var corr := e * (0.5 * (e.length() - w) / e.length()) * 0.5
						q += corr
						P[k + 1] = (P[k + 1] as Vector3) - corr
				P[k] = _collide(q, near, side, arm_side) if it == 2 else q
	for k in range(first, n):   # last: no link longer than its length, then out of the body once more
		var d: Vector3 = P[k] - P[k - SHEET_COLS]
		if d.length() > seg:
			P[k] = P[k - SHEET_COLS] + d * (seg / d.length())
		P[k] = _collide(P[k], near, side, arm_side)
	sh.p = P
	sh.o = O
	_draw_sheet(sh.mesh, P, SHEET_ROWS, SHEET_COLS, col)


## A short tail (a sash end, a headband tail): a chain of `n` points from `start`, resting along `dir`, each
## springing back toward its place (looser toward the tip), its links kept their length. Drawn as tapering segments.
func _chain(id: String, start: Vector3, dir: Vector3, n: int, seg: float, r: float, col: Color, dt: float, f: Dictionary, side := Vector3.ZERO) -> void:
	if not _chains.has(id):
		var segs := []
		var mat := _cloth_mat(col)
		for k in n:
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.bottom_radius = r * (1.0 - 0.5 * float(k) / n) + 0.003
			cm.top_radius = r * (1.0 - 0.5 * float(k + 1) / n) + 0.003
			cm.height = 1.0
			cm.radial_segments = 6
			cm.rings = 1
			mi.mesh = cm
			mi.material_override = mat
			add_child(mi)
			segs.append(mi)
		_chains[id] = { "p": [], "o": [], "segs": segs, "have": false }
	var ch: Dictionary = _chains[id]
	var d := dir.normalized()
	if not ch.have or (ch.p[0] as Vector3).distance_to(start) > 2.5:
		ch.p = []
		ch.o = []
		for k in n + 1:
			ch.p.append(start + d * seg * k)
			ch.o.append(start + d * seg * k)
		ch.have = true
	ch.seg = seg
	var step := start - (ch.p[0] as Vector3)
	var carry := _carry(step)
	_shift_arr(ch.p, ch.o, 1, carry)
	step -= carry
	ch.p[0] = start
	ch.o[0] = start
	for k in range(1, n + 1):
		var q: Vector3 = ch.p[k]
		var v := step * 0.98 + ((q - (ch.o[k] as Vector3)) - step) * 0.86
		ch.o[k] = q
		var stiff := lerpf(140.0, 40.0, float(k) / n)
		ch.p[k] = q + v + (((start + d * seg * k) - q) * stiff + Vector3(0, -9.0, 0)) * dt * dt
	var near := _near(ch.p, 0, seg * n)
	for it in 3:   # v0.12.8 each link its length, then out of the body (to `side` of it: tails behind the head)
		for k in range(1, n + 1):
			var a: Vector3 = ch.p[k - 1]
			var e: Vector3 = (ch.p[k] as Vector3) - a
			if e.length() > 1e-5:
				ch.p[k] = a + e.normalized() * seg
			if it == 2:
				ch.p[k] = _collide(ch.p[k], near, side, side)
	for k in n:
		_place(ch.segs[k], ch.p[k], ch.p[k + 1])


## Every simulated (free) cloth point now, as [position, piece name] (tests and the cloth pictures check them against
## the body).
func cloth_points() -> Array:
	var out := []
	if not visible:
		return out
	if _have_robe:
		for k in range(STRANDS * _pinned_rows, _p.size()):
			out.append([_p[k], "robe"])
	if _have_cloak:
		for k in range(CLOAK_COLS, _cp.size()):
			out.append([_cp[k], "cloak"])
	for id in _sheets:
		var sh: Dictionary = _sheets[id]
		if sh.have:
			for k in range(SHEET_COLS, (sh.p as PackedVector3Array).size()):
				out.append([sh.p[k], id])
	for id in _chains:
		var ch: Dictionary = _chains[id]
		if ch.have:
			for k in range(1, (ch.p as Array).size()):
				out.append([ch.p[k], id])
	if _have_tail:
		for k in range(1, _tail_p.size()):
			out.append([_tail_p[k], "hood_tail"])
	return out


## Where each simulated point is pinned (its anchor), for the reach check: [point, its anchor, the most it may be
## from it]. The robe's and kilt's strands hang from the waist ring, the cloak's columns and the panels' from their top
## edge, the tails from their knot.
func cloth_reach() -> Array:
	var out := []
	if not visible:
		return out
	if _have_robe:
		for k in range(STRANDS * _pinned_rows, _p.size()):
			var j := k % STRANDS
			var top: Vector3 = _p[(_pinned_rows - 1) * STRANDS + j]
			out.append([_p[k], top, _robe_len[k / STRANDS], "robe"])
	if _have_cloak:
		for k in range(CLOAK_COLS, _cp.size()):
			out.append([_cp[k], _cp[k % CLOAK_COLS], _cloak_seg * float(k / CLOAK_COLS)])
	for id in _sheets:
		var sh: Dictionary = _sheets[id]
		if sh.have:
			for k in range((BELT_ROW + 1) * SHEET_COLS, (sh.p as PackedVector3Array).size()):
				out.append([sh.p[k], sh.p[BELT_ROW * SHEET_COLS + k % SHEET_COLS], float(sh.seg) * float(k / SHEET_COLS - BELT_ROW)])
	for id in _chains:
		var ch: Dictionary = _chains[id]
		if ch.have:
			for k in range(1, (ch.p as Array).size()):
				out.append([ch.p[k], ch.p[0], float(ch.seg) * k])
	return out


## The scout's satchel: a leather bag on the hip that bounces on a spring as he moves.
func _satchel_bounce(f: Dictionary, dt: float) -> void:
	if _satchel == null:
		_satchel = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.16, 0.14, 0.07)
		_satchel.mesh = bm
		_satchel.material_override = _cloth_mat(Color("7a5236"))
		add_child(_satchel)
	var vel: Vector3 = f.get("vel", Vector3.ZERO)
	var bob := Vector3(0, -absf(sin(_t * 9.0)) * 0.03 * clampf(Vector2(vel.x, vel.z).length() / 6.0, 0.0, 1.0), 0)
	_sat_v += ((bob - _sat_off) * 160.0 - _sat_v * 9.0) * dt
	_sat_v += -Vector3(vel.x, 0, vel.z) * 0.0   # (the body's motion is already in its anchor)
	_sat_off += _sat_v * dt
	_sat_off = _sat_off.limit_length(0.06)
	_satchel.global_transform = Transform3D(f.satchel_basis, (f.satchel_at as Vector3) + _sat_off)

