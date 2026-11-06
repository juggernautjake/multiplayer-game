## The 3D test character, rigged and dressed: hips, a two-part spine (waist and chest), neck and head (eyes, brows,
## nose, ears, hair), shoulders, elbows, wrists and hands (with thumbs), hips, knees and booted feet; a tunic with a
## belt and flared hem. Arms and legs are two-bone IK chains, so every pose only says where hands and feet go.
##
## Animation is computed every frame from the player's state (no network traffic):
##   resting: breathing, a slow weight shift, a glance around now and then; weapons held naturally (sword at the
##     ready, club two-handed on the shoulder, bow low in the left hand, slingshot at the waist);
##   moving: feet step and plant, hips bob, free arms swing; in the air: knees tucked;
##   melee: keyframed wind-up, strike through the moment the hit lands, follow-through, recovery;
##   bow, as real archery: the body turns side-on to the target with the head kept on it, the bow arm comes up level,
##     the right elbow lifts and draws back to an anchor at the jaw; the bow's limbs flex with the draw (drawn live),
##     the arrow lies along the aim line; a long hold trembles; release snaps the string, the limbs spring and settle,
##     the hand follows through past the ear, then reaches back to the quiver for the next arrow;
##   slingshot: the fork held out at eye level, the pouch pinched and pulled back to the cheek, the bands stretching;
##     release snaps them forward with a wobble, then the hand reloads from the pouch on the belt.
## v0.8.0: strafing leans into the side it's going and backpedalling leans back; the head leads into turns; a crouch
## soaks up every landing (deeper the harder the fall) with a ring of dust, and it stretches up on take-off; in the air
## the free arms go out for balance; a dash drops the body low, sweeps the arms back and streaks speed lines; running
## feet kick up dust where they plant; no two swings are quite the same (each blow's height and body turn vary a
## little); the staff and wand move through each spell's own gesture (CastPose); and the wizard garb (WizardGarb):
## the robe recolours the tunic, sleeves and trousers, bell sleeves hang and swing from the forearms, and the cloth
## robe, hat and hood are simulated around the body.
## Same interface as Avatar (Pip): yaw, grounded, dashing, state, model, label, flash(), animate().
class_name FigureAvatar
extends Node3D

const SKIN := Color("f1c9a5")
const PANTS := Color("3b4252")
const BOOTS := Color("4a3426")
const BELT := Color("3a2618")
const HAIR := Color("6b4426")
const UPPER_ARM := 0.3
const FOREARM := 0.27
## v0.8.1: the shoulder joints sit at the outer ends of the collarbones, level with the base of the neck and a little
## below the top of the torso (they used to sit above it, like epaulettes); SHOULDER is that point in the chest's frame.
const SHOULDER := Vector3(0.215, 0.03, 0.0)
const SHOULDER_REST := Vector3(0.215, 1.42, 0.0)   # the same at rest, in the body's frame (for planning arm poses)
const PALM := 0.04             # the palm's centre, past the wrist along the forearm: where a handle sits
const THIGH := 0.43
const SHIN := 0.42
const BOW_HALF := 0.62         # half the bow's length
const DRAW_LEN := 0.68         # bow grip to anchor at full draw
const ARROW_RUN := 0.62        # v0.8.1: grip to anchor along the arrow in the archery stance

var yaw := 0.0
var grounded := true
var dashing := false
var state: Sim.PlayerState
var instant := false           # skip blending (pose previews)
var aim_pitch := 0.0           # set by Main for your own player: the archery stance tilts to where you aim

var model: Node3D              # everything in the body's frame (x right, y up, -z forward); hidden in first person
var label: Label3D
var hp_bar: Sprite3D
var zap_bar: Sprite3D        # v0.11.0: Static build-up (Avatar.static_bars)
var zap_back: Sprite3D
var _tumble := 0.0
var blob: MeshInstance3D
var held: Node3D               # club / sword / slingshot model (the bow is drawn live)
var held_w := -1
var parts := {}                # name -> MeshInstance3D
var _mats: Array = []
var _bow_segs: Array = []      # the bow stave, drawn live so its limbs can flex
var _string_a: MeshInstance3D  # bow string halves / slingshot bands
var _string_b: MeshInstance3D
var _arrow: Node3D             # the nocked arrow
var _stone: MeshInstance3D     # the stone in the slingshot pouch
var _pouch: MeshInstance3D
var _quiver: Node3D            # on the back while you have a bow
var _belt_bag: MeshInstance3D  # stones, on the belt while you have a slingshot

var _last := Vector3.ZERO
var _vel := Vector3.ZERO
var _have_last := false
var _phase := 0.0
var _t := 0.0
var _flash := 0.0
var _slashed_n := -1
var _shot_n := -1
var _release_t := 9.0          # seconds since the last release (limbs / bands spring)
var _release_pull := 0.0
var _last_pull := 0.0
var _hold_t := 0.0             # seconds at full draw (tremble)
# the smoothed pose
var _hand_r := Vector3(0.28, 1.0, -0.05)
var _hand_l := Vector3(-0.28, 1.0, -0.05)
var _pole_r := Vector3(0.2, -0.15, 1.0)
var _pole_l := Vector3(-0.2, -0.15, 1.0)
var _wdir := Vector3(0, 0, -1)
var _wroll := Vector3(1, 0, 0)
var _twist := 0.0
var _lean := 0.0
var _crouch := 0.0
var _foot_r := Vector3(0.12, 0.0, 0.0)
var _foot_l := Vector3(-0.12, 0.0, 0.0)
var _look := 0.0
var _along_r := Vector3.DOWN   # forearm directions (elbow -> wrist), for gripping
var _along_l := Vector3.DOWN
var last_hand_r := Vector3.ZERO   # palms and the weapon's grip this frame (pose previews mark them)
var last_hand_l := Vector3.ZERO
var last_grip := Vector3.ZERO
var _fight_t := 99.0           # seconds since the last attack (fists keep their guard up for a while)
# critically damped springs (Holden, "Spring-It-On"): velocities of the smoothed pose
var _v_hand_r := Vector3.ZERO
var _v_hand_l := Vector3.ZERO
var _v_twist := 0.0
var _v_lean := 0.0
var _v_crouch := 0.0
var _hitstop := 0.0            # seconds of hit-stop left (pose frozen)
var _hit_shake := false
var _accel_lean := 0.0
var _v_accel_lean := 0.0
var _bank := 0.0
var _last_vel := Vector3.ZERO
var _last_yaw := 0.0
var _prev_hand_r := Vector3.ZERO
var _was_grounded := true
var _fall_v := 0.0
var _plant_sign := 1.0
var _speed_line_t := 0.0
var _turn_look := 0.0
var _yaw_rate := 0.0
var _joints := {}              # knee_r, ankle_r, elbow_r, ... (body frame) this frame: the robe's colliders
var _garb: WizardGarb
var _garb_kind := 0
var _base_col := {}            # part -> its own colour (the robe recolours some)
var _sleeves := {}             # "r" / "l" -> [MeshInstance3D, hang direction]


var _name := ""


## PvP on: crossed swords by the name.
func set_pvp(on: bool) -> void:
	label.text = ("⚔ " if on else "") + _name


func _init(player_name: String, color: Color, show_name: bool, _outfit := 0) -> void:
	_name = player_name
	_accent_col = color.lightened(0.15)
	model = Node3D.new()
	add_child(model)
	var tunic := color
	var sleeve := color.darkened(0.12)
	var sphere_parts := ["head", "hair", "nose", "ear_l", "ear_r", "eyew_l", "eyew_r", "eye_l", "eye_r", "hand_r", "hand_l",
		"thumb_r", "thumb_l", "elbow_r", "elbow_l", "knee_r", "knee_l", "shoulder_r", "shoulder_l", "buckle"]
	var box_parts := ["foot_r", "foot_l", "brow_l", "brow_r"]
	for spec in [["pelvis", PANTS], ["waist", tunic.darkened(0.05)], ["chest", tunic], ["hem", tunic.darkened(0.08)],
			["belt", BELT], ["buckle", Color("d9b44a")], ["neck", SKIN], ["head", SKIN], ["hair", HAIR], ["nose", SKIN.darkened(0.05)],
			["ear_l", SKIN], ["ear_r", SKIN], ["eyew_l", Color.WHITE], ["eyew_r", Color.WHITE], ["eye_l", Color(0.1, 0.12, 0.2)],
			["eye_r", Color(0.1, 0.12, 0.2)], ["brow_l", HAIR], ["brow_r", HAIR],
			["trap_r", tunic], ["trap_l", tunic], ["upper_r", sleeve], ["upper_l", sleeve], ["fore_r", SKIN], ["fore_l", SKIN], ["elbow_r", SKIN], ["elbow_l", SKIN],
			["hand_r", SKIN], ["hand_l", SKIN], ["thumb_r", SKIN], ["thumb_l", SKIN], ["shoulder_r", tunic], ["shoulder_l", tunic],
			["thigh_r", PANTS], ["thigh_l", PANTS], ["shin_r", PANTS], ["shin_l", PANTS], ["knee_r", PANTS], ["knee_l", PANTS],
			["boot_r", BOOTS], ["boot_l", BOOTS], ["foot_r", BOOTS], ["foot_l", BOOTS]]:
		var nm: String = spec[0]
		var mi := MeshInstance3D.new()
		if nm in sphere_parts:
			var s := SphereMesh.new()
			s.radius = 0.5
			s.height = 1.0
			mi.mesh = s
		elif nm in box_parts:
			mi.mesh = BoxMesh.new()
		elif nm in ["chest", "waist", "pelvis"]:
			var c := CapsuleMesh.new()
			c.radius = 0.5
			c.height = 1.6
			mi.mesh = c
		elif nm in ["hem", "belt"]:
			var cy := CylinderMesh.new()
			cy.top_radius = 0.5 if nm == "belt" else 0.42
			cy.bottom_radius = 0.5
			cy.height = 1.0
			mi.mesh = cy
		else:
			var cy2 := CylinderMesh.new()
			cy2.top_radius = 0.5
			cy2.bottom_radius = 0.45 if nm.begins_with("fore") or nm.begins_with("shin") else 0.5
			cy2.height = 1.0
			mi.mesh = cy2
		var mat := StandardMaterial3D.new()
		mat.albedo_color = spec[1]
		mat.roughness = 0.85 if nm != "buckle" else 0.3
		mat.metallic = 0.6 if nm == "buckle" else 0.0
		mi.material_override = mat
		_mats.append([mat, spec[1]])
		_base_col[nm] = _mats.size() - 1
		model.add_child(mi)
		parts[nm] = mi
	_string_a = _line_mesh(WeaponModels.STRING)
	_string_b = _line_mesh(WeaponModels.STRING)
	for i in 10:
		_bow_segs.append(_line_mesh(WeaponModels.WOOD, true))
	_arrow = Node3D.new()
	model.add_child(_arrow)
	WeaponModels._box(_arrow, Vector3(0.016, 0.016, 0.78), Vector3(0, 0, -0.39), WeaponModels.WOOD, 0.7)
	WeaponModels._box(_arrow, Vector3(0.035, 0.035, 0.07), Vector3(0, 0, -0.8), WeaponModels.STEEL_DARK, 0.4, 0.6)
	WeaponModels._box(_arrow, Vector3(0.006, 0.05, 0.1), Vector3(0, 0, -0.04), WeaponModels.BAND, 0.8)
	WeaponModels._box(_arrow, Vector3(0.05, 0.006, 0.1), Vector3(0, 0, -0.04), WeaponModels.BAND, 0.8)
	_arrow.visible = false
	_stone = WeaponModels._sphere(model, 0.035, Vector3.ZERO, WeaponModels.STONE)
	_stone.visible = false
	_pouch = WeaponModels._box(model, Vector3(0.05, 0.035, 0.03), Vector3.ZERO, WeaponModels.LEATHER, 0.8)
	_pouch.visible = false
	_quiver = WeaponModels.quiver()
	model.add_child(_quiver)
	_quiver.visible = false
	_belt_bag = WeaponModels._box(model, Vector3(0.1, 0.12, 0.07), Vector3.ZERO, WeaponModels.LEATHER, 0.8)
	_belt_bag.visible = false

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
	var zb := Avatar.static_bars(self, img, 2.14)
	zap_back = zb[0]
	zap_bar = zb[1]
	_garb = WizardGarb.new()
	add_child(_garb)
	for sd in ["r", "l"]:   # bell sleeves, shown with a robe
		var sl := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.16      # the cuff: wide at the wrist (the +y end), narrow up the forearm
		cm.bottom_radius = 0.085
		cm.height = 1.0
		cm.radial_segments = 10
		sl.mesh = cm
		sl.material_override = WizardGarb._cloth_mat(WizardGarb.GREY)
		sl.visible = false
		model.add_child(sl)
		_sleeves[sd] = [sl, Vector3.DOWN]


