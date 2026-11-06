## Thunderhorn on screen (v0.10.0): a giant bull made of dark storm cloud, a skeleton of lightning flickering inside
## it, crackling horns, glowing eyes, sparking hooves; drawn from the server's state (Net.boss_changed) and its events
## (Net.magic_fx "boss_*"), with the boss health bar and his status (staggered, slowed, burning, enraged, shielded).
##
## Animation, all from his state and how long he's been in it: coming down out of the sky in a lightning strike;
## breathing at rest, the head swaying, the tail swishing; walking and galloping (four legs on a gait cycle, the body
## bobbing, hooves sparking where they strike); turning; the charge's wind-up (head down, a front hoof scraping) and
## the charge itself; rearing up and slamming down (the stomp); the horns glowing for the beam; bellowing at the sky to
## call lightning; the roar; a flinch when hit hard; staggering; the death (he falls and comes apart into cloud and
## lightning). Enraged, his eyes and lightning burn red-white.
class_name BossView
extends Node3D

var net: Net
var main: Node3D
var fx: MagicFx
var root: Node3D
var body: Node3D
var head: Node3D
var legs: Array = []          # [pivot, lower, hoof]
var tail: Array = []
var eyes: Array = []
var horns: Array = []         # [base, tip] nodes
var cloud_mats: Array = []
var skeleton: MeshInstance3D
var skel_mesh: ImmediateMesh
var skel_mat: StandardMaterial3D
var core_light: OmniLight3D
var beam: MeshInstance3D
var ring_nodes: Array = []
var ball_nodes: Array = []
var state := -1
var state_t := 0.0
var pos := Vector3.ZERO
var yaw := 0.0
var hp := 0
var max_hp := 1
var flags := 0
var beam_a := 0.0
var rings: Array = []
var balls: Array = []
var phase := 0.0
var last_pos := Vector3.ZERO
var flinch := 0.0
var alive := false
var hud: CanvasLayer
var bar_fill: ColorRect
var bar_name: Label
var bar_status: Label
var _skel_t := 0.0
var _storm_t := 999.0
static var _roars := {}
static var _thunder: AudioStreamWAV


func setup(n: Net, m: Node3D, mfx: MagicFx) -> void:
	net = n
	main = m
	fx = mfx
	net.boss_changed.connect(_on_state)
	net.magic_fx.connect(_on_fx)
	_build_hud()


# ================================================================ the model
func _cloud_mat(dark := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.11 - dark, 0.11 - dark, 0.16 - dark, 0.96)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	m.emission_enabled = true
	m.emission = Color("2a3a6a")
	m.emission_energy_multiplier = 0.18
	m.rim_enabled = true
	m.rim = 0.35
	cloud_mats.append(m)
	return m


