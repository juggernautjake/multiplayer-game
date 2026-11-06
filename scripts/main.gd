## The game shell: start menu, the world (sky, light, a big open plane with landmarks), player avatars, the camera
## (third person or first person, V to switch) and the controls. Networking and simulation live in Net / Sim.
##
## Command line (after `--`):  --server [--port 7777]   run a dedicated server with no window and no player
##                             --host / --join <address>  [--name <name>]   skip the menu
##                             --bot          a scripted player (walks, sprints, jumps, dashes) for testing
##                             --bot fight    a scripted player that picks up every weapon, then uses each on a dummy
##                             --style pip|figure   (host) how everyone is drawn: Pip the sprite, or the 3D figure
##                             --screenshot <file.png> [--shot-frame 240] [--view first]   save one frame and quit
extends Node3D

const CAM_HEIGHT := 1.7   # third-person focus height
const EYE_HEIGHT := 1.82  # first-person eye height (the character's eyes)

enum View { THIRD, FIRST }

var net: Net
var cam: Camera3D
var avatars := {}  # id -> Node3D
var cam_yaw := 0.0
var cam_pitch := -0.25
var view := View.THIRD
var cam_dist := 4.6
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
var aim_yaw := 0.0
var face_yaw := 0.0   # where the body turns to attack: from the body's centre to what the crosshair is on
var cam_focus := Vector3.INF    # smoothed point the camera orbits
var cam_shoulder := 0.3
var projs := {}            # server projectile id -> { node, kind, tick0, pos0, vel0, g, end_tick, end_pos, stuck, local_t0 }
var local_shots: Array = []  # our own shots drawn at once, waiting for the server's launch to give them an id
var dummies: Array = []    # Dummy nodes, index i = target id -(i+1)
var hud_weapons: Label
var hp_fill: ColorRect
var charge_fill: ColorRect
var shake := 0.0           # camera shake left (s), when our hit lands
var items := {}            # item id -> { node, kind, pos }
var prompt: Label3D        # "E  pick up Sword" over the nearest weapon
var magic_fx: MagicFx      # spells' effects, shield bubbles, stuns
var golem_view: GolemView  # the wand's stone golems
var fog_view: FogView      # v0.12.0: the wand's fog clouds, who they hide and outline, the blindness inside
var spell_sel := {}        # weapon -> the spell picked for it (R cycles)
var aim_point := Vector3.ZERO   # what the crosshair is on (spells use it)
var mana_fill: ColorRect
var zap_back: ColorRect       # v0.11.0: Thunderhorn's Static build-up, over the health bar
var zap_fill: ColorRect
var zap_label: Label
var hud_spells: Label
var owned_seen := 1        # weapons we had last frame (a new one gets selected)
var char_pick: OptionButton
var mouse_sens := 0.0025     # radians per pixel (Esc menu)
var aiming := false          # right mouse held: zoomed aim
var attack_block_until := 0  # msec: the click that grabs the mouse doesn't also swing
var pause_menu: Control
var pause_char: OptionButton
var joining_until := 0     # msec: waiting for the host to answer a Join
var arena_view: ArenaView  # v0.10.0: the Duel Stone and the Storm Altar
var boss_view: BossView    # Thunderhorn
var cutscene_view: CutsceneView   # v0.12.3 the Duel Stone's corruption: the film (camera, letterbox, puppets, eyes)
var prize: PrizeScreen     # victory (the prize) and defeat screens
var audit := {}   # --log: counts of every replicated event this client received (network audit)
# v0.12.2 selection and orders (see "controls"): the spell hotbar, the radial wheels, taps and holds
const HOLD_MS := 220         # a key held this long opens its wheel; let go sooner: a tap
const HELP_LINE := "WASD move  Shift sprint  Space jump  Q dash  LMB attack / cast  RMB block  E use  V view  P PvP  Esc menu  F1 all controls  ` console\nWeapons: 1-7, mouse wheel, tap Tab last, hold Tab wheel     Spells (staff / wand): mouse wheel, R next, Shift+R back, hold R wheel, Ctrl+1-8     Golems: tap G follow / stay, hold G orders, middle mouse attack / go"
## Every control, for the F1 panel (and the Esc menu's Controls button). Keep in step with README "Controls".
const CONTROLS := [
	["Move", "WASD (relative to the camera); Shift sprint, Space jump, Q dash"],
	["Look / aim", "Mouse orbits the camera; drawing a bow or slingshot zooms in"],
	["Attack / cast", "Left mouse: swing (click again for the combo), hold to draw a bow or slingshot, hold to cast"],
	["Block", "Hold right mouse: brace behind your weapon, facing the crosshair (a slow walk, no attacking). Hits from the"],
	["", "front lose 65% with a sword, club or staff, 40% with fists, a bow, a slingshot or the wand; none from behind"],
	["Use", "E: pick up a weapon, open the vault, press the Duel Stone, eat fruit"],
	["Weapons", "1-7 fists, club, sword, bow, slingshot, staff, wand (the ones you have)"],
	["", "Mouse wheel (not holding the staff or wand): next / previous weapon     Tap Tab: back to the last weapon"],
	["", "Hold Tab: the weapon wheel (point with the mouse, let go of Tab or click to take it)"],
	["Spells", "(staff or wand in hand; the hotbar over your health shows them all)"],
	["", "Mouse wheel: next / previous spell     Tap R: next     Shift+R: previous     Ctrl+1-8: that spell"],
	["", "Hold R: the spell wheel (locked spells show the level that unlocks them)"],
	["Mastery", "Every spell levels up I -> II -> III from what it achieves (damage to enemies, health healed, metres"],
	["", "teleported, seconds stunned...; not on dummies): bigger, stronger, new tricks. Hotbar pips and bar show it"],
	["Golems", "Tap G: Follow me <-> Stay here     Middle mouse: attack the enemy under the crosshair, else go there"],
	["", "Hold G: the order wheel: Follow me, Stay here, Go there, Attack that, Regroup"],
	["Camera", "V first / third person     Ctrl + mouse wheel: camera distance"],
	["Game", "P PvP on / off     F2 Pip / 3D figure (host)     F1 this list     Esc menu"],
	["Dev console", "` (left of 1): type commands (host; help lists them): max, level staff max, give all, spawn sword 3 friendly"],
]
var spell_bar: SpellBar
var console: DevConsole   # v0.12.6 the dev console
var radial: RadialMenu
var wheel_kind := ""         # the wheel that's open: "weapon", "spell", "golem" or ""
var wheel_target := []       # the golem wheel: [id, position, name] of the enemy under the crosshair when it opened
var wheel_ground := Vector3.ZERO   # and the spot on the ground under it
var held := {}               # physical key -> msec it went down (Tab, R, G), until it comes up
var last_weapon := 0         # tap Tab: back to this one
var switch_label: Label      # "Fireball", "Sword", "Golems: Go there" under the crosshair for a moment
var controls_panel: Control  # F1: every control


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
	net.projectile_bounced.connect(_on_proj_bounce)
	net.item_added.connect(_on_item_added)
	net.item_removed.connect(_on_item_removed)
	net.style_changed.connect(_on_style)
	net.toast_msg.connect(func(text: String):
		if hud_spells:
			toast(text))
	if args_has_log():
		for sig in ["hit", "item_added", "item_removed", "projectile_spawned", "projectile_ended", "roster_changed"]:
			audit[sig] = 0
			net.connect(sig, func(a = null, b = null, c = null, d = null, e = null, f = null, g = null): audit[sig] += 1)
		net.eco.connect(_audit_eco)

	var args := _args()
	if args.has("server"):
		var port := int(args.get("port", Config.DEFAULT_PORT))
		net.persist = not args.has("no-save")   # v0.12.7: a dedicated server keeps everyone's progress too
		var err := net.host(port, "", false)
		net.style = "figure" if str(args.get("style", "pip")) == "figure" else "pip"
		print("Dedicated server v%s on UDP port %d: %s (look: %s)" % [Updater.running_version(), port, "ok" if err == OK else error_string(err), net.style])
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
	if args.has("style"):
		char_pick.select(1 if str(args["style"]) == "figure" else 0)
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
	if text.begins_with("The host is on v"):   # turned away for a different version: stop waiting, show why
		joining_until = 0
		if menu:
			menu.visible = true
		if updater:
			updater.check()
	if status_label:
		status_label.text = text
	if text.begins_with("Disconnected") and menu and not menu.visible and not last_join.is_empty() and not bot:
		# v0.12.7 the host went away mid-game (most likely restarting for an update): keep trying to rejoin for 90 s;
		# your progress is kept on the host's side and given back when you're in again
		reconnect_until = Time.get_ticks_msec() + 90000
		joining_until = Time.get_ticks_msec() + 2000
		toast("The host went away (restarting for an update?): reconnecting...")
	if menu and net.my_id == 0:  # the connection failed or dropped: back to the menu
		menu.visible = true
		host_info = ""
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func args_has_log() -> bool:
	return OS.get_cmdline_user_args().has("--log")


## Yard events (fruit, worms, birds) counted by kind and phase for the audit line.
func _audit_eco(kind: String, args: Array) -> void:
	var k := "eco:" + kind
	if (kind == "worm" or kind == "bird") and args.size() > 3:
		k += ":" + str(args[3])
	audit[k] = int(audit.get(k, 0)) + 1


## Network audit line: what this client has received so far, plus what it sees of everyone.
func _audit_print() -> void:
	if audit.is_empty():
		return
	var looks := ["look=" + net.style]
	var me := net.predicted
	print("[audit %s] %s  roster %s  hp %d owned %d arrows %d rocks %d corrections %d" % [name_edit.text, audit, looks,
		me.hp if me else -1, me.owned if me else -1, me.arrows if me else -1, me.rocks if me else -1, net.corrections])


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
		if b.kind == "vault":
			_build_vault(b)
			continue
		if b.kind == "duel":   # drawn by ArenaView
			continue
		var pillar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(b.hx * 2.0, b.h, b.hz * 2.0)
		pillar.mesh = bm
		pillar.material_override = _mat(Color.from_hsv(tint.randf_range(0.05, 0.15), 0.25, tint.randf_range(0.55, 0.8)))
		pillar.position = Vector3(b.cx, b.h / 2.0, b.cz)
		add_child(pillar)
		if b.kind == "step" or b.kind == "tower":   # the wizard's tower: blue-grey stone with a pale cap
			pillar.material_override = _mat(Color("6f7690") if b.kind == "tower" else Color("8a8fa6"))
			var cap := MeshInstance3D.new()
			var cm := BoxMesh.new()
			cm.size = Vector3(b.hx * 2.0 + 0.12, 0.14, b.hz * 2.0 + 0.12)
			cap.mesh = cm
			cap.material_override = _mat(Color("c9cde0"))
			cap.position = Vector3(b.cx, b.h - 0.07, b.cz)
			add_child(cap)

	_build_beacon()
	magic_fx = MagicFx.new()
	magic_fx.name = "Magic"
	add_child(magic_fx)
	magic_fx.setup(net, self)
	magic_fx._vault_door = vault_door
	golem_view = GolemView.new()
	golem_view.name = "Golems"
	add_child(golem_view)
	golem_view.setup(net, self)
	fog_view = FogView.new()
	fog_view.name = "Fog"
	add_child(fog_view)
	fog_view.setup(net, self)
	arena_view = ArenaView.new()
	arena_view.name = "Arena"
	add_child(arena_view)
	arena_view.setup(net, self)
	boss_view = BossView.new()
	boss_view.name = "Boss"
	add_child(boss_view)
	boss_view.setup(net, self, magic_fx)
	cutscene_view = CutsceneView.new()
	cutscene_view.name = "Cutscene"
	add_child(cutscene_view)
	cutscene_view.setup(net, self, boss_view)
	prize = PrizeScreen.new()
	prize.name = "Prize"
	add_child(prize)
	prize.setup(net)

	var eco := EcoView.new()   # trees, fruit, worms and birds, drawn from the server's events
	eco.name = "Eco"
	add_child(eco)
	eco.setup(net)

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


var _shown_names := {}   # v0.12.6: id -> the name its avatar was built with


## Each player is drawn as the look they chose: Pip (sprite) or the 3D figure. Both take the same inputs.
func _make_avatar(id: int, info: Dictionary) -> Node3D:
	var nm := str(info.get("name", "?"))
	var col: Color = info.get("color", Color.WHITE)
	var av: Node3D
	if net.style == "figure":
		av = FigureAvatar.new(nm, col, id != net.my_id, int(info.get("outfit", 0)))
	else:
		av = Avatar.new(nm, col, id != net.my_id, int(info.get("outfit", 0)))
	add_child(av)
	av.set_pvp(bool(info.get("pvp", false)))
	av.npc = id >= Fog.NPC_ID0   # v0.12.0: challengers' wizards show their mana
	return av


func _on_roster(r: Dictionary) -> void:
	if cam == null:
		return
	for id in avatars.keys():
		if not r.has(id):
			avatars[id].queue_free()
			avatars.erase(id)
	for id in r.keys():
		# v0.12.6: renamed (the dev console, or a player changing their name): build it again with the new name tag
		if avatars.has(id) and str(_shown_names.get(id, "")) != str(r[id].get("name", "?")):
			avatars[id].queue_free()
			avatars.erase(id)
		if not avatars.has(id):
			avatars[id] = _make_avatar(id, r[id])
			_shown_names[id] = str(r[id].get("name", "?"))
		avatars[id].set_pvp(bool(r[id].get("pvp", false)))
		var sz := clampf(float(r[id].get("size", 1.0)), 0.2, 5.0)   # v0.12.6: the dev console's size
		(avatars[id] as Node3D).scale = Vector3.ONE * sz


## The host changed the look: rebuild everyone's avatar.
func _on_style(s: String) -> void:
	if cam == null:
		return
	for id in avatars.keys():
		avatars[id].queue_free()
	avatars.clear()
	_on_roster(net.roster)
	if pause_char:
		pause_char.select(1 if s == "figure" else 0)


