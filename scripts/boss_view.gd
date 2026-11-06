## Thunderhorn on screen (v0.10.0, rebuilt in v0.11.0): the sculpted, skinned storm bull (BossModel) drawn from the
## server's state (Net.boss_changed) and events (Net.magic_fx "boss_*"), with the boss bar, the phase banners, the
## Storm Leap's landing marker, the rush's glowing path, rings, ball lightning, homing orbs, and every sound and impact.
## He renders the same in both character styles (Pip and the 3D figure): he is a 3D creature in the 3D world.
##
## Animation, all from his state and how long he's been in it (BossModel.apply poses the skeleton):
##   at rest:  breathing, the head swaying, a snort and a head-shake now and then, a hoof pawing, the tail swishing;
##   moving:   a walking gait (diagonal pairs) and a gallop, strafing side-on, backing off, a crouch and pounce for the
##             hop, a stamping snap-round for the turn, a dip and lunge;
##   attacks:  the charge's head-down hoof scrape, rearing and slamming (stomp and the slams), the horns lit for the
##             beam (the head follows it), bellowing at the sky (call, roar, the howl, the jaw wide), the gore's wound-up
##             hooking head, the tail lash's coil and whip, the leap's deep crouch, tucked flight and heavy landing,
##             the rush's pawing;
##   hurt:     a flinch on big hits, stumbling when staggered, the phase changes (rearing and roaring as the plates
##             crack open with light when enraged; the storm swirling round him at a quarter), the death (he buckles,
##             then comes apart into cloud and lightning).
## Glowing trails (BossModel.Trail) stream from his eyes always, and from whatever part is attacking (horns: charge,
## beam, gore, rush; hooves: stomps, slams, leap, hops, charges; tail: the lash), in the attack's colour: blue normally,
## cyan for the beam, violet for static, white-gold for the Storm Leap, red when enraged.
class_name BossView
extends Node3D

const BLUE := Color("6fb0ff")
const RED := Color("ff4a3a")
const VIOLET := Color("b070ff")
const GOLD := Color("ffe39a")
const CYAN := Color("9ff0ff")
const TEAL := Color("5ff0d0")

var net: Net
var main: Node3D
var fx: MagicFx
var root: Node3D
var model: BossModel
var core_light: OmniLight3D
var beam: MeshInstance3D
var marker: Node3D
var marker_mat: StandardMaterial3D
var path: MeshInstance3D
var ring_nodes: Array = []
var ball_nodes: Array = []
var orb_nodes: Array = []
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
var orbs := PackedVector3Array()
var extra: Array = [0.0, 0.0, 0, 0, 0, 0, 0]
var phase := 0.0
var flinch := 0.0
var alive := false
var hud: CanvasLayer
var bar_fill: ColorRect
var bar_name: Label
var bar_status: Label
var banner: Label
var banner_t := 0.0
var _storm_t := 999.0
var _crack := 0.0
var _flash := 0.0
var _orbs_seen := 0
var _idle_shake := 0.0
var _snort_t := 3.0
var _step_t := 0.0
var _swirl: Array = []
static var _sounds := {}


func setup(n: Net, m: Node3D, mfx: MagicFx) -> void:
	net = n
	main = m
	fx = mfx
	net.boss_changed.connect(_on_state)
	net.magic_fx.connect(_on_fx)
	_build_hud()


# ================================================================ building
func _build() -> void:
	root = Node3D.new()
	add_child(root)
	model = BossModel.new()
	root.add_child(model)
	model.build()
	core_light = OmniLight3D.new()
	core_light.light_color = Color("8fb4ff")
	core_light.light_energy = 3.0
	core_light.omni_range = 14.0
	core_light.position = Vector3(0, 4.5, -0.5)
	root.add_child(core_light)
	beam = MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.25
	bm.bottom_radius = 0.6
	bm.height = 1.0
	beam.mesh = bm
	var bmat := MagicFx._glow_mat(Color("cfe4ff"), 8.0, 0.8)
	bmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam.material_override = bmat
	beam.visible = false
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(beam)
	# the Storm Leap's landing marker: a glowing ring and a disc that fills as the moment comes
	marker = Node3D.new()
	main.add_child(marker)
	var tm := TorusMesh.new()
	tm.inner_radius = 3.6
	tm.outer_radius = 4.0
	tm.rings = 48
	var mr := MeshInstance3D.new()
	mr.mesh = tm
	marker_mat = MagicFx._glow_mat(GOLD, 5.0, 0.9)
	marker_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mr.material_override = marker_mat
	marker.add_child(mr)
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 1.0
	dm.bottom_radius = 1.0
	dm.height = 0.02
	disc.mesh = dm
	disc.name = "fill"
	disc.material_override = marker_mat
	marker.add_child(disc)
	var ml := OmniLight3D.new()
	ml.light_color = GOLD
	ml.light_energy = 3.0
	ml.omni_range = 8.0
	ml.position.y = 1.5
	marker.add_child(ml)
	marker.visible = false
	# the rush's path, glowing on the ground
	path = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.0, 1.0)
	path.mesh = pm
	var pmat := MagicFx._glow_mat(RED, 3.0, 0.5)
	pmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	path.material_override = pmat
	path.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	path.visible = false
	main.add_child(path)


# ================================================================ state from the server
func _on_state(_tick: int, d: Array) -> void:
	if d.is_empty():
		_despawn()
		return
	if not alive:
		_build()
		alive = true
		hud.visible = true
		root.position = Vector3(d[2], d[3], d[4])
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
	if d.size() > 13:
		orbs = d[12]
		extra = d[13]
	Boss.shown_enraged = flags & 8 != 0


func _despawn() -> void:
	alive = false
	state = -1
	Boss.shown_enraged = false
	if root:
		model.free_trails()
		root.queue_free()
		root = null
	for n in [beam, marker, path]:
		if n:
			(n as Node).queue_free()
	beam = null
	marker = null
	path = null
	if _leap_shadow != null:
		_leap_shadow.queue_free()
		_leap_shadow = null
	for n in ring_nodes + ball_nodes + orb_nodes + _swirl:
		(n as Node).queue_free()
	ring_nodes = []
	ball_nodes = []
	orb_nodes = []
	_swirl = []
	if hud:
		hud.visible = false


