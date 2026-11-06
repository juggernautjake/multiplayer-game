## Thunderhorn on screen (v0.10.0, rebuilt in v0.11.0): the sculpted, skinned storm bull (BossModel) drawn from the
## server's state (Net.boss_changed) and events (Net.magic_fx "boss_*"), with the boss bar, the phase banners, the
## Storm Leap's landing marker, the rush's glowing path, rings, ball lightning, homing orbs, and every sound and impact.
## He renders the same in both character styles (Pip and the 3D figure): he is a 3D creature in the 3D world.
##
## Animation, all from his state and how long he's been in it (BossModel.apply poses the skeleton):
##   at rest:  breathing, the head swaying, a snort and a head-shake now and then, a hoof pawing, the tail swishing;
##   moving:   (v0.12.0, _locomote) a 4-beat walk, a diagonal trot and a transverse gallop on IK-planted hooves (each
##             foot stays put in the world until it steps; swings land where the body will be), a lift-and-slam
##             footfall, head bob, hump roll, the gallop's rocking and spine flex, leaning into turns, braced skids,
##             a momentum spring (overshoot after braking and turning), a jump for the hop and the Storm Leap
##             (haunches, push, forelegs tucked, reach and absorb), a buck when he snorts at apples underfoot;
##   attacks:  the charge's head-down hoof scrape, rearing on the haunches with the forelegs striking the air and
##             slamming down (stomp, the slams, the howl, call, roar, phase change), the horns lit for the
##             beam (the head follows it), bellowing at the sky (call, roar, the howl, the jaw wide), the gore's wound-up
##             hooking head, the tail lash's coil and whip, the leap's deep crouch, tucked flight and heavy landing,
##             the rush's pawing;
##   hurt:     a flinch on big hits, stumbling when staggered, the phase changes (rearing and roaring as the plates
##             crack open with light when enraged; the storm swirling round him at a quarter), the death (he buckles,
##             then comes apart into cloud and lightning).
## The face: brows furrow in attacks and lift in roars, lids narrow or open wide, the eyes follow his target (extra[4]),
## steam breath (BossModel.breath) from the nostrils and an open roaring mouth.
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
var stun_bg: ColorRect           # v0.12.0 the stun meter under the health bar
var stun_fill: ColorRect
var stun_label: Label
var _stars: Node3D               # v0.12.0 stars circling his head while he's dazed
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
	if _stars != null:
		_stars.queue_free()
		_stars = null
	for n in [beam, marker, path]:
		if n:
			(n as Node).queue_free()
	beam = null
	marker = null
	path = null
	if _leap_shadow != null:
		_leap_shadow.queue_free()
		_leap_shadow = null
	if _leap_pillar != null:
		_leap_pillar.queue_free()
		_leap_pillar = null
	if _arrow != null:
		_arrow.visible = false
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
	var rear := 0.0           # v0.12.0: rearing up on the haunches (0..1), the forelegs striking the air
	var jump := -1.0          # v0.12.0: a jump's stage: 0..1 crouch, 1..3 flight, 3..4 landing
	p.brow = -0.45            # always scowling
	p.lid = 0.35
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
			jump = clampf(t / (10 * Config.DT), 0.0, 1.0) if t < 10 * Config.DT else 1.0 + clampf((t - 10 * Config.DT) / 0.6, 0.0, 1.0) * 2.6
			p.brow = -1.0
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
			p.brow = -1.0
			p.lid = 0.6
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
			p.brow = -1.0
			p.lid = 0.6
			p.head_dip = 0.55
			p.flare = 1.0
			for k in ["horn_l", "horn_r", "hoof_FL", "hoof_FR", "hoof_BL", "hoof_BR"]:
				on[k] = 1.0
			col = Color("ff8a50") if enraged else Color("cfe4ff")
			hot = 1.0
		Boss.S.STOMP_WIND:
			rear = clampf(t / 0.5, 0.0, 1.0)
			p.brow = -1.0
			p.head_up = 0.35
			p.jaw = 0.35
			on["hoof_FL"] = 1.0
			on["hoof_FR"] = 1.0
			hot = 0.5
		Boss.S.STOMP, Boss.S.SLAMS:
			if state == Boss.S.SLAMS:   # v0.12.0: up for 0.5 s before each wave (at 0.5, 1.75 and 3.0 s), down hard on it
				var ph := fposmod(t - 0.5 + 0.55, Boss.WAVE_GAP * Config.DT)
				rear = (clampf(ph / 0.5, 0.0, 1.0) if ph < 0.55 else maxf(0.0, 1.0 - (ph - 0.55) * 5.0)) if t < 3.1 else 0.0
			else:
				var cyc := fposmod(t + 0.2, 0.4) / 0.4
				rear = 0.75 * maxf(0.0, sin(cyc * PI)) if t > 0.15 else maxf(0.0, 1.0 - t * 7.0)
			p.brow = -1.0
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
			rear = 0.75 * sin(clampf(t / 1.0, 0.0, 1.0) * PI)
			p.brow = 1.0
			p.lid = 0.0
			p.tongue = 1.0
			p.head_up = 0.8
			p.jaw = 0.75
			col = Color("c8c0ff")
			hot = 1.2
		Boss.S.ROAR:
			p.head_dip = 0.4 * clampf(t / 0.35, 0.0, 1.0) * (1.0 - clampf((t - 0.45) / 0.15, 0.0, 1.0))   # v0.12.0 the tell
			p.flare = clampf(t / 0.5, 0.0, 1.0)
			t = maxf(t - (Boss.ROAR_AT - 15) * Config.DT, 0.0)   # the roar itself, timed to the server's
			rear = 0.45 * sin(clampf(t / 0.9, 0.0, 1.0) * PI)
			p.brow = 1.0
			p.lid = 0.0
			p.tongue = 1.0
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
			p.brow = -1.0
			p.lid = 0.6
			p.head_dip = 0.55
			p.head_yaw = -0.6
			p.crouch = 0.2
			p.flare = 1.0
			on["horn_l"] = 1.0
			on["horn_r"] = 1.0
			hot = 0.7
		Boss.S.GORE:
			p.brow = -1.0
			p.lid = 0.5
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
			rear = 0.45 * maxf(0.0, 1.0 - t / 0.45) * minf(1.0, t / 0.12)
			p.brow = 0.8
			p.lid = 0.0
			shake = 0.05
			p.roll = sin(t * 9.0) * 0.12
			p.crouch = 0.35
			p.head_dip = 0.4
			p.thrash = sin(t * 7.0) * 0.3
		Boss.S.PHASE:
			var k := clampf((t - 0.3) / 0.5, 0.0, 1.0) * (1.0 - clampf((t - 1.6) / 0.5, 0.0, 1.0))
			rear = k
			p.brow = 1.0
			p.lid = 0.0
			p.tongue = k
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
			jump = k
			p.brow = -1.0
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
			var u := clampf(t / (_leap_air_t() * Config.DT), 0.0, 1.0)
			jump = 1.0 + u * 2.0
			p.head_up = 0.3
			col = GOLD
			hot = 2.0
			for kk in ["hoof_FL", "hoof_FR", "hoof_BL", "hoof_BR", "horn_l", "horn_r", "tail"]:
				on[kk] = 1.0
		Boss.S.LEAP_LAND:
			jump = 3.0 + clampf(t / 0.6, 0.0, 1.0)
			p.head_dip = 0.4
			col = GOLD
			hot = 1.2
		Boss.S.HOWL:
			var k := clampf(t / 0.5, 0.0, 1.0) * (1.0 - clampf((t - 4.0) / 0.3, 0.0, 1.0))
			p.head_up = 0.95 * k
			p.jaw = 0.95 * k
			rear = k * (1.0 - clampf((t - 1.5) / 0.35, 0.0, 1.0))   # up on the haunches, then down hard to howl
			p.brow = 1.0
			p.lid = 0.0
			p.tongue = k
			p.thrash = sin(t * 24.0) * 0.06 * k
			shake = 0.03 * k
			col = VIOLET
			hot = 2.0 * k
			if randf() < delta * 20.0 * k:   # arcs crawling over his back
				var a := root.position + Vector3(randf_range(-2, 2), 6.0, randf_range(-3, 3))
				_arc(a, a + Vector3(randf_range(-2, 2), randf_range(0.5, 2.0), randf_range(-2, 2)), VIOLET, 0.1)
		Boss.S.PAW:
			p.brow = -1.0
			p.lid = 0.65
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
			p.brow = -1.0
			p.lid = 0.6
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
		Boss.S.DAZED:   # v0.12.0 the stun meter filled: stagger, legs buckle, down on his knees and side, dazed, up
			var up_at := Boss.STUN_TICKS * Config.DT - 1.4
			var k := clampf((t - 0.25) / 0.55, 0.0, 1.0)   # buckling
			var g := clampf((t - up_at) / 1.3, 0.0, 1.0)    # struggling up
			var down := k * (1.0 - g * g * (3.0 - 2.0 * g))
			var strain := sin(clampf((t - up_at) / 1.3, 0.0, 1.0) * PI)
			rear = 0.3 * maxf(0.0, 1.0 - t / 0.3) * minf(1.0, t / 0.1)   # the first stagger
			p.crouch = 2.0 * down + 0.2 * strain
			tuck = 0.75 * down
			p.pitch = 0.12 * down
			p.roll = 0.42 * down + sin(t * 10.0) * 0.06 * strain + sin(t * 9.0) * 0.08 * (1.0 - k)
			p.head_dip = 0.75 * down - 0.2 * strain
			p.head_yaw = sin(t * 1.6) * 0.35 * down
			p.thrash = sin(t * 2.3) * 0.12 * down
			p.brow = 0.7
			p.lid = 0.75 * down
			p.jaw = 0.35 * down
			p.tongue = 0.7 * down
			p.flare = 0.4 + 0.4 * strain
			shake = 0.05 * (1.0 - k) + 0.02 * strain
			col = GOLD
			hot = 0.15
		Boss.S.DEATH:
			var k := clampf(t / 1.2, 0.0, 1.0)
			p.crouch = 1.6 * k
			p.roll = 0.5 * k
			p.head_dip = 0.9 * k
			p.jaw = 0.6
			p.lid = 0.3 + 0.7 * k
			p.brow = 0.3
			col = Color("cfe4ff")
			hot = 1.5 * (1.0 - k)
	if enraged and state not in [Boss.S.LEAP_WIND, Boss.S.LEAP, Boss.S.LEAP_LAND, Boss.S.HOWL, Boss.S.SLAMS, Boss.S.PAW, Boss.S.RUSH]:
		col = col.lerp(RED, 0.6)
	if hot > 0.3:
		on["eye_l"] = 1.0
		on["eye_r"] = 1.0
	for k in ["horn2_l", "horn2_r", "spike"]:   # v0.12.0: the second pair and the nose spike burn with the horns
		on[k] = float(on.get("horn_l", 0.0))
	if state in [Boss.S.CHARGE, Boss.S.RUSH, Boss.S.GORE, Boss.S.GORE_WIND, Boss.S.LUNGE]:
		on["spike"] = 1.0
	# v0.12.0: the legs walk, trot and gallop on IK-planted hooves, and the whole body carries its weight (_locomote)
	var legs := _locomote(delta, gait, mv, speed, scrape, tuck, rear, jump)
	# idle life: snorts and head shakes now and then, pawing the ground
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
	_face_life(delta, p)
	model.position = Vector3(randf_range(-shake, shake), lift, 0)
	_smooth_pose(p, delta)
	var pose := _pose.duplicate()
	for k in _add:
		pose[k] = float(pose.get(k, 0.0)) + float(_add[k])
	model.apply(pose, legs, Time.get_ticks_msec() * 0.001, delta)
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
	_update_daze(delta)
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
	for k in ["pitch", "crouch", "head_dip", "head_up", "head_yaw", "jaw", "bend", "roll", "thrash", "lash", "tail_up", "flare", "bob",
			"arch", "twist", "brow", "lid", "tongue", "hump_roll", "surge"]:
		var want := float(p.get(k, 0.0 if k != "jaw" else 0.05))
		var cur := float(_pose.get(k, want))
		var rate := 30.0 if k in ["roll", "thrash", "bob"] else (16.0 if k in ["brow", "lid", "jaw"] else 11.0)
		_pose[k] = lerpf(cur, want, clampf(delta * rate, 0.0, 1.0))