func flash() -> void:
	_flash = 0.15


## Freeze the pose for a few frames when a hit lands (attacker and victim); the victim shakes.
func hitstop(seconds: float, shake: bool) -> void:
	_hitstop = maxf(_hitstop, seconds)
	_hit_shake = _hit_shake or shake


## Critically damped spring toward a goal, framerate independent. -> [value, velocity]
static func spring_v(x: Vector3, v: Vector3, goal: Vector3, halflife: float, dt: float) -> Array:
	var y := (4.0 * 0.6931 / maxf(halflife, 0.001)) / 2.0
	var j0 := x - goal
	var j1 := v + j0 * y
	var e := exp(-y * dt)
	return [e * (j0 + j1 * dt) + goal, e * (v - j1 * y * dt)]


static func spring_f(x: float, v: float, goal: float, halflife: float, dt: float) -> Array:
	var y := (4.0 * 0.6931 / maxf(halflife, 0.001)) / 2.0
	var j0 := x - goal
	var j1 := v + j0 * y
	var e := exp(-y * dt)
	return [e * (j0 + j1 * dt) + goal, e * (v - j1 * y * dt)]


# ================================================================ per frame
func animate(delta: float, _cam: Camera3D) -> void:
	if _hitstop > 0.0:   # the pose holds still on impact; the victim shakes
		_hitstop -= delta
		model.position.x = randf_range(-0.02, 0.02) if _hit_shake else 0.0
		if _hitstop <= 0.0:
			model.position.x = 0.0
			_hit_shake = false
		return
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
	_track_release(st, w, delta)

	_fight_t = 0.0 if st != null and st.atk > 0 else _fight_t + delta
	var pose := _pose(st, speed)
	var a := 1.0 if instant else clampf(delta * (30.0 if pose.get("snap", false) else 12.0), 0.0, 1.0)
	# hands, torso: critically damped springs (snappy into attacks, softer settling back)
	var hl := 0.025 if pose.get("snap", false) else 0.1
	if instant:
		_hand_r = pose.hand_r
		_hand_l = pose.hand_l
	else:
		var sr := spring_v(_hand_r, _v_hand_r, pose.hand_r, hl, delta)
		_hand_r = sr[0]
		_v_hand_r = sr[1]
		var sl := spring_v(_hand_l, _v_hand_l, pose.hand_l, hl * 1.2, delta)   # the off hand lags a touch (overlap)
		_hand_l = sl[0]
		_v_hand_l = sl[1]
	_pole_r = _pole_r.lerp(pose.get("pole_r", Vector3(0.2, -0.15, 1.0)), a)   # elbows point back, a little out
	_pole_l = _pole_l.lerp(pose.get("pole_l", Vector3(-0.2, -0.15, 1.0)), a)
	var wd: Vector3 = (pose.wdir as Vector3).normalized()
	var wdot := _wdir.normalized().dot(wd)
	# (nearly the same way already: no slerp; its rotation axis would be a cross product too tiny to normalize)
	_wdir = _wdir.normalized().slerp(wd, a).normalized() if wdot > -0.99 and wdot < 0.99999 else wd
	_wroll = _wroll.lerp(pose.wroll, a).normalized()
	if instant:
		_twist = pose.twist
		_lean = pose.lean
		_crouch = pose.crouch
	else:
		var tw := spring_f(_twist, _v_twist, pose.twist, hl * 0.9, delta)   # the hips lead
		_twist = tw[0]
		_v_twist = tw[1]
		var ln := spring_f(_lean, _v_lean, pose.lean, 0.1, delta)
		_lean = ln[0]
		_v_lean = ln[1]
		var cr := spring_f(_crouch, _v_crouch, pose.crouch, 0.08, delta)
		_crouch = cr[0]
		_v_crouch = cr[1]
	_look = lerpf(_look, pose.look, a if pose.has("aim") else (clampf(delta * 3.0, 0.0, 1.0) if not instant else 1.0))

	# ---- feet
	# stride locked to the distance covered (no foot sliding): one full cycle covers `stride_full` metres
	var stride_full := clampf(1.3 + 0.16 * speed, 1.3, 2.9)
	var stride := stride_full * 0.5 if speed > 0.3 else 0.0   # each foot sweeps half the cycle length
	var run := clampf((speed - Sim.WALK_SPEED * 0.6) / (Sim.SPRINT_SPEED - Sim.WALK_SPEED * 0.6), 0.0, 1.0)
	var lift := (0.11 + 0.12 * run) * clampf(speed / 1.5, 0.0, 1.0)
	var fwd_dir := Vector2(local_vel.x, local_vel.z)
	fwd_dir = fwd_dir.normalized() if fwd_dir.length() > 0.2 else Vector2(0, -1)
	if grounded and speed > 0.3:
		_phase += TAU * speed * delta / stride_full
	# leaning: forward with speed, into acceleration, banking into turns (all smoothed)
	if delta > 0.0 and not instant:
		var acc := global_transform.basis.inverse() * ((_vel - _last_vel) / delta)
		var al := spring_f(_accel_lean, _v_accel_lean, clampf(-acc.z * 0.03, -0.26, 0.26), 0.1, delta)
		_accel_lean = al[0]
		_v_accel_lean = al[1]
		var yaw_rate := wrapf(yaw - _last_yaw, -PI, PI) / delta
		_yaw_rate = yaw_rate
		_bank = lerpf(_bank, clampf(atan(speed * yaw_rate / 9.8), -0.35, 0.35), clampf(delta * 8.0, 0.0, 1.0))
	_last_vel = _vel
	_last_yaw = yaw
	var stance := 0.13 + (0.05 if pose.has("aim") else 0.0)   # archers stand a little wider
	var fr := _step_foot(_phase, stride, lift, fwd_dir, stance)
	var fl := _step_foot(_phase + PI, stride, lift, fwd_dir, -stance)
	if pose.has("aim") and speed < 0.3:   # side-on stance: front foot forward
		fl = Vector3(-0.16, 0.0, -0.14)
		fr = Vector3(0.16, 0.0, 0.12)
	if not grounded:
		fr = Vector3(0.13, 0.42, -0.12)
		fl = Vector3(-0.13, 0.3, 0.12)
	if pose.has("foot_r"):
		fr = pose.foot_r
	if pose.has("foot_l"):
		fl = pose.foot_l
	var fa := 1.0 if instant else clampf(delta * 20.0, 0.0, 1.0)
	_foot_r = _foot_r.lerp(fr, fa)
	_foot_l = _foot_l.lerp(fl, fa)
	# take-off stretches up; landing sinks into a crouch by how hard it came down, with dust
	if not instant:
		if not grounded:
			if _was_grounded:
				_v_crouch -= 1.4
			_fall_v = maxf(_fall_v, -_vel.y)
		elif not _was_grounded:
			_v_crouch += clampf(_fall_v * 0.09, 0.4, 2.2)
			if _fall_v > 4.0 and model.visible and get_parent() != null:
				MotionFx.land(get_parent(), position, clampf(_fall_v / 14.0, 0.3, 1.4))
			_fall_v = 0.0
		_was_grounded = grounded
		# running feet kick up dust where they plant
		var plant := signf(sin(_phase))
		if grounded and speed > Sim.WALK_SPEED * 0.9 and plant != _plant_sign and model.visible and get_parent() != null:
			var foot := _foot_l if plant > 0.0 else _foot_r
			MotionFx.puff(get_parent(), global_transform * foot, 2, 0.5)
		_plant_sign = plant
		if dashing and model.visible and get_parent() != null:
			_speed_line_t -= delta
			if _speed_line_t <= 0.0:
				_speed_line_t = 0.04
				MotionFx.speed_lines(get_parent(), position, _vel, label.modulate)

	# ---- the skeleton: pelvis, waist, chest (the twist and lean spread over both), neck, head
	var dead := st != null and st.dead > 0
	# v0.11.0 knocked down: tumbling through the air, flat on the ground, then pushing up onto the feet; stunned: dizzy
	var downed := st != null and st.down > 0 and not dead
	var lie := -PI / 2.0 if dead else 0.0
	var lie_y := 0.25 if dead else 0.0
	if downed:
		if not grounded:
			_tumble -= delta * 9.0
			lie = -PI / 2.0 + _tumble
		else:
			_tumble = 0.0
			var up := 1.0 - clampf(float(st.down) / Sim.DOWN_GETUP, 0.0, 1.0)
			lie = -PI / 2.0 * (1.0 - _smooth(up))
			lie_y = 0.25 * (1.0 - up)
			_crouch = maxf(_crouch, 0.35 * sin(up * PI))
	else:
		_tumble = 0.0
	if downed and not grounded:
		model.rotation.x = lie
	else:
		model.rotation.x = lerpf(model.rotation.x, lie, a)
	model.position.y = lerpf(model.position.y, lie_y, a)
	var dizzy := st != null and st.stun > 0 and not dead
	model.rotation.z = sin(_t * 5.0) * 0.1 if dizzy else lerpf(model.rotation.z, 0.0, a)
	dead = dead or downed
	var breathe := sin(_t * 1.6) * 0.01                                    # ~15 breaths a minute
	var moving := clampf(speed / 1.5, 0.0, 1.0) if grounded else 0.0
	var idle_shift := sin(_t * 0.9) * sin(_t * 0.31) * 0.03 * (1.0 - moving)   # a slow weight shift now and then
	# walking: hips highest at mid-stance (twice a cycle), swaying toward the standing leg, turning with the swinging
	# leg; running: the bob flips (lowest at stance) and grows, the sway shrinks
	var bob := (-cos(2.0 * _phase) * lerpf(0.025, -0.04, run)) * moving
	var sway := -sin(_phase) * lerpf(0.025, 0.008, run) * moving + idle_shift
	var hip_yaw := sin(_phase) * lerpf(0.1, 0.14, run) * moving
	var chest_yaw := -sin(_phase) * lerpf(0.12, 0.22, run) * moving   # the chest counter-rotates
	var fwd_frac := clampf(-local_vel.z / maxf(speed, 0.1), -1.0, 1.0)   # 1 straight ahead, -1 backpedalling
	var side_frac := clampf(local_vel.x / maxf(speed, 0.1), -1.0, 1.0)   # strafing right +, left -
	var speed_lean := lerpf(0.05, 0.2, clampf(speed / Sim.SPRINT_SPEED, 0.0, 1.0)) * moving * clampf(fwd_frac, -0.6, 1.0) + (0.4 if dashing else 0.0)
	var run_lean := speed_lean + _accel_lean
	var strafe_tilt := -side_frac * 0.13 * moving   # leaning into the side it's stepping toward
	if not instant and delta > 0.0:
		_turn_look = lerpf(_turn_look, clampf(_yaw_rate * 0.09, -0.45, 0.45), clampf(delta * 10.0, 0.0, 1.0))
	var pelvis := Vector3(sway, 0.95 - _crouch + bob, 0)
	var low := Basis(Vector3.UP, _twist * 0.3 + hip_yaw) * Basis(Vector3.BACK, (_bank + strafe_tilt) * 0.5) * Basis(Vector3.RIGHT, (_lean - run_lean) * 0.5)
	var spine := Basis(Vector3.UP, _twist + chest_yaw) * Basis(Vector3.BACK, _bank + strafe_tilt) * Basis(Vector3.RIGHT, _lean - run_lean)
	var waist := pelvis + low * Vector3(0, 0.2, 0)
	var chest := waist + spine * Vector3(0, 0.24 + breathe, 0)
	var sh_r := chest + spine * SHOULDER
	var sh_l := chest + spine * Vector3(-SHOULDER.x, SHOULDER.y, SHOULDER.z)
	# clavicles: the shoulder shrugs up when its arm goes high and reaches forward on a punch or thrust
	for side in [[1.0, _hand_r], [-1.0, _hand_l]]:
		var hnd: Vector3 = side[1]
		var shp := sh_r if side[0] > 0 else sh_l
		var up := clampf((hnd.y - shp.y) * 0.1, -0.01, 0.04)
		var fwd := clampf((-(hnd.z - shp.z) - 0.25) * 0.18, 0.0, 0.05)
		shp += Vector3(0, up, -fwd)
		if side[0] > 0:
			sh_r = shp
		else:
			sh_l = shp
	var neck := chest + spine * Vector3(0, 0.17, 0)
	# the head stays steady: it undoes most of the gait's twist and keeps looking ahead
	var head_basis := Basis(Vector3.UP, _twist + _look + _turn_look - chest_yaw * 0.8) * Basis(Vector3.RIGHT, (_lean - run_lean) * 0.3)
	var head := neck + head_basis * Vector3(0, 0.15, 0)
	var hip_r := pelvis + low * Vector3(0.1, -0.04, 0)
	var hip_l := pelvis + low * Vector3(-0.1, -0.04, 0)

	_place_ball("pelvis", pelvis, Vector3(0.32, 0.16, 0.2), low)
	_place_seg("waist", pelvis + low * Vector3(0, 0.02, 0), waist, 0.14, 1.2)
	_place_seg("chest", waist, chest + spine * Vector3(0, 0.08, 0), 0.18, 1.38, spine)
	_place_seg("hem", pelvis + low * Vector3(0, -0.12, 0), pelvis + low * Vector3(0, 0.06, 0), 0.19, 1.15)
	_place_seg("belt", pelvis + low * Vector3(0, 0.06, 0), pelvis + low * Vector3(0, 0.11, 0), 0.172, 1.15)
	_place_ball("buckle", pelvis + low * Vector3(0, 0.085, -0.17), Vector3(0.06, 0.05, 0.03), low)
	_place_seg("neck", neck - spine * Vector3(0, 0.06, 0), head - head_basis * Vector3(0, 0.1, 0), 0.06)
	_place_ball("head", head, Vector3(0.33, 0.35, 0.33), head_basis)
	_place_ball("hair", head + head_basis * Vector3(0, 0.065, 0.035), Vector3(0.345, 0.27, 0.345), head_basis)
	_place_ball("nose", head + head_basis * Vector3(0, -0.01, -0.15), Vector3(0.04, 0.05, 0.05), head_basis)
	for s in [-1.0, 1.0]:
		var sd := "l" if s < 0 else "r"
		_place_ball("ear_" + sd, head + head_basis * Vector3(s * 0.15, 0.0, 0.01), Vector3(0.04, 0.07, 0.05), head_basis)
		_place_ball("eyew_" + sd, head + head_basis * Vector3(s * 0.055, 0.025, -0.13), Vector3(0.055, 0.05, 0.03), head_basis)
		_place_ball("eye_" + sd, head + head_basis * Vector3(s * 0.055, 0.025, -0.143), Vector3(0.03, 0.035, 0.02), head_basis)
		_place_ball("brow_" + sd, head + head_basis * Vector3(s * 0.058, 0.07, -0.135), Vector3(0.06, 0.012, 0.02), head_basis)
	# the deltoid caps the joint and the trapezius slopes from the neck down to it, so the arm grows out of the torso
	var nb := chest + spine * Vector3(0, 0.1, 0)
	for sd in [["r", sh_r, 1.0], ["l", sh_l, -1.0]]:
		var shp: Vector3 = sd[1]
		var arm_dir := ((_hand_r if sd[0] == "r" else _hand_l) - shp).normalized()
		var delt := shp + spine * Vector3(0.025 * float(sd[2]), -0.01, 0) + arm_dir * 0.03
		_place_ball("shoulder_" + sd[0], delt, Vector3(0.135, 0.15, 0.135), spine)
		_place_seg("trap_" + sd[0], nb + spine * Vector3(0.04 * float(sd[2]), 0.0, 0.01), shp + spine * Vector3(-0.01 * float(sd[2]), 0.035, 0.0), 0.05, 1.0, spine)
	var hand_r := _arm("r", sh_r, _hand_r, _pole_r)
	var hand_l := _arm("l", sh_l, _hand_l, _pole_l)
	_leg("r", hip_r, _foot_r + Vector3(0, 0.07, 0))
	_leg("l", hip_l, _foot_l + Vector3(0, 0.07, 0))

	# ---- gear on the body
	var have_bow := st != null and (st.owned >> Weapons.BOW) & 1 == 1
	var have_sling := st != null and (st.owned >> Weapons.SLING) & 1 == 1
	_quiver.visible = have_bow and not dead
	if _quiver.visible:   # on the back, slanting up over the right shoulder
		var qb := spine * Basis(Vector3.BACK, -0.35)
		_quiver.transform = Transform3D(qb, chest + spine * Vector3(0.06, -0.3, 0.17))
	_belt_bag.visible = have_sling and not dead
	if _belt_bag.visible:
		_belt_bag.transform = Transform3D(low, pelvis + low * Vector3(0.18, 0.02, -0.06))

	# ---- the weapon in hand
	var palm_r := hand_r + _along_r * PALM
	var palm_l := hand_l + _along_l * PALM
	last_hand_r = palm_r
	last_hand_l = palm_l
	_draw_weapon(st, w, palm_r, palm_l, dead, pose)
	_dress(delta, st, pelvis, low, neck, head, head_basis, hip_r, hip_l, dead, chest, spine)

	_swing_fx(st)
	_flash = maxf(_flash - delta, 0.0)
	for mc in _mats:
		(mc[0] as StandardMaterial3D).albedo_color = Color(1, 0.4, 0.4) if _flash > 0.0 else mc[1]
	if st != null:
		var hpk := float(st.hp) / float(Sim.MAX_HP)
		hp_bar.scale.x = maxf(0.9 * hpk, 0.001)
		hp_bar.modulate = Color(0.9, 0.2, 0.2).lerp(Color(0.3, 0.9, 0.3), hpk)
		hp_bar.visible = label.visible and st.dead == 0
		Avatar.show_static(zap_back, zap_bar, st, label.visible)
	var ground := WorldLayout.ground_height(position.x, position.z, position.y)
	blob.global_position = Vector3(position.x, ground + 0.012, position.z)
	var bs := clampf(1.0 - (position.y - ground) / 6.0, 0.35, 1.0)
	blob.scale = Vector3(bs, 1, bs)


