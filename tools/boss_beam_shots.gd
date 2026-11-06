## Thunderhorn's horn beam, start to finish (v0.12.0): a real BossView fed made-up server states (idle, BEAM_WIND
## with the feeder beams and the growing orb, BEAM sweeping there and back as when enraged, the collapse), at dusk
## with a few posts and a player-sized dummy so the light reads. Run windowed:
##   Godot.exe --path . --resolution 1280x720 -s tools/boss_beam_shots.gd -- <out dir> [stills|clip] [wide|close]
## stills: beam_<n>_<what>.png at chosen moments (five camera angles); also prints how far the orb sits from the nose
## spike's tip. clip: no stills, the camera dollying from his front round to his side; record it with the movie maker, e.g.
##   Godot.exe --path . --resolution 1280x720 --write-movie beam.avi --fixed-fps 30 -s tools/boss_beam_shots.gd -- <dir> clip
extends SceneTree

var out := "user://"
var mode := "stills"
var cam: Camera3D
var world: Node3D
var view: BossView
var net: Net
var frame := 0
var _gt := 0.0
var _last_st := -1
var _st := 0.0
var dummy: Node3D
var _shots_done := {}

const WIND := 1.0
const FIRE := 160   # ticks (enraged: there and back)
# [time (s), name, camera: 0 side, 1 front three-quarter, 2 low behind the dummy]
const STILLS := [[0.15, "idle", 1], [0.55, "feeders", 1], [0.8, "orb_small", 1], [1.25, "orb_grown", 1], [1.38, "orb_close", 3],
	[1.5, "fire", 1], [1.9, "sweep_a", 0], [2.3, "sweep_b", 2], [2.75, "sweep_c", 1], [3.3, "back", 0], [3.6, "impact", 4],
	[4.15, "collapse", 1], [4.6, "after", 1]]


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0] if a.size() > 0 else out
	mode = a[1] if a.size() > 1 else "stills"
	DirAccess.make_dir_recursive_absolute(out)
	world = Node3D.new()
	get_root().add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("2a3346")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.22, 0.24, 0.32)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 1.0
	e.glow_bloom = 0.15
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, -40, 0)
	sun.light_energy = 0.35
	sun.light_color = Color("9fb0d8")
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("4e6650")
	gm.roughness = 0.9
	ground.material_override = gm
	world.add_child(ground)
	for i in 14:   # posts in an arc in front of him so the light reads
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.35, 1.6, 0.35)
		post.mesh = bm
		var ang := -1.1 + i * 2.2 / 13.0
		post.position = Vector3(-sin(ang), 0, -cos(ang)) * 28.0 + Vector3(0, 0.8, 0)
		world.add_child(post)
	dummy = MeshInstance3D.new()   # a player-sized figure, standing in the sweep
	var cm := CapsuleMesh.new()
	cm.radius = 0.4
	cm.height = 1.8
	(dummy as MeshInstance3D).mesh = cm
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color("c8b090")
	(dummy as MeshInstance3D).material_override = dm
	dummy.position = Vector3(5.5, 0.9, -15.0)
	world.add_child(dummy)
	cam = Camera3D.new()
	cam.fov = 50.0
	world.add_child(cam)
	cam.make_current()
	net = Net.new()
	var fx := MagicFx.new()
	fx.net = net
	fx.main = world
	world.add_child(fx)
	fx.avatars[1] = dummy
	view = BossView.new()
	world.add_child(view)
	view.setup(net, world, fx)
	process_frame.connect(_tick)


func _beam_a(t: int) -> float:
	var sweep := deg_to_rad(150.0)
	var from := -sweep * 0.5
	var to := sweep * 0.5
	if t <= 90:
		return lerp_angle(from, to, clampf(float(t) / 90.0, 0.0, 1.0))
	return lerp_angle(to, from, clampf(float(t - 90) / 70.0, 0.0, 1.0))


func _tick() -> void:
	frame += 1
	var dt := 1.0 / 60.0 if mode == "stills" else 1.0 / 30.0
	_gt += dt
	var st := Boss.S.IDLE
	var t := _gt
	var ba := 0.0
	if _gt >= 0.3 and _gt < 0.3 + WIND:
		st = Boss.S.BEAM_WIND
		t = _gt - 0.3
	elif _gt >= 0.3 + WIND and _gt < 0.3 + WIND + FIRE / 60.0:
		st = Boss.S.BEAM
		t = _gt - 0.3 - WIND
		ba = _beam_a(int(t * 60.0))
	elif _gt >= 0.3 + WIND:
		t = _gt - 0.3 - WIND - FIRE / 60.0
	if st != _last_st:
		_last_st = st
		if st == Boss.S.BEAM_WIND:
			view._on_fx("boss_beam_wind", [Vector3.ZERO, 1])
		elif st == Boss.S.BEAM:
			view._on_fx("boss_beam", [Vector3.ZERO, -1.3, 1.3, FIRE])
	view._on_state(0, [st, int(t * 60.0), 0.0, 0.0, 0.0, 0.0, 9000, 14000, 0, ba, [], [],
		PackedVector3Array(), [0.0, 0.0, 1, 1, 1, 0, 0, 60, 0.0]])
	view.state_t = t   # (the view counts its own time in a state; keep it on the script's clock)
	view.hud.visible = false
	var at := Vector3(0, 2.5, -9.0)
	if mode == "clip":   # front three-quarter for the charge-up, then a slow dolly round to his side for the sweep
		var k := clampf((_gt - 1.4) / 2.2, 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		cam.look_at_from_position(Vector3(13, 7.0, -21).lerp(Vector3(-24, 6.5, -6), k), Vector3(0, 3.0, -4).lerp(Vector3(0, 2.0, -10), k))
	else:
		var which := 1
		for s in STILLS:
			if _gt >= float(s[0]) - 0.001:
				which = int(s[2])
		_cam(which)
	if _gt > 0.3 + WIND + 0.5 and _gt < 0.3 + WIND + 0.52 and view.model != null and view.horn_beam != null:
		var tip: Vector3 = (view.model.anchors["spike"] as Node3D).global_position
		print("spike tip %s  orb %s  apart %.2f m" % [str(tip), str(view.horn_beam.orb.global_position), tip.distance_to(view.horn_beam.orb.global_position)])
	if mode == "stills":
		for i in STILLS.size():
			var s: Array = STILLS[i]
			if not _shots_done.has(i) and _gt >= float(s[0]):
				_shots_done[i] = true
				get_root().get_texture().get_image().save_png(out.path_join("beam_%02d_%s.png" % [i, s[1]]))
	if _gt > 4.9:
		quit()


func _cam(which: int) -> void:
	match which:
		0:   # from his left side, wide
			cam.look_at_from_position(Vector3(-24, 6.5, -6), Vector3(0, 2.0, -10))
		1:   # front three-quarter
			cam.look_at_from_position(Vector3(13, 7.0, -21), Vector3(0, 3.0, -4))
		2:   # low, behind the dummy, looking back at him down the beam
			cam.look_at_from_position(Vector3(9, 2.2, -26), Vector3(0, 3.2, -3))
		3:   # close on the head and the orb
			cam.look_at_from_position(Vector3(6.5, 5.0, -11.5), Vector3(0, 3.6, -5.5))
		4:   # the impact on the ground
			cam.look_at_from_position(Vector3(-12, 4.0, -26), Vector3(-6, 0.5, -18))
