## Close-up of the 3D figure in one pose, rendered to a PNG, with small markers: red = right hand, green = left hand,
## yellow = the weapon's grip point (it should sit in the hand). Run windowed:
##   Godot.exe --path . -s tools/figure_poses.gd -- out.png <pose> [view_degrees] [no-markers]
## Poses: idle, sword, slash, thrust, club, bash, smash, bow, bowdraw, bowrelease, sling, slingdraw, jab, kick
extends SceneTree

var frames := 0
var out := "user://pose.png"
var fig: FigureAvatar
var cam: Camera3D
var markers := true
var marks: Array = []

const POSES := {
	"idle": [Weapons.FISTS, 0, -1.0, 0.0], "sword": [Weapons.SWORD, 0, -1.0, 0.0], "slash": [Weapons.SWORD, 0, 0.3, 0.0],
	"thrust": [Weapons.SWORD, 2, 0.33, 0.0], "club": [Weapons.CLUB, 0, -1.0, 0.0], "bash": [Weapons.CLUB, 0, 0.44, 0.0],
	"smash": [Weapons.CLUB, 2, 0.36, 0.0], "bow": [Weapons.BOW, 0, -1.0, 0.0], "bowdraw": [Weapons.BOW, 0, -1.0, 1.0],
	"bowrelease": [Weapons.BOW, 0, -2.0, 0.0], "sling": [Weapons.SLING, 0, -1.0, 0.0], "slingdraw": [Weapons.SLING, 0, -1.0, 1.0],
	"jab": [Weapons.FISTS, 0, 0.3, 0.0], "cross": [Weapons.FISTS, 1, 0.31, 0.0], "kick": [Weapons.FISTS, 2, 0.35, 0.0],
	"slashwind": [Weapons.SWORD, 0, 0.0, 0.0], "smashhit": [Weapons.CLUB, 2, 0.5, 0.0],
}


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0] if a.size() > 0 else out
	var pose: String = a[1] if a.size() > 1 else "idle"
	var view := deg_to_rad(float(a[2])) if a.size() > 2 else deg_to_rad(30.0)
	markers = not (a.size() > 3 and a[3] == "no-markers")
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
	fig = FigureAvatar.new(pose, Color("4363d8"), false)
	fig.instant = true
	fig.yaw = PI   # faces +Z, toward a camera at view 0
	var p: Array = POSES.get(pose, POSES["idle"])
	var st := Sim.PlayerState.new()
	st.weapon = p[0]
	st.combo = p[1]
	st.owned = 0b11111
	st.arrows = 10
	st.rocks = 10
	if float(p[2]) >= 0.0:
		var mv := Weapons.move(st.weapon, st.combo)
		st.atk = maxi(1, int(round(float(mv.swing) * (1.0 - float(p[2])))))
	elif float(p[2]) == -2.0:   # just released
		var d := Weapons.get_data(st.weapon)
		st.atk = int(d.shot) - 3
		st.atk_cd = int(d.cooldown) - 3
	if float(p[3]) > 0.0:
		st.charge = int(float(Weapons.get_data(st.weapon).draw) * float(p[3]))
	fig.state = st
	root.add_child(fig)
	cam = Camera3D.new()
	cam.fov = 38.0
	root.add_child(cam)
	var at := Vector3(0, 1.15, 0)
	cam.look_at_from_position(at + Vector3(sin(view), 0.12, cos(view)) * 4.2, at)
	cam.make_current()
	for c in [Color.RED, Color.GREEN, Color.YELLOW]:
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.022
		sm.height = 0.044
		m.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = c
		mat.no_depth_test = true
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.material_override = mat
		m.visible = markers
		root.add_child(m)
		marks.append(m)


func _process(_d: float) -> bool:
	frames += 1
	fig.animate(1.0 / 60.0, cam)
	(marks[0] as Node3D).global_position = fig.model.to_global(fig.last_hand_r)
	(marks[1] as Node3D).global_position = fig.model.to_global(fig.last_hand_l)
	(marks[2] as Node3D).global_position = fig.model.to_global(fig.last_grip)
	if frames == 12:
		get_root().get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		return true
	return false