## A foot's place in its step cycle: forward through the air when sin(phase) > 0, planted and sliding back otherwise.
func _step_foot(ph: float, stride: float, lift: float, dir: Vector2, side: float) -> Vector3:
	var along := cos(ph) * stride * 0.5
	var up := maxf(sin(ph), 0.0) * lift
	return Vector3(side - dir.x * along, up, -dir.y * along)


## Notice a release (bow string / slingshot bands spring) and how long a full draw has been held.
func _track_release(st: Sim.PlayerState, w: int, delta: float) -> void:
	_release_t += delta
	if st == null or not Weapons.is_ranged(w):
		_last_pull = 0.0
		return
	var d := Weapons.get_data(w)
	var pull := clampf(float(st.charge) / float(d.draw), 0.0, 1.0)
	if st.swing_n != _shot_n:
		if _shot_n != -1 and st.charge == 0:
			_release_t = 0.0
			_release_pull = maxf(_last_pull, 0.3)
		_shot_n = st.swing_n
	_hold_t = _hold_t + delta if pull >= 1.0 else 0.0
	_last_pull = pull


# ================================================================ poses
## Where the hands go (body frame), the weapon's direction and the way its flat faces, torso twist and lean, hip
## drop, head turn, the right elbow's pole, and a right-foot target for kicks. "aim" marks the archery stance.
func _pose(st: Sim.PlayerState, speed: float) -> Dictionary:
	var mv_k := clampf(speed / 1.5, 0.0, 1.0) if grounded else 0.0
	var run := clampf((speed - Sim.WALK_SPEED * 0.6) / (Sim.SPRINT_SPEED - Sim.WALK_SPEED * 0.6), 0.0, 1.0)
	# each arm swings with the opposite leg (the right arm forward while the right foot is back)
	var swing := cos(_phase) * lerpf(0.2, 0.32, run) * mv_k
	var glance := sin(_t * 0.37) * sin(_t * 0.23) * 0.22 * (1.0 - clampf(speed, 0.0, 1.0))   # an idle look around
	# the free arms, as a person's: swinging from the shoulder opposite to the legs (about 15 degrees each way when
	# walking, 30 running), the elbows relaxed and slightly bent at rest, bending toward 80-90 degrees at a run;
	# strafing swings them less; they hang a touch out from the body so they clear the hips (and a robe)
	var local_v := global_transform.basis.inverse() * _vel if is_inside_tree() else Vector3.ZERO
	var sidestep := clampf(absf(local_v.x) / maxf(speed, 0.1), 0.0, 1.0)
	var amp := lerpf(0.26, 0.5, run) * mv_k * (1.0 - 0.6 * sidestep)
	var bend := lerpf(0.28 + 0.22 * mv_k, 1.45, run * mv_k)
	var breath := 0.03 * sin(_t * 1.6) * (1.0 - mv_k)
	var ar := arm_fk(1.0, amp * cos(_phase) + 0.05 + breath, bend, 0.1)
	var al := arm_fk(-1.0, -amp * cos(_phase) + 0.05 + breath, bend, 0.1)
	var p := { "hand_r": ar[1], "hand_l": al[1], "pole_r": ar[2], "pole_l": al[2],
		"wdir": Vector3(0, -0.3, -1), "wroll": Vector3(1, 0, 0), "twist": 0.0, "lean": 0.0, "crouch": 0.0, "look": glance }
	if st == null or st.dead > 0 or st.down > 0:
		return p
	var w := st.weapon
	var free_l := w in [Weapons.FISTS, Weapons.SWORD, Weapons.STAFF, Weapons.WAND]
	if not grounded and st.atk == 0 and st.charge == 0:   # in the air: the free arms lift a little out for balance
		var up_l := arm_fk(-1.0, 0.25, 0.7, 0.45)
		if free_l:
			p.hand_l = up_l[1]
			p.pole_l = up_l[2]
		if w == Weapons.FISTS:
			var up_r := arm_fk(1.0, 0.15, 0.75, 0.45)
			p.hand_r = up_r[1]
			p.pole_r = up_r[2]
	if dashing and st.atk == 0 and st.charge == 0:          # a dash: low, the arms trailing back, elbows soft
		p.crouch = 0.12
		var dl := arm_fk(-1.0, -0.55, 0.45, 0.18)
		if free_l:
			p.hand_l = dl[1]
			p.pole_l = dl[2]
		if w == Weapons.FISTS:
			var dr := arm_fk(1.0, -0.55, 0.45, 0.18)
			p.hand_r = dr[1]
			p.pole_r = dr[2]
	match w:
		Weapons.FISTS:   # after a punch, the guard stays up a while: fists by the chin, elbows in, knees soft
			if _fight_t < 3.0 and speed < Sim.SPRINT_SPEED:
				p.hand_l = Vector3(-0.1, 1.5, -0.3)
				p.hand_r = Vector3(0.14, 1.46, -0.2)
				p.twist = -0.15
				p.crouch = 0.05
				p.pole_r = Vector3(0.3, -1.0, 0.4)
				p.guard = true
		Weapons.SWORD:   # at the ready: blade forward and a little up, the free arm loose
			p.hand_r = Vector3(0.24, 1.08, -0.28 - swing * 0.3)
			p.wdir = Vector3(-0.15, 0.35, -1.0)
		Weapons.CLUB:    # two-handed, resting on the right shoulder
			p.hand_r = Vector3(0.18, 1.25, -0.22)
			p.hand_l = Vector3(0.08, 1.1, -0.26)
			p.wdir = Vector3(0.2, 0.75, 0.6)
		Weapons.BOW:     # held low in the left hand, stave slanting forward
			p.hand_l = Vector3(-0.28, 1.02, -0.14 + swing)
			p.wdir = Vector3(0.1, 0.9, -0.45)
		Weapons.SLING:   # fork up in the left hand at the waist
			p.hand_l = Vector3(-0.24, 1.05, -0.22 + swing)
			p.wdir = Vector3(0, 1.0, -0.25)
		Weapons.STAFF:   # the staff upright in the right hand, like a walking stick
			p.hand_r = Vector3(0.3, 1.02, -0.18 - swing * 0.2)
			p.wdir = Vector3(0, 1.0, -0.12)
		Weapons.WAND:	# the wand held low, pointing ahead
			p.hand_r = Vector3(0.26, 1.0, -0.26 - swing * 0.3)
			p.wdir = Vector3(0, 0.2, -1.0)

	# a hand placed for a weapon: its elbow points back and a little out (not where the free swing put it)
	if w in [Weapons.SWORD, Weapons.CLUB, Weapons.STAFF, Weapons.WAND]:
		p.pole_r = Vector3(0.3, -0.2, 1.0)
	if w in [Weapons.CLUB, Weapons.BOW, Weapons.SLING]:
		p.pole_l = Vector3(-0.3, -0.2, 1.0)
	if Weapons.is_melee(w) and st.atk > 0:
		var mv := Weapons.move(w, st.combo)
		var t := 1.0 - float(st.atk) / float(mv.swing)
		var h := float(mv.windup) / float(mv.swing)
		var keys := _move_keys(mv.name, h, p)
		var frame := 1.0 / float(mv.swing)
		var k := _sample(keys, t, h)
		# no two blows quite alike: each swing (by its number) lands a little higher or lower and turns a little more
		var n := float(st.swing_n)
		var bell := sin(clampf(t, 0.0, 1.0) * PI)
		if k.has("hand_r"):
			k.hand_r = (k.hand_r as Vector3) + Vector3(0, sin(n * 12.9898) * 0.07, sin(n * 4.1414) * 0.04) * bell
		if k.has("twist"):
			k.twist = float(k.twist) + sin(n * 7.233) * 0.09 * bell
		# the kinetic chain: the body leads the arms by ~2 frames, the weapon trails the hand by ~1
		var kb := _sample(keys, minf(t + 2.0 * frame, 1.0), h)
		for key in ["twist", "lean", "crouch", "foot_r", "foot_l"]:
			if kb.has(key):
				k[key] = kb[key]
		var kw := _sample(keys, maxf(t - frame, 0.0), h)
		if kw.has("wdir"):
			k.wdir = kw.wdir
		for key in k.keys():
			p[key] = k[key]
		p.snap = true
		# the blade's edge faces the way it's travelling through the strike
		if w == Weapons.SWORD and t > h * 0.8 and t < h + 0.3:
			var hv := (p.hand_r as Vector3) - _prev_hand_r
			var wd := (p.wdir as Vector3).normalized()
			var edge := hv - wd * hv.dot(wd)
			if edge.length() > 0.002:
				p.wroll = edge.normalized().cross(wd).normalized()
		_prev_hand_r = p.hand_r
		if not p.has("foot_l") and speed < 0.5:   # step the lead foot into the strike, settle back after
			var step := _smooth(clampf(t / maxf(h, 0.01), 0.0, 1.0)) * (1.0 - _smooth(clampf((t - h - 0.3) / 0.4, 0.0, 1.0)))
			p.foot_l = Vector3(-0.15, 0.0, -0.05 - 0.22 * step)
			p.crouch = float(p.get("crouch", 0.0)) + 0.05 * step
		if w == Weapons.CLUB:
			p.hand_l = p.hand_r - (p.wdir as Vector3).normalized() * 0.14 + Vector3(-0.04, 0, 0)
		return p

	if Weapons.is_magic(w):   # staff upright / wand pointing; casting thrusts it forward and up
		if st.shield > 0:   # holding the shield up: the staff raised high overhead, the free hand up too
			p.hand_r = Vector3(0.12, 1.86, -0.3)   # the orb at the top of the bubble (it pours out of it)
			p.wdir = Vector3(0, 1.0, -0.15)
			p.hand_l = Vector3(-0.22, 1.7, -0.36)
			p.lean = -0.05
			return p
		if st.atk > 0:   # each spell's own gesture (CastPose): wind up, release with overshoot, follow through
			var sp := Weapons.spell(w, st.spell)
			var c := CastPose.at(w, str(sp.name), float(int(sp.cast) - st.atk), float(sp.windup), float(sp.cast))
			var aim := float(c.aim)
			p.wdir = Vector3(0, cos(aim), -sin(aim))
			p.hand_r = Vector3(0.24 + float(c.side), 1.12 + float(c.lift), -0.24 - 0.42 * float(c.reach))
			p.lean = -float(c.lean)
			p.crouch = float(c.crouch)
			p.twist = -0.2
			if c.two_hand:   # the free hand joins lower on the staff
				p.hand_l = (p.hand_r as Vector3) - (p.wdir as Vector3).normalized() * 0.28 + Vector3(-0.06, 0, 0)
			else:            # the free hand opens out with the gesture
				p.hand_l = Vector3(-0.3, 1.15 + float(c.lift) * 0.7, -0.25 - 0.25 * float(c.reach))
			p.snap = float(c.flare) > 1.0
		return p
	if not Weapons.is_melee(w):
		var d := Weapons.get_data(w)
		var pull := clampf(float(st.charge) / float(d.draw), 0.0, 1.0)
		var drawing := st.charge > 0
		var releasing := not drawing and st.atk > 0
		var reloading := not drawing and st.atk == 0 and st.atk_cd > 0
		if not (drawing or releasing or reloading):
			return p
		# v0.8.1, a real archery stance: side-on to the target (the left shoulder leads), the head turned to look straight
		# along the arrow; the arrow line runs level with the jaw, to the right of the face with room to spare, from
		# the bow hand (out in front at shoulder height) back to an anchor at the side of the jaw. The whole line tilts
		# with where you aim (up or down; your own player only: others' aim isn't sent). It used to run through the
		# head and neck.
		p.aim = true
		p.twist = -0.95
		p.look = 0.95
		var tilt := Basis(Vector3.RIGHT, clampf(aim_pitch, -0.9, 0.9))
		var pivot := Vector3(0.0, 1.52, 0.0)
		var anchor := pivot + tilt * (Vector3(0.17, 1.57, 0.03) - pivot)
		var grip := pivot + tilt * (Vector3(0.17, 1.57, 0.03 - ARROW_RUN) - pivot)
		p.hand_l = grip
		if _hold_t > 0.8:   # holding a full draw: the arms start to tremble
			var tr := sin(_t * 41.0) * 0.004 + sin(_t * 23.0) * 0.003
			p.hand_l += Vector3(tr, tr * 0.6, 0)
		p.pole_r = Vector3(1.0, 0.55, 1.0)   # drawing elbow high and back
		if w == Weapons.BOW:
			p.wdir = tilt * Vector3(0.25, 1.0, 0.0)   # stave up, canted away from the face so the string clears it
			p.wroll = Vector3(0, 0, 1)
			var nock := grip + Vector3(0.0, 0.0, 0.12)
			if drawing:
				p.hand_r = nock.lerp(anchor, _ease_draw(pull))
			elif releasing:   # the hand recoils back along the jaw past the ear; the bow arm kicks and settles
				var f := clampf(1.0 - float(st.atk) / float(d.shot), 0.0, 1.0)
				p.hand_r = anchor + Vector3(0.08, 0.03, 0.14) * (1.0 - pow(1.0 - minf(f * 3.0, 1.0), 3.0))
				p.hand_l = grip + Vector3(0, -0.035, -0.02) * exp(-f * 5.0) * sin(minf(f * 8.0, PI))
				p.snap = true
			else:             # reach back to the quiver over the right shoulder, then come back to the string
				var f := 1.0 - float(st.atk_cd) / float(int(d.cooldown) - int(d.shot))
				var quiver := Vector3(0.14, 1.72, 0.2)
				p.hand_r = anchor.lerp(quiver, _smooth(clampf(f * 2.2, 0.0, 1.0))) if f < 0.5 else quiver.lerp(nock, _smooth(clampf((f - 0.5) * 2.2, 0.0, 1.0)))
				p.pole_r = Vector3(1.0, 0.2, 0.6)
		else:
			p.hand_l = grip + Vector3(0, -0.02, 0)
			p.wdir = Vector3(0, 1.0, -0.12)
			p.wroll = Vector3(1, 0, 0)
			var fork := grip + Vector3(0.0, 0.25, 0.02)
			if drawing:
				p.hand_r = fork.lerp(anchor + Vector3(0, -0.02, 0), _ease_draw(pull))
			elif releasing:
				var f := clampf(1.0 - float(st.atk) / float(d.shot), 0.0, 1.0)
				p.hand_r = anchor + Vector3(0.12, -0.02, 0.12) * _smooth(minf(f * 3.0, 1.0))
				p.snap = true
			else:             # a stone from the belt pouch, back to the fork
				var f := 1.0 - float(st.atk_cd) / maxf(float(int(d.cooldown) - int(d.shot)), 1.0)
				var bag := Vector3(0.24, 1.0, -0.06)
				p.hand_r = anchor.lerp(bag, _smooth(clampf(f * 2.2, 0.0, 1.0))) if f < 0.5 else bag.lerp(fork, _smooth(clampf((f - 0.5) * 2.2, 0.0, 1.0)))
				p.pole_r = Vector3(0.8, -0.6, 0.6)
	return p