# ================================================================ every frame
func _process(delta: float) -> void:
	if banner_t > 0.0:
		banner_t -= delta
		banner.modulate.a = clampf(banner_t / 0.6, 0.0, 1.0)
		banner.scale = Vector2.ONE * (1.0 + maxf(banner_t - 2.6, 0.0) * 0.6)
		banner.visible = banner_t > 0.0
	if not alive or root == null:
		return
	state_t += delta
	var enraged := flags & 8 != 0
	var before := root.position
	root.position = root.position.lerp(pos, clampf(delta * 14.0, 0.0, 1.0)) if root.position.distance_to(pos) < 8.0 else pos
	root.rotation.y = lerp_angle(root.rotation.y, yaw, clampf(delta * 12.0, 0.0, 1.0))
	var mv := Vector2(root.position.x - before.x, root.position.z - before.z) / maxf(delta, 1e-4)
	var speed := mv.length()
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var t := state_t
	var p := {}               # pose (see BossModel.apply)
	var gait := 0.0           # 0 standing, 1 walk, 2 gallop
	var shake := 0.0
	var lift := 0.0
	var scrape := -1          # a leg pawing the ground
	var tuck := 0.0           # legs folded (leaping)
	var col := RED if enraged else BLUE
	var hot := 0.0
	var on := {"eye_l": 0.55, "eye_r": 0.55, "tail": 0.15}
	match state:
		Boss.S.ENTER:
			var k := clampf(t / 1.0, 0.0, 1.0)
			lift = (1.0 - k * k) * 30.0
			tuck = 1.0 - k
			if t > 1.0 and t < 1.6:
				p.crouch = 0.8 * (1.0 - (t - 1.0) / 0.6)
			if t > 1.4:
				p.head_up = 0.6
				p.jaw = 0.7
			col = GOLD
			hot = 1.0
		Boss.S.IDLE:
			p.bob = sin(t * 2.0) * 0.06
			p.head_yaw = sin(t * 0.9) * 0.18
			p.head_dip = 0.15   # always a little head-low: aggressive
			p.thrash = sin(t * 18.0) * 0.25 * _idle_shake
			p.flare = maxf(0.0, sin(t * 2.0)) * 0.4
		Boss.S.WALK, Boss.S.STRAFE, Boss.S.BACKOFF:
			gait = 1.0
			p.head_dip = 0.25
			p.bend = 0.25 * signf(mv.normalized().cross(fwd)) if state == Boss.S.STRAFE else 0.0
		Boss.S.HOP:
			if t < 10 * Config.DT:
				p.crouch = 0.7
			else:
				tuck = 0.8
				p.pitch = 0.2 if t < 0.4 else -0.15
			on["hoof_FL"] = 0.8
			on["hoof_FR"] = 0.8
		Boss.S.TURN:
			p.bend = 0.4 * sin(t * 6.0)
			scrape = int(t * 10.0) % 4
			p.head_dip = 0.3
			p.thrash = 0.2 * sin(t * 20.0)
		Boss.S.LUNGE:
			p.crouch = 0.4 if t < 0.12 else 0.0
			p.head_dip = 0.5
			gait = 2.0 if t > 0.12 else 0.0
			on["horn_l"] = 0.6
			on["horn_r"] = 0.6
		Boss.S.CHARGE_WIND:
			p.head_dip = 0.6
			p.crouch = 0.25
			p.flare = 1.0
			scrape = 1
			on["horn_l"] = 0.8
			on["horn_r"] = 0.8
			col = Color("ff8a50") if enraged else Color("cfe4ff")
			hot = 0.6
		Boss.S.CHARGE:
			gait = 2.0
			p.head_dip = 0.55
			p.flare = 1.0
			for k in ["horn_l", "horn_r", "hoof_FL", "hoof_FR", "hoof_BL", "hoof_BR"]:
				on[k] = 1.0
			col = Color("ff8a50") if enraged else Color("cfe4ff")
			hot = 1.0
		Boss.S.STOMP_WIND:
			p.pitch = 0.65 * clampf(t / 0.5, 0.0, 1.0)
			p.head_up = 0.35
			p.jaw = 0.35
			on["hoof_FL"] = 1.0
			on["hoof_FR"] = 1.0
			hot = 0.5
		Boss.S.STOMP, Boss.S.SLAMS:
			var period := 0.4 if state == Boss.S.STOMP else 0.6667
			var off := 0.0 if state == Boss.S.STOMP else 0.5
			var cyc := fposmod(t - off + period * 0.5, period) / period
			p.pitch = (0.75 if state == Boss.S.SLAMS else 0.55) * maxf(0.0, sin(cyc * PI)) if t > 0.15 else maxf(0.0, 0.65 - t * 5.0)
			p.jaw = 0.4
			p.head_up = 0.2
			for k in ["hoof_FL", "hoof_FR"]:
				on[k] = 1.0
			col = GOLD if state == Boss.S.SLAMS else col
			hot = 0.8
		Boss.S.BEAM_WIND:
			p.head_up = 0.25 * clampf(t / 0.6, 0.0, 1.0)
			p.jaw = 0.2
			on["horn_l"] = 1.0
			on["horn_r"] = 1.0
			col = CYAN if not enraged else Color("ff9a8a")
			hot = clampf(t / 0.75, 0.0, 1.0) * 1.5
		Boss.S.BEAM:
			p.head_dip = 0.2
			p.jaw = 0.6
			p.head_yaw = wrapf(beam_a - yaw, -PI, PI) * 0.8
			on["horn_l"] = 1.0
			on["horn_r"] = 1.0
			col = CYAN if not enraged else Color("ff9a8a")
			hot = 1.6
		Boss.S.CALL:
			p.pitch = 0.5 * sin(clampf(t / 1.0, 0.0, 1.0) * PI)
			p.head_up = 0.8
			p.jaw = 0.75
			col = Color("c8c0ff")
			hot = 1.2
		Boss.S.ROAR:
			p.head_up = 0.6 * sin(clampf(t / 1.0, 0.0, 1.0) * PI)
			p.jaw = 0.85 * sin(clampf(t / 1.0, 0.0, 1.0) * PI)
			p.thrash = sin(t * 26.0) * 0.12 if t > 0.25 and t < 0.9 else 0.0
			shake = 0.03 if t > 0.25 and t < 0.9 else 0.0
			col = VIOLET if int(extra[2]) > 0 else col
			hot = 1.0
		Boss.S.BALLS:
			p.head_dip = -0.2 + 0.45 * clampf(t / 0.4, 0.0, 1.0)
			p.jaw = 0.5
			col = VIOLET if int(extra[2]) > 0 else col
			hot = 1.0
		Boss.S.GORE_WIND:
			p.head_dip = 0.55
			p.head_yaw = -0.6
			p.crouch = 0.2
			p.flare = 1.0
			on["horn_l"] = 1.0
			on["horn_r"] = 1.0
			hot = 0.7
		Boss.S.GORE:
			var k := clampf(t / 0.2, 0.0, 1.0)
			p.head_yaw = lerpf(-0.6, 0.9, k)
			p.head_dip = 0.45 - 0.5 * k
			p.thrash = 0.35 * k
			on["horn_l"] = 1.0
			on["horn_r"] = 1.0
			hot = 1.0
		Boss.S.TAIL_WIND:
			p.tail_up = 0.8
			p.lash = -1.0
			p.bend = -0.3
			p.crouch = 0.15
			on["tail"] = 1.0
			col = TEAL if not enraged else col
			hot = 0.6
		Boss.S.TAIL:
			var k := clampf(t / 0.2, 0.0, 1.0)
			p.lash = lerpf(-1.0, 1.4, k) * (1.0 - clampf((t - 0.35) / 0.3, 0.0, 1.0)) + 0.0
			p.bend = 0.35 * k
			p.tail_up = 0.5
			on["tail"] = 1.0
			col = TEAL if not enraged else col
			hot = 1.0
		Boss.S.STAGGER:
			shake = 0.05
			p.roll = sin(t * 9.0) * 0.12
			p.crouch = 0.35
			p.head_dip = 0.4
			p.thrash = sin(t * 7.0) * 0.3
		Boss.S.PHASE:
			var k := clampf((t - 0.3) / 0.5, 0.0, 1.0) * (1.0 - clampf((t - 1.6) / 0.5, 0.0, 1.0))
			p.pitch = 0.75 * k
			p.head_up = 0.8 * k
			p.jaw = 0.9 * k
			p.thrash = sin(t * 30.0) * 0.15 * k
			shake = 0.05 * k
			col = RED if int(extra[3]) >= 1 else BLUE
			if int(extra[3]) >= 2:
				col = VIOLET
			hot = 2.0 * k
		Boss.S.LEAP_WIND:
			var k := clampf(t / 1.4, 0.0, 1.0)
			p.crouch = 1.1 * k
			p.head_dip = 0.25
			p.flare = 1.0
			p.jaw = 0.4 * k
			shake = 0.035 * k
			col = GOLD
			hot = 2.0 * k
			for kk in ["hoof_FL", "hoof_FR", "hoof_BL", "hoof_BR", "horn_l", "horn_r"]:
				on[kk] = k
			if randf() < delta * 30.0 * k:   # lightning gathering into him
				var a := root.position + Vector3(randf_range(-9, 9), randf_range(0.5, 9), randf_range(-9, 9))
				_arc(a, root.position + Vector3(0, 4.0, 0), GOLD, 0.12)
		Boss.S.LEAP:
			var u := clampf(t / (Boss.LEAP_AIR * Config.DT), 0.0, 1.0)
			tuck = 1.0
			p.pitch = 0.35 - u * 0.7
			p.head_up = 0.3
			p.tail_up = -0.5
			col = GOLD
			hot = 2.0
			for kk in ["hoof_FL", "hoof_FR", "hoof_BL", "hoof_BR", "horn_l", "horn_r", "tail"]:
				on[kk] = 1.0
		Boss.S.LEAP_LAND:
			p.crouch = 1.2 * (1.0 - clampf(t / 0.6, 0.0, 1.0))
			p.head_dip = 0.4
			col = GOLD
			hot = 1.2
		Boss.S.HOWL:
			var k := clampf(t / 0.5, 0.0, 1.0) * (1.0 - clampf((t - 4.0) / 0.3, 0.0, 1.0))
			p.head_up = 0.95 * k
			p.jaw = 0.95 * k
			p.pitch = 0.25 * k
			p.thrash = sin(t * 24.0) * 0.06 * k
			shake = 0.03 * k
			col = VIOLET
			hot = 2.0 * k
			if randf() < delta * 20.0 * k:   # arcs crawling over his back
				var a := root.position + Vector3(randf_range(-2, 2), 6.0, randf_range(-3, 3))
				_arc(a, a + Vector3(randf_range(-2, 2), randf_range(0.5, 2.0), randf_range(-2, 2)), VIOLET, 0.1)
		Boss.S.PAW:
			p.head_dip = 0.65
			p.crouch = 0.2
			p.flare = 1.0
			p.roll = sin(t * 4.0) * 0.04
			scrape = 0 if int(t * 2.0) % 2 == 0 else 1
			col = GOLD
			hot = 1.0
			on["horn_l"] = 1.0
			on["horn_r"] = 1.0
		Boss.S.RUSH:
			gait = 2.0
			p.head_dip = 0.6
			p.flare = 1.0
			col = GOLD
			hot = 2.0
			for kk in ["horn_l", "horn_r", "hoof_FL", "hoof_FR", "hoof_BL", "hoof_BR"]:
				on[kk] = 1.0
		Boss.S.RECOVER:
			p.head_dip = 0.45
			p.bob = sin(t * 9.0) * 0.07
			p.flare = 0.7 + 0.3 * sin(t * 9.0)
			p.jaw = 0.25
		Boss.S.DEATH:
			var k := clampf(t / 1.2, 0.0, 1.0)
			p.crouch = 1.6 * k
			p.roll = 0.5 * k
			p.head_dip = 0.9 * k
			p.jaw = 0.6
			col = Color("cfe4ff")
			hot = 1.5 * (1.0 - k)
	if enraged and state not in [Boss.S.LEAP_WIND, Boss.S.LEAP, Boss.S.LEAP_LAND, Boss.S.HOWL, Boss.S.SLAMS, Boss.S.PAW, Boss.S.RUSH]:
		col = col.lerp(RED, 0.6)
	if hot > 0.3:
		on["eye_l"] = 1.0
		on["eye_r"] = 1.0
	if gait == 0.0 and speed > 1.0:
		gait = 1.0 if speed < 10.0 else 2.0
	# legs: gait cycles, pawing, tucked
	var legs := [[0.0, 0.0], [0.0, 0.0], [0.0, 0.0], [0.0, 0.0]]
	var rear := float(p.get("pitch", 0.0))
	if gait > 0.0:
		var before_ph := phase
		var dirk := -1.0 if mv.dot(fwd) < -0.5 else 1.0
		phase += delta * (4.5 if gait < 1.5 else 9.5) * dirk
		var amp := 0.45 if gait < 1.5 else 0.85
		var offs := [0.0, PI, PI, 0.0] if gait < 1.5 else [0.0, 0.6, PI, PI + 0.6]
		for i in 4:
			var ph: float = phase + offs[i]
			legs[i] = [sin(ph) * amp, maxf(0.0, -cos(ph)) * amp * 1.3]
			if sin(before_ph + offs[i]) < 0.0 and sin(ph) >= 0.0:
				_hoof_fall(model.anchors["hoof_" + BossModel.LEGS[i]], gait > 1.5)
		p.bob = float(p.get("bob", 0.0)) + absf(sin(phase)) * (0.12 if gait < 1.5 else 0.35)
	else:
		if rear > 0.2:   # rearing: the front legs come up and paddle
			for i in 2:
				legs[i] = [-0.9 - 0.2 * sin(state_t * 8.0 + i), 1.3]
		if scrape >= 0:
			legs[scrape] = [0.35 + sin(t * 9.0) * 0.55, maxf(0.0, cos(t * 9.0)) * 0.9]
			_step_t -= delta
			if _step_t <= 0.0:
				_step_t = 0.35
				var h: Node3D = model.anchors["hoof_" + BossModel.LEGS[scrape]]
				MotionFx.puff(main, Vector3(h.global_position.x, pos.y, h.global_position.z), 3, 1.0)
				_sound("scrape", h.global_position, -4.0)
	if tuck > 0.0:
		for i in 4:
			var back := i >= 2
			legs[i] = [(0.9 if back else -0.9) * tuck, 1.5 * tuck]
	if state == Boss.S.STAGGER:
		for i in 4:
			legs[i] = [sin(state_t * 10.0 + i * 1.7) * 0.25, 0.3]
	# idle life: snorts and head shakes now and then
	if state == Boss.S.IDLE:
		_snort_t -= delta
		if _snort_t <= 0.0:
			_snort_t = randf_range(2.5, 5.0)
			if randf() < 0.5:
				_idle_shake = 1.0
			_snort()
	_idle_shake = maxf(_idle_shake - delta * 1.6, 0.0)
	flinch = maxf(flinch - delta * 4.0, 0.0)
	p.roll = float(p.get("roll", 0.0)) + randf_range(-shake, shake) * 3.0 + sin(state_t * 30.0) * 0.06 * flinch
	p.head_dip = float(p.get("head_dip", 0.0)) + flinch * 0.25
	model.position = Vector3(randf_range(-shake, shake), lift, 0)
	_smooth_pose(p, delta)
	model.apply(_pose, legs, Time.get_ticks_msec() * 0.001, delta)
	# his colours, the cracks of light that open when he's enraged, a flash when hit hard
	_crack = move_toward(_crack, 1.0 if enraged else 0.0, delta * 0.6)
	_flash = maxf(_flash - delta * 5.0, 0.0)
	model.set_look(col, hot, _crack, _flash)
	model.tick_trails(delta, on, col.lightened(0.2))
	core_light.light_color = col
	core_light.light_energy = (2.0 + randf() * 2.0) * (1.0 + hot * 0.6)
	if state in [Boss.S.BEAM_WIND, Boss.S.BEAM] and randf() < delta * 14.0:
		_arc(model.anchors["horn_l"].global_position, model.anchors["horn_r"].global_position, col, 0.1)
	_update_beam(col)
	_update_marker()
	_update_path(col)
	# fading out as he dies
	if state == Boss.S.DEATH:
		var k := clampf((state_t - 1.2) / 1.6, 0.0, 1.0)
		model.scale = Vector3.ONE * BossModel.S * (1.0 - k * 0.9)
		if randf() < delta * 12.0 * (1.0 - k):
			fx._smoke(root.position + Vector3(randf_range(-3, 3), 3.0, randf_range(-3, 3)), 1, 0.6, 3.0, 0.5)
	# below a quarter of his health the storm hangs over the arena and swirls round him
	if flags & 32:
		_storm_t -= delta
		if _storm_t <= 0.0:
			_storm_t = 28.0
			fx._storm(Vector3(WorldLayout.ALTAR_C.x, 5.0, WorldLayout.ALTAR_C.y + 10.0), 30.0, 22.0)
		_update_swirl(delta, col)
	# the static field: little arcs crackling over the ground round his hooves, all the time
	if state != Boss.S.DEATH and state != Boss.S.ENTER and randf() < delta * (16.0 if enraged else 10.0):
		var a0 := randf() * TAU
		var r0 := randf_range(1.0, Boss.RADIUS + 1.2)
		var g := Vector3(root.position.x, pos.y + 0.08, root.position.z)
		var p0 := g + Vector3(cos(a0) * r0, 0, sin(a0) * r0)
		var p1 := g + Vector3(cos(a0 + 0.5) * (r0 + 0.8), 0, sin(a0 + 0.5) * (r0 + 0.8))
		_arc(p0, p1, col, 0.12)
	_draw_rings()
	_draw_balls(col)
	_draw_orbs(delta)
	_update_hud(enraged)