# ================================================================ every frame: draw
func _process(_delta: float) -> void:
	if cam == null:
		return
	_process_joining()
	var frac := Engine.get_physics_interpolation_fraction()
	if cutscene_view:
		cutscene_view.pre_avatars(avatars, _delta)   # v0.12.3: the minions' puppet poses, name tags hidden in the film
	for id in avatars.keys():
		var av = avatars[id]
		if id == net.my_id and net.predicted != null:
			av.visible = true
			av.position = net.own_draw_position(frac)
			av.yaw = net.predicted.yaw
			av.grounded = net.predicted.grounded
			av.dashing = net.predicted.dash_ticks > 0
			av.state = net.predicted
			if "aim_pitch" in av:
				av.aim_pitch = aim_pitch
			av.model.visible = view == View.THIRD or (cutscene_view != null and cutscene_view.showing())
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
	# zoomed aim (v0.12.5): while a bow or slingshot is drawn (the right mouse button blocks now)
	aiming = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and net.predicted != null and net.predicted.charge > 0
	cam.fov = lerpf(cam.fov, 46.0 if aiming else 70.0, clampf(_delta * 12.0, 0.0, 1.0))
	# the camera follows a smoothed focus point: steady, without lagging behind fast moves
	cam_focus = me if cam_focus == Vector3.INF else cam_focus.lerp(me, 1.0 - exp(-_delta * 18.0))
	if view == View.FIRST:
		cam.position = me + Vector3(0, EYE_HEIGHT, 0)
		cam.rotation = Vector3(cam_pitch, cam_yaw, 0)
	else:
		var shoulder := 0.6 if aiming or (net.predicted != null and net.predicted.charge > 0) else 0.3
		cam_shoulder = lerpf(cam_shoulder, shoulder, 1.0 - exp(-_delta * 10.0))
		var focus := cam_focus + Vector3(0, CAM_HEIGHT, 0) + Vector3(cos(cam_yaw), 0, -sin(cam_yaw)) * cam_shoulder
		var back := Vector3(sin(cam_yaw) * cos(cam_pitch), -sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch))
		var dist := cam_dist * (0.55 if aiming else 1.0)
		var hit := WorldLayout.ray_hit(focus, back, dist)  # pull in so a pillar never hides the player
		if hit < dist:
			dist = maxf(hit - 0.3, 0.6)
		var p := focus + back * dist
		p.y = maxf(p.y, 0.3)  # don't dip under the ground
		cam.position = p
		cam.look_at(focus, Vector3.UP)
		_chase_cam()
	if cutscene_view:   # v0.12.3: the film takes the camera, then eases it back to you
		cutscene_view.camera(cam, _delta)
		cutscene_view.post_avatars(avatars, _delta)

	_update_projectiles(frac)
	_update_items(_delta)
	_update_holds()
	if magic_fx:
		magic_fx.avatars = avatars
		var sts := {}
		for id in avatars.keys():
			sts[id] = avatars[id].state
		magic_fx.update(_delta, sts)
	if fog_view:
		fog_view.update(_delta, avatars, golem_view, cam)
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
		var ql := net.quality_line()
		if ql != "":
			hud.text += "\n" + ql
		hud.text += "\nPvP %s (P)" % ("ON: other PvP players can hurt you" if bool(net.roster.get(net.my_id, {}).get("pvp", false)) else "off: nobody can hurt you")
		if host_info != "" and multiplayer.multiplayer_peer and multiplayer.is_server():
			hud.text += "\n\n" + host_info

	frames += 1
	if _args().has("leave-at") and frames == int(_args()["leave-at"]):   # testing: press "Leave game"
		print("[leave] leaving at frame %d" % frames)
		_leave_game()
		return
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
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not (console and console.visible):   # (typing in the console: no moving)
		if Input.is_physical_key_pressed(KEY_W): b |= Sim.Btn.FORWARD
		if Input.is_physical_key_pressed(KEY_S): b |= Sim.Btn.BACK
		if Input.is_physical_key_pressed(KEY_A): b |= Sim.Btn.LEFT
		if Input.is_physical_key_pressed(KEY_D): b |= Sim.Btn.RIGHT
		if Input.is_physical_key_pressed(KEY_SPACE): b |= Sim.Btn.JUMP
		if Input.is_physical_key_pressed(KEY_SHIFT): b |= Sim.Btn.SPRINT
		if Input.is_physical_key_pressed(KEY_Q): b |= Sim.Btn.DASH
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Time.get_ticks_msec() > attack_block_until and not (radial and radial.visible):
			b |= Sim.Btn.ATTACK
		if Input.is_physical_key_pressed(KEY_E): b |= Sim.Btn.INTERACT
		if view == View.FIRST: b |= Sim.Btn.FACE_CAM
		# v0.12.5: the right mouse button braces behind your weapon (block); it used to aim (the bow and slingshot
		# now zoom in on their own while drawn)
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not (radial and radial.visible): b |= Sim.Btn.BLOCK
	return [b, cam_yaw, aim_pitch, weapon_slot, aim_yaw, face_yaw, int(spell_sel.get(weapon_slot, 0)), aim_point]


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
	var tp := _ray_people(o, fwd, t)
	var on_body := tp < t        # the crosshair is on a dummy or a player: face its centre, not the near side of it
	t = minf(t, tp)
	var target := o + fwd * t
	aim_point = target
	# the next position (the shot leaves after this tick's step): close enough at walking speed
	var m := Weapons.muzzle(net.predicted.pos, cam_yaw)
	var to := target - m
	var flat := Vector2(to.x, to.z).length()
	aim_yaw = atan2(-to.x, -to.z) if flat > 0.3 else cam_yaw   # straight at the crosshair point, from the bow
	# the body faces the crosshair point from its own centre. Only for a point in front of you along the camera heading
	# (looking down at the ground near your feet the point can be beside or behind you), and never more than 60 degrees
	# off the camera heading; otherwise just the camera heading
	var tb := (ray_hit_centre if on_body else target) - net.predicted.pos
	var fwd_flat := Vector2(-sin(cam_yaw), -cos(cam_yaw))
	var ahead := Vector2(tb.x, tb.z).dot(fwd_flat)
	if ahead > 0.12 and Vector2(tb.x, tb.z).length() < 40.0:
		var fy := atan2(-tb.x, -tb.z)
		face_yaw = wrapf(cam_yaw + clampf(wrapf(fy - cam_yaw, -PI, PI), -PI / 3.0, PI / 3.0), -PI, PI)
	else:
		face_yaw = cam_yaw
	# lift for gravity: the low arc that lands on the point at the speed the shot would leave at now
	var st := net.predicted
	var w := Weapons.get_data(st.weapon)
	var pitch := atan2(to.y, maxf(flat, 0.3))
	if w.kind == "ranged" and flat > 0.5:
		var v := float(Weapons.shot(st.weapon, maxi(st.charge, 1))[0])
		var g := float(w.gravity)
		var disc := v * v * v * v - g * (g * flat * flat + 2.0 * to.y * v * v)
		if disc >= 0.0:
			pitch = atan((v * v - sqrt(disc)) / (g * flat))
		else:
			pitch = PI / 4.0   # out of reach at this draw: throw it as far as it goes
	aim_pitch = clampf(pitch, -1.2, 1.2)


## Distance along a ray to the first practice dummy or other player it passes through (upright cylinders), or INF.
var ray_hit_centre := Vector3.ZERO   # the centre of the dummy / player _ray_people last hit

func _ray_people(o: Vector3, d: Vector3, max_t: float) -> float:
	var best := INF
	var cyls: Array = []
	for p: Vector3 in WorldLayout.DUMMIES:
		cyls.append(p)
	for id in avatars.keys():
		if id != net.my_id and avatars[id].visible:
			cyls.append(avatars[id].position)
	for c: Vector3 in cyls:
		var oc := Vector2(o.x - c.x, o.z - c.z)
		var dd := Vector2(d.x, d.z)
		var a := dd.dot(dd)
		if a < 1e-8:
			continue
		var b := 2.0 * oc.dot(dd)
		var cc := oc.dot(oc) - 0.45 * 0.45
		var disc := b * b - 4.0 * a * cc
		if disc < 0.0:
			continue
		var tt := (-b - sqrt(disc)) / (2.0 * a)
		if tt > 0.0 and tt < max_t:
			var y := o.y + d.y * tt
			if y > c.y and y < c.y + 1.9 and tt < best:
				best = tt
				ray_hit_centre = c
	return best


## Test player: walks in a slow circle, sprints, jumps and dashes on a timetable; logs what it sees every 2 s.
func _bot_input() -> Array:
	if bot_mode == "fight" or bot_mode == "aim":
		return _bot_fight()
	if bot_mode == "close":
		return _bot_close()
	if bot_mode == "magic":
		return _bot_magic()
	if bot_mode == "show":
		return _bot_show()
	if bot_mode == "duel":
		return _bot_duel()
	if bot_mode == "boss":
		return _bot_boss()
	if bot_mode == "prize":   # just the end screens: --bot prize [--defeat] [--no-prize-pic] --shots <dir> [--every N] [--ticks N]
		bot_t += 1
		if bot_t == 30:
			prize.start_defeat() if _args().has("defeat") else prize.start_victory()
		if bot_t % maxi(int(_args().get("every", 30)), 1) == 0 and _args().has("shots"):
			get_viewport().get_texture().get_image().save_png(str(_args()["shots"]).path_join("prize_%04d.png" % bot_t))
		if bot_t > int(_args().get("ticks", 1100)):
			get_tree().quit()
		return [0, cam_yaw, 0.0, weapon_slot]
	if bot_mode == "golems":
		return _bot_golems()
	if bot_mode == "ui":
		return _bot_ui()
	if bot_mode == "archery":
		return _bot_archery()
	if bot_mode == "console":
		return _bot_console()
	if bot_mode == "fog":
		return _bot_fog()
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
	return [b | Sim.Btn.FACE_CAM, cam_yaw, 0.0, weapon_slot]


## Magic test bot (--host --give-all --bot magic [--shots <dir>]): stands 6 m from the middle dummy and casts every
## staff spell (lightning, fireball twice, shield) and every wand spell (golem, teleport, stun) at it, logging what
## happens and saving pictures along the way.
func _bot_magic() -> Array:
	bot_t += 1
	if net.predicted == null:
		return [0, cam_yaw, 0.0, weapon_slot]
	var dummy: Vector3 = WorldLayout.DUMMIES[1]
	var me := net.predicted.pos
	var stand := dummy + Vector3(0, 0, 6.0)
	# v0.12.7 (with --mastery 1-3 for the spells' level): --foes puts two neutral units beside the dummy to hit (and
	# god mode on us), so the arcs, jumps, charms and bursts have someone to land on
	if bot_t == 30 and _args().has("foes") and net.players.has(net.my_id):
		print(DevCmd.run(net, net.my_id, "god on"))
		for k in 2:
			var q: Net.ServerPlayer = net.spawn_npc(net.players[net.my_id], Weapons.SWORD, 0)
			q.side = Net.Side.NEUTRAL
			q.dev = true
			q.state.pos = dummy + Vector3(-2.5 + 5.0 * k, 0, 1.0)
			q.ai = null
	if bot_t == 60 and _args().has("mastery-toast"):   # the level-up moment: the column and the toast
		print(DevCmd.run(net, net.my_id, "mastery fireball 3"))
	if _args().has("foes"):   # keep them standing where they were put (no brain: they just take it)
		for q: Net.ServerPlayer in net.players.values():
			if q.npc and q.ai == null:
				q.state.hp = maxi(q.state.hp, 40)
				q.state.dead = 0
	var b := 0
	var to := stand - me
	cam_yaw = atan2(-(dummy - me).x, -(dummy - me).z)
	if bot_t < 520 and Vector2(to.x, to.z).length() > 0.4:
		cam_yaw = atan2(-to.x, -to.z)
		b |= Sim.Btn.FORWARD
	_update_aim()
	var spell := 0
	var aim := dummy + Vector3(0, 1.0, 0)
	# [start tick, spell, ticks to hold the button]; level-2 spells only with --max-level
	var S := func(n: String) -> int: return Weapons.idx(Weapons.STAFF, n)
	var W := func(n: String) -> int: return Weapons.idx(Weapons.WAND, n)
	var plan := [[90, S.call("Lightning"), 3], [170, S.call("Fireball"), 3], [230, S.call("Fireball"), 3], [300, S.call("Shield"), 80],
		[400, S.call("Frost Nova"), 3], [480, W.call("Golem"), 3], [560, W.call("Fog"), 3], [640, W.call("Teleport"), 3],
		[720, W.call("Stun"), 3], [800, W.call("Spark Beam"), 3], [870, W.call("Life Drain"), 3]]
	weapon_slot = Weapons.STAFF if bot_t < 435 else Weapons.WAND
	if _args().has("plan2"):   # the level-3 spells: a meteor on the dummy, then a gravity well beside it
		plan = [[90, S.call("Meteor"), 3], [330, W.call("Gravity Well"), 3]]
		weapon_slot = Weapons.STAFF if bot_t < 300 else Weapons.WAND
	if _args().has("plan3"):   # the ultimates: an arcane storm over the dummies, then a stone titan beside them
		plan = [[90, S.call("Arcane Storm"), 3], [480, W.call("Stone Titan"), 3]]
		weapon_slot = Weapons.STAFF if bot_t < 450 else Weapons.WAND
	for p in plan:
		if bot_t >= p[0] and bot_t < p[0] + p[2]:
			b |= Sim.Btn.ATTACK
		if bot_t >= p[0] - 10:
			spell = p[1]
	if bot_t >= 470 and bot_t < 560 and not _args().has("plan2") and not _args().has("plan3"):
		aim = dummy + Vector3(0, 0, 2.5)
	elif bot_t >= 640 and bot_t < 720:
		aim = me + Vector3(7.0, 0, 0)
	if bot_t % 30 == 0:
		print("[magic] t%d fps %d %s spell %d mana %d shield %d recharge %s golems %d" % [bot_t, Engine.get_frames_per_second(), Weapons.NAMES[weapon_slot], net.predicted.spell,
			net.predicted.mana / 5, net.predicted.shield, str(net.predicted.recharge), golem_view.golems.size() if golem_view else -1])
	var shots := str(_args().get("shots", ""))
	if shots != "" and (bot_t in [104, 116, 140, 156, 166, 186, 196, 250, 340, 372, 380, 418, 440, 470, 520, 580, 600, 660, 700, 734, 760, 860] or (_args().has("every") and bot_t % 6 == 0)):
		get_viewport().get_texture().get_image().save_png(shots.path_join("magic_%d.png" % bot_t))
	if bot_t > 900:
		_audit_print()
		get_tree().quit()
	spell_sel[weapon_slot] = spell
	return [b, cam_yaw, 0.0, weapon_slot, aim_yaw, atan2(-(aim - me).x, -(aim - me).z), spell, aim]


