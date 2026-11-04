## A player's body on screen: a simple jointed placeholder character (legs and arms on hinges at the hips and
## shoulders), animated in code from how it moves: a walk and run cycle that speeds up with speed, a jump pose in the
## air, a forward lean while dashing, breathing when idle. Every client animates every player from the movement it
## already has, so animation costs no network traffic.
##
## Later this is swapped for a rigged model (glTF) driven by an AnimationTree, fed the same numbers (speed, airborne,
## dashing), so nothing else has to change.
class_name Avatar
extends Node3D

const SKIN := Color("f1c9a5")
const PANTS := Color("3b4252")

var model: Node3D         # everything that moves with the body (hidden for your own player in first person)
var torso: Node3D
var leg_l: Node3D
var leg_r: Node3D
var arm_l: Node3D
var arm_r: Node3D
var blob: MeshInstance3D  # contact shadow
var label: Label3D

var _last := Vector3.ZERO
var _vel := Vector3.ZERO
var _phase := 0.0
var _t := 0.0
var _have_last := false


func _init(player_name: String, color: Color, show_name: bool) -> void:
	model = Node3D.new()
	add_child(model)

	torso = Node3D.new()  # pivot at the hips, so the whole upper body can lean
	torso.position.y = 0.92
	model.add_child(torso)
	torso.add_child(_mesh(_capsule(0.3, 0.9), Vector3(0, 0.33, 0), color))
	torso.add_child(_mesh(_sphere(0.25), Vector3(0, 0.95, 0), SKIN))                       # head
	for sx in [-0.09, 0.09]:
		torso.add_child(_mesh(_sphere(0.045), Vector3(sx, 1.0, -0.225), Color(0.08, 0.08, 0.1)))   # eyes
	arm_l = _limb(torso, Vector3(-0.38, 0.62, 0), 0.085, 0.62, color.darkened(0.15), true)
	arm_r = _limb(torso, Vector3(0.38, 0.62, 0), 0.085, 0.62, color.darkened(0.15), true)

	leg_l = _limb(model, Vector3(-0.15, 0.92, 0), 0.11, 0.86, PANTS, false)
	leg_r = _limb(model, Vector3(0.15, 0.92, 0), 0.11, 0.86, PANTS, false)

	blob = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.45
	disc.bottom_radius = 0.45
	disc.height = 0.01
	blob.mesh = disc
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0, 0, 0, 0.35)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blob.material_override = bm
	blob.top_level = true  # placed in world space, on whatever is underneath
	add_child(blob)

	label = Label3D.new()
	label.text = player_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.3
	label.font_size = 48
	label.outline_size = 12
	label.no_depth_test = true
	label.visible = show_name
	add_child(label)


## Call every frame after setting position and rotation.
func animate(delta: float) -> void:
	_t += delta
	if not _have_last:
		_last = position
		_have_last = true
	if delta > 0.0:
		var v := (position - _last) / delta
		_vel = _vel.lerp(v, clampf(delta * 15.0, 0.0, 1.0))  # smooth out frame-to-frame jitter
	_last = position

	var ground := WorldLayout.ground_height(position.x, position.z, position.y)
	var air := position.y > ground + 0.05
	var speed := Vector2(_vel.x, _vel.z).length()
	var dashing := speed > Sim.SPRINT_SPEED + 3.0
	var k := clampf(1.0 - minf(delta * 12.0, 1.0), 0.0, 1.0)  # blend factor toward the new pose

	var legs := 0.0
	var arms := 0.0
	var arm_out := 0.06
	var lean := 0.0
	var bob := 0.0
	if air:
		# jump pose: one knee up, arms lifted out
		_pose(leg_l, 0.55, k)
		_pose(leg_r, -0.25, k)
		_pose(arm_l, -0.35, k)
		_pose(arm_r, -0.35, k)
		arm_out = 0.6
		lean = -0.1
	else:
		_phase += delta * (2.0 + speed * 1.15)
		var amp := clampf(speed / Sim.WALK_SPEED, 0.0, 1.5) * 0.55
		legs = sin(_phase) * amp
		arms = -sin(_phase) * amp * 0.85
		bob = absf(sin(_phase)) * 0.05 * clampf(speed / Sim.WALK_SPEED, 0.0, 1.0)
		lean = -0.12 * clampf(speed / Sim.SPRINT_SPEED, 0.0, 1.0)
		if speed < 0.3:  # idle: breathe
			bob = sin(_t * 2.2) * 0.01
		_pose(leg_l, legs, k)
		_pose(leg_r, -legs, k)
		_pose(arm_l, arms, k)
		_pose(arm_r, -arms, k)
	if dashing:
		lean = -0.45
		_pose(arm_l, 0.9, k)  # arms swept back
		_pose(arm_r, 0.9, k)
	arm_l.rotation.z = lerpf(arm_l.rotation.z, -arm_out, 1.0 - k)
	arm_r.rotation.z = lerpf(arm_r.rotation.z, arm_out, 1.0 - k)
	torso.rotation.x = lerpf(torso.rotation.x, lean, 1.0 - k)
	model.position.y = lerpf(model.position.y, bob, 1.0 - k)

	# the shadow sits on the surface below and shrinks with height above it
	blob.global_position = Vector3(position.x, ground + 0.012, position.z)
	var s := clampf(1.0 - (position.y - ground) / 6.0, 0.35, 1.0)
	blob.scale = Vector3(s, 1, s)


## Swing a limb forward (+) or back (-), blending from its current angle.
func _pose(limb: Node3D, angle: float, k: float) -> void:
	limb.rotation.x = lerpf(limb.rotation.x, angle, 1.0 - k)


## A limb hinged at `at`, hanging down `length`, with a round end (hand or foot).
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
