## The 3D test character, rigged: pelvis, spine and chest, neck and head, shoulders, elbows, wrists, hands, hips,
## knees and feet. Arms and legs are two-bone IK chains (elbows bend out and down, knees forward), so every pose only
## says where the hands and feet go and the limbs bend naturally to get there.
##
## Animation is computed every frame from the player's state (no network traffic):
##   resting: breathing, a slow weight shift, now and then a glance around; the weapon held naturally (sword at the
##     ready, club two-handed on the shoulder, bow and slingshot in the left hand);
##   moving: feet step and plant (stride grows with speed), hips bob, free arms swing; air: knees tucked;
##   attacks: keyframed hand paths with the weapon's angle, torso twist and lean: a wind-up, a fast strike through
##     the moment the hit lands, a follow-through and recovery; club moves use both hands;
##   bow / slingshot: the left arm holds it out, the right hand draws the string or band back to the cheek; the string
##     and bands are drawn live from the weapon's tips to the drawing hand, with the arrow or stone in it.
## Same interface as Avatar (Pip): yaw, grounded, dashing, state, model, label, flash(), animate().
class_name FigureAvatar
extends Node3D

const SKIN := Color("f1c9a5")
const PANTS := Color("3b4252")
const BOOTS := Color("2a2a30")
const UPPER_ARM := 0.29
const FOREARM := 0.27
const THIGH := 0.45
const SHIN := 0.44

var yaw := 0.0
var grounded := true
var dashing := false
var state: Sim.PlayerState
var instant := false        # skip blending (pose previews)

var model: Node3D           # everything in the body's frame (x right, y up, -z forward); hidden in first person
var label: Label3D
var hp_bar: Sprite3D
var blob: MeshInstance3D
var held: Node3D
var held_w := -1
var parts := {}             # name -> MeshInstance3D
var _mats: Array = []
var _string_a: MeshInstance3D   # live bow string / slingshot bands
var _string_b: MeshInstance3D
var _ammo: Node3D               # nocked arrow / stone in the pouch

var _last := Vector3.ZERO
var _vel := Vector3.ZERO
var _have_last := false
var _phase := 0.0
var _t := 0.0
var _flash := 0.0
var _slashed_n := -1
# the smoothed pose
var _hand_r := Vector3(0.28, 1.0, -0.05)
var _hand_l := Vector3(-0.28, 1.0, -0.05)
var _wdir := Vector3(0, 0, -1)
var _wroll := Vector3(1, 0, 0)
var _twist := 0.0
var _lean := 0.0
var _crouch := 0.0
var _foot_r := Vector3(0.12, 0.0, 0.0)
var _foot_l := Vector3(-0.12, 0.0, 0.0)
var _look := 0.0


func _init(player_name: String, color: Color, show_name: bool) -> void:
	model = Node3D.new()
	add_child(model)
	var sleeve := color.darkened(0.15)
	for spec in [["pelvis", PANTS], ["chest", color], ["neck", SKIN], ["head", SKIN], ["eye_l", Color(0.08, 0.08, 0.1)],
			["eye_r", Color(0.08, 0.08, 0.1)], ["upper_r", sleeve], ["upper_l", sleeve], ["fore_r", SKIN], ["fore_l", SKIN],
			["elbow_r", sleeve], ["elbow_l", sleeve], ["hand_r", SKIN], ["hand_l", SKIN], ["shoulder_r", color], ["shoulder_l", color],
			["thigh_r", PANTS], ["thigh_l", PANTS], ["shin_r", PANTS], ["shin_l", PANTS], ["knee_r", PANTS], ["knee_l", PANTS],
			["foot_r", BOOTS], ["foot_l", BOOTS]]:
		var mi := MeshInstance3D.new()
		var nm: String = spec[0]
		if nm in ["head", "eye_l", "eye_r", "hand_r", "hand_l", "elbow_r", "elbow_l", "knee_r", "knee_l", "shoulder_r", "shoulder_l"]:
			var s := SphereMesh.new()
			s.radius = 0.5
			s.height = 1.0
			mi.mesh = s
		elif nm in ["pelvis", "foot_r", "foot_l"]:
			mi.mesh = BoxMesh.new()
		elif nm == "chest":
			var c := CapsuleMesh.new()
			c.radius = 0.5
			c.height = 1.6
			mi.mesh = c
		else:
			var cy := CylinderMesh.new()
			cy.top_radius = 0.5
			cy.bottom_radius = 0.5
			cy.height = 1.0
			mi.mesh = cy
		var mat := StandardMaterial3D.new()
		mat.albedo_color = spec[1]
		mat.roughness = 0.8
		mi.material_override = mat
		_mats.append([mat, spec[1]])
		model.add_child(mi)
		parts[nm] = mi
	_string_a = _line_mesh(WeaponModels.STRING)
	_string_b = _line_mesh(WeaponModels.STRING)

	blob = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.45
	disc.bottom_radius = 0.45
	disc.height = 0.01
	blob.mesh = disc
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(color.r, color.g, color.b, 0.5)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blob.material_override = bm
	blob.top_level = true
	add_child(blob)
	label = Label3D.new()
	label.text = player_name
	label.modulate = color.lightened(0.35)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.25
	label.font_size = 44
	label.outline_size = 12
	label.no_depth_test = true
	label.visible = show_name
	add_child(label)
	hp_bar = Sprite3D.new()
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	hp_bar.texture = ImageTexture.create_from_image(img)
	hp_bar.scale = Vector3(0.9, 0.08, 1)
	hp_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp_bar.no_depth_test = true
	hp_bar.position.y = 2.05
	hp_bar.visible = show_name
	add_child(hp_bar)