## Showcase bot (--host --give-staff | --give-wand | --give-all --bot show --shots <dir> [--style figure]): shows the
## character from the front and the sides while it runs toward the camera, strafes, backpedals, dashes, jumps, swings
## the sword (a combo), casts with the staff and the wand and holds the shield, saving a picture every few frames, so
## the animation, the wizard garb's cloth and the effects can be checked by eye.
func _bot_show() -> Array:
	bot_t += 1
	if net.predicted == null:
		return [0, cam_yaw, 0.0, weapon_slot]
	var t := bot_t
	var b := 0
	var face := cam_yaw + PI   # toward the camera
	var spell := 0
	var me := net.predicted.pos
	var owned := net.predicted.owned
	var magic := Weapons.STAFF if (owned >> Weapons.STAFF) & 1 else Weapons.WAND
	if _args().has("cycle") and t >= 60:   # every weapon (so every costume) in turn, standing then walking; the camera circles
		var k := (t - 60) / 70
		if k >= 7 * 2:
			get_tree().quit()
			return [0, cam_yaw, 0.0, weapon_slot]
		weapon_slot = [Weapons.FISTS, Weapons.SWORD, Weapons.CLUB, Weapons.BOW, Weapons.SLING, Weapons.STAFF, Weapons.WAND][k % 7]
		cam_yaw = (t - 60) * 0.012
		cam_dist = 5.0
		_shot_show(t)
		return [Sim.Btn.FORWARD if k >= 7 and (t / 35) % 2 == 0 else 0, cam_yaw + (0.0 if k < 7 else PI), 0.0, weapon_slot]
	if _args().has("carry") and t >= 60:   # every weapon in turn, walking and standing, the camera circling
		var ws := [Weapons.SWORD, Weapons.CLUB, Weapons.BOW, Weapons.SLING, Weapons.STAFF, Weapons.WAND]
		var k := (t - 60) / 120
		if k >= ws.size():
			get_tree().quit()
			return [0, cam_yaw, 0.0, weapon_slot]
		weapon_slot = ws[k]
		cam_dist = 4.6   # the default play camera
		# 40 ticks each: walking away from the camera (his back to us), toward it, across it (side on), standing
		var ph := ((t - 60) % 120) / 40
		cam_yaw = 0.0
		_shot_show(t)
		match ph:
			0:
				return [Sim.Btn.FORWARD, cam_yaw, 0.0, weapon_slot]
			1:
				return [Sim.Btn.BACK, cam_yaw, 0.0, weapon_slot]
			_:
				return [Sim.Btn.RIGHT, cam_yaw, 0.0, weapon_slot]
	if _args().has("guard") and t >= 60:   # v0.12.5: braced with every weapon in turn, the camera going round
		var gs := [Weapons.FISTS, Weapons.SWORD, Weapons.CLUB, Weapons.BOW, Weapons.SLING, Weapons.STAFF, Weapons.WAND]
		var k := (t - 60) / 100
		if k >= gs.size():
			get_tree().quit()
			return [0, cam_yaw, 0.0, weapon_slot]
		weapon_slot = gs[k]
		cam_dist = 4.6
		cam_yaw = ((t - 60) % 100) / 100.0 * TAU
		var shots_g := str(_args().get("shots", ""))
		if shots_g != "" and (t - 60) % 100 in [30, 55, 80]:
			get_viewport().get_texture().get_image().save_png(shots_g.path_join("guard_%s_%02d.png" % [Weapons.NAMES[weapon_slot], (t - 60) % 100]))
		var fy := 0.0
		return [Sim.Btn.BLOCK if (t - 60) % 100 > 12 else 0, cam_yaw, 0.0, weapon_slot, fy, fy, 0, me + Vector3(0, 1, -8)]
	if t < 60:
		cam_yaw = 0.0
	elif t < 180 and _args().has("orbit"):   # standing still while the camera goes all the way round (front, side, back)
		cam_yaw = (t - 60) / 120.0 * TAU
		face = 0.0
		return [0, cam_yaw, 0.0, weapon_slot, face, face, spell, me + Vector3(0, 1, -8)] if _shot_show(t) else [0, cam_yaw, 0.0, weapon_slot]
	elif t < 180:                       # run toward the camera, sprinting
		b |= Sim.Btn.BACK | Sim.Btn.SPRINT
	elif t < 290:                       # strafe right then left, facing away (the camera on the side)
		cam_yaw = lerp_angle(cam_yaw, PI * 0.5, 0.05)
		b |= Sim.Btn.FACE_CAM | (Sim.Btn.RIGHT if t < 235 else Sim.Btn.LEFT)
		face = cam_yaw
	elif t < 360:                       # backpedal, then dash toward the camera
		cam_yaw = lerp_angle(cam_yaw, 0.0, 0.05)
		b |= Sim.Btn.BACK
		if t == 320 or t == 345:
			b |= Sim.Btn.DASH
	elif t < 430:                       # running jumps, seen from the side
		cam_yaw = lerp_angle(cam_yaw, -PI * 0.5, 0.06)
		b |= Sim.Btn.BACK
		if t == 372 or t == 405:
			b |= Sim.Btn.JUMP
	elif t < 520:                       # a sword combo, facing the camera
		cam_yaw = lerp_angle(cam_yaw, 0.0, 0.08)
		weapon_slot = Weapons.SWORD
		if t % 12 == 0:
			b |= Sim.Btn.ATTACK
	elif t < 900:                       # spells, facing the camera at an angle
		cam_yaw = lerp_angle(cam_yaw, 0.6, 0.03)
		weapon_slot = magic
		var plan := [[540, 1], [600, 0], [690, 2, 100], [820, 0]] if magic == Weapons.STAFF else [[540, Weapons.idx(Weapons.WAND, "Golem")], [640, Weapons.idx(Weapons.WAND, "Teleport")], [720, Weapons.idx(Weapons.WAND, "Stun")], [800, 0]]
		for p in plan:
			if t >= p[0] - 10:
				spell = p[1]
			if t >= p[0] and t < p[0] + (p[2] if p.size() > 2 else 3):
				b |= Sim.Btn.ATTACK
	else:
		_audit_print()
		get_tree().quit()
	var aim := me + Vector3(-sin(face), 0, -cos(face)) * 8.0 + Vector3(0, 1.0, 0)
	var shots := str(_args().get("shots", ""))
	if shots != "" and t > 60 and t % 6 == 0:
		get_viewport().get_texture().get_image().save_png(shots.path_join("show_%03d.png" % t))
	spell_sel[weapon_slot] = spell
	return [b, cam_yaw, 0.0, weapon_slot, face, face, spell, aim]


## v0.12.6 console bot (--host --bot console --shots <dir> [--style figure]): opens the dev console, types commands
## (max, levels, spawns on every side, a giant, a tiny one, rename), then closes it and watches the friendly and
## hostile units fight while the neutral one stands by. Pictures along the way.
func _bot_console() -> Array:
	bot_t += 1
	if net.predicted == null:
		return [0, cam_yaw, 0.0, weapon_slot]
	var lines := { 60: "help", 75: "max", 90: "level sword 2", 105: "spawn sword 2 friendly tier 3 level 4",
		120: "spawn club 2 hostile tier 2", 135: "spawn bow neutral name \"Steve the Bystander\"",
		150: "spawn mix 1 hostile size 2.5 name \"Big Bertha\"", 165: "size \"Steve\" 0.5", 180: "list" }
	if bot_t == 55:
		console.toggle()
	if lines.has(bot_t):
		console.edit.text = lines[bot_t]
		console._submit(lines[bot_t])
	if bot_t == 240:
		console.toggle()
	cam_yaw = PI + 0.4
	cam_dist = 9.0
	cam_pitch = -0.35
	var shots := str(_args().get("shots", ""))
	if shots != "" and bot_t in [100, 200, 236, 300, 400, 500, 600, 700]:
		get_viewport().get_texture().get_image().save_png(shots.path_join("console_%d.png" % bot_t))
	if bot_t > 720:
		var n := 0
		for p in net.players.values():
			if p.npc:
				print("[console] %s side %s size %.1f hp %d dead %d" % [p.name, Net.SIDE_NAMES[Net.side_of(p)], p.size, p.state.hp, p.state.dead])
				n += 1
		get_tree().quit()
	return [0, cam_yaw, 0.0, weapon_slot]


## Fog bot (v0.12.0; --host --give-all --max-level --bot fog --shots <dir> [--style figure]): a challenger's fog
## round you (you're blind in it), then walking out of it (thick smoke hiding the challenger inside), then your own
## fog with the challenger in it (faint for you, the challenger outlined, confused). Pictures along the way.
func _bot_fog() -> Array:
	bot_t += 1
	if net.predicted == null or not net.players.has(net.my_id):
		return [0, cam_yaw, 0.0, weapon_slot]
	var sp: Net.ServerPlayer = net.players[net.my_id]
	sp.state.hp = Sim.MAX_HP
	var me := net.predicted.pos
	var npc: Net.ServerPlayer = null
	for q: Net.ServerPlayer in net.players.values():
		if q.npc:
			npc = q
	if bot_t == 20 and npc == null:
		npc = net.spawn_npc(sp, Weapons.SWORD, 0)
	if npc != null and bot_t < 60:
		npc.state.pos = me + Vector3(0, 0, -5)
	if bot_t == 60 and npc != null:   # the challenger's fog, round us both
		var f := Fog.make(net.next_fog, me, npc.id, net.server_tick)
		net.next_fog += 1
		net.fogs.append(f)
		net._fx("fog", Fog.to_args(f))
	var b := 0
	weapon_slot = Weapons.WAND
	var spell := Weapons.idx(Weapons.WAND, "Spark Beam")
	cam_yaw = 0.0
	if bot_t >= 200 and bot_t < 330:   # walk out of it, then look back
		b |= Sim.Btn.BACK
	if bot_t >= 680 and npc != null and bot_t < 700:   # the challenger's fog is over: ours now
		npc.state.pos = me + Vector3(1.5, 0, -6)
	spell = Weapons.idx(Weapons.WAND, "Fog") if bot_t >= 690 else spell
	if bot_t >= 700 and bot_t < 703:
		b |= Sim.Btn.ATTACK
	var shots := str(_args().get("shots", ""))
	if shots != "" and bot_t in [50, 70, 90, 150, 260, 340, 380, 560, 640, 760, 820, 900, 960]:
		get_viewport().get_texture().get_image().save_png(shots.path_join("fog_%d.png" % bot_t))
	if bot_t > 1000:
		get_tree().quit()
	spell_sel[weapon_slot] = spell
	var aim := me + Vector3(0, 1.0, -8.0)
	return [b, cam_yaw, -0.15, weapon_slot, 0.0, 0.0, spell, aim]


## Golem-watching bot (--host --give-all --max-level --bot golems --shots <dir>): stands to one side of the dummies,
## summons a golem at them, then the stone titan, and watches from the side as they walk, leap and slam.
func _bot_golems() -> Array:
	bot_t += 1
	if net.predicted == null:
		return [0, cam_yaw, 0.0, weapon_slot]
	var dummy: Vector3 = WorldLayout.DUMMIES[1]
	var me := net.predicted.pos
	var stand := dummy + Vector3(0.0, 0, 7.5)
	var to := stand - me
	var b := 0
	if Vector2(to.x, to.z).length() > 0.5:
		b |= Sim.Btn.FORWARD
		cam_yaw = atan2(-to.x, -to.z)
	else:
		cam_yaw = lerp_angle(cam_yaw, atan2(-(dummy - me).x, -(dummy - me).z) + 0.5, 0.1)
	weapon_slot = Weapons.WAND
	var spell := Weapons.idx(Weapons.WAND, "Golem") if bot_t < 600 else Weapons.idx(Weapons.WAND, "Stone Titan")
	var aim := dummy + Vector3(-2.0, 0, 3.0)
	if bot_t == 150 and _args().has("rival"):   # v0.12.7: a hostile wand wizard too, so golems of two colours meet
		net.send_dev("god")
		net.send_dev("spawn wand hostile tier 3")
	if (bot_t >= 200 and bot_t < 203) or (bot_t >= 700 and bot_t < 703):
		b |= Sim.Btn.ATTACK
	var shots := str(_args().get("shots", ""))
	if shots != "" and bot_t > 200 and bot_t % 6 == 0:
		get_viewport().get_texture().get_image().save_png(shots.path_join("show_%03d.png" % (bot_t / 6)))
	if bot_t > 1300:
		get_tree().quit()
	spell_sel[weapon_slot] = spell
	return [b, cam_yaw, 0.0, weapon_slot, atan2(-(aim - me).x, -(aim - me).z), atan2(-(aim - me).x, -(aim - me).z), spell, aim]


## v0.12.2 UI pictures (--host --give-all --max-level --bot ui --shots <dir>): the staff's hotbar mid-cooldown, the
## wand's with recharges running, the spell wheel, the weapon wheel, the golem order wheel over the dummy, then an
## Attack that order (ring round the dummy, icons over the golems) and a Go there order (the marker on the ground).
func _bot_ui() -> Array:
	bot_t += 1
	if net.predicted == null:
		return [0, cam_yaw, 0.0, weapon_slot]
	var dummy: Vector3 = WorldLayout.DUMMIES[1]
	var me := net.predicted.pos
	var stand := dummy + Vector3(1.5, 0, 9.0)
	var to := stand - me
	var b := 0
	var face := atan2(-(dummy - me).x, -(dummy - me).z)
	if Vector2(to.x, to.z).length() > 0.5 and bot_t < 900:
		b |= Sim.Btn.FORWARD
		cam_yaw = atan2(-to.x, -to.z)
	elif bot_t < 560:
		cam_yaw = lerp_angle(cam_yaw, face, 0.2)
	else:   # the orders: looking down at the dummy from one side, further back
		cam_yaw = lerp_angle(cam_yaw, face + 0.55, 0.1)
		cam_dist = 8.0
	cam_pitch = -0.1 if bot_t < 560 else -0.42
	var shots := str(_args().get("shots", ""))
	var shot := func(nm: String):
		if shots != "":
			get_viewport().get_texture().get_image().save_png(shots.path_join(nm + ".png"))
			print("[ui] saved ", nm)
	var aim := dummy + Vector3(-1.5, 0, 2.5)
	if bot_t < 200:   # (the --give-all pick-up puts the wand in hand on the first frames)
		weapon_slot = Weapons.STAFF
	if bot_t == 100:
		spell_sel[Weapons.STAFF] = Weapons.idx(Weapons.STAFF, "Fireball")
	if bot_t >= 160 and bot_t < 163:
		b |= Sim.Btn.ATTACK
	if bot_t == 176:
		_pick_spell(Weapons.idx(Weapons.STAFF, "Meteor"))
	if bot_t == 182:
		shot.call("hotbar_staff")
	if bot_t == 200:
		_pick_weapon(Weapons.WAND)
		spell_sel[Weapons.WAND] = Weapons.idx(Weapons.WAND, "Golem")
	if bot_t >= 210 and bot_t < 213:
		b |= Sim.Btn.ATTACK
	if bot_t == 280:
		spell_sel[Weapons.WAND] = Weapons.idx(Weapons.WAND, "Stone Titan")
	if bot_t >= 285 and bot_t < 288:
		b |= Sim.Btn.ATTACK
	if bot_t == 370:
		spell_sel[Weapons.WAND] = Weapons.idx(Weapons.WAND, "Spark Beam")
	if bot_t >= 375 and bot_t < 378:
		b |= Sim.Btn.ATTACK
	if bot_t == 395:
		_pick_spell(Weapons.idx(Weapons.WAND, "Stun"))
	if bot_t == 400:
		shot.call("hotbar_wand")
	if bot_t == 420:
		_open_wheel(KEY_R)
		radial.point_at(Weapons.idx(Weapons.WAND, "Gravity Well"))
	if bot_t == 436:
		shot.call("wheel_spells")
	if bot_t == 440:
		_wheel_pick(wheel_kind, radial.close())
		wheel_kind = ""
	if bot_t == 460:
		_open_wheel(KEY_TAB)
		radial.point_at(Weapons.SWORD)
	if bot_t == 476:
		shot.call("wheel_weapons")
	if bot_t == 480:
		radial.close()
		wheel_kind = ""
	if bot_t == 520:
		_open_wheel(KEY_G)
		print("[ui] crosshair on ", wheel_target)
		radial.point_at(Golems.Order.ATTACK)
	if bot_t == 536:
		shot.call("wheel_golems")
	if bot_t == 540:
		_wheel_pick(wheel_kind, radial.close())
		wheel_kind = ""
	if bot_t == 600:
		shot.call("order_attack")
	if bot_t == 700:
		_golem_order(Golems.Order.GOTO, dummy + Vector3(-12.0, 0, 6.0))   # (clear of the dummies: HOLD_R)
	if bot_t == 712:
		shot.call("order_go_1")
	if bot_t == 880:
		shot.call("order_go_2")
	_bot_ui_keys()
	if bot_t > 1010:
		get_tree().quit()
	var sp := int(spell_sel.get(weapon_slot, 0))
	return [b, cam_yaw, -0.1, weapon_slot, atan2(-(aim - me).x, -(aim - me).z), face, sp, aim]


## The end of --bot ui: real key and mouse events through the input pipeline (Input.parse_input_event), checking the
## taps and holds: Ctrl+3 picks spell 3, the wheel steps the spell (a magic weapon in hand), a tap of Tab goes back, a tap of R steps the
## spell, Shift+R steps back, holding G opens the order wheel and letting go in the middle takes nothing.
var _ui_check := {}