# ================================================================ v0.12.0: locomotion and weight
## Gaits: [phase offsets FL, FR, BL, BR], duty factor (share of the cycle a hoof is down), stride (m) at the reference
## speed, the reference speed (m/s), hoof lift (m), carpus fold, hock fold. Walk: the 4-beat lateral sequence (LH, LF,
## RH, RF); trot: diagonal pairs; gallop: transverse (LH, RH, LF, RF) with a suspension phase after the forefeet push.
const GAITS := {
	"walk": [[0.25, 0.75, 0.0, 0.5], 0.66, 4.2, 6.0, 0.6, 1.2, 0.6],
	"trot": [[0.0, 0.5, 0.5, 0.0], 0.45, 5.4, 10.0, 0.75, 1.5, 0.6],
	"gallop": [[0.36, 0.48, 0.0, 0.11], 0.28, 9.5, 19.0, 1.25, 1.8, 1.1],
}
# leg poses relative to the leg's root (shoulder / hip joint), in the model's axes (before S); [offset, flex, curl]
const FRONT_TUCK := [Vector3(0, -1.25, -0.8), 1.9, 1.0]
const FRONT_REACH := [Vector3(0, -3.1, -1.25), 0.15, 0.2]
const HIND_PUSH := [Vector3(0, -3.55, 1.6), 0.05, 0.6]
const HIND_TUCK := [Vector3(0, -2.3, -0.6), 1.15, 0.8]
const HIND_KICK := [Vector3(0, -1.35, 3.35), 0.0, 0.3]
var _feet: Array = []          # per leg: w (planted, world), sw (swinging), s, dur, from, land, lift, ov (posed by an attack)
var _gname := "walk"
var _gw := {"walk": 0.0, "trot": 0.0, "gallop": 0.0}
var _yaw_prev := 0.0
var _omega := 0.0              # turning rate (rad/s)
var _fs_prev := 0.0
var _acc := 0.0                # forward acceleration (m/s2), smoothed
var _brace := 0.0
var _skid_t := 0.0
var _rear_s := 0.0
var _rear_peak := false
var _buck_t := 99.0
var _toss_t := 9.0             # the impale toss: someone skewered on the nose spike and flung off it
const BUCK_N := 3              # bucks in a row
const BUCK_T := 0.78           # seconds each
var _buck_sun := 0.0
var _sway := Vector2.ZERO      # momentum spring: x pitch, y roll
var _sway_v := Vector2.ZERO
var _add := {}                 # pose offsets from the gait and momentum, added after smoothing
var _dust_t := 0.0
var _breath_t := 2.0


