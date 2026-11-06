## Thunderhorn close-ups for working on his body and animation (v0.12.0). Run windowed:
##   Godot.exe --path . --resolution 960x540 -s tools/boss_pose_shots.gd -- <out dir> [model|gait]
## model: BossModel alone, standing / roaring / charging poses from four sides (bull_<pose>_<view>.png).
## gait:  a real BossView fed made-up server states: walk, trot, gallop, a turn, a skid, pawing, the stomp's rearing,
##        the gore, a roar; pictures every few frames (gait_<n>_<what>.png), the camera following from the side.
## dazed: (v0.12.0) the stun meter's 7 s daze: the collapse, the dazed sway and the struggle up (strip_dazed.png, and
##        a 3/4 front close-up strip strip_dazed_front.png).
extends SceneTree

var out := "user://"
var mode := "model"
var cam: Camera3D
var world: Node3D
var model: BossModel
var view: BossView
var frame := 0
var shots: Array = []   # model mode: [pose name, pose dict, view angle]
var target: Node3D


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0] if a.size() > 0 else out
	mode = a[1] if a.size() > 1 else "model"
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
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("6f8f74")
	ground.material_override = gm
	world.add_child(ground)
	for i in 40:   # posts so movement reads
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.4, 1.2, 0.4)
		post.mesh = bm
		post.position = Vector3(-12.0, 0.6, -200.0 + i * 10.0)
		world.add_child(post)
	cam = Camera3D.new()
	cam.fov = 45.0
	world.add_child(cam)
	cam.make_current()
	target = Node3D.new()
	world.add_child(target)
	if mode == "model":
		model = BossModel.new()
		world.add_child(model)
		model.build()
		var poses := {
			"stand": {"head_dip": 0.15, "brow": -0.5, "lid": 0.35},
			"roar": {"head_up": 0.8, "jaw": 0.85, "brow": 1.0, "lid": 0.0, "tongue": 1.0, "flare": 1.0},
			"charge": {"head_dip": 0.6, "crouch": 0.3, "brow": -1.0, "lid": 0.6, "flare": 1.0},
			"rear": {"pitch": 0.65, "head_up": 0.3, "jaw": 0.4, "brow": 0.3},
		}
		for k in poses:
			for v in [35, 90, 160, 270]:
				shots.append([k, poses[k], v, 16.0, Vector3(0, 3.5, -0.5)])
		for k in ["stand", "roar"]:   # face close-ups from the front and a little to the side
			for v in [0, 30]:
				shots.append(["face_" + k, poses[k], v, 7.5, Vector3(0, 4.2, -4.4)])
	else:
		var net := Net.new()
		var fx := MagicFx.new()
		fx.net = net
		fx.main = world
		world.add_child(fx)
		fx.avatars[1] = target
		view = BossView.new()
		world.add_child(view)
		view.setup(net, world, fx)
	process_frame.connect(_tick)


var _st := 0.0
var _pos := Vector3.ZERO
var _yaw := 0.0
var _gt := 0.0


func _tick() -> void:
	frame += 1
	if mode == "model":
		_model_tick()
	else:
		_gait_tick()


func _model_tick() -> void:
	var i := (frame - 2) / 3
	if i >= shots.size():
		quit()
		return
	if i < 0:
		return
	var s: Array = shots[i]
	var legs := []
	for l in BossModel.LEGS:
		legs.append({"t": BossModel.foot_home(l)})
	var p: Dictionary = s[1]
	model.look_target = Vector3(6, 1.5, -12)
	model.apply(p, legs, frame * 0.05, 0.016)
	model.set_look(Color("6fb0ff"), 0.6 if s[0] != "stand" else 0.0, 0.0, 0.0)
	var ang := deg_to_rad(float(s[2]))
	var at: Vector3 = s[4]
	cam.look_at_from_position(at + Vector3(-sin(ang), 0.25, -cos(ang)) * float(s[3]), at)
	if (frame - 2) % 3 == 2:
		get_root().get_texture().get_image().save_png(out.path_join(("%s_%03d.png" if str(s[0]).begins_with("face") else "bull_%s_%03d.png") % [s[0], int(s[2])]))