func _ball(parent: Node3D, at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 14
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = mat
	mi.position = at
	mi.scale = size
	parent.add_child(mi)
	return mi


func _build() -> void:
	root = Node3D.new()
	root.scale = Vector3.ONE * 1.25
	add_child(root)
	body = Node3D.new()              # pivots at the hips, so he can rear up
	body.position = Vector3(0, 0, 1.3)
	root.add_child(body)
	var torso := Node3D.new()
	torso.position = Vector3(0, 0, -1.3)
	body.add_child(torso)
	# the body: lumps of storm cloud, the shoulders humped high
	for spec in [[Vector3(0, 2.0, 1.5), Vector3(1.9, 1.7, 1.9)], [Vector3(0, 2.15, 0.5), Vector3(2.2, 2.0, 2.0)],
			[Vector3(0, 2.45, -0.6), Vector3(2.5, 2.4, 2.1)], [Vector3(0, 2.7, -1.2), Vector3(2.2, 2.0, 1.6)],
			[Vector3(0.5, 1.6, 0.2), Vector3(1.0, 1.0, 1.8)], [Vector3(-0.5, 1.6, 0.2), Vector3(1.0, 1.0, 1.8)]]:
		_ball(torso, spec[0], spec[1], _cloud_mat(randf() * 0.04))
	# the lightning skeleton inside (redrawn as it flickers)
	skel_mesh = ImmediateMesh.new()
	skeleton = MeshInstance3D.new()
	skeleton.mesh = skel_mesh
	skel_mat = StandardMaterial3D.new()
	skel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	skel_mat.vertex_color_use_as_albedo = true
	skel_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	skel_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	skel_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	skeleton.material_override = skel_mat
	skeleton.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	torso.add_child(skeleton)
	core_light = OmniLight3D.new()
	core_light.light_color = Color("8fb4ff")
	core_light.light_energy = 3.0
	core_light.omni_range = 9.0
	core_light.position = Vector3(0, 2.2, -0.3)
	torso.add_child(core_light)
	# the head, its eyes and horns
	head = Node3D.new()
	head.position = Vector3(0, 2.6, -2.3)
	torso.add_child(head)
	_ball(head, Vector3(0, 0, -0.35), Vector3(1.2, 1.1, 1.5), _cloud_mat(0.03))
	_ball(head, Vector3(0, -0.25, -0.95), Vector3(0.85, 0.7, 0.75), _cloud_mat(0.05))   # the muzzle
	for x in [-0.32, 0.32]:
		var e := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.11
		em.height = 0.16
		e.mesh = em
		e.material_override = MagicFx._glow_mat(Color("cfe8ff"), 9.0)
		e.position = Vector3(x, 0.15, -0.95)
		head.add_child(e)
		eyes.append(e)
	for side in [-1.0, 1.0]:   # horns: three tapering segments sweeping out, up and forward
		var pts := [Vector3(0.45 * side, 0.35, -0.3), Vector3(1.0 * side, 0.6, -0.35), Vector3(1.35 * side, 1.05, -0.6), Vector3(1.3 * side, 1.45, -1.05)]
		var hm := StandardMaterial3D.new()
		hm.albedo_color = Color("1c1e2c")
		hm.emission_enabled = true
		hm.emission = Color("9fc4ff")
		hm.emission_energy_multiplier = 0.6
		hm.roughness = 0.5
		for i in 3:
			var seg := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.bottom_radius = 0.17 - i * 0.05
			cm.top_radius = 0.12 - i * 0.05 + 0.005
			cm.height = 1.0
			seg.mesh = cm
			seg.material_override = hm
			head.add_child(seg)
			seg.transform = WizardGarb._xf(pts[i], pts[i + 1])
		horns.append([pts[3], hm])
	# legs: a pivot at the shoulder or hip, thigh and shin of cloud, a dark hoof
	for spec in [[-0.75, -1.3], [0.75, -1.3], [-0.7, 1.5], [0.7, 1.5]]:
		var pv := Node3D.new()
		pv.position = Vector3(spec[0], 1.7, spec[1])
		torso.add_child(pv)
		_ball(pv, Vector3(0, -0.45, 0), Vector3(0.62, 1.15, 0.7), _cloud_mat(0.02))
		var lo := Node3D.new()
		lo.position = Vector3(0, -0.95, 0)
		pv.add_child(lo)
		_ball(lo, Vector3(0, -0.35, 0), Vector3(0.42, 0.95, 0.46), _cloud_mat(0.04))
		var hoof := MeshInstance3D.new()
		var hb := BoxMesh.new()
		hb.size = Vector3(0.42, 0.22, 0.5)
		hoof.mesh = hb
		var hm := StandardMaterial3D.new()
		hm.albedo_color = Color("15161e")
		hm.emission_enabled = true
		hm.emission = Color("6f9cff")
		hm.emission_energy_multiplier = 0.4
		hoof.material_override = hm
		hoof.position = Vector3(0, -0.78, -0.03)
		lo.add_child(hoof)
		legs.append([pv, lo, hoof])
	var tp := Node3D.new()
	tp.position = Vector3(0, 2.3, 2.3)
	torso.add_child(tp)
	var prev := tp
	for i in 3:
		var tn := Node3D.new()
		tn.position = Vector3(0, -0.35, 0.25) if i > 0 else Vector3.ZERO
		prev.add_child(tn)
		_ball(tn, Vector3(0, -0.2, 0.15), Vector3(0.25 - i * 0.05, 0.5, 0.25 - i * 0.05), _cloud_mat(0.03))
		tail.append(tn)
		prev = tn
	beam = MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.18
	bm.bottom_radius = 0.35
	bm.height = 1.0
	beam.mesh = bm
	var bmat := MagicFx._glow_mat(Color("cfe4ff"), 8.0, 0.8)
	bmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam.material_override = bmat
	beam.visible = false
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(beam)


# ================================================================ state from the server
func _on_state(_tick: int, d: Array) -> void:
	if d.is_empty():
		if alive and state != Boss.S.DEATH:
			pass
		_despawn()
		return
	if not alive:
		_build()
		alive = true
		hud.visible = true
		last_pos = Vector3(d[2], d[3], d[4])
	if int(d[0]) != state:
		state = int(d[0])
		state_t = float(d[1]) * Config.DT
	pos = Vector3(d[2], d[3], d[4])
	yaw = float(d[5])
	hp = int(d[6])
	max_hp = maxi(int(d[7]), 1)
	flags = int(d[8])
	beam_a = float(d[9])
	rings = d[10]
	balls = d[11]


func _despawn() -> void:
	alive = false
	state = -1
	if root:
		root.queue_free()
		root = null
	if beam:
		beam.queue_free()
		beam = null
	for n in ring_nodes + ball_nodes:
		(n as Node).queue_free()
	ring_nodes = []
	ball_nodes = []
	legs = []
	tail = []
	eyes = []
	horns = []
	cloud_mats = []
	if hud:
		hud.visible = false


# ================================================================ every frame
func _process(delta: float) -> void:
	if not alive or root == null:
		return
	state_t += delta
	var enraged := flags & 8 != 0
	var before := root.position
	root.position = root.position.lerp(pos, clampf(delta * 12.0, 0.0, 1.0)) if root.position.distance_to(pos) < 6.0 else pos
	root.rotation.y = lerp_angle(root.rotation.y, yaw, clampf(delta * 10.0, 0.0, 1.0))
	var speed := Vector2(root.position.x - before.x, root.position.z - before.z).length() / maxf(delta, 1e-4)
	var t := state_t
	var pitch := 0.0          # the body rearing (+ up)
	var head_dip := 0.0       # + head down
	var head_up := 0.0
	var bob := 0.0
	var gait := 0.0           # 0 standing, 1 walk, 2 gallop
	var shake := 0.0
	var lift := 0.0           # coming down out of the sky
	var sink := 0.0
	match state:
		Boss.S.ENTER:
			var k := clampf(t / 1.0, 0.0, 1.0)
			lift = (1.0 - k * k) * 30.0
			if t > 1.0 and t < 1.5:
				pitch = 0.35 * (1.0 - (t - 1.0) / 0.5)
			head_up = 0.4 if t > 1.3 else 0.0
		Boss.S.IDLE:
			bob = sin(t * 2.0) * 0.05
		Boss.S.WALK:
			gait = 1.0
		Boss.S.CHARGE_WIND:
			head_dip = 0.55
			# a front hoof scraping the ground
			var scrape := sin(t * 14.0)
			(legs[1][0] as Node3D).rotation.x = scrape * 0.5
		Boss.S.CHARGE:
			gait = 2.0
			head_dip = 0.5
		Boss.S.STOMP_WIND:
			pitch = 0.65 * clampf(t / 0.5, 0.0, 1.0)
			head_up = 0.3
		Boss.S.STOMP:
			var cyc := fmod(t, 0.4)
			pitch = maxf(0.0, 0.35 * sin(cyc / 0.4 * PI)) if t > 0.2 else maxf(0.0, 0.65 - t * 6.0)
			shake = 0.02 if cyc < 0.08 else 0.0
		Boss.S.BEAM_WIND:
			head_up = 0.25 * clampf(t / 0.6, 0.0, 1.0)
		Boss.S.BEAM:
			head_dip = 0.15
		Boss.S.CALL:
			pitch = 0.5 * sin(clampf(t / 1.0, 0.0, 1.0) * PI)
			head_up = 0.7
		Boss.S.ROAR:
			head_up = 0.6 * sin(clampf(t / 1.0, 0.0, 1.0) * PI)
			shake = 0.03 if t > 0.25 and t < 0.9 else 0.0
		Boss.S.BALLS:
			head_dip = -0.2 + 0.4 * clampf(t / 0.4, 0.0, 1.0)
		Boss.S.STAGGER:
			shake = 0.05
			bob = -0.15
			head_dip = 0.3
		Boss.S.DEATH:
			sink = clampf(t / 1.5, 0.0, 1.0) * 1.4
			head_dip = 0.8 * clampf(t / 1.2, 0.0, 1.0)
	if gait == 0.0 and speed > 1.0:
		gait = 1.0 if speed < 9.0 else 2.0
	# gait: legs in diagonal pairs (walk) or front and back pairs (gallop), the body bobbing
	if gait > 0.0:
		var before_ph := phase
		phase += delta * (5.0 if gait < 1.5 else 11.0)
		var amp := 0.45 if gait < 1.5 else 0.8
		var offs := [0.0, PI, PI, 0.0] if gait < 1.5 else [0.0, 0.6, PI, PI + 0.6]
		for i in 4:
			var ph: float = phase + offs[i]
			(legs[i][0] as Node3D).rotation.x = sin(ph) * amp
			(legs[i][1] as Node3D).rotation.x = maxf(0.0, -cos(ph)) * amp * 1.2
			if sin(before_ph + offs[i]) < 0.0 and sin(ph) >= 0.0:
				_hoof_spark(legs[i][2], gait > 1.5)
		bob = absf(sin(phase)) * (0.12 if gait < 1.5 else 0.3)
	elif state not in [Boss.S.CHARGE_WIND]:
		for i in 4:
			var l: Node3D = legs[i][0]
			var target := 0.0
			if pitch > 0.2 and i < 2:   # rearing: the front legs come up
				target = -0.9
			if state == Boss.S.DEATH:
				target = 1.1 * clampf(state_t / 1.0, 0.0, 1.0)
			l.rotation.x = lerpf(l.rotation.x, target, clampf(delta * 10.0, 0.0, 1.0))
			(legs[i][1] as Node3D).rotation.x = lerpf((legs[i][1] as Node3D).rotation.x, -0.6 if target < -0.5 else 0.0, clampf(delta * 10.0, 0.0, 1.0))
	flinch = maxf(flinch - delta * 4.0, 0.0)
	body.rotation.x = lerpf(body.rotation.x, pitch, clampf(delta * 12.0, 0.0, 1.0))
	body.rotation.z = randf_range(-shake, shake) * 3.0 + sin(state_t * 30.0) * 0.04 * flinch
	body.position = Vector3(randf_range(-shake, shake), bob + lift - sink, 1.3)
	head.rotation.x = lerpf(head.rotation.x, head_up - head_dip, clampf(delta * 8.0, 0.0, 1.0))
	head.rotation.y = sin(state_t * 0.9) * 0.15 if state == Boss.S.IDLE else lerpf(head.rotation.y, 0.0, delta * 4.0)
	for i in tail.size():
		(tail[i] as Node3D).rotation.z = sin(state_t * 3.0 - i * 0.7) * 0.35
		(tail[i] as Node3D).rotation.x = 0.4 + sin(state_t * 2.0 - i) * 0.15
	# lightning inside him, eyes, horns, the core light: blue-white, red-white when enraged; brighter when attacking
	var col := Color("ffd0c8") if enraged else Color("cfe4ff")
	var hot := 1.0
	if state in [Boss.S.BEAM_WIND, Boss.S.BEAM, Boss.S.CALL, Boss.S.CHARGE]:
		hot = 1.8
	for e in eyes:
		(e.material_override as StandardMaterial3D).emission = Color("ff5a4a") if enraged else Color("cfe8ff")
	for h in horns:
		(h[1] as StandardMaterial3D).emission = col
		(h[1] as StandardMaterial3D).emission_energy_multiplier = 0.6 + (3.0 * clampf(state_t / 0.75, 0.0, 1.0) if state == Boss.S.BEAM_WIND else (3.0 if state == Boss.S.BEAM else 0.0))
	core_light.light_color = Color("ff9a8a") if enraged else Color("8fb4ff")
	core_light.light_energy = (2.0 + randf() * 2.5) * hot
	_skel_t -= delta
	if _skel_t <= 0.0:
		_skel_t = 0.06
		_draw_skeleton(col, hot)
	if state in [Boss.S.BEAM_WIND, Boss.S.BEAM] and randf() < delta * 14.0:
		var a: Vector3 = head.to_global(horns[0][0])
		var b: Vector3 = head.to_global(horns[1][0])
		var arc := fx._ribbons([[MagicFx._fractal(a, b, 3, 0.25), 0.05]], col, 6.0)
		var atw := arc.create_tween()
		atw.tween_property(arc.material_override, "albedo_color:a", 0.0, 0.1)
		atw.tween_callback(arc.queue_free)
	# the beam
	if beam:
		beam.visible = state == Boss.S.BEAM
		if beam.visible:
			var o: Vector3 = head.to_global(Vector3(0, -0.2, -1.1))
			var e: Vector3 = o + Vector3(-sin(beam_a), -0.12, -cos(beam_a)) * 18.0
			beam.global_transform = WizardGarb._xf(o, e)
			var bmat: StandardMaterial3D = beam.material_override
			bmat.albedo_color = Color(col.r, col.g, col.b, 0.55 + randf() * 0.4)
			if randf() < delta * 20.0:
				Fx.burst(main, e, Vector3.UP, col, 4, 4.0, 0.04)
	# fading out as he dies
	if state == Boss.S.DEATH:
		var k := clampf((state_t - 1.2) / 1.6, 0.0, 1.0)
		for m in cloud_mats:
			(m as StandardMaterial3D).albedo_color.a = 0.96 * (1.0 - k)
		if randf() < delta * 10.0 * (1.0 - k):
			fx._smoke(root.position + Vector3(randf_range(-1.5, 1.5), 1.5, randf_range(-1.5, 1.5)), 1, 0.4, 2.0, 0.4)
	# below a quarter of his health the storm hangs over the arena (renewed while it lasts)
	if flags & 32:
		_storm_t -= delta
		if _storm_t <= 0.0:
			_storm_t = 28.0
			fx._storm(Vector3(WorldLayout.ALTAR_C.x, pos.y + 5.0, WorldLayout.ALTAR_C.y + 10.0), 30.0, 22.0)
	# the static field: little arcs crackling over the ground round his hooves, all the time
	if state != Boss.S.DEATH and state != Boss.S.ENTER and randf() < delta * (14.0 if enraged else 9.0):
		var a0 := randf() * TAU
		var r0 := randf_range(0.6, 2.6)
		var g := Vector3(root.position.x, pos.y + 0.08, root.position.z)
		var p0 := g + Vector3(cos(a0) * r0, 0, sin(a0) * r0)
		var p1 := g + Vector3(cos(a0 + 0.6) * (r0 + 0.6), 0, sin(a0 + 0.6) * (r0 + 0.6))
		var sarc := fx._ribbons([[MagicFx._fractal(p0, p1, 2, 0.35), 0.025]], col, 5.0)
		var stw := sarc.create_tween()
		stw.tween_property(sarc.material_override, "albedo_color:a", 0.0, 0.12)
		stw.tween_callback(sarc.queue_free)
	_draw_rings()
	_draw_balls(col)
	_update_hud(enraged)


## The skeleton: a spine of lightning from his rump to his skull, ribs arcing off it, legs; re-jittered every few
## frames so it flickers like lightning in a cloud.
func _draw_skeleton(col: Color, hot: float) -> void:
	skel_mesh.clear_surfaces()
	skel_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var spine := MagicFx._fractal(Vector3(0, 2.2, 1.9), Vector3(0, 2.6, -2.2), 3, 0.06)
	var paths := [[spine, 0.07]]
	for i in 5:
		var at: Vector3 = spine[2 + i]
		for side in [-1.0, 1.0]:
			paths.append([MagicFx._fractal(at, at + Vector3(0.75 * side, -0.7, 0.05), 2, 0.12), 0.035])
	for spec in [[-0.75, -1.3], [0.75, -1.3], [-0.7, 1.5], [0.7, 1.5]]:
		paths.append([MagicFx._fractal(Vector3(spec[0], 1.9, spec[1]), Vector3(spec[0], 0.6, spec[1]), 2, 0.1), 0.04])
	var a := (0.35 + randf() * 0.5) * minf(hot, 1.4)
	var c := Color(col.r, col.g, col.b, a)
	for pw in paths:
		var pts: Array = pw[0]
		var w := float(pw[1])
		for i in pts.size() - 1:
			var p: Vector3 = pts[i]
			var q: Vector3 = pts[i + 1]
			var d := q - p
			if d.length() < 1e-4:
				continue
			var s1 := d.cross(Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT).normalized() * w
			var s2 := d.cross(s1).normalized() * w
			for sv in [s1, s2]:
				for v in [p - sv, p + sv, q + sv, p - sv, q + sv, q - sv]:
					skel_mesh.surface_set_color(c)
					skel_mesh.surface_add_vertex(v)
	skel_mesh.surface_end()


func _hoof_spark(hoof: Node3D, big: bool) -> void:
	var at := hoof.global_position
	Fx.burst(main, at, Vector3.UP, Color("cfe4ff"), 8 if big else 4, 4.0 if big else 2.5, 0.03)
	MotionFx.puff(main, Vector3(at.x, pos.y, at.z), 3 if big else 2, 1.0)
	if big:
		fx._shake_near_scaled(at, 0.05)


func _draw_rings() -> void:
	while ring_nodes.size() < rings.size():
		var mi := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.9
		tm.outer_radius = 1.0
		tm.rings = 48
		mi.mesh = tm
		var m := MagicFx._glow_mat(Color("bfd8ff"), 3.0, 0.75)
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mi.material_override = m
		main.add_child(mi)
		ring_nodes.append(mi)
	for i in ring_nodes.size():
		var mi: MeshInstance3D = ring_nodes[i]
		mi.visible = i < rings.size()
		if mi.visible:
			var r := float(rings[i])
			mi.global_position = Vector3(root.position.x, pos.y + 0.15, root.position.z)
			mi.scale = Vector3(r, 0.5, r)
			(mi.material_override as StandardMaterial3D).albedo_color.a = 0.85 * clampf(1.0 - r / 14.0, 0.0, 1.0)


func _draw_balls(col: Color) -> void:
	while ball_nodes.size() < balls.size():
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.35
		sm.height = 0.7
		mi.mesh = sm
		mi.material_override = MagicFx._glow_mat(Color("dff0ff"), 8.0)
		var l := OmniLight3D.new()
		l.light_color = Color("9fc4ff")
		l.light_energy = 2.0
		l.omni_range = 4.0
		mi.add_child(l)
		main.add_child(mi)
		ball_nodes.append(mi)
	for i in ball_nodes.size():
		var mi: MeshInstance3D = ball_nodes[i]
		mi.visible = i < balls.size()
		if mi.visible:
			var target: Vector3 = balls[i]
			mi.global_position = mi.global_position.lerp(target, 0.5) if mi.global_position.distance_to(target) < 3.0 else target
			mi.scale = Vector3.ONE * (0.9 + 0.25 * randf())
			if randf() < 0.3:
				var c0 := mi.global_position
				var arc := fx._ribbons([[MagicFx._fractal(c0, c0 + Vector3(randf_range(-0.7, 0.7), randf_range(-0.7, 0.7), randf_range(-0.7, 0.7)), 2, 0.3), 0.03]], col, 6.0)
				var atw := arc.create_tween()
				atw.tween_property(arc.material_override, "albedo_color:a", 0.0, 0.1)
				atw.tween_callback(arc.queue_free)


# ================================================================ events
func _on_fx(kind: String, a: Array) -> void:
	match kind:
		"npc_arrive":   # a challenger steps out of a burst of light and dust
			var at: Vector3 = a[1]
			fx._blink(at, true)
			MotionFx.land(main, at, 1.0)
			Fx.burst(main, at + Vector3(0, 1, 0), Vector3.UP, Color("ffd27a"), 30, 5.0, 0.05)
		"npc_leave":
			fx._smoke(a[1], 4, 0.6, 1.6, 0.5)
		"boss_enter":   # the storm gathers; he comes down in a lightning strike
			fx._storm(a[0] + Vector3(0, 6, 0), 6.0, 14.0)
			get_tree().create_timer(1.0).timeout.connect(func():
				fx._bolt(a[0])
				fx._cracks(a[0], 7.0, 14)
				fx._scorch_ragged(a[0], 4.0, 10)
				fx._shake_near_scaled(a[0], 0.6)
				MotionFx.land(main, a[0], 2.5)
				_sound(_thunder_s(), a[0], 6.0))
		"boss_roar":
			var v := int(a[1])
			_sound(_roar(clampi(v, 0, 2)), a[0], 6.0 if v == 0 else 4.0)
			fx._shake_near_scaled(a[0], 0.35 if v != 2 else 0.25)
			fx._flash_light(a[0] + Vector3(0, 3, 0), Color("ff9a8a") if v == 1 else Color("bfd8ff"), 6.0, 20.0, 0.5)
		"boss_enrage":
			_sound(_roar(1), a[0], 6.0)
			fx._flash_light(a[0] + Vector3(0, 3, 0), Color("ff6a5a"), 10.0, 24.0, 0.8)
			fx._shake_near_scaled(a[0], 0.5)
			if net.my_id != 0 and main.has_method("toast"):
				main.toast("Thunderhorn is ENRAGED!")
		"boss_storm":
			_storm_t = 0.0
			if main.has_method("toast"):
				main.toast("Thunderhorn calls the storm!")
		"boss_charge_wind":
			fx._smoke(a[0], 3, 1.0, 0.8, 0.45)
		"boss_charge":
			_sound(_roar(2), a[0], 0.0)
		"boss_skid":
			fx._smoke(a[0], 6, 1.6, 1.0, 0.5)
			MotionFx.land(main, a[0], 1.5)
		"boss_rear":
			pass
		"boss_stomp":
			fx._cracks(a[0], 4.0, 8)
			MotionFx.land(main, a[0], 2.0)
			fx._shake_near_scaled(a[0], 0.4)
			fx._flash_light(a[0] + Vector3(0, 0.5, 0), Color("bfd8ff"), 5.0, 10.0, 0.25)
			_sound(_thunder_s(), a[0], -4.0)
		"boss_beam_wind":
			pass
		"boss_beam":
			_sound(_thunder_s(), a[0], -2.0)
		"boss_call":
			fx._flash_light(a[0] + Vector3(0, 8, 0), Color("bfd8ff"), 6.0, 40.0, 0.6)
			_sound(_roar(2), a[0], 2.0)
		"boss_balls":
			fx._flash_light(a[0] + Vector3(0, 2, 0), Color("dff0ff"), 4.0, 8.0, 0.3)
		"boss_ball_pop":
			Fx.burst(main, a[0], Vector3.UP, Color("dff0ff"), 16, 5.0, 0.04)
			fx._flash_light(a[0], Color("cfe4ff"), 3.0, 5.0, 0.2)
		"boss_stagger":
			flinch = 1.0
			Fx.burst(main, a[0] + Vector3(0, 2.5, 0), Vector3.UP, Color("ffe46b"), 14, 3.0, 0.05)
		"boss_flinch":
			flinch = 0.6
		"boss_death":   # he bellows, comes apart into cloud and lightning
			_sound(_roar(3), a[0], 6.0)
			for i in 4:
				get_tree().create_timer(0.3 * i).timeout.connect(func():
					fx._bolt(a[0] + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))))
			fx._shake_near_scaled(a[0], 0.6)
		"boss_leave":
			fx._smoke(a[0], 10, 2.0, 3.0, 0.6)
			fx._bolt(a[0])


