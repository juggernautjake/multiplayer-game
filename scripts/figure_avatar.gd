## The 3D test character (the earlier jointed placeholder), the second look besides Pip. It holds the real 3D
## weapons and animates every attack in code from the player's state: the arms and the weapon are aimed along
## directions in the body's frame for each phase (windup, strike, recovery), so each move reads differently:
## club bash / backhand / overhead smash, sword slash / backslash / lunging thrust, fists jab / cross / kick,
## bow (held out left, string drawn to the cheek), slingshot (band drawn back to the chest).
## Same interface as Avatar (Pip): yaw, grounded, dashing, state, model, label, flash(), animate().
class_name FigureAvatar
extends Node3D

const SKIN := Color("f1c9a5")
const PANTS := Color("3b4252")
const ARM_LEN := 0.62

var yaw := 0.0
var grounded := true
var dashing := false
var state: Sim.PlayerState

var model: Node3D
var torso: Node3D
var leg_l: Node3D
var leg_r: Node3D
var arm_l: Node3D
var arm_r: Node3D
var blob: MeshInstance3D
var label: Label3D
var hp_bar: Sprite3D
var held: Node3D           # the weapon in hand
var held_w := -1
var _mats: Array = []
var _last := Vector3.ZERO
var _vel := Vector3.ZERO
var _phase := 0.0
var _t := 0.0
var _have_last := false
var _flash := 0.0
var _slashed_n := -1


func _init(player_name: String, color: Color, show_name: bool) -> void:
	model = Node3D.new()
	add_child(model)
	torso = Node3D.new()
	torso.position.y = 0.92
	model.add_child(torso)
	torso.add_child(_mesh(_capsule(0.3, 0.9), Vector3(0, 0.33, 0), color))
	torso.add_child(_mesh(_sphere(0.25), Vector3(0, 0.95, 0), SKIN))
	for sx in [-0.09, 0.09]:
		torso.add_child(_mesh(_sphere(0.045), Vector3(sx, 1.0, -0.225), Color(0.08, 0.08, 0.1)))
	arm_l = _limb(torso, Vector3(-0.38, 0.62, 0), 0.085, ARM_LEN, color.darkened(0.15), true)
	arm_r = _limb(torso, Vector3(0.38, 0.62, 0), 0.085, ARM_LEN, color.darkened(0.15), true)
	leg_l = _limb(model, Vector3(-0.15, 0.92, 0), 0.11, 0.86, PANTS, false)
	leg_r = _limb(model, Vector3(0.15, 0.92, 0), 0.11, 0.86, PANTS, false)

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
	label.position.y = 2.35
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
	hp_bar.position.y = 2.12
	hp_bar.visible = show_name
	add_child(hp_bar)


func flash() -> void:
	_flash = 0.15


