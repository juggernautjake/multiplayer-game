## The game shell: start menu, the world (sky, light, a big open plane with landmarks), player avatars, the camera
## (third person or first person, V to switch) and the controls. Networking and simulation live in Net / Sim.
##
## Command line (after `--`):  --server [--port 7777]   run a dedicated server with no window and no player
##                             --host / --join <address>  [--name <name>]   skip the menu
##                             --bot          a scripted player (walks, sprints, jumps, dashes) for testing
##                             --screenshot <file.png> [--shot-frame 240] [--view first]   save one frame and quit
extends Node3D

const MOUSE_SENS := 0.0025
const CAM_HEIGHT := 1.6   # third-person focus height
const EYE_HEIGHT := 1.62  # first-person eye height

enum View { THIRD, FIRST }

var net: Net
var cam: Camera3D
var avatars := {}  # id -> Node3D
var cam_yaw := 0.0
var cam_pitch := -0.25
var view := View.THIRD
var cam_dist := 6.0
var menu: Control
var hud: Label
var status_label: Label
var name_edit: LineEdit
var addr_edit: LineEdit
var port_edit: LineEdit
var host_info := ""  # the addresses friends can join, shown under the HUD while hosting
var bot := false
var bot_t := 0
var shot_path := ""
var shot_frame := 240
var frames := 0


func _ready() -> void:
	net = Net.new()
	net.name = "Net"
	add_child(net)
	net.input_source = _sample_input
	net.roster_changed.connect(_on_roster)
	net.status.connect(_on_status)

	var args := _args()
	if args.has("server"):
		var port := int(args.get("port", Config.DEFAULT_PORT))
		var err := net.host(port, "", false)
		print("Dedicated server on UDP port %d: %s" % [port, "ok" if err == OK else error_string(err)])
		_print_addresses(port)
		return

	bot = args.has("bot")
	shot_path = str(args.get("screenshot", ""))
	shot_frame = int(args.get("shot-frame", 240))
	if str(args.get("view", "")) == "first":
		view = View.FIRST
	_build_world()
	_build_ui()
	if args.has("name"):
		name_edit.text = str(args["name"])
	if args.has("port"):
		port_edit.text = str(args["port"])
	if args.has("host"):
		_start_host()
	elif args.has("join"):
		addr_edit.text = str(args["join"])
		_start_join()


func _on_status(text: String) -> void:
	if status_label:
		status_label.text = text
	if menu and net.my_id == 0:  # the connection failed or dropped: back to the menu
		menu.visible = true
		host_info = ""
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _args() -> Dictionary:
	var out := {}
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		var k := a[i].trim_prefix("--")
		if i + 1 < a.size() and not a[i + 1].begins_with("--"):
			out[k] = a[i + 1]
			i += 2
		else:
			out[k] = true
			i += 1
	return out