var _pose := {}


## The pose eases toward what the state wants (snappier for big moves).
func _smooth_pose(p: Dictionary, delta: float) -> void:
	for k in ["pitch", "crouch", "head_dip", "head_up", "head_yaw", "jaw", "bend", "roll", "thrash", "lash", "tail_up", "flare", "bob", "arch", "twist"]:
		var want := float(p.get(k, 0.0 if k != "jaw" else 0.05))
		var cur := float(_pose.get(k, want))
		var rate := 30.0 if k in ["roll", "thrash", "bob"] else 11.0
		_pose[k] = lerpf(cur, want, clampf(delta * rate, 0.0, 1.0))


func _arc(a: Vector3, b: Vector3, c: Color, life: float) -> void:
	var arc := fx._ribbons([[MagicFx._fractal(a, b, 3, 0.3), 0.04]], c, 6.0)
	var tw := arc.create_tween()
	tw.tween_property(arc.material_override, "albedo_color:a", 0.0, life)
	tw.tween_callback(arc.queue_free)


func _hoof_fall(hoof: Node3D, big: bool) -> void:
	var at := hoof.global_position
	Fx.burst(main, at, Vector3.UP, Color("cfe4ff"), 8 if big else 4, 4.0 if big else 2.5, 0.04)
	MotionFx.puff(main, Vector3(at.x, pos.y, at.z), 3 if big else 2, 1.2)
	if big:
		fx._shake_near_scaled(at, 0.08)
	if randf() < (0.6 if big else 0.3):
		_sound("hoof", at, -2.0 if big else -8.0)


