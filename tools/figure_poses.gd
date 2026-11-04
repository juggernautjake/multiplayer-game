## Pose sheet for the 3D figure: a row of figures frozen at key moments (idle with each weapon, wind-ups, impacts,
## full bow and slingshot draws), rendered to a PNG. Run windowed:
##   Godot.exe --path . -s tools/figure_poses.gd -- out.png [yaw_degrees]
extends SceneTree

var frames := 0
var out := "user://poses.png"
var figs: Array = []
var cam: Camera3D

# [label, weapon, combo, t through the move (or -1 = idle), charge fraction (ranged)]
const POSES := [
	["sword idle", Weapons.SWORD, 0, -1.0, 0.0], ["slash windup", Weapons.SWORD, 0, 0.0, 0.0], ["slash hit", Weapons.SWORD, 0, 0.3, 0.0],
	["backslash hit", Weapons.SWORD, 1, 0.3, 0.0], ["thrust hit", Weapons.SWORD, 2, 0.33, 0.0],
	["club idle", Weapons.CLUB, 0, -1.0, 0.0], ["bash windup", Weapons.CLUB, 0, 0.05, 0.0], ["bash hit", Weapons.CLUB, 0, 0.44, 0.0],
	["smash raised", Weapons.CLUB, 2, 0.36, 0.0], ["smash hit", Weapons.CLUB, 2, 0.5, 0.0],
	["bow idle", Weapons.BOW, 0, -1.0, 0.0], ["bow full draw", Weapons.BOW, 0, -1.0, 1.0],
	["sling draw", Weapons.SLING, 0, -1.0, 1.0], ["jab", Weapons.FISTS, 0, 0.3, 0.0], ["kick", Weapons.FISTS, 2, 0.36, 0.0],
]


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	var view_yaw := deg_to_rad(float(a[1])) if a.size() > 1 else deg_to_rad(145.0)   # 180 = facing the camera
	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("cfd8dc")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	root.add_child(sun)
	var cols := 5
	for i in POSES.size():
		var p: Array = POSES[i]
		var f := FigureAvatar.new(p[0], Color("4363d8"), true)
		f.instant = true
		f.position = Vector3((i % cols) * 2.4, 0, (i / cols) * 4.5)
		f.yaw = view_yaw
		var st := Sim.PlayerState.new()
		st.weapon = p[1]
		st.combo = p[2]
		if float(p[3]) >= 0.0:
			var mv := Weapons.move(st.weapon, st.combo)
			st.atk = maxi(1, int(round(float(mv.swing) * (1.0 - float(p[3])))))
		if float(p[4]) > 0.0:
			st.charge = int(float(Weapons.get_data(st.weapon).draw) * float(p[4]))
		f.state = st
		root.add_child(f)
		figs.append(f)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 12.0
	root.add_child(cam)
	cam.look_at_from_position(Vector3(4.8, 7.5, 16.0), Vector3(4.8, 0.6, 4.5))
	cam.make_current()


func _process(_d: float) -> bool:
	frames += 1
	for f in figs:
		f.animate(1.0 / 60.0, cam)
		f._swing_fx(null)
	if frames == 20:
		get_root().get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		return true
	return false
