## The game shell: start menu, the world (sky, light, a big open plane with landmarks), player avatars, the camera
## (third person or first person, V to switch) and the controls. Networking and simulation live in Net / Sim.
##
## Command line (after `--`):  --server [--port 7777]   run a dedicated server with no window and no player
##                             --host / --join <address>  [--name <name>]   skip the menu
##                             --bot          a scripted player (walks, sprints, jumps, dashes) for testing
##                             --bot fight    a scripted player that walks to a practice dummy and uses every weapon on it
##                             --screenshot <file.png> [--shot-frame 240] [--view first]   save one frame and quit
extends Node3D

const MOUSE_SENS := 0.0025
const CAM_HEIGHT := 1.7   # third-person focus height
const EYE_HEIGHT := 1.82  # first-person eye height (the character's eyes)

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
var bot_mode := ""
var weapon_slot := 0
var aim_pitch := 0.0
var projs := {}            # server projectile id -> { node, kind, tick0, pos0, vel0, g, end_tick, end_pos, stuck, local_t0 }
var local_shots: Array = []  # our own shots drawn at once, waiting for the server's launch to give them an id
var dummies: Array = []    # Dummy nodes, index i = target id -(i+1)
var hud_weapons: Label
var hp_fill: ColorRect
var charge_fill: ColorRect
var shake := 0.0           # camera shake left (s), when our hit lands


func _ready() -> void:
	net = Net.new()
	net.name = "Net"
	add_child(net)
	net.input_source = _sample_input
	net.roster_changed.connect(_on_roster)
	net.status.connect(_on_status)
	net.projectile_spawned.connect(_on_proj_spawn)
	net.projectile_ended.connect(_on_proj_end)
	net.hit.connect(_on_hit)
	net.local_shot.connect(_on_local_shot)

	var args := _args()
	if args.has("server"):
		var port := int(args.get("port", Config.DEFAULT_PORT))
		var err := net.host(port, "", false)
		print("Dedicated server on UDP port %d: %s" % [port, "ok" if err == OK else error_string(err)])
		_print_addresses(port)
		return

	bot = args.has("bot")
	bot_mode = str(args["bot"]) if args.has("bot") and args["bot"] is String else ""
	shot_path = str(args.get("screenshot", ""))
	shot_frame = int(args.get("shot-frame", 240))
	if str(args.get("view", "")) == "first":
		view = View.FIRST
	_build_world()
	_build_ui()
	if args.has("name"):
		name_edit.text = str(args["name"])
	if args.has("netsim"):  # --netsim ping_ms,jitter_ms,loss_percent: test this client over a bad connection
		var p := str(args["netsim"]).split(",")
		net.sim_lat_ms = float(p[0])
		net.sim_jit_ms = float(p[1]) if p.size() > 1 else 0.0
		net.sim_loss = float(p[2]) / 100.0 if p.size() > 2 else 0.0
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

	for p: Vector3 in WorldLayout.DUMMIES:
		var d := Dummy.new()
		d.position = p
		add_child(d)
		dummies.append(d)

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