func _snort() -> void:
	if root == null:
		return
	_sound("snort", root.position, -2.0)
	var nose: Vector3 = model.anchors["eye_l"].global_position.lerp(model.anchors["eye_r"].global_position, 0.5)
	nose += Vector3(-sin(yaw), -0.5, -cos(yaw)) * 1.2
	fx._smoke(nose, 2, 0.3, 0.6, 0.35)


func _update_beam(col: Color) -> void:
	beam.visible = state == Boss.S.BEAM
	if not beam.visible:
		return
	var o: Vector3 = model.anchors["horn_l"].global_position.lerp(model.anchors["horn_r"].global_position, 0.5) + Vector3(0, -1.2, 0)
	o += Vector3(-sin(yaw), 0, -cos(yaw)) * 1.0
	var e := Vector3(root.position.x, pos.y + 0.1, root.position.z) + Vector3(-sin(beam_a), 0, -cos(beam_a)) * 24.0
	beam.global_transform = WizardGarb._xf(o, e)
	(beam.material_override as StandardMaterial3D).albedo_color = Color(col.r, col.g, col.b, 0.55 + randf() * 0.4)
	if randf() < get_process_delta_time() * 25.0:   # a scorched line where it sweeps the ground
		var gp := Vector3(root.position.x, pos.y, root.position.z) + Vector3(-sin(beam_a), 0, -cos(beam_a)) * randf_range(6.0, 24.0)
		Fx.burst(main, gp, Vector3.UP, col, 5, 4.0, 0.05)
		if randf() < 0.3:
			fx._scorch_ragged(gp, 0.8, 3)


