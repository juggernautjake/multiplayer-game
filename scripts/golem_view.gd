## Draws and animates the small, quick stone golems (about 60% of a person's size) from the server's updates (Net.golems_changed, a few times a second), easing
## each one toward where the server says it is. A golem is built from rough stone blocks with moss on its shoulders
## and two glowing amber eyes:
##   rising:   it pushes up out of the ground, shaking, shedding dust;
##   idle:     slow breathing, arms hanging;
##   walking:  heavy steps, legs swinging, arms swinging the other way, the body rocking side to side;
##   slamming: both arms swing up over its head, it leans back, then brings them down hard and leans in;
##   stunned:  violet tint, trembling;
##   crumbling: the blocks fall apart, tumble and sink into the ground.
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


func _on_states(_tick: int, data: Array) -> void:
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
		if int(e[6]) != g.state:
			g.state = int(e[6])
			g.t = float(e[7]) * Config.DT
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
	for x in [-0.11, 0.11]:
		var eye := MeshInstance3D.new()
		var em := BoxMesh.new()
		em.size = Vector3(0.09, 0.06, 0.03)
		eye.mesh = em
		eye.material_override = MagicFx._glow_mat(Color("ff3a1a") if titan else Color("ffb02e"), 5.0 if titan else 4.0)
		eye.position = Vector3(x, 0.14, -0.225)
		head.add_child(eye)
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
		"mats": mats, "owner": owner, "label": label, "bar": bar, "phase": 0.0, "flash": 0.0, "pieces": [], "titan": titan }


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
		root.position = root.position.lerp(g.pos, clampf(delta * 10.0, 0.0, 1.0))
		root.rotation.y = lerp_angle(root.rotation.y, g.yaw, clampf(delta * 10.0, 0.0, 1.0))
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
	match g.state:
		Golems.State.RISE:   # pushes up out of the ground
			var k := clampf(t / (Golems.RISE * Config.DT), 0.0, 1.0)
			sink = (1.0 - ease(k, 0.4)) * 2.3
			arm_x = -1.2 * (1.0 - k)
			body.position.x = randf_range(-0.03, 0.03) * (1.0 - k)
			if randf() < delta * 12.0 * (1.0 - k):
				Fx.burst(get_parent(), root.position + Vector3(randf_range(-0.6, 0.6), 0.1, randf_range(-0.6, 0.6)), Vector3.UP, Color("8a8070"), 3, 2.0, 0.07)
		Golems.State.WALK:
			g.phase += delta * clampf(speed, 0.5, 9.0) * 2.6
			leg_swing = sin(g.phase) * 0.55
			arm_swing = -sin(g.phase) * 0.4
			rock = sin(g.phase) * 0.06
			bob = absf(sin(g.phase)) * 0.06
			lean = 0.08
		Golems.State.ATTACK:   # arms up over the head, leaning back; then the slam, leaning in
			var w := Golems.WINDUP * Config.DT
			if t < w:
				var k := ease(clampf(t / w, 0.0, 1.0), 0.6)
				arm_x = -2.8 * k
				lean = -0.25 * k
			else:
				var k := clampf((t - w) / 0.12, 0.0, 1.0)
				var back := clampf((t - w - 0.35) / 0.4, 0.0, 1.0)
				arm_x = lerpf(-2.8, 0.5, k) * (1.0 - back)
				lean = lerpf(-0.25, 0.35, k) * (1.0 - back)
		_:   # idle: breathing
			bob = sin(t * 2.0) * 0.02
			arm_x = sin(t * 2.0) * 0.04
	if g.state == Golems.State.ATTACK and speed > 0.5:   # swinging on the run: the legs keep going
		g.phase += delta * clampf(speed, 0.5, 9.0) * 2.6
		leg_swing = sin(g.phase) * 0.5
		bob = absf(sin(g.phase)) * 0.05
	if g.stun:
		body.position.x = randf_range(-0.02, 0.02)
		arm_x = 0.1
	root.position.y = g.pos.y - sink
	body.position.y = 0.95 + bob
	body.rotation = Vector3(-lean, 0, rock)
	al.rotation = Vector3(arm_x + arm_swing, 0, -0.08)
	ar.rotation = Vector3(arm_x - arm_swing, 0, 0.08)
	ll.rotation.x = leg_swing
	lr.rotation.x = -leg_swing


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