func _bot_ui_keys() -> void:
	var key := func(code: int, down: bool, ctrl := false, shift := false):
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = down
		e.ctrl_pressed = ctrl
		e.shift_pressed = shift
		Input.parse_input_event(e)
	var say := func(ok: bool, what: String):
		print("[ui-check] %s  %s" % ["ok  " if ok else "FAIL", what])
	match bot_t:
		905:
			key.call(KEY_3, true, true)
			key.call(KEY_3, false, true)
		912:
			say.call(weapon_slot == Weapons.WAND and int(spell_sel.get(Weapons.WAND, -1)) == 2, "Ctrl+3 picks the wand's third spell (%d)" % int(spell_sel.get(Weapons.WAND, -1)))
			_ui_check["w"] = weapon_slot
			# a notch up, then (v0.12.7) a busy scroll: 4 down and 4 up, each with its release; net: one up
			var dn := MOUSE_BUTTON_WHEEL_DOWN
			var up := MOUSE_BUTTON_WHEEL_UP
			for bi in [up, dn, dn, dn, dn, up, up, up, up]:
				for down_e in [true, false]:
					var e := InputEventMouseButton.new()
					e.button_index = bi
					e.pressed = down_e
					Input.parse_input_event(e)
		920:
			# v0.12.5: with the staff or wand in hand the wheel steps the spell, not the weapon
			say.call(weapon_slot == Weapons.WAND and net.predicted.weapon == Weapons.WAND and int(spell_sel.get(Weapons.WAND, -1)) == 1,
				"9 notches of the mouse wheel step only the wand's spells (now %d), the wand stays in hand" % int(spell_sel.get(Weapons.WAND, -1)))
			key.call(KEY_TAB, true)
		924:
			key.call(KEY_TAB, false)
		932:
			say.call(weapon_slot != Weapons.WAND and not radial.visible, "a tap of Tab goes back to the last weapon (%s)" % Weapons.NAMES[weapon_slot])
			key.call(KEY_7, true)
			key.call(KEY_7, false)
			_ui_check["s"] = int(spell_sel.get(Weapons.WAND, 0))
			key.call(KEY_R, true)
		935:
			say.call(weapon_slot == Weapons.WAND, "7 takes the wand again (%s)" % Weapons.NAMES[weapon_slot])
			key.call(KEY_R, false)
		942:
			say.call(int(spell_sel.get(Weapons.WAND, 0)) == int(_ui_check["s"]) + 1, "a tap of R picks the next spell (%d)" % int(spell_sel.get(Weapons.WAND, 0)))
			key.call(KEY_R, true, false, true)
		945:
			key.call(KEY_R, false, false, true)
		952:
			say.call(int(spell_sel.get(Weapons.WAND, 0)) == int(_ui_check["s"]), "Shift+R steps back (%d)" % int(spell_sel.get(Weapons.WAND, 0)))
			_ui_check["o"] = net.golem_orders.get(net.my_id, [0])[0]
			key.call(KEY_G, true)
		980:
			say.call(radial.visible and wheel_kind == "golem", "holding G opens the order wheel")
			key.call(KEY_G, false)
		990:
			say.call(not radial.visible and net.golem_orders.get(net.my_id, [0])[0] == _ui_check["o"], "letting go in the middle takes nothing (order %d)" % net.golem_orders.get(net.my_id, [0])[0])
			key.call(KEY_G, true)
			key.call(KEY_G, false)
		1000:
			say.call(net.golem_orders.get(net.my_id, [0])[0] == Golems.Order.STAY, "a tap of G: Stay here (order %d)" % net.golem_orders.get(net.my_id, [0])[0])


## Duel bot (--host --give-all --bot duel --shots <dir>): walks to the Duel Stone and presses E (the real way), then
## meets one challenger of every kind in turn -- sword, club, bow, slingshot, then (after a level-up turns the stone's
## runes violet) staff and wand wizards -- for 7 s each, swinging its sword when they come close; both are kept on
## their feet until the end of each bout, then the challenger falls. Pictures through each fight.
func _bot_duel() -> Array:
	bot_t += 1
	if net.predicted == null or not net.players.has(net.my_id):
		return [0, cam_yaw, 0.0, weapon_slot]
	var shots := str(_args().get("shots", ""))
	var sp: Net.ServerPlayer = net.players[net.my_id]
	sp.state.hp = maxi(sp.state.hp, 40)
	var me := net.predicted.pos
	var stone := Vector3(WorldLayout.DUEL_C.x, 0, WorldLayout.DUEL_C.y)
	var order := [Weapons.SWORD, Weapons.CLUB, Weapons.BOW, Weapons.SLING, Weapons.STAFF, Weapons.WAND]
	weapon_slot = Weapons.SWORD
	var npc: Net.ServerPlayer = null
	for q: Net.ServerPlayer in net.players.values():
		if q.npc and q.state.dead == 0:
			npc = q
	var b := 0
	if bot_t < 240:   # walk to the stone and press E
		var to := stone + Vector3(0, 0, 1.6) - me
		if Vector2(to.x, to.z).length() > 0.4:
			b |= Sim.Btn.FORWARD
			cam_yaw = atan2(-to.x, -to.z)
		elif npc == null:
			b |= Sim.Btn.INTERACT
		if shots != "" and bot_t in [120, 200, 236]:
			get_viewport().get_texture().get_image().save_png(shots.path_join("duel_stone_%d.png" % bot_t))
		return [b, cam_yaw, -0.1, weapon_slot]
	var k := (bot_t - 240) / 420
	var t := (bot_t - 240) % 420
	if k >= order.size():
		get_tree().quit()
		return [0, cam_yaw, 0.0, weapon_slot]
	var w: int = order[k]
	if t == 0:
		for q: Net.ServerPlayer in net.players.values():
			if q.npc:
				net._damage(q.id, 9999, net.my_id, Vector3.FORWARD, 0.0)
		if w == Weapons.STAFF:
			sp.state.staff_lvl = 2   # the first level-up: the stone turns violet
	if t == 30:
		npc = net.spawn_npc(sp, w, 1)
	if npc != null and t < 400:
		npc.state.hp = maxi(npc.state.hp, 30)
	if t == 400 and npc != null:
		net._damage(npc.id, 9999, net.my_id, Vector3.FORWARD, 0.0)
	if npc != null:
		var to := npc.state.pos - me
		var d := Vector2(to.x, to.z).length()
		var face := atan2(-to.x, -to.z)
		cam_yaw = lerp_angle(cam_yaw, face + 0.6, 0.08)
		if d > 6.0 and w in [Weapons.BOW, Weapons.SLING, Weapons.STAFF, Weapons.WAND]:
			b |= Sim.Btn.FORWARD | Sim.Btn.FACE_CAM
		if d < 2.6 and bot_t % 40 < 4:
			b |= Sim.Btn.ATTACK
		if shots != "" and t in [80, 140, 200, 260, 320, 380]:
			get_viewport().get_texture().get_image().save_png(shots.path_join("duel_%d_%s_%d.png" % [k, Weapons.NAMES[w], t]))
		return [b, cam_yaw, -0.15, weapon_slot, face, face]
	return [b, cam_yaw, -0.15, weapon_slot]


## Boss bot (--host --give-all --bot boss --shots <dir> [--defeat]): reaches level 3 (the stone turns violet at 2, the
## altar rises at 3), walks to the Storm Altar and jumps on it; watches Thunderhorn come down and fight from the side
## of the arena, kept on its feet, casting at him now and then; takes him down to half (enraged) and a quarter (the
## storm), then beats him -- and pictures the victory and the prize. With --defeat it falls instead: the defeat screen,
## then a key, and the restart.
## v0.12.0 demo (--bot boss --leap --chase): through the Storm Leap the camera follows Thunderhorn from behind and
## above instead of our player, to watch the whole bound.
func _chase_cam() -> void:
	if bot_mode != "boss" or not _args().has("chase") or net.boss == null or boss_view == null or boss_view.root == null:
		return
	var b := net.boss
	if b.state not in [Boss.S.LEAP_WIND, Boss.S.LEAP, Boss.S.LEAP_LAND, Boss.S.HOWL]:
		return
	var at: Vector3 = boss_view.root.position
	var d := Vector3(b.leap_to.x - b.leap_from.x, 0, b.leap_to.z - b.leap_from.z)
	if b.state == Boss.S.LEAP_WIND:
		d = Vector3(b.leap_to.x - b.pos.x, 0, b.leap_to.z - b.pos.z)
	d = d.normalized() if d.length() > 0.1 else Vector3.FORWARD
	var side := d.cross(Vector3.UP)
	cam.position = at - d * 20.0 + side * 9.0 + Vector3(0, 7.0, 0)
	cam.look_at(at + d * 10.0 + Vector3(0, 3.0, 0), Vector3.UP)


func _bot_boss() -> Array:
	bot_t += 1
	if net.predicted == null or not net.players.has(net.my_id):
		return [0, cam_yaw, 0.0, weapon_slot]
	var shots := str(_args().get("shots", ""))
	var defeat := _args().has("defeat")
	var sp: Net.ServerPlayer = net.players[net.my_id]
	var me := net.predicted.pos
	var altar := Vector3(WorldLayout.ALTAR_C.x, 0, WorldLayout.ALTAR_C.y)
	weapon_slot = Weapons.STAFF
	if bot_t == 30:
		sp.state.staff_lvl = 2
	if bot_t == 60:
		sp.state.staff_lvl = 3
	var b := 0
	var snap := func(nm: String):
		if shots != "":
			get_viewport().get_texture().get_image().save_png(shots.path_join(nm + ".png"))
	if net.boss == null and not net.defeated and not boss_view.alive and not prize.visible and not has_meta("boss_t0"):
		if bot_t > 4000:
			get_tree().quit()
			return [0, cam_yaw, 0.0, weapon_slot]
		var to := altar - me
		var d := Vector2(to.x, to.z).length()
		if d > 0.6:
			b |= Sim.Btn.FORWARD | Sim.Btn.SPRINT
			cam_yaw = atan2(-to.x, -to.z)
		if d < 4.5 and bot_t % 40 == 0:
			b |= Sim.Btn.JUMP
		if bot_t % 60 == 0 and d < 30.0:
			snap.call("boss_approach_%04d" % bot_t)
		return [b, cam_yaw, -0.2, weapon_slot]
	var bt := bot_t - int(get_meta("boss_t0", bot_t))
	if not has_meta("boss_t0"):
		set_meta("boss_t0", bot_t)
	if prize.visible:   # the end screens
		if bt % 20 == 0:
			snap.call("boss_end_%04d_%s" % [bt, PrizeScreen.Mode.keys()[prize.mode]])
		if prize.mode == PrizeScreen.Mode.FIESTA and prize.t > 9.0:
			prize.close()
			get_tree().quit()
		if prize.mode == PrizeScreen.Mode.DEFEAT and prize.t > 4.0:
			var ev := InputEventKey.new()
			ev.keycode = KEY_SPACE
			ev.physical_keycode = KEY_SPACE
			ev.pressed = true
			Input.parse_input_event(ev)
		return [0, cam_yaw, 0.0, weapon_slot]
	if net.defeated:
		return [0, cam_yaw, 0.0, weapon_slot]
	var boss := net.boss
	if boss == null:
		if bt % 20 == 0:
			snap.call("boss_after_%04d" % bt)
		if bt > 1200:   # restarted (defeat run): a look two seconds later, done
			if not has_meta("restart_t"):
				set_meta("restart_t", bt)
			if bt == int(get_meta("restart_t")) + 120:
				snap.call("boss_restarted")
				get_tree().quit()
		return [0, cam_yaw, 0.0, weapon_slot]
	# keep our player standing (except a defeat run past the first 25 s)
	if not (defeat and bt > 1500):
		sp.state.hp = Sim.MAX_HP
	elif bt == 1501:
		net._damage(net.my_id, 9999, Boss.ID, Vector3.FORWARD, 0.0)
	# --leap (v0.11.0): Static on us, then a Storm Leap at once, pictures every 10 ticks, done after 25 s
	if _args().has("leap"):
		if bt in [250, 262, 274, 286]:
			net._boss_zap(net.my_id, 0, Vector3.FORWARD, false)
		if bt == 330:
			boss.last_leap = -100000
			boss._start_leap([[net.my_id, me, true, false, 100]])
		var every := int(_args().get("every", 10))   # v0.12.0 demo: --every, --from, --until
		if bt % every == 0 and bt > int(_args().get("from", 240)):
			snap.call("leap_%04d_%s" % [bt, Boss.S.keys()[boss.state]])
		if bt > int(_args().get("until", 1800)):
			get_tree().quit()
	# v0.12.3 --cutscene: he drops under 60% at once (after his entrance), the Duel Stone's corruption plays, then a short
	# fight with the minions round, then he dies (the minions collapse into smoke); --every N pictures, --until T quits
	var cut := _args().has("cutscene")
	if cut:
		if bt == int(_args().get("cut-at", 330)):
			boss.hp = int(boss.max_hp * 0.59)
		if boss.state != Boss.S.CUTSCENE and boss.cut_done:
			boss.hp = maxi(boss.hp, int(boss.max_hp * 0.52))
		if not has_meta("cut_frame") and boss.state == Boss.S.CUTSCENE:
			set_meta("cut_frame", frames)
			print("[bot] the cutscene starts at frame %d" % frames)
		if not has_meta("cut_end") and boss.cut_done and boss.state != Boss.S.CUTSCENE:
			set_meta("cut_end", bt)
			boss.leaps = Boss.LEAP_MAX   # (no Storm Leap carrying him off: the demo watches the minions come)
			print("[bot] the cutscene ends at frame %d" % frames)
		if has_meta("cut_end") and bt == int(get_meta("cut_end")) + int(_args().get("kill-after", 600)):
			net._damage(Boss.ID, 999999, net.my_id, Vector3.FORWARD, 0.0)
		var every := int(_args().get("every", 0))
		if every > 0 and bt % every == 0 and bt > 300:
			snap.call("cut_%04d_%s" % [bt, Boss.S.keys()[boss.state]])
		if bt > int(_args().get("until", 99999)):
			get_tree().quit()
	# his health, scripted: full for 30 s, then half (enraged) for 20 s, then a quarter (the storm) for 20 s, then done
	var floor_k := 1.0 if bt < 1800 else (0.45 if bt < 3000 else (0.2 if bt < 4200 else 0.0))
	if cut:
		floor_k = -1.0
	if floor_k > 0.0:
		boss.hp = maxi(boss.hp, int(boss.max_hp * floor_k)) if bt != 1800 and bt != 3000 else int(boss.max_hp * floor_k)
	elif bt == 4200:
		net._damage(Boss.ID, 999999, net.my_id, Vector3.FORWARD, 0.0)
	# keep 10-16 m from him, strafing round him, facing him, casting now and then
	var c := boss.pos
	var face := atan2(-(c - me).x, -(c - me).z)
	var dist := Vector2(c.x - me.x, c.z - me.z).length()
	if bt > 200:
		if dist > 16.0:
			b |= Sim.Btn.FORWARD
		elif dist < 10.0:
			b |= Sim.Btn.BACK
		b |= Sim.Btn.LEFT if (bt / 600) % 2 == 0 else Sim.Btn.RIGHT
	cam_yaw = lerp_angle(cam_yaw, face + 0.12, 0.15)
	cam_pitch = -0.12
	if bt > 300 and bt % 150 < 3:
		b |= Sim.Btn.ATTACK
	if bt % 15 == 0 and not _args().has("leap") and not cut:
		snap.call("boss_%04d_%s" % [bt, Boss.S.keys()[boss.state]])
	var aim := c + Vector3(0, 1.5, 0)
	spell_sel[weapon_slot] = 0
	return [b, cam_yaw, -0.12, weapon_slot, face, face, 0, aim]


func _shot_show(t: int) -> bool:
	var shots := str(_args().get("shots", ""))
	if shots != "" and t % 6 == 0:
		get_viewport().get_texture().get_image().save_png(shots.path_join("show_%03d.png" % t))
	return true