func flash() -> void:
	_flash = 0.15


# ================================================================ per frame
func animate(delta: float, _cam: Camera3D) -> void:
	_t += delta
	if not _have_last:
		_last = position
		_have_last = true
	if delta > 0.0:
		_vel = _vel.lerp((position - _last) / delta, clampf(delta * 15.0, 0.0, 1.0))
	_last = position
	rotation.y = yaw
	var local_vel := global_transform.basis.inverse() * _vel
	var speed := Vector2(_vel.x, _vel.z).length()
	var st := state
	var w := st.weapon if st != null else Weapons.FISTS
	_update_held(w)

	var pose := _pose(st, speed)
	var a := 1.0 if instant else clampf(delta * (30.0 if pose.get("snap", false) else 12.0), 0.0, 1.0)
	_hand_r = _hand_r.lerp(pose.hand_r, a)
	_hand_l = _hand_l.lerp(pose.hand_l, a)
	_wdir = _wdir.slerp(pose.wdir.normalized(), a) if _wdir.normalized().dot(pose.wdir.normalized()) > -0.99 else pose.wdir.normalized()
	_wroll = _wroll.lerp(pose.wroll, a).normalized()
	_twist = lerpf(_twist, pose.twist, a)
	_lean = lerpf(_lean, pose.lean, a)
	_crouch = lerpf(_crouch, pose.crouch, a)
	_look = lerpf(_look, pose.look, clampf(delta * 3.0, 0.0, 1.0) if not instant else 1.0)

	# ---- feet: step and plant while moving, tuck in the air, kick when kicking
	var stride := clampf(speed * 0.11, 0.0, 0.85)
	var lift := clampf(speed * 0.03, 0.0, 0.2)
	var fwd_dir := Vector2(local_vel.x, local_vel.z)
	fwd_dir = fwd_dir.normalized() if fwd_dir.length() > 0.2 else Vector2(0, -1)
	if grounded and speed > 0.3:
		_phase += delta * (4.0 + speed * 1.1)
	var fr := _step_foot(_phase, stride, lift, fwd_dir, 0.13)
	var fl := _step_foot(_phase + PI, stride, lift, fwd_dir, -0.13)
	if not grounded:
		fr = Vector3(0.13, 0.42, -0.12)
		fl = Vector3(-0.13, 0.3, 0.12)
	if pose.has("foot_r"):
		fr = pose.foot_r
	var fa := 1.0 if instant else clampf(delta * 20.0, 0.0, 1.0)
	_foot_r = _foot_r.lerp(fr, fa)
	_foot_l = _foot_l.lerp(fl, fa)

	# ---- the skeleton
	var dead := st != null and st.dead > 0
	model.rotation.x = lerpf(model.rotation.x, -PI / 2.0 if dead else 0.0, a)
	model.position.y = lerpf(model.position.y, 0.25 if dead else 0.0, a)
	var breathe := sin(_t * 2.1) * 0.012
	var sway := sin(_t * 0.55) * 0.025 * (1.0 - clampf(speed, 0.0, 1.0))
	var bob := absf(sin(_phase)) * 0.045 * clampf(speed / Sim.WALK_SPEED, 0.0, 1.0) if grounded else 0.0
	var pelvis := Vector3(sway, 0.95 - _crouch + bob, 0)
	var spine := Basis(Vector3.UP, _twist) * Basis(Vector3.RIGHT, _lean - (0.12 * clampf(speed / Sim.SPRINT_SPEED, 0.0, 1.0)) - (0.4 if dashing else 0.0))
	var chest := pelvis + spine * Vector3(0, 0.42 + breathe, 0)
	var sh_r := chest + spine * Vector3(0.2, 0.13, 0)
	var sh_l := chest + spine * Vector3(-0.2, 0.13, 0)
	var neck := chest + spine * Vector3(0, 0.2, 0)
	var head := neck + spine * Vector3(0, 0.17, 0)
	var head_basis := spine * Basis(Vector3.UP, _look - _twist * 0.6)
	var hip_r := pelvis + Vector3(0.1, -0.03, 0)
	var hip_l := pelvis + Vector3(-0.1, -0.03, 0)

	_place_ball("pelvis", pelvis, Vector3(0.34, 0.18, 0.2), spine)
	_place_seg("chest", pelvis + spine * Vector3(0, 0.08, 0), chest + spine * Vector3(0, 0.1, 0), 0.19)
	_place_seg("neck", neck - spine * Vector3(0, 0.05, 0), head - spine * Vector3(0, 0.08, 0), 0.06)
	_place_ball("head", head, Vector3.ONE * 0.32)
	_place_ball("eye_l", head + head_basis * Vector3(-0.055, 0.02, -0.15), Vector3.ONE * 0.04)
	_place_ball("eye_r", head + head_basis * Vector3(0.055, 0.02, -0.15), Vector3.ONE * 0.04)
	_place_ball("shoulder_r", sh_r, Vector3.ONE * 0.13)
	_place_ball("shoulder_l", sh_l, Vector3.ONE * 0.13)
	var hand_r := _arm("r", sh_r, _hand_r, Vector3(0.6, -1.0, 0.7))
	var hand_l := _arm("l", sh_l, _hand_l, Vector3(-0.6, -1.0, 0.7))
	_leg("r", hip_r, _foot_r + Vector3(0, 0.07, 0))
	_leg("l", hip_l, _foot_l + Vector3(0, 0.07, 0))

	# ---- the weapon in hand, and the bow string / slingshot bands drawn live
	if held != null:
		var in_left := w == Weapons.BOW or w == Weapons.SLING
		var grip := hand_l if in_left else hand_r
		var y := _wdir.normalized()
		var x := _wroll.cross(y)
		x = x.normalized() if x.length() > 0.05 else y.cross(Vector3.FORWARD).normalized()
		var z := x.cross(y).normalized()
		held.transform = Transform3D(Basis(x, y, z), grip)
		held.visible = not dead
		_draw_string(st, w, hand_r)
	else:
		_string_a.visible = false
		_string_b.visible = false
		if _ammo:
			_ammo.visible = false

	_swing_fx(st)
	_flash = maxf(_flash - delta, 0.0)
	for mc in _mats:
		(mc[0] as StandardMaterial3D).albedo_color = Color(1, 0.4, 0.4) if _flash > 0.0 else mc[1]
	if st != null:
		var hpk := float(st.hp) / float(Sim.MAX_HP)
		hp_bar.scale.x = maxf(0.9 * hpk, 0.001)
		hp_bar.modulate = Color(0.9, 0.2, 0.2).lerp(Color(0.3, 0.9, 0.3), hpk)
		hp_bar.visible = label.visible and not dead
	var ground := WorldLayout.ground_height(position.x, position.z, position.y)
	blob.global_position = Vector3(position.x, ground + 0.012, position.z)
	var bs := clampf(1.0 - (position.y - ground) / 6.0, 0.35, 1.0)
	blob.scale = Vector3(bs, 1, bs)