func _foot_home_w(i: int, ground: float) -> Vector3:
	var h := model.to_global(BossModel.foot_home(BossModel.LEGS[i]))
	return Vector3(h.x, ground, h.z)


func _plus(k: String, v: float) -> void:
	_add[k] = float(_add.get(k, 0.0)) + v


## Where a foot starting a swing now should land: under its home `tau` seconds from now, the body having moved on at
## v and turned at _omega.
func _predict(home_w: Vector3, tau: float, v3: Vector3) -> Vector3:
	var rel := home_w - root.position
	rel.y = 0.0
	return Vector3(root.position.x, home_w.y, root.position.z) + Basis(Vector3.UP, _omega * tau) * rel + v3 * tau


func _start_swing(f: Dictionary, lift: float, dur: float) -> void:
	f.sw = true
	f.s = 0.0
	f.from = f.w
	f.land = f.w
	f.lift = lift
	f.dur = dur


## Every frame: picks the gait from his speed, steps each hoof (planted ones stay put in the world, lifted ones swing
## on a lift-and-slam arc to where they'll be needed), rears, jumps, bucks, braces and skids, and sways with momentum.
## Returns BossModel.apply's leg targets; fills _add (gait bob, roll, pitch rocking, lean, sway).
func _locomote(delta: float, gait: float, mv: Vector2, speed: float, scrape: int, tuck: float, rear: float, jump: float) -> Array:
	_add = {}
	var v3 := Vector3(mv.x, 0, mv.y)
	var ground := pos.y
	var yr := root.rotation.y
	var dt := maxf(delta, 1e-4)
	_omega = lerpf(_omega, wrapf(yr - _yaw_prev, -PI, PI) / dt, clampf(delta * 10.0, 0.0, 1.0))
	_yaw_prev = yr
	var fwd3 := Vector3(-sin(yr), 0, -cos(yr))
	var fs := v3.dot(fwd3)
	_acc = lerpf(_acc, (fs - _fs_prev) / dt, clampf(delta * 6.0, 0.0, 1.0))
	_fs_prev = fs
	if _acc < -16.0 and fs > 4.0:
		_skid_t = maxf(_skid_t, 0.45)
	_skid_t -= delta
	_brace = move_toward(_brace, 1.0 if _skid_t > 0.0 else 0.0, delta * (8.0 if _skid_t > 0.0 else 3.0))
	# momentum: a damped spring (overshoots a little): nose down braking, squatting back speeding up, leaning into turns
	var want := Vector2(clampf(_acc * 0.004, -0.12, 0.08), clampf(_omega * speed * 0.012, -0.22, 0.22))
	_sway_v += ((want - _sway) * 60.0 - _sway_v * 9.0) * delta
	_sway += _sway_v * delta
	_plus("pitch", _sway.x + 0.12 * _brace)
	_plus("roll", _sway.y)
	_plus("hump_roll", _sway.y * 0.6 - _sway_v.y * 0.05)   # the hump jiggles after the body
	_plus("lash", -_sway_v.y * 0.6 - _sway_v.x * 0.3)      # the tail swings on
	_plus("bend", clampf(_omega * 0.22, -0.3, 0.3))
	_plus("head_yaw", clampf(_omega * 0.15, -0.3, 0.3))
	_plus("crouch", 0.22 * _brace)
	_plus("head_up", 0.3 * _brace)
	# rearing on the haunches: the spine up ~40 degrees, the hind legs bent under him, the tail braced, the forelegs
	# striking the air; a heavy slam of both forefeet coming down
	_rear_s = lerpf(_rear_s, rear, clampf(delta * 12.0, 0.0, 1.0))
	var slam := false
	if _rear_s > 0.5:
		_rear_peak = true
	elif _rear_peak and _rear_s < 0.12:
		_rear_peak = false
		slam = true
	_plus("pitch", 0.7 * _rear_s)
	_plus("crouch", 0.55 * _rear_s)
	_plus("tail_up", -0.35 * _rear_s)
	_plus("head_up", 0.25 * _rear_s)
	# the jump: crouch on the haunches, the hind legs drive, forelegs tucked under the chest, reached out to land
	var jf := 0.0     # front leg pose weight
	var jh := 0.0
	var front_pose: Array = FRONT_TUCK
	var hind_pose: Array = HIND_TUCK
	if jump >= 0.0:
		if jump < 1.0:
			_plus("crouch", 1.0 * jump)
			_plus("pitch", 0.18 * jump)
			_plus("head_dip", 0.15 * jump)
		elif jump < 1.25:
			var k := (jump - 1.0) / 0.25
			_plus("pitch", 0.18 + 0.2 * k)
			_plus("crouch", 1.0 - k)
			hind_pose = HIND_PUSH
			jh = k
			jf = k
		elif jump < 2.6:
			var k := (jump - 1.25) / 1.35
			_plus("pitch", lerpf(0.38, -0.12, k))
			jf = 1.0
			jh = 1.0
			hind_pose = HIND_PUSH if k < 0.25 else HIND_TUCK
			_plus("tail_up", -0.4)
		elif jump < 3.0:
			var k := (jump - 2.6) / 0.4
			_plus("pitch", -0.12 - 0.12 * k)
			front_pose = FRONT_REACH
			jf = 1.0
			jh = 1.0 - 0.3 * k
		else:   # landing: forefeet first, knees giving, the hindquarters following down
			var k := clampf(jump - 3.0, 0.0, 1.0)
			_plus("pitch", -0.24 * (1.0 - k) * (1.0 - k))
			_plus("crouch", 0.9 * sin(k * PI) * (1.0 - k * 0.5))
			jh = maxf(0.0, 0.7 - k * 2.5)
	if tuck > 0.0:
		jf = maxf(jf, tuck)
		jh = maxf(jh, tuck)
	var airborne := jf > 0.5 or jh > 0.5
	# the buck: three in a row; each: head down, the rump and both hind legs flung high and straight back, a twist,
	# the tail whipping, a hard landing on the forelegs with dust
	var bk := 0.0
	if _buck_t < BUCK_N * BUCK_T:
		var prev := _buck_t
		_buck_t += delta
		var n := int(_buck_t / BUCK_T)
		var b := fmod(_buck_t, BUCK_T)
		var side := _buck_sun if n % 2 == 0 else -_buck_sun
		if b < 0.14:
			_plus("crouch", 0.35 * b / 0.14)
			_plus("head_dip", 0.6 * b / 0.14)
		elif b < 0.55:
			var k := sin((b - 0.14) / 0.41 * PI)
			bk = clampf(k * 1.6, 0.0, 1.0)
			_plus("bob", 1.1 * k)
			_plus("pitch", -0.5 * k)
			_plus("head_dip", 0.65)
			_plus("twist", 0.55 * side * k)
			_plus("roll", 0.18 * side * k)
			_plus("tail_up", 0.7 * k)
			_plus("lash", 1.2 * side * sin((b - 0.14) / 0.41 * TAU))
		else:
			var k := (b - 0.55) / (BUCK_T - 0.55)
			_plus("crouch", 0.4 * sin(k * PI))
			_plus("pitch", -0.12 * sin(k * PI))
			_plus("head_dip", 0.65 * (1.0 - k))
		if fmod(prev, BUCK_T) < 0.5 and b >= 0.5:   # the forefeet take the landing
			for i in 2:
				var f: Dictionary = _feet[i] if _feet.size() > i else {}
				if not f.is_empty():
					_hoof_fall(f.w, true)
			fx._shake_near_scaled(root.position, 0.2)
	if _toss_t < 0.55:   # skewered: a heave of the head up and to the side flings them off the spike
		_toss_t += delta
		var k := sin(clampf(_toss_t / 0.55, 0.0, 1.0) * PI)
		_plus("head_up", 1.0 * k)
		_plus("head_dip", -0.35 * k)
		_plus("thrash", 0.35 * k)
		_plus("pitch", 0.08 * k)
	# ---- the gait
	if _feet.is_empty():
		for i in 4:
			var h := _foot_home_w(i, ground)
			_feet.append({"w": h, "sw": false, "s": 0.0, "dur": 0.0, "from": h, "land": h, "lift": 0.0, "ov": false})
	var spd := maxf(speed, absf(_omega) * 3.2)
	var gal := state in [Boss.S.CHARGE, Boss.S.RUSH, Boss.S.HOME, Boss.S.LUNGE] and speed > 5.0
	if gal or spd > 13.0:
		_gname = "gallop"
	elif spd > 7.5 and not (_gname == "gallop" and spd > 11.0):
		_gname = "trot" if spd > 8.0 or _gname != "walk" else "walk"
	elif spd < 6.5:
		_gname = "walk"
	var g: Array = GAITS[_gname]
	var moving := spd > 0.45 and _brace < 0.3 and not airborne
	for k in _gw:
		_gw[k] = move_toward(float(_gw[k]), 1.0 if (moving and k == _gname) else 0.0, delta * 3.0)
	var duty := float(g[1])
	var stride := float(g[2]) * clampf(spd / float(g[3]), 0.45, 1.25)
	var freq := spd / maxf(stride, 0.5)
	if moving:
		phase += freq * delta
	var t_st := duty / maxf(freq, 0.1)
	var swinging := 0
	for f in _feet:
		if f.sw:
			swinging += 1
	var legs := []
	for i in 4:
		var leg: String = BossModel.LEGS[i]
		var f: Dictionary = _feet[i]
		var home_w := _foot_home_w(i, ground)
		if airborne or (f.w as Vector3).distance_to(home_w) > 9.0:   # in the air or snapped far: start from home
			f.w = home_w
			f.sw = false
		var u := fposmod(phase + float(g[0][i]), 1.0)
		var want_sw := moving and u >= duty
		if not f.sw and not f.ov and not airborne:
			if _brace > 0.3:   # skidding: the planted hooves slide with him, the forelegs braced out in front
				var to := home_w + fwd3 * (1.1 if i < 2 else -0.2)
				f.w = ((f.w as Vector3) + v3 * delta).lerp(to, clampf(delta * 5.0, 0.0, 1.0))
				_dust_t -= delta
				if i < 2 and _dust_t <= 0.0 and v3.length() > 1.5:
					_dust_t = 0.05
					MotionFx.puff(main, f.w, 2, 0.8)
			elif want_sw and (u - duty) / (1.0 - duty) < 0.6:
				_start_swing(f, float(g[4]), (1.0 - u) / maxf(freq, 0.1))
				swinging += 1
			elif (f.w as Vector3).distance_to(home_w) > (3.2 if moving else 0.45) and (moving or swinging == 0):
				_start_swing(f, float(g[4]) * 0.7 if moving else 0.35, 0.25 if moving else 0.42)
				swinging += 1
		var wp: Vector3 = f.w
		var flex := 0.0
		var curl := 0.0
		if f.sw:
			if want_sw:
				f.dur = (1.0 - u) / maxf(freq, 0.1)
			else:
				f.dur = maxf(float(f.dur) - delta, 0.0)
			f.s = minf(1.0, float(f.s) + (1.0 - float(f.s)) * delta / maxf(float(f.dur), delta))
			f.land = _predict(home_w, float(f.dur) + (t_st * 0.5 if moving else 0.0), v3 if moving else Vector3.ZERO)
			if moving and i < 2:   # the forelegs reach out ahead (most in the gallop)
				f.land = (f.land as Vector3) + fwd3 * (0.9 * float(_gw["gallop"]) + 0.25 * float(_gw["trot"]))
			var e := smoothstep(0.0, 1.0, float(f.s))
			wp = (f.from as Vector3).lerp(f.land, e)
			var arc := sin(PI * pow(float(f.s), 0.75))   # up early, a late hard drop: the slam
			wp.y = ground + float(f.lift) * arc
			var kf := float(f.lift) / float(g[4])
			flex = arc * float(g[5] if i < 2 else g[6]) * kf
			curl = arc * 0.9 * kf
			if float(f.s) >= 0.999:
				f.w = f.land
				f.sw = false
				var big := _gname == "gallop" or state in [Boss.S.CHARGE, Boss.S.RUSH]
				_hoof_fall(f.land, big)
				if _gname == "walk" and i < 2 and randf() < 0.25:
					model.breath(0.35)
		var tl := model.to_local(wp)
		tl.y += BossModel.HOOF_Y
		var spec := {"t": tl, "flex": flex, "curl": curl}
		# attacks and stunts pose legs on top of the gait
		var ov := false
		if i < 2 and jf > 0.0:
			spec.rel = front_pose[0]
			spec.k = jf
			spec.flex = lerpf(flex, float(front_pose[1]), jf)
			spec.curl = lerpf(curl, float(front_pose[2]), jf)
		if i >= 2 and jh > 0.0:
			spec.rel = hind_pose[0]
			spec.k = jh
			spec.flex = lerpf(flex, float(hind_pose[1]), jh)
			spec.curl = lerpf(curl, float(hind_pose[2]), jh)
		if i < 2 and _rear_s > 0.2 and jf <= 0.0:   # forelegs up and forward, knees bent, striking in turn
			var a := state_t * 8.5 + (0.0 if i == 0 else PI)
			var k := clampf((_rear_s - 0.2) / 0.3, 0.0, 1.0)
			spec.rel = Vector3(0, -1.6 + 0.45 * sin(a), -1.25 - 0.5 * cos(a))
			spec.k = k
			spec.flex = lerpf(flex, 1.55 + 0.3 * sin(a + 0.6), k)
			spec.curl = lerpf(curl, 0.8, k)
			ov = k > 0.5
		if i >= 2 and bk > 0.0:
			spec.rel = HIND_KICK[0]
			spec.k = bk
			spec.flex = lerpf(flex, float(HIND_KICK[1]), bk)
			spec.curl = lerpf(curl, float(HIND_KICK[2]), bk)
			ov = bk > 0.5
		if i == scrape:   # pawing: drag the hoof back through the dirt, lift it forward, again
			var home := BossModel.foot_home(leg)
			var c := fposmod(state_t / 0.6, 1.0)
			var tt := home
			if c < 0.55:
				tt.z = home.z - 1.0 + 1.7 * (c / 0.55)
				spec.flex = 0.2
			else:
				var sc := (c - 0.55) / 0.45
				tt.z = home.z + 0.7 - 1.7 * sc
				tt.y = home.y + 0.8 * sin(PI * sc)
				spec.flex = 1.3 * sin(PI * sc)
				spec.curl = 0.8 * sin(PI * sc)
			spec.t = tt
			ov = true
			if c < 0.1:
				_step_t -= delta
				if _step_t <= 0.0:
					_step_t = 0.5
					var hp3 := model.to_global(tt)
					MotionFx.puff(main, Vector3(hp3.x, ground, hp3.z), 3, 1.0)
					_sound("scrape", hp3, -4.0)
		if state == Boss.S.STAGGER:
			spec.t = (spec.t as Vector3) + Vector3(sin(state_t * 11.0 + i * 1.7) * 0.25, 0, cos(state_t * 9.0 + i) * 0.3)
		if f.ov and not ov:   # back on the ground where the hoof came down
			var hw := (model.anchors["hoof_" + leg] as Node3D).global_position
			f.w = Vector3(hw.x, ground, hw.z)
			f.sw = false
			if i < 2 and slam:
				_hoof_fall(f.w, true)
				fx._shake_near_scaled(f.w, 0.25)
				_sound("hoof", f.w, 2.0)
			elif i >= 2 and _buck_t < BUCK_N * BUCK_T:
				_hoof_fall(f.w, true)
		f.ov = ov
		legs.append(spec)
	# the body over the legs: head bob and hump roll walking, a bounce trotting, the gallop's rocking and spine flex
	var ph := TAU * phase
	var ww := float(_gw["walk"])
	var wt := float(_gw["trot"])
	var wg := float(_gw["gallop"])
	_plus("head_dip", ww * 0.07 * cos(2.0 * ph - TAU * 0.5) + wt * 0.03 * sin(2.0 * ph) + wg * 0.13 * sin(ph + 0.4))
	_plus("bob", ww * -0.05 * cos(2.0 * ph - TAU * 0.6) + wt * -0.09 * cos(2.0 * ph) + wg * 0.45 * cos(ph - TAU * 0.9))
	_plus("hump_roll", ww * 0.045 * sin(ph) + wt * 0.02 * sin(ph))
	_plus("twist", ww * 0.05 * sin(ph))
	_plus("pitch", wg * 0.09 * sin(ph - 0.3))
	_plus("arch", wg * 0.1 * cos(ph))
	_plus("surge", wg * 0.12 * sin(ph))
	return legs