## Archery check (--host --give-all --bot archery --shots <dir> [--style figure] [--sling]): stands still facing one
## way and draws, holds and looses the bow (or the slingshot) again and again, aiming level, up and down, while the
## camera looks from behind, the side, the front and above; pictures at half draw, full draw, the release and rest.
func _bot_archery() -> Array:
	bot_t += 1
	if net.predicted == null:
		return [0, cam_yaw, 0.0, weapon_slot]
	weapon_slot = Weapons.SLING if _args().has("sling") else Weapons.BOW
	var cycle := bot_t / 150
	var t := bot_t % 150
	var views := [[0.0, -0.25], [PI * 0.5, -0.2], [PI, -0.2], [PI * 1.5, -0.2], [PI * 0.75, -1.1]]
	var pitches := [0.0, 0.45, -0.35]
	if cycle >= views.size() * pitches.size():
		get_tree().quit()
		return [0, cam_yaw, 0.0, weapon_slot]
	var v: Array = views[cycle % views.size()]
	var pitch: float = pitches[(cycle / views.size()) % pitches.size()]
	cam_yaw = float(v[0])
	cam_pitch = float(v[1])
	aim_pitch = pitch
	var b := Sim.Btn.ATTACK if t >= 20 and t < 80 else 0
	var shots := str(_args().get("shots", ""))
	if shots != "" and t in [40, 78, 86, 140]:
		get_viewport().get_texture().get_image().save_png(shots.path_join("arch_%02d_%s_%d.png" % [cycle, ["half", "full", "release", "rest"][[40, 78, 86, 140].find(t)], int(pitch * 100)]))
	return [b, cam_yaw, pitch, weapon_slot, 0.0, 0.0]


## Close-quarters test bot (--bot close [--shots <dir>]): picks up every weapon, then for each one walks into the
## middle dummy and then into a pillar, pressing forward the whole time (as close as you can get), keeps the crosshair
## on the target like a player would, and attacks: clicks, then holds attack (bows: draws and lets go). Every 6 ticks it
## logs how far the body is turned from the target and from the camera; at the end, the worst angle per weapon.
var close_t := 0
var close_worst := {}
var close_pillar := Vector3.ZERO
var close_locked := false

func _bot_close() -> Array:
	if net.predicted == null or net.predicted.owned != 0b11111 or net.predicted.arrows == 0 or net.predicted.rocks == 0:
		if close_t == 0:
			return _bot_fight()
	close_t += 1
	var phase := close_t / 420               # 7 s per weapon and target
	var weapons := [Weapons.FISTS, Weapons.CLUB, Weapons.SWORD, Weapons.BOW, Weapons.SLING]
	if phase >= weapons.size() * 2:
		if close_t == weapons.size() * 2 * 420 + 1:
			print("[close] worst body angle once at the target (degrees from the target / from the camera):")
			for k in close_worst:
				print("[close]   %-22s target %5.1f   camera %5.1f" % [k, close_worst[k][0], close_worst[k][1]])
			get_tree().quit()
		return [0, cam_yaw, 0.0, weapon_slot]
	weapon_slot = weapons[phase / 2]
	var at_pillar := phase % 2 == 1
	var me := net.predicted.pos
	var target: Vector3 = WorldLayout.DUMMIES[1] + Vector3(0, 1.2, 0)
	if at_pillar:   # the middle of the nearest tall pillar's nearest face, chosen once, at chest height
		if close_t % 420 == 1 or close_pillar == Vector3.ZERO:
			var best := INF
			for bx: WorldLayout.Box in WorldLayout.boxes():
				if bx.h < 1.5:
					continue
				var p := Vector3(clampf(me.x, bx.cx - bx.hx, bx.cx + bx.hx), 1.2, clampf(me.z, bx.cz - bx.hz, bx.cz + bx.hz))
				if p.distance_to(me) < best:
					best = p.distance_to(me)
					var fx := absf(p.x - bx.cx) >= bx.hx - 0.001
					close_pillar = Vector3(p.x, 1.2, bx.cz) if fx else Vector3(bx.cx, 1.2, p.z)
		target = close_pillar
	# put the crosshair on the target: the camera's forward ray through it (the camera sits over the shoulder)
	var o := cam.global_position if cam else me + Vector3(0, 1.6, 0)
	var tc := target - o
	var touching := Vector2(target.x - me.x, target.z - me.z).length() < (Sim.RADIUS + 0.08 if at_pillar else Sim.RADIUS + Sim.DUMMY_RADIUS + 0.08)
	if close_t % 420 < 2:
		close_locked = false
	if not close_locked:   # aim the mouse until touching, then hold it still like a person would
		cam_yaw = atan2(-tc.x, -tc.z)
		close_locked = touching and close_t % 420 > 60
	_update_aim()
	var t := close_t % 420
	var touch := (Vector2(target.x - me.x, target.z - me.z).length() < (Sim.RADIUS + 0.08 if at_pillar else Sim.RADIUS + Sim.DUMMY_RADIUS + 0.08))
	var b := Sim.Btn.FORWARD if t < 400 and not touch else 0   # walk in until touching: as close as the collision allows
	var ranged := not Weapons.is_melee(weapon_slot)
	if t > 90:
		if ranged:
			if (t / 60) % 2 == 0: b |= Sim.Btn.ATTACK   # draw 1 s, let go, again
		elif t < 250:
			if t % 14 == 0: b |= Sim.Btn.ATTACK         # clicks: the combo
		else:
			b |= Sim.Btn.ATTACK                          # held down
	var to := target - me
	var flat := Vector2(to.x, to.z)
	var want := atan2(-to.x, -to.z)
	var e_t := rad_to_deg(absf(wrapf(net.predicted.yaw - want, -PI, PI)))
	var e_c := rad_to_deg(absf(wrapf(net.predicted.yaw - cam_yaw, -PI, PI)))
	var key := "%s at %s" % [Weapons.NAMES[weapon_slot], "pillar" if at_pillar else "dummy"]
	if t > 150:   # arrived and attacking
		var wv: Array = close_worst.get(key, [0.0, 0.0])
		close_worst[key] = [maxf(wv[0], e_t), maxf(wv[1], e_c)]
	if t % 6 == 0:
		print("[close] %-18s t%3d dist %.2f  body vs target %5.1f  vs camera %5.1f  atk %d" % [key, t, flat.length(), e_t, e_c, net.predicted.atk])
	var shots := str(_args().get("shots", ""))
	if shots != "" and t in [200, 300, 360]:
		get_viewport().get_texture().get_image().save_png(shots.path_join("%s_%d.png" % [key.replace(" ", "_"), t]))
	return [b, cam_yaw, 0.0, weapon_slot, aim_yaw, face_yaw]


## Fighting test bot: walk up to the middle dummy, then use each weapon on it for 6 s (club, sword from close up;
## bow and slingshot from 10 m back, drawn fully), logging every hit it sees.
func _bot_fight() -> Array:
	bot_t += 1
	if bot_t % 600 == 0:
		_audit_print()
	if bot_t == 1500 and multiplayer.is_server():   # host test: switch the look mid-game for everyone
		_switch_character()
	if net.predicted == null:
		return [0, cam_yaw, 0.0, weapon_slot]
	# first walk to every weapon and ammo spawn and pick it up
	if net.predicted.owned != 0b11111 or net.predicted.arrows == 0 or net.predicted.rocks == 0:
		for s in WorldLayout.ITEM_SPAWNS:
			var k := int(s[0])
			var need: bool = (k <= 3 and not (net.predicted.owned >> (k + 1)) & 1) or (k == 4 and net.predicted.arrows == 0) or (k == 5 and net.predicted.rocks == 0)
			if not need:
				continue
			var to: Vector3 = s[1] - net.predicted.pos
			cam_yaw = atan2(-to.x, -to.z)
			var bb := Sim.Btn.FORWARD if Vector2(to.x, to.z).length() > 0.6 else 0
			if bot_t % 2 == 0:
				bb |= Sim.Btn.INTERACT
			return [bb, cam_yaw, 0.0, weapon_slot]
	weapon_slot = (bot_t / 360) % 5
	if bot_mode == "aim":
		weapon_slot = Weapons.BOW if (bot_t / 1440) % 2 == 0 else Weapons.SLING
	var target: Vector3 = WorldLayout.DUMMIES[1]
	var me := net.predicted.pos
	var to := target - me
	if bot_mode != "aim":
		cam_yaw = atan2(-to.x, -to.z)
	elif bot_t % 720 == 1:
		cam_yaw = atan2(-to.x, -to.z)   # rough start; the crosshair steering does the rest
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
	elif bot_mode == "aim":
		# play it like a person: put the crosshair on the dummy's chest, draw, let go (tests that shots go where the
		# crosshair is). Alternates 10 m and 22 m every 12 s.
		want = 10.0 if (bot_t / 720) % 2 == 0 else 22.0
		b = 0
		if dist > want + 0.4:
			b |= Sim.Btn.FORWARD
		elif dist < want - 0.4:
			b |= Sim.Btn.BACK
		if cam:
			var sp := cam.unproject_position(target + Vector3(0, 1.3, 0))
			var c := get_viewport().get_visible_rect().size / 2.0
			cam_yaw -= (sp.x - c.x) * 0.0015
			cam_pitch = clampf(cam_pitch - (sp.y - c.y) * 0.0015, -1.2, 0.5)
		_update_aim()
		pitch = aim_pitch
		if (bot_t % 70) < 55 and absf(dist - want) < 1.0:
			b |= Sim.Btn.ATTACK
		return [b | Sim.Btn.FACE_CAM, cam_yaw, pitch, weapon_slot, aim_yaw, face_yaw]
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
	return [b | Sim.Btn.FACE_CAM, cam_yaw, pitch, weapon_slot]


func _unhandled_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	var mb := event as InputEventMouseButton
	var key := event as InputEventKey
	var down := key != null and key.pressed and not key.echo
	var code := key.physical_keycode if key else KEY_NONE
	if mm and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if radial and radial.visible:   # a wheel is open: the mouse points at its options, the camera stays put
			radial.push(mm.relative)
			return
		var sens := mouse_sens * (0.55 if aiming else 1.0)
		cam_yaw = wrapf(cam_yaw - mm.relative.x * sens, -PI, PI)
		var lo := -1.45 if view == View.FIRST else -1.25
		var hi := 1.45 if view == View.FIRST else 0.85
		cam_pitch = clampf(cam_pitch - mm.relative.y * sens, lo, hi)
	elif key and not key.pressed and held.has(code):   # Tab / R / G let go: a tap, or take what the wheel points at
		_key_up(code)
	elif down and (code == KEY_TAB or code == KEY_R or code == KEY_G) and _playing():
		if not held.has(code):
			held[code] = Time.get_ticks_msec()
			if code == KEY_R:
				held["shift"] = key.shift_pressed
	elif down and code == KEY_F1:
		if controls_panel:
			controls_panel.visible = not controls_panel.visible
	elif down and code == KEY_F2:
		_switch_character()
	elif down and code == KEY_F9 and update_ready:   # v0.12.7: restart into the downloaded update, straight back in
		_restart_for_update()
	elif down and code == KEY_P and menu and not menu.visible:
		net.request_pvp(not bool(net.roster.get(net.my_id, {}).get("pvp", false)))
	elif down and key.ctrl_pressed and code >= KEY_1 and code <= KEY_9 and _playing():   # Ctrl+number: that spell
		if Weapons.is_magic(weapon_slot):
			_pick_spell(code - KEY_1)
		else:
			_flash_msg("Ctrl+number picks a spell: take the staff (6) or the wand (7)", Color("c9c9d6"))
	elif down and code >= KEY_1 and code <= KEY_7 and _playing():
		var want := code - KEY_1
		if (net.predicted.owned >> want) & 1:
			_pick_weapon(want)
		else:
			_flash_msg("No %s yet" % Weapons.NAMES[want].to_lower(), Color("c9c9d6"))
	elif down and code == KEY_V:
		view = View.FIRST if view == View.THIRD else View.THIRD
		cam_pitch = clampf(cam_pitch, -1.2, 0.5)
	elif mb and mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var step := -1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1
		if radial and radial.visible:
			pass
		elif mb.ctrl_pressed or not _playing():   # Ctrl + wheel: camera distance
			cam_dist = clampf(cam_dist + 0.6 * step, 2.5, 14.0)
		elif _magic_in_hand() >= 0:   # v0.12.5: staff or wand in hand: the wheel picks the spell, never the weapon
			_step_spell(step, _magic_in_hand())
		else:
			_cycle_weapon(step)
	elif mb and mb.pressed and mb.button_index == MOUSE_BUTTON_MIDDLE and _playing() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_smart_order()
	elif mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and radial and radial.visible:
		attack_block_until = Time.get_ticks_msec() + 300   # a click takes what the wheel points at (no swing)
		for k in held.keys():
			if k is int:
				_key_up(k)
				break
	elif mb and mb.pressed and menu and not menu.visible and not pause_menu.visible and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			and not (console and console.visible):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		attack_block_until = Time.get_ticks_msec() + 250
	elif event.is_action_pressed("ui_cancel") and menu and not menu.visible:
		if radial and radial.visible:   # Esc closes a wheel without picking
			radial.close()
			wheel_kind = ""
			held.clear()
			return
		if controls_panel and controls_panel.visible:
			controls_panel.visible = false
			return
		_set_paused(not pause_menu.visible)


# ================================================================ v0.12.2 controls: weapons, spells, golem orders
## Weapons: 1-7, the mouse wheel (owned ones, in turn), tap Tab = the last one, hold Tab = the weapon wheel.
## Spells (staff / wand in hand): Ctrl+1-8, tap R = next, Shift+R = back, right mouse + wheel, hold R = the spell
## wheel. Golems: tap G = Follow <-> Stay, hold G = the order wheel, middle mouse = attack what's under the crosshair
## (or go to the spot). Every pick shows its name under the crosshair for a moment. The pick is part of every input
## (weapon, spell) or a request to the server (orders), so everyone sees the same.
func _playing() -> bool:
	return net.predicted != null and menu != null and not menu.visible and pause_menu != null and not pause_menu.visible


## Tab / R / G held long enough: open its wheel.
func _update_holds() -> void:
	if radial == null or held.is_empty() or radial.visible:
		return
	var now := Time.get_ticks_msec()
	for code in [KEY_TAB, KEY_R, KEY_G]:
		if held.has(code) and now - int(held[code]) >= HOLD_MS:
			_open_wheel(code)
			return


func _key_up(code: int) -> void:
	var was_held := held.has(code)
	var shift := bool(held.get("shift", false))
	held.erase(code)
	held.erase("shift")
	if not was_held:
		return
	if radial and radial.visible:
		var kind := wheel_kind
		wheel_kind = ""
		var pick := radial.close()
		if pick >= 0:
			_wheel_pick(kind, pick)
		return
	if not _playing():
		return
	match code:   # a tap
		KEY_TAB:
			if last_weapon != weapon_slot and (net.predicted.owned >> last_weapon) & 1:
				_pick_weapon(last_weapon)
			else:
				_cycle_weapon(1)
		KEY_R:
			if Weapons.is_magic(weapon_slot):
				_step_spell(-1 if shift else 1)
			else:
				_flash_msg("R picks a spell: take the staff (6) or the wand (7)", Color("c9c9d6"))
		KEY_G:
			var mode: int = (net.golem_orders.get(net.my_id, [Golems.Order.FOLLOW]) as Array)[0]
			_golem_order(Golems.Order.FOLLOW if mode == Golems.Order.STAY else Golems.Order.STAY)


func _pick_weapon(w: int, quiet := false) -> void:
	if w == weapon_slot:
		return
	last_weapon = weapon_slot
	weapon_slot = w
	if not quiet:
		var extra := ""
		if Weapons.is_magic(w):
			var sp := Weapons.spell(w, int(spell_sel.get(w, 0)))
			extra = "  (%s)" % sp.name
		_flash_msg(Weapons.NAMES[w] + extra, Color("fff2a8"))


## The next owned weapon up (+1) or down (-1) the list, round the end.
func _cycle_weapon(step: int) -> void:
	if net.predicted == null:
		return
	var n := Weapons.NAMES.size()
	for k in range(1, n):
		var w := posmod(weapon_slot + step * k, n)
		if (net.predicted.owned >> w) & 1:
			_pick_weapon(w)
			return


func _spell_level() -> int:
	if net.predicted == null:
		return 1
	return net.predicted.staff_lvl if weapon_slot == Weapons.STAFF else net.predicted.wand_lvl


