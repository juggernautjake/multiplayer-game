## Draws and animates the small, quick stone golems (about 60% of a person's size) from the server's updates (Net.golems_changed, a few times a second), easing
## each one toward where the server says it is. A golem is built from rough stone blocks with moss on its shoulders
## and two glowing amber eyes:
##   rising:   it pushes up out of the ground, shaking, shedding dust;
##   idle:     slow breathing, arms hanging;
##   walking:  heavy steps, legs swinging, arms swinging the other way, the body rocking side to side;
##   slamming: both arms swing up over its head, it leans back, then brings them down hard and leans in;
##   stunned:  violet tint, trembling;
##   crumbling: the blocks fall apart, tumble and sink into the ground.
## v0.8.0: every footfall thuds down with a puff of dust (the titan's crack the ground); its swings alternate between
## the two-fisted overhead slam and a one-armed haymaker that twists the whole body; the leap: a crouch, arms flung
## back, a high arc with the arms raised, and a squashing landing in a burst of dust; hits make it flinch; standing
## guard, its head turns slowly to look about, and its eyes pulse.
class_name GolemView
extends Node3D

const STONE := Color("7d7a74")
const STONE_DARK := Color("5d5a55")
const MOSS := Color("5f7f3a")

var net: Net
var golems := {}     # id -> { root, body, head, arm_l, arm_r, leg_l, leg_r, pos, yaw, state, t, hp, stun, seen, mats, owner, label, bar }


func setup(n: Net) -> void:
	net = n
	net.golems_changed.connect(_on_states)


func _on_states(tick: int, data: Array) -> void:
	var seen := {}
	for e in data:
		var id := int(e[0])
		seen[id] = true
		if not golems.has(id):
			golems[id] = _make(int(e[1]), e.size() > 10 and int(e[10]) == 1)
			(golems[id].root as Node3D).position = Vector3(e[2], e[3], e[4])
		var g: Dictionary = golems[id]
		g.pos = Vector3(e[2], e[3], e[4])
		g.yaw = float(e[5])
		if not g.has("samples"):
			g.samples = []
		g.samples.append([tick, g.pos, g.yaw])   # drawn on the same delayed clock as the players (see _process)
		if g.samples.size() > 16:
			g.samples.pop_front()
		if int(e[6]) != g.state:
			g.state = int(e[6])
			g.t = float(e[7]) * Config.DT
			if g.state == Golems.State.ATTACK:
				g.swing = int(g.get("swing", 0)) + 1
			if g.state == Golems.State.LEAP:
				g.landed = false
		g.hp = int(e[8])
		g.stun = int(e[9]) == 1
	for id in golems.keys():
		if not seen.has(id) and golems[id].state != Golems.State.DIE:
			golems[id].state = Golems.State.DIE
			golems[id].t = 0.0


func flash(id: int) -> void:
	if golems.has(id):
		golems[id].flash = 0.15


func _block(parent: Node3D, size: Vector3, at: Vector3, c: Color, mats: Array) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	mi.material_override = m
	mi.position = at
	parent.add_child(mi)
	mats.append([m, c])
	return mi


