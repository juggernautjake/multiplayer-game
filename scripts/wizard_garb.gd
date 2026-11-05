## Wizard garb (Jacob 2026-11-05), purely visual and worked out on every client from the player's state (no network
## traffic): whoever carries the Wizard staff wears a long grey robe and a tall pointed hat; whoever carries the Magic
## wand wears a dark hooded robe; someone with both wears the grey robe and hat with the dark hood dropped round the
## neck. It goes when the item goes (the staff and wand go back to the tower and the vault when their holder leaves).
##
## The cloth is simulated (Verlet particles, a few constraint passes a frame, in world space so it trails behind):
##   robe:  20 strands x 6 rows hanging from the waist ring. The top row is pinned to the body (it turns, leans and
##          bobs with it); the rest swing under gravity, keep their length, spring gently back toward the robe's shape,
##          are pushed out of the legs (the 3D figure's thighs and shins) and the body, and stay above the ground. Moving
##          makes them trail; running and dashing make the hem flutter; stopping makes it swing past and settle;
##   hat:   a chain of 5 points from the brim to the tip, each springing back toward its place (stiff at the base, loose
##          at the tip), so the tip lags, bobs with every step and whips on a dash; the brim tilts after it;
##   hood:  a dome over the back of the head with a rim round the face and a pointed tail hanging down the back that
##          swings like the hat's tip.
## Avatars call update() every frame with where the body is (FigureAvatar and Avatar each work that out their own way).
class_name WizardGarb
extends Node3D

enum Kind { NONE, WIZARD, SHADOW, BOTH }

const GREY := Color("8d9098")
const GREY_TRIM := Color("c9d2de")
const DARK := Color("231c2c")
const DARK_TRIM := Color("5a3f7a")
const HAT_BAND := Color("4a5a78")
const STRANDS := 20
const ROWS := 6
const HAT_N := 5
const TAIL_N := 4


## Which garb this player wears, from what they carry.
static func kind_for(st: Sim.PlayerState) -> int:
	if st == null:
		return Kind.NONE
	var staff := (st.owned >> Weapons.STAFF) & 1 == 1
	var wand := (st.owned >> Weapons.WAND) & 1 == 1
	if staff and wand:
		return Kind.BOTH
	if staff:
		return Kind.WIZARD
	if wand:
		return Kind.SHADOW
	return Kind.NONE


## The robe's colour for a kind (the figure recolours its tunic, sleeves and trousers to match).
static func robe_color(k: int) -> Color:
	return DARK if k == Kind.SHADOW else GREY


var kind := Kind.NONE
var _t := 0.0
# robe
var _p := PackedVector3Array()
var _o := PackedVector3Array()
var _have_robe := false
var _last_hip := Vector3.ZERO
var _robe_mi: MeshInstance3D
var _robe_mesh: ImmediateMesh
var _robe_mat: StandardMaterial3D
# hat
var _hat_p: Array = []
var _hat_o: Array = []
var _have_hat := false
var _hat_segs: Array = []
var _brim: MeshInstance3D
var _band: MeshInstance3D
var _hat_built_for := -1.0
# hood
var _hood: MeshInstance3D
var _rim: MeshInstance3D
var _tail_p: Array = []
var _tail_o: Array = []
var _have_tail := false
var _tail_segs: Array = []
var _cowl: MeshInstance3D
var _hood_built_for := -1.0


func _init() -> void:
	top_level = true   # everything here is placed in world space


func _ready() -> void:
	global_transform = Transform3D.IDENTITY


func set_kind(k: int) -> void:
	if k == kind:
		return
	kind = k
	for c in get_children():
		c.queue_free()
	_robe_mi = null
	_brim = null
	_band = null
	_hood = null
	_rim = null
	_cowl = null
	_hat_segs = []
	_tail_segs = []
	_have_robe = false
	_have_hat = false
	_have_tail = false
	_hat_built_for = -1.0
	_hood_built_for = -1.0
	if k == Kind.NONE:
		return
	_robe_mesh = ImmediateMesh.new()
	_robe_mi = MeshInstance3D.new()
	_robe_mi.mesh = _robe_mesh
	_robe_mat = _cloth_mat(Color.WHITE)
	_robe_mat.vertex_color_use_as_albedo = true
	_robe_mi.material_override = _robe_mat
	add_child(_robe_mi)


static func _cloth_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m


