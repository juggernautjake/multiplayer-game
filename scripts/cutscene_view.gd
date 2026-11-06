## The Duel Stone's corruption on screen (v0.12.3; the timeline and the rules are in Cutscene, the server's side in
## Net / Boss): the camera's shots, the letterbox bars and the title card, the six minions' puppet poses and their
## glowing eye trails, the corrupted look of the minions, the sounds, and the minions' collapse into purple smoke.
## Main calls pre_avatars (before the avatars are posed), camera (after its own camera, overriding it) and
## post_avatars (after; the eye trails need this frame's poses and camera).
##
## The time comes from the boss state (BossView.state == Boss.S.CUTSCENE, its state_t), so a player who joins in the
## middle sees the rest from where it is, and nothing that already happened is replayed. The camera (the same one in
## the Pip and figure looks) cuts between shots built from where things really are (Thunderhorn as drawn, the stone,
## the minions' avatars, the players):
##   wide        he stops and swings round toward the stone          (from the side, high, pushing in)
##   tracking    the gallop to the stone                              (alongside him)
##   low angle   he rears up over the stone and slams it              (from the ground beside the stone)
##   close-up    the runes turn from gold to red and violet           (on the face away from him; the title card)
##   wide        six figures claw up out of the ground                (from beyond them, craning up)
##   close-up    two of them jerk their heads up, eyes igniting       (in front of their faces)
##   orbit       they twitch and jerk, possessed                      (circling the group)
##   snap        they freeze, snap round to face the players, draw    (from the players' side, a quick push in)
## then the camera eases back to each player over Cutscene.BLEND s and the bars slide away.
class_name CutsceneView
extends Node

var net: Net
var main: Node3D
var bv: BossView
var layer: CanvasLayer
var bar_top: ColorRect
var bar_bot: ColorRect
var title: Label
var active := false
var ct := 0.0                 # film time in ticks
var _last_ct := -1.0
var p0 := Vector3.ZERO        # where he was when it began (as drawn here)
var _blend := 0.0             # seconds of the ease back to the player left
var _cam_tr := Transform3D()
var _cam_fov := 50.0
var _bars := 0.0
var _trails := {}             # minion id -> {l, r: BossModel.Trail, gl, gr: glowing eyes, level}
var _overlay: StandardMaterial3D
var _overlay_t := 0.0
var _hidden := false          # the HUDs and name tags are hidden (restored after)
var _minion_ids: Array = []


func setup(n: Net, m: Node3D, boss_view: BossView) -> void:
	net = n
	main = m
	bv = boss_view
	net.magic_fx.connect(_on_fx)
	layer = CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	bar_top = ColorRect.new()
	bar_bot = ColorRect.new()
	for b in [bar_top, bar_bot]:
		(b as ColorRect).color = Color.BLACK
		(b as ColorRect).mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(b)
	title = Label.new()
	title.text = "THE DUEL STONE IS CORRUPTED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color("ff5a7e"))
	title.add_theme_color_override("font_outline_color", Color("2a0620"))
	title.add_theme_constant_override("outline_size", 18)
	title.add_theme_color_override("font_shadow_color", Color(0.55, 0.1, 1.0, 0.6))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 0)
	title.add_theme_constant_override("shadow_outline_size", 40)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.visible = false
	layer.add_child(title)
	_overlay = StandardMaterial3D.new()   # the minions' corrupted look on the figure: everything darker and purpler
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	_overlay.albedo_color = Color(0.52, 0.34, 0.55)


## Is the film showing (or the camera still easing back)? Main shows your own body then, even in first person.
func showing() -> bool:
	return active or _blend > 0.0


# ================================================================ every frame (Main calls these three)
func pre_avatars(avatars: Dictionary, delta: float) -> void:
	_tick(delta)
	_minion_ids = []
	for id in avatars.keys():
		if int(net.roster.get(id, {}).get("kind", 0)) == 2:
			_minion_ids.append(id)
	_minion_ids.sort()
	_overlay_t -= delta
	var redo := _overlay_t <= 0.0
	if redo:
		_overlay_t = 0.3
	for id in avatars.keys():
		var av: Node3D = avatars[id]
		var i := _minion_ids.find(id)
		if i >= 0:
			_corrupt_look(av, redo)
			av.set("puppet", Cutscene.puppet(ct, i) if active and i < 6 else {})
		if active and av.get("label") != null:
			(av.get("label") as Label3D).visible = false
	if active:
		_hidden = true
	elif _hidden and _blend <= 0.0:
		_hidden = false
		for id in avatars.keys():
			if id != net.my_id and avatars[id].get("label") != null:
				(avatars[id].get("label") as Label3D).visible = true