func _pick_spell(i: int) -> void:
	var spells: Array = Weapons.get_data(weapon_slot).spells
	if i < 0 or i >= spells.size():
		return
	var sp: Dictionary = spells[i]
	if not Weapons.unlocked(weapon_slot, i, _spell_level()):
		_flash_msg("%s unlocks at %s level %d" % [sp.name, Weapons.NAMES[weapon_slot].to_lower(), int(sp.get("level", 1))], Color("ff9a8a"))
		return
	spell_sel[weapon_slot] = i
	_flash_msg(str(sp.name), Color("bcd6ff"))


## v0.12.7 the staff or wand you're holding or switching to (-1: neither). Mid-cast a switch waits until the cast
## ends, so the staff can still be in hand after you pressed another number: the wheel goes by either, so it only ever
## steps spells while a magic weapon is involved, and never turns into a weapon switch by accident.
func _magic_in_hand() -> int:
	if Weapons.is_magic(weapon_slot):
		return weapon_slot
	if net.predicted != null and Weapons.is_magic(net.predicted.weapon):
		return net.predicted.weapon
	return -1


## The next (+1) or previous (-1) unlocked spell of weapon w (the one in hand), round the end.
func _step_spell(step: int, w := -1) -> void:
	if w < 0:
		w = weapon_slot
	if not Weapons.is_magic(w):
		return
	var n: int = (Weapons.get_data(w).spells as Array).size()
	var cur := int(spell_sel.get(w, 0))
	var lv := 1
	if net.predicted != null:
		lv = net.predicted.staff_lvl if w == Weapons.STAFF else net.predicted.wand_lvl
	for k in range(1, n + 1):
		var i := posmod(cur + step * k, n)
		if Weapons.unlocked(w, i, lv):
			if i != cur:
				spell_sel[w] = i
				_flash_msg(str(Weapons.spell(w, i).name), Color("bcd6ff"))
			return


## Under the crosshair for a moment: what was just picked.
func _flash_msg(text: String, col := Color.WHITE) -> void:
	if switch_label == null:
		return
	switch_label.text = text
	switch_label.add_theme_color_override("font_color", col)
	switch_label.modulate.a = 1.0
	if switch_label.has_meta("tw"):
		(switch_label.get_meta("tw") as Tween).kill()
	var tw := switch_label.create_tween()
	tw.tween_interval(0.9)
	tw.tween_property(switch_label, "modulate:a", 0.0, 0.5)
	switch_label.set_meta("tw", tw)


func _open_wheel(code: int) -> void:
	var st := net.predicted
	match code:
		KEY_TAB:
			var its := []
			for i in Weapons.NAMES.size():
				var own := ((st.owned >> i) & 1) == 1
				var sub := "%d" % (i + 1)
				if i == Weapons.BOW:
					sub += "   %d arrows" % st.arrows
				elif i == Weapons.SLING:
					sub += "   %d rocks" % st.rocks
				elif Weapons.is_magic(i) and own:
					sub += "   " + str(Weapons.spell(i, int(spell_sel.get(i, 0))).name)
				its.append({ "icon": "w:%d" % i, "label": Weapons.NAMES[i], "sub": sub if own else "not found yet", "enabled": own })
			wheel_kind = "weapon"
			radial.open(its, "Weapons", weapon_slot, "point, then let go of Tab")
		KEY_R:
			if not Weapons.is_magic(weapon_slot):
				held.erase(KEY_R)
				_flash_msg("R picks a spell: take the staff (6) or the wand (7)", Color("c9c9d6"))
				return
			var its := []
			var spells: Array = Weapons.get_data(weapon_slot).spells
			var wand := weapon_slot == Weapons.WAND
			for i in spells.size():
				var sp: Dictionary = spells[i]
				var ok := Weapons.unlocked(weapon_slot, i, _spell_level())
				var sub := ""
				if not ok:
					sub = "Lv %d" % int(sp.get("level", 1))
				elif wand:
					var left: int = st.recharge[i] if i < st.recharge.size() else 0
					sub = ("%d s" % int(ceil(left * Config.DT))) if left > 0 else "ready"
				elif bool(sp.get("channel", false)):
					sub = "%d mana/s" % int(round(float(sp.get("drain", 1)) * Config.TICK_RATE / 5.0))
				else:
					sub = "%d mana" % int(sp.cost)
				its.append({ "icon": str(sp.name), "label": "%d  %s" % [i + 1, sp.name], "sub": sub, "enabled": ok })
			wheel_kind = "spell"
			radial.open(its, Weapons.NAMES[weapon_slot] + " spells", int(spell_sel.get(weapon_slot, 0)), "point, then let go of R")
		KEY_G:
			wheel_target = _crosshair_enemy()
			wheel_ground = _ground_point()
			var n := _my_golems()
			var mode: int = (net.golem_orders.get(net.my_id, [Golems.Order.FOLLOW]) as Array)[0]
			var col: Color = net.roster.get(net.my_id, {}).get("color", Color.WHITE)
			var tgt := "nothing under the crosshair"
			var tgt_ok := false
			if not wheel_target.is_empty():
				tgt_ok = _may_order_attack(int(wheel_target[0]))
				tgt = str(wheel_target[2]) + ("" if tgt_ok else " (PvP off)")
			var its := [
				{ "icon": "o:follow", "label": "Follow me", "sub": "guard me as I go", "enabled": n > 0, "tint": col },
				{ "icon": "o:stay", "label": "Stay here", "sub": "hold where I stand", "enabled": n > 0, "tint": col },
				{ "icon": "o:go", "label": "Go there", "sub": "hold the crosshair spot", "enabled": n > 0, "tint": col },
				{ "icon": "o:attack", "label": "Attack that", "sub": tgt, "enabled": n > 0 and tgt_ok, "tint": col },
				{ "icon": "o:regroup", "label": "Regroup", "sub": "drop it, come back", "enabled": n > 0, "tint": col },
			]
			wheel_kind = "golem"
			radial.open(its, "Golems (%d)" % n if n > 0 else "No golems", mode, "point, then let go of G" if n > 0 else "summon some with the wand")


func _wheel_pick(kind: String, i: int) -> void:
	match kind:
		"weapon":
			_pick_weapon(i)
		"spell":
			_pick_spell(i)
		"golem":
			match i:
				0: _golem_order(Golems.Order.FOLLOW)
				1: _golem_order(Golems.Order.STAY)
				2: _golem_order(Golems.Order.GOTO, wheel_ground)
				3: _golem_order(Golems.Order.ATTACK, Vector3.ZERO, int(wheel_target[0]) if not wheel_target.is_empty() else 0)
				4: _golem_order(Golems.Order.REGROUP)


## How many golems (titan included) this player has standing, as drawn.
func _my_golems() -> int:
	var n := 0
	if golem_view:
		for g: Dictionary in golem_view.golems.values():
			if g.owner == net.my_id and g.state != Golems.State.DIE:
				n += 1
	return n


## Ask the server to order this player's golems (it checks and tells everyone).
func _golem_order(mode: int, point := Vector3.ZERO, target := 0) -> void:
	if _my_golems() == 0:
		_flash_msg("No golems: summon them with the wand's Golem spell", Color("c9c9d6"))
		return
	if mode == Golems.Order.STAY and net.predicted:
		point = net.predicted.pos
	net.request_golem_order(mode, point, target)
	var words := ["Golems: follow me", "Golems: stay here", "Golems: go there", "Golems: attack!", "Golems: regroup"]
	var txt: String = words[mode]
	if mode == Golems.Order.ATTACK and not wheel_target.is_empty() and int(wheel_target[0]) == target:
		txt = "Golems: attack %s!" % wheel_target[2]
	_flash_msg(txt, net.roster.get(net.my_id, {}).get("color", Color.WHITE).lightened(0.3))


## Middle mouse: attack the enemy under the crosshair, or go to the spot on the ground there.
func _smart_order() -> void:
	var e := _crosshair_enemy()
	if not e.is_empty() and _may_order_attack(int(e[0])):
		wheel_target = e
		_golem_order(Golems.Order.ATTACK, Vector3.ZERO, int(e[0]))
	else:
		_golem_order(Golems.Order.GOTO, _ground_point())


## Could our golems be ordered against this target (the server checks again)? Thunderhorn, challengers, their golems
## and the dummies always; players and their golems only when both of you have PvP on.
func _may_order_attack(t: int) -> bool:
	var mine := bool(net.roster.get(net.my_id, {}).get("pvp", false))
	if t == Boss.ID or t >= Fog.NPC_ID0 or (t < 0 and t > -1000):
		return true
	if t > 0:
		return mine and bool(net.roster.get(t, {}).get("pvp", false))
	var g = golem_view.golems.get(-1000 - t, null) if golem_view else null
	if g == null:
		return false
	return int(g.owner) >= Fog.NPC_ID0 or (mine and bool(net.roster.get(int(g.owner), {}).get("pvp", false)))


## The spot on the ground the crosshair points at (or 80 m out along it), for Go there.
func _ground_point() -> Vector3:
	var o := cam.global_position
	var d := -cam.global_transform.basis.z
	var t := 80.0
	if d.y < -0.001:
		t = minf(t, -o.y / d.y)
	t = minf(t, WorldLayout.ray_hit(o, d, t))
	var p := o + d * t
	return Vector3(p.x, 0.0, p.z)


## Distance along a ray to an upright cylinder (feet at c, radius r, height h), or INF.
static func _ray_cyl(o: Vector3, d: Vector3, c: Vector3, r: float, h: float, max_t: float) -> float:
	var oc := Vector2(o.x - c.x, o.z - c.z)
	var dd := Vector2(d.x, d.z)
	var a := dd.dot(dd)
	if a < 1e-8:
		return INF
	var b := 2.0 * oc.dot(dd)
	var cc := oc.dot(oc) - r * r
	var disc := b * b - 4.0 * a * cc
	if disc < 0.0:
		return INF
	for tt in [(-b - sqrt(disc)) / (2.0 * a), (-b + sqrt(disc)) / (2.0 * a)]:
		if tt > 0.0 and tt < max_t:
			var y: float = o.y + d.y * tt
			if y > c.y - 0.2 and y < c.y + h:
				return tt
	return INF


## What enemy (or practice dummy) the crosshair is on: [id, feet position, name], or []. Players and challengers
## (by their drawn bodies), other summoners' golems and titans, Thunderhorn, the dummies; walls and the ground stop
## the look. A little generous (+0.25 m), so a moving target is easy to pick.
func _crosshair_enemy() -> Array:
	if cam == null:
		return []
	var o := cam.global_position
	var d := -cam.global_transform.basis.z
	var max_t := 80.0
	if d.y < -0.001:
		max_t = minf(max_t, -o.y / d.y + 0.5)
	max_t = minf(max_t, WorldLayout.ray_hit(o, d, max_t) + 0.3)
	var best := []
	var best_t := INF
	for id in avatars.keys():
		if id == net.my_id or not avatars[id].visible:
			continue
		var p: Vector3 = avatars[id].position
		var t := _ray_cyl(o, d, p, 0.7, 1.95, max_t)
		if t < best_t:
			best_t = t
			best = [id, p, str(net.roster.get(id, {}).get("name", "them"))]
	if golem_view:
		for gid in golem_view.golems.keys():
			var g: Dictionary = golem_view.golems[gid]
			if g.owner == net.my_id or g.state == Golems.State.DIE:
				continue
			var p: Vector3 = (g.root as Node3D).position
			var t := _ray_cyl(o, d, p, 1.2 if g.titan else 0.6, 3.6 if g.titan else 1.4, max_t)
			if t < best_t:
				best_t = t
				best = [-1000 - int(gid), p, ("%s's titan" if g.titan else "%s's golem") % str(net.roster.get(g.owner, {}).get("name", "a"))]
	if boss_view and boss_view.alive:
		var t := _ray_cyl(o, d, boss_view.pos, Boss.RADIUS + 0.3, Boss.HEIGHT, max_t)
		if t < best_t:
			best_t = t
			best = [Boss.ID, boss_view.pos, "Thunderhorn"]
	for i in WorldLayout.DUMMIES.size():
		var t := _ray_cyl(o, d, WorldLayout.DUMMIES[i], 0.6, 1.9, max_t)
		if t < best_t:
			best_t = t
			best = [-(i + 1), WorldLayout.DUMMIES[i], "the dummy"]
	return best


## Esc menu: resume, mouse sensitivity, which look to play as, leave the game. The game keeps running underneath
## (it's online); your player just stops taking input while it is open.
func _set_paused(on: bool) -> void:
	pause_menu.visible = on
	if on:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		attack_block_until = Time.get_ticks_msec() + 250


## F2 / Esc menu: the host switches the look for everyone; for anyone else it's the host's choice.
func _switch_character() -> void:
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		net.host_set_style("figure" if net.style == "pip" else "pip")
	else:
		Fx.word(self, (net.predicted.pos if net.predicted else Vector3.ZERO) + Vector3(0, 1.2, 0), "the host picks the look", Color("ffe08a"))


func _pause_pick_style(i: int) -> void:
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		net.host_set_style("figure" if i == 1 else "pip")
	else:
		pause_char.select(1 if net.style == "figure" else 0)   # not the host: show the host's choice