## f: hip (Vector3, the waist ring's centre), basis (the body's turn and lean), top_r, hem_r, len (waist to hem),
## colliders ([[a, b, r]] capsules the robe can't go through), ground, head_top, head_c, head_r, up, face (unit,
## horizontal), hat_h, hat_r, brim_r, visible.
func update(delta: float, f: Dictionary) -> void:
	if kind == Kind.NONE:
		return
	_t += delta
	visible = bool(f.get("visible", true))
	if not visible:
		_have_robe = false
		_have_hat = false
		_have_tail = false
		return
	var dt := clampf(delta, 0.001, 1.0 / 30.0)
	_robe(f, dt)
	if kind == Kind.WIZARD or kind == Kind.BOTH:
		_hat(f, dt)
	if kind == Kind.SHADOW:
		_hood_up(f, dt)
	if kind == Kind.BOTH:
		_hood_down(f)


# ================================================================ robe
func _rest(f: Dictionary, i: int, j: int) -> Vector3:
	var u := float(i) / float(ROWS - 1)
	var a := TAU * float(j) / float(STRANDS)
	var r := lerpf(float(f.top_r), float(f.hem_r), pow(u, 0.8))
	return (f.hip as Vector3) + (f.basis as Basis) * Vector3(cos(a) * r, -float(f.len) * u, sin(a) * r)


func _robe(f: Dictionary, dt: float) -> void:
	var n := STRANDS * ROWS
	var hip: Vector3 = f.hip
	if not _have_robe or hip.distance_to(_last_hip) > 2.5:   # first frame, or a teleport: start hanging still
		_p.resize(n)
		_o.resize(n)
		for i in ROWS:
			for j in STRANDS:
				_p[i * STRANDS + j] = _rest(f, i, j)
				_o[i * STRANDS + j] = _p[i * STRANDS + j]
		_have_robe = true
		_last_hip = hip
	var step := hip - _last_hip   # the body's own motion this frame: the cloth's damping is relative to it (air
	_last_hip = hip               # drag on the moving body is small; damping the world velocity would blow it flat)
	var basis: Basis = f.basis
	var up := basis.y.normalized()
	var vel: Vector3 = f.get("vel", Vector3.ZERO)
	var speed := Vector2(vel.x, vel.z).length()
	var flutter := clampf((speed - 2.0) / 10.0, 0.0, 1.6)
	var seg := float(f.len) / float(ROWS - 1)
	var dt2 := dt * dt
	# integrate (the top row is pinned to the body)
	for j in STRANDS:
		var a := TAU * float(j) / float(STRANDS)
		var out := (basis * Vector3(cos(a), 0, sin(a))).normalized()
		_p[j] = _rest(f, 0, j)
		_o[j] = _p[j]
		for i in range(1, ROWS):
			var k := i * STRANDS + j
			var u := float(i) / float(ROWS - 1)
			var p: Vector3 = _p[k]
			var v := step * 0.985 + ((p - _o[k]) - step) * 0.84
			_o[k] = p
			var acc := Vector3(0, -12.0, 0)
			acc += (_rest(f, i, j) - p) * lerpf(70.0, 22.0, u)   # it keeps a robe's shape
			# flutter: the hem snaps in and out as the legs drive through it when running or dashing
			var g := sin(_t * 11.0 + float(j) * 1.9 + float(i) * 0.7) + 0.6 * sin(_t * 17.0 - float(j) * 2.3)
			acc += out * g * flutter * 9.0 * u
			p += v + acc * dt2
			_p[k] = p
	var cols: Array = f.get("colliders", [])
	var ground := float(f.get("ground", -100.0))
	for it in 3:
		for j in STRANDS:
			for i in range(1, ROWS):
				var k := i * STRANDS + j
				var above: Vector3 = _p[k - STRANDS]
				var p: Vector3 = _p[k]
				var d := p - above
				var dl := d.length()
				var want := seg * 1.02
				if dl > 1e-5:
					# keep its length, and never swing more than ~60 degrees out from hanging straight down (a robe
					# swings and flares; it doesn't fly up like a flag when you stop dead)
					var down := -up
					var dd := d.dot(down)
					var hz := d - down * dd
					var dmin := want * 0.5
					if dd < dmin:
						dd = dmin
					var hl := sqrt(maxf(want * want - dd * dd, 0.0))
					p = above + down * dd + (hz.normalized() * hl if hz.length() > 1e-5 else Vector3.ZERO)
					if (p - above).length() < want * 0.99:
						p = above + (p - above).normalized() * want
				# round the ring: neighbours stay about their distance apart
				var jn := (j + 1) % STRANDS
				var q: Vector3 = _p[i * STRANDS + jn]
				var ring_r := lerpf(float(f.top_r), float(f.hem_r), pow(float(i) / float(ROWS - 1), 0.8))
				var hw := 2.0 * ring_r * sin(PI / STRANDS)
				var e := q - p
				var el := e.length()
				if el > 1e-5:
					var corr := e * (0.5 * (el - hw) / el) * 0.6
					p += corr
					_p[i * STRANDS + jn] = q - corr
				# out of the body: never closer to the body's axis than a little inside the robe's shape
				var rel := p - hip
				var along := rel.dot(up)
				var radial := rel - up * along
				var min_r := lerpf(float(f.top_r) * 0.92, float(f.hem_r) * 0.55, float(i) / float(ROWS - 1))
				if radial.length() < min_r and radial.length() > 1e-4:
					p = hip + up * along + radial.normalized() * min_r
				for c in cols:
					p = _push_out(p, c[0], c[1], float(c[2]))
				if p.y < ground + 0.03:
					p.y = ground + 0.03
				_p[k] = p
	_draw_robe(f)