func camera(cam: Camera3D, delta: float) -> void:
	if active:
		var s: Array = _shot(ct)
		var at: Vector3 = s[0]
		var look: Vector3 = s[1]
		if ct >= Cutscene.RISE_AT:   # (the stone's own close-ups look into it)
			at = _clear(at, look)
		at.y = maxf(at.y, 0.25)
		cam.position = at
		if at.distance_to(look) > 0.05:
			cam.look_at(look, Vector3.UP)
		cam.fov = float(s[2])
		_cam_tr = cam.global_transform
		_cam_fov = cam.fov
	elif _blend > 0.0:
		_blend = maxf(_blend - delta, 0.0)
		var k := smoothstep(0.0, 1.0, 1.0 - _blend / Cutscene.BLEND)
		var game := cam.global_transform
		var tr := _cam_tr.interpolate_with(game, k)
		tr.origin += Vector3.UP * 5.0 * sin(k * PI) * clampf(_cam_tr.origin.distance_to(game.origin) / 30.0, 0.0, 1.0)   # up and over
		cam.global_transform = tr
		cam.fov = lerpf(_cam_fov, cam.fov, k)


func post_avatars(avatars: Dictionary, delta: float) -> void:
	var cam := main.get_viewport().get_camera_3d()
	for id in _trails.keys():
		if not avatars.has(id):
			_free_trail(id)
	for id in _minion_ids:
		var av: Node3D = avatars[id]
		if not av.has_method("eye_points"):
			continue
		if not _trails.has(id):
			_trails[id] = _make_trail()
		var tr: Dictionary = _trails[id]
		var i := _minion_ids.find(id)
		var st = av.get("state")
		var alive: bool = st != null and (st as Sim.PlayerState).dead == 0 and av.visible
		var lit := alive and av.global_position.y > -1.0
		if active:
			lit = lit and ct >= Cutscene.eyes_at(mini(i, 5))
		var eyes: Array = av.eye_points(cam)
		var flick := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.02 + i)
		(tr.l as BossModel.Trail).step(eyes[0], 1.0 * flick if lit else 0.0, Cutscene.EVIL, delta)
		(tr.r as BossModel.Trail).step(eyes[1], 1.0 * flick if lit else 0.0, Cutscene.EVIL2.lerp(Cutscene.EVIL, 0.35), delta)
		for k in [["gl", 0], ["gr", 1]]:
			var g: MeshInstance3D = tr[k[0]]
			g.visible = lit
			g.global_position = eyes[k[1]]


# ================================================================ the film's clock, the bars, the title, the sounds
func _tick(delta: float) -> void:
	var on := bv != null and bv.alive and bv.state == Boss.S.CUTSCENE
	if on and not active:
		active = true
		p0 = bv.root.position if bv.root != null else bv.pos
		ct = bv.state_t / Config.DT
		_last_ct = ct if ct > 6.0 else -1.0   # joined in the middle: don't replay what already happened
		_blend = 0.0
	elif not on and active:
		active = false
		_blend = Cutscene.BLEND if bv != null and bv.alive else 0.25
	if active:
		ct = bv.state_t / Config.DT
		_events()
		_last_ct = ct
	# the letterbox bars slide in and out
	_bars = move_toward(_bars, 1.0 if active else 0.0, delta / (0.45 if active else 0.8))
	var vs := main.get_viewport().get_visible_rect().size
	var h := vs.y * 0.115 * smoothstep(0.0, 1.0, _bars)
	bar_top.position = Vector2(0, 0)
	bar_top.size = Vector2(vs.x, h)
	bar_bot.position = Vector2(0, vs.y - h)
	bar_bot.size = Vector2(vs.x, h)
	bar_top.visible = h > 0.5
	bar_bot.visible = h > 0.5
	# the title card, over the runes' close-up
	var t0 := float(Cutscene.SLAM_AT + 30)
	var t1 := float(Cutscene.RISE_AT + 50)
	var a := 0.0
	if active and ct >= t0 and ct < t1:
		a = clampf((ct - t0) / 20.0, 0.0, 1.0) * clampf((t1 - ct) / 20.0, 0.0, 1.0)
	title.visible = a > 0.0
	if title.visible:
		title.size = Vector2(vs.x, 120)
		title.position = Vector2(0, vs.y * 0.62)
		title.pivot_offset = title.size * 0.5
		title.scale = Vector2.ONE * (1.0 + 0.06 * (1.0 - clampf((ct - t0) / 60.0, 0.0, 1.0)))
		title.modulate = Color(1, 1, 1, a)
	# the HUDs step aside while it shows
	var show_hud := not showing()
	var hud = main.get("hud")
	if hud != null and (hud as Node).get_parent() is CanvasLayer:
		var pm = main.get("pause_menu")
		((hud as Node).get_parent() as CanvasLayer).visible = show_hud or (pm != null and (pm as Control).visible)
	if bv != null and bv.hud != null and bv.alive:
		bv.hud.visible = show_hud


