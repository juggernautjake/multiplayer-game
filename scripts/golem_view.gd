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
var main = null      # v0.12.2 (Main, untyped: it has no class name): for where players (main.avatars) and Thunderhorn (main.boss_view) are drawn
var golems := {}     # id -> { root, body, head, arm_l, arm_r, leg_l, leg_r, pos, yaw, state, t, hp, stun, seen, mats, owner, label, bar }
## v0.12.2 golem orders, as the server said: owner -> { mode, point, target, age }. Each standing order has a marker
## in the owner's colour: a pulsing ring and a faint shaft of light on the spot to hold (Stay here / Go there), or a
## ring round the feet of the one to attack with the crossed-swords icon over it. Every golem carries a small order
## icon (its owner's colour) while the order isn't Follow, and for a few seconds after any order; when an order
## comes, its golems turn their heads to the spot or the target, and the owner hears a grunt.
var orders := {}
var markers := {}    # owner -> { root, ring, ring_mat, shaft, shaft_mat, icon }
var _grunts := {}


func setup(n: Net, m = null) -> void:
	net = n
	main = m
	net.golems_changed.connect(_on_states)
	net.golem_order_changed.connect(_on_order)


func _owner_color(owner: int) -> Color:
	return net.roster.get(owner, {}).get("color", Color("d9cfc0"))


## A new order (or Follow again) for `owner`'s golems.
func _on_order(owner: int, mode: int, point: Vector3, target: int) -> void:
	if mode == Golems.Order.FOLLOW:
		orders.erase(owner)
	else:
		orders[owner] = { "mode": mode, "point": point, "target": target, "age": 0.0 }
	var any_titan := false
	var mine := 0
	for g: Dictionary in golems.values():
		if g.owner != owner or g.state == Golems.State.DIE:
			continue
		mine += 1
		any_titan = any_titan or g.titan
		g.icon_t = 4.0
		(g.icon as Sprite3D).texture = Icons.texture("o:" + Golems.ORDER_NAMES[mode], _owner_color(owner))
		if mode == Golems.Order.FOLLOW or mode == Golems.Order.REGROUP:
			g.look_owner = true
		else:
			g.look_owner = false
		g.look_t = 1.6
		g.look_yaw = (g.head as Node3D).rotation.y
	if owner == net.my_id and mine > 0:
		var k := "%d%s" % [1 if mode == Golems.Order.ATTACK else 0, "t" if any_titan else ""]
		if not _grunts.has(k):
			_grunts[k] = Synth.grunt(1 if mode == Golems.Order.ATTACK else 0, any_titan)
		Synth.play(self, _grunts[k], -4.0)


## Where a golem order's target is drawn now (a player or challenger, Thunderhorn, a golem, a dummy), or null.
func target_point(t: int):
	if t == Boss.ID:
		return main.boss_view.pos if main != null and main.boss_view != null and main.boss_view.alive else null
	if t > 0:
		if main != null and main.avatars.has(t) and (main.avatars[t] as Node3D).visible:
			return (main.avatars[t] as Node3D).position
		return null
	if t <= -1000:
		var g = golems.get(-1000 - t, null)
		return (g.root as Node3D).position if g != null and g.state != Golems.State.DIE else null
	if t < 0 and -t - 1 < WorldLayout.DUMMIES.size():
		return WorldLayout.DUMMIES[-t - 1]
	return null


## Where an owner's golems should look when an order comes: the spot, the target, or the owner.
func _look_point(g: Dictionary):
	var o = orders.get(g.owner, null)
	if g.get("look_owner", false) or o == null:
		if main != null and main.avatars.has(g.owner):
			return (main.avatars[g.owner] as Node3D).position
		return null
	if o.mode == Golems.Order.ATTACK:
		return target_point(o.target)
	return o.point


func _make_marker(owner: int) -> Dictionary:
	var col := _owner_color(owner)
	var root := Node3D.new()
	add_child(root)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.86
	tm.outer_radius = 1.0
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(col.r, col.g, col.b, 0.85)
	rm.no_depth_test = false
	ring.material_override = rm
	ring.scale = Vector3(1, 0.15, 1)
	ring.position.y = 0.05
	root.add_child(ring)
	var shaft := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.22
	cm.height = 3.0
	shaft.mesh = cm
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(col.r, col.g, col.b, 0.3)
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	shaft.material_override = sm
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shaft.position.y = 1.5
	root.add_child(shaft)
	var icon := Sprite3D.new()
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.no_depth_test = true
	icon.pixel_size = 0.012
	icon.position.y = 3.3
	root.add_child(icon)
	return { "root": root, "ring": ring, "ring_mat": rm, "shaft": shaft, "shaft_mat": sm, "icon": icon, "col": col, "mode": -1 }