func animate(delta: float, cam: Camera3D) -> void:
	_t += delta
	if not _have_last:
		_last = position
		_have_last = true
	if delta > 0.0:
		_vel = _vel.lerp((position - _last) / delta, clampf(delta * 15.0, 0.0, 1.0))
	_last = position
	rotation.y = yaw
	var speed := Vector2(_vel.x, _vel.z).length()
	var st := state
	var k := 1.0 - clampf(delta * 14.0, 0.0, 1.0)   # blend toward the target pose

	# the weapon in hand follows the selected slot
	var w := st.weapon if st != null else Weapons.FISTS
	if w != held_w:
		if held != null:
			held.queue_free()
		held = WeaponModels.for_weapon(w)
		if held != null:
			held.top_level = true   # placed by hand each frame
			add_child(held)
		held_w = w

	# ---- legs and body from movement
	var lean := 0.0
	var bob := 0.0
	if st != null and st.dead > 0:
		model.rotation.x = lerpf(model.rotation.x, -PI / 2.0, 1.0 - k)   # knocked flat
		model.position.y = lerpf(model.position.y, 0.3, 1.0 - k)
	else:
		model.rotation.x = lerpf(model.rotation.x, 0.0, 1.0 - k)
		if not grounded:
			_swing_limb(leg_l, 0.55, k)
			_swing_limb(leg_r, -0.25, k)
		else:
			_phase += delta * (2.0 + speed * 1.15)
			var amp := clampf(speed / Sim.WALK_SPEED, 0.0, 1.5) * 0.55
			_swing_limb(leg_l, sin(_phase) * amp, k)
			_swing_limb(leg_r, -sin(_phase) * amp, k)
			bob = absf(sin(_phase)) * 0.05 * clampf(speed / Sim.WALK_SPEED, 0.0, 1.0)
			lean = -0.12 * clampf(speed / Sim.SPRINT_SPEED, 0.0, 1.0)
			if speed < 0.3:
				bob = sin(_t * 2.2) * 0.01
		if dashing:
			lean = -0.45
		model.position.y = lerpf(model.position.y, bob, 1.0 - k)

	# ---- arms and weapon: a pose in the body's frame (F forward, R right, U up)
	var pose := _pose(st, speed)
	torso.rotation.x = lerpf(torso.rotation.x, lean + float(pose.get("lean", 0.0)), 1.0 - k)
	torso.rotation.y = lerpf(torso.rotation.y, float(pose.get("twist", 0.0)), 1.0 - (k if not pose.get("snap", false) else 0.2))
	_aim(arm_r, pose.arm_r, k if not pose.get("snap", false) else 0.25)
	_aim(arm_l, pose.arm_l, k)
	if pose.has("kick"):
		_swing_limb(leg_r, float(pose.kick), 0.3)
	if held != null:
		var hand := (arm_l if w == Weapons.BOW else arm_r).global_transform * Vector3(0, -ARM_LEN, 0)
		var wd: Vector3 = _world(pose.weapon)
		var roll: Vector3 = _world(pose.get("roll", Vector3(1, 0, 0)))
		var y := wd.normalized()
		var x := roll.cross(y).normalized() if absf(roll.normalized().dot(y)) < 0.98 else y.cross(Vector3.FORWARD).normalized()
		var z := x.cross(y).normalized()
		held.global_transform = Transform3D(Basis(x, y, z), hand)
		held.visible = model.visible and (st == null or st.dead == 0)
	_swing_fx(st)

	_flash = maxf(_flash - delta, 0.0)
	for mc in _mats:
		(mc[0] as StandardMaterial3D).albedo_color = Color(1, 0.4, 0.4) if _flash > 0.0 else mc[1]
	if st != null:
		var hpk := float(st.hp) / float(Sim.MAX_HP)
		hp_bar.scale.x = maxf(0.9 * hpk, 0.001)
		hp_bar.modulate = Color(0.9, 0.2, 0.2).lerp(Color(0.3, 0.9, 0.3), hpk)
		hp_bar.visible = label.visible and st.dead == 0
	var ground := WorldLayout.ground_height(position.x, position.z, position.y)
	blob.global_position = Vector3(position.x, ground + 0.012, position.z)
	var s := clampf(1.0 - (position.y - ground) / 6.0, 0.35, 1.0)
	blob.scale = Vector3(s, 1, s)