## A foot's place in its step cycle: forward through the air when sin(phase) > 0, planted and sliding back otherwise.
func _step_foot(ph: float, stride: float, lift: float, dir: Vector2, side: float) -> Vector3:
	var along := cos(ph) * stride * 0.5
	var up := maxf(sin(ph), 0.0) * lift
	return Vector3(side - dir.x * along, up, -dir.y * along)


# ================================================================ poses
## Where the hands go (body frame), the weapon's direction and the way its flat faces, torso twist and lean,
## how low the hips sit, head turn, and a right-foot target for kicks.
func _pose(st: Sim.PlayerState, speed: float) -> Dictionary:
	var swing := sin(_phase) * clampf(speed / Sim.WALK_SPEED, 0.0, 1.4) * 0.22 if grounded else 0.0
	var glance := sin(_t * 0.37) * sin(_t * 0.23) * 0.7 * (1.0 - clampf(speed, 0.0, 1.0))   # an idle look around
	var p := { "hand_r": Vector3(0.27, 1.0 + 0.01 * sin(_t * 2.1), -0.04 - swing), "hand_l": Vector3(-0.27, 1.0, -0.04 + swing),
		"wdir": Vector3(0, -0.3, -1), "wroll": Vector3(1, 0, 0), "twist": 0.0, "lean": 0.0, "crouch": 0.0, "look": glance }
	if st == null or st.dead > 0:
		return p
	var w := st.weapon
	match w:
		Weapons.SWORD:   # at the ready: blade forward and a little up, the free arm loose
			p.hand_r = Vector3(0.24, 1.08, -0.28 - swing * 0.3)
			p.wdir = Vector3(-0.15, 0.35, -1.0)
			p.wroll = Vector3(1, 0, 0)
		Weapons.CLUB:    # two-handed, resting on the right shoulder
			p.hand_r = Vector3(0.18, 1.25, -0.22)
			p.hand_l = Vector3(0.08, 1.1, -0.26)
			p.wdir = Vector3(0.2, 0.75, 0.6)
			p.wroll = Vector3(1, 0, 0)
		Weapons.BOW:     # held loosely at the left side, stave upright
			p.hand_l = Vector3(-0.3, 1.05, -0.12 + swing)
			p.wdir = Vector3(0.1, 1.0, 0.15)
			p.wroll = Vector3(0, 0, 1)
		Weapons.SLING:   # fork up in the left hand
			p.hand_l = Vector3(-0.26, 1.05, -0.2 + swing)
			p.wdir = Vector3(0, 1.0, -0.25)
			p.wroll = Vector3(1, 0, 0)

	if Weapons.is_melee(w) and st.atk > 0:
		var mv := Weapons.move(w, st.combo)
		var t := 1.0 - float(st.atk) / float(mv.swing)     # 0 .. 1 through the move
		var h := float(mv.windup) / float(mv.swing)        # when the blow lands
		var keys: Array = _move_keys(mv.name, h, p)
		var k := _sample(keys, t)
		for key in k.keys():
			p[key] = k[key]
		p.snap = true
		if w == Weapons.CLUB:   # both hands on the club
			p.hand_l = p.hand_r - (p.wdir as Vector3).normalized() * 0.14 + Vector3(-0.04, 0, 0)
		return p

	if not Weapons.is_melee(w) and (st.charge > 0 or st.atk > 0):
		var d := Weapons.get_data(w)
		var pull := clampf(float(st.charge) / float(d.draw), 0.0, 1.0)
		var shot_t := 0.0
		if st.charge == 0 and st.atk > 0:   # just released: the string snaps forward, the hand flicks back
			pull = 0.0
			shot_t = 1.0 - float(st.atk) / float(d.shot)
		var aim_l := Vector3(-0.04, 1.47, -0.64)
		var anchor := Vector3(0.12, 1.55, -0.03)     # the drawing hand's anchor at the cheek
		p.hand_l = aim_l
		p.twist = 0.45
		p.look = -0.4
		if w == Weapons.BOW:
			p.wdir = Vector3(0.12, 1.0, 0.0)
			p.wroll = Vector3(0, 0, 1)
			var nock := aim_l + Vector3(0.02, 0, 0.08)
			p.hand_r = nock.lerp(anchor, _smooth(pull)) if shot_t == 0.0 else anchor + Vector3(0.12, 0.02, 0.12) * _smooth(minf(shot_t * 3.0, 1.0))
		else:
			p.hand_l = aim_l + Vector3(0, -0.02, 0)
			p.wdir = Vector3(0, 1.0, -0.15)
			p.wroll = Vector3(1, 0, 0)
			var pouch := aim_l + Vector3(0, 0.27, 0.06)
			p.hand_r = pouch.lerp(anchor + Vector3(0, -0.05, 0), _smooth(pull)) if shot_t == 0.0 else anchor + Vector3(0.1, 0, 0.1) * _smooth(minf(shot_t * 3.0, 1.0))
		p.snap = shot_t > 0.0
	return p