func _make_avatar(id: int, info: Dictionary) -> Avatar:
	var av := Avatar.new(str(info.get("name", "?")), info.get("color", Color.WHITE), id != net.my_id)
	add_child(av)
	return av


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
		var av: Avatar = avatars[id]
		if id == net.my_id and net.predicted != null:
			av.visible = true
			av.position = net.own_draw_position(frac)
			av.yaw = cam_yaw
			av.grounded = net.predicted.grounded
			av.dashing = net.predicted.dash_ticks > 0
			av.state = net.predicted
			av.model.visible = view == View.THIRD
		else:
			var d := net.remote_draw(id, frac)
			if d.is_empty():
				av.visible = false
				continue
			av.visible = true
			av.position = d[0]
			av.yaw = d[1]
			av.grounded = d[2]
			av.dashing = d[3]
			av.state = d[4]
		av.animate(_delta, cam)

	var me := Vector3.ZERO
	if avatars.has(net.my_id):
		me = (avatars[net.my_id] as Node3D).position
	if view == View.FIRST:
		cam.position = me + Vector3(0, EYE_HEIGHT, 0)
		cam.rotation = Vector3(cam_pitch, cam_yaw, 0)
	else:
		var focus := me + Vector3(0, CAM_HEIGHT, 0) + Vector3(cos(cam_yaw), 0, -sin(cam_yaw)) * 0.55  # over the right shoulder
		var back := Vector3(sin(cam_yaw) * cos(cam_pitch), -sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch))
		var dist := cam_dist
		var hit := WorldLayout.ray_hit(focus, back, cam_dist)  # pull in so a pillar never hides the player
		if hit < dist:
			dist = maxf(hit - 0.3, 0.6)
		var p := focus + back * dist
		p.y = maxf(p.y, 0.3)  # don't dip under the ground
		cam.position = p
		cam.look_at(focus, Vector3.UP)

	_update_projectiles(frac)
	if shake > 0.0:
		shake = maxf(shake - _delta, 0.0)
		cam.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * 0.07 * (shake / 0.14)
	if hud:
		_update_combat_hud()
		var dash := "ready"
		if net.predicted != null and net.predicted.dash_cd > 0:
			dash = "%.1f s" % (net.predicted.dash_cd * Config.DT)
		var extrap := 100.0 * net.extrap_frames / maxf(net.drawn_frames, 1.0)
		hud.text = "%s   players %d   ping %d ms   fps %d   view %s   dash %s\nnet: corrections %d   others drawn %d ms behind   guessed %.1f%%" % [
			"HOST" if multiplayer.multiplayer_peer and multiplayer.is_server() else "CLIENT",
			net.roster.size(), net.ping_ms(), Engine.get_frames_per_second(),
			"1st person" if view == View.FIRST else "3rd person", dash, net.corrections,
			int(net.interp_delay * Config.DT * 1000.0), extrap]
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
	_update_aim()
	var b := 0
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or menu == null or not menu.visible:
		if Input.is_physical_key_pressed(KEY_W): b |= Sim.Btn.FORWARD
		if Input.is_physical_key_pressed(KEY_S): b |= Sim.Btn.BACK
		if Input.is_physical_key_pressed(KEY_A): b |= Sim.Btn.LEFT
		if Input.is_physical_key_pressed(KEY_D): b |= Sim.Btn.RIGHT
		if Input.is_physical_key_pressed(KEY_SPACE): b |= Sim.Btn.JUMP
		if Input.is_physical_key_pressed(KEY_SHIFT): b |= Sim.Btn.SPRINT
		if Input.is_physical_key_pressed(KEY_Q): b |= Sim.Btn.DASH
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			b |= Sim.Btn.ATTACK
	return [b, cam_yaw, aim_pitch, weapon_slot]


## Aim where the crosshair points: find what the camera's centre ray hits (ground, a pillar, or 80 m away) and pitch
## the shot from the muzzle toward it.
func _update_aim() -> void:
	if cam == null or net.predicted == null:
		return
	var fwd := -cam.global_transform.basis.z
	var o := cam.global_position
	var t := 80.0
	if fwd.y < -0.001:
		t = minf(t, -o.y / fwd.y)
	t = minf(t, WorldLayout.ray_hit(o, fwd, t))
	var target := o + fwd * t
	var m := Weapons.muzzle(net.predicted.pos, cam_yaw)
	var flat := Vector2(target.x - m.x, target.z - m.z).length()
	aim_pitch = clampf(atan2(target.y - m.y, maxf(flat, 0.5)), -1.2, 1.2)


