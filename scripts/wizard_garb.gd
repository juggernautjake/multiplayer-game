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
var _robe_mesh: ImmediateMesh
var _var: PackedFloat32Array        # per-strand shade variation (folds, fading)
# cloak
var _cp := PackedVector3Array()
var _co := PackedVector3Array()
var _crows := 0
var _have_cloak := false
var _cloak_mesh: ImmediateMesh
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


func _cloth_node() -> ImmediateMesh:
	var im := ImmediateMesh.new()
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
func update(delta: float, f: Dictionary) -> void:
	if kind == Kind.NONE:
		return
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
				_sheet(id, pins[0], pins[1], float(f.tabard_len), f, dt, f.accent)
		Kind.BRAWLER:     # the sash's ends and the headband's tails
			_chain("sash_a", f.sash_at, f.sash_dir, 4, 0.07, 0.035, f.accent, dt, f)
			_chain("sash_b", (f.sash_at as Vector3) + (f.sash_side as Vector3) * 0.05, f.sash_dir, 3, 0.07, 0.03, f.accent, dt, f)
			_chain("band_a", f.band_at, f.band_dir, 3, 0.06, 0.02, f.accent, dt, f)
			_chain("band_b", (f.band_at as Vector3) + (f.band_side as Vector3) * 0.04, f.band_dir, 3, 0.055, 0.018, f.accent, dt, f)
		Kind.SCOUT:       # the bandana's knot tails, and the satchel bouncing on the hip
			_chain("knot_a", f.band_at, f.band_dir, 2, 0.06, 0.02, f.accent, dt, f)
			_chain("knot_b", (f.band_at as Vector3) + (f.band_side as Vector3) * 0.04, f.band_dir, 2, 0.055, 0.018, f.accent, dt, f)
			_satchel_bounce(f, dt)


# ================================================================ v0.12: cloth keeps up with fast moves
## Cloth may lag the body by what a sprint would give it, never more: on a dash, a teleport, a frame hitch or a net
## correction the body moves far further than that in one frame, and the cloth used to be left behind and then whip
## back. `_carry(step)` is the part of the body's step to move every free point (and its previous position) along by
## before integrating, so only a run's worth of lag is left to swing.
var lag_speed := 7.0   # m/s of body motion the cloth is allowed to trail
var _frame_dt := 1.0 / 60.0


func _carry(step: Vector3) -> Vector3:
	var keep := lag_speed * _frame_dt
	var l := step.length()
	return step * ((l - keep) / l) if l > keep else Vector3.ZERO


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
	var up := ((rings[pinned - 1] as Array)[1] as Basis).y.normalized()
	var vel: Vector3 = f.get("vel", Vector3.ZERO)
	var flutter := clampf((Vector2(vel.x, vel.z).length() - 5.0) / 12.0, 0.0, 1.0) * 0.35   # a little billow, fast only
	var dt2 := dt * dt
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
	var ground := float(f.get("ground", -100.0))
	for it in 4:
		for j in STRANDS:
			for i in range(pinned, rows):
				var k := i * STRANDS + j
				var above: Vector3 = _p[k - STRANDS]
				var want := ((rings[i] as Array)[0] as Vector3).distance_to((rings[i - 1] as Array)[0]) * 1.01
				var p := _hang(above, _p[k], want, up)
				var jn := (j + 1) % STRANDS
				var q: Vector3 = _p[i * STRANDS + jn]
				var hw := _ring_pt(rings[i], TAU * j / STRANDS).distance_to(_ring_pt(rings[i], TAU * jn / STRANDS))
				var e := q - p
				var el := e.length()
				if el > 1e-5:
					var corr := e * (0.5 * (el - hw) / el) * 0.6
					p += corr
					_p[i * STRANDS + jn] = q - corr
				for c in cols:
					p = _push_from_leg(p, c[0], c[1], float(c[2]), anchor)
				for c in arm_cols:
					p = _push_inward(p, c[0], c[1], float(c[2]), anchor)
				if p.y < ground + 0.02:
					p.y = ground + 0.02
				_p[k] = p
	# last, no segment longer than its rest length (the side constraints and colliders can leave one stretched)
	for i in range(pinned, rows):
		var want := ((rings[i] as Array)[0] as Vector3).distance_to((rings[i - 1] as Array)[0]) * 1.01
		for j in STRANDS:
			var k := i * STRANDS + j
			var d: Vector3 = _p[k] - _p[k - STRANDS]
			if d.length() > want:
				_p[k] = _p[k - STRANDS] + d * (want / d.length())
	_draw_loop(_robe_mesh, _p, rows, pinned, f.get("robe_col", robe_color(kind)), true)