var _leap_shadow: MeshInstance3D


func _update_marker() -> void:
	var leaping := state in [Boss.S.LEAP_WIND, Boss.S.LEAP]
	marker.visible = leaping
	if _leap_shadow != null:
		_leap_shadow.visible = state == Boss.S.LEAP
	if not leaping:
		return
	var land := Vector3(float(extra[0]), 0.06, float(extra[1]))
	marker.global_position = land
	var total := (90 + Boss.LEAP_AIR) * Config.DT
	var k := clampf((state_t + (90 * Config.DT if state == Boss.S.LEAP else 0.0)) / total, 0.0, 1.0)
	var fill: Node3D = marker.get_node("fill")
	fill.scale = Vector3(4.0 * k, 1, 4.0 * k)
	marker_mat.albedo_color.a = 0.55 + 0.4 * absf(sin(Time.get_ticks_msec() * 0.012))
	marker.rotation.y += get_process_delta_time() * 1.5
	if state == Boss.S.LEAP:
		# v0.12.0: his shadow grows and darkens on the landing spot as he comes down, and lightning streaks behind
		# him through the air
		if _leap_shadow == null:
			_leap_shadow = MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 1.0
			cm.bottom_radius = 1.0
			cm.height = 0.02
			cm.radial_segments = 32
			_leap_shadow.mesh = cm
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(0, 0, 0, 0.0)
			_leap_shadow.material_override = m
			_leap_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			main.add_child(_leap_shadow)
		var u := clampf(state_t / (Boss.LEAP_AIR * Config.DT), 0.0, 1.0)
		_leap_shadow.global_position = land + Vector3(0, 0.03, 0)
		var r := lerpf(1.0, Boss.RADIUS + 2.5, u * u)
		_leap_shadow.scale = Vector3(r, 1, r)
		(_leap_shadow.material_override as StandardMaterial3D).albedo_color.a = 0.15 + 0.6 * u * u
		var dt := get_process_delta_time()
		if root != null and randf() < dt * 24.0:
			var c := root.position + Vector3(0, 4.0, 0)
			var back := Vector3(c.x - land.x, 0, c.z - land.z).normalized()
			var tail := c + back * randf_range(6.0, 12.0) + Vector3(randf_range(-2, 2), randf_range(-1.5, 3.0), randf_range(-2, 2))
			_arc(c + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)), tail, GOLD if randf() < 0.6 else Color.WHITE, 0.18)


func _update_path(col: Color) -> void:
	var show := state in [Boss.S.PAW, Boss.S.CHARGE_WIND]
	path.visible = show
	if not show:
		return
	var len := 30.0
	var k := clampf(state_t / (1.4 if state == Boss.S.PAW else 0.8), 0.0, 1.0)
	var f := Vector3(-sin(root.rotation.y), 0, -cos(root.rotation.y))
	path.global_position = Vector3(root.position.x, pos.y + 0.05, root.position.z) + f * (len * 0.5 + 2.0)
	path.rotation = Vector3(0, root.rotation.y, 0)
	path.scale = Vector3(Boss.RADIUS * 1.6, 1, len)
	var m: StandardMaterial3D = path.material_override
	var c := GOLD if state == Boss.S.PAW else col
	m.albedo_color = Color(c.r, c.g, c.b, (0.15 + 0.35 * k) * (0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.02)))
	m.emission = c