## An arm posed from angles, as a person moves one (body frame): `swing` forward (+) or back (-) at the shoulder,
## `bend` at the elbow (0 straight, ~1.5 a right angle; the forearm comes forward), `out` away from the body.
## -> [elbow, hand, the elbow's pole for the IK] for side 1 (right) or -1 (left).
static func arm_fk(side: float, swing: float, bend: float, out: float) -> Array:
	var sh := Vector3(SHOULDER_REST.x * side, SHOULDER_REST.y, 0)
	var up_dir := Vector3(sin(out) * side, -cos(out) * cos(swing), -cos(out) * sin(swing))
	var elbow := sh + up_dir * UPPER_ARM
	var fa := swing + clampf(bend, 0.0, 2.4)
	var fore := Vector3(sin(out) * side * 0.6, -cos(fa), -sin(fa)).normalized()
	var hand := elbow + fore * FOREARM
	return [elbow, hand, (elbow - (sh + hand) * 0.5).normalized() + Vector3(0.15 * side, 0, 0.2)]


## The draw speeds up then settles into the anchor, like pulling against a stiffening bow.
func _ease_draw(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 2.2)


## Keyframes for each melee move: [time, values...]. Times 0..1 through the move; `h` is when the blow lands.
func _move_keys(name: String, h: float, rest: Dictionary) -> Array:
	var R: Vector3 = rest.hand_r
	var L: Vector3 = rest.hand_l
	match name:
		"slash":
			return [[0.0, {"hand_r": Vector3(0.38, 1.5, 0.1), "wdir": Vector3(0.55, 0.55, 0.65), "wroll": Vector3(0, 1, 0), "twist": -0.55, "hand_l": Vector3(-0.3, 1.15, -0.2)}],
				[h, {"hand_r": Vector3(0.02, 1.28, -0.58), "wdir": Vector3(-1.0, 0.05, -0.55), "wroll": Vector3(0, 1, 0), "twist": 0.3, "lean": -0.12}],
				[minf(h + 0.28, 0.9), {"hand_r": Vector3(-0.36, 1.08, -0.28), "wdir": Vector3(-0.8, -0.35, 0.45), "wroll": Vector3(0, 1, 0), "twist": 0.65, "lean": -0.15}],
				[1.0, {"hand_r": R, "wdir": rest.wdir, "wroll": rest.wroll, "twist": 0.0, "lean": 0.0, "hand_l": L}]]
		"backslash":
			return [[0.0, {"hand_r": Vector3(-0.32, 1.42, -0.12), "wdir": Vector3(-0.7, 0.45, 0.4), "wroll": Vector3(0, -1, 0), "twist": 0.55}],
				[h, {"hand_r": Vector3(0.12, 1.25, -0.6), "wdir": Vector3(1.0, 0.0, -0.6), "wroll": Vector3(0, -1, 0), "twist": -0.25, "lean": -0.12}],
				[minf(h + 0.28, 0.9), {"hand_r": Vector3(0.45, 1.12, -0.18), "wdir": Vector3(0.85, -0.3, 0.5), "wroll": Vector3(0, -1, 0), "twist": -0.6, "lean": -0.1}],
				[1.0, {"hand_r": R, "wdir": rest.wdir, "wroll": rest.wroll, "twist": 0.0, "lean": 0.0}]]
		"thrust":
			return [[0.0, {"hand_r": Vector3(0.26, 1.12, 0.18), "wdir": Vector3(0, 0.05, -1), "wroll": Vector3(0, 1, 0), "twist": 0.45, "crouch": 0.08, "hand_l": Vector3(-0.32, 1.2, -0.25)}],
				[h, {"hand_r": Vector3(0.06, 1.3, -0.8), "wdir": Vector3(0, 0.02, -1), "wroll": Vector3(0, 1, 0), "twist": -0.3, "lean": -0.28, "crouch": 0.12, "hand_l": Vector3(-0.35, 1.25, 0.15)}],
				[minf(h + 0.35, 0.92), {"hand_r": Vector3(0.06, 1.3, -0.78), "wdir": Vector3(0, 0.02, -1), "wroll": Vector3(0, 1, 0), "twist": -0.3, "lean": -0.25, "crouch": 0.1}],
				[1.0, {"hand_r": R, "wdir": rest.wdir, "wroll": rest.wroll, "twist": 0.0, "lean": 0.0, "crouch": 0.0, "hand_l": L}]]
		"bash":
			return [[0.0, {"hand_r": Vector3(0.36, 1.62, 0.22), "wdir": Vector3(0.45, 0.7, 0.6), "wroll": Vector3(0, 1, 0), "twist": -0.7, "crouch": 0.05}],
				[h, {"hand_r": Vector3(0.0, 1.22, -0.6), "wdir": Vector3(-1.0, 0.1, -0.35), "wroll": Vector3(0, 1, 0), "twist": 0.35, "lean": -0.15, "crouch": 0.1}],
				[minf(h + 0.3, 0.9), {"hand_r": Vector3(-0.38, 1.0, -0.2), "wdir": Vector3(-0.65, -0.55, 0.45), "wroll": Vector3(0, 1, 0), "twist": 0.75, "lean": -0.2, "crouch": 0.1}],
				[1.0, {"hand_r": R, "wdir": rest.wdir, "wroll": rest.wroll, "twist": 0.0, "lean": 0.0, "crouch": 0.0}]]
		"backhand":
			return [[0.0, {"hand_r": Vector3(-0.32, 1.5, 0.1), "wdir": Vector3(-0.55, 0.65, 0.5), "wroll": Vector3(0, -1, 0), "twist": 0.7, "crouch": 0.05}],
				[h, {"hand_r": Vector3(0.12, 1.22, -0.6), "wdir": Vector3(1.0, 0.1, -0.4), "wroll": Vector3(0, -1, 0), "twist": -0.35, "lean": -0.15, "crouch": 0.1}],
				[minf(h + 0.3, 0.9), {"hand_r": Vector3(0.45, 1.05, -0.15), "wdir": Vector3(0.7, -0.5, 0.45), "wroll": Vector3(0, -1, 0), "twist": -0.75, "lean": -0.18, "crouch": 0.1}],
				[1.0, {"hand_r": R, "wdir": rest.wdir, "wroll": rest.wroll, "twist": 0.0, "lean": 0.0, "crouch": 0.0}]]
		"smash":
			return [[0.0, {"hand_r": Vector3(0.12, 1.75, -0.05), "wdir": Vector3(0.05, 1.0, 0.25), "wroll": Vector3(1, 0, 0), "lean": 0.05}],
				[h * 0.75, {"hand_r": Vector3(0.1, 1.98, 0.12), "wdir": Vector3(0.0, 0.75, 0.75), "wroll": Vector3(1, 0, 0), "lean": 0.18}],
				[h, {"hand_r": Vector3(0.05, 0.95, -0.62), "wdir": Vector3(0.0, -0.65, -1.0), "wroll": Vector3(1, 0, 0), "lean": -0.45, "crouch": 0.18}],
				[minf(h + 0.32, 0.92), {"hand_r": Vector3(0.05, 0.92, -0.6), "wdir": Vector3(0.0, -0.7, -1.0), "wroll": Vector3(1, 0, 0), "lean": -0.4, "crouch": 0.16}],
				[1.0, {"hand_r": R, "wdir": rest.wdir, "wroll": rest.wroll, "lean": 0.0, "crouch": 0.0}]]
		"jab":   # the lead (left) hand snaps straight out from the guard and straight back; the right stays at the chin
			return [[0.0, {"hand_l": Vector3(-0.1, 1.5, -0.3), "hand_r": Vector3(0.14, 1.46, -0.2), "twist": -0.25, "crouch": 0.05}],
				[h * 0.5, {"hand_l": Vector3(-0.1, 1.47, -0.26), "twist": -0.2}],
				[h, {"hand_l": Vector3(-0.04, 1.53, -0.74), "hand_r": Vector3(0.14, 1.47, -0.18), "twist": -0.45, "lean": -0.08, "crouch": 0.07}],
				[minf(h + 0.12, 0.9), {"hand_l": Vector3(-0.04, 1.53, -0.72), "twist": -0.42}],   # held out a moment
				[minf(h + 0.34, 0.92), {"hand_l": Vector3(-0.1, 1.5, -0.32), "twist": -0.28, "lean": 0.0}],
				[1.0, {"hand_l": Vector3(-0.1, 1.5, -0.3), "hand_r": Vector3(0.14, 1.46, -0.2), "twist": -0.25, "crouch": 0.05}]]
		"cross":   # the rear (right) hand, driven by the hips and shoulders turning through; the back heel pivots
			return [[0.0, {"hand_l": Vector3(-0.1, 1.5, -0.3), "hand_r": Vector3(0.14, 1.46, -0.2), "twist": -0.3, "crouch": 0.05}],
				[h * 0.6, {"hand_r": Vector3(0.16, 1.44, -0.12), "twist": -0.4, "crouch": 0.08}],
				[h, {"hand_r": Vector3(0.02, 1.52, -0.76), "hand_l": Vector3(-0.16, 1.48, -0.16), "twist": 0.55, "lean": -0.15, "crouch": 0.1,
					"foot_r": Vector3(0.15, 0.03, 0.14)}],
				[minf(h + 0.12, 0.9), {"hand_r": Vector3(0.03, 1.52, -0.74), "twist": 0.5}],   # held out a moment
				[minf(h + 0.36, 0.92), {"hand_r": Vector3(0.12, 1.47, -0.3), "twist": 0.1, "lean": -0.05, "foot_r": Vector3(0.14, 0.0, 0.1)}],
				[1.0, {"hand_l": Vector3(-0.1, 1.5, -0.3), "hand_r": Vector3(0.14, 1.46, -0.2), "twist": -0.25, "lean": 0.0, "crouch": 0.05,
					"foot_r": Vector3(0.14, 0.0, 0.08)}]]
		"kick":   # roundhouse: chamber the knee, pivot on the standing foot, lean back, whip the shin through, recover
			return [[0.0, {"hand_l": Vector3(-0.1, 1.5, -0.3), "hand_r": Vector3(0.14, 1.46, -0.2), "foot_r": Vector3(0.14, 0.0, 0.08), "twist": -0.25}],
				[h * 0.55, {"foot_r": Vector3(0.22, 0.55, -0.12), "twist": -0.55, "lean": 0.12, "crouch": 0.04}],
				[h, {"foot_r": Vector3(-0.15, 1.0, -0.72), "twist": -0.95, "lean": 0.32, "hand_r": Vector3(0.36, 1.12, 0.12),
					"hand_l": Vector3(-0.18, 1.45, -0.32), "crouch": 0.06}],
				[minf(h + 0.28, 0.9), {"foot_r": Vector3(0.05, 0.45, -0.3), "twist": -0.5, "lean": 0.12}],
				[1.0, {"foot_r": Vector3(0.14, 0.0, 0.08), "hand_l": Vector3(-0.1, 1.5, -0.3), "hand_r": Vector3(0.14, 1.46, -0.2), "twist": -0.25, "lean": 0.0, "crouch": 0.0}]]
	return [[0.0, {}], [1.0, {}]]