## Test player: walks in a slow circle, sprints, jumps and dashes on a timetable; logs what it sees every 2 s.
func _bot_input() -> Array:
	if bot_mode == "fight":
		return _bot_fight()
	bot_t += 1
	cam_yaw = wrapf(bot_t * 0.01, -PI, PI)
	var b: int = Sim.Btn.FORWARD
	if (bot_t / 120) % 2 == 1: b |= Sim.Btn.SPRINT
	if bot_t % 90 == 45: b |= Sim.Btn.JUMP
	if bot_t % 150 == 100: b |= Sim.Btn.DASH
	if bot_t % 120 == 0 and net.predicted != null:
		print("[bot %s] tick %d  pos (%.1f, %.1f, %.1f)  sees %d players  ping %d ms  corrections %d  others %d ms behind  guessed %.1f%%" % [
			name_edit.text, net.latest_tick, net.predicted.pos.x, net.predicted.pos.y, net.predicted.pos.z,
			net.roster.size(), net.ping_ms(), net.corrections, int(net.interp_delay * Config.DT * 1000.0),
			100.0 * net.extrap_frames / maxf(net.drawn_frames, 1.0)])
	return [b, cam_yaw, 0.0, weapon_slot]


## Fighting test bot: walk up to the middle dummy, then use each weapon on it for 6 s (club, sword from close up;
## bow and slingshot from 10 m back, drawn fully), logging every hit it sees.
func _bot_fight() -> Array:
	bot_t += 1
	weapon_slot = (bot_t / 360) % 4
	if net.predicted == null:
		return [0, cam_yaw, 0.0, weapon_slot]
	var target: Vector3 = WorldLayout.DUMMIES[1]
	var me := net.predicted.pos
	var to := target - me
	cam_yaw = atan2(-to.x, -to.z)
	var want := 1.6 if Weapons.is_melee(weapon_slot) else 10.0
	var b := 0
	var dist := Vector2(to.x, to.z).length()
	if dist > want + 0.4:
		b |= Sim.Btn.FORWARD
	elif dist < want - 0.4:
		b |= Sim.Btn.BACK
	var pitch := 0.0
	if Weapons.is_melee(weapon_slot):
		if dist < want + 0.8:
			b |= Sim.Btn.ATTACK
	else:
		var m := Weapons.muzzle(me, cam_yaw)
		var sd := Weapons.shot(weapon_slot, int(Weapons.get_data(weapon_slot).draw))
		var v := float(sd[0])
		var g := float(Weapons.get_data(weapon_slot).gravity)
		var dx := Vector2(target.x - m.x, target.z - m.z).length()
		var dy := target.y + 1.2 - m.y
		var disc := v * v * v * v - g * (g * dx * dx + 2.0 * dy * v * v)   # low-arc launch angle to hit the dummy
		pitch = atan((v * v - sqrt(maxf(disc, 0.0))) / (g * dx)) if dx > 0.1 else 0.0
		if (bot_t % 70) < 55 and absf(dist - want) < 1.5:
			b |= Sim.Btn.ATTACK   # hold to draw, then let go
	return [b, cam_yaw, pitch, weapon_slot]