func _build_pause_menu(layer: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.visible = false
	layer.add_child(panel)
	pause_menu = panel
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Paused (the world keeps going)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(func(): _set_paused(false))
	box.add_child(resume)
	var sl := Label.new()
	box.add_child(sl)
	var slider := HSlider.new()
	slider.min_value = 0.0005
	slider.max_value = 0.008
	slider.step = 0.0001
	slider.value = mouse_sens
	sl.text = "Mouse sensitivity  %.1f" % (mouse_sens * 1000.0)
	slider.value_changed.connect(func(v): mouse_sens = v; sl.text = "Mouse sensitivity  %.1f" % (v * 1000.0))
	box.add_child(slider)
	var cl := Label.new()
	cl.text = "Look for everyone (host only, F2)"
	box.add_child(cl)
	pause_char = OptionButton.new()
	pause_char.add_item("Pip (pixel sprite)")
	pause_char.add_item("3D figure (test character)")
	pause_char.item_selected.connect(func(i): _pause_pick_style(i))
	box.add_child(pause_char)
	var ctl := Button.new()
	ctl.text = "Controls (F1)"
	ctl.pressed.connect(func(): controls_panel.visible = not controls_panel.visible)
	box.add_child(ctl)
	var leave := Button.new()
	leave.text = "Leave game"
	leave.pressed.connect(_leave_game)
	box.add_child(leave)


## v0.12.2 F1: every control in one panel (the game keeps running under it).
func _build_controls_panel(layer: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.08, 0.86)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	panel.visible = false
	layer.add_child(panel)
	controls_panel = panel
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	panel.add_child(grid)
	var head := Label.new()
	head.text = "Controls"
	head.add_theme_font_size_override("font_size", 22)
	head.add_theme_color_override("font_color", Icons.GOLD)
	grid.add_child(head)
	var close := Label.new()
	close.text = "F1 or Esc to close"
	close.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	grid.add_child(close)
	for row in CONTROLS:
		var a := Label.new()
		a.text = row[0]
		a.add_theme_color_override("font_color", Color("ffe9a8"))
		grid.add_child(a)
		var b := Label.new()
		b.text = row[1]
		grid.add_child(b)


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
	help.text = HELP_LINE
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	help.position = Vector2(12, -36)
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
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
	zap_back = ColorRect.new()   # Static: segments over the health bar, shown while it builds or stuns
	zap_back.color = Color(0, 0, 0, 0.55)
	zap_back.size = Vector2(300, 12)
	zap_back.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	zap_back.position = Vector2(-150, -76)
	zap_back.visible = false
	layer.add_child(zap_back)
	zap_fill = ColorRect.new()
	zap_fill.color = Color("b070ff")
	zap_fill.size = Vector2(0, 8)
	zap_fill.position = Vector2(2, 2)
	zap_back.add_child(zap_fill)
	for i in 6:   # the dividers between stacks (placed each frame: 5 or 6 stacks)
		var dv := ColorRect.new()
		dv.color = Color(0, 0, 0, 0.8)
		dv.size = Vector2(2, 12)
		dv.name = "div%d" % i
		zap_back.add_child(dv)
	zap_label = Label.new()
	zap_label.position = Vector2(0, -5)
	zap_label.size = Vector2(300, 20)
	zap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zap_label.add_theme_font_size_override("font_size", 12)
	zap_label.add_theme_color_override("font_color", Color("e6c8ff"))
	zap_label.add_theme_color_override("font_outline_color", Color.BLACK)
	zap_label.add_theme_constant_override("outline_size", 5)
	zap_back.add_child(zap_label)
	var mana_back := ColorRect.new()   # mana, under the health bar
	mana_back.color = Color(0, 0, 0, 0.55)
	mana_back.size = Vector2(300, 10)
	mana_back.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	mana_back.position = Vector2(-150, -42)
	layer.add_child(mana_back)
	mana_fill = ColorRect.new()
	mana_fill.color = Color(0.3, 0.55, 1.0)
	mana_fill.size = Vector2(296, 6)
	mana_fill.position = Vector2(2, 2)
	mana_back.add_child(mana_fill)
	hud_spells = Label.new()
	hud_spells.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hud_spells.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud_spells.grow_vertical = Control.GROW_DIRECTION_BEGIN   # grows upward, above the weapons line
	hud_spells.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	hud_spells.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_spells.offset_top = -330
	hud_spells.offset_bottom = -222   # the level line, over the spell hotbar
	hud_spells.add_theme_font_size_override("font_size", 16)
	hud_spells.add_theme_color_override("font_color", Color("bcd6ff"))
	hud_spells.add_theme_color_override("font_outline_color", Color.BLACK)
	hud_spells.add_theme_constant_override("outline_size", 6)
	layer.add_child(hud_spells)
	spell_bar = SpellBar.new()   # v0.12.2: the spell hotbar, over the weapons line and the health bar
	spell_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	spell_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spell_bar.offset_left = -300
	spell_bar.offset_right = 300
	spell_bar.offset_top = -182
	spell_bar.offset_bottom = -130
	spell_bar.visible = false
	layer.add_child(spell_bar)
	switch_label = Label.new()   # what was just picked, under the crosshair
	switch_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)   # over the crosshair, clear of your body
	switch_label.offset_left = -300
	switch_label.offset_right = 300
	switch_label.offset_top = -110
	switch_label.offset_bottom = -80
	switch_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	switch_label.add_theme_font_size_override("font_size", 22)
	switch_label.add_theme_color_override("font_outline_color", Color.BLACK)
	switch_label.add_theme_constant_override("outline_size", 7)
	switch_label.modulate.a = 0.0
	layer.add_child(switch_label)
	radial = RadialMenu.new()
	radial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(radial)
	_build_controls_panel(layer)
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

	_build_pause_menu(layer)
	console = DevConsole.new(net)   # v0.12.6: ` opens it
	add_child(console)
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
	name_edit = _field(box, "Your character's name", _saved_name())
	name_edit.placeholder_text = "Type a name (you can change it later: ` then name ...)"
	name_edit.max_length = Config.MAX_NAME
	addr_edit = _field(box, "Invite code or address (to join)", "127.0.0.1")
	port_edit = _field(box, "Port (UDP)", str(Config.DEFAULT_PORT))
	var cl := Label.new()
	cl.text = "Look for everyone (when you host)"
	box.add_child(cl)
	char_pick = OptionButton.new()
	char_pick.add_item("Pip (pixel sprite)")
	char_pick.add_item("3D figure (test character)")
	box.add_child(char_pick)
	var row := HBoxContainer.new()
	box.add_child(row)
	for spec in [["Play / Host", _start_host], ["Join a friend", _start_join]]:
		var btn := Button.new()
		btn.text = spec[0]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(spec[1])
		row.add_child(btn)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	status_label.text = "Play / Host starts a game (alone, or friends join you). To join a friend's game, paste their invite code (or address) and click Join a friend."
	box.add_child(status_label)
	# updates: the version, what the update check found, and a restart / download button when there is one
	var urow := HBoxContainer.new()
	box.add_child(urow)
	update_label = Label.new()
	update_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	update_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	update_label.add_theme_font_size_override("font_size", 13)
	update_label.text = "v" + Updater.running_version()
	urow.add_child(update_label)
	update_btn = Button.new()
	update_btn.visible = false
	urow.add_child(update_btn)
	update_btn.pressed.connect(func():
		if update_page != "":
			OS.shell_open(update_page)
		else:
			_restart_for_update())
	if not bot:
		updater = Updater.new()
		updater.changed.connect(_on_update)
		add_child(updater)
		var every := Timer.new()   # v0.12.7: look for updates every 10 minutes while playing, not only at start
		every.wait_time = 600.0
		every.autostart = true
		every.timeout.connect(func():
			if updater and not update_ready:
				updater.check())
		add_child(every)
	_resume_after_update()


var updater: Updater
var update_label: Label
var update_btn: Button
var update_page := ""

var update_ready := false   # v0.12.7: a downloaded update waits; F9 in the game restarts into it


func _on_update(text: String, can_restart: bool, page_url: String) -> void:
	update_label.text = text
	update_page = page_url
	update_btn.visible = can_restart or page_url != ""
	update_btn.text = "Restart now" if can_restart else "Download page"
	if can_restart and not update_ready:
		update_ready = true
		if menu and not menu.visible:
			toast("%s  Press F9 to restart into it: you'll come straight back with all your progress." % text)


func _field(box: VBoxContainer, label: String, value: String) -> LineEdit:
	var l := Label.new()
	l.text = label
	box.add_child(l)
	var e := LineEdit.new()
	e.text = value
	box.add_child(e)
	return e


## Leave the game: close the connection first (so its port is free to host on again), then rebuild the world and go
## back to the menu.
func _leave_game() -> void:
	net.shutdown()
	get_tree().reload_current_scene()


## v0.12.6 (Jacob): you name your character going in. The name is remembered for next time (user://profile.cfg); the
## Host and Join buttons ask for one if the box is empty. In the game, the console's `name <new name>` changes it.
const PROFILE := "user://profile.cfg"


func _saved_name() -> String:
	var c := ConfigFile.new()
	if c.load(PROFILE) == OK:
		return str(c.get_value("player", "name", ""))
	return ""


## -> false (and asks for a name) if the box is empty when a person pressed Host or Join.
func _name_ready() -> bool:
	var nm := name_edit.text.strip_edges()
	if nm == "":
		if bot or _args().has("host") or _args().has("join"):
			return true   # tests and command-line starts: the server names them "Player N"
		status_label.text = "Type a name for your character first"
		name_edit.grab_focus()
		return false
	var c := ConfigFile.new()
	c.load(PROFILE)
	c.set_value("player", "name", nm)
	c.save(PROFILE)
	return true


## v0.12.7 real play keeps progress on disk (Net.persist); tests, bots and the testing flags never touch it.
func _real_play() -> bool:
	if bot:
		return false
	for a in ["give-all", "give-staff", "give-wand", "max-level", "screenshot", "no-save"]:
		if _args().has(a):
			return false
	return true


# ---- v0.12.7 restarting for an update drops you straight back into the same game
const RESUME := "user://resume.json"
var reconnect_until := 0      # a guest whose host went away (restarting for an update?): keep trying to rejoin until then
var last_join := []           # [address, port] of the last game joined


## Restart into the downloaded update, coming straight back to this game: the host hosts again on the same port (and
## everyone's progress comes back with them, Net.save_progress), a guest rejoins the same address.
func _restart_for_update() -> void:
	var r := {}
	if net.my_id == 1 and net.multiplayer.multiplayer_peer != null and not menu.visible:
		r = { "mode": "host", "port": int(port_edit.text), "name": name_edit.text, "style": net.style }
	elif net.my_id != 1 and not last_join.is_empty():   # in a friend's game, or just turned away for an old version
		r = { "mode": "join", "addr": str(last_join[0]), "port": int(last_join[1]), "name": name_edit.text }
	if not r.is_empty():
		r["t"] = int(Time.get_unix_time_from_system())
		var f := FileAccess.open(RESUME, FileAccess.WRITE)
		f.store_string(JSON.stringify(r))
		f.close()
	net.shutdown()   # (the host saves everyone's progress here)
	Updater.restart()


## At start: just restarted for an update? Back into the game it came from.
func _resume_after_update() -> void:
	if bot or _args().has("host") or _args().has("join") or not FileAccess.file_exists(RESUME):
		return
	var r = JSON.parse_string(FileAccess.get_file_as_string(RESUME))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RESUME))
	if typeof(r) != TYPE_DICTIONARY or int(Time.get_unix_time_from_system()) - int(r.get("t", 0)) > 300:
		return
	name_edit.text = str(r.get("name", name_edit.text))
	port_edit.text = str(int(r.get("port", Config.DEFAULT_PORT)))
	if str(r.get("mode", "")) == "host":
		char_pick.select(1 if str(r.get("style", "pip")) == "figure" else 0)
		_start_host.call_deferred()
	elif str(r.get("mode", "")) == "join":
		addr_edit.text = str(r.get("addr", ""))
		reconnect_until = Time.get_ticks_msec() + 90000   # the host may still be restarting too
		_start_join.call_deferred()


func _start_host() -> void:
	if not _name_ready():
		return
	net.persist = _real_play()   # v0.12.7
	net.style = "figure" if char_pick.selected == 1 else "pip"
	var port := int(port_edit.text)
	var err := net.host(port, name_edit.text)
	if err != OK:
		status_label.text = "Could not host on port %d: %s" % [port, error_string(err)]
		print(status_label.text)
		return
	print("[host] hosting on UDP %d" % port)
	_print_addresses(port)
	_enter_game()


## Join: the menu stays up ("Connecting...") until the host answers; after 6 s with no answer, give up with a clear
## message instead of leaving you in an empty world.
func _start_join() -> void:
	if not _name_ready():
		return
	var addr := addr_edit.text.strip_edges()
	var inv := decode_invite(addr)
	if inv.size() == 2:   # an invite code: it carries the address and the port
		addr = inv[0]
		port_edit.text = str(inv[1])
	var err := net.join(addr, int(port_edit.text), name_edit.text)
	if err != OK:
		status_label.text = "Could not start: %s" % error_string(err)
		return
	last_join = [addr, int(port_edit.text)]
	status_label.text = "Connecting to %s:%s ..." % [addr, port_edit.text]
	joining_until = Time.get_ticks_msec() + 6000
	if bot:
		_enter_game()


func _process_joining() -> void:
	if joining_until == 0:
		return
	if net.my_id != 0 and net.predicted != null:   # in: the host knows us and our player exists
		joining_until = 0
		_enter_game()
	elif Time.get_ticks_msec() > joining_until and Time.get_ticks_msec() < reconnect_until and not last_join.is_empty():
		# v0.12.7 the host is restarting (an update?): try again every few seconds for a while
		status_label.text = "Waiting for the host to come back (restarting for an update?)... trying again"
		net.join(str(last_join[0]), int(last_join[1]), name_edit.text)
		joining_until = Time.get_ticks_msec() + 5000
	elif Time.get_ticks_msec() > joining_until:
		joining_until = 0
		net._reset()
		menu.visible = true
		status_label.text = "No game answered at %s:%s. Is the host running and is the address right?
To play on your own, click Play / Host." % [addr_edit.text.strip_edges(), port_edit.text]


func _enter_game() -> void:
	menu.visible = false
	if not bot:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _print_addresses(port: int) -> void:
	var lines := ["Invite codes (give one to a friend; they paste it into Join):"]
	var best := ""
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			var ts := ip.begins_with("100.")
			var kind := "Tailscale" if ts else "same Wi-Fi"
			var code := invite_code(ip, port)
			lines.append("  %s: %s   (%s)" % [kind, code, ip])
			if ts or best == "":
				best = code
	host_lines = lines
	_show_host_info(best)
	_fetch_public_ip(port)


var host_lines: Array = []

func _show_host_info(copy_code: String) -> void:
	if copy_code != "":
		DisplayServer.clipboard_set(copy_code)
	var lines := host_lines.duplicate()
	if copy_code != "":
		lines.append("  (copied to the clipboard: %s)" % copy_code)
	print("\n".join(lines))
	host_info = "\n".join(lines)


## Ask a public service for this PC's internet address, for the over-the-internet invite code (needs UDP port
## forwarding on the host's router).
func _fetch_public_ip(port: int) -> void:
	if bot:
		return
	var req := HTTPRequest.new()
	req.timeout = 6.0
	add_child(req)
	req.request_completed.connect(func(result, code, _h, body):
		req.queue_free()
		var ip := (body as PackedByteArray).get_string_from_utf8().strip_edges()
		if result == HTTPRequest.RESULT_SUCCESS and code == 200 and ip.is_valid_ip_address() and ip.count(".") == 3:
			host_lines.append("  over the internet: %s   (%s, needs UDP %d forwarded on your router)" % [invite_code(ip, port), ip, port])
			_show_host_info(""))
	req.request("https://api.ipify.org")


## Invite codes: an IPv4 address and port packed into 48 bits and written as ten letters/digits in two groups
## (Crockford base 32: no I, L, O or U, so it reads aloud cleanly), e.g. "3J8QZ-K0W7P".
const CODE_ABC := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

static func invite_code(ip: String, port: int) -> String:
	var p := ip.split(".")
	var n := 0
	for i in 4:
		n = (n << 8) | (int(p[i]) & 255)
	n = (n << 16) | (port & 0xFFFF)
	var s := ""
	for i in 10:
		s = CODE_ABC[n & 31] + s
		n >>= 5
	return s.substr(0, 5) + "-" + s.substr(5)