## The eyes on his target, the head turning to follow it, breath steaming from his nostrils.
func _face_life(delta: float, p: Dictionary) -> void:
	var tid := int(extra[4]) if extra.size() > 4 else 0
	var tgt = null
	if fx != null and fx.avatars.has(tid):
		tgt = (fx.avatars[tid] as Node3D).global_position + Vector3(0, 1.4, 0)
	model.look_target = tgt
	if tgt != null and state in [Boss.S.IDLE, Boss.S.WALK, Boss.S.STRAFE, Boss.S.BACKOFF, Boss.S.TURN, Boss.S.CHARGE_WIND,
			Boss.S.PAW, Boss.S.RECOVER, Boss.S.BALLS, Boss.S.LUNGE, Boss.S.STOMP_WIND, Boss.S.BEAM_WIND]:
		var d: Vector3 = (tgt as Vector3) - root.position
		var rel := wrapf(atan2(-d.x, -d.z) - root.rotation.y, -PI, PI)
		p.head_yaw = float(p.get("head_yaw", 0.0)) + clampf(rel, -0.75, 0.75) * 0.8
	_breath_t -= delta
	if _breath_t <= 0.0:
		var hard := state in [Boss.S.CHARGE, Boss.S.RUSH, Boss.S.CHARGE_WIND, Boss.S.PAW, Boss.S.RECOVER, Boss.S.HOME]
		_breath_t = 0.4 if hard else randf_range(2.0, 3.0)
		model.breath(0.9 if hard else 0.45)
	if float(p.get("jaw", 0.0)) > 0.55 and randf() < delta * 7.0:   # roaring: steam from the open mouth
		model.breath(1.0, true)

