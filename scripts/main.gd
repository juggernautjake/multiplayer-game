## The game shell: start menu, the world (sky, light, a big open plane with landmarks), player avatars, a third-person
## camera and the controls. Networking and simulation live in Net / Sim.
##
## Command line (after `--`):  --server [--port 7777]   run a dedicated server with no window and no player
##                             --host / --join <address>  [--name <name>]   skip the menu
extends Node3D

const MOUSE_SENS := 0.0025
const CAM_DIST := 6.0
const CAM_HEIGHT := 1.6

var net: Net
var cam: Camera3D
var avatars := {}  # id -> Node3D
var cam_yaw := 0.0
var cam_pitch := -0.25
var menu: Control
var hud: Label
var status_label: Label
var name_edit: LineEdit
var addr_edit: LineEdit
var port_edit: LineEdit
var host_info := ""  # the addresses friends can join, shown under the HUD while hosting


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

	_build_world()
	_build_ui()
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

	# landmarks, so you can tell where you are and how fast you go (fixed positions: the same on every machine)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261104
	for i in 60:
		var pillar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var h := rng.randf_range(1.0, 7.0)
		bm.size = Vector3(rng.randf_range(0.8, 2.5), h, rng.randf_range(0.8, 2.5))
		pillar.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.from_hsv(rng.randf_range(0.05, 0.15), 0.25, rng.randf_range(0.55, 0.8))
		pillar.material_override = m
		var r := rng.randf_range(15.0, Config.WORLD_HALF - 10.0)
		var a := rng.randf() * TAU
		pillar.position = Vector3(cos(a) * r, h / 2.0, sin(a) * r)
		add_child(pillar)

	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 600.0
	cam.position = Vector3(0, 4, 8)
	add_child(cam)
	cam.make_current()


func _make_avatar(id: int, info: Dictionary) -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.4
	cap.height = 1.8
	body.mesh = cap
	body.position.y = 0.9
	var mat := StandardMaterial3D.new()
	mat.albedo_color = info.get("color", Color.WHITE)
	body.material_override = mat
	root.add_child(body)
	var nose := MeshInstance3D.new()  # shows which way the player faces
	var nb := BoxMesh.new()
	nb.size = Vector3(0.25, 0.18, 0.35)
	nose.mesh = nb
	nose.position = Vector3(0, 1.4, -0.42)
	var nm := StandardMaterial3D.new()
	nm.albedo_color = Color(0.1, 0.1, 0.1)
	nose.material_override = nm
	root.add_child(nose)
	var label := Label3D.new()
	label.text = str(info.get("name", "?"))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.25
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
		else:
			var d := net.remote_draw(id, frac)
			if d.is_empty():
				av.visible = false
				continue
			av.visible = true
			av.position = d[0]
			av.rotation.y = d[1]
	# third-person camera behind our player
	var focus := Vector3.ZERO
	if avatars.has(net.my_id):
		focus = (avatars[net.my_id] as Node3D).position + Vector3(0, CAM_HEIGHT, 0)
	var back := Vector3(sin(cam_yaw) * cos(cam_pitch), -sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch))
	cam.position = focus + back * CAM_DIST
	cam.look_at(focus, Vector3.UP)
	if hud:
		hud.text = "%s   players %d   ping %d ms   fps %d   tick %d" % [
			"HOST" if multiplayer.multiplayer_peer and multiplayer.is_server() else "CLIENT",
			net.roster.size(), net.ping_ms(), Engine.get_frames_per_second(), net.latest_tick]
		if host_info != "" and multiplayer.multiplayer_peer and multiplayer.is_server():
			hud.text += "\n\n" + host_info


# ================================================================ controls
func _sample_input() -> Array:
	var b := 0
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or menu == null or not menu.visible:
		if Input.is_physical_key_pressed(KEY_W): b |= Sim.Btn.FORWARD
		if Input.is_physical_key_pressed(KEY_S): b |= Sim.Btn.BACK
		if Input.is_physical_key_pressed(KEY_A): b |= Sim.Btn.LEFT
		if Input.is_physical_key_pressed(KEY_D): b |= Sim.Btn.RIGHT
		if Input.is_physical_key_pressed(KEY_SPACE): b |= Sim.Btn.JUMP
		if Input.is_physical_key_pressed(KEY_SHIFT): b |= Sim.Btn.SPRINT
	return [b, cam_yaw]


func _unhandled_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	var mb := event as InputEventMouseButton
	if mm and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw = wrapf(cam_yaw - mm.relative.x * MOUSE_SENS, -PI, PI)
		cam_pitch = clampf(cam_pitch - mm.relative.y * MOUSE_SENS, -1.2, 0.5)
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
	help.text = "WASD move   Shift sprint   Space jump   mouse look (click to capture, Esc to release)"
	help.position = Vector2(12, 32)
	help.add_theme_color_override("font_outline_color", Color.BLACK)
	help.add_theme_constant_override("outline_size", 6)
	layer.add_child(help)

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
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _print_addresses(port: int) -> void:
	var lines := ["Friends can join with one of these addresses, UDP port %d:" % port]
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			lines.append("  same Wi-Fi / LAN: %s" % ip)
	lines.append("  over the internet: your public IP, after forwarding UDP %d on the router (see README)" % port)
	print("\n".join(lines))
	host_info = "\n".join(lines)
