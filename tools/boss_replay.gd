## v0.12.9 replays what a guest received of Thunderhorn (main.gd --bosslog: every boss_state as it arrived, with the
## guest's clock and position each frame) through a real BossView, frame by frame, so a laggy guest's view of his
## orbs can be recorded with Godot's movie maker (a live window can't be: the movie maker slows the game clock).
##   Godot.exe --path . --resolution 1280x720 --write-movie out.avi --fixed-fps 60 -s tools/boss_replay.gd -- <log> [label] [from_s] [secs]
## from_s / secs: where to start (seconds after the first orb arrived, default -2) and how long (default 12).
extends SceneTree

var view: BossView
var net: Net
var cam: Camera3D
var me_n: Node3D
var label: Label
var packets: Array = []   # [ms, tick, data]
var clock: Array = []     # [ms, render tick, pos, cam yaw]
var t0 := 0.0
var secs := 12.0
var tag := ""
var _f := 0
var _pi := 0
var _ci := 0


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	tag = a[1] if a.size() > 1 else ""
	var from := float(a[2]) if a.size() > 2 else -2.0
	secs = float(a[3]) if a.size() > 3 else 12.0
	var f := FileAccess.open(a[0], FileAccess.READ)
	var first_orb := -1.0
	while not f.eof_reached():
		var l := f.get_line()
		var p := l.split("|")
		if p.size() < 4:
			continue
		if p[0] == "B":
			var d: Array = bytes_to_var(Marshalls.base64_to_raw(p[3]))
			packets.append([float(p[1]), int(p[2]), d])
			if first_orb < 0.0 and d.size() > 12 and (d[12] as PackedVector3Array).size() > 0:
				first_orb = float(p[1])
		elif p[0] == "R":
			var v := p[3].split(",")
			clock.append([float(p[1]), float(p[2]), Vector3(float(v[0]), float(v[1]), float(v[2])), float(p[4]) if p.size() > 4 else 0.0])
	t0 = first_orb + from * 1000.0
	var world := Node3D.new()
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
	for i in 40:   # posts so motion reads
		for j in 40:
			if (i + j) % 3 == 0:
				var post := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.25, 0.6, 0.25)
				post.mesh = bm
				post.position = Vector3(-100 + i * 5.0, 0.3, -40 + j * 5.0)
				world.add_child(post)
	cam = Camera3D.new()
	cam.fov = 70.0
	world.add_child(cam)
	cam.make_current()
	me_n = MeshInstance3D.new()   # the guest: a capsule where it stood
	var cm := CapsuleMesh.new()
	cm.radius = 0.4
	cm.height = 1.8
	(me_n as MeshInstance3D).mesh = cm
	world.add_child(me_n)
	net = Net.new()
	net.my_id = 2
	var fx := MagicFx.new()
	fx.net = net
	fx.main = world
	world.add_child(fx)
	fx.avatars[2] = me_n
	view = BossView.new()
	world.add_child(view)
	view.setup(net, world, fx)
	var hud := CanvasLayer.new()
	world.add_child(hud)
	label = Label.new()
	label.position = Vector2(24, 18)
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_constant_override("outline_size", 10)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_child(label)
	process_frame.connect(_frame)


func _frame() -> void:
	var now := t0 + _f * 1000.0 / 60.0
	_f += 1
	if now > t0 + secs * 1000.0:
		quit()
		return
	while _ci + 1 < clock.size() and float(clock[_ci + 1][0]) <= now:
		_ci += 1
	var c: Array = clock[_ci]
	net.render_tick = float(c[1])   # (BossView adds the physics fraction; the movie maker keeps it small)
	while _pi < packets.size() and float(packets[_pi][0]) <= now:
		view._on_state(int(packets[_pi][1]), packets[_pi][2])
		_pi += 1
	if view.hud:
		view.hud.visible = false
	var me: Vector3 = c[2]
	me_n.position = me + Vector3(0, 0.9, 0)
	var yaw := float(c[3])
	var back := Vector3(sin(yaw), 0, cos(yaw))
	cam.look_at_from_position(me + back * 7.0 + Vector3(0, 3.2, 0), me + Vector3(0, 1.6, 0) - back * 6.0)
	label.text = "%s   guest view, 120 ms ping, 30 ms jitter, 2%% loss   t %.1f s" % [tag, (now - t0) / 1000.0]