## The address and port in an invite code, or [] if the text isn't one.
static func decode_invite(text: String) -> Array:
	var t := text.strip_edges().to_upper().replace("-", "").replace(" ", "")
	t = t.replace("O", "0").replace("I", "1").replace("L", "1")
	if t.length() != 10:
		return []
	var n := 0
	for ch in t:
		var v := CODE_ABC.find(ch)
		if v < 0:
			return []
		n = (n << 5) | v
	var port := n & 0xFFFF
	n >>= 16
	return ["%d.%d.%d.%d" % [(n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255], port]


# ================================================================ combat visuals
func _on_local_shot(kind: int, pos0: Vector3, vel0: Vector3, g: float) -> void:
	# our own shot, drawn from this instant on our own clock
	var lv := Weapons.mastery_named(net.predicted.mastery, Weapons.STAFF, "Fireball") if net.predicted != null else 1
	var e := { "node": _proj_node(kind, lv), "kind": kind, "pos0": pos0, "vel0": vel0, "g": g, "local_t0": Engine.get_physics_frames(),
		"tick0": -1, "end_tick": -1, "end_pos": Vector3.ZERO, "stuck": false }
	add_child(e.node)
	local_shots.append(e)


func _on_proj_spawn(id: int, owner: int, kind: int, tick0: int, pos0: Vector3, vel0: Vector3, g: float) -> void:
	if owner == net.my_id and not local_shots.is_empty() and int(local_shots[0].kind) == kind:
		var e: Dictionary = local_shots.pop_front()   # the server's copy of a shot we already drew: link them
		e.tick0 = tick0
		projs[id] = e
		return
	var lv := 1   # v0.12.7: a fireball is drawn at its caster's Fireball mastery
	if kind == 2 and avatars.has(owner) and avatars[owner].state != null:
		lv = Weapons.mastery_named(avatars[owner].state.mastery, Weapons.STAFF, "Fireball")
	var n := { "node": _proj_node(kind, lv), "kind": kind, "pos0": pos0, "vel0": vel0, "g": g, "local_t0": -1,
		"tick0": tick0, "end_tick": -1, "end_pos": Vector3.ZERO, "stuck": false }
	n.node.visible = false
	add_child(n.node)
	projs[id] = n


## A shot bounced off a shield: from now on it follows the server's new path (on the same clock as everyone else's).
func _on_proj_bounce(id: int, tick0: int, pos0: Vector3, vel0: Vector3) -> void:
	if projs.has(id):
		var e: Dictionary = projs[id]
		e.tick0 = tick0
		e.pos0 = pos0
		e.vel0 = vel0
		e.local_t0 = -1


func _on_proj_end(id: int, tick: int, pos: Vector3, stuck: bool) -> void:
	if projs.has(id):
		var e: Dictionary = projs[id]
		e.end_tick = tick
		e.end_pos = pos
		e.stuck = stuck


func _proj_node(kind: int, lv := 1) -> MeshInstance3D:
	if kind == 2:
		var fb := MagicFx.fireball_node() as FireballView
		fb.set_level(lv)   # v0.12.7: bigger, with a thicker trail (and white-hot at III) with mastery
		return fb
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
	if avatars.has(attacker) and avatars[attacker].state != null:
		weapon = avatars[attacker].state.weapon
	if target <= -1000:
		if golem_view:
			golem_view.flash(-1000 - target)
		Fx.burst(self, pos, dir, Color("9a8f80"), 14, 4.0, 0.07)   # stone chips
	elif target < 0:
		var i := -target - 1
		if i < dummies.size():
			(dummies[i] as Dummy).hit(amount, dir)
		Fx.burst(self, pos, dir, Color("e2c27a"), 16, 4.5, 0.06)   # straw
	elif avatars.has(target):
		avatars[target].flash()
		Fx.burst(self, pos, dir, Color("ffe6a0"), 12, 5.5, 0.05)   # sparks
	if weapon == Weapons.SWORD:
		Fx.burst(self, pos, dir, Color("dff2ff"), 8, 7.0, 0.04)
		Fx.word(self, pos, "Shing!", Color("bfe6ff"))
	elif weapon == Weapons.CLUB:
		Fx.word(self, pos, "Thock!" if not killed else "WHAM!", Color("ffb066"))
	# hit-stop: both fighters freeze a moment on impact (3-6 frames light, 8-12 heavy), the victim shakes
	var stop := (4.0 if amount <= 7 else 9.0) / 60.0
	if avatars.has(attacker):
		avatars[attacker].hitstop(stop, false)
	if target >= 0 and avatars.has(target):
		avatars[target].hitstop(stop, true)
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
	if st == null:
		return
	var names := []
	for i in Weapons.NAMES.size():
		if (st.owned >> i) & 1:
			var nm: String = Weapons.NAMES[i]
			if i == Weapons.BOW:
				nm += " (%d)" % st.arrows
			elif i == Weapons.SLING:
				nm += " (%d)" % st.rocks
			names.append(("[%d %s]" if i == st.weapon else " %d %s ") % [i + 1, nm])
	hud_weapons.text = "   ".join(names)
	if not (st.owned >> weapon_slot) & 1:   # v0.12.7: the weapon picked isn't yours any more: what's in hand is
		weapon_slot = st.weapon
	if st.owned != owned_seen:   # just picked up a weapon: take it in hand
		var gained := st.owned & ~owned_seen
		for i in range(Weapons.NAMES.size() - 1, 0, -1):
			if (gained >> i) & 1:
				_pick_weapon(i, true)
				break
		owned_seen = st.owned
	hp_fill.size.x = 296.0 * float(st.hp) / float(Sim.MAX_HP)
	hp_fill.color = Color(0.9, 0.25, 0.2).lerp(Color(0.3, 0.85, 0.35), float(st.hp) / float(Sim.MAX_HP))
	var w := Weapons.get_data(st.weapon)
	charge_fill.size.x = 60.0 * float(st.charge) / float(w.draw) if w.kind == "ranged" else 0.0
	mana_fill.size.x = 296.0 * float(st.mana) / float(Sim.MANA_FULL)
	_static_hud(st)
	if spell_bar:   # v0.12.2: the hotbar (icons, keys, costs, recharges) replaces the old line of names
		spell_bar.mxp = net.roster.get(net.my_id, {}).get("mxp", [])   # v0.12.7: spell mastery points
		spell_bar.show_state(st, int(spell_sel.get(st.weapon, 0)))
	if w.kind == "magic":
		var lv := st.staff_lvl if st.weapon == Weapons.STAFF else st.wand_lvl
		var kills: Array = net.roster.get(net.my_id, {}).get("kills", [0, 0])
		var kn := int(kills[0 if st.weapon == Weapons.STAFF else 1])
		var lvl_line := "%s level %d" % [Weapons.NAMES[st.weapon], lv]
		if lv < Weapons.MAX_LEVEL:
			lvl_line += "   kills %d / %d to the next level" % [kn, int(Weapons.LEVEL_KILLS[lv])]
		else:
			lvl_line += "   (ultimate unlocked)"
		hud_spells.text = ("STUNNED\n" if st.stun > 0 else "") + lvl_line
	elif Weapons.is_arm(st.weapon):   # v0.12.5: fists, club, sword, bow and slingshot level up too (more damage)
		var arms: Array = net.roster.get(net.my_id, {}).get("arms", [0, 0, 0, 0, 0])
		var kn := int(arms[st.weapon]) if st.weapon < arms.size() else 0
		var lv := Weapons.level_for(kn)
		var lvl_line := "%s level %d   damage +%d%%" % [Weapons.NAMES[st.weapon], lv, int(round((float(Weapons.ARM_DAMAGE[lv - 1]) - 1.0) * 100.0))]
		if lv < Weapons.MAX_LEVEL:
			lvl_line += "   kills %d / %d to the next level" % [kn, int(Weapons.LEVEL_KILLS[lv])]
		else:
			lvl_line += "   (max level)"
		hud_spells.text = ("STUNNED\n" if st.stun > 0 else "") + lvl_line
	else:
		hud_spells.text = "STUNNED" if st.stun > 0 else ""
	if st.dead > 0:
		hud_weapons.text = "Knocked out: back up in %.1f s" % (st.dead * Config.DT)
	elif st.down > 0:
		hud_weapons.text = "Knocked down! Getting up..."


## v0.11.0: the Static bar: a segment a stack (6, or 5 while Thunderhorn is enraged), draining slowly; when it's full,
## a 7 s stun, the bar running down and flashing.
func _static_hud(st: Sim.PlayerState) -> void:
	zap_back.visible = st.zap > 0 and st.dead == 0
	if not zap_back.visible:
		return
	var need := Boss.static_need(Boss.shown_enraged)
	for i in 6:
		var dv: ColorRect = zap_back.get_node("div%d" % i)
		dv.visible = i > 0 and i < need
		dv.position.x = 300.0 * i / need - 1.0
	if st.zap >= Sim.ZAP_STUN:
		zap_fill.size.x = 296.0 * float(st.stun) / Sim.STATIC_STUN
		zap_fill.color = Color("b070ff").lerp(Color.WHITE, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.02))
		zap_label.text = "STATIC STUN  %.1f s" % (st.stun * Config.DT)
	else:
		var k := float(st.zap) / float(Sim.ZAP_STACK * need)
		zap_fill.size.x = 296.0 * k
		zap_fill.color = Color("8a5cff").lerp(Color("e6c8ff"), k)
		zap_label.text = "STATIC  %d / %d" % [int(ceil(float(st.zap) / Sim.ZAP_STACK)), need]



# ================================================================ items in the world
func _on_item_added(id: int, kind: int, pos: Vector3, count: int) -> void:
	if cam == null or items.has(id):
		return
	var holder := Node3D.new()
	var m := WeaponModels.make(kind, count)   # v0.12.7: one spent arrow / stone looks like one, not a quiver / pile
	var spin := Node3D.new()   # v0.12.7: weapons turn round their own middle (they used to swing round the grip)
	holder.add_child(spin)
	spin.add_child(m)
	if Weapons.ITEM_WEAPON[kind] >= 0:
		# lying flat: rolled onto its side (the bow flat on the ground, not standing up on its curve like an arch)
		m.rotation = Vector3(0, 0, PI / 2.0) if kind == Weapons.Item.BOW else Vector3(PI / 2.0, 0, 0.3)
		var mid := WeaponModels.middle(m)
		m.position = -(m.basis * mid)
		spin.position.y = 0.16
		var ring := MeshInstance3D.new()        # a soft glow ring, so weapons are easy to spot
		var tm := TorusMesh.new()
		tm.inner_radius = 0.45
		tm.outer_radius = 0.52
		ring.mesh = tm
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.albedo_color = Color(1.0, 0.9, 0.5, 0.55)
		ring.material_override = rm
		ring.scale = Vector3(1, 0.3, 1)
		ring.position.y = 0.03
		holder.add_child(ring)
	add_child(holder)
	holder.global_position = pos
	items[id] = { "node": holder, "model": m, "spin": spin, "kind": kind, "pos": pos, "t": randf() * 6.0 }


func _on_item_removed(id: int, taker: int) -> void:
	if items.has(id):
		var e: Dictionary = items[id]
		(e.node as Node3D).queue_free()
		items.erase(id)
		if taker == net.my_id and Weapons.ITEM_WEAPON[e.kind] >= 0:
			Fx.word(self, e.pos, "+ " + Weapons.ITEM_NAMES[e.kind], Color("fff2a8"))


## Weapons bob and turn slowly; the nearest one within reach shows "E  pick up ...".
func _update_items(delta: float) -> void:
	if prompt == null:
		prompt = Label3D.new()
		prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		prompt.no_depth_test = true
		prompt.font_size = 40
		prompt.outline_size = 12
		prompt.modulate = Color("fff2a8")
		add_child(prompt)
	var me := net.predicted.pos if net.predicted != null else Vector3(1e9, 0, 0)
	var best := -1
	var best_d := 2.2
	for id in items.keys():
		var e: Dictionary = items[id]
		e.t += delta
		if e.kind == Weapons.Item.WAND and magic_fx and magic_fx._door_target == 0.0:
			continue
		if Weapons.ITEM_WEAPON[e.kind] >= 0:
			var sp: Node3D = e.spin
			sp.position.y = 0.2 + sin(e.t * 2.2) * 0.05
			sp.rotation.y = e.t * 0.8
			var d := Vector2(e.pos.x - me.x, e.pos.z - me.z).length()
			if d < best_d:
				best_d = d
				best = id
	var door := WorldLayout.VAULT_DOOR
	if best < 0 and magic_fx and magic_fx._door_target == 0.0 and Vector2(me.x - door.x, me.z - door.z).length() < 2.0 and me.x > door.x - 0.3:
		prompt.visible = true
		prompt.text = "E  open the door"
		prompt.global_position = door + Vector3(0, 1.9, 0)
		return
	if best < 0 and arena_view:
		var ap := arena_view.prompt_for(me)
		if not ap.is_empty():
			prompt.visible = true
			prompt.text = ap[0]
			prompt.global_position = ap[1]
			return
	if best < 0 and net.predicted != null and net.predicted.dead == 0:   # v0.12.7: gathering ammo
		var g := WorldLayout.gather_at(me)
		if g != "":
			prompt.visible = true
			prompt.text = "E  gather stones" if g == "stones" else "E  whittle arrows"
			prompt.global_position = me + Vector3(0, 2.3, 0)
			return
	prompt.visible = best >= 0
	if best >= 0:
		var e: Dictionary = items[best]
		prompt.text = "E  pick up " + Weapons.ITEM_NAMES[e.kind]
		prompt.global_position = e.pos + Vector3(0, 1.0, 0)


# ================================================================ the vault and the tower's beacon
var vault_door: Node3D

## The hidden vault: a squat stone block with a dark doorway on its far side (+x), a shelf inside it for the wand, and
## a heavy wooden door on an iron hinge that swings open (MagicFx turns it). Drawn as blocks round the opening; the
## simulation collides with the whole block.
func _build_vault(b: WorldLayout.Box) -> void:
	var stone := _mat(Color("6b6560"))
	var dark := _mat(Color("1d1a18"))
	var x0 := b.cx - b.hx
	var x1 := b.cx + b.hx
	var z0 := b.cz - b.hz
	var z1 := b.cz + b.hz
	var ow := 0.55   # half the opening's width
	var oh := 1.5    # its height
	var depth := 0.7
	for spec in [
		[Vector3(x1 - x0 - depth, b.h, z1 - z0), Vector3((x0 + x1 - depth) / 2.0, b.h / 2.0, b.cz), stone],   # the back of the block
		[Vector3(depth, b.h, (z1 - z0) / 2.0 - ow), Vector3(x1 - depth / 2.0, b.h / 2.0, (z0 + b.cz - ow) / 2.0), stone],
		[Vector3(depth, b.h, (z1 - z0) / 2.0 - ow), Vector3(x1 - depth / 2.0, b.h / 2.0, (z1 + b.cz + ow) / 2.0), stone],
		[Vector3(depth, b.h - oh, ow * 2.0), Vector3(x1 - depth / 2.0, oh + (b.h - oh) / 2.0, b.cz), stone],   # over the door
		[Vector3(0.05, oh, ow * 2.0), Vector3(x1 - depth + 0.03, oh / 2.0, b.cz), dark],                     # the back of the niche
		[Vector3(depth - 0.1, 0.06, ow * 2.0), Vector3(x1 - depth / 2.0, 0.5, b.cz), _mat(Color("8a6a4a"))],   # the shelf
	]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = spec[0]
		mi.mesh = bm
		mi.material_override = spec[2]
		mi.position = spec[1]
		add_child(mi)
	# the door: planks with two iron bands and a ring pull, hinged on the -z edge of the opening
	vault_door = Node3D.new()
	vault_door.position = Vector3(x1 + 0.04, 0.0, b.cz - ow)
	add_child(vault_door)
	for spec in [[Vector3(0.08, oh, ow * 2.0), Vector3(0, oh / 2.0, ow), Color("7a5232")],
			[Vector3(0.1, 0.1, ow * 2.0), Vector3(0.01, 0.35, ow), Color("3b3b40")],
			[Vector3(0.1, 0.1, ow * 2.0), Vector3(0.01, 1.15, ow), Color("3b3b40")],
			[Vector3(0.12, 0.14, 0.14), Vector3(0.06, 0.8, ow * 1.6), Color("9a9aa2")]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = spec[0]
		mi.mesh = bm
		mi.material_override = _mat(spec[2])
		mi.position = spec[1]
		vault_door.add_child(mi)
	# a faint glow from inside, so the curious notice something
	var l := OmniLight3D.new()
	l.light_color = Color("b066ff")
	l.light_energy = 0.6
	l.omni_range = 2.5
	l.position = Vector3(x1 - depth / 2.0, 0.8, b.cz)
	add_child(l)


## A pale shaft of light over the tower's top, so you can see where the staff is from the spawn.
func _build_beacon() -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.9
	cm.height = 40.0
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.55, 0.8, 1.0, 0.12)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(WorldLayout.TOWER_C.x, WorldLayout.TOWER_TOP + 20.0, WorldLayout.TOWER_C.y)
	add_child(mi)


## A big message in the middle of the screen for a few seconds (level ups).
func toast(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 34)
	l.add_theme_color_override("font_color", Color("ffd86a"))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 10)
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var stacked := 0   # several at once stack downwards
	for c in hud_spells.get_parent().get_children():
		if c.has_meta("toast"):
			stacked += 1
	l.set_meta("toast", true)
	l.position.y += 140 + 52 * stacked
	hud_spells.get_parent().add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)