## Keep `p` `want` from `above`, no more than ~60 degrees out from hanging straight down.
static func _hang(above: Vector3, p: Vector3, want: float, up: Vector3) -> Vector3:
	var d := p - above
	if d.length() < 1e-5:
		return above - up * want
	var down := -up
	var dd := maxf(d.normalized().dot(down) * want, want * 0.5)   # the drop, for a segment exactly `want` long
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
## and wear at the hem.
func _draw_loop(im: ImmediateMesh, pts: PackedVector3Array, rows: int, pinned: int, body: Color, wear: bool) -> void:
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rows - 1:
		for j in STRANDS:
			var jn := (j + 1) % STRANDS
			for v in [[i, j], [i, jn], [i + 1, j], [i, jn], [i + 1, jn], [i + 1, j]]:
				var r: int = v[0]
				var s: int = v[1]
				var p: Vector3 = pts[r * STRANDS + s]
				var side: Vector3 = pts[r * STRANDS + (s + 1) % STRANDS] - pts[r * STRANDS + (s + STRANDS - 1) % STRANDS]
				var dn: Vector3 = pts[mini(r + 1, rows - 1) * STRANDS + s] - pts[maxi(r - 1, 0) * STRANDS + s]
				var n := dn.cross(side)
				im.surface_set_normal(n.normalized() if n.length() > 1e-6 else Vector3.UP)
				var u := float(r) / float(rows - 1)
				var c := body * (1.0 + _var[s] - 0.1 * u)
				if wear and r == rows - 1:
					c = c.lerp(WEAR, 0.45 + _var[s] * 3.0)
				im.surface_set_color(c)
				im.surface_add_vertex(p)
	# v0.8.1: the cloth has thickness: an inner layer (the lining, darker) a little inside the outer one, and a band
	# joining them round the hem, so the edge shows as cloth, not a paper-thin shell
	var inner := PackedVector3Array()
	inner.resize(pts.size())
	for r in rows:
		var mid := Vector3.ZERO
		for j in STRANDS:
			mid += pts[r * STRANDS + j]
		mid /= float(STRANDS)
		for j in STRANDS:
			var p: Vector3 = pts[r * STRANDS + j]
			var inward := Vector3(mid.x - p.x, 0, mid.z - p.z)
			inner[r * STRANDS + j] = p + (inward.normalized() * THICK if inward.length() > 1e-4 else Vector3.ZERO)
	var lining := body.darkened(0.35)
	for i in range(pinned, rows - 1):
		for j in STRANDS:
			var jn := (j + 1) % STRANDS
			for v in [[i, j], [i + 1, j], [i, jn], [i, jn], [i + 1, j], [i + 1, jn]]:
				var p: Vector3 = inner[int(v[0]) * STRANDS + int(v[1])]
				var o: Vector3 = pts[int(v[0]) * STRANDS + int(v[1])]
				im.surface_set_normal((p - o).normalized() if p.distance_to(o) > 1e-5 else Vector3.UP)
				im.surface_set_color(lining)
				im.surface_add_vertex(p)
	var hem := rows - 1
	for j in STRANDS:
		var jn := (j + 1) % STRANDS
		for q in [[pts, j], [inner, j], [pts, jn], [pts, jn], [inner, j], [inner, jn]]:
			var arr: PackedVector3Array = q[0]
			im.surface_set_normal(Vector3.DOWN)
			im.surface_set_color(body.lerp(WEAR, 0.5) if wear else body.darkened(0.2))
			im.surface_add_vertex(arr[hem * STRANDS + int(q[1])])
	im.surface_end()


