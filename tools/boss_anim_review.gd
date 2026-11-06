## Thunderhorn's animation review (v0.12.0): the boss alone on open ground playing every motion in turn, slowed down
## (Engine.time_scale 0.25) under a slowly orbiting three-quarter camera, with the motion's name on screen. It drives a
## real BossView with made-up server states, so what you see is exactly the game's animation. Watch it live:
##   Godot.exe --path . -s tools/boss_anim_review.gd
## or record it (Godot's movie maker), then cut it with ffmpeg using the segments file it writes:
##   Godot.exe --path . --resolution 1280x720 --write-movie review.avi --fixed-fps 30 -s tools/boss_anim_review.gd -- <out dir>
## Writes <out dir>/segments.txt: "name first_frame last_frame" per motion (frames of the movie). Options after --:
## <out dir> [speed] (time scale, default 0.25).
extends SceneTree

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