func _arc(a: Vector3, b: Vector3, c: Color, life: float) -> void:
	var arc := fx._ribbons([[MagicFx._fractal(a, b, 3, 0.3), 0.04]], c, 6.0)
	var tw := arc.create_tween()
	tw.tween_property(arc.material_override, "albedo_color:a", 0.0, life)
	tw.tween_callback(arc.queue_free)


func _hoof_fall(at: Vector3, big: bool) -> void:
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
	model.breath(1.0)


func _update_beam(col: Color) -> void:
	beam.visible = state == Boss.S.BEAM
	if not beam.visible:
		return
	var o: Vector3 = (model.points["brow"] as Node3D).global_position
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
var _leap_pillar: MeshInstance3D


## This leap's ticks in the air (v0.12.0: longer for a longer bound; sent as extra[7]).
func _leap_air_t() -> int:
	return int(extra[7]) if extra.size() > 7 else Boss.LEAP_AIR


func _update_marker() -> void:
	var leaping := state in [Boss.S.LEAP_WIND, Boss.S.LEAP]
	marker.visible = leaping
	if _leap_shadow != null:
		_leap_shadow.visible = state == Boss.S.LEAP
	if _leap_pillar != null:
		_leap_pillar.visible = leaping
	_leap_arrow(leaping)
	if not leaping:
		return
	# v0.12.0: a tall gold light pillar over the landing spot, visible from anywhere on the map
	if _leap_pillar == null:
		_leap_pillar = MeshInstance3D.new()
		var pc := CylinderMesh.new()
		pc.top_radius = 1.2
		pc.bottom_radius = 2.2
		pc.height = 120.0
		pc.radial_segments = 16
		pc.cap_top = false
		pc.cap_bottom = false
		_leap_pillar.mesh = pc
		var pm := MagicFx._glow_mat(GOLD, 3.0, 0.28)
		pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		pm.cull_mode = BaseMaterial3D.CULL_DISABLED
		_leap_pillar.material_override = pm
		_leap_pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		main.add_child(_leap_pillar)
	_leap_pillar.global_position = Vector3(float(extra[0]), 60.0, float(extra[1]))
	(_leap_pillar.material_override as StandardMaterial3D).albedo_color.a = 0.2 + 0.12 * absf(sin(Time.get_ticks_msec() * 0.006))
	var land := Vector3(float(extra[0]), 0.06, float(extra[1]))
	marker.global_position = land
	var total := (90 + _leap_air_t()) * Config.DT
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
		var u := clampf(state_t / (_leap_air_t() * Config.DT), 0.0, 1.0)
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


