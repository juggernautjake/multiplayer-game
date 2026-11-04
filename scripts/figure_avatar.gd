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
## Same interface as Avatar (Pip): yaw, grounded, dashing, state, model, label, flash(), animate().
class_name FigureAvatar
extends Node3D

const SKIN := Color("f1c9a5")
const PANTS := Color("3b4252")
const BOOTS := Color("4a3426")
const BELT := Color("3a2618")
const HAIR := Color("6b4426")
const UPPER_ARM := 0.29
const FOREARM := 0.27
const THIGH := 0.45
const SHIN := 0.44
const BOW_HALF := 0.62         # half the bow's length
const DRAW_LEN := 0.68         # bow grip to anchor at full draw

var yaw := 0.0
var grounded := true
var dashing := false
var state: Sim.PlayerState
var instant := false           # skip blending (pose previews)

var model: Node3D              # everything in the body's frame (x right, y up, -z forward); hidden in first person
var label: Label3D
var hp_bar: Sprite3D
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
var _pole_r := Vector3(0.6, -1.0, 0.7)
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
	var tunic := color
	var sleeve := color.darkened(0.12)
	var sphere_parts := ["head", "hair", "nose", "ear_l", "ear_r", "eyew_l", "eyew_r", "eye_l", "eye_r", "hand_r", "hand_l",
		"thumb_r", "thumb_l", "elbow_r", "elbow_l", "knee_r", "knee_l", "shoulder_r", "shoulder_l", "buckle"]
	var box_parts := ["foot_r", "foot_l", "brow_l", "brow_r"]
	for spec in [["pelvis", PANTS], ["waist", tunic.darkened(0.05)], ["chest", tunic], ["hem", tunic.darkened(0.08)],
			["belt", BELT], ["buckle", Color("d9b44a")], ["neck", SKIN], ["head", SKIN], ["hair", HAIR], ["nose", SKIN.darkened(0.05)],
			["ear_l", SKIN], ["ear_r", SKIN], ["eyew_l", Color.WHITE], ["eyew_r", Color.WHITE], ["eye_l", Color(0.1, 0.12, 0.2)],
			["eye_r", Color(0.1, 0.12, 0.2)], ["brow_l", HAIR], ["brow_r", HAIR],
			["upper_r", sleeve], ["upper_l", sleeve], ["fore_r", SKIN], ["fore_l", SKIN], ["elbow_r", SKIN], ["elbow_l", SKIN],
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
	_track_release(st, w, delta)

	var pose := _pose(st, speed)
	var a := 1.0 if instant else clampf(delta * (30.0 if pose.get("snap", false) else 12.0), 0.0, 1.0)
	_hand_r = _hand_r.lerp(pose.hand_r, a)
	_hand_l = _hand_l.lerp(pose.hand_l, a)
	_pole_r = _pole_r.lerp(pose.get("pole_r", Vector3(0.6, -1.0, 0.7)), a)
	var wd: Vector3 = (pose.wdir as Vector3).normalized()
	_wdir = _wdir.slerp(wd, a) if _wdir.normalized().dot(wd) > -0.99 else wd
	_wroll = _wroll.lerp(pose.wroll, a).normalized()
	_twist = lerpf(_twist, pose.twist, a)
	_lean = lerpf(_lean, pose.lean, a)
	_crouch = lerpf(_crouch, pose.crouch, a)
	_look = lerpf(_look, pose.look, a if pose.has("aim") else (clampf(delta * 3.0, 0.0, 1.0) if not instant else 1.0))

	# ---- feet
	var stride := clampf(speed * 0.11, 0.0, 0.85)
	var lift := clampf(speed * 0.03, 0.0, 0.2)
	var fwd_dir := Vector2(local_vel.x, local_vel.z)
	fwd_dir = fwd_dir.normalized() if fwd_dir.length() > 0.2 else Vector2(0, -1)
	if grounded and speed > 0.3:
		_phase += delta * (4.0 + speed * 1.1)
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
	var fa := 1.0 if instant else clampf(delta * 20.0, 0.0, 1.0)
	_foot_r = _foot_r.lerp(fr, fa)
	_foot_l = _foot_l.lerp(fl, fa)

	# ---- the skeleton: pelvis, waist, chest (the twist and lean spread over both), neck, head
	var dead := st != null and st.dead > 0
	model.rotation.x = lerpf(model.rotation.x, -PI / 2.0 if dead else 0.0, a)
	model.position.y = lerpf(model.position.y, 0.25 if dead else 0.0, a)
	var breathe := sin(_t * 2.1) * 0.012
	var sway := sin(_t * 0.55) * 0.025 * (1.0 - clampf(speed, 0.0, 1.0))
	var bob := absf(sin(_phase)) * 0.045 * clampf(speed / Sim.WALK_SPEED, 0.0, 1.0) if grounded else 0.0
	var run_lean := 0.12 * clampf(speed / Sim.SPRINT_SPEED, 0.0, 1.0) + (0.4 if dashing else 0.0)
	var pelvis := Vector3(sway, 0.95 - _crouch + bob, 0)
	var low := Basis(Vector3.UP, _twist * 0.45) * Basis(Vector3.RIGHT, (_lean - run_lean) * 0.5)
	var spine := Basis(Vector3.UP, _twist) * Basis(Vector3.RIGHT, _lean - run_lean)
	var waist := pelvis + low * Vector3(0, 0.2, 0)
	var chest := waist + spine * Vector3(0, 0.24 + breathe, 0)
	var sh_r := chest + spine * Vector3(0.21, 0.12, 0)
	var sh_l := chest + spine * Vector3(-0.21, 0.12, 0)
	# the shoulder rises a little when its arm is raised high
	sh_r.y += clampf((_hand_r.y - sh_r.y) * 0.08, 0.0, 0.04)
	sh_l.y += clampf((_hand_l.y - sh_l.y) * 0.08, 0.0, 0.04)
	var neck := chest + spine * Vector3(0, 0.2, 0)
	var head_basis := Basis(Vector3.UP, _twist + _look) * Basis(Vector3.RIGHT, (_lean - run_lean) * 0.3)
	var head := neck + head_basis * Vector3(0, 0.16, 0)
	var hip_r := pelvis + low * Vector3(0.1, -0.04, 0)
	var hip_l := pelvis + low * Vector3(-0.1, -0.04, 0)

	_place_ball("pelvis", pelvis, Vector3(0.32, 0.16, 0.2), low)
	_place_seg("waist", pelvis + low * Vector3(0, 0.02, 0), waist, 0.15, 1.15)
	_place_seg("chest", waist, chest + spine * Vector3(0, 0.08, 0), 0.17, 1.3, spine)
	_place_seg("hem", pelvis + low * Vector3(0, -0.12, 0), pelvis + low * Vector3(0, 0.06, 0), 0.19, 1.15)
	_place_seg("belt", pelvis + low * Vector3(0, 0.06, 0), pelvis + low * Vector3(0, 0.11, 0), 0.172, 1.15)
	_place_ball("buckle", pelvis + low * Vector3(0, 0.085, -0.17), Vector3(0.06, 0.05, 0.03), low)
	_place_seg("neck", neck - spine * Vector3(0, 0.05, 0), head - head_basis * Vector3(0, 0.08, 0), 0.055)
	_place_ball("head", head, Vector3(0.3, 0.32, 0.3), head_basis)
	_place_ball("hair", head + head_basis * Vector3(0, 0.06, 0.03), Vector3(0.31, 0.25, 0.31), head_basis)
	_place_ball("nose", head + head_basis * Vector3(0, -0.01, -0.15), Vector3(0.04, 0.05, 0.05), head_basis)
	for s in [-1.0, 1.0]:
		var sd := "l" if s < 0 else "r"
		_place_ball("ear_" + sd, head + head_basis * Vector3(s * 0.15, 0.0, 0.01), Vector3(0.04, 0.07, 0.05), head_basis)
		_place_ball("eyew_" + sd, head + head_basis * Vector3(s * 0.055, 0.025, -0.13), Vector3(0.055, 0.05, 0.03), head_basis)
		_place_ball("eye_" + sd, head + head_basis * Vector3(s * 0.055, 0.025, -0.143), Vector3(0.03, 0.035, 0.02), head_basis)
		_place_ball("brow_" + sd, head + head_basis * Vector3(s * 0.058, 0.07, -0.135), Vector3(0.06, 0.012, 0.02), head_basis)
	_place_ball("shoulder_r", sh_r, Vector3(0.15, 0.13, 0.14), spine)
	_place_ball("shoulder_l", sh_l, Vector3(0.15, 0.13, 0.14), spine)
	var hand_r := _arm("r", sh_r, _hand_r, _pole_r)
	var hand_l := _arm("l", sh_l, _hand_l, Vector3(-0.6, -1.0, 0.5))
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
	_draw_weapon(st, w, hand_r, hand_l, dead, pose)

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


## Notice a release (bow string / slingshot bands spring) and how long a full draw has been held.
func _track_release(st: Sim.PlayerState, w: int, delta: float) -> void:
	_release_t += delta
	if st == null or Weapons.is_melee(w):
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

	if Weapons.is_melee(w) and st.atk > 0:
		var mv := Weapons.move(w, st.combo)
		var t := 1.0 - float(st.atk) / float(mv.swing)
		var h := float(mv.windup) / float(mv.swing)
		var k := _sample(_move_keys(mv.name, h, p), t)
		for key in k.keys():
			p[key] = k[key]
		p.snap = true
		if w == Weapons.CLUB:
			p.hand_l = p.hand_r - (p.wdir as Vector3).normalized() * 0.14 + Vector3(-0.04, 0, 0)
		return p

	if not Weapons.is_melee(w):
		var d := Weapons.get_data(w)
		var pull := clampf(float(st.charge) / float(d.draw), 0.0, 1.0)
		var drawing := st.charge > 0
		var releasing := not drawing and st.atk > 0
		var reloading := not drawing and st.atk == 0 and st.atk_cd > 0
		if not (drawing or releasing or reloading):
			return p
		# side-on to the target, head kept on it; the left shoulder leads
		p.aim = true
		p.twist = -0.95
		p.look = 0.95 * 0.55
		var shoulder_l := Vector3(-0.21 * cos(-0.95), 1.49, 0.21 * sin(-0.95))
		var grip := shoulder_l + Vector3(0.0, -0.01, -(UPPER_ARM + FOREARM) * 0.96)   # bow arm straight out, level
		var anchor := grip + Vector3(0.03, 0.08, DRAW_LEN)   # at the jaw, along the arrow line
		p.hand_l = grip
		if _hold_t > 0.8:   # holding a full draw: the arms start to tremble
			var tr := sin(_t * 41.0) * 0.004 + sin(_t * 23.0) * 0.003
			p.hand_l += Vector3(tr, tr * 0.6, 0)
		p.pole_r = Vector3(1.0, 0.55, 1.0)   # drawing elbow high and back
		if w == Weapons.BOW:
			p.wdir = Vector3(0.12, 1.0, 0.0)   # stave up, a slight cant
			p.wroll = Vector3(0, 0, 1)
			var nock := grip + Vector3(0.0, 0.0, 0.12)
			if drawing:
				p.hand_r = nock.lerp(anchor, _ease_draw(pull))
			elif releasing:   # the hand follows through past the ear
				var f := clampf(1.0 - float(st.atk) / float(d.shot), 0.0, 1.0)
				p.hand_r = anchor + Vector3(0.1, 0.03, 0.16) * _smooth(minf(f * 3.0, 1.0))
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
		"jab":
			return [[0.0, {"hand_r": Vector3(0.18, 1.38, -0.18), "hand_l": Vector3(-0.16, 1.42, -0.22)}],
				[h, {"hand_r": Vector3(0.12, 1.47, -0.66), "hand_l": Vector3(-0.16, 1.42, -0.2), "twist": -0.25, "lean": -0.08}],
				[minf(h + 0.25, 0.9), {"hand_r": Vector3(0.18, 1.4, -0.3), "twist": -0.1}],
				[1.0, {"hand_r": Vector3(0.18, 1.38, -0.18), "hand_l": Vector3(-0.16, 1.42, -0.22), "twist": 0.0, "lean": 0.0}]]
		"cross":
			return [[0.0, {"hand_r": Vector3(0.18, 1.4, -0.2), "hand_l": Vector3(-0.16, 1.4, -0.2)}],
				[h, {"hand_l": Vector3(-0.02, 1.47, -0.68), "hand_r": Vector3(0.2, 1.42, -0.15), "twist": 0.45, "lean": -0.12}],
				[minf(h + 0.25, 0.9), {"hand_l": Vector3(-0.12, 1.42, -0.32), "twist": 0.2}],
				[1.0, {"hand_l": L, "hand_r": R, "twist": 0.0, "lean": 0.0}]]
		"kick":
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
	_place_seg("fore_" + side, elbow, hand, 0.052)
	_place_ball("elbow_" + side, elbow, Vector3.ONE * 0.1)
	# the hand: a slightly flat mitten along the forearm, the thumb on its inner side
	var along := (hand - elbow).normalized()
	var across := along.cross(Vector3.UP if absf(along.y) < 0.9 else Vector3.FORWARD).normalized()
	var hb := Basis(across, along, across.cross(along)).orthonormalized()
	_place_ball("hand_" + side, hand + along * 0.02, Vector3(0.09, 0.11, 0.07), hb)
	_place_ball("thumb_" + side, hand + across * (0.045 if side == "l" else -0.045) + along * 0.01, Vector3(0.035, 0.05, 0.035), hb)
	return hand


func _leg(side: String, hip: Vector3, foot: Vector3) -> void:
	var r := ik(hip, foot, THIGH, SHIN, Vector3(0, 0.2, -1))
	var knee: Vector3 = r[0]
	var ankle: Vector3 = r[1]
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
	if st != null and not Weapons.is_melee(w):
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
		if nocked:
			var aim := (hand_l - nock)
			aim = aim.normalized() if aim.length() > 0.05 else Vector3.FORWARD
			_arrow.transform = Transform3D(Basis.looking_at(aim, Vector3.UP), nock)
			_arrow.visible = true
	elif w == Weapons.SLING and held != null:
		var y := (_wdir as Vector3).normalized()
		var x := Vector3.RIGHT.cross(y).cross(y).normalized() * -1.0
		var z := x.cross(y).normalized()
		held.transform = Transform3D(Basis(x, y, z), hand_l)
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
		held.transform = Transform3D(Basis(x, y, z), hand_r)
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