func _unhandled_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	var mb := event as InputEventMouseButton
	var key := event as InputEventKey
	if mm and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw = wrapf(cam_yaw - mm.relative.x * MOUSE_SENS, -PI, PI)
		var lo := -1.45 if view == View.FIRST else -1.2
		var hi := 1.45 if view == View.FIRST else 0.5
		cam_pitch = clampf(cam_pitch - mm.relative.y * MOUSE_SENS, lo, hi)
	elif key and key.pressed and not key.echo and key.physical_keycode >= KEY_1 and key.physical_keycode <= KEY_4:
		weapon_slot = key.physical_keycode - KEY_1
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
	help.text = "WASD move   Shift sprint   Space jump   Q dash   left click attack (hold to draw a bow)   1-4 weapons   V first/third person   wheel zoom   Esc release mouse"
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	help.position = Vector2(12, -34)
	help.add_theme_color_override("font_outline_color", Color.BLACK)
	help.add_theme_constant_override("outline_size", 6)
	layer.add_child(help)
	hud_weapons = Label.new()
	hud_weapons.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hud_weapons.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud_weapons.position.y -= 92
	hud_weapons.add_theme_font_size_override("font_size", 20)
	hud_weapons.add_theme_color_override("font_outline_color", Color.BLACK)
	hud_weapons.add_theme_constant_override("outline_size", 6)
	layer.add_child(hud_weapons)
	var hp_back := ColorRect.new()
	hp_back.color = Color(0, 0, 0, 0.55)
	hp_back.size = Vector2(300, 16)
	hp_back.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hp_back.position = Vector2(-150, -60)
	layer.add_child(hp_back)
	hp_fill = ColorRect.new()
	hp_fill.color = Color(0.3, 0.85, 0.35)
	hp_fill.size = Vector2(296, 12)
	hp_fill.position = Vector2(2, 2)
	hp_back.add_child(hp_fill)
	charge_fill = ColorRect.new()  # bow / slingshot draw, under the crosshair
	charge_fill.color = Color(1, 0.85, 0.3)
	charge_fill.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	charge_fill.size = Vector2(0, 5)
	charge_fill.position = Vector2(-30, 22)
	layer.add_child(charge_fill)
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


# ================================================================ combat visuals
func _on_local_shot(kind: int, pos0: Vector3, vel0: Vector3, g: float) -> void:
	# our own shot, drawn from this instant on our own clock
	var e := { "node": _proj_node(kind), "kind": kind, "pos0": pos0, "vel0": vel0, "g": g, "local_t0": Engine.get_physics_frames(),
		"tick0": -1, "end_tick": -1, "end_pos": Vector3.ZERO, "stuck": false }
	add_child(e.node)
	local_shots.append(e)


func _on_proj_spawn(id: int, owner: int, kind: int, tick0: int, pos0: Vector3, vel0: Vector3, g: float) -> void:
	if owner == net.my_id and not local_shots.is_empty():
		var e: Dictionary = local_shots.pop_front()   # the server's copy of a shot we already drew: link them
		e.tick0 = tick0
		projs[id] = e
		return
	var n := { "node": _proj_node(kind), "kind": kind, "pos0": pos0, "vel0": vel0, "g": g, "local_t0": -1,
		"tick0": tick0, "end_tick": -1, "end_pos": Vector3.ZERO, "stuck": false }
	n.node.visible = false
	add_child(n.node)
	projs[id] = n


func _on_proj_end(id: int, tick: int, pos: Vector3, stuck: bool) -> void:
	if projs.has(id):
		var e: Dictionary = projs[id]
		e.end_tick = tick
		e.end_pos = pos
		e.stuck = stuck