# ================================================================ the cloak (the wizard's)
func _cloak(f: Dictionary, dt: float) -> void:
	var rings: Array = f.rings
	var top: Array = rings[0]
	var rows := 6
	# a fixed length (from the shoulders to near the feet), never down to the ground: mid-jump it used to stretch
	var hang_len := ((top[0] as Vector3).y - float(f.get("feet_y", f.ground))) * 0.86
	var seg := hang_len / float(rows - 1)
	var basis: Basis = top[1]
	var up := basis.y.normalized()
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
	for c in CLOAK_COLS:
		_cp[c] = _cloak_top(top, c)
		_co[c] = _cp[c]
		var back := _cloak_back(top, c)
		for i in range(1, rows):
			var k := i * CLOAK_COLS + c
			var u := float(i) / float(rows - 1)
			var p: Vector3 = _cp[k]
			var v := step * 0.99 + ((p - _co[k]) - step) * 0.8   # a little lighter than the robe: it swings a bit more
			_co[k] = p
			var rest := _cloak_top(top, c) - up * seg * i + back * (0.05 + 0.02 * i)
			var acc := Vector3(0, -12.0, 0) + (rest - p) * lerpf(24.0, 11.0, u)
			acc += back * billow * (0.45 + 0.3 * sin(_t * 4.0 + c)) * u   # billows out a little behind when moving fast
			_cp[k] = p + v + acc * dt * dt
	var cols: Array = f.get("colliders", [])
	for it in 3:
		for c in CLOAK_COLS:
			for i in range(1, rows):
				var k := i * CLOAK_COLS + c
				var p := _hang(_cp[k - CLOAK_COLS], _cp[k], seg, up)
				if c < CLOAK_COLS - 1:   # keep the width
					var q: Vector3 = _cp[k + 1]
					var want := _cloak_top(top, c).distance_to(_cloak_top(top, c + 1)) * (1.0 + 0.15 * float(i) / rows)
					var e := q - p
					if e.length() > 1e-5:
						var corr := e * (0.5 * (e.length() - want) / e.length()) * 0.5
						p += corr
						_cp[k + 1] = q - corr
				# never inside the robe: out past the robe's ring at that height
				var ring: Array = rings[mini(i + int(f.pinned) - 1, rings.size() - 1)]
				var rel := p - (ring[0] as Vector3)
				var flat := rel - up * rel.dot(up)
				var min_r := maxf(float(ring[2]), float(ring[3])) * 1.05
				if flat.length() < min_r and flat.length() > 1e-4:
					p += flat.normalized() * (min_r - flat.length())
				for cc in cols:
					p = _push_out(p, cc[0], cc[1], float(cc[2]) + 0.04)
				if p.y < float(f.ground) + 0.03:
					p.y = float(f.ground) + 0.03
				_cp[k] = p
	for k in range(CLOAK_COLS, n):   # no segment longer than its rest length
		var d: Vector3 = _cp[k] - _cp[k - CLOAK_COLS]
		if d.length() > seg:
			_cp[k] = _cp[k - CLOAK_COLS] + d * (seg / d.length())
	_draw_sheet(_cloak_mesh, _cp, rows, CLOAK_COLS, f.get("cloak_col", GREY_CLOAK))


var _cloak_prev := Vector3.ZERO


## Where cloak column c is pinned: round the back of the shoulder ring, from one shoulder to the other.
func _cloak_top(top: Array, c: int) -> Vector3:
	var a := lerpf(PI * 0.08, PI * 0.92, float(c) / float(CLOAK_COLS - 1))   # +z is the back
	return (top[0] as Vector3) + (top[1] as Basis) * Vector3(cos(a) * float(top[2]) * 1.12, 0.03, sin(a) * float(top[3]) * 1.25)


func _cloak_back(top: Array, c: int) -> Vector3:
	var a := lerpf(PI * 0.08, PI * 0.92, float(c) / float(CLOAK_COLS - 1))
	return ((top[1] as Basis) * Vector3(cos(a) * 0.4, 0, sin(a))).normalized()


func _draw_sheet(im: ImmediateMesh, pts: PackedVector3Array, rows: int, cols: int, body: Color) -> void:
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rows - 1:
		for col in cols - 1:
			for v in [[i, col], [i, col + 1], [i + 1, col], [i, col + 1], [i + 1, col + 1], [i + 1, col]]:
				var r: int = v[0]
				var s: int = v[1]
				var p: Vector3 = pts[r * cols + s]
				var side: Vector3 = pts[r * cols + mini(s + 1, cols - 1)] - pts[r * cols + maxi(s - 1, 0)]
				var dn: Vector3 = pts[mini(r + 1, rows - 1) * cols + s] - pts[maxi(r - 1, 0) * cols + s]
				var n := dn.cross(side)
				im.surface_set_normal(n.normalized() if n.length() > 1e-6 else Vector3.UP)
				var c := body * (1.0 + _var[s % STRANDS] - 0.08 * float(r) / rows)
				if r == rows - 1:
					c = c.lerp(WEAR, 0.4)
				im.surface_set_color(c)
				im.surface_add_vertex(p)
	# the back of the cloak: the same sheet a cloth's thickness behind, darker
	for i in rows - 1:
		for col in cols - 1:
			for v in [[i, col], [i + 1, col], [i, col + 1], [i, col + 1], [i + 1, col], [i + 1, col + 1]]:
				var r: int = v[0]
				var sc: int = v[1]
				var p: Vector3 = pts[r * cols + sc]
				var side: Vector3 = pts[r * cols + mini(sc + 1, cols - 1)] - pts[r * cols + maxi(sc - 1, 0)]
				var dn: Vector3 = pts[mini(r + 1, rows - 1) * cols + sc] - pts[maxi(r - 1, 0) * cols + sc]
				var n := dn.cross(side).normalized()
				im.surface_set_normal(-n)
				im.surface_set_color(body.darkened(0.3))
				im.surface_add_vertex(p - n * THICK)
	im.surface_end()


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
	for it in 2:
		for k in range(1, TAIL_N):
			var a: Vector3 = _tail_p[k - 1]
			var d: Vector3 = (_tail_p[k] as Vector3) - a
			if d.length() > 1e-5:
				_tail_p[k] = a + d.normalized() * seg
	for k in TAIL_N - 1:
		_place(_tail_segs[k], _tail_p[k], _tail_p[k + 1])