static func _push_out(p: Vector3, a: Vector3, b: Vector3, r: float) -> Vector3:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	var c := a + ab * t
	var d := p - c
	var dl := d.length()
	if dl < r and dl > 1e-5:
		return c + d * (r / dl)
	return p


func _draw_robe(f: Dictionary) -> void:
	var body := robe_color(kind)
	var trim := DARK_TRIM if kind == Kind.SHADOW else GREY_TRIM
	var hip: Vector3 = f.hip
	var up := (f.basis as Basis).y.normalized()
	_robe_mesh.clear_surfaces()
	_robe_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in ROWS - 1:
		for j in STRANDS:
			var jn := (j + 1) % STRANDS
			var quad := [[i, j], [i, jn], [i + 1, j], [i, jn], [i + 1, jn], [i + 1, j]]
			for v in quad:
				var p: Vector3 = _p[v[0] * STRANDS + v[1]]
				var rel := p - hip
				var nrm := rel - up * rel.dot(up)
				_robe_mesh.surface_set_normal(nrm.normalized() if nrm.length() > 1e-4 else up)
				var shade := 1.0 - 0.18 * float(v[0]) / float(ROWS - 1)   # a little darker toward the hem
				_robe_mesh.surface_set_color(trim if v[0] == ROWS - 1 else body * shade)
				_robe_mesh.surface_add_vertex(p)
	_robe_mesh.surface_end()


# ================================================================ hat
func _build_hat(f: Dictionary) -> void:
	for s in _hat_segs:
		s.queue_free()
	_hat_segs = []
	if _brim:
		_brim.queue_free()
	if _band:
		_band.queue_free()
	var h := float(f.hat_h)
	var r0 := float(f.hat_r)
	var mat := _cloth_mat(GREY.darkened(0.08))
	for k in HAT_N - 1:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.bottom_radius = r0 * (1.0 - float(k) / float(HAT_N - 1)) + 0.002
		cm.top_radius = r0 * (1.0 - float(k + 1) / float(HAT_N - 1)) + 0.002
		cm.height = 1.0
		cm.radial_segments = 12
		cm.rings = 1
		mi.mesh = cm
		mi.material_override = mat
		add_child(mi)
		_hat_segs.append(mi)
	_brim = MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = float(f.brim_r)
	bm.bottom_radius = float(f.brim_r) * 1.02
	bm.height = h * 0.035
	bm.radial_segments = 20
	_brim.mesh = bm
	_brim.material_override = mat
	add_child(_brim)
	_band = MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = r0 * 0.9
	dm.bottom_radius = r0 * 1.03
	dm.height = h * 0.09
	dm.radial_segments = 16
	_band.mesh = dm
	_band.material_override = _cloth_mat(HAT_BAND)
	add_child(_band)
	_hat_built_for = h


func _hat_rest(f: Dictionary, k: int) -> Vector3:
	var up: Vector3 = f.up
	var face: Vector3 = f.face
	var u := float(k) / float(HAT_N - 1)
	# a classic wizard's hat: straight at first, the top half bending back and over
	return (f.head_top as Vector3) + up * (float(f.hat_h) * u * (1.0 - 0.12 * u * u)) - face * (float(f.hat_h) * 0.22 * u * u * u)


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
	_hat_p[0] = base
	_hat_o[0] = base
	for k in range(1, HAT_N):
		var p: Vector3 = _hat_p[k]
		var v := step * 0.98 + ((p - (_hat_o[k] as Vector3)) - step) * 0.88
		_hat_o[k] = p
		var stiff := lerpf(900.0, 90.0, float(k) / float(HAT_N - 1))
		var acc := ((_hat_rest(f, k) - p) * stiff) + Vector3(0, -6.0, 0)
		_hat_p[k] = p + v + acc * dt * dt
	for it in 2:
		for k in range(1, HAT_N):
			var a: Vector3 = _hat_p[k - 1]
			var d: Vector3 = (_hat_p[k] as Vector3) - a
			if d.length() > 1e-5:
				_hat_p[k] = a + d.normalized() * seg
	for k in HAT_N - 1:
		_place(_hat_segs[k], _hat_p[k], _hat_p[k + 1])
	# the brim tilts partway toward where the crown leans
	var lean := ((_hat_p[1] as Vector3) - base).normalized()
	var bn := ((f.up as Vector3) + lean).normalized()
	_brim.global_transform = Transform3D(_basis_y(bn), base)
	_band.global_transform = Transform3D(_basis_y(lean), base + lean * float(f.hat_h) * 0.05)


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