# ================================================================ the world
func _build_world() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("3a6fb0")
	sky_mat.sky_horizon_color = Color("a9c6e8")
	sky_mat.ground_horizon_color = Color("a9c6e8")
	sky_mat.ground_bottom_color = Color("4a5a3a")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("a9c6e8")
	env.fog_density = 0.004
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)

	# the open plane, with a grid so motion reads clearly
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(Config.WORLD_HALF * 2, Config.WORLD_HALF * 2)
	ground.mesh = plane
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform vec3 base : source_color = vec3(0.34, 0.47, 0.30);
uniform vec3 line_col : source_color = vec3(0.26, 0.37, 0.23);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float grid(vec2 p, float step, float w) {
	vec2 g = abs(fract(p / step - 0.5) - 0.5) * step;
	vec2 aa = fwidth(p) * 1.5;
	vec2 l = 1.0 - smoothstep(vec2(w) - aa, vec2(w) + aa, g);
	return max(l.x, l.y);
}
void fragment() {
	float g = max(grid(wpos.xz, 2.0, 0.03) * 0.5, grid(wpos.xz, 10.0, 0.06));
	ALBEDO = mix(base, line_col, g);
	ROUGHNESS = 0.95;
}
"""
	var gm := ShaderMaterial.new()
	gm.shader = sh
	ground.material_override = gm
	add_child(ground)

	# solid pillars and steps from the shared layout (the simulation collides with exactly these)
	var tint := RandomNumberGenerator.new()
	tint.seed = 7
	for b: WorldLayout.Box in WorldLayout.boxes():
		var pillar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(b.hx * 2.0, b.h, b.hz * 2.0)
		pillar.mesh = bm
		pillar.material_override = _mat(Color.from_hsv(tint.randf_range(0.05, 0.15), 0.25, tint.randf_range(0.55, 0.8)))
		pillar.position = Vector3(b.cx, b.h / 2.0, b.cz)
		add_child(pillar)

	cam = Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.05
	cam.far = 600.0
	cam.position = Vector3(0, 4, 8)
	add_child(cam)
	cam.make_current()


func _mat(c: Color, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


## A simple placeholder character: a body in the player's colour, a head, eyes facing forward (-Z), hands, and a
## contact shadow. The "model" node holds the meshes, so first person can hide your own.
func _make_avatar(id: int, info: Dictionary) -> Node3D:
	var root := Node3D.new()
	var model := Node3D.new()
	model.name = "model"
	root.add_child(model)
	var col: Color = info.get("color", Color.WHITE)
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.36
	cap.height = 1.25
	body.mesh = cap
	body.position.y = 0.72
	body.material_override = _mat(col)
	model.add_child(body)
	var head := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.27
	hs.height = 0.54
	head.mesh = hs
	head.position.y = 1.58
	head.material_override = _mat(Color("f1c9a5"))
	model.add_child(head)
	for sx in [-0.1, 0.1]:
		var eye := MeshInstance3D.new()
		var es := SphereMesh.new()
		es.radius = 0.05
		es.height = 0.1
		eye.mesh = es
		eye.position = Vector3(sx, 1.63, -0.24)
		eye.material_override = _mat(Color(0.08, 0.08, 0.1), 0.3)
		model.add_child(eye)
	for sx in [-0.46, 0.46]:
		var hand := MeshInstance3D.new()
		var hm := SphereMesh.new()
		hm.radius = 0.11
		hm.height = 0.22
		hand.mesh = hm
		hand.position = Vector3(sx, 0.85, -0.05)
		hand.material_override = _mat(col.darkened(0.25))
		model.add_child(hand)
	var blob := MeshInstance3D.new()  # a soft contact shadow, so height reads while jumping
	var disc := CylinderMesh.new()
	disc.top_radius = 0.45
	disc.bottom_radius = 0.45
	disc.height = 0.01
	blob.mesh = disc
	blob.name = "blob"
	var bmat := _mat(Color(0, 0, 0, 0.35))
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blob.material_override = bmat
	root.add_child(blob)
	var label := Label3D.new()
	label.text = str(info.get("name", "?"))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.15
	label.font_size = 48
	label.outline_size = 12
	label.no_depth_test = true
	label.visible = id != net.my_id
	root.add_child(label)
	add_child(root)
	return root


func _on_roster(r: Dictionary) -> void:
	if cam == null:
		return
	for id in avatars.keys():
		if not r.has(id):
			avatars[id].queue_free()
			avatars.erase(id)
	for id in r.keys():
		if not avatars.has(id):
			avatars[id] = _make_avatar(id, r[id])


# ================================================================ every frame: draw
func _process(_delta: float) -> void:
	if cam == null:
		return
	var frac := Engine.get_physics_interpolation_fraction()
	for id in avatars.keys():
		var av: Node3D = avatars[id]
		if id == net.my_id and net.predicted != null:
			av.position = net.own_draw_position(frac)
			av.rotation.y = cam_yaw
			(av.get_node("model") as Node3D).visible = view == View.THIRD
		else:
			var d := net.remote_draw(id, frac)
			if d.is_empty():
				av.visible = false
				continue
			av.visible = true
			av.position = d[0]
			av.rotation.y = d[1]
		# the contact shadow stays on the ground and shrinks with height
		var blob := av.get_node("blob") as Node3D
		blob.global_position = Vector3(av.position.x, 0.01, av.position.z)
		var k := clampf(1.0 - av.position.y / 6.0, 0.35, 1.0)
		blob.scale = Vector3(k, 1, k)

	var me := Vector3.ZERO
	if avatars.has(net.my_id):
		me = (avatars[net.my_id] as Node3D).position
	if view == View.FIRST:
		cam.position = me + Vector3(0, EYE_HEIGHT, 0)
		cam.rotation = Vector3(cam_pitch, cam_yaw, 0)
	else:
		var focus := me + Vector3(0, CAM_HEIGHT, 0)
		var back := Vector3(sin(cam_yaw) * cos(cam_pitch), -sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch))
		var dist := cam_dist
		var hit := WorldLayout.ray_hit(focus, back, cam_dist)  # pull in so a pillar never hides the player
		if hit < dist:
			dist = maxf(hit - 0.3, 0.6)
		var p := focus + back * dist
		p.y = maxf(p.y, 0.3)  # don't dip under the ground
		cam.position = p
		cam.look_at(focus, Vector3.UP)

	if hud:
		var dash := "ready"
		if net.predicted != null and net.predicted.dash_cd > 0:
			dash = "%.1f s" % (net.predicted.dash_cd * Config.DT)
		hud.text = "%s   players %d   ping %d ms   fps %d   view %s   dash %s   corrections %d" % [
			"HOST" if multiplayer.multiplayer_peer and multiplayer.is_server() else "CLIENT",
			net.roster.size(), net.ping_ms(), Engine.get_frames_per_second(),
			"1st person" if view == View.FIRST else "3rd person", dash, net.corrections]
		if host_info != "" and multiplayer.multiplayer_peer and multiplayer.is_server():
			hud.text += "\n\n" + host_info

	frames += 1
	if shot_path != "" and frames == shot_frame:
		get_viewport().get_texture().get_image().save_png(shot_path)
		print("screenshot saved: ", shot_path)
		get_tree().quit()


# ================================================================ controls
func _sample_input() -> Array:
	if bot:
		return _bot_input()
	var b := 0
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or menu == null or not menu.visible:
		if Input.is_physical_key_pressed(KEY_W): b |= Sim.Btn.FORWARD
		if Input.is_physical_key_pressed(KEY_S): b |= Sim.Btn.BACK
		if Input.is_physical_key_pressed(KEY_A): b |= Sim.Btn.LEFT
		if Input.is_physical_key_pressed(KEY_D): b |= Sim.Btn.RIGHT
		if Input.is_physical_key_pressed(KEY_SPACE): b |= Sim.Btn.JUMP
		if Input.is_physical_key_pressed(KEY_SHIFT): b |= Sim.Btn.SPRINT
		if Input.is_physical_key_pressed(KEY_Q): b |= Sim.Btn.DASH
	return [b, cam_yaw]


## Test player: walks in a slow circle, sprints, jumps and dashes on a timetable; logs what it sees every 2 s.
func _bot_input() -> Array:
	bot_t += 1
	cam_yaw = wrapf(bot_t * 0.01, -PI, PI)
	var b: int = Sim.Btn.FORWARD
	if (bot_t / 120) % 2 == 1: b |= Sim.Btn.SPRINT
	if bot_t % 90 == 45: b |= Sim.Btn.JUMP
	if bot_t % 150 == 100: b |= Sim.Btn.DASH
	if bot_t % 120 == 0 and net.predicted != null:
		print("[bot %s] tick %d  pos (%.1f, %.1f, %.1f)  sees %d players  ping %d ms  corrections %d" % [
			name_edit.text, net.latest_tick, net.predicted.pos.x, net.predicted.pos.y, net.predicted.pos.z,
			net.roster.size(), net.ping_ms(), net.corrections])
	return [b, cam_yaw]


func _unhandled_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	var mb := event as InputEventMouseButton
	var key := event as InputEventKey
	if mm and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw = wrapf(cam_yaw - mm.relative.x * MOUSE_SENS, -PI, PI)
		var lo := -1.45 if view == View.FIRST else -1.2
		var hi := 1.45 if view == View.FIRST else 0.5
		cam_pitch = clampf(cam_pitch - mm.relative.y * MOUSE_SENS, lo, hi)
	elif key and key.pressed and not key.echo and key.physical_keycode == KEY_V:
		view = View.FIRST if view == View.THIRD else View.THIRD
		cam_pitch = clampf(cam_pitch, -1.2, 0.5)
	elif mb and mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		cam_dist = clampf(cam_dist + (-0.6 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 0.6), 2.5, 14.0)
	elif mb and mb.pressed and menu and not menu.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ================================================================ menu and HUD
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(12, 8)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(hud)
	var help := Label.new()
	help.text = "WASD move   Shift sprint   Space jump   Q dash   V first/third person   wheel zoom   mouse look (click to capture, Esc to release)"
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	help.position = Vector2(12, -34)
	help.add_theme_color_override("font_outline_color", Color.BLACK)
	help.add_theme_constant_override("outline_size", 6)
	layer.add_child(help)
	var cross := Label.new()  # a crosshair, mostly for first person
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 22)
	cross.add_theme_color_override("font_outline_color", Color.BLACK)
	cross.add_theme_constant_override("outline_size", 4)
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	cross.grow_horizontal = Control.GROW_DIRECTION_BOTH
	cross.grow_vertical = Control.GROW_DIRECTION_BOTH
	layer.add_child(cross)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	layer.add_child(panel)
	menu = panel
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Multiplayer Game"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	name_edit = _field(box, "Your name", "Player")
	addr_edit = _field(box, "Server address (to join)", "127.0.0.1")
	port_edit = _field(box, "Port (UDP)", str(Config.DEFAULT_PORT))
	var row := HBoxContainer.new()
	box.add_child(row)
	for spec in [["Play solo / Host", _start_host], ["Join", _start_join]]:
		var btn := Button.new()
		btn.text = spec[0]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(spec[1])
		row.add_child(btn)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	status_label.text = "Host to play (friends can join you), or enter a host's address and Join."
	box.add_child(status_label)


func _field(box: VBoxContainer, label: String, value: String) -> LineEdit:
	var l := Label.new()
	l.text = label
	box.add_child(l)
	var e := LineEdit.new()
	e.text = value
	box.add_child(e)
	return e


func _start_host() -> void:
	var port := int(port_edit.text)
	var err := net.host(port, name_edit.text)
	if err != OK:
		status_label.text = "Could not host on port %d: %s" % [port, error_string(err)]
		return
	_print_addresses(port)
	_enter_game()


func _start_join() -> void:
	var err := net.join(addr_edit.text.strip_edges(), int(port_edit.text), name_edit.text)
	if err != OK:
		status_label.text = "Could not start: %s" % error_string(err)
		return
	_enter_game()


func _enter_game() -> void:
	menu.visible = false
	if not bot:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _print_addresses(port: int) -> void:
	var lines := ["Friends can join with one of these addresses, UDP port %d:" % port]
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			var kind := "Tailscale" if ip.begins_with("100.") else "same Wi-Fi / LAN"
			lines.append("  %s: %s" % [kind, ip])
	lines.append("  over the internet: your public IP, after forwarding UDP %d on the router (see README)" % port)
	print("\n".join(lines))
	host_info = "\n".join(lines)