func _update_swirl(delta: float, col: Color) -> void:
	while _swirl.size() < 8:
		var q := QuadMesh.new()
		q.size = Vector2(5, 3)
		var m := ShaderMaterial.new()
		m.shader = BossModel._shader(BossModel.SMOKE_SHADER)
		m.set_shader_parameter("seed", randf() * 40.0)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		main.add_child(mi)
		_swirl.append(mi)
	var tt := Time.get_ticks_msec() * 0.001
	for i in _swirl.size():
		var a := tt * 0.9 + TAU * i / _swirl.size()
		var r := 7.0 + sin(tt + i) * 1.0
		(_swirl[i] as Node3D).global_position = root.position + Vector3(cos(a) * r, 3.0 + sin(tt * 1.3 + i) * 1.5, sin(a) * r)
		((_swirl[i] as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("storm", col)


func _draw_rings() -> void:
	while ring_nodes.size() < rings.size():
		var mi := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.88
		tm.outer_radius = 1.0
		tm.rings = 64
		mi.mesh = tm
		var m := MagicFx._glow_mat(Color("bfd8ff"), 3.0, 0.75)
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		main.add_child(mi)
		ring_nodes.append(mi)
	for i in ring_nodes.size():
		var mi: MeshInstance3D = ring_nodes[i]
		mi.visible = i < rings.size()
		if mi.visible:
			var rr = rings[i]
			var r := float(rr[0]) if rr is Array else float(rr)
			var c := Vector3(float(rr[1]), 0, float(rr[2])) if rr is Array else root.position
			var jump: bool = rr is Array and int(rr[3]) == 1
			mi.global_position = Vector3(c.x, 0.2, c.z)
			mi.scale = Vector3(r, 0.9 if jump else 0.6, r)
			var m: StandardMaterial3D = mi.material_override
			var cc := GOLD if jump else Color("bfd8ff")
			m.albedo_color = Color(cc.r, cc.g, cc.b, 0.9 * clampf(1.0 - r / 24.0, 0.0, 1.0))
			m.emission = cc
			if randf() < 0.5:   # dust and sparks thrown up along it
				var a := randf() * TAU
				var at := Vector3(c.x + cos(a) * r, 0.1, c.z + sin(a) * r)
				Fx.burst(main, at, Vector3.UP, cc, 3, 3.0, 0.04)
				if randf() < 0.3:
					MotionFx.puff(main, at, 1, 0.4)


func _draw_balls(col: Color) -> void:
	while ball_nodes.size() < balls.size():
		var holder := Node3D.new()
		var mi := MeshInstance3D.new()   # a plain damage ball: a smooth blue-white sphere
		var sm := SphereMesh.new()
		sm.radius = 0.4
		sm.height = 0.8
		mi.mesh = sm
		mi.name = "plain"
		mi.material_override = MagicFx._glow_mat(Color("dff0ff"), 8.0)
		var l := OmniLight3D.new()
		l.light_color = Color("9fc4ff")
		l.light_energy = 2.0
		l.omni_range = 4.0
		mi.add_child(l)
		holder.add_child(mi)
		var star := static_star(1.3)   # a Static ball
		star.name = "static"
		holder.add_child(star)
		main.add_child(holder)
		ball_nodes.append(holder)
	var stat_n := 0
	for i in ball_nodes.size():
		var holder: Node3D = ball_nodes[i]
		holder.visible = i < balls.size()
		if holder.visible:
			var b = balls[i]
			var target: Vector3 = b[0] if b is Array else b
			var stat: bool = b is Array and bool(b[1])
			holder.global_position = holder.global_position.lerp(target, 0.5) if holder.global_position.distance_to(target) < 3.0 else target
			var mi: MeshInstance3D = holder.get_node("plain")
			var star: Node3D = holder.get_node("static")
			mi.visible = not stat
			star.visible = stat
			if stat:
				stat_n += 1
				_static_spin(star, get_process_delta_time())
			else:
				mi.scale = Vector3.ONE * (0.95 + 0.1 * randf())
				(mi.material_override as StandardMaterial3D).emission = col.lightened(0.4)
				if randf() < 0.3:
					var c0 := holder.global_position
					_arc(c0, c0 + Vector3(randf_range(-0.8, 0.8), randf_range(-0.8, 0.8), randf_range(-0.8, 0.8)), col, 0.1)
	if stat_n > _stat_seen and root != null:
		_static_seen(root.position)
	_stat_seen = stat_n


## v0.12.0: every Static source (homing orbs, static balls) looks the same, and nothing like his plain blue damage
## balls: a spinning, spiky magenta-violet caltrop (six white-hot spikes round a hot pink core), crackling white,
## trailing violet sparks, with an electric buzz when it appears.
const STATIC_CORE := Color("ff4fd8")
var _static_banner_shown := false
var _orbs_buzzed := 0
var _stat_seen := 0


static func static_star(size := 1.0) -> Node3D:
	var root_n := Node3D.new()
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22 * size
	sm.height = 0.44 * size
	sm.radial_segments = 8
	sm.rings = 4
	core.mesh = sm
	core.material_override = MagicFx._glow_mat(STATIC_CORE, 9.0)
	root_n.add_child(core)
	var spike_mat := MagicFx._glow_mat(Color("fff0ff"), 6.0)
	var dirs := [Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(1, 1, 1).normalized(), Vector3(-1, 1, 1).normalized(), Vector3(1, -1, 1).normalized()]
	for d: Vector3 in dirs:
		var sp := MeshInstance3D.new()
		var cm := CylinderMesh.new()   # a double cone: thick in the middle, needle points at both ends
		cm.top_radius = 0.0
		cm.bottom_radius = 0.07 * size
		cm.height = 0.55 * size
		cm.radial_segments = 4
		cm.rings = 1
		for end in [1.0, -1.0]:
			var half := MeshInstance3D.new()
			half.mesh = cm
			half.material_override = spike_mat
			var y: Vector3 = d * end
			var x: Vector3 = y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
			half.transform = Transform3D(Basis(x, y, x.cross(y)), y * 0.3 * size)
			sp.add_child(half)
		root_n.add_child(sp)
	var shell := MeshInstance3D.new()
	var sh := SphereMesh.new()
	sh.radius = 0.5 * size
	sh.height = 1.0 * size
	sh.radial_segments = 10
	sh.rings = 6
	shell.mesh = sh
	var smat := MagicFx._glow_mat(VIOLET, 2.5, 0.25)
	smat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	shell.material_override = smat
	root_n.add_child(shell)
	return root_n


func _static_spin(n: Node3D, delta: float) -> void:
	n.rotate_y(delta * 9.0)
	n.rotate_x(delta * 5.0)
	if randf() < delta * 30.0:
		Fx.burst(main, n.global_position, Vector3.UP, VIOLET, 2, 1.5, 0.04)
	if randf() < delta * 8.0:
		var c0 := n.global_position
		_arc(c0, c0 + Vector3(randf_range(-0.9, 0.9), randf_range(-0.9, 0.9), randf_range(-0.9, 0.9)), Color("fff0ff"), 0.08)


func _static_seen(at: Vector3) -> void:
	_sound("buzz", at, -4.0)
	if not _static_banner_shown:
		_static_banner_shown = true
		_banner("Violet orbs build STATIC" + char(10) + "6 hits = stun!", VIOLET, 3.5)


## The homing orbs: violet cores in a crackling shell, each trailing sparks; a zip as each one launches.
func _draw_orbs(delta: float) -> void:
	if orbs.size() > _orbs_seen and root != null:
		_sound("chirp", root.position, -6.0)
	_orbs_seen = orbs.size()
	while orb_nodes.size() < orbs.size():
		var mi := static_star(1.1)
		if orb_nodes.size() % 4 == 0:   # a light on every fourth (cheap)
			var l := OmniLight3D.new()
			l.light_color = STATIC_CORE
			l.light_energy = 1.5
			l.omni_range = 5.0
			mi.add_child(l)
		main.add_child(mi)
		orb_nodes.append(mi)
	if orbs.size() > _orbs_buzzed and root != null:
		_static_seen(root.position)
	_orbs_buzzed = orbs.size()
	for i in orb_nodes.size():
		var mi: Node3D = orb_nodes[i]
		mi.visible = i < orbs.size()
		if mi.visible:
			var target := orbs[i]
			mi.global_position = mi.global_position.lerp(target, clampf(delta * 30.0, 0.0, 1.0)) if mi.global_position.distance_to(target) < 4.0 else target
			mi.scale = Vector3.ONE * (0.9 + 0.2 * randf())
			_static_spin(mi, delta)


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
		"static_hit":   # a static stack: sparks crawl over them, a zap
			Fx.burst(main, a[1], Vector3.UP, VIOLET, 10, 3.0, 0.04)
			var near: bool = int(a[0]) == net.my_id
			_sound("zap", a[1], 2.0 if near else -6.0)
			for i in 2:
				_arc(a[1], (a[1] as Vector3) + Vector3(randf_range(-0.7, 0.7), randf_range(-0.6, 0.8), randf_range(-0.7, 0.7)), VIOLET, 0.12)
		"static_stun":   # fully charged: a crack of light, then 7 s stunned
			fx._flash_light((a[1] as Vector3) + Vector3(0, 1.2, 0), VIOLET, 6.0, 8.0, 0.4)
			Fx.burst(main, (a[1] as Vector3) + Vector3(0, 1.0, 0), Vector3.UP, Color("f0e0ff"), 30, 6.0, 0.05)
			_sound("stun", a[1], 4.0)
			if int(a[0]) == net.my_id:
				_banner("STATIC STUN!", VIOLET, 1.6)
		"boss_launch":   # thrown by the rush
			var at: Vector3 = a[1]
			Fx.burst(main, at + Vector3(0, 1, 0), a[2], GOLD, 30, 9.0, 0.06)
			fx._flash_light(at + Vector3(0, 1.5, 0), GOLD, 6.0, 10.0, 0.25)
			fx._shake_near_scaled(at, 0.7)
			_sound("slam", at, 4.0)
		"boss_dodged":
			Fx.burst(main, (a[0] as Vector3) + Vector3(0, 1, 0), Vector3.UP, Color.WHITE, 12, 4.0, 0.04)
			if main.has_method("toast"):
				main.toast("Dodged!")
	if not alive and kind.begins_with("boss_") and kind != "boss_enter":
		return
	match kind:
		"boss_enter":   # the storm gathers; he comes down in a lightning strike
			fx._storm(a[0] + Vector3(0, 6, 0), 6.0, 14.0)
			_banner("THUNDERHORN", Color("cfe4ff"), 3.0)
			get_tree().create_timer(1.0).timeout.connect(func():
				fx._bolt(a[0])
				fx._cracks(a[0], 9.0, 16)
				fx._scorch_ragged(a[0], 5.0, 12)
				fx._shake_near_scaled(a[0], 0.8)
				MotionFx.land(main, a[0], 3.5)
				_sound("thunder", a[0], 6.0)
				_sound("slam", a[0], 6.0))
		"boss_roar":
			var v := int(a[1])
			_sound("roar%d" % clampi(v, 0, 2), a[0], 6.0 if v == 0 else 4.0)
			fx._shake_near_scaled(a[0], 0.4 if v != 2 else 0.3)
			fx._flash_light(a[0] + Vector3(0, 4, 0), Color("ff9a8a") if v == 1 else Color("bfd8ff"), 6.0, 24.0, 0.5)
			_air_ring(a[0], 16.0)
		"boss_roar_wind":
			_snort()
		"boss_enrage":
			if main.has_method("toast"):
				main.toast("Thunderhorn is ENRAGED!")
		"boss_storm":
			_storm_t = 0.0
			if main.has_method("toast"):
				main.toast("Thunderhorn calls the storm!")
		"boss_phase_wind":
			_sound("charge", a[0], 2.0)
		"boss_phase":   # the transformation
			var ph := int(a[1])
			_banner("THUNDERHORN IS ENRAGED" if ph == 1 else "THE STORM BREAKS", RED if ph == 1 else VIOLET, 3.2)
			_sound("roar1", a[0], 7.0)
			_sound("thunder", a[0], 4.0, 0.2)
			fx._flash_light(a[0] + Vector3(0, 4, 0), RED if ph == 1 else VIOLET, 12.0, 30.0, 0.9)
			fx._shake_near_scaled(a[0], 0.7)
			_flash = 1.0
			for i in 5:
				var at: Vector3 = (a[0] as Vector3) + Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
				get_tree().create_timer(0.15 * i).timeout.connect(func(): fx._bolt(at))
			if ph >= 2:
				_storm_t = 0.0
		"boss_charge_wind":
			_snort()
			fx._smoke(a[0], 3, 1.5, 0.8, 0.45)
			if int(a[2]) > 0 and main.has_method("toast"):
				main.toast("Thunderhorn lowers his horns... more than once!")
		"boss_scrape":
			pass   # (the leg's own scrape puffs and sound)
		"boss_charge":
			_sound("roar2", a[0], 0.0)
			_sound("whoosh", a[0], 2.0)
		"boss_skid":
			fx._smoke(a[0], 8, 2.4, 1.2, 0.55)
			MotionFx.land(main, a[0], 2.2)
			fx._scorch_ragged(a[0], 2.5, 6)
			_sound("scrape", a[0], 4.0)
		"boss_rear":
			_sound("snort", a[0], 2.0)
			_sound("whoosh", a[0], -2.0)
		"boss_stomp":
			var at: Vector3 = a[0]
			fx._cracks(at, 5.0, 10)
			MotionFx.land(main, at, 2.8)
			fx._shake_near_scaled(at, 0.5)
			fx._flash_light(at + Vector3(0, 0.5, 0), Color("bfd8ff"), 6.0, 14.0, 0.25)
			fx._scorch_ragged(at + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)), 3.0, 8)
			_sound("slam", at, 2.0)
			_sound("thunder", at, -4.0)
		"boss_beam_wind":
			_sound("crackle", a[0], 2.0)
			_sound("charge", a[0], -4.0)
		"boss_beam":
			_sound("thunder", a[0], -1.0)
			_sound("crackle", a[0], 0.0, 0.6)
		"boss_call":
			fx._flash_light(a[0] + Vector3(0, 10, 0), Color("bfd8ff"), 6.0, 40.0, 0.6)
			_sound("roar2", a[0], 2.0)
		"boss_balls":
			fx._flash_light(a[0] + Vector3(0, 4, 0), VIOLET if int(a[1]) > 0 else Color("dff0ff"), 4.0, 10.0, 0.3)
			_sound("crackle", a[0], 0.0)
		"boss_ball_pop", "boss_orb_pop":
			var st: bool = kind == "boss_orb_pop" or (a.size() > 1 and bool(a[1]))
			Fx.burst(main, a[0], Vector3.UP, VIOLET if st else Color("dff0ff"), 16, 5.0, 0.04)
			fx._flash_light(a[0], VIOLET if st else Color("cfe4ff"), 3.0, 5.0, 0.2)
		"boss_gore_wind":
			_snort()
		"boss_gore":
			_sound("whoosh", a[0], 2.0)
			_sound("roar2", a[0], -4.0)
			var f := Vector3(-sin(float(a[1])), 0, -cos(float(a[1])))
			Fx.burst(main, (a[0] as Vector3) + f * 4.0 + Vector3(0, 3, 0), f, Color("cfe4ff"), 18, 7.0, 0.05)
		"boss_tail_wind":
			_sound("snort", a[0], 0.0)
		"boss_tail":
			_sound("whoosh", a[0], 3.0)
			var b := Vector3(sin(float(a[1])), 0, cos(float(a[1])))
			MotionFx.land(main, (a[0] as Vector3) + b * 5.0, 1.6)
			fx._smoke((a[0] as Vector3) + b * 5.0, 4, 2.0, 0.6, 0.4)
		"boss_snort":
			_snort()
		"boss_hop":
			_sound("whoosh", a[0], 0.0)
			MotionFx.land(main, a[0], 1.5)
		"boss_hop_land":
			MotionFx.land(main, a[0], 2.5)
			fx._shake_near_scaled(a[0], 0.3)
			_sound("hoof", a[0], 4.0)
			fx._cracks(a[0], 3.0, 6)
		"boss_turn":
			_sound("hoof", a[0], 0.0)
			_sound("hoof", a[0], -2.0, 0.15)
			MotionFx.puff(main, a[0], 4, 2.5)
		"boss_lunge":
			_snort()
			_sound("whoosh", a[0], -2.0)
		"boss_leap_wind":   # the Storm Leap begins
			_banner("STORM LEAP", GOLD, 2.2)
			_sound("charge", a[0], 5.0)
			_sound("roar2", a[0], 2.0, 0.6)
			fx._flash_light(a[1] + Vector3(0, 2, 0), GOLD, 4.0, 10.0, 2.5)
			fx._warn_ring(a[1], float(a[2]) * Config.DT)
		"boss_leap":   # v0.12.0 take-off: the ground caves in under him, debris flies, everything shakes
			_sound("whoosh", a[0], 8.0)
			_sound("slam", a[0], 4.0)
			MotionFx.land(main, a[0], 3.5)
			fx._cracks(a[0], 7.0, 14)
			fx._scorch_ragged(a[0], 4.5, 12)
			Fx.burst(main, a[0] + Vector3(0, 0.5, 0), Vector3.UP, Color("6b5a44"), 36, 12.0, 0.12)
			Fx.burst(main, a[0] + Vector3(0, 0.5, 0), Vector3.UP, GOLD, 18, 9.0, 0.05)
			fx._smoke(a[0], 8, 4.0, 2.0, 0.5)
			fx._shake_near_scaled(a[0], 0.9)
		"boss_leap_land":
			var at: Vector3 = a[0]
			fx._bolt(at)
			fx._cracks(at, 10.0, 18)
			fx._scorch_ragged(at, 6.0, 14)
			MotionFx.land(main, at, 5.0)
			fx._shake_near_scaled(at, 1.5)
			fx._flash_light(at + Vector3(0, 2, 0), GOLD, 12.0, 26.0, 0.6)
			fx._flash_light(at + Vector3(0, 8, 0), Color.WHITE, 20.0, 40.0, 0.25)   # the impact flash
			Fx.burst(main, at + Vector3(0, 1, 0), Vector3.UP, GOLD, 40, 10.0, 0.07)
			Fx.burst(main, at + Vector3(0, 0.6, 0), Vector3.UP, Color("6b5a44"), 50, 14.0, 0.14)   # debris
			fx._bolt(at + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5)))
			fx._smoke(at, 10, 5.0, 2.0, 0.6)
			_sound("slam", at, 8.0)
			_sound("thunder", at, 6.0)
			if main.has_method("toast"):
				main.toast("JUMP the ring!")
		"boss_howl":
			_sound("roar4", a[0], 8.0)
			fx._flash_light(a[0] + Vector3(0, 6, 0), VIOLET, 8.0, 30.0, 4.0)
			_air_ring(a[0], 20.0)
		"boss_paw":
			_snort()
			if int(a[2]) == net.my_id:
				_banner("HE'S COMING FOR YOU: DASH SIDEWAYS!", GOLD, 2.0)
		"boss_rush":
			_sound("roar1", a[0], 4.0)
			_sound("whoosh", a[0], 4.0)
			MotionFx.land(main, a[0], 2.5)
		"boss_pant":
			_sound("pant", a[0], 2.0)
			fx._smoke(a[0] + Vector3(-sin(yaw) * 5.0, 3.5, -cos(yaw) * 5.0), 3, 0.5, 1.0, 0.3)
		"boss_stagger":
			flinch = 1.0
			_flash = 0.6
			Fx.burst(main, a[0] + Vector3(0, 5, 0), Vector3.UP, Color("ffe46b"), 20, 4.0, 0.06)
			_sound("roar2", a[0], -2.0)
		"boss_flinch":
			flinch = 0.6
			_flash = 0.4
		"boss_death":   # he bellows, comes apart into cloud and lightning
			_sound("roar3", a[0], 6.0)
			for i in 6:
				get_tree().create_timer(0.3 * i).timeout.connect(func():
					fx._bolt(a[0] + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))))
			fx._shake_near_scaled(a[0], 0.7)
		"boss_leave":
			fx._smoke(a[0], 12, 3.0, 4.0, 0.6)
			fx._bolt(a[0])