func _make(owner: int, titan := false) -> Dictionary:
	var mats := []
	var root := Node3D.new()
	add_child(root)
	var rig := Node3D.new()           # the golem itself, small (or a titan: huge, darker, with red eyes and a glow)
	rig.scale = Vector3.ONE * (Golems.TITAN_SCALE if titan else Golems.SCALE)
	root.add_child(rig)
	var body := Node3D.new()           # everything above the hips; leans and rocks
	body.position.y = 0.95
	rig.add_child(body)
	_block(body, Vector3(0.95, 0.85, 0.6), Vector3(0, 0.42, 0), STONE, mats)            # chest
	_block(body, Vector3(0.7, 0.3, 0.5), Vector3(0, -0.05, 0), STONE_DARK, mats)        # belly
	_block(body, Vector3(0.36, 0.12, 0.62), Vector3(-0.3, 0.86, 0), MOSS, mats)          # moss on the shoulders
	_block(body, Vector3(0.3, 0.1, 0.5), Vector3(0.33, 0.86, 0.05), MOSS, mats)
	var head := Node3D.new()
	head.position = Vector3(0, 0.98, -0.05)
	body.add_child(head)
	_block(head, Vector3(0.48, 0.4, 0.44), Vector3(0, 0.12, 0), STONE, mats)
	_block(head, Vector3(0.5, 0.1, 0.12), Vector3(0, 0.25, -0.2), STONE_DARK, mats)     # brow
	var eyes := []
	for x in [-0.11, 0.11]:
		var eye := MeshInstance3D.new()
		var em := BoxMesh.new()
		em.size = Vector3(0.09, 0.06, 0.03)
		eye.mesh = em
		eye.material_override = MagicFx._glow_mat(Color("ff3a1a") if titan else Color("ffb02e"), 5.0 if titan else 4.0)
		eye.position = Vector3(x, 0.14, -0.225)
		head.add_child(eye)
		eyes.append(eye)
	var arms := []
	for side in [-1.0, 1.0]:
		var sh := Node3D.new()          # shoulder pivot
		sh.position = Vector3(0.62 * side, 0.7, 0)
		body.add_child(sh)
		_block(sh, Vector3(0.34, 0.6, 0.34), Vector3(0, -0.28, 0), STONE_DARK, mats)
		_block(sh, Vector3(0.4, 0.45, 0.4), Vector3(0, -0.78, -0.02), STONE, mats)    # forearm and fist
		arms.append(sh)
	var legs := []
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0.24 * side, 0.95, 0)
		rig.add_child(hip)
		_block(hip, Vector3(0.36, 0.7, 0.4), Vector3(0, -0.4, 0), STONE_DARK, mats)
		_block(hip, Vector3(0.42, 0.22, 0.52), Vector3(0, -0.84, -0.05), STONE, mats)  # foot
		legs.append(hip)
	var label := Label3D.new()
	var who: String = net.roster.get(owner, {}).get("name", "?")
	label.text = ("Stone Titan (%s)" if titan else "Golem (%s)") % who
	if titan:   # a molten glow in its chest
		var core := OmniLight3D.new()
		core.light_color = Color("ff5a1a")
		core.light_energy = 2.0
		core.omni_range = 4.0
		core.position = Vector3(0, 1.4, -0.4)
		rig.add_child(core)
		for mc in mats:
			mc[1] = (mc[1] as Color).darkened(0.25)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 4.2 if titan else 1.75
	label.font_size = 34
	label.outline_size = 10
	label.modulate = Color("d9cfc0")
	label.no_depth_test = true
	root.add_child(label)
	var bar := Sprite3D.new()
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	bar.texture = ImageTexture.create_from_image(img)
	bar.pixel_size = 1.0
	bar.scale = Vector3(0.6, 0.06, 1)
	bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bar.no_depth_test = true
	bar.position.y = 3.95 if titan else 1.58
	root.add_child(bar)
	return { "root": root, "body": body, "head": head, "arm_l": arms[0], "arm_r": arms[1], "leg_l": legs[0], "leg_r": legs[1],
		"pos": root.position, "yaw": 0.0, "state": Golems.State.RISE, "t": 0.0, "hp": Golems.HP, "stun": false,
		"mats": mats, "owner": owner, "label": label, "bar": bar, "phase": 0.0, "flash": 0.0, "pieces": [], "titan": titan,
		"eyes": eyes, "seed": randf() * 10.0, "squash": 0.0, "swing": 0, "landed": true, "thumped": false }


func _process(delta: float) -> void:
	for id in golems.keys():
		var g: Dictionary = golems[id]
		g.t += delta
		var root: Node3D = g.root
		if g.state == Golems.State.DIE:
			if _crumble(g, delta):
				root.queue_free()
				golems.erase(id)
			continue
		var before := root.position
		var at := _interp(g)
		root.position = Vector3(at[0].x, root.position.y, at[0].z)
		root.rotation.y = at[1]
		var speed := Vector2(root.position.x - before.x, root.position.z - before.z).length() / maxf(delta, 1e-4)
		_pose(g, speed, delta)
		var k := float(g.hp) / float(Golems.TITAN_HP if g.titan else Golems.HP)
		(g.bar as Sprite3D).scale.x = maxf(0.6 * k, 0.001)
		(g.bar as Sprite3D).modulate = Color(0.9, 0.3, 0.2).lerp(Color(0.85, 0.8, 0.6), k)
		g.flash = maxf(g.flash - delta, 0.0)
		for mc in g.mats:
			var c: Color = mc[1]
			if g.flash > 0.0:
				c = Color(1, 0.9, 0.85)
			elif g.stun:
				c = c.lerp(Color("a070e0"), 0.5)
			(mc[0] as StandardMaterial3D).albedo_color = c