func _proj_node(kind: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	if kind == 0:  # arrow: a thin shaft along -Z
		var bm := BoxMesh.new()
		bm.size = Vector3(0.035, 0.035, 0.75)
		mi.mesh = bm
		m.albedo_color = Color("b07840")
		var head := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(0.06, 0.06, 0.1)
		head.mesh = hm
		head.position.z = -0.4
		var hmat := StandardMaterial3D.new()
		hmat.albedo_color = Color("b8c2ce")
		head.material_override = hmat
		mi.add_child(head)
		var fl := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(0.12, 0.02, 0.12)
		fl.mesh = fm
		fl.position.z = 0.32
		var fmat := StandardMaterial3D.new()
		fmat.albedo_color = Color("d04040")
		fl.material_override = fmat
		mi.add_child(fl)
	else:  # stone
		var sm := SphereMesh.new()
		sm.radius = 0.07
		sm.height = 0.14
		mi.mesh = sm
		m.albedo_color = Color("8a8a92")
	mi.material_override = m
	return mi


## Every projectile follows its fixed path. Others' shots run on the same delayed clock as the players they came from
## (render_tick), our own on our own clock, so each lines up with the bow it left.
func _update_projectiles(frac: float) -> void:
	var now_local := Engine.get_physics_frames() + frac
	for list in [projs, local_shots]:
		var keys: Array = list.keys() if list is Dictionary else range(list.size())
		for k in keys:
			var e: Dictionary = list[k]
			var n: float
			if e.local_t0 >= 0:
				n = now_local - e.local_t0
			else:
				n = net.render_tick + frac - e.tick0
			var node: MeshInstance3D = e.node
			if n < 0.0:
				node.visible = false
				continue
			var ended: bool = e.end_tick >= 0 and n >= e.end_tick - e.tick0
			if ended:
				if not e.stuck or n > e.end_tick - e.tick0 + 180:   # stuck arrows stay 3 s
					node.queue_free()
					if list is Dictionary:
						list.erase(k)
					continue
				node.global_position = e.end_pos
				continue
			if n > 320:
				node.queue_free()
				if list is Dictionary:
					list.erase(k)
				continue
			node.visible = true
			var p := Weapons.proj_pos(e.pos0, e.vel0, e.g, n)
			var v := Weapons.proj_vel(e.vel0, e.g, n)
			node.global_position = p
			if v.length_squared() > 0.01:
				node.look_at(p + v, Vector3.UP if absf(v.normalized().y) < 0.99 else Vector3.RIGHT)


func _on_hit(target: int, amount: int, pos: Vector3, dir: Vector3, killed: bool, attacker: int) -> void:
	if cam == null:
		return
	var weapon := -1
	if avatars.has(attacker) and (avatars[attacker] as Avatar).state != null:
		weapon = (avatars[attacker] as Avatar).state.weapon
	if target < 0:
		var i := -target - 1
		if i < dummies.size():
			(dummies[i] as Dummy).hit(amount, dir)
		Fx.burst(self, pos, dir, Color("e2c27a"), 16, 4.5, 0.06)   # straw
	elif avatars.has(target):
		(avatars[target] as Avatar).flash()
		Fx.burst(self, pos, dir, Color("ffe6a0"), 12, 5.5, 0.05)   # sparks
	if weapon == Weapons.SWORD:
		Fx.burst(self, pos, dir, Color("dff2ff"), 8, 7.0, 0.04)
		Fx.word(self, pos, "Shing!", Color("bfe6ff"))
	elif weapon == Weapons.CLUB:
		Fx.word(self, pos, "Thock!" if not killed else "WHAM!", Color("ffb066"))
	if attacker == net.my_id:
		shake = 0.14
	# a damage number that floats up and fades
	var l := Label3D.new()
	l.text = ("%d" % amount) + ("  KO!" if killed else "")
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 64 if attacker == net.my_id else 44
	l.outline_size = 14
	l.modulate = Color("ffd34d") if attacker == net.my_id else (Color("ff5a5a") if target == net.my_id else Color.WHITE)
	add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.3, 0.3), 0.4, randf_range(-0.3, 0.3))
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position", l.global_position + Vector3(0, 1.1, 0), 0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


func _update_combat_hud() -> void:
	var st := net.predicted
	var names := []
	for i in Weapons.NAMES.size():
		names.append(("[%d %s]" if i == weapon_slot else " %d %s ") % [i + 1, Weapons.NAMES[i]])
	hud_weapons.text = "   ".join(names)
	if st == null:
		return
	hp_fill.size.x = 296.0 * float(st.hp) / float(Sim.MAX_HP)
	hp_fill.color = Color(0.9, 0.25, 0.2).lerp(Color(0.3, 0.85, 0.35), float(st.hp) / float(Sim.MAX_HP))
	var w := Weapons.get_data(st.weapon)
	charge_fill.size.x = 60.0 * float(st.charge) / float(w.draw) if w.kind == "ranged" else 0.0
	if st.dead > 0:
		hud_weapons.text = "Knocked out: back up in %.1f s" % (st.dead * Config.DT)