## The pose at time t. Into the strike (the key at h) the extreme wind-up pose holds, then the strike covers the
## last ~20% of the wind-up with a fast ease-out (most of the arc in its first half); other spans ease in-out. Hands
## travel on arcs around their shoulder, not in straight lines through the body.
func _sample(keys: Array, t: float, h := -1.0) -> Dictionary:
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
		var x := clampf((t - prev_t) / maxf(kt - prev_t, 0.001), 0.0, 1.0)
		var f := _smooth(x)
		if h >= 0.0 and absf(kt - h) < 0.0001:   # the strike: hold the wind-up, then snap through with ease-out
			var start := prev_t + (kt - prev_t) * 0.78
			var s := clampf((t - start) / maxf(kt - start, 0.001), 0.0, 1.0)
			f = 1.0 - pow(1.0 - s, 3.0)
		elif h >= 0.0 and prev_t >= h - 0.0001:   # after the hit: ease-out into the follow-through and recovery
			f = 1.0 - pow(1.0 - x, 2.0)
		var out := prev.duplicate()
		for key in kv.keys():
			if prev.has(key):
				if key == "hand_r" or key == "hand_l":
					out[key] = _arc_lerp(prev[key], kv[key], f, Vector3(SHOULDER_REST.x if key == "hand_r" else -SHOULDER_REST.x, SHOULDER_REST.y, 0.0))
				elif prev[key] is Vector3:
					out[key] = (prev[key] as Vector3).lerp(kv[key], f)
				else:
					out[key] = lerpf(prev[key], kv[key], f)
		return out
	return acc


