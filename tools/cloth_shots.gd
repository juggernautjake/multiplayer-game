extends SceneTree
## Pictures of the 3D figure's cloth through every move (tools/cloth_rig.gd), each moment from five sides at once
## (front, back, the right and left sides, three-quarters front-left): <out>/<prefix>_<weapon>_<moment>_<view>.png.
## Cloth points inside the body are marked with red dots (seen through everything). Run windowed:
##   Godot.exe --path . --script tools/cloth_shots.gd -- <out_dir> <prefix> [weapons, e.g. 2,0] [movie]
## `movie`: instead, every frame of one weapon's run from an orbiting camera: <out>/<prefix>_movie_00000.png
## `fps`: eight figures in different costumes running through their moves side by side, the frame rate printed.

const VIEWS := { "front": Vector3(0, 0, -1), "back": Vector3(0, 0, 1), "right": Vector3(1, 0, 0), "left": Vector3(-1, 0, 0),
	"q34": Vector3(-0.72, 0, -0.7) }
var out := ""
var prefix := "shot"
var weapons: Array = []
var movie := false
var rig
var Rig
var cams := {}
var vps := {}
var marks: Array = []
var wait := 0
var pending := ""
var frame := 0
var stats := {}
var fps_mode := false
var crowd: Array = []
var t_start := 0


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0]
	prefix = a[1] if a.size() > 1 else prefix
	weapons = [Weapons.FISTS, Weapons.SWORD, Weapons.CLUB, Weapons.BOW, Weapons.SLING, Weapons.STAFF, Weapons.WAND]
	if a.size() > 2 and a[2] != "all":
		weapons = Array(a[2].split(",")).map(func(x): return int(x))
	movie = a.size() > 3 and a[3] == "movie"
	fps_mode = a.size() > 3 and a[3] == "fps"
	Rig = load("res://tools/cloth_rig.gd")
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("cfd8dc")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -25, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 155, 0)
	fill.light_energy = 0.45
	root.add_child(fill)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("8fa37a")
	ground.material_override = gm
	root.add_child(ground)
	if fps_mode:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		root.size = Vector2i(1280, 720)
		var c := Camera3D.new()
		c.fov = 50.0
		root.add_child(c)
		c.look_at_from_position(Vector3(0, 3.0, 9.0), Vector3(0, 1.0, 0))
		c.make_current()
		var all := [Weapons.FISTS, Weapons.SWORD, Weapons.CLUB, Weapons.BOW, Weapons.SLING, Weapons.STAFF, Weapons.WAND, Weapons.STAFF]
		for i in 8:
			crowd.append(Rig.new(root, all[i], Vector3(-7.0 + 2.0 * i, 0, 0)))
		return
	if movie:
		root.size = Vector2i(960, 720)
		var c := Camera3D.new()
		c.fov = 45.0
		root.add_child(c)
		c.make_current()
		cams["movie"] = c
	else:
		for v in VIEWS:
			var vp := SubViewport.new()
			vp.size = Vector2i(260, 340)
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			vp.msaa_3d = Viewport.MSAA_4X
			root.add_child(vp)
			var c := Camera3D.new()
			c.fov = 34.0
			vp.add_child(c)
			cams[v] = c
			vps[v] = vp
	for i in 40:
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.018
		sm.height = 0.036
		m.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.RED
		mat.no_depth_test = true
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.material_override = mat
		m.visible = false
		root.add_child(m)
		marks.append(m)
	_next_weapon()


func _next_weapon() -> void:
	if rig != null:
		rig.fig.queue_free()
		rig = null
	if weapons.is_empty():
		for w in stats:
			print("%s: worst %s" % [w, stats[w]])
		quit()
		return
	var w: int = weapons.pop_front()
	rig = Rig.new(root, w)


func _place_cams() -> void:
	var f: FigureAvatar = rig.fig
	var at := f.position + Vector3(0, 1.0, 0)
	var b := Basis(Vector3.UP, f.yaw)
	if movie:
		var ang := float(frame) * 0.012
		var c: Camera3D = cams["movie"]
		c.look_at_from_position(at + Vector3(sin(ang) * 4.2, 0.9, cos(ang) * 4.2), at + Vector3(0, -0.1, 0))
		return
	for v in VIEWS:
		var c: Camera3D = cams[v]
		var d: Vector3 = b * (VIEWS[v] as Vector3).normalized()
		c.look_at_from_position(at + d * 4.0 + Vector3(0, 0.35, 0), at)


func _mark() -> void:
	var f: FigureAvatar = rig.fig
	var i := 0
	var worst := 0.0
	for cp in f._garb.cloth_points():
		var bd = f.body_depth(cp[0])
		if float(bd[0]) > 0.012 and i < marks.size():
			(marks[i] as Node3D).global_position = cp[0]
			(marks[i] as Node3D).visible = true
			i += 1
		worst = maxf(worst, float(bd[0]))
	for k in range(i, marks.size()):
		(marks[k] as Node3D).visible = false


func _process(_d: float) -> bool:
	if fps_mode:
		frame += 1
		var mid := Vector3.ZERO
		for r in crowd:
			if not r.done():
				r.step()
			mid += r.fig.position / float(crowd.size())
		(root.get_camera_3d() as Camera3D).look_at_from_position(mid + Vector3(0, 3.0, 9.0), mid + Vector3(0, 1.0, 0))
		if frame == 60:
			t_start = Time.get_ticks_usec()
			WizardGarb.busy_usec = 0
		if frame == 660:
			var ms := (Time.get_ticks_usec() - t_start) / 1000.0 / 600.0
			print("8 figures on screen: %.1f fps (%.2f ms a frame), cloth %.2f ms a frame" % [1000.0 / ms, ms, WizardGarb.busy_usec / 1000.0 / 600.0])
			quit()
			return true
		return false
	if rig == null:
		return true
	if wait > 0:
		wait -= 1
		if wait == 0:
			var wn: String = Weapons.NAMES[rig.weapon]
			for v in vps:
				(vps[v] as SubViewport).get_texture().get_image().save_png(out.path_join("%s_%s_%s_%s.png" % [prefix, wn, pending, v]))
			var m: Dictionary = rig.measure()
			print("%s %s: depth %.3f (%s in %s) reach +%.2f" % [wn, pending, m.depth, m.piece, m.part, m.reach])
		return false
	if rig.done():
		_next_weapon()
		return false
	rig.step()
	_place_cams()
	if not movie:
		_mark()
	frame += 1
	if movie:
		if frame > 30:
			root.get_texture().get_image().save_png(out.path_join("%s_movie_%05d.png" % [prefix, frame]))
	elif rig.label != "":
		pending = rig.label
		wait = 2
	return false