## v0.12.0: an arrow at the edge of the screen pointing to where he will land (or to him, while he is far away and
## off screen), with the distance.
var _arrow: Label


func _leap_arrow(leaping: bool) -> void:
	var cam := get_viewport().get_camera_3d()
	var to := Vector3.ZERO
	var show := false
	if root != null and cam != null:
		to = Vector3(float(extra[0]), 2.0, float(extra[1])) if leaping else root.position + Vector3(0, 3.0, 0)
		show = leaping or cam.global_position.distance_to(to) > 45.0
		if show and not cam.is_position_behind(to):
			var sp := cam.unproject_position(to)
			var vr := get_viewport().get_visible_rect().size
			show = sp.x < 0 or sp.y < 0 or sp.x > vr.x or sp.y > vr.y
	if _arrow == null:
		if not show:
			return
		_arrow = Label.new()
		_arrow.add_theme_font_size_override("font_size", 30)
		_arrow.add_theme_color_override("font_outline_color", Color.BLACK)
		_arrow.add_theme_constant_override("outline_size", 8)
		var layer := CanvasLayer.new()
		layer.layer = 5
		add_child(layer)
		layer.add_child(_arrow)
	_arrow.visible = show
	if not show:
		return
	var vr := get_viewport().get_visible_rect().size
	var c := vr / 2.0
	var cb := cam.global_transform.basis
	var rel := to - cam.global_position
	var dir := Vector2(rel.dot(cb.x), -rel.dot(cb.y) * 0.3 - absf(rel.dot(cb.z)) * 0.0)
	if rel.dot(-cb.z) < 0.0 and absf(dir.x) < 1.0:
		dir.x = 1.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	var edge := Vector2(clampf(c.x + dir.x * (c.x - 90.0), 60.0, vr.x - 160.0), clampf(c.y + dir.y * (c.y - 60.0), 60.0, vr.y - 60.0))
	_arrow.text = (">> %d m" if dir.x >= 0 else "<< %d m") % int(Vector2(rel.x, rel.z).length())
	_arrow.add_theme_color_override("font_color", GOLD if leaping else Color("ff8a6b"))
	_arrow.position = edge


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


