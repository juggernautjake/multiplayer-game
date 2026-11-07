## Thunderhorn's animation review (v0.12.0): the boss alone on open ground playing every motion in turn, slowed down
## (Engine.time_scale 0.25) under a slowly orbiting three-quarter camera, with the motion's name on screen. It drives a
## real BossView with made-up server states, so what you see is exactly the game's animation. Watch it live:
##   Godot.exe --path . -s tools/boss_anim_review.gd
## or record it (Godot's movie maker), then cut it with ffmpeg using the segments file it writes:
##   Godot.exe --path . --resolution 1280x720 --write-movie review.avi --fixed-fps 30 -s tools/boss_anim_review.gd -- <out dir>
## Writes <out dir>/segments.txt: "name first_frame last_frame" per motion (frames of the movie). Options after --:
## <out dir> [speed] (time scale, default 0.25).
## v0.12.9 SIM mode: `-- <out dir> 1.0 sim <scenario> [label]` drives the same BossView from a REAL Boss (the server's
## brain, ticking at 60 a second against a scripted player; his packed state every other tick and his events, as a
## client gets them), to review whole attacks with their real timing: what comes next, what cuts in. Scenarios:
##   charge_out  a charge started outside the arena (where he is after a far leap or the Duel Stone cutscene)
##   beam_meteor the horn beam, hit by a meteor (60) part-way through the sweep
##   stomp_cut   a stomp, his health dropping under 60% (the Duel Stone cutscene) mid-slams
##   charge_rage an enraged charge in the arena, and what follows it
## Each runs SIM_SECS; the label (e.g. BEFORE / AFTER) is shown on screen.
extends SceneTree

const SIM_SECS := {"charge_out": 7.0, "beam_meteor": 6.0, "stomp_cut": 8.0, "charge_rage": 7.0}
var sim := ""
var sim_label := ""
var sb: Boss
var sim_k := 0
var sim_acc := 0.0
var sim_p := Vector3.ZERO
var sim_log := []

# [game seconds, state, speed m/s, turn rad/s, label, event at the start]
const PLAN := [
	[3.0, "IDLE", 0.0, 0.0, "idle / breathing", ""],
	[3.0, "WALK", 4.5, 0.0, "walk (4-beat: LH LF RH RF)", ""],
	[2.4, "WALK", 9.5, 0.0, "trot (diagonal pairs)", ""],
	[2.6, "CHARGE", 19.0, 0.0, "gallop (transverse, suspension)", ""],
	[1.3, "IDLE", 0.0, 0.0, "skid stop", "boss_skid"],
	[1.8, "TURN", 0.0, 2.0, "turn on the spot", ""],
	[2.4, "WALK", 5.0, 0.8, "walking turn (leaning in)", ""],
	[2.0, "PAW", 0.0, 0.0, "paw", ""],
	[0.7, "STOMP_WIND", 0.0, 0.0, "stomp", ""],
	[1.3, "STOMP", 0.0, 0.0, "stomp", ""],
	[2.7, "IDLE", 0.0, 0.0, "buck", "boss_snort"],
	[1.4, "LEAP_WIND", 0.0, 0.0, "jump (Storm Leap)", ""],
	[1.2, "LEAP", 0.0, 0.0, "jump (Storm Leap)", ""],
	[0.9, "LEAP_LAND", 0.0, 0.0, "jump (Storm Leap)", ""],
	[2.8, "HOWL", 0.0, 0.0, "rear (howl / orb launch)", ""],
	[0.9, "CHARGE_WIND", 0.0, 0.0, "charge wind-up + charge", ""],
	[1.6, "CHARGE", 19.0, 0.0, "charge wind-up + charge", ""],
	[0.6, "IDLE", 0.0, 0.0, "charge wind-up + charge", "boss_skid"],
	[0.45, "GORE_WIND", 0.0, 0.0, "gore", ""],
	[0.6, "GORE", 0.0, 0.0, "gore", ""],
	[0.45, "TAIL_WIND", 0.0, 0.0, "tail lash", ""],
	[0.7, "TAIL", 0.0, 0.0, "tail lash", ""],
	[0.8, "BEAM_WIND", 0.0, 0.0, "horn beam", ""],
	[1.5, "BEAM", 0.0, 0.0, "horn beam", ""],
	[1.0, "STAGGER", 0.0, 0.0, "stagger", ""],
	[1.4, "ROAR", 0.0, 0.0, "roar (face)", ""],
	[1.2, "PHASE", 0.0, 0.0, "enrage (rear + roar)", ""],
	[1.0, "IDLE", 0.0, 0.0, "idle", ""],
]