# ================================================================ v0.9.0: tabards, tails, the satchel
var _sheets := {}     # id -> { mesh, have, p, o }: hanging panels (the knight's tabard)
var _chains := {}     # id -> { p, o, segs }: short swinging tails (sash ends, headband tails, the bandana's knot)
var _satchel: MeshInstance3D
var _sat_off := Vector3.ZERO
var _sat_v := Vector3.ZERO
const SHEET_COLS := 5
const SHEET_ROWS := 5


## A cloth panel pinned along its top edge from `left` to `right`, hanging `length` down: heavy, damped, its rows
## kept their length (it never stretches, on a jump either), springing back toward hanging straight, pushed in front
## of striding legs.
func _sheet(id: String, left: Vector3, right: Vector3, length: float, f: Dictionary, dt: float, col: Color) -> void:
	var sh: Dictionary = _sheets[id]
	var up := (f.up as Vector3) if f.has("up") else Vector3.UP
	up = Vector3.UP
	var seg := length / float(SHEET_ROWS - 1)
	var n := SHEET_ROWS * SHEET_COLS
	if not sh.have or (sh.p[0] as Vector3).distance_to(left) > 2.5:
		var p := PackedVector3Array()
		p.resize(n)
		for i in SHEET_ROWS:
			for c in SHEET_COLS:
				p[i * SHEET_COLS + c] = left.lerp(right, float(c) / (SHEET_COLS - 1)) - up * seg * i
		sh.p = p
		sh.o = p.duplicate()
		sh.have = true
	var P: PackedVector3Array = sh.p
	var O: PackedVector3Array = sh.o
	var step := left - P[0]
	var carry := _carry(step)
	_shift(P, O, SHEET_COLS, carry)
	step -= carry
	for c in SHEET_COLS:
		var top := left.lerp(right, float(c) / (SHEET_COLS - 1))
		P[c] = top
		O[c] = top
		for i in range(1, SHEET_ROWS):
			var k := i * SHEET_COLS + c
			var q: Vector3 = P[k]
			var v := step * 0.99 + ((q - O[k]) - step) * 0.8
			O[k] = q
			var rest := top - up * seg * i
			P[k] = q + v + ((rest - q) * 20.0 + Vector3(0, -12.0, 0)) * dt * dt
	var cols: Array = f.get("colliders", [])
	var anchor: Vector3 = (left + right) * 0.5
	for it in 3:
		for c in SHEET_COLS:
			for i in range(1, SHEET_ROWS):
				var k := i * SHEET_COLS + c
				var q := _hang(P[k - SHEET_COLS], P[k], seg, up)
				if c < SHEET_COLS - 1:
					var w := left.distance_to(right) / (SHEET_COLS - 1)
					var e: Vector3 = P[k + 1] - q
					if e.length() > 1e-5:
						var corr := e * (0.5 * (e.length() - w) / e.length()) * 0.5
						q += corr
						P[k + 1] = (P[k + 1] as Vector3) - corr
				for cc in cols:
					q = _push_from_leg(q, cc[0], cc[1], float(cc[2]) + 0.02, anchor - up * 0.3)
				P[k] = q
	sh.p = P
	sh.o = O
	_draw_sheet(sh.mesh, P, SHEET_ROWS, SHEET_COLS, col)


## A short tail (a sash end, a headband tail): a chain of `n` points from `start`, resting along `dir`, each
## springing back toward its place (looser toward the tip), its links kept their length. Drawn as tapering segments.
func _chain(id: String, start: Vector3, dir: Vector3, n: int, seg: float, r: float, col: Color, dt: float, f: Dictionary) -> void:
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
	for it in 2:
		for k in range(1, n + 1):
			var a: Vector3 = ch.p[k - 1]
			var e: Vector3 = (ch.p[k] as Vector3) - a
			if e.length() > 1e-5:
				ch.p[k] = a + e.normalized() * seg
	for k in n:
		_place(ch.segs[k], ch.p[k], ch.p[k + 1])


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