## Rings: a glowing band on the ground; v0.12.0 the map-wide waves (kind 1 the landing ring, gold; kind 2 the slam
## waves, white-blue) also get a bright glowing wall ~1.4 m high that stays readable hundreds of metres away, a
## constant thickness however big they grow, a ripple of dust just ahead, and a rising rumble as one nears you.
var _ring_heard := {}


func _draw_rings() -> void:
	while ring_nodes.size() < rings.size():
		var holder := Node3D.new()
		var mi := MeshInstance3D.new()
		mi.name = "band"
		var tm := TorusMesh.new()
		tm.rings = 64
		tm.ring_segments = 4
		mi.mesh = tm
		var m := MagicFx._glow_mat(Color("bfd8ff"), 3.0, 0.75)
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
		var wall := MeshInstance3D.new()
		wall.name = "wall"
		var cm := CylinderMesh.new()
		cm.cap_top = false
		cm.cap_bottom = false
		cm.height = 1.4
		cm.radial_segments = 192
		cm.rings = 1
		wall.mesh = cm
		var wm := MagicFx._glow_mat(Color("bfd8ff"), 3.0, 0.5)
		wm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		wm.cull_mode = BaseMaterial3D.CULL_DISABLED
		wall.material_override = wm
		wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(wall)
		main.add_child(holder)
		ring_nodes.append(holder)
	var me := Vector3.INF
	if fx.avatars.has(net.my_id):
		me = (fx.avatars[net.my_id] as Node3D).position
	for i in ring_nodes.size():
		var holder: Node3D = ring_nodes[i]
		holder.visible = i < rings.size()
		if not holder.visible:
			continue
		var rr = rings[i]
		var r := float(rr[0]) if rr is Array else float(rr)
		var c := Vector3(float(rr[1]), 0, float(rr[2])) if rr is Array else root.position
		var kind: int = int(rr[3]) if rr is Array else 0
		var wide := kind >= 1
		var mi: MeshInstance3D = holder.get_node("band")
		var wall: MeshInstance3D = holder.get_node("wall")
		var tm: TorusMesh = mi.mesh
		var th := 0.35 if r < 30.0 else 0.6   # a constant band width, a little wider far out
		tm.inner_radius = maxf(r - th, 0.05)
		tm.outer_radius = r + th
		tm.rings = 64 if r < 30.0 else 256
		holder.global_position = Vector3(c.x, 0.2, c.z)
		mi.scale = Vector3(1, 0.9 if wide else 0.6, 1)
		var cc := GOLD if kind == 1 else Color("bfd8ff")
		var m: StandardMaterial3D = mi.material_override
		m.albedo_color = Color(cc.r, cc.g, cc.b, 0.9 if wide else 0.9 * clampf(1.0 - r / 24.0, 0.0, 1.0))
		m.emission = cc
		wall.visible = wide
		if wide:
			var cm: CylinderMesh = wall.mesh
			cm.top_radius = r
			cm.bottom_radius = r
			wall.position = Vector3(0, 0.5, 0)
			var wm: StandardMaterial3D = wall.material_override
			wm.albedo_color = Color(cc.r, cc.g, cc.b, 0.35 + 0.15 * sin(Time.get_ticks_msec() * 0.02))
			wm.emission = cc
		# dust and sparks thrown up along it: near our player when it's a map-wide wave, anywhere on a small one
		if randf() < 0.5:
			var a := randf() * TAU
			if wide and me != Vector3.INF:
				a = atan2(me.z - c.z, me.x - c.x) + randf_range(-0.25, 0.25)
			var at := Vector3(c.x + cos(a) * r, 0.1, c.z + sin(a) * r)
			Fx.burst(main, at, Vector3.UP, cc, 3, 3.0, 0.04)
			if randf() < 0.3:
				MotionFx.puff(main, at, 1, 0.4)
		if wide and me != Vector3.INF:
			var gap := Vector2(me.x - c.x, me.z - c.z).length() - r
			if gap > 0.0 and gap < 12.0 and randf() < 0.3:   # a ripple running ahead of it
				var a2 := atan2(me.z - c.z, me.x - c.x) + randf_range(-0.15, 0.15)
				MotionFx.puff(main, Vector3(c.x + cos(a2) * (r + 3.0), 0.05, c.z + sin(a2) * (r + 3.0)), 1, 0.3)
			var key := "%d:%d:%d" % [int(c.x * 10), int(c.z * 10), kind]
			if gap > 0.0 and gap < 30.0 and not _ring_heard.has(key):
				_ring_heard[key] = true
				_sound("whoosh", me, -8.0)
				_sound("slam", me, -6.0, gap / Boss.WAVE_V)
				_sound("whoosh", me, 2.0, maxf(gap / Boss.WAVE_V - 0.5, 0.0))
	if rings.is_empty():
		_ring_heard.clear()


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
			if alive and model != null:   # v0.12.0: impaled on the nose spike, then tossed off it
				_toss_t = 0.0
				var tip := (model.anchors["spike"] as Node3D).global_position
				Fx.burst(main, tip, Vector3.UP, Color.WHITE, 16, 6.0, 0.05)
				fx._flash_light(tip, Color("cfe4ff"), 4.0, 6.0, 0.2)
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
			_skid_t = 0.6
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
			# v0.12.0: snorting at apples underfoot while he ambles: a buck (sometimes a sunfishing twist)
			if state in [Boss.S.IDLE, Boss.S.WALK, Boss.S.TURN] or (state == Boss.S.STRAFE and state_t > 0.3):
				_buck_t = 0.0
				_buck_sun = (1.0 if randf() < 0.5 else -1.0) * (1.0 if randf() < 0.5 else 0.45)
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
		"boss_stun_hit":   # v0.12.0 a Stun caught him: a notch on the meter
			flinch = maxf(flinch, 0.35)
			Fx.burst(main, (a[0] as Vector3) + Vector3(0, 5, 0), Vector3.UP, Color("ffe46b"), 10, 3.0, 0.04)
			if int(a[1]) >= Boss.STUN_NEED - 2 and int(a[1]) < Boss.STUN_NEED and main.has_method("toast"):
				main.toast("Thunderhorn is reeling: %d more Stun%s!" % [Boss.STUN_NEED - int(a[1]), "" if Boss.STUN_NEED - int(a[1]) == 1 else "s"])
		"boss_dazed":   # the meter filled: he goes down
			_banner("THUNDERHORN IS DAZED!", GOLD, 2.4)
			_flash = 1.0
			fx._flash_light((a[0] as Vector3) + Vector3(0, 4, 0), GOLD, 8.0, 18.0, 0.5)
			Fx.burst(main, (a[0] as Vector3) + Vector3(0, 5, 0), Vector3.UP, GOLD, 30, 6.0, 0.06)
			_sound("roar2", a[0], 2.0)
			_sound("slam", a[0], 4.0, 0.6)
			get_tree().create_timer(0.7).timeout.connect(func():
				if alive:
					MotionFx.land(main, a[0], 3.5)
					fx._shake_near_scaled(a[0], 0.6))
		"boss_get_up":
			_snort()
			_sound("roar0", a[0], 0.0)
			MotionFx.land(main, a[0], 2.0)
		"boss_death":   # he bellows, comes apart into cloud and lightning
			_sound("roar3", a[0], 6.0)
			for i in 6:
				get_tree().create_timer(0.3 * i).timeout.connect(func():
					fx._bolt(a[0] + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))))
			fx._shake_near_scaled(a[0], 0.7)
		"boss_leave":
			fx._smoke(a[0], 12, 3.0, 4.0, 0.6)
			fx._bolt(a[0])