func _cross(x: float) -> bool:
	return _last_ct < x and ct >= x


## The film's moments: sounds, the lightning strike on the stone, the minions' dirt and eyes, their snap.
func _events() -> void:
	var s := Cutscene.stone()
	var mfx: MagicFx = main.get("magic_fx")
	if _cross(0.0) or _cross(1.0):
		Synth.play(self, Synth.thunder(), -6.0)
		Synth.play(self, Synth.fx("snort"), -2.0)
	if _cross(Cutscene.TURN_END + 4.0):
		Synth.play(self, Synth.roar(2), -6.0)
	if _cross(Cutscene.RUN_END + 8.0):
		Synth.play(self, Synth.roar(1), -2.0)
	if _cross(Cutscene.SLAM_AT):
		Synth.play(self, Synth.corrupt("slam"), 2.0)
		Synth.play(self, Synth.thunder(), 0.0)
		if mfx != null:
			mfx._bolt(s + Vector3(0, WorldLayout.DUEL_H, 0))
			mfx._flash_light(s + Vector3(0, 2.0, 0), Cutscene.EVIL, 14.0, 24.0, 0.9)
			mfx._cracks(s, 4.0, 12)
		MotionFx.land(main, s, 2.0)
		Fx.burst(main, s + Vector3(0, 1.0, 0), Vector3.UP, Cutscene.EVIL, 30, 8.0, 0.05)
		main.set("shake", 0.4)
	if _cross(Cutscene.CORRUPT_AT):
		Synth.play(self, Synth.corrupt("drone"), -3.0)
		evil_smoke(main, s + Vector3(0, 0.6, 0), 4, 0.7, 3.0, 0.5)
	for i in 6:
		var at := _minion_pos(i)
		if _cross(float(Cutscene.rise_start(i))):
			Synth.play(self, Synth.corrupt("creak"), -7.0 + (2.0 if i == 2 else 0.0))
			Fx.burst(main, Vector3(at.x, 0.1, at.z), Vector3.UP, Color("5a4632"), 22, 3.5, 0.07)
			evil_smoke(main, Vector3(at.x, 0.0, at.z), 3, 0.4, 1.4, 0.45, 0.35)
			if mfx != null:
				mfx._cracks(Vector3(at.x, 0, at.z), 1.6, 6)
		if _cross(float(Cutscene.eyes_at(i))):   # the eyes ignite
			Fx.burst(main, Vector3(at.x, 1.6, at.z), Vector3.UP, Cutscene.EVIL, 12, 2.0, 0.04)
	if _cross(Cutscene.EYES_AT):
		Synth.play(self, Synth.corrupt("whisper"), -1.0)
	if _cross(Cutscene.TWITCH_AT + 40.0):
		Synth.play(self, Synth.corrupt("creak"), -9.0)
	if _cross(Cutscene.SNAP_AT + 14.0):
		Synth.play(self, Synth.corrupt("snap"), 0.0)
		main.set("shake", 0.18)
	if _cross(Cutscene.SNAP_AT + 22.0):   # weapons drawn: a flash at each
		for i in 6:
			Fx.burst(main, _minion_pos(i) + Vector3(0, 1.1, 0), Vector3.UP, Cutscene.EVIL2, 14, 2.5, 0.04)
		Synth.play(self, Synth.fx("whoosh"), -4.0)


## Minion i's avatar, or where it will rise.
func _minion_pos(i: int) -> Vector3:
	if i < _minion_ids.size():
		var av = (main.get("avatars") as Dictionary).get(_minion_ids[i], null)
		if av != null:
			return (av as Node3D).global_position
	return Cutscene.minion_spot(i, p0)


