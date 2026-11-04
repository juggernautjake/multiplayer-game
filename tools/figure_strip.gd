## A filmstrip of one move: the 3D figure posed tick by tick through the whole move at 60 fps (springs and all), with
## every Nth frame saved. Run windowed:  Godot.exe --path . -s tools/figure_strip.gd -- <out_prefix> <weapon> <combo> [view] [every]
## weapon: 0 fists 1 club 2 sword 3 bow 4 sling. For bow / sling it draws to full, holds, releases.
extends SceneTree

var fig: FigureAvatar
var cam: Camera3D
var st: Sim.PlayerState
var tick := -10
var total := 0
var every := 4
var prefix := "user://strip"
var weapon := 0
var saved := 0


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	prefix = a[0]
	weapon = int(a[1])
	var combo := int(a[2])
	var view := deg_to_rad(float(a[3])) if a.size() > 3 else deg_to_rad(60.0)
	every = int(a[4]) if a.size() > 4 else 4
	var root := Node3D.new()
	get_root().add_child(root)
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
	root.add_child(sun)
	fig = FigureAvatar.new("x", Color("4363d8"), false)
	fig.yaw = PI
	st = Sim.PlayerState.new()
	st.weapon = weapon
	st.combo = combo
	st.owned = 0b11111
	st.arrows = 10
	st.rocks = 10
	fig.state = st
	root.add_child(fig)
	var d := Weapons.get_data(weapon)
	total = int(Weapons.move(weapon, combo).swing) + 20 if d.kind == "melee" else int(d.draw) + 20 + int(d.cooldown) + 10
	cam = Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	cam.look_at_from_position(Vector3(sin(view), 0.15, cos(view)) * 4.6 + Vector3(0, 1.1, 0), Vector3(0, 1.0, 0))
	cam.make_current()


func _process(_d: float) -> bool:
	tick += 1
	var d := Weapons.get_data(weapon)
	if tick >= 0:
		if d.kind == "melee":
			var mv := Weapons.move(weapon, st.combo)
			st.atk = maxi(int(mv.swing) - tick, 0)
		else:
			var draw := int(d.draw)
			if tick <= draw + 20:
				st.charge = mini(tick, draw)   # draw, then hold
				st.atk = 0
			else:
				var after := tick - draw - 20
				st.charge = 0
				st.atk = maxi(int(d.shot) - after, 0)
				st.atk_cd = maxi(int(d.cooldown) - after, 0)
				if after == 0:
					st.swing_n += 1
	fig.animate(1.0 / 60.0, cam)
	if OS.get_environment("STRIP_DEBUG") != "" and tick >= 0 and tick % 3 == 0:
		print(tick, " atk ", st.atk, " hand_r ", fig._hand_r, " hand_l ", fig._hand_l)
	if tick >= 0 and tick % every == 0:
		get_root().get_viewport().get_texture().get_image().save_png("%s_%03d.png" % [prefix, tick])
		saved += 1
	return tick > total