## v0.12.0 dazed: a ring of stars and sparks circling his head, little arcs crackling over him.
func _update_daze(delta: float) -> void:
	var on := state == Boss.S.DAZED and state_t < Boss.STUN_TICKS * Config.DT - 0.5
	if on and _stars == null:
		_stars = Node3D.new()
		main.add_child(_stars)
		for i in 6:
			var st := MeshInstance3D.new()
			var sm := PrismMesh.new()
			sm.size = Vector3(0.5, 0.5, 0.14)
			st.mesh = sm
			st.material_override = MagicFx._glow_mat(Color("ffe46b") if i % 2 == 0 else Color("fff6d0"), 5.0)
			var a := TAU * i / 6.0
			st.position = Vector3(cos(a) * 1.6, sin(a * 2.0) * 0.15, sin(a) * 1.6)
			_stars.add_child(st)
	if _stars == null:
		return
	if not on:
		_stars.queue_free()
		_stars = null
		return
	var head: Node3D = model.anchors["eye_l"]
	var h2: Node3D = model.anchors["eye_r"]
	_stars.global_position = (head.global_position + h2.global_position) * 0.5 + Vector3(0, 1.3, 0)
	_stars.rotation.y += delta * 3.2
	for c in _stars.get_children():
		(c as Node3D).rotation.y = -_stars.rotation.y + state_t * 4.0
	if randf() < delta * 10.0:
		var c0 := root.position + Vector3(randf_range(-2.5, 2.5), randf_range(1.0, 4.0), randf_range(-3, 3))
		_arc(c0, c0 + Vector3(randf_range(-1.2, 1.2), randf_range(-0.8, 0.8), randf_range(-1.2, 1.2)), GOLD, 0.1)
	if randf() < delta * 4.0:
		Fx.burst(main, _stars.global_position, Vector3.UP, GOLD, 4, 2.0, 0.03)


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
	box.offset_bottom = 96
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
	# v0.12.0 the stun meter: a thin gold bar under the health bar, a notch per hit (10 = dazed 7 s)
	stun_bg = ColorRect.new()
	stun_bg.color = Color(0, 0, 0, 0.55)
	stun_bg.anchor_left = 0.42
	stun_bg.anchor_right = 0.72
	stun_bg.offset_top = 55
	stun_bg.offset_bottom = 65
	box.add_child(stun_bg)
	stun_fill = ColorRect.new()
	stun_fill.color = Color("ffd84a")
	stun_fill.anchor_bottom = 1.0
	stun_fill.offset_left = 1
	stun_fill.offset_top = 1
	stun_fill.offset_bottom = -1
	stun_bg.add_child(stun_fill)
	for i in range(1, Boss.STUN_NEED):
		var notch := ColorRect.new()
		notch.color = Color(0, 0, 0, 0.7)
		notch.anchor_left = float(i) / Boss.STUN_NEED
		notch.anchor_right = float(i) / Boss.STUN_NEED
		notch.anchor_bottom = 1.0
		notch.offset_right = 1
		stun_bg.add_child(notch)
	stun_label = Label.new()
	stun_label.anchor_left = 0.725
	stun_label.anchor_right = 0.97
	stun_label.offset_top = 50
	stun_label.add_theme_font_size_override("font_size", 14)
	stun_label.add_theme_constant_override("outline_size", 5)
	stun_label.add_theme_color_override("font_outline_color", Color.BLACK)
	stun_label.add_theme_color_override("font_color", Color("ffe48a"))
	box.add_child(stun_label)
	bar_status = Label.new()
	bar_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar_status.anchor_left = 0.42
	bar_status.anchor_right = 0.97
	bar_status.offset_top = 68
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
	if flags & 64:
		st.append("[DAZED]")
	# v0.12.0 the stun meter: fills a notch per Stun hit; full and flashing while he's dazed
	var sm := float(extra[8]) if extra.size() > 8 else 0.0
	var dazed := flags & 64 != 0
	stun_fill.anchor_right = clampf(sm / Boss.STUN_NEED, 0.0, 1.0)
	stun_fill.offset_right = -1
	var fl := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.015)
	stun_fill.color = Color("fff4b0").lerp(Color("ffb020"), fl) if dazed else Color("ffd84a")
	if dazed:
		stun_label.text = "DAZED %.0f s" % maxf(Boss.STUN_TICKS * Config.DT - state_t, 0.0)
	else:
		stun_label.text = "STUN %d/%d" % [int(sm + 0.001), Boss.STUN_NEED] if sm > 0.0 else "STUN"
	stun_bg.modulate.a = 1.0 if (sm > 0.0 or dazed) else 0.45
	if state in Boss.SEQ:
		st.append("[STORM LEAP]")
	bar_status.text = "   ".join(st)