var out := ""
var cam: Camera3D
var world: Node3D
var view: BossView
var target: Node3D
var label: Label
var _gt := 0.0
var _st := 0.0
var _pos := Vector3.ZERO
var _yaw := 0.0
var _last := -1
var _frame := 0
var _segs: Array = []   # [name, first, last]


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0] if a.size() > 0 else ""
	Engine.time_scale = float(a[1]) if a.size() > 1 else 0.25
	if a.size() > 3 and a[2] == "sim":
		sim = a[3]
		sim_label = a[4] if a.size() > 4 else ""
	if out != "":
		DirAccess.make_dir_recursive_absolute(out)
	world = Node3D.new()
	get_root().add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("aab8c4")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.52, 0.58)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("6f8f74")
	ground.material_override = gm
	world.add_child(ground)
	for i in 60:   # marker posts so movement and sliding feet read
		for sx in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.3, 0.8, 0.3)
			post.mesh = bm
			post.position = Vector3(9.0 * sx, 0.4, 30.0 - i * 6.0)
			world.add_child(post)
	cam = Camera3D.new()
	cam.fov = 45.0
	world.add_child(cam)
	cam.make_current()
	target = Node3D.new()
	world.add_child(target)
	var net := Net.new()
	var fx := MagicFx.new()
	fx.net = net
	fx.main = world
	world.add_child(fx)
	fx.avatars[1] = target
	view = BossView.new()
	world.add_child(view)
	view.setup(net, world, fx)
	var hud := CanvasLayer.new()
	world.add_child(hud)
	label = Label.new()
	label.position = Vector2(24, 18)
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_constant_override("outline_size", 10)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_child(label)
	if sim != "":
		_sim_setup()
		process_frame.connect(_sim_frame)
	else:
		process_frame.connect(_tick)


func _tick() -> void:
	var dt := get_root().get_process_delta_time()
	_gt += dt
	var tot := 0.0
	var idx := -1
	var into := 0.0
	for i in PLAN.size():
		if _gt < tot + float(PLAN[i][0]):
			idx = i
			into = _gt - tot
			break
		tot += float(PLAN[i][0])
	if idx < 0:
		if not _segs.is_empty():
			_segs[-1][2] = _frame
		_write_segments()
		quit()
		return
	var cur: Array = PLAN[idx]
	var st: int = Boss.S[cur[1]]
	_yaw += float(cur[3]) * dt
	var fwd := Vector3(-sin(_yaw), 0, -cos(_yaw))
	_pos += fwd * float(cur[2]) * dt
	var fresh := idx != _last
	if fresh:
		_last = idx
		_st = 0.0
		if _segs.is_empty() or _segs[-1][0] != cur[4]:
			if not _segs.is_empty():
				_segs[-1][2] = _frame - 1
			_segs.append([cur[4], _frame, _frame])
	else:
		_st += dt
	var y := 0.0
	if cur[1] == "LEAP":
		var u := into / float(cur[0])
		y = 4.0 * 6.0 * u * (1.0 - u)
	var air := int(float(PLAN[idx][0]) / Config.DT) if cur[1] == "LEAP" else 72
	target.position = _pos + fwd * 14.0 + Vector3(5, 0, 0)
	var extra := [_pos.x, _pos.z, 0, 1 if cur[1] == "PHASE" else 0, 1, 0, 0, air]
	var flags := 8 if cur[1] == "PHASE" else 0
	view._on_state(0, [st, int(_st / Config.DT), _pos.x, y, _pos.z, _yaw, 7000, 7000, flags, _yaw + sin(_st * 2.0) * 0.8,
		[], [], PackedVector3Array(), extra])
	view.hud.visible = false
	if fresh and cur[5] != "":
		view._on_fx(cur[5], [_pos, _yaw])
	label.text = cur[4]
	var at := (view.root.position if view.root else _pos) + Vector3(0, 3.0, 0)
	at.y = 3.0 + y * 0.6
	var ang := _yaw + PI * 0.5 + 0.45 * sin(_gt * 0.35) + 0.25
	cam.look_at_from_position(at + Vector3(-sin(ang), 0.0, -cos(ang)) * 17.0 + Vector3(0, 1.6, 0), at)
	_frame += 1