# script: [seconds, state, speed m/s, yaw rate rad/s, motion name, event at the start]
const PLAN := [[1.6, "IDLE", 0.0, 0.0, "idle", ""], [2.4, "WALK", 4.5, 0.0, "walk", ""], [1.6, "WALK", 9.5, 0.0, "trot", ""],
	[1.6, "CHARGE", 19.0, 0.0, "gallop", ""], [1.0, "IDLE", 0.0, 0.0, "skid", "boss_skid"],
	[1.4, "TURN", 0.0, 2.0, "turn", ""], [1.6, "WALK", 5.0, 0.7, "walkturn", ""], [1.6, "PAW", 0.0, 0.0, "paw", ""],
	[2.6, "IDLE", 0.0, 0.0, "buck", "boss_snort"], [2.6, "HOWL", 0.0, 0.0, "rear", ""],
	[0.7, "STOMP_WIND", 0.0, 0.0, "stompwind", ""], [1.3, "STOMP", 0.0, 0.0, "stomp", ""],
	[1.4, "LEAP_WIND", 0.0, 0.0, "jumpwind", ""], [1.0, "LEAP", 0.0, 0.0, "jump", ""], [0.8, "LEAP_LAND", 0.0, 0.0, "land", ""],
	[0.45, "GORE_WIND", 0.0, 0.0, "gorewind", ""], [0.4, "GORE", 0.0, 0.0, "gore", ""], [1.1, "ROAR", 0.0, 0.0, "roar", ""],
	[0.9, "STAGGER", 0.0, 0.0, "stagger", ""], [0.8, "IDLE", 0.0, 0.0, "end", ""]]
const DAZED_PLAN := [[7.0, "DAZED", 0.0, 0.0, "dazed", "boss_dazed"], [1.2, "IDLE", 0.0, 0.0, "end", "boss_get_up"]]
const STRIP_N := 8
var plan: Array = PLAN
var _strip: Array = []
var _last := ""


var _fired := ""


func _gait_tick() -> void:
	var dt := 1.0 / 60.0
	var warm := frame < 12   # v0.12.2: let the first frames render before anything is captured (no black frame)
	if not warm:
		_gt += dt
	var tot := 0.0
	var cur: Array = plan[-1]
	var into := 0.0
	var done := true
	if mode == "dazed":
		plan = DAZED_PLAN
	for s in plan:
		if _gt < tot + float(s[0]):
			cur = s
			into = _gt - tot
			done = false
			break
		tot += float(s[0])
	if done:
		quit()
		return
	var st: int = Boss.S[cur[1]]
	_yaw += float(cur[3]) * dt
	var fwd := Vector3(-sin(_yaw), 0, -cos(_yaw))
	_pos += fwd * float(cur[2]) * dt
	var name: String = cur[4]
	if name != _last:
		if _last != "" and not _strip.is_empty():
			_save_strip(_last)
		_last = name
		_st = 0.0
	elif not warm:
		_st += dt
	var y := 0.0
	var air := 60
	if cur[1] == "LEAP":
		var u := into / float(cur[0])
		y = 4.0 * 7.0 * u * (1.0 - u)
	var extra := [_pos.x, _pos.z, 0, 0, 1, 0, 0, air]
	target.position = _pos + fwd * 14.0 + Vector3(4, 0, 0)
	view._on_state(0, [st, int(_st / Config.DT), _pos.x, y, _pos.z, _yaw, 7000, 7000, 0, _yaw, [], [], PackedVector3Array(), extra])
	view.hud.visible = false
	if cur[5] != "" and not warm and _fired != name:
		_fired = name
		view._on_fx(cur[5], [_pos, _yaw])
	if warm:
		cam.look_at_from_position(_pos + Vector3(-11, 3, 9), _pos + Vector3(0, 2.6, 0))
		return
	var side := Vector3(cos(_yaw), 0, -sin(_yaw))
	var at := (view.root.position if view.root else _pos) + Vector3(0, 3.2, 0)
	at.y = 3.2 + y * 0.5
	if mode == "dazed":   # three-quarter front, a little lower
		at.y = 2.6
		if OS.get_environment("DAZE_VIEW") == "side":   # straight from the side, for the legs
			cam.look_at_from_position(at - side * 15.0 + Vector3(0, 0.5, 0), at)
		else:
			cam.look_at_from_position(at - side * 11.0 + fwd * 9.0 + Vector3(0, 0.2, 0), at)
	else:
		cam.look_at_from_position(at - side * 15.0 + fwd * 2.0 + Vector3(0, 0.5, 0), at)
	var d := float(cur[0])
	var n := DAZED_N if name == "dazed" else STRIP_N
	var k := int(floor(into / d * n))
	if k < n and _strip.size() == k:
		var img := get_root().get_texture().get_image()
		img.resize(480, 270, Image.INTERPOLATE_BILINEAR)
		_strip.append(img)
	if name == "dazed" and OS.get_environment("DAZE_FRAMES") != "" and int(round(_st * 60.0)) % 6 == 0:
		get_root().get_texture().get_image().save_png(out.path_join("dz_%03d.png" % int(round(_st * 10.0))))


const DAZED_N := 12   # v0.12.2: the daze strip has 12 frames (3 rows)


func _save_strip(name: String) -> void:
	var rows := (_strip.size() + 3) / 4
	var w := Image.create(1920, 270 * rows, false, _strip[0].get_format())
	for i in _strip.size():
		w.blit_rect(_strip[i], Rect2i(0, 0, 480, 270), Vector2i((i % 4) * 480, (i / 4) * 270))
	w.save_png(out.path_join("strip_%s.png" % name))
	_strip = []