# ================================================================ hood
func _build_hood(f: Dictionary) -> void:
	for n in [_hood, _rim]:
		if n:
			n.queue_free()
	for s in _tail_segs:
		s.queue_free()
	_tail_segs = []
	var r := float(f.head_r)
	var mat := _cloth_mat(DARK)
	_hood = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r * 1.22
	sm.height = r * 1.22
	sm.is_hemisphere = true
	sm.radial_segments = 20
	sm.rings = 8
	_hood.mesh = sm
	_hood.material_override = mat
	add_child(_hood)
	_rim = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r * 1.08
	tm.outer_radius = r * 1.3
	tm.rings = 20
	tm.ring_segments = 6
	_rim.mesh = tm
	_rim.material_override = _cloth_mat(DARK_TRIM.darkened(0.3))
	add_child(_rim)
	for k in TAIL_N - 1:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.bottom_radius = r * 0.32 * (1.0 - float(k) / float(TAIL_N - 1)) + 0.003
		cm.top_radius = r * 0.32 * (1.0 - float(k + 1) / float(TAIL_N - 1)) + 0.003
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
	var back := (-face * 0.9 + up * 0.25).normalized()   # the dome bulges back and a little up
	var c: Vector3 = (f.head_c as Vector3) + up * r * 0.08
	_hood.global_transform = Transform3D(_basis_y(back) * Basis.from_scale(Vector3(1.0, 1.15, 1.05)), c - back * r * 0.08)
	_rim.global_transform = Transform3D(_basis_y((-face * 0.97 + up * 0.08).normalized()), c - face * r * 0.02 - up * r * 0.04)
	# the tail: from the back of the hood, hanging down between the shoulders
	var start := c + back * r * 1.05 + up * r * 0.2
	var seg := r * 0.42
	if not _have_tail or (_tail_p[0] as Vector3).distance_to(start) > 2.5:
		_tail_p = []
		_tail_o = []
		for k in TAIL_N:
			var q := start + back * seg * 0.6 * k - up * seg * 0.7 * k
			_tail_p.append(q)
			_tail_o.append(q)
		_have_tail = true
	var step := start - (_tail_p[0] as Vector3)
	_tail_p[0] = start
	_tail_o[0] = start
	for k in range(1, TAIL_N):
		var p: Vector3 = _tail_p[k]
		var v := step * 0.98 + ((p - (_tail_o[k] as Vector3)) - step) * 0.88
		_tail_o[k] = p
		var rest := start + back * seg * 0.6 * k - up * seg * 0.7 * k
		var acc := (rest - p) * 60.0 + Vector3(0, -9.0, 0)
		_tail_p[k] = p + v + acc * dt * dt
	for it in 2:
		for k in range(1, TAIL_N):
			var a: Vector3 = _tail_p[k - 1]
			var d: Vector3 = (_tail_p[k] as Vector3) - a
			if d.length() > 1e-5:
				_tail_p[k] = a + d.normalized() * seg
	for k in TAIL_N - 1:
		_place(_tail_segs[k], _tail_p[k], _tail_p[k + 1])


## Someone with both: the dark hood lies dropped round the neck under the hat.
func _hood_down(f: Dictionary) -> void:
	var r := float(f.head_r)
	if _cowl == null or absf(_hood_built_for - r) > 1e-4:
		if _cowl:
			_cowl.queue_free()
		_cowl = MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r * 0.5
		tm.outer_radius = r * 0.85
		tm.rings = 18
		tm.ring_segments = 8
		_cowl.mesh = tm
		_cowl.material_override = _cloth_mat(DARK)
		add_child(_cowl)
		_hood_built_for = r
	var up: Vector3 = f.up
	var face: Vector3 = f.face
	var tilt := (up - face * 0.45).normalized()   # draped lower at the back
	_cowl.global_transform = Transform3D(_basis_y(tilt) * Basis.from_scale(Vector3(1.0, 0.55, 1.0)), (f.neck as Vector3) - face * r * 0.22 - up * r * 0.05)