# ================================================================ the shots
## The camera at film time c (ticks): [position, look-at point, fov].
func _shot(c: float) -> Array:
	var s := Cutscene.stone()
	var b: Vector3 = bv.root.position if bv.root != null else bv.pos
	var d := Vector3(s.x - p0.x, 0, s.z - p0.z)
	d = d.normalized() if d.length() > 0.5 else Vector3(0, 0, -1)
	var side := d.cross(Vector3.UP).normalized()
	var stand := Cutscene.stand_spot(p0)
	var u := Vector3(stand.x - s.x, 0, stand.z - s.z).normalized()
	var su := u.cross(Vector3.UP).normalized()
	var up := Vector3.UP
	if c < Cutscene.TURN_END:   # wide: he swings round toward the stone
		var k := c / Cutscene.TURN_END
		return [p0 + side * (21.0 - 3.0 * k) - d * 9.0 + up * 7.5, b + up * 3.5, lerpf(52.0, 47.0, k)]
	if c < Cutscene.RUN_END:   # tracking alongside the gallop
		return [b + side * 12.5 - d * 3.5 + up * 3.2, b + d * 6.0 + up * 2.6, 56.0]
	if c < Cutscene.SLAM_AT + 14:   # low angle from the ground beside the stone: he rears over it and slams
		var k := clampf((c - Cutscene.RUN_END) / float(Cutscene.SLAM_AT + 14 - Cutscene.RUN_END), 0.0, 1.0)
		return [s + su * 6.0 - u * 3.4 + up * 0.35, b.lerp(s, 0.3) + up * (4.0 + 2.0 * k), lerpf(66.0, 60.0, k)]
	if c < Cutscene.RISE_AT:   # close-up of the runes on the face away from him, turning evil
		var k := clampf((c - Cutscene.SLAM_AT - 14.0) / float(Cutscene.RISE_AT - Cutscene.SLAM_AT - 14), 0.0, 1.0)
		var n := Vector3(0, 0, -1.0 if u.z > 0.0 else 1.0)
		var drift := Vector3(n.z, 0, -n.x) * (0.35 - 0.7 * k)
		return [s + n * (3.4 - 0.7 * k) + drift + up * 1.25, s + up * 1.0, 40.0]
	if c < Cutscene.EYES_AT - 14:   # wide: they claw up out of the ground facing us, the stone and him behind them
		var k := clampf((c - Cutscene.RISE_AT) / float(Cutscene.EYES_AT - 14 - Cutscene.RISE_AT), 0.0, 1.0)
		return [s - u * 13.5 - su * 2.0 + up * (1.6 + 0.9 * k), s - u * 4.5 + up * 1.7, 54.0]
	var group := Vector3.ZERO
	for i in 6:
		group += _minion_pos(i)
	group /= 6.0
	group.y = 0.0
	if c < Cutscene.TWITCH_AT:   # close-up: the two in the middle jerk their heads up, eyes igniting
		var mid := (_minion_pos(2) + _minion_pos(3)) * 0.5
		mid.y = 0.0
		var k := clampf((c - Cutscene.EYES_AT + 14.0) / float(Cutscene.TWITCH_AT - Cutscene.EYES_AT + 14), 0.0, 1.0)
		return [mid - u * (4.4 - 0.6 * k) + up * 1.25, mid + up * 1.4, 40.0]
	if c < Cutscene.SNAP_AT:   # circling in front of them as they twitch and jerk
		var k := (c - Cutscene.TWITCH_AT) / float(Cutscene.SNAP_AT - Cutscene.TWITCH_AT)
		var dir := (-u).rotated(Vector3.UP, 0.55 - 1.1 * k)
		var hand := Vector3(sin(c * 0.37) * 0.05, sin(c * 0.23) * 0.04, 0)
		return [group + dir * 8.5 + up * 2.0 + hand, group + up * 1.1, 50.0]
	# the snap: high over Thunderhorn's shoulder from the players' side, a push in as they whip round to face us
	var punch := smoothstep(Cutscene.SNAP_AT + 12.0, Cutscene.SNAP_AT + 24.0, c)
	var cam := s + u * 4.0 + su * 14.0 + up * 4.0   # the tableau from the side: him, the stone, his six
	var look := s - u * 3.5 + up * 1.6
	return [cam.lerp(look, 0.15 * punch), look, lerpf(58.0, 50.0, punch)]


## Pull a shot's camera in front of a pillar, trunk or wall between it and what it looks at.
func _clear(at: Vector3, look: Vector3) -> Vector3:
	var v := at - look
	var dist := v.length()
	if dist < 1.5:
		return at
	var dir := v / dist
	var hit := WorldLayout.ray_hit(look + dir * 1.0, dir, dist - 1.0)
	if hit < dist - 1.0:
		return look + dir * maxf(1.0 + hit - 0.6, 1.2)
	return at


