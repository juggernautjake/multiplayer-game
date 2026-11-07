## v0.12.18 SPELL AIM PREVIEW (Jacob and his friend: "if we are aiming with a fireball, there should be some kind of
## circle that indicates where the spell is going to land before we cast it, and the circle should move with the
## cursor"; "for spells that have self focused casting... an outer radius... so you know your spell's range"; "these
## calculated areas of effect should only appear for the caster").
## Drawn on THIS screen only (a local node: nothing is sent, nobody else sees it), while you hold the left mouse button
## with a spell ready to let go (Main.previewing) or hold the right mouse button to aim with the staff or wand. Each
## spell's shape is worked out the way the server will work it out, at your mastery of it:
##   Lightning, Meteor (and its extra rocks), Arcane Storm, Gravity Well (its pull too), Golem, Stone Titan: a ring
##     where it will land (Net._aim_ground: the crosshair point, pulled in to the spell's reach), and a faint ring of
##     the reach round you;
##   Fireball: its flight (the same arc under gravity) to where it will burst, and the blast's ring there;
##   Stun: the bolt's line and the burst's ring where it stops;
##   Spark Beam, Life Drain: the beam's line to its reach (Life Drain: a ring on the enemy it will latch onto);
##   Teleport: where you will arrive (Sim.teleport_target) and the reach;
##   Frost Nova, Heal Aura: their ring round you; Fog: the cloud's square round you.
class_name AimPreview
extends Node3D

const COL_AREA := Color(1.0, 0.45, 0.1, 0.95)
const COL_HEAL := Color(0.3, 1.0, 0.45, 0.95)
const COL_REACH := Color(1.0, 1.0, 1.0, 0.35)
const COL_LINE := Color(1.0, 0.8, 0.3, 0.85)
const SEG := 56

var main: Node
var net: Net
var mesh := ImmediateMesh.new()
var _mi := MeshInstance3D.new()
var shown := ""    # the spell it last drew ("" = nothing; tests)
var shown_at := Vector3.ZERO
var shown_r := 0.0


func setup(n: Net, m: Node) -> void:
	net = n
	main = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mi.mesh = mesh
	_mi.material_override = mat
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)