## Keyframes for each melee move: [time, values...]. Times 0..1 through the move; `h` is when the blow lands.
## Hands are body-frame positions; wdir points along the weapon; wroll is the side its flat (edge) faces.
func _move_keys(name: String, h: float, rest: Dictionary) -> Array:
	var R: Vector3 = rest.hand_r
	var L: Vector3 = rest.hand_l
	match name:
		"slash":    # wind up behind the right shoulder, cut across the front, follow through low left
			return [[0.0, {"hand_r": Vector3(0.38, 1.5, 0.1), "wdir": Vector3(0.55, 0.55, 0.65), "wroll": Vector3(0, 1, 0), "twist": -0.55, "hand_l": Vector3(-0.3, 1.15, -0.2)}],
				[h, {"hand_r": Vector3(0.02, 1.28, -0.58), "wdir": Vector3(-1.0, 0.05, -0.55), "wroll": Vector3(0, 1, 0), "twist": 0.3, "lean": -0.12}],
				[minf(h + 0.28, 0.9), {"hand_r": Vector3(-0.36, 1.08, -0.28), "wdir": Vector3(-0.8, -0.35, 0.45), "wroll": Vector3(0, 1, 0), "twist": 0.65, "lean": -0.15}],
				[1.0, {"hand_r": R, "wdir": rest.wdir, "wroll": rest.wroll, "twist": 0.0, "lean": 0.0, "hand_l": L}]]
		"backslash":   # from the left shoulder back across to the right
			return [[0.0, {"hand_r": Vector3(-0.32, 1.42, -0.12), "wdir": Vector3(-0.7, 0.45, 0.4), "wroll": Vector3(0, -1, 0), "twist": 0.55}],
				[h, {"hand_r": Vector3(0.12, 1.25, -0.6), "wdir": Vector3(1.0, 0.0, -0.6), "wroll": Vector3(0, -1, 0), "twist": -0.25, "lean": -0.12}],
				[minf(h + 0.28, 0.9), {"hand_r": Vector3(0.45, 1.12, -0.18), "wdir": Vector3(0.85, -0.3, 0.5), "wroll": Vector3(0, -1, 0), "twist": -0.6, "lean": -0.1}],
				[1.0, {"hand_r": R, "wdir": rest.wdir, "wroll": rest.wroll, "twist": 0.0, "lean": 0.0}]]
		"thrust":   # draw back to the hip, drive straight out with the lunge, hold, recover
			return [[0.0, {"hand_r": Vector3(0.26, 1.12, 0.18), "wdir": Vector3(0, 0.05, -1), "wroll": Vector3(0, 1, 0), "twist": 0.45, "crouch": 0.08, "hand_l": Vector3(-0.32, 1.2, -0.25)}],
				[h, {"hand_r": Vector3(0.06, 1.3, -0.8), "wdir": Vector3(0, 0.02, -1), "wroll": Vector3(0, 1, 0), "twist": -0.3, "lean": -0.28, "crouch": 0.12, "hand_l": Vector3(-0.35, 1.25, 0.15)}],
				[minf(h + 0.35, 0.92), {"hand_r": Vector3(0.06, 1.3, -0.78), "wdir": Vector3(0, 0.02, -1), "wroll": Vector3(0, 1, 0), "twist": -0.3, "lean": -0.25, "crouch": 0.1}],
				[1.0, {"hand_r": R, "wdir": rest.wdir, "wroll": rest.wroll, "twist": 0.0, "lean": 0.0, "crouch": 0.0, "hand_l": L}]]
		"bash":     # a big wind-up over the right shoulder, a heavy sweep across, carried through low
			return [[0.0, {"hand_r": Vector3(0.36, 1.62, 0.22), "wdir": Vector3(0.45, 0.7, 0.6), "wroll": Vector3(0, 1, 0), "twist": -0.7, "crouch": 0.05}],
				[h, {"hand_r": Vector3(0.0, 1.22, -0.6), "wdir": Vector3(-1.0, 0.1, -0.35), "wroll": Vector3(0, 1, 0), "twist": 0.35, "lean": -0.15, "crouch": 0.1}],
				[minf(h + 0.3, 0.9), {"hand_r": Vector3(-0.38, 1.0, -0.2), "wdir": Vector3(-0.65, -0.55, 0.45), "wroll": Vector3(0, 1, 0), "twist": 0.75, "lean": -0.2, "crouch": 0.1}],
				[1.0, {"hand_r": R, "wdir": rest.wdir, "wroll": rest.wroll, "twist": 0.0, "lean": 0.0, "crouch": 0.0}]]
		"backhand":
			return [[0.0, {"hand_r": Vector3(-0.32, 1.5, 0.1), "wdir": Vector3(-0.55, 0.65, 0.5), "wroll": Vector3(0, -1, 0), "twist": 0.7, "crouch": 0.05}],
				[h, {"hand_r": Vector3(0.12, 1.22, -0.6), "wdir": Vector3(1.0, 0.1, -0.4), "wroll": Vector3(0, -1, 0), "twist": -0.35, "lean": -0.15, "crouch": 0.1}],
				[minf(h + 0.3, 0.9), {"hand_r": Vector3(0.45, 1.05, -0.15), "wdir": Vector3(0.7, -0.5, 0.45), "wroll": Vector3(0, -1, 0), "twist": -0.75, "lean": -0.18, "crouch": 0.1}],
				[1.0, {"hand_r": R, "wdir": rest.wdir, "wroll": rest.wroll, "twist": 0.0, "lean": 0.0, "crouch": 0.0}]]
		"smash":    # raise high behind the head, hang, bring it down hard with the knees bending
			return [[0.0, {"hand_r": Vector3(0.12, 1.75, -0.05), "wdir": Vector3(0.05, 1.0, 0.25), "wroll": Vector3(1, 0, 0), "lean": 0.05}],
				[h * 0.75, {"hand_r": Vector3(0.1, 1.98, 0.12), "wdir": Vector3(0.0, 0.75, 0.75), "wroll": Vector3(1, 0, 0), "lean": 0.18}],
				[h, {"hand_r": Vector3(0.05, 0.95, -0.62), "wdir": Vector3(0.0, -0.65, -1.0), "wroll": Vector3(1, 0, 0), "lean": -0.45, "crouch": 0.18}],
				[minf(h + 0.32, 0.92), {"hand_r": Vector3(0.05, 0.92, -0.6), "wdir": Vector3(0.0, -0.7, -1.0), "wroll": Vector3(1, 0, 0), "lean": -0.4, "crouch": 0.16}],
				[1.0, {"hand_r": R, "wdir": rest.wdir, "wroll": rest.wroll, "lean": 0.0, "crouch": 0.0}]]
		"jab":      # guard up, a quick straight right
			return [[0.0, {"hand_r": Vector3(0.18, 1.38, -0.18), "hand_l": Vector3(-0.16, 1.42, -0.22)}],
				[h, {"hand_r": Vector3(0.12, 1.47, -0.66), "hand_l": Vector3(-0.16, 1.42, -0.2), "twist": -0.25, "lean": -0.08}],
				[minf(h + 0.25, 0.9), {"hand_r": Vector3(0.18, 1.4, -0.3), "twist": -0.1}],
				[1.0, {"hand_r": Vector3(0.18, 1.38, -0.18), "hand_l": Vector3(-0.16, 1.42, -0.22), "twist": 0.0, "lean": 0.0}]]
		"cross":    # the left, with the hips turning into it
			return [[0.0, {"hand_r": Vector3(0.18, 1.4, -0.2), "hand_l": Vector3(-0.16, 1.4, -0.2)}],
				[h, {"hand_l": Vector3(-0.02, 1.47, -0.68), "hand_r": Vector3(0.2, 1.42, -0.15), "twist": 0.45, "lean": -0.12}],
				[minf(h + 0.25, 0.9), {"hand_l": Vector3(-0.12, 1.42, -0.32), "twist": 0.2}],
				[1.0, {"hand_l": L, "hand_r": R, "twist": 0.0, "lean": 0.0}]]
		"kick":     # chamber the knee, snap the foot out, set it down
			return [[0.0, {"hand_r": Vector3(0.2, 1.38, -0.15), "hand_l": Vector3(-0.2, 1.38, -0.15), "foot_r": Vector3(0.13, 0.0, 0.0)}],
				[h * 0.6, {"foot_r": Vector3(0.13, 0.5, -0.25), "lean": 0.1}],
				[h, {"foot_r": Vector3(0.1, 0.95, -0.8), "lean": 0.28, "hand_r": Vector3(0.32, 1.25, 0.05), "hand_l": Vector3(-0.32, 1.3, -0.2)}],
				[minf(h + 0.3, 0.9), {"foot_r": Vector3(0.13, 0.35, -0.25), "lean": 0.1}],
				[1.0, {"foot_r": Vector3(0.13, 0.0, 0.0), "hand_r": R, "hand_l": L, "lean": 0.0}]]
	return [[0.0, {}], [1.0, {}]]