## The pose for this moment: arm_r / arm_l (directions the arms point), weapon (direction of the weapon's length),
## roll (which way its flat faces), twist (torso turn), lean, kick (right leg swing). All in the body's frame:
## x right, y up, z back (forward is -z).
func _pose(st: Sim.PlayerState, speed: float) -> Dictionary:
	var F := Vector3(0, 0, -1)
	var R := Vector3(1, 0, 0)
	var U := Vector3(0, 1, 0)
	var swing_arm := -sin(_phase) * clampf(speed / Sim.WALK_SPEED, 0.0, 1.5) * 0.5
	var rest := { "arm_r": (-U + F * swing_arm).normalized(), "arm_l": (-U - F * swing_arm).normalized(),
		"weapon": (F * 0.8 - U * 0.3).normalized(), "roll": R }
	if st == null or st.dead > 0:
		return rest
	var w := st.weapon
	match w:
		Weapons.CLUB:
			rest.weapon = (U * 0.75 - F * 0.65).normalized()     # resting on the shoulder
			rest.arm_r = (-U * 0.4 + F * 0.6 + R * 0.2).normalized()
		Weapons.BOW:
			rest.weapon = U
			rest.roll = R
		Weapons.SLING:
			rest.weapon = (-U * 0.4 + F * 0.6).normalized()
	if Weapons.is_melee(w) and st.atk > 0:
		var mv := Weapons.move(w, st.combo)
		var p := 1.0 - float(st.atk) / float(mv.swing)      # 0 .. 1 through the move
		var hit := float(mv.windup) / float(mv.swing)       # the moment the blow lands
		var name: String = mv.name
		if name in ["jab", "cross"]:
			var arm := "arm_r" if name == "jab" else "arm_l"
			var ext := _ease_strike(p, hit)
			rest[arm] = (F * (0.3 + 0.7 * ext) - U * (0.6 - 0.6 * ext) + (R if arm == "arm_r" else -R) * 0.1).normalized()
			rest.twist = (0.25 if name == "jab" else -0.35) * ext
			rest.snap = true
			return rest
		if name == "kick":
			var ext := _ease_strike(p, hit)
			rest.kick = 1.5 * ext
			rest.lean = 0.25 * ext
			rest.arm_l = (-U * 0.3 - R * 0.8).normalized()
			rest.arm_r = (-U * 0.3 + R * 0.8).normalized()
			return rest
		if mv.shape == "arc":
			# a horizontal sweep: wind back over one shoulder, then across the body fast, then follow through
			var back := name in ["backhand", "backslash"]
			var a0 := -1.9 if back else 1.9    # start angle (radians, + = to the right)
			var a1 := 1.5 if back else -1.5
			var a: float
			if p < hit:
				a = lerpf(a0 * 0.6, a0, _smooth(p / hit))
			else:
				a = lerpf(a0, a1, _ease_out(clampf((p - hit) / 0.35, 0.0, 1.0)))
			var dir := (F * cos(a) + R * sin(a) + U * 0.15).normalized()
			rest.arm_r = (dir * 0.8 - U * 0.15).normalized()
			rest.weapon = dir
			rest.roll = U
			rest.twist = -a * 0.45
			rest.snap = true
			return rest
		if mv.shape == "smash":
			# overhead: raise high behind the head, hold, then bring it down hard in front
			var b: float
			if p < hit:
				b = lerpf(0.4, -0.35, _smooth(p / hit))       # up and back
			else:
				b = lerpf(-0.35, 2.1, _ease_out(clampf((p - hit) / 0.18, 0.0, 1.0)))
			var dir := (U * cos(b) + F * sin(b)).normalized()
			rest.arm_r = dir
			rest.arm_l = (dir * 0.9 - R * 0.25).normalized()
			rest.weapon = dir
			rest.roll = R
			rest.lean = -0.35 * clampf((p - hit) / 0.2, 0.0, 1.0)
			rest.snap = true
			return rest
		if mv.shape == "thrust":
			# pull back to the hip, then drive straight forward with the lunge
			var ext := _ease_strike(p, hit)
			rest.arm_r = (F * (0.2 + 0.8 * ext) - U * (0.5 - 0.45 * ext) + R * 0.2 * (1.0 - ext)).normalized()
			rest.weapon = (F + U * 0.05).normalized()
			rest.roll = U
			rest.twist = 0.35 - 0.6 * ext
			rest.lean = -0.25 * ext
			rest.snap = true
			return rest
	if not Weapons.is_melee(w) and (st.charge > 0 or st.atk > 0):
		var d := Weapons.get_data(w)
		var pull := clampf(float(st.charge) / float(d.draw), 0.0, 1.0)
		if w == Weapons.BOW:
			rest.arm_l = (F + U * 0.05).normalized()                 # bow arm straight out
			rest.arm_r = (F * (0.9 - 0.75 * pull) + R * (0.15 + 0.35 * pull) + U * 0.15).normalized()   # drawing hand to the cheek
			rest.weapon = U
			rest.roll = R
			rest.twist = 0.25 + 0.25 * pull
		else:
			rest.arm_r = (F + U * 0.1).normalized()
			rest.arm_l = (F * (0.9 - 0.7 * pull) - R * 0.2 + U * 0.05).normalized()
			rest.weapon = (U * 0.85 + F * 0.15).normalized()
			rest.roll = R
		return rest
	return rest


## 0 -> 1 with a quick snap at the hit and a gentle return after.
func _ease_strike(p: float, hit: float) -> float:
	if p < hit:
		return -0.25 * _smooth(p / hit)              # a little pull-back before the strike
	var q := (p - hit) / maxf(1.0 - hit, 0.01)
	return 1.0 - _smooth(clampf((q - 0.35) / 0.65, 0.0, 1.0))


func _smooth(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


func _ease_out(x: float) -> float:
	return 1.0 - (1.0 - x) * (1.0 - x) * (1.0 - x)


func _world(v: Vector3) -> Vector3:
	return global_transform.basis * v


## Point a limb (hanging along its -Y) along `dir` (body frame), blending.
func _aim(limb: Node3D, dir: Vector3, k: float) -> void:
	var d := (torso.global_transform.basis.inverse() * _world(dir)).normalized()
	var y := -d
	var x := Vector3(1, 0, 0) if absf(y.x) < 0.95 else Vector3(0, 0, 1)
	var z := x.cross(y).normalized()
	x = y.cross(z).normalized()
	var target := Basis(x, y, z).get_rotation_quaternion()
	limb.quaternion = limb.quaternion.slerp(target, 1.0 - k)


func _swing_limb(limb: Node3D, angle: float, k: float) -> void:
	limb.rotation.x = lerpf(limb.rotation.x, angle, 1.0 - k)


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


func _limb(parent: Node3D, at: Vector3, radius: float, length: float, color: Color, hand: bool) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	parent.add_child(pivot)
	pivot.add_child(_mesh(_capsule(radius, length), Vector3(0, -length / 2.0, 0), color))
	if hand:
		pivot.add_child(_mesh(_sphere(radius * 1.35), Vector3(0, -length + 0.02, -0.01), SKIN))
	else:
		var foot := _mesh(_capsule(radius * 0.95, 0.32), Vector3(0, -length + 0.05, -0.08), PANTS.darkened(0.4))
		foot.rotation.x = PI / 2.0
		pivot.add_child(foot)
	return pivot


func _mesh(m: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	mi.material_override = mat
	_mats.append([mat, color])
	return mi


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.0)
	return c


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s