func update(active: bool) -> void:
	mesh.clear_surfaces()
	shown = ""
	var s: Sim.PlayerState = net.predicted
	if not active or s == null or s.dead > 0 or not Weapons.is_magic(s.weapon):
		return
	var spell_i := int(main.spell_sel.get(main.weapon_slot, s.spell)) if s.weapon == main.weapon_slot else s.spell
	var sp := Weapons.spell_at(s.weapon, spell_i, s.mastery)
	var nm := str(sp.name)
	var aim: Vector3 = main.aim_point
	var yaw: float = main.face_yaw
	var hand := s.pos + Vector3(0, 1.45, 0) + Vector3(-sin(yaw), 0, -cos(yaw)) * 0.45
	if nm == "Shield":
		return   # nothing to place
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	match nm:
		"Lightning", "Golem", "Stone Titan":
			var at := Net.aim_ground(s.pos, aim, float(sp.range), yaw)
			var r := float(sp.get("radius", 1.2 if nm == "Golem" else 2.2))
			_ring(at, r, COL_AREA, true)
			_ring(s.pos, float(sp.range), COL_REACH)
			_mark(nm, at, r)
		"Meteor":
			var at := Net.aim_ground(s.pos, aim, float(sp.range), yaw)
			_ring(at, float(sp.radius), COL_AREA, true)
			var n := int(sp.get("meteors", 1))
			var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
			for k in range(1, n):   # the extra rocks round it (as Net._cast places them)
				var a := atan2(fwd.x, fwd.z) + TAU * float(k - 1) / float(n - 1) + (PI / 4.0 if n == 5 else PI / 2.0)
				var w := at + Vector3(sin(a), 0, cos(a)) * float(sp.get("spread", 4.5))
				w.y = WorldLayout.ground_height(w.x, w.z, at.y + 1.0)
				_ring(w, float(sp.radius), Color(COL_AREA, 0.5))
			_ring(s.pos, float(sp.range), COL_REACH)
			_mark(nm, at, float(sp.radius))
		"Arcane Storm":
			var at := Net.aim_ground(s.pos, aim, float(sp.range), yaw)
			_ring(at, float(sp.area), COL_AREA, true)
			_ring(s.pos, float(sp.range), COL_REACH)
			_mark(nm, at, float(sp.area))
		"Gravity Well":
			var at := Net.aim_ground(s.pos, aim, float(sp.range), yaw)
			_ring(at, float(sp.pull_radius), Color(0.7, 0.5, 1.0, 0.55))
			_ring(at, float(sp.radius), COL_AREA, true)
			_ring(s.pos, float(sp.range), COL_REACH)
			_mark(nm, at, float(sp.pull_radius))
		"Fireball":
			var to := aim - hand
			if to.length() < 1.0:
				to = Vector3(-sin(yaw), 0.05, -cos(yaw))
			var path := fireball_path(hand, to.normalized() * float(sp.speed), float(sp.gravity))
			for i in range(1, path.size()):
				_line(path[i - 1], path[i], COL_LINE)
			var end: Vector3 = path[-1]
			var ground := Vector3(end.x, WorldLayout.ground_height(end.x, end.z, end.y + 0.5), end.z)
			_ring(ground if end.y - ground.y < 1.5 else end, float(sp.radius), COL_AREA, true)
			_mark(nm, end, float(sp.radius))
		"Stun":
			var end := beam_end(hand, aim, float(sp.range))
			if hand.distance_to(aim) < hand.distance_to(end) and aim.length() > 0.0:
				end = aim
			_line(hand, end, COL_LINE)
			_ring(Vector3(end.x, WorldLayout.ground_height(end.x, end.z, end.y + 0.5), end.z), float(sp.radius), Color(0.6, 0.8, 1.0, 0.9), true)
			_mark(nm, end, float(sp.radius))
		"Spark Beam", "Life Drain":
			var end := beam_end(hand, aim, float(sp.range))
			_line(hand, end, COL_LINE)
			_ring(s.pos, float(sp.range), COL_REACH)
			if nm == "Life Drain":   # the enemy it will latch onto (the same aim help the server gives)
				var t = main.drain_preview_target(hand, aim, float(sp.range), float(sp.get("assist", 0.0)))
				if t != null:
					_ring(t, 0.8, Color(0.85, 0.2, 0.3, 0.95), true)
					_line(hand, (t as Vector3) + Vector3(0, 1.1, 0), Color(0.9, 0.25, 0.35, 0.9))
			_mark(nm, end, 0.0)
		"Teleport":
			var at := Sim.teleport_target(s.pos, yaw, aim, float(sp.range))
			_ring(at, 0.7, Color(0.6, 0.6, 1.0, 0.95), true)
			_ring(s.pos, float(sp.range), COL_REACH)
			_mark(nm, at, 0.7)
		"Frost Nova":
			_ring(s.pos, float(sp.radius), Color(0.6, 0.85, 1.0, 0.9), true)
			if float(sp.get("freeze_r", 0.0)) > 0.0:
				_ring(s.pos, float(sp.freeze_r), Color(0.8, 0.95, 1.0, 0.6))
			_mark(nm, s.pos, float(sp.radius))
		"Heal Aura":
			_ring(s.pos, float(sp.radius), COL_HEAL, true)
			_mark(nm, s.pos, float(sp.radius))
		"Fog":
			var h := float(sp.half)
			var c := [Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, h)]
			for i in 4:
				_line(s.pos + c[i] + Vector3(0, 0.08, 0), s.pos + c[(i + 1) % 4] + Vector3(0, 0.08, 0), Color(0.8, 0.8, 0.85, 0.7))
			_mark(nm, s.pos, h)
		_:
			pass   # the Shield: nothing to place
	mesh.surface_end()


func _mark(nm: String, at: Vector3, r: float) -> void:
	shown = nm
	shown_at = at
	shown_r = r