## A ring of air blasting out from a roar: dust kicked up along it.
func _air_ring(at: Vector3, r: float) -> void:
	for i in 16:
		var a := TAU * i / 16.0
		var p := at + Vector3(cos(a), 0, sin(a)) * randf_range(r * 0.4, r * 0.7)
		MotionFx.puff(main, p, 1, 0.8)


func _banner(text: String, c: Color, life: float) -> void:
	banner.text = text
	banner.add_theme_color_override("font_color", c)
	banner_t = life
	banner.visible = true


## A sound from somewhere in the world (made once, cached): quieter the farther it is from our player.
func _sound(key: String, at: Vector3, db := 0.0, delay := 0.0) -> void:
	if not _sounds.has(key):
		if key == "thunder":
			_sounds[key] = Synth.thunder()
		elif key.begins_with("roar"):
			_sounds[key] = Synth.roar(int(key.substr(4)))
		else:
			_sounds[key] = Synth.fx(key)
	var st: AudioStream = _sounds[key]
	var d := 0.0
	if fx.avatars.has(net.my_id):
		d = (fx.avatars[net.my_id] as Node3D).position.distance_to(at)
	var vol := db - clampf(d * 0.3, 0.0, 30.0)
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
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	for m in Boss.LEAP_HP:   # ticks where the Storm Leap is guaranteed
		var tick := ColorRect.new()
		tick.color = Color(1.0, 0.9, 0.5, 0.8)
		tick.anchor_left = float(m)
		tick.anchor_right = float(m)
		tick.anchor_bottom = 1.0
		tick.offset_right = 2
		bg.add_child(tick)
	bar_status = Label.new()
	bar_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar_status.anchor_left = 0.42
	bar_status.anchor_right = 0.97
	bar_status.offset_top = 54
	bar_status.add_theme_font_size_override("font_size", 18)
	bar_status.add_theme_constant_override("outline_size", 6)
	bar_status.add_theme_color_override("font_outline_color", Color.BLACK)
	box.add_child(bar_status)
	banner = Label.new()
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.anchor_left = 0.0
	banner.anchor_right = 1.0
	banner.offset_top = 140
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 52)
	banner.add_theme_constant_override("outline_size", 14)
	banner.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.visible = false
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(banner)


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
	if state in Boss.SEQ:
		st.append("[STORM LEAP]")
	bar_status.text = "   ".join(st)