func _pose(g: Dictionary, speed: float, delta: float) -> void:
	var body: Node3D = g.body
	var al: Node3D = g.arm_l
	var ar: Node3D = g.arm_r
	var ll: Node3D = g.leg_l
	var lr: Node3D = g.leg_r
	var root: Node3D = g.root
	var t: float = g.t
	var lean := 0.0
	var arm_x := 0.0
	var arm_swing := 0.0
	var leg_swing := 0.0
	var rock := 0.0
	var bob := 0.0
	var sink := 0.0
	var twist := 0.0
	var arm_r_extra := Vector3.ZERO
	var lift := 0.0
	var head: Node3D = g.head
	head.rotation.y = lerpf(head.rotation.y, 0.0, clampf(delta * 4.0, 0.0, 1.0))
	match g.state:
		Golems.State.RISE:   # pushes up out of the ground
			var k := clampf(t / (Golems.RISE * Config.DT), 0.0, 1.0)
			sink = (1.0 - ease(k, 0.4)) * 2.3
			arm_x = -1.2 * (1.0 - k)
			body.position.x = randf_range(-0.03, 0.03) * (1.0 - k)
			if randf() < delta * 12.0 * (1.0 - k):
				Fx.burst(get_parent(), root.position + Vector3(randf_range(-0.6, 0.6), 0.1, randf_range(-0.6, 0.6)), Vector3.UP, Color("8a8070"), 3, 2.0, 0.07)
		Golems.State.WALK:
			var before := sin(g.phase)
			g.phase += delta * clampf(speed, 0.5, 9.0) * (1.7 if g.titan else 2.6)
			leg_swing = sin(g.phase) * 0.6
			arm_swing = -sin(g.phase) * 0.45
			rock = sin(g.phase) * (0.1 if g.titan else 0.07)
			bob = -absf(cos(g.phase)) * 0.05 + 0.05   # dips as each foot lands
			lean = 0.1 + clampf(speed / 8.0, 0.0, 1.0) * 0.08
			if signf(before) != signf(sin(g.phase)):   # a foot comes down
				_footfall(g)
		Golems.State.LEAP:   # crouch, spring, a high arc with the arms flung up, then a squashing landing
			var dur := Golems.LEAP_T * Config.DT
			var k := clampf(t / dur, 0.0, 1.0)
			if k < 0.15:
				var c := k / 0.15
				sink = 0.25 * c
				arm_x = 0.9 * c
				lean = 0.3 * c
			else:
				var a := (k - 0.15) / 0.85
				lift = 4.0 * 1.3 * a * (1.0 - a) * (2.5 if g.titan else 1.0)
				arm_x = lerpf(0.9, -2.7, minf(a * 2.0, 1.0))
				leg_swing = 0.35
				lean = lerpf(-0.2, 0.35, a)
			if k >= 1.0 and not g.get("landed", true):
				g.landed = true
				g.squash = 1.0
				Fx.burst(get_parent(), root.position + Vector3(0, 0.15, 0), Vector3.UP, Color("8a8070"), 26, 4.0, 0.08)
				MotionFx.land(get_parent(), root.position, 0.8)
		Golems.State.ATTACK:
			var w := Golems.WINDUP * Config.DT
			var hook: bool = int(g.get("swing", 0)) % 2 == 0 and not g.titan
			if not hook:   # arms up over the head, leaning back; then the slam, leaning in
				if t < w:
					var k := ease(clampf(t / w, 0.0, 1.0), 0.6)
					arm_x = -2.8 * k
					lean = -0.25 * k
				else:
					var k := clampf((t - w) / 0.12, 0.0, 1.0)
					var back := clampf((t - w - 0.35) / 0.4, 0.0, 1.0)
					arm_x = lerpf(-2.8, 0.5, k) * (1.0 - back)
					lean = lerpf(-0.25, 0.35, k) * (1.0 - back)
			else:          # a haymaker: the right fist drawn back, the body coiled, then it swings round through
				if t < w:
					var k := ease(clampf(t / w, 0.0, 1.0), 0.6)
					twist = 0.7 * k
					arm_r_extra = Vector3(-1.2 * k, 0.6 * k, 0.4 * k)
					lean = -0.1 * k
				else:
					var k := clampf((t - w) / 0.1, 0.0, 1.0)
					var back := clampf((t - w - 0.3) / 0.4, 0.0, 1.0)
					twist = lerpf(0.7, -0.8, k) * (1.0 - back)
					arm_r_extra = Vector3(lerpf(-1.2, -1.5, k), lerpf(0.6, -0.9, k), lerpf(0.4, 0.9, k)) * (1.0 - back)
					lean = lerpf(-0.1, 0.3, k) * (1.0 - back)
			if t >= w and not g.get("thumped", false):
				g.thumped = true
				var fwd := Vector3(-sin(root.rotation.y), 0, -cos(root.rotation.y))
				Fx.burst(get_parent(), root.position + fwd * (1.6 if g.titan else 0.7) + Vector3(0, 0.1, 0), Vector3.UP, Color("8a8070"), 10, 3.0, 0.07)
			if t < w:
				g.thumped = false
		_:   # idle: breathing, looking slowly about
			bob = sin(t * 2.0) * 0.02
			arm_x = sin(t * 2.0) * 0.04
			head.rotation.y = sin(t * 0.7 + float(g.get("seed", 0.0))) * 0.55
	if g.state == Golems.State.ATTACK and speed > 0.5:   # swinging on the run: the legs keep going
		g.phase += delta * clampf(speed, 0.5, 9.0) * 2.6
		leg_swing = sin(g.phase) * 0.5
		bob = absf(sin(g.phase)) * 0.05
	if g.stun:
		body.position.x = randf_range(-0.02, 0.02)
		arm_x = 0.1
	# a squash on landing hard, a flinch when hit
	g.squash = maxf(float(g.get("squash", 0.0)) - delta * 4.0, 0.0)
	var sq := float(g.squash)
	var flinch := float(g.flash) / 0.15
	root.position.y = g.pos.y - sink + lift
	(body.get_parent() as Node3D).scale = Vector3.ONE * (Golems.TITAN_SCALE if g.titan else Golems.SCALE) * Vector3(1.0 + 0.25 * sq, 1.0 - 0.3 * sq, 1.0 + 0.25 * sq)
	body.position.y = 0.95 + bob
	body.rotation = Vector3(-lean + 0.35 * flinch, twist, rock)
	al.rotation = Vector3(arm_x + arm_swing, 0, -0.08)
	ar.rotation = Vector3(arm_x - arm_swing, 0, 0.08) + arm_r_extra
	ll.rotation.x = leg_swing
	lr.rotation.x = -leg_swing
	# eyes pulse
	for e in g.get("eyes", []):
		((e as MeshInstance3D).material_override as StandardMaterial3D).emission_energy_multiplier = (5.0 if g.titan else 4.0) * (0.75 + 0.25 * sin(g.t * 3.0 + float(g.get("seed", 0.0))))