func _smooth(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


## Move from a to b around `center` (the shoulder): angles and reach blend, so the hand sweeps on an arc.
func _arc_lerp(a: Vector3, b: Vector3, f: float, center: Vector3) -> Vector3:
	var da := a - center
	var db := b - center
	var ra := da.length()
	var rb := db.length()
	if ra < 0.01 or rb < 0.01:
		return a.lerp(b, f)
	var dir := da.normalized().slerp(db.normalized(), f) if da.normalized().dot(db.normalized()) > -0.98 else da.normalized().lerp(db.normalized(), f).normalized()
	return center + dir * lerpf(ra, rb, f)


# ================================================================ the rig
## Two-bone IK: from root `a` toward target `t` with bone lengths l1, l2, bending toward `pole`.
## -> [joint (elbow / knee), end (hand / foot, pulled in if out of reach)].
static func ik(a: Vector3, t: Vector3, l1: float, l2: float, pole: Vector3) -> Array:
	var d := t - a
	var dist := clampf(d.length(), 0.05, (l1 + l2) * 0.998)
	var dir := d.normalized() if d.length() > 1e-4 else Vector3.DOWN
	var x := (l1 * l1 + dist * dist - l2 * l2) / (2.0 * dist)   # how far along the reach the joint sits
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
	_joints["elbow_" + side] = elbow
	_joints["hand_" + side] = hand
	# in a robe, the arm is inside a sleeve: a wider tube over the upper arm and the forearm, a full elbow, ending in
	# the bell cuff at the wrist (in _dress) that the hand comes out of
	var robed := _garb_kind != WizardGarb.Kind.NONE
	_place_seg("upper_" + side, shoulder, elbow, 0.092 if robed else 0.068)
	_place_seg("fore_" + side, elbow, hand - (hand - elbow).normalized() * 0.03, 0.082 if robed else 0.05)
	_place_ball("elbow_" + side, elbow, Vector3.ONE * (0.18 if robed else 0.105))
	# the hand: a slightly flat mitten along the forearm, the thumb on its inner side
	var along := (hand - elbow).normalized()
	if side == "r":
		_along_r = along
	else:
		_along_l = along
	var across := along.cross(Vector3.UP if absf(along.y) < 0.9 else Vector3.FORWARD).normalized()
	var hb := Basis(across, along, across.cross(along)).orthonormalized()
	_place_ball("hand_" + side, hand + along * 0.02, Vector3(0.09, 0.11, 0.07), hb)
	_place_ball("thumb_" + side, hand + across * (0.045 if side == "l" else -0.045) + along * 0.01, Vector3(0.035, 0.05, 0.035), hb)
	return hand


func _leg(side: String, hip: Vector3, foot: Vector3) -> void:
	var r := ik(hip, foot, THIGH, SHIN, Vector3(0, 0.2, -1))
	var knee: Vector3 = r[0]
	var ankle: Vector3 = r[1]
	_joints["knee_" + side] = knee
	_joints["ankle_" + side] = ankle
	_place_seg("thigh_" + side, hip, knee, 0.085)
	_place_seg("shin_" + side, knee, ankle, 0.068)
	_place_ball("knee_" + side, knee, Vector3.ONE * 0.15)
	_place_seg("boot_" + side, ankle + Vector3(0, -0.02, 0), ankle + (knee - ankle).normalized() * 0.16, 0.075)
	var foot_mi: MeshInstance3D = parts["foot_" + side]
	foot_mi.transform = Transform3D(Basis.from_scale(Vector3(0.12, 0.08, 0.27)), ankle + Vector3(0, -0.04, -0.06))


## A cylinder or capsule part from a to b, radius r (wider sideways by `wide`), turned with `turn` about its length.
func _place_seg(nm: String, a: Vector3, b: Vector3, r: float, wide := 1.0, turn := Basis.IDENTITY) -> void:
	var mi: MeshInstance3D = parts[nm]
	var d := b - a
	var len := maxf(d.length(), 0.001)
	var y := d / len
	var ref := turn * Vector3.FORWARD
	var x := y.cross(ref) if absf(y.dot(ref)) < 0.95 else y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	var h := len / (1.6 if nm in ["chest", "waist", "pelvis"] else 1.0)
	mi.transform = Transform3D(Basis(x * r * 2.0 * wide, y * h, z * r * 2.0), (a + b) / 2.0)


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
	if w != Weapons.BOW:   # the bow is drawn live (its limbs flex); the others are models
		held = WeaponModels.for_weapon(w)
		if held != null:
			model.add_child(held)
	held_w = w


## The weapon in hand; for the bow, the stave (limbs flexing with the draw and springing after a release), its string
## and the nocked arrow; for the slingshot, the bands and pouch stretched to the drawing hand, with the stone.
func _draw_weapon(st: Sim.PlayerState, w: int, hand_r: Vector3, hand_l: Vector3, dead: bool, pose: Dictionary) -> void:
	var drawing := st != null and st.charge > 0
	var pull := 0.0
	if st != null and Weapons.is_ranged(w):
		pull = clampf(float(st.charge) / float(Weapons.get_data(w).draw), 0.0, 1.0)
	# after a release: the limbs / bands spring back and wobble (a damped oscillation)
	var spring := _release_pull * exp(-_release_t * 9.0) * cos(_release_t * 38.0) if _release_t < 0.6 else 0.0

	for s in _bow_segs:
		s.visible = false
	_arrow.visible = false
	_stone.visible = false
	_pouch.visible = false
	_string_a.visible = false
	_string_b.visible = false
	if dead:
		if held:
			held.visible = false
		return

	if w == Weapons.BOW:
		last_grip = hand_l
		var up := (_wdir as Vector3).normalized()
		var back := (Vector3(0, 0, 1) - up * up.z).normalized()   # toward the archer, square to the stave
		var flex := 0.12 + 0.11 * _ease_draw(pull) - 0.05 * spring
		var pts := []
		for i in 11:
			var s := (i - 5) / 5.0
			pts.append(hand_l + up * (s * BOW_HALF) + back * (flex * s * s - 0.02))
		for i in 10:
			var thick := 0.026 - 0.01 * absf((i - 4.5) / 4.5)   # thicker at the grip, tapering to the tips
			_seg_line(_bow_segs[i], pts[i], pts[i + 1], thick)
			_bow_segs[i].visible = true
		var tip_a: Vector3 = pts[0]
		var tip_b: Vector3 = pts[10]
		var nock: Vector3 = hand_r if drawing else (tip_a + tip_b) / 2.0 + back * (0.03 * spring)
		_string_on(tip_a, tip_b, nock, 0.005, WeaponModels.STRING)
		var nocked := st != null and st.arrows > 0 and (drawing or (pose.has("aim") and st.atk == 0 and st.atk_cd == 0))
		if nocked:   # the arrow runs from the string to the bow, resting on the bow's left side
			var side := (Vector3.UP.cross(hand_l - nock)).normalized() * 0.02
			var aim := (hand_l + side - nock)
			aim = aim.normalized() if aim.length() > 0.05 else Vector3.FORWARD
			_arrow.transform = Transform3D(Basis.looking_at(aim, Vector3.UP), nock)
			_arrow.visible = true
	elif w == Weapons.SLING and held != null:
		var y := (_wdir as Vector3).normalized()
		var x := Vector3.RIGHT.cross(y).cross(y).normalized() * -1.0
		var z := x.cross(y).normalized()
		held.transform = Transform3D(Basis(x, y, z), hand_l - y * 0.0)
		last_grip = hand_l
		held.visible = true
		var prong_a := held.transform * Vector3(-0.1, 0.27, 0)
		var prong_b := held.transform * Vector3(0.1, 0.27, 0)
		var rest := (prong_a + prong_b) / 2.0 + z * 0.1
		var pouch: Vector3 = hand_r if drawing else rest + z * (0.06 * spring) + y * (0.02 * spring)
		for nm in ["band_l", "band_r", "pouch"]:
			var n := held.get_node_or_null(nm)
			if n:
				n.visible = false
		_string_on(prong_a, prong_b, pouch, 0.009, WeaponModels.BAND)
		_pouch.transform = Transform3D(Basis.looking_at((rest - pouch).normalized() if rest.distance_to(pouch) > 0.02 else -z, Vector3.UP), pouch)
		_pouch.visible = true
		if drawing and st.rocks > 0:
			_stone.position = pouch
			_stone.visible = true
	elif held != null:
		var y := _wdir.normalized()
		var x := _wroll.cross(y)
		x = x.normalized() if x.length() > 0.05 else y.cross(Vector3.FORWARD).normalized()
		var z := x.cross(y).normalized()
		# the handle's middle in the palm (the sword's grip is 0.04 up from its origin)
		var grip_mid := 0.04 if w == Weapons.SWORD else 0.0
		held.transform = Transform3D(Basis(x, y, z), hand_r - y * grip_mid)
		last_grip = hand_r
		held.visible = true


func _string_on(a: Vector3, b: Vector3, mid: Vector3, r: float, c: Color) -> void:
	_seg_line(_string_a, a, mid, r)
	_seg_line(_string_b, b, mid, r)
	(_string_a.material_override as StandardMaterial3D).albedo_color = c
	(_string_b.material_override as StandardMaterial3D).albedo_color = c
	_string_a.visible = true
	_string_b.visible = true


func _line_mesh(c: Color, shaded := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.5
	cy.bottom_radius = 0.5
	cy.height = 1.0
	cy.radial_segments = 6 if shaded else 4
	mi.mesh = cy
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if not shaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.roughness = 0.7
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


# ================================================================ the wizard garb
const ROBE_PARTS := ["chest", "waist", "hem", "upper_r", "upper_l", "fore_r", "fore_l", "elbow_r", "elbow_l", "shoulder_r", "shoulder_l", "trap_r", "trap_l", "pelvis",
	"thigh_r", "thigh_l", "shin_r", "shin_l", "knee_r", "knee_l"]
const SHADED_PARTS := ["head", "nose", "ear_l", "ear_r", "neck"]
const SKIN_C := Color("f1c9a5")
## v0.9.0: what each costume does to the body's own parts (the rest keep their colours).
const TORSO := ["chest", "waist", "hem", "shoulder_r", "shoulder_l", "trap_r", "trap_l"]
const ARMS := ["upper_r", "upper_l", "fore_r", "fore_l", "elbow_r", "elbow_l"]
const LEGS := ["pelvis", "thigh_r", "thigh_l", "shin_r", "shin_l", "knee_r", "knee_l"]
const HANDS := ["hand_r", "hand_l", "thumb_r", "thumb_l"]
const FEET := ["boot_r", "boot_l", "foot_r", "foot_l"]
static var COLS := {
	WizardGarb.Kind.BRAWLER: { "torso": Color("5c4030"), "arms": SKIN_C, "legs": Color("4a3f38"), "hands": Color("ece6d8") },
	WizardGarb.Kind.KNIGHT: { "torso": Color("9aa0aa"), "arms": Color("8a909a"), "legs": Color("3f3a36") },
	WizardGarb.Kind.BARBARIAN: { "torso": SKIN_C, "arms": SKIN_C, "legs": Color("6a4a32"), "feet": Color("8a6240") },
	WizardGarb.Kind.RANGER: { "torso": Color("8a5c38"), "arms": Color("4c6038"), "legs": Color("4c5a38") },
	WizardGarb.Kind.SCOUT: { "torso": Color("b88a40"), "arms": Color("e8e2d0"), "legs": Color("4a4038") },
}
var _costume_parts := {}   # name -> MeshInstance3D: the costumes' rigid pieces, built once, shown per costume
var _accent_col := Color.WHITE


## The rigid pieces of every costume, made once (and only shown with their costume): shoulder guards, a mail coif and
## a tabard emblem (knight); a fur mantle with tufts, fur boot tops and a harness (barbarian); a bracer and the hood
## down round the neck (ranger); a headband (brawler); a bandana cap (scout).
func _build_costume_parts() -> void:
	var specs := {
		"pauldron_r": ["sphere", Color("c8ced8"), Vector3(0.17, 0.12, 0.17)], "pauldron_l": ["sphere", Color("c8ced8"), Vector3(0.17, 0.12, 0.17)],
		"coif": ["hemi", Color("a8aeb8"), Vector3(0.37, 0.37, 0.37)], "emblem": ["box", Color("e8c050"), Vector3(0.08, 0.08, 0.02)],
		"mantle": ["torus", Color("8a6240"), Vector3(0.34, 0.16, 0.26)], "boot_fur_r": ["torus", Color("a07a52"), Vector3(0.1, 0.06, 0.1)],
		"boot_fur_l": ["torus", Color("a07a52"), Vector3(0.1, 0.06, 0.1)], "strap_a": ["box", Color("4a3424"), Vector3(0.05, 0.62, 0.03)],
		"strap_b": ["box", Color("4a3424"), Vector3(0.05, 0.62, 0.03)], "bracer": ["cyl", Color("5a3e2a"), Vector3(0.12, 0.12, 0.12)],
		"collar": ["torus", Color("4c5a38"), Vector3(0.26, 0.12, 0.22)], "headband": ["torus", Color.WHITE, Vector3(0.36, 0.06, 0.36)],
		"bandana": ["hemi", Color.WHITE, Vector3(0.36, 0.34, 0.36)], "sash": ["torus", Color.WHITE, Vector3(0.36, 0.1, 0.27)],
	}
	for nm in specs:
		var sp: Array = specs[nm]
		var mi := MeshInstance3D.new()
		match sp[0]:
			"sphere":
				var m := SphereMesh.new()
				m.radius = 0.5
				m.height = 1.0
				mi.mesh = m
			"hemi":
				var m := SphereMesh.new()
				m.radius = 0.5
				m.height = 0.5
				m.is_hemisphere = true
				mi.mesh = m
			"box":
				mi.mesh = BoxMesh.new()
			"cyl":
				var m := CylinderMesh.new()
				m.top_radius = 0.5
				m.bottom_radius = 0.5
				m.height = 1.0
				mi.mesh = m
			"torus":
				var m := TorusMesh.new()
				m.inner_radius = 0.38
				m.outer_radius = 0.5
				m.rings = 20
				m.ring_segments = 8
				mi.mesh = m
		var mat := StandardMaterial3D.new()
		mat.albedo_color = sp[1]
		mat.roughness = 0.4 if nm in ["pauldron_r", "pauldron_l", "coif"] else 0.95
		mat.metallic = 0.6 if nm in ["pauldron_r", "pauldron_l", "coif"] else 0.0
		mi.material_override = mat
		mi.set_meta("size", sp[2])
		mi.visible = false
		model.add_child(mi)
		_costume_parts[nm] = mi
	for nm in ["headband", "bandana", "sash"]:   # in the player's colour
		(_costume_parts[nm].material_override as StandardMaterial3D).albedo_color = _accent_col


const SHOWN := {
	WizardGarb.Kind.KNIGHT: ["pauldron_r", "pauldron_l", "coif", "emblem"],
	WizardGarb.Kind.BARBARIAN: ["mantle", "boot_fur_r", "boot_fur_l", "strap_a", "strap_b"],
	WizardGarb.Kind.RANGER: ["bracer", "collar"],
	WizardGarb.Kind.BRAWLER: ["headband", "sash"],
	WizardGarb.Kind.SCOUT: ["bandana"],
}


func _cpart(nm: String, at: Vector3, basis: Basis) -> void:
	var mi: MeshInstance3D = _costume_parts[nm]
	mi.transform = Transform3D(basis * Basis.from_scale(mi.get_meta("size")), at)


func _dress(delta: float, st: Sim.PlayerState, pelvis: Vector3, low: Basis, neck: Vector3, head: Vector3, head_basis: Basis,
		hip_r: Vector3, hip_l: Vector3, dead: bool, chest := Vector3.ZERO, spine := Basis.IDENTITY) -> void:
	var k := WizardGarb.kind_for(st)
	var robe_kind := k == WizardGarb.Kind.WIZARD or k == WizardGarb.Kind.SHADOW or k == WizardGarb.Kind.BOTH
	if _costume_parts.is_empty():
		_build_costume_parts()
	if k != _garb_kind:
		var first := _garb_kind == 0
		_garb_kind = k
		_garb.set_kind(k)   # (the cloth starts again from hanging at rest)
		var robe := WizardGarb.robe_color(k)
		var scheme: Dictionary = COLS.get(k, {})
		for nm in ROBE_PARTS + HANDS + FEET:   # the costume over the body's own parts (or their own colours back)
			var mc: Array = _mats[_base_col[nm]]
			var orig: Color = (mc[0] as StandardMaterial3D).get_meta("orig", mc[1])
			(mc[0] as StandardMaterial3D).set_meta("orig", orig)
			var c := orig
			if robe_kind and nm in ROBE_PARTS:
				c = robe.darkened(0.06) if nm.begins_with("upper") or nm.begins_with("shoulder") else robe
			elif nm in TORSO and scheme.has("torso"):
				c = scheme.torso
			elif nm in ARMS and scheme.has("arms"):
				c = scheme.arms if not (nm.begins_with("fore") or nm.begins_with("elbow")) or k != WizardGarb.Kind.SCOUT else SKIN_C   # rolled sleeves
			elif nm in LEGS and scheme.has("legs"):
				c = scheme.legs
			elif nm in HANDS and scheme.has("hands"):
				c = scheme.hands
			elif nm in FEET and scheme.has("feet"):
				c = scheme.feet
			mc[1] = c
		for nm in SHADED_PARTS:   # in the dark robe's cowl, the face is in shadow
			var mc: Array = _mats[_base_col[nm]]
			var orig: Color = (mc[0] as StandardMaterial3D).get_meta("orig", mc[1])
			(mc[0] as StandardMaterial3D).set_meta("orig", orig)
			mc[1] = orig.darkened(0.5) if k == WizardGarb.Kind.SHADOW else orig
		for nm in ["belt", "buckle"]:   # no belt line breaking a robe
			(parts[nm] as MeshInstance3D).visible = not robe_kind
		for sd in _sleeves:
			var sl: MeshInstance3D = _sleeves[sd][0]
			sl.visible = robe_kind
			(sl.material_override as StandardMaterial3D).albedo_color = robe.darkened(0.04)
		var shown: Array = SHOWN.get(k, [])
		for nm in _costume_parts:
			(_costume_parts[nm] as MeshInstance3D).visible = nm in shown
		if not first and get_parent() != null and model.visible:   # a puff as it changes: sparkles for magic, dust
			Fx.burst(get_parent(), position + Vector3(0, 1.1, 0), Vector3.UP, Color("c9a8ff") if robe_kind else Color("e8dcc0"), 26, 3.2, 0.045)
			MotionFx.puff(get_parent(), position + Vector3(0, 0.3, 0), 6, 1.2)
	if k == WizardGarb.Kind.NONE:
		return
	# the rigid pieces, on the body
	match k:
		WizardGarb.Kind.KNIGHT:
			for sd in [["r", 1.0], ["l", -1.0]]:
				_cpart("pauldron_" + sd[0], chest + spine * Vector3(0.2 * float(sd[1]), 0.06, 0.0), spine * Basis(Vector3.BACK, -0.35 * float(sd[1])))
			_cpart("coif", head + head_basis * Vector3(0, -0.01, 0.01), head_basis)
			_cpart("emblem", chest + spine * Vector3(0, -0.02, -0.235), spine)
		WizardGarb.Kind.BARBARIAN:
			_cpart("mantle", chest + spine * Vector3(0, 0.07, 0.01), spine)
			for sd in ["r", "l"]:
				var an: Vector3 = _joints.get("ankle_" + sd, Vector3.ZERO)
				var kn: Vector3 = _joints.get("knee_" + sd, Vector3.ZERO)
				_cpart("boot_fur_" + sd, an + (kn - an).normalized() * 0.15, WizardGarb._basis_y((kn - an).normalized()))
			_cpart("strap_a", chest + spine * Vector3(0, -0.08, -0.205), spine * Basis(Vector3.BACK, 0.6))
			_cpart("strap_b", chest + spine * Vector3(0, -0.08, 0.205), spine * Basis(Vector3.BACK, -0.6))
		WizardGarb.Kind.RANGER:
			var el: Vector3 = _joints.get("elbow_l", Vector3.ZERO)
			var hd: Vector3 = _joints.get("hand_l", Vector3.ZERO)
			var ax := (hd - el).normalized() if hd.distance_to(el) > 0.01 else Vector3.DOWN
			var bb := WizardGarb._basis_y(ax)
			_costume_parts.bracer.transform = Transform3D(Basis(bb.x * 0.12, bb.y * 0.14, bb.z * 0.12), hd - ax * 0.09)
			_cpart("collar", neck + spine * Vector3(0, -0.07, 0.03), spine)
		WizardGarb.Kind.BRAWLER:
			_cpart("headband", head + head_basis * Vector3(0, 0.07, 0), head_basis)
			_cpart("sash", pelvis + low * Vector3(0, 0.09, 0), low)
		WizardGarb.Kind.SCOUT:
			_cpart("bandana", head + head_basis * Vector3(0, 0.02, 0.01), head_basis)
	# long bell sleeves (the robes) from the elbows, hanging and swinging behind the forearm
	if robe_kind:
		for sd in _sleeves:
			var sl: MeshInstance3D = _sleeves[sd][0]
			var el: Vector3 = _joints.get("elbow_" + sd, Vector3.ZERO)
			var hd: Vector3 = _joints.get("hand_" + sd, Vector3.ZERO)
			var along := (hd - el).normalized() if hd.distance_to(el) > 0.01 else Vector3.DOWN
			var want := (along * 0.85 + Vector3.DOWN * 0.3).normalized()
			var hang: Vector3 = (_sleeves[sd][1] as Vector3).lerp(want, clampf(delta * 6.0, 0.0, 1.0)).normalized()   # weighty lag
			_sleeves[sd][1] = hang
			var fl := hd.distance_to(el)
			sl.transform = WizardGarb._xf(el + along * fl * 0.45, hd + along * 0.02 + (hang - along).normalized() * 0.05 * (hang - along).length())
	var mt := model.global_transform
	var mb := mt.basis.orthonormalized()
	var up := (mb * head_basis * Vector3.UP).normalized()
	var face := (mb * head_basis * Vector3.FORWARD).normalized()
	var ground := WorldLayout.ground_height(position.x, position.z, position.y)
	var cols := []
	for sd in ["r", "l"]:
		var hip := hip_r if sd == "r" else hip_l
		cols.append([mt * hip, mt * (_joints.get("knee_" + sd, hip) as Vector3), 0.19])
		cols.append([mt * (_joints.get("knee_" + sd, hip) as Vector3), mt * (_joints.get("ankle_" + sd, hip) as Vector3) + Vector3(0, -0.05, 0), 0.17])
	var sb := mb * spine
	var wb := mb * low
	var waist_c := mt * (pelvis + low * Vector3(0, 0.12, 0))
	var hang_b := Basis(Vector3.UP, rotation.y)
	var feet_y := (mt * Vector3.ZERO).y + 0.03   # lengths are fixed (to the feet), never down to the ground
	var rings := [
		[mt * (chest + spine * Vector3(0, 0.12, 0.0)), sb, 0.12, 0.11],
		[mt * (chest + spine * Vector3(0, 0.03, 0.01)), sb, 0.29, 0.21],
		[mt * (chest + spine * Vector3(0, -0.13, 0.0)), sb, 0.28, 0.22],
		[waist_c, wb, 0.25, 0.21]]
	var pinned := 4
	var hang_h := maxf(waist_c.y - feet_y, 0.5)
	if k == WizardGarb.Kind.BARBARIAN:   # the kilt: from the waist to the knees
		rings = [[waist_c, wb, 0.25, 0.21]]
		pinned = 1
		for i in 3:
			var u := float(i + 1) / 3.0
			rings.append([Vector3(waist_c.x, waist_c.y - hang_h * 0.5 * u, waist_c.z), hang_b, lerpf(0.27, 0.34, u), lerpf(0.23, 0.29, u)])
	else:
		for i in 6:
			var u := float(i + 1) / 6.0
			rings.append([Vector3(waist_c.x, waist_c.y - hang_h * u, waist_c.z), hang_b, lerpf(0.27, 0.42, u), lerpf(0.24, 0.38, u)])
	var arm_cols := []   # forearms and hands: cloth stays inside them
	for sd in ["r", "l"]:
		var el: Vector3 = _joints.get("elbow_" + sd, Vector3.ZERO)
		var hd: Vector3 = _joints.get("hand_" + sd, Vector3.ZERO)
		arm_cols.append([mt * el, mt * (hd + (hd - el).normalized() * 0.08), 0.09])
	var right := (mb * low * Vector3.RIGHT).normalized()
	var down := Vector3.DOWN
	var back := (mb * head_basis * Vector3.BACK).normalized()
	_garb.update(delta, {
		"rings": rings, "pinned": pinned, "feet_y": feet_y, "colliders": cols, "arm_colliders": arm_cols, "ground": ground, "vel": _vel,
		"head_top": mt * (head + head_basis * Vector3(0, 0.15, 0.01)), "head_c": mt * head, "head_r": 0.17,
		"up": up, "face": face, "neck": mt * neck, "hat_h": 0.72, "hat_r": 0.2, "brim_r": 0.42,
		"own": not label.visible, "visible": model.visible, "accent": _accent_col,
		"robe_col": Color("b89870") if k == WizardGarb.Kind.BARBARIAN else WizardGarb.robe_color(k),
		"cloak_col": Color("56603e") if k == WizardGarb.Kind.RANGER else WizardGarb.GREY_CLOAK,
		"tabard_front": [mt * (chest + spine * Vector3(-0.13, 0.04, -0.215)), mt * (chest + spine * Vector3(0.13, 0.04, -0.215))],
		"tabard_back": [mt * (chest + spine * Vector3(0.13, 0.04, 0.215)), mt * (chest + spine * Vector3(-0.13, 0.04, 0.215))],
		"tabard_len": maxf((mt * chest).y - feet_y - 0.45, 0.4),
		"sash_at": mt * (pelvis + low * Vector3(0.16, 0.08, -0.12)), "sash_dir": (down * 0.9 + right * 0.2).normalized(), "sash_side": right,
		"band_at": mt * (head + head_basis * Vector3(0, 0.07, 0.17)), "band_dir": (back * 0.6 + down * 0.8).normalized(),
		"band_side": right,
		"satchel_at": mt * (pelvis + low * Vector3(0.24, -0.04, 0.02)), "satchel_basis": mb * low })


## Where the staff's (or wand's) orb is now, for the shield pouring out of it; null without one.
func orb_position():
	var n: Node3D = held
	if n == null or not n.visible:
		return null
	var orb := n.get_node_or_null("Orb") as Node3D
	return orb.global_position if orb else null