## The Fireball's flight from `from` (as Net._update_projectiles moves it) until it meets the ground or a wall, or 3 s.
static func fireball_path(from: Vector3, v0: Vector3, g: float) -> Array:
	var out := [from]
	var prev := from
	for n in range(1, 180):
		var p := Weapons.proj_pos(from, v0, g, n)
		var d := p - prev
		var len := d.length()
		if len > 0.0001:
			var t := WorldLayout.ray_hit(prev, d / len, len)
			if t < len:
				out.append(prev + d / len * t)
				return out
		var gy := WorldLayout.ground_height(p.x, p.z, prev.y + 0.2)
		if p.y <= gy:
			out.append(Vector3(p.x, gy, p.z))
			return out
		if n % 3 == 0:
			out.append(p)
		prev = p
	out.append(prev)
	return out


## Where a beam from the wand toward the crosshair stops: the first wall or the reach (people stop it too: the
## crosshair point when it's on someone).
static func beam_end(from: Vector3, aim: Vector3, reach: float) -> Vector3:
	var dir := aim - from
	if dir.length() < 0.5:
		return from
	dir = dir.normalized()
	var t := minf(WorldLayout.ray_hit(from, dir, reach), reach)
	t = minf(t, from.distance_to(aim) if from.distance_to(aim) > 0.5 else t)
	return from + dir * t


func _line(a: Vector3, b: Vector3, c: Color, w := 0.06) -> void:
	var d := b - a
	var side := d.cross(Vector3.UP)
	if side.length() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized() * w
	_quad(a - side, a + side, b + side, b - side, c, c)


func _quad(a0: Vector3, a1: Vector3, b1: Vector3, b0: Vector3, ca: Color, cb: Color) -> void:
	for v in [[a0, ca], [a1, ca], [b1, cb], [a0, ca], [b1, cb], [b0, cb]]:
		mesh.surface_set_color(v[1])
		mesh.surface_add_vertex(v[0])


## A ring on the ground round `at` (following the ground's height): a band; `bold`: thicker, with a soft fill inside
## and a dot at the centre.
func _ring(at: Vector3, r: float, c: Color, bold := false) -> void:
	if r <= 0.0:
		return
	var seg := SEG if r > 3.0 else 32
	var w := clampf(r * 0.03, 0.08, 0.3) * (1.6 if bold else 1.0)
	var fill := Color(c, 0.13)
	var clear := Color(c, 0.0)
	var pts_o := []
	var pts_i := []
	for i in seg + 1:
		var a := TAU * float(i) / float(seg)
		var dir := Vector3(cos(a), 0, sin(a))
		pts_o.append(_on_ground(at + dir * r, at.y))
		pts_i.append(_on_ground(at + dir * maxf(r - w, 0.0), at.y))
	for i in seg:
		_quad(pts_i[i], pts_o[i], pts_o[i + 1], pts_i[i + 1], c, c)
	if bold:
		var mid := []
		for i in seg + 1:
			var a := TAU * float(i) / float(seg)
			mid.append(_on_ground(at + Vector3(cos(a), 0, sin(a)) * r * 0.55, at.y))
		for i in seg:   # a glow fading in from the edge
			_quad(mid[i], pts_i[i], pts_i[i + 1], mid[i + 1], clear, fill)
		var dot := minf(r * 0.08, 0.35)
		for i in 12:
			var a0 := TAU * float(i) / 12.0
			var a1 := TAU * float(i + 1) / 12.0
			var p0 := _on_ground(at + Vector3(cos(a0), 0, sin(a0)) * dot, at.y)
			var p1 := _on_ground(at + Vector3(cos(a1), 0, sin(a1)) * dot, at.y)
			var ctr := _on_ground(at, at.y)
			for v in [ctr, p0, p1]:
				mesh.surface_set_color(c)
				mesh.surface_add_vertex(v)


func _on_ground(p: Vector3, y_hint: float) -> Vector3:
	return Vector3(p.x, WorldLayout.ground_height(p.x, p.z, y_hint + 0.6) + 0.06, p.z)