## The blocks come apart: each flies off a little, tumbles, falls and sinks. True when it's all gone.
func _crumble(g: Dictionary, delta: float) -> bool:
	var root: Node3D = g.root
	if (g.pieces as Array).is_empty() and g.t < 2.0:
		(g.label as Node3D).visible = false
		(g.bar as Node3D).visible = false
		for n in root.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var gp := mi.global_transform
			mi.get_parent().remove_child(mi)
			root.add_child(mi)
			mi.global_transform = gp
			g.pieces.append([mi, Vector3(randf_range(-2, 2), randf_range(1.0, 3.5), randf_range(-2, 2)), Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))])
		Fx.burst(get_parent(), root.position + Vector3(0, 1.0, 0), Vector3.UP, Color("8a8070"), 30, 3.5, 0.08)
	for pc in g.pieces:
		var mi: MeshInstance3D = pc[0]
		pc[1].y -= 14.0 * delta
		mi.position += pc[1] * delta
		if mi.global_position.y < 0.15:
			mi.global_position.y = 0.15 - minf(g.t * 0.2, 0.6)
			pc[1] = Vector3(pc[1].x * 0.6, 0, pc[1].z * 0.6)
		else:
			mi.rotation += pc[2] * delta
	return g.t > Golems.DIE * Config.DT + 0.4


## A foot comes down: a puff of dust (the titan: a bigger one, and cracks).
func _footfall(g: Dictionary) -> void:
	var root: Node3D = g.root
	if g.titan:
		Fx.burst(get_parent(), root.position + Vector3(0, 0.1, 0), Vector3.UP, Color("8a8070"), 8, 2.5, 0.09)
		MotionFx.puff(get_parent(), root.position, 4, 1.4)
	else:
		MotionFx.puff(get_parent(), root.position, 1, 0.5)


## Where to draw a golem now: between the two updates around the moment other players are drawn at (Net.render_tick:
## a little in the past, so there are updates on both sides), so golems move as smoothly as players and line up with
## them; past the newest update it carries on along its last motion for up to 0.1 s. -> [position, yaw]
func _interp(g: Dictionary) -> Array:
	var ss: Array = g.get("samples", [])
	if ss.is_empty() or net == null:
		return [g.pos, g.yaw]
	var t := net.render_tick + Engine.get_physics_interpolation_fraction()
	if t <= float(ss[0][0]):
		return [ss[0][1], ss[0][2]]
	for i in range(ss.size() - 1):
		var a: Array = ss[i]
		var b: Array = ss[i + 1]
		if t >= float(a[0]) and t <= float(b[0]):
			var w := (t - float(a[0])) / maxf(float(b[0] - a[0]), 1.0)
			return [(a[1] as Vector3).lerp(b[1], w), lerp_angle(float(a[2]), float(b[2]), w)]
	var last: Array = ss[-1]
	if ss.size() >= 2:
		var prev: Array = ss[-2]
		var dt := maxf(float(last[0] - prev[0]), 1.0)
		var ahead := minf(t - float(last[0]), 6.0)
		return [(last[1] as Vector3) + ((last[1] as Vector3) - (prev[1] as Vector3)) / dt * ahead, float(last[2])]
	return [last[1], last[2]]