func _roar(kind: int) -> AudioStreamWAV:
	if not _roars.has(kind):
		_roars[kind] = Synth.roar(kind)
	return _roars[kind]


func _thunder_s() -> AudioStreamWAV:
	if _thunder == null:
		_thunder = Synth.thunder()
	return _thunder


## A sound from somewhere in the world: quieter the farther it is from our player.
func _sound(st: AudioStream, at: Vector3, db := 0.0, delay := 0.0) -> void:
	var d := 0.0
	if fx.avatars.has(net.my_id):
		d = (fx.avatars[net.my_id] as Node3D).position.distance_to(at)
	var vol := db - clampf(d * 0.35, 0.0, 30.0)
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(func(): Synth.play(main, st, vol))
	else:
		Synth.play(main, st, vol)


# ================================================================ the health bar
func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.layer = 5
	hud.visible = false
	add_child(hud)
	var box := Control.new()
	box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	box.offset_top = 8
	box.offset_bottom = 80
	hud.add_child(box)
	bar_name = Label.new()
	bar_name.text = "THUNDERHORN"
	bar_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar_name.anchor_left = 0.42
	bar_name.anchor_right = 0.97
	bar_name.add_theme_font_size_override("font_size", 26)
	bar_name.add_theme_constant_override("outline_size", 8)
	bar_name.add_theme_color_override("font_outline_color", Color.BLACK)
	box.add_child(bar_name)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.anchor_left = 0.42
	bg.anchor_right = 0.97
	bg.offset_top = 34
	bg.offset_bottom = 52
	box.add_child(bg)
	bar_fill = ColorRect.new()
	bar_fill.color = Color("c03030")
	bar_fill.anchor_left = 0.0
	bar_fill.anchor_right = 1.0
	bar_fill.anchor_bottom = 1.0
	bar_fill.offset_left = 2
	bar_fill.offset_top = 2
	bar_fill.offset_right = -2
	bar_fill.offset_bottom = -2
	bg.add_child(bar_fill)
	bar_status = Label.new()
	bar_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar_status.anchor_left = 0.42
	bar_status.anchor_right = 0.97
	bar_status.offset_top = 54
	bar_status.add_theme_font_size_override("font_size", 18)
	bar_status.add_theme_constant_override("outline_size", 6)
	bar_status.add_theme_color_override("font_outline_color", Color.BLACK)
	box.add_child(bar_status)


func _update_hud(enraged: bool) -> void:
	var k := float(hp) / float(max_hp)
	bar_fill.anchor_right = clampf(k, 0.0, 1.0)
	bar_fill.color = (Color("ff4040").lerp(Color.WHITE, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012))) if enraged else Color("c03030")
	bar_name.text = "THUNDERHORN   %d / %d" % [hp, max_hp]
	var st := []
	if flags & 16:
		st.append("[INVULNERABLE]")
	if flags & 1:
		st.append("[STAGGERED]")
	if flags & 2:
		st.append("[SLOWED]")
	if flags & 4:
		st.append("[BURNING]")
	if flags & 8:
		st.append("[ENRAGED]")
	if flags & 32:
		st.append("[STORM]")
	bar_status.text = "   ".join(st)