# ================================================================ the minions' look
func _corrupt_look(av: Node3D, redo: bool) -> void:
	if av is Avatar:
		(av as Avatar).tint = Color(0.5, 0.34, 0.55)
		return
	if not redo:
		return
	var model = av.get("model")
	if model == null:
		return
	for c in (model as Node).find_children("*", "MeshInstance3D", true, false):
		if (c as MeshInstance3D).material_overlay == null:
			(c as MeshInstance3D).material_overlay = _overlay


func _make_trail() -> Dictionary:
	var l := BossModel.Trail.new(main, 0.06)
	var r := BossModel.Trail.new(main, 0.06)
	l.seg = 0.07
	r.seg = 0.07
	var out := {"l": l, "r": r}
	for k in ["gl", "gr"]:
		var g := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.035
		sm.height = 0.07
		sm.radial_segments = 8
		sm.rings = 4
		g.mesh = sm
		g.material_override = MagicFx._glow_mat(Color("ff3a6a"), 6.0)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.top_level = true
		g.visible = false
		main.add_child(g)
		out[k] = g
	return out


func _free_trail(id) -> void:
	var tr: Dictionary = _trails[id]
	for k in ["l", "r"]:
		var t: BossModel.Trail = tr[k]
		if is_instance_valid(t.mi):
			t.mi.queue_free()
	for k in ["gl", "gr"]:
		if is_instance_valid(tr[k]):
			(tr[k] as Node).queue_free()
	_trails.erase(id)


# ================================================================ events
func _on_fx(kind: String, a: Array) -> void:
	match kind:
		"minion_fall":   # Thunderhorn fell: they collapse, smoke pouring off them
			evil_smoke(main, a[1], 4, 0.4, 1.8, 0.55)
			Fx.burst(main, (a[1] as Vector3) + Vector3(0, 1.0, 0), Vector3.UP, Cutscene.EVIL2, 18, 2.5, 0.05)
		"minion_gone":   # dissolving into purple smoke
			evil_smoke(main, a[1], 9, 0.6, 2.8, 0.7)
			Fx.burst(main, (a[1] as Vector3) + Vector3(0, 0.8, 0), Vector3.UP, Cutscene.EVIL, 30, 3.5, 0.05)
			Fx.burst(main, (a[1] as Vector3) + Vector3(0, 0.8, 0), Vector3.UP, Cutscene.EVIL2, 20, 2.0, 0.05)
			Synth.play(self, Synth.fx("whoosh"), -12.0)


## Purple-black smoke billowing up (the corruption's smoke: the stone, the minions rising and dissolving).
static func evil_smoke(parent: Node, at: Vector3, n: int, spread: float, rise: float, alpha: float, size := 0.5) -> void:
	for i in n:
		var puff := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = randf_range(0.3, 0.6) * size
		sm.height = sm.radius * 2.0
		sm.radial_segments = 10
		sm.rings = 5
		puff.mesh = sm
		var m := StandardMaterial3D.new()
		var g := randf_range(0.0, 1.0)
		m.albedo_color = Color(0.2 + 0.12 * g, 0.04, 0.22 + 0.1 * (1.0 - g), 0.0)
		m.emission_enabled = true
		m.emission = Cutscene.EVIL2.lerp(Cutscene.EVIL, g)
		m.emission_energy_multiplier = 0.2
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		puff.material_override = m
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(puff)
		puff.global_position = at + Vector3(randf_range(-spread, spread), randf_range(0.1, 0.8), randf_range(-spread, spread))
		var wind := Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
		var life := randf_range(1.3, 2.4)
		var tw := puff.create_tween().set_parallel(true)
		var dl := randf_range(0.0, 0.25)
		tw.tween_property(m, "albedo_color:a", alpha * randf_range(0.7, 1.0), 0.15).set_delay(dl)
		tw.tween_property(puff, "global_position", puff.global_position + wind + Vector3(0, rise * randf_range(0.7, 1.3), 0), life).set_delay(dl).set_ease(Tween.EASE_OUT)
		tw.tween_property(puff, "scale", Vector3.ONE * randf_range(1.5, 2.2), life).set_delay(dl)
		tw.tween_property(m, "albedo_color:a", 0.0, life * 0.7).set_delay(dl + life * 0.3)
		tw.chain().tween_callback(puff.queue_free)