## Markers follow the orders: on the spot to hold, or round the target's feet (sized to it), pulsing.
func _update_markers(delta: float) -> void:
	for owner in markers.keys():
		if not orders.has(owner) or orders[owner].mode == Golems.Order.REGROUP:
			(markers[owner].root as Node3D).queue_free()
			markers.erase(owner)
	for owner in orders.keys():
		var o: Dictionary = orders[owner]
		o.age += delta
		if o.mode == Golems.Order.REGROUP:
			continue
		if not markers.has(owner):
			markers[owner] = _make_marker(owner)
		var mk: Dictionary = markers[owner]
		var root: Node3D = mk.root
		if mk.mode != o.mode:
			mk.mode = o.mode
			(mk.icon as Sprite3D).texture = Icons.texture("o:" + Golems.ORDER_NAMES[o.mode], mk.col)
		var at = o.point
		var r := 1.6
		var top := 3.3
		if o.mode == Golems.Order.ATTACK:
			at = target_point(o.target)
			if o.target == Boss.ID:
				r = Boss.RADIUS + 0.4
				top = Boss.HEIGHT + 1.2
			elif o.target <= -1000 and golems.has(-1000 - o.target) and golems[-1000 - o.target].titan:
				r = 1.6
				top = 4.8
			else:
				r = 0.75
				top = 2.6
		root.visible = at != null
		if at == null:
			continue
		root.global_position = Vector3(at.x, at.y, at.z)
		var mine: bool = owner == net.my_id
		var pulse := 0.5 + 0.5 * sin(o.age * 6.0)
		var settle := clampf(1.0 - (o.age - 2.5) / 1.5, 0.0, 1.0)   # bright at first, then quieter
		var base_a := (0.55 + 0.35 * settle) if mine else (0.3 + 0.3 * settle)
		var grow := 1.0 + 0.6 * maxf(0.0, 1.0 - o.age / 0.35)      # it lands with a little shrink
		(mk.ring as Node3D).scale = Vector3(r * grow * (1.0 + 0.06 * pulse), 0.15, r * grow * (1.0 + 0.06 * pulse))
		(mk.ring_mat as StandardMaterial3D).albedo_color.a = base_a * (0.75 + 0.25 * pulse)
		(mk.shaft as Node3D).visible = o.mode != Golems.Order.ATTACK
		(mk.shaft_mat as StandardMaterial3D).albedo_color.a = 0.25 * (0.4 + 0.6 * settle) * (0.8 + 0.2 * pulse)
		var icon: Sprite3D = mk.icon
		icon.position.y = top + 0.12 * sin(o.age * 3.0)
		icon.modulate.a = base_a + 0.1


func _on_states(tick: int, data: Array) -> void:
	var seen := {}
	for e in data:
		var id := int(e[0])
		seen[id] = true
		if not golems.has(id):
			golems[id] = _make(int(e[1]), e.size() > 10 and int(e[10]) == 1, id)
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


func _make(owner: int, titan := false, gid := -1) -> Dictionary:
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
	# v0.12.6: each golem has its own (silly) name, then whose it is
	label.text = "%s (%s's %s)" % [Names.golem(gid, titan), who, "titan" if titan else "golem"] if gid >= 0 \
		else (("Stone Titan (%s)" if titan else "Golem (%s)") % who)
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
	var icon := Sprite3D.new()   # v0.12.2: its order, over its name
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.no_depth_test = true
	icon.pixel_size = 0.0065 if not titan else 0.009
	icon.position.y = 4.65 if titan else 2.12
	icon.visible = false
	root.add_child(icon)
	var o = orders.get(owner, null)
	if o != null:
		icon.texture = Icons.texture("o:" + Golems.ORDER_NAMES[o.mode], _owner_color(owner))
	return { "root": root, "body": body, "head": head, "arm_l": arms[0], "arm_r": arms[1], "leg_l": legs[0], "leg_r": legs[1],
		"pos": root.position, "yaw": 0.0, "state": Golems.State.RISE, "t": 0.0, "hp": Golems.HP, "stun": false,
		"mats": mats, "owner": owner, "label": label, "bar": bar, "phase": 0.0, "flash": 0.0, "pieces": [], "titan": titan,
		"eyes": eyes, "seed": randf() * 10.0, "squash": 0.0, "swing": 0, "landed": true, "thumped": false,
		"icon": icon, "icon_t": 0.0, "look_t": 0.0, "look_owner": false }


## v0.12.2: just after an order, the head turns to the spot / target / owner (within its neck's reach); the order
## icon shows while the order isn't Follow, and for a few seconds after any order.
func _order_look(g: Dictionary, delta: float) -> void:
	var icon: Sprite3D = g.icon
	g.icon_t = maxf(float(g.icon_t) - delta, 0.0)
	var o = orders.get(g.owner, null)
	icon.visible = icon.texture != null and (g.icon_t > 0.0 or (o != null and o.mode != Golems.Order.REGROUP))
	if o == null and g.icon_t <= 0.0:
		icon.texture = null
	icon.modulate.a = clampf(float(g.icon_t) / 0.5, 0.55, 1.0) if o != null else clampf(float(g.icon_t) / 0.5, 0.0, 1.0)
	if g.look_t <= 0.0:
		return
	g.look_t = float(g.look_t) - delta
	var at = _look_point(g)
	if at == null:
		return
	var root: Node3D = g.root
	var d := Vector2(at.x - root.position.x, at.z - root.position.z)
	if d.length() < 0.3:
		return
	var want := wrapf(atan2(-d.x, -d.y) - root.rotation.y, -PI, PI)
	var head: Node3D = g.head
	g.look_yaw = lerp_angle(float(g.get("look_yaw", head.rotation.y)), clampf(want, -1.3, 1.3), clampf(delta * 9.0, 0.0, 1.0))
	head.rotation.y = lerp_angle(head.rotation.y, g.look_yaw, clampf(g.look_t / 0.4, 0.0, 1.0))


func _process(delta: float) -> void:
	_update_markers(delta)
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
		_order_look(g, delta)
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