## The pose at time t: blend the two keys around it (smoothstep), carrying values forward from earlier keys.
func _sample(keys: Array, t: float) -> Dictionary:
	var acc := {}
	var prev: Dictionary = {}
	var prev_t := 0.0
	for k in keys:
		var kt: float = k[0]
		var kv: Dictionary = k[1]
		if kt <= t:
			for key in kv.keys():
				acc[key] = kv[key]
			prev = acc.duplicate()
			prev_t = kt
			continue
		var f := _smooth(clampf((t - prev_t) / maxf(kt - prev_t, 0.001), 0.0, 1.0))
		var out := prev.duplicate()
		for key in kv.keys():
			if prev.has(key):
				if prev[key] is Vector3:
					out[key] = (prev[key] as Vector3).lerp(kv[key], f)
				else:
					out[key] = lerpf(prev[key], kv[key], f)
		return out
	return acc


func _smooth(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


# ================================================================ the rig
## Two-bone IK: from root `a` toward target `t` with bone lengths l1, l2, bending toward `pole`.
## -> [joint (elbow / knee), end (hand / foot, pulled in if out of reach)].
static func ik(a: Vector3, t: Vector3, l1: float, l2: float, pole: Vector3) -> Array:
	var d := t - a
	var dist := clampf(d.length(), 0.05, (l1 + l2) * 0.998)
	var dir := d.normalized() if d.length() > 1e-4 else Vector3.DOWN
	var x := (l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist)
	var hgt := sqrt(maxf(l1 * l1 - x * x, 0.0))
	var pp := pole - dir * pole.dot(dir)
	if pp.length_squared() < 1e-6:
		pp = dir.cross(Vector3.RIGHT)
	var joint := a + dir * x + pp.normalized() * hgt
	return [joint, a + dir * dist]


func _arm(side: String, shoulder: Vector3, target: Vector3, pole: Vector3) -> Vector3:
	var r := ik(shoulder, target, UPPER_ARM, FOREARM, pole)
	var elbow: Vector3 = r[0]
	var hand: Vector3 = r[1]
	_place_seg("upper_" + side, shoulder, elbow, 0.065)
	_place_seg("fore_" + side, elbow, hand, 0.055)
	_place_ball("elbow_" + side, elbow, Vector3.ONE * 0.12)
	_place_ball("hand_" + side, hand, Vector3.ONE * 0.11)
	return hand


func _leg(side: String, hip: Vector3, foot: Vector3) -> void:
	var r := ik(hip, foot, THIGH, SHIN, Vector3(0, 0.2, -1))
	var knee: Vector3 = r[0]
	var ankle: Vector3 = r[1]
	_place_seg("thigh_" + side, hip, knee, 0.085)
	_place_seg("shin_" + side, knee, ankle, 0.07)
	_place_ball("knee_" + side, knee, Vector3.ONE * 0.15)
	var foot_mi: MeshInstance3D = parts["foot_" + side]
	foot_mi.transform = Transform3D(Basis.from_scale(Vector3(0.12, 0.08, 0.26)), ankle + Vector3(0, -0.04, -0.06))


## A cylinder or capsule part from a to b, radius r.
func _place_seg(nm: String, a: Vector3, b: Vector3, r: float) -> void:
	var mi: MeshInstance3D = parts[nm]
	var d := b - a
	var len := maxf(d.length(), 0.001)
	var y := d / len
	var x := y.cross(Vector3.FORWARD) if absf(y.dot(Vector3.FORWARD)) < 0.95 else y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	var h := len / (1.6 if nm == "chest" else 1.0)
	mi.transform = Transform3D(Basis(x * r * 2.0, y * h, z * r * 2.0), (a + b) / 2.0)


func _place_ball(nm: String, at: Vector3, size: Vector3, basis := Basis.IDENTITY) -> void:
	var mi: MeshInstance3D = parts[nm]
	mi.transform = Transform3D(basis * Basis.from_scale(size), at)


# ================================================================ weapons
func _update_held(w: int) -> void:
	if w == held_w:
		return
	if held != null:
		held.queue_free()
		held = null
	if _ammo != null:
		_ammo.queue_free()
		_ammo = null
	held = WeaponModels.for_weapon(w)
	if held != null:
		model.add_child(held)
		if w == Weapons.BOW:
			_ammo = WeaponModels._box(model, Vector3(0.02, 0.02, 0.75), Vector3.ZERO, WeaponModels.WOOD, 0.7)
			WeaponModels._box(_ammo, Vector3(0.04, 0.04, 0.08), Vector3(0, 0, -0.4), WeaponModels.STEEL_DARK, 0.5)
		elif w == Weapons.SLING:
			_ammo = WeaponModels._sphere(model, 0.05, Vector3.ZERO, WeaponModels.STONE)
	held_w = w


## The bow string (from the stave's tips) or the slingshot bands (from the prongs) to the drawing hand, plus the
## arrow on the string or the stone in the pouch while drawing.
func _draw_string(st: Sim.PlayerState, w: int, hand_r: Vector3) -> void:
	var drawing := st != null and st.charge > 0
	var tips: Array = []
	if w == Weapons.BOW:
		tips = [held.transform * Vector3(0, 0.62, 0), held.transform * Vector3(0, -0.62, 0)]
	elif w == Weapons.SLING:
		tips = [held.transform * Vector3(-0.1, 0.27, 0), held.transform * Vector3(0.1, 0.27, 0)]
	if tips.is_empty():
		_string_a.visible = false
		_string_b.visible = false
		return
	var pull_point: Vector3 = hand_r if drawing else (tips[0] + tips[1]) / 2.0
	if w == Weapons.BOW and not drawing:
		pull_point = (tips[0] + tips[1]) / 2.0
	for nm in ["string", "band_l", "band_r", "pouch"]:
		var n := held.get_node_or_null(nm)
		if n:
			n.visible = not drawing
	_string_a.visible = drawing
	_string_b.visible = drawing
	if drawing:
		_seg_line(_string_a, tips[0], pull_point, 0.006 if w == Weapons.BOW else 0.012)
		_seg_line(_string_b, tips[1], pull_point, 0.006 if w == Weapons.BOW else 0.012)
		(_string_a.material_override as StandardMaterial3D).albedo_color = WeaponModels.STRING if w == Weapons.BOW else WeaponModels.BAND
		(_string_b.material_override as StandardMaterial3D).albedo_color = WeaponModels.STRING if w == Weapons.BOW else WeaponModels.BAND
	if _ammo != null:
		_ammo.visible = drawing
		if drawing:
			var aim := (held.transform.origin - pull_point)
			aim.y = 0.0
			aim = aim.normalized() if aim.length() > 0.01 else Vector3.FORWARD
			if w == Weapons.BOW:
				var mid := pull_point + aim * 0.36
				_ammo.transform = Transform3D(Basis.looking_at(aim, Vector3.UP), mid)
			else:
				_ammo.position = pull_point


func _line_mesh(c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.5
	cy.bottom_radius = 0.5
	cy.height = 1.0
	cy.radial_segments = 4
	mi.mesh = cy
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.visible = false
	model.add_child(mi)
	return mi


func _seg_line(mi: MeshInstance3D, a: Vector3, b: Vector3, r: float) -> void:
	var d := b - a
	var len := maxf(d.length(), 0.001)
	var y := d / len
	var x := y.cross(Vector3.FORWARD) if absf(y.dot(Vector3.FORWARD)) < 0.95 else y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	mi.transform = Transform3D(Basis(x * r * 2.0, y * len, z * r * 2.0), (a + b) / 2.0)


## Slash trail on the tick the blow lands, matching the move.
func _swing_fx(st: Sim.PlayerState) -> void:
	if st == null or st.dead > 0 or not Weapons.is_melee(st.weapon) or st.atk == 0:
		return
	var mv := Weapons.move(st.weapon, st.combo)
	if st.atk > int(mv.swing) - int(mv.windup) + 1 or _slashed_n == st.swing_n:
		return
	_slashed_n = st.swing_n
	_trail(get_parent(), global_position, yaw, st.weapon, mv)


## Shared with Pip's avatar: the trail for a move.
static func _trail(parent: Node, pos: Vector3, yaw: float, weapon: int, mv: Dictionary) -> void:
	var sword := weapon == Weapons.SWORD
	var fists := weapon == Weapons.FISTS
	var col := Color(0.75, 0.9, 1.0, 0.95) if sword else (Color(1, 1, 1, 0.5) if fists else Color(1.0, 0.72, 0.4, 0.75))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	if mv.shape == "thrust":
		Fx.thrust(parent, pos, yaw, float(mv.range), col)
	elif mv.shape == "smash":
		Fx.slash(parent, pos, yaw, float(mv.range) * 0.85, 150.0, col, true)
		Fx.shockwave(parent, pos + fwd * 1.3, Color(1.0, 0.85, 0.6, 0.8))
		Fx.burst(parent, pos + fwd * 1.3, Vector3.UP, Color("c9a26b"), 18, 5.0, 0.07)
	else:
		Fx.slash(parent, pos, yaw, float(mv.range) * (0.95 if sword else 0.8), float(mv.arc), col, false,
			mv.name in ["backhand", "backslash"])