func _write_segments() -> void:
	if out == "":
		return
	var f := FileAccess.open(out.path_join("segments.txt"), FileAccess.WRITE)
	for s in _segs:
		f.store_line("%s|%d|%d" % [s[0], s[1], s[2]])
	f.close()


# ================================================================ v0.12.9 SIM mode (header)
func _sim_setup() -> void:
	var c := Boss.arena_c()
	match sim:
		"charge_out":   # next to the Duel Stone, as after the cutscene: 40 m outside the arena
			sb = Boss.new(Vector3(WorldLayout.DUEL_C.x - 4.0, 0, WorldLayout.DUEL_C.y + 6.0), 1, 77)
			sim_p = sb.pos + Vector3(-3, 0, 18)
		"beam_meteor", "stomp_cut", "charge_rage":
			sb = Boss.new(c, 1, 78)
			sim_p = c + Vector3(-2, 0, -12 if sim == "beam_meteor" else (-6 if sim == "stomp_cut" else -16))
	sb.state = Boss.S.IDLE
	sb.yaw = atan2(-(sim_p - sb.pos).x, -(sim_p - sb.pos).z)
	sb.fx.clear()
	if sim == "charge_rage":
		sb.enraged = true
		sb.phase = 1
		sb.want_phase = 1
		sb.hp = int(sb.max_hp * 0.45)
	if sim == "stomp_cut":
		sb.cut_on = true
		sb.hp = int(sb.max_hp * 0.62)
	sb.leaps = Boss.LEAP_MAX   # (no Storm Leap here)
	match sim:
		"charge_out", "charge_rage": sb._attack("charge", sim_p)
		"beam_meteor": sb._attack("beam", sim_p)
		"stomp_cut": sb._attack("stomp", sim_p)
	target.position = sim_p


func _sim_frame() -> void:
	var dt := get_root().get_process_delta_time()
	_gt += dt
	if _gt > float(SIM_SECS.get(sim, 6.0)):
		_write_sim_log()
		quit()
		return
	sim_acc += dt
	while sim_acc >= Config.DT:
		sim_acc -= Config.DT
		_sim_tick()
	var names: String = Boss.S.keys()[sb.state]
	label.text = "%s  %s
%s  (t %d)" % [sim_label, sim.replace("_", " "), names, sb.t]
	var mid := (view.root.position if view.root else sb.pos).lerp(sim_p, 0.35) + Vector3(0, 2.5, 0)
	var ang := 0.9 + 0.12 * sin(_gt * 0.3)
	cam.look_at_from_position(mid + Vector3(sin(ang), 0, cos(ang)) * 30.0 + Vector3(0, 11.0, 0), mid)
	_frame += 1


func _sim_tick() -> void:
	sim_k += 1
	# the player: side-steps slowly, out of the way of a charge
	sim_p += Vector3(1.2, 0, 0) * Config.DT
	target.position = sim_p
	var st0 := sb.state
	sb.tick(sim_k, [[1, sim_p, true, false, 100, 0, false, false]], [])
	if sim == "beam_meteor" and sim_k == 100:
		sb.hurt(40, 1, "Meteor")
		sb.fx.append(["boss_stun_hit", [sb.pos, 0]])   # (a burst on him so the hit shows)
	if sim == "stomp_cut" and sim_k == 90:
		sb.hurt(int(sb.max_hp * 0.04), 1, "")
	if sb.state != st0:
		sim_log.append("%d %s -> %s" % [sim_k, Boss.S.keys()[st0], Boss.S.keys()[sb.state]])
	for e in sb.fx:
		view._on_fx(str(e[0]), e[1])
	sb.fx.clear(); sb.hits.clear(); sb.zaps.clear(); sb.launches.clear(); sb.strikes.clear(); sb.slows.clear()
	sb.felled.clear(); sb.splats.clear()
	if sim_k % 2 == 0:
		view._on_state(sim_k, sb.pack())
		view.hud.visible = false


func _write_sim_log() -> void:
	print("[sim %s %s] %s" % [sim, sim_label, ", ".join(sim_log)])
	if out == "":
		return
	var f := FileAccess.open(out.path_join("sim_%s.txt" % sim), FileAccess.WRITE)
	for l in sim_log:
		f.store_line(l)
	f.close()
