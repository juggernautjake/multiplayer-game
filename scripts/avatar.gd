## A player on screen, drawn as Pip (Jacob's sprite character from 04-games/pip): a pixel-art billboard that stands
## upright, picks the view (S, SE, E, NE, N drawn; SW, W, NW mirrored) from where the camera is relative to the way
## the player faces, and plays the animation that matches the player's state: idle, walk, run, dash, jump, air, land,
## club and sword swings (standing, walking, running, in the air), bow and slingshot draw and release, knocked down.
## Every client animates every player from the state it already has, so animation adds no network traffic.
## On top of the drawn frames (v0.8.0): squash and stretch (a crouch before a jump, stretching up into it, squashing
## on landing by how hard he came down, a jolt on every blow), dust kicked up by running feet and landings,
## afterimages streaking behind a dash, a kick back on every bow and slingshot release, the staff and wand moving
## through each spell's own gesture (CastPose), and the wizard garb (WizardGarb) while he carries the staff or wand.
class_name Avatar
extends Node3D

const SHEETS := [["res://assets/pip/pip-spritesheet.png", "res://assets/pip/pip-spritesheet.json"],
	["res://assets/pip/pip-weapons.png", "res://assets/pip/pip-weapons.json"]]
const PIXEL := 0.04          # metres per sprite pixel: Pip (~45 px) stands ~1.8 m
const DIRS := ["S", "SE", "E", "NE", "N", "NW", "W", "SW"]   # clockwise from facing the camera
const MIRROR := {"SW": "SE", "W": "E", "NW": "NE"}

static var _textures: Array = []
static var _outfit_tex := {}   # outfit -> [body sheet, weapon sheet] (outfit 0 = _textures)
static var _anims := {}   # name -> { dir -> { sheet, row, frames, durations (s), loop } }
static var _cell := Vector2i(64, 64)
static var _anchor := Vector2(32, 58)

var yaw := 0.0
var grounded := true
var dashing := false
var state: Sim.PlayerState   # weapon, attack, charge, death (set by Main every frame)

var model: Node3D         # hidden for your own player in first person
var sprite: Sprite3D
var blob: MeshInstance3D  # coloured ring at the feet
var label: Label3D
var hp_bar: Sprite3D
var zap_bar: Sprite3D        # v0.11.0: Thunderhorn's Static build-up, over the health bar
var zap_back: Sprite3D

var _anim := "idle"
var _frame := 0
var _frame_t := 0.0
var _speed_scale := 1.0
var _last := Vector3.ZERO
var _vel := Vector3.ZERO
var _have_last := false
var _was_grounded := true
var _landing := 0.0
var _dir_i := -1
var _swing_n := -1
var _flash := 0.0
var _slashed_n := -1
# the procedural layer over the drawn frames
var _sq := 1.0                 # vertical squash / stretch (1 = as drawn), a spring
var _v_sq := 0.0
var _nudge := 0.0              # forward jolt (m) along the facing, a spring
var _v_nudge := 0.0
var _ghost_t := 0.0
var _step_d := 0.0             # metres since the last footfall puff
var _fall_v := 0.0             # how fast he was falling just before landing
var _shot_seen := -1
var _accent: Sprite3D
var _color := Color.WHITE
var _carry: Sprite3D          # the weapon he carries (assets/pip/carry), held at his hand in every frame
var _garb_kind := 0
var _outfit := 0
var _cam: Camera3D


static func _load_sheets() -> void:
	if not _textures.is_empty():
		return
	for i in SHEETS.size():
		_textures.append(load(SHEETS[i][0]))
		var f := FileAccess.open(SHEETS[i][1], FileAccess.READ)
		var meta: Dictionary = JSON.parse_string(f.get_as_text())
		_cell = Vector2i(int(meta.cell.w), int(meta.cell.h))
		_anchor = Vector2(float(meta.anchor.x), float(meta.anchor.y))
		for a in meta.animations:
			var by_dir: Dictionary = _anims.get(a.name, {})
			var durs := PackedFloat32Array()
			for ms in a.durationsMs:
				durs.append(float(ms) / 1000.0)
			by_dir[a.dir] = { "sheet": i, "row": int(a.row), "frames": int(a.frames), "durations": durs, "loop": bool(a.loop) }
			_anims[a.name] = by_dir


var _tex: Array = []     # this player's sheets: Pip in their outfit
var _name := ""


## Pip's sheets recoloured for an outfit (tools/make_outfits.py): 0 the original (the host), 1 blue, 2 green, 3 crimson.
## v0.8.1: outfit "wizard" / "shadow" are the garb sheets (tools/make_garb_sheets.py): the robe, hat, cloak or hood
## drawn into every frame.
static func garb_textures(look: String) -> Array:
	if not _outfit_tex.has(look):
		_outfit_tex[look] = [load("res://assets/pip/garb/pip-spritesheet-%s.png" % look), load("res://assets/pip/garb/pip-weapons-%s.png" % look),
			load("res://assets/pip/garb/pip-spritesheet-%s-accent.png" % look), load("res://assets/pip/garb/pip-weapons-%s-accent.png" % look)]
	return _outfit_tex[look]


static func outfit_textures(outfit: int) -> Array:
	if outfit <= 0:
		return _textures
	if not _outfit_tex.has(outfit):
		_outfit_tex[outfit] = [load("res://assets/pip/outfits/pip-spritesheet-%d.png" % outfit), load("res://assets/pip/outfits/pip-weapons-%d.png" % outfit)]
	return _outfit_tex[outfit]


func _init(player_name: String, color: Color, show_name: bool, outfit := 0) -> void:
	_load_sheets()
	_outfit = outfit % 4
	_tex = outfit_textures(_outfit)
	_name = player_name
	model = Node3D.new()
	add_child(model)
	sprite = Sprite3D.new()
	sprite.texture = _tex[0]
	sprite.region_enabled = true
	sprite.pixel_size = PIXEL
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y   # stays upright, turns to face the camera
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST  # crisp pixels
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.shaded = false
	sprite.double_sided = true
	sprite.centered = true
	sprite.offset = Vector2(_cell.x / 2.0 - _anchor.x, _anchor.y - _cell.y / 2.0)  # Pip's feet on the origin
	model.add_child(sprite)

	blob = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.42
	disc.bottom_radius = 0.42
	disc.height = 0.01
	blob.mesh = disc
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(color.r, color.g, color.b, 0.55)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blob.material_override = bm
	blob.top_level = true
	add_child(blob)

	label = Label3D.new()
	label.text = player_name
	label.modulate = color.lightened(0.35)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.35
	label.font_size = 44
	label.outline_size = 12
	label.no_depth_test = true
	label.visible = show_name
	add_child(label)

	# a small health bar over other players' heads
	hp_bar = Sprite3D.new()
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	hp_bar.texture = ImageTexture.create_from_image(img)
	hp_bar.pixel_size = 1.0
	hp_bar.scale = Vector3(0.9, 0.08, 1)
	hp_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp_bar.no_depth_test = true
	hp_bar.position.y = 2.12
	hp_bar.visible = show_name
	add_child(hp_bar)
	var zb := Avatar.static_bars(self, img, 2.2)
	zap_back = zb[0]
	zap_bar = zb[1]
	_color = color
	_accent = Sprite3D.new()   # the costume's accent colour pieces, tinted with his colour (v0.9.0)
	_accent.pixel_size = PIXEL
	_accent.region_enabled = true
	_accent.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_accent.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_accent.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_accent.shaded = false
	_accent.double_sided = true
	_accent.centered = true
	_accent.offset = sprite.offset
	_accent.modulate = Color(color.r * 1.25, color.g * 1.25, color.b * 1.25)
	_accent.visible = false
	model.add_child(_accent)
	_carry = Sprite3D.new()   # the weapon he carries, in his hand in every frame
	_carry.pixel_size = PIXEL
	_carry.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_carry.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_carry.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_carry.shaded = false
	_carry.double_sided = true
	_carry.visible = false
	_carry.sorting_offset = 1.0
	_carry.render_priority = 1
	model.add_child(_carry)
	_show()


## v0.11.0: the Static bar over a player's head (a dark back and a violet fill), shared with the 3D figure.
static func static_bars(owner: Node3D, img: Image, y: float) -> Array:
	var out := []
	for i in 2:
		var b := Sprite3D.new()
		b.texture = ImageTexture.create_from_image(img)
		b.pixel_size = 1.0
		b.scale = Vector3(0.9, 0.07, 1)
		b.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		b.no_depth_test = true
		b.position.y = y
		b.render_priority = i
		b.modulate = Color(0, 0, 0, 0.6) if i == 0 else Color("b070ff")
		b.visible = false
		owner.add_child(b)
		out.append(b)
	return out


## Fill it from the player's state: stacks out of Boss.static_need; while static-stunned, the stun running out, flashing.
static func show_static(back: Sprite3D, fill: Sprite3D, st: Sim.PlayerState, shown: bool) -> void:
	var on := shown and st.dead == 0 and st.zap > 0
	back.visible = on
	fill.visible = on
	if not on:
		return
	var k := 0.0
	if st.zap >= Sim.ZAP_STUN:
		k = float(st.stun) / Sim.STATIC_STUN
		fill.modulate = Color("b070ff").lerp(Color.WHITE, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.02))
	else:
		k = float(st.zap) / float(Sim.ZAP_STACK * Boss.static_need(Boss.shown_enraged))
		fill.modulate = Color("8a5cff").lerp(Color("e6c8ff"), k)
	fill.scale.x = maxf(0.9 * clampf(k, 0.0, 1.0), 0.001)
	fill.position.x = 0.0


## PvP on: crossed swords by the name, in red.
func set_pvp(on: bool) -> void:
	label.text = ("⚔ " if on else "") + _name


# v0.12.0 thrown by a charge: Pip spins head over heels in the view's plane (the billboards are switched off and the
# body is turned to face the camera, rolled round its middle), with a dust burst at every bounce and a dust trail as he
# skids; the lying and getting-up frames take over once he stops.
var _roll := 0.0
var _rolling := false
var _roll_vy := 0.0
var _roll_dust := 0.0
var _roll_hv := Vector2.ZERO


func _pip_tumble(delta: float, cam: Camera3D) -> void:
	var st := state
	var hv := Vector2(_vel.x, _vel.z)
	var on := st != null and st.down > 0 and st.dead == 0 and cam != null and (not grounded or hv.length() > 3.0)
	if st != null and st.down > 0 and st.dead == 0 and get_parent() != null:
		if _roll_vy < -3.0 and (_vel.y > 0.5 or grounded):
			MotionFx.land(get_parent(), global_position, clampf(-_roll_vy / 8.0, 0.4, 1.6))
		elif _roll_hv.length() > 5.0 and hv.dot(_roll_hv) < 0.0:
			MotionFx.land(get_parent(), global_position + Vector3(0, 0.6, 0), 0.8)
		if grounded and hv.length() > 2.0:
			_roll_dust -= delta
			if _roll_dust <= 0.0:
				_roll_dust = 0.05
				MotionFx.puff(get_parent(), global_position, 2, 0.45)
	_roll_vy = _vel.y
	_roll_hv = hv
	if on:
		var cb := cam.global_transform.basis
		var right_ish := hv.normalized().dot(Vector2(cb.x.x, cb.x.z)) if hv.length() > 0.1 else 1.0
		_roll -= delta * clampf(hv.length() * 0.8, 5.0, 18.0) * (1.0 if right_ish >= 0.0 else -1.0)
		for sp in [sprite, _accent, _carry]:
			if sp != null:
				sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		var rb := Basis(cb.z.normalized(), _roll) * Basis(cb.x, cb.y, cb.z).orthonormalized()
		var c := Vector3(0, 0.5, 0)
		model.global_transform = Transform3D(rb, global_position + Vector3(0, 0.3, 0) + c - rb * c)
		_rolling = true
	elif _rolling:
		_rolling = false
		model.transform = Transform3D.IDENTITY
		for sp in [sprite, _accent, _carry]:
			if sp != null:
				sp.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y


## Briefly tint red (hit).
func flash() -> void:
	_flash = 0.18


var _hitstop := 0.0
var _hit_shake := false


## Freeze the frame for a moment when a hit lands; the victim shakes.
func hitstop(seconds: float, shake: bool) -> void:
	_hitstop = maxf(_hitstop, seconds)
	_hit_shake = _hit_shake or shake


## Call every frame after setting position, yaw, grounded, dashing and state.
func animate(delta: float, cam: Camera3D) -> void:
	_cam = cam
	if _hitstop > 0.0:
		_hitstop -= delta
		sprite.position.x = randf_range(-0.03, 0.03) if _hit_shake else 0.0
		if _hitstop <= 0.0:
			sprite.position.x = 0.0
			_hit_shake = false
		return
	_pip_tumble(delta, cam)
	if not _have_last:
		_last = position
		_have_last = true
	if delta > 0.0:
		var v := (position - _last) / delta
		_vel = _vel.lerp(v, clampf(delta * 12.0, 0.0, 1.0))
	_last = position
	var speed := Vector2(_vel.x, _vel.z).length()

	var want := _pick(speed)
	if state != null and state.swing_n != _swing_n:   # a new swing or shot started: play it from the top
		if _swing_n != -1:
			_anim = ""
		_swing_n = state.swing_n
	if want != _anim:
		_anim = want
		_frame = 0
		_frame_t = 0.0
	_speed_scale = clampf(speed / Sim.WALK_SPEED, 0.6, 1.6) if _anim == "walk" else (clampf(speed / Sim.SPRINT_SPEED, 0.7, 1.4) if _anim == "run" else 1.0)

	var a := _clip(_dir_for(cam))
	if _anim == "getUp" and state != null:   # getting up follows the knock-down's clock
		_frame = clampi(int((1.0 - float(state.down) / Sim.DOWN_GETUP) * a.frames), 0, a.frames - 1)
	elif _anim.ends_with("Draw") and state != null:
		# the draw follows how far the string is pulled, not the clock
		var d := Weapons.get_data(state.weapon)
		_frame = mini(int(float(state.charge) / float(d.draw) * a.frames), a.frames - 1)
	else:
		_frame_t += delta * _speed_scale
		var durs: PackedFloat32Array = a.durations
		while _frame_t >= durs[mini(_frame, durs.size() - 1)]:
			_frame_t -= durs[mini(_frame, durs.size() - 1)]
			if _frame < a.frames - 1:
				_frame += 1
			elif a.loop:
				_frame = 0
			else:
				_frame_t = 0.0
				break
	_show(cam)
	_swing_fx()
	_update_prop(delta)
	_procedural(delta, speed)
	_dress(delta, cam)

	_flash = maxf(_flash - delta, 0.0)
	sprite.modulate = Color(1, 0.45, 0.45) if _flash > 0.0 else Color.WHITE
	if state != null:
		var k := float(state.hp) / float(Sim.MAX_HP)
		hp_bar.scale.x = maxf(0.9 * k, 0.001)
		hp_bar.modulate = Color(0.9, 0.2, 0.2).lerp(Color(0.3, 0.9, 0.3), k)
		hp_bar.visible = label.visible and state.dead == 0
		Avatar.show_static(zap_back, zap_bar, state, label.visible)
		# stunned: dizzy, swaying, crackling violet when it's Static; knocked down: lying, then getting up
		var dizzy := state.stun > 0 and state.dead == 0
		sprite.position.x = sin(Time.get_ticks_msec() * 0.008) * 0.06 if dizzy else 0.0
		if dizzy and state.zap >= Sim.ZAP_STUN and int(Time.get_ticks_msec() / 90) % 4 == 0:
			sprite.modulate = Color(0.85, 0.7, 1.4)

	var ground := WorldLayout.ground_height(position.x, position.z, position.y)
	blob.global_position = Vector3(position.x, ground + 0.012, position.z)
	var s := clampf(1.0 - (position.y - ground) / 6.0, 0.35, 1.0)
	blob.scale = Vector3(s, 1, s)


## The slash trail, on the tick the hit lands (shared with the 3D figure).
func _swing_fx() -> void:
	if state == null or state.dead > 0 or not Weapons.is_melee(state.weapon) or state.atk == 0:
		return
	var mv := Weapons.move(state.weapon, state.combo)
	if state.atk > int(mv.swing) - int(mv.windup) + 1 or _slashed_n == state.swing_n:
		return
	_slashed_n = state.swing_n
	FigureAvatar._trail(get_parent(), global_position, yaw, state.weapon, mv)


## The animation for this moment.
func _pick(speed: float) -> String:
	var st := state
	if st != null and st.dead > 0:
		return "lieDown" if st.dead > Sim.RESPAWN_TICKS - 30 else "lieIdle"
	if st != null and st.down > 0:   # v0.11.0: thrown by Thunderhorn's rush
		if st.down <= Sim.DOWN_GETUP:
			return "getUp"
		return "lieDown" if st.down > Sim.DOWN_TICKS - 24 or not grounded else "lieIdle"
	if st != null:
		var melee := Weapons.is_melee(st.weapon)
		if melee and st.atk > 0:
			var mv := Weapons.move(st.weapon, st.combo)
			var anim: String = mv.anim
			if mv.shape == "arc" and st.weapon in [Weapons.CLUB, Weapons.SWORD]:
				# Pip has moving versions of the club swings (the sword frames are made from them)
				var p := "s" if st.weapon == Weapons.SWORD else "c"
				if not grounded:
					return "a" + p + "_swing"
				if speed > Sim.SPRINT_SPEED - 1.5:
					return "r" + p + "_swing"
				if speed > 0.6:
					return "w" + anim
			return anim
		if Weapons.is_magic(st.weapon):
			if st.atk > 0:
				return "jab"   # Pip thrusts the staff / wand forward to cast
		elif not melee:
			var b := "bow" if st.weapon == Weapons.BOW else "sling"
			if st.charge > 0:
				return b + "Draw"
			if st.atk > 0:
				return b + "Shot"
	_landing = maxf(_landing, 0.0)
	if dashing:
		_was_grounded = grounded
		return "dash"
	if not grounded:
		var r := "air" if (not _was_grounded and (_anim == "air" or (_anim == "jumpStart" and _done()))) else "jumpStart"
		if _was_grounded:
			_v_sq += 3.2   # stretching up into the jump
		_fall_v = maxf(_fall_v, -_vel.y)
		_was_grounded = false
		return r
	if not _was_grounded:
		_landing = 0.21
		_land(_fall_v)
		_fall_v = 0.0
	_was_grounded = true
	_landing = maxf(_landing - get_process_delta_time(), 0.0)
	if _landing > 0.0 and speed < Sim.WALK_SPEED * 0.5:
		return "land"
	if speed < 0.4:
		return "idle"
	if speed < Sim.WALK_SPEED + 1.5:
		return "walk"
	return "run"


func _done() -> bool:
	var a := _clip("S")
	return _frame >= a.frames - 1


## Which of the 8 views to show: 0 = Pip faces the camera (S), 90 deg = faces screen-right (E), 180 = back (N).
func _dir_for(cam: Camera3D) -> String:
	if cam == null:
		return "S"
	var facing := Vector3(-sin(yaw), 0, -cos(yaw))
	var to_cam := cam.global_position - global_position
	to_cam.y = 0.0
	if to_cam.length_squared() < 1e-6:
		return "N"
	to_cam = to_cam.normalized()
	var right := cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var ang := atan2(facing.dot(right), facing.dot(to_cam))
	var f := ang / (PI / 4.0)
	# hysteresis: keep the current view until the angle is clearly into the next one, so Pip doesn't flicker
	if _dir_i >= 0:
		var d := fposmod(f - _dir_i + 4.0, 8.0) - 4.0
		if absf(d) < 0.62:
			return DIRS[_dir_i]
	_dir_i = posmod(int(round(f)), 8)
	return DIRS[_dir_i]


func _clip(dir: String) -> Dictionary:
	var by_dir: Dictionary = _anims.get(_anim, _anims["idle"])
	var d: String = MIRROR.get(dir, dir)
	if by_dir.has(d):
		return by_dir[d]
	return by_dir.values()[0]


func _show(cam: Camera3D = null) -> void:
	var dir := _dir_for(cam)
	var a := _clip(dir)
	var f := mini(_frame, a.frames - 1)
	var tex: Texture2D = _tex[a.sheet]
	if sprite.texture != tex:
		sprite.texture = tex
	sprite.region_rect = Rect2(f * _cell.x, a.row * _cell.y, _cell.x, _cell.y)
	var by_dir: Dictionary = _anims.get(_anim, _anims["idle"])
	sprite.flip_h = MIRROR.has(dir) and by_dir.has(MIRROR[dir])
	if _accent:   # the costume's accent, in this player's colour, exactly over the same frame
		_accent.visible = _tex.size() > 2
		if _accent.visible:
			_accent.texture = _tex[2 + int(a.sheet)]
			_accent.region_rect = sprite.region_rect
			_accent.flip_h = sprite.flip_h


## v0.8.1: the weapon he has out is in his hand in every frame (not only while he attacks), drawn in his own pixel
## style (assets/pip/carry, made by tools/make_garb_sheets.py) and held at his hand: where his hands are in every frame
## of every animation is in assets/pip/garb/pip-hands.json. The sword hangs at his side, the club too, the bow is held
## upright, the slingshot in his fist, the staff upright like a walking staff (it bobs with his steps, rises with
## each spell's gesture, and goes up over his head for the shield), the wand pointing down. The attack frames have the
## weapon drawn in already, so it's hidden during those.
static var _hands := {}
static var _carry_meta := {}
static var _carry_tex := {}
const CARRY := { Weapons.SWORD: "sword", Weapons.CLUB: "club", Weapons.BOW: "bow", Weapons.SLING: "sling",
	Weapons.STAFF: "staff", Weapons.WAND: "wand" }
const DRAWN_IN := ["c_swing", "c_back", "c_smash", "wc_swing", "wc_back", "rc_swing", "ac_swing", "s_swing", "s_back",
	"s_smash", "ws_swing", "ws_back", "rs_swing", "as_swing", "bowDraw", "bowShot", "slingDraw", "slingShot"]
var _carry_w := -1
var _carry_px := Vector2.ZERO        # the weapon's grip in its sprite (pixels)
var _carry_mirror := false


static func _load_carry() -> void:
	if not _hands.is_empty():
		return
	var f := FileAccess.open("res://assets/pip/garb/pip-hands.json", FileAccess.READ)
	_hands = JSON.parse_string(f.get_as_text())
	var g := FileAccess.open("res://assets/pip/carry/carry.json", FileAccess.READ)
	_carry_meta = JSON.parse_string(g.get_as_text())
	for nm in _carry_meta.keys():
		_carry_tex[nm] = [load("res://assets/pip/carry/%s.png" % nm), load("res://assets/pip/carry/%s-m.png" % nm)]


func _update_prop(delta: float) -> void:
	_load_carry()
	var w := state.weapon if state != null and state.dead == 0 else -1
	var nm: String = CARRY.get(w, "")
	if nm == "" or _anim in DRAWN_IN or not model.visible:
		_carry.visible = false
		return
	var cam := _cam
	var dir := _dir_for(cam)
	var cell_dir: String = MIRROR.get(dir, dir)
	var a := _clip(dir)
	var key := "%d:%d" % [a.row, mini(_frame, a.frames - 1)]
	var sheet := "pip-spritesheet" if int(a.sheet) == 0 else "pip-weapons"
	var hv: Array = (_hands.get(sheet, {}) as Dictionary).get(key, [-1, -1, -1, -1])
	# which hand: the one on screen-left facing us (S, SE), the one on the right otherwise
	var use_left := cell_dir in ["S", "SE"]
	var hx := float(hv[0] if use_left else hv[2])
	var hy := float(hv[1] if use_left else hv[3])
	if hx < 0.0:
		hx = _anchor.x + (-8.0 if use_left else 8.0)
		hy = _anchor.y - 14.0
	# v0.8.2: held beside him, not across his body: a couple of pixels out from his middle on the hand's side (from
	# behind, the staff used to sit across his back)
	hx += 2.0 if hx >= _anchor.x else -2.0
	if cell_dir == "E":   # side on: carried a little ahead of him, not across his face
		hx = maxf(hx, _anchor.x) + 5.0
	var mirror_view := sprite.flip_h
	if mirror_view:
		hx = _cell.x - 1 - hx
	# the weapon points outward from the hand: away from the body on screen
	var mirror_img := use_left != mirror_view
	var m: Dictionary = _carry_meta[nm]
	var grip := Vector2(float(m.grip[0]), float(m.grip[1]))
	var size := Vector2(float(m.size[0]), float(m.size[1]))
	if mirror_img:
		grip.x = size.x - 1 - grip.x
	_carry.texture = _carry_tex[nm][1 if mirror_img else 0]
	_carry.offset = Vector2(size.x / 2.0 - grip.x - 0.5, grip.y - size.y / 2.0 + 0.5)
	_carry_px = grip
	_carry_mirror = mirror_img
	var right := Vector3(1, 0, 0)
	var toward := Vector3(0, 0, 1)
	if cam:
		right = cam.global_transform.basis.x
		right.y = 0.0
		right = right.normalized() if right.length() > 0.01 else Vector3(1, 0, 0)
		toward = cam.global_transform.basis.z
		toward.y = 0.0
		toward = toward.normalized() if toward.length() > 0.01 else Vector3(0, 0, 1)
	var lift := 0.0
	var side := 0.0
	# the staff and wand move through each spell's gesture; the staff goes up over his head for the shield
	if (w == Weapons.STAFF or w == Weapons.WAND) and state.atk > 0:
		var sp := Weapons.spell(w, state.spell)
		var pose := CastPose.at(w, str(sp.name), float(int(sp.cast) - state.atk), float(sp.windup), float(sp.cast))
		lift = float(pose.lift) * 0.7 - float(pose.crouch)
		side = float(pose.reach) * 0.18 * (-1.0 if use_left != mirror_view else 1.0)
		if float(pose.crouch) > 0.12:
			_v_sq -= 0.3   # a slam jolts him down
	if w == Weapons.STAFF and state.shield > 0:
		hx = _anchor.x + (-3.0 if use_left != mirror_view else 3.0)
		hy = _anchor.y - 40.0
		lift = 0.05 * sin(Time.get_ticks_msec() * 0.03)
	var px := (hx - _anchor.x) * PIXEL * sprite.scale.x
	var py := (_anchor.y - hy) * PIXEL * sprite.scale.y
	# in front of him: a clear 12 cm toward the camera (it used to be 3 cm, which could lose the depth test to his body
	# sprite at some camera angles and put the weapon behind him), and sorted after him too
	_carry.position = sprite.position + right * (px + side) + Vector3(0, py + lift, 0) + toward * 0.12
	_carry.visible = true


## The procedural layer over the drawn frames: squash and stretch, the forward jolt on blows and the kick back on
## shots, dust under running feet, afterimages behind a dash.
func _procedural(delta: float, speed: float) -> void:
	if delta <= 0.0:
		return
	var st := state
	# blows: a jolt forward as the hit lands; shots: a kick back as the string lets go
	if st != null and st.dead == 0 and Weapons.is_melee(st.weapon) and st.atk > 0:
		var mv := Weapons.move(st.weapon, st.combo)
		var into := int(mv.swing) - st.atk
		if into == int(mv.windup) - 1:
			_v_nudge += 2.4 if st.weapon != Weapons.FISTS else 1.4
			_v_sq -= 1.2 if st.weapon == Weapons.CLUB else 0.6
	if st != null and Weapons.is_ranged(st.weapon) and st.swing_n != _shot_seen:
		if _shot_seen != -1 and st.charge == 0 and st.atk > 0:
			_v_nudge -= 1.6
			_v_sq += 0.8
		_shot_seen = st.swing_n
	if st != null and st.charge > 0 and Weapons.is_ranged(st.weapon):   # leaning into the draw
		_sq = lerpf(_sq, 0.97, clampf(delta * 6.0, 0.0, 1.0))
	var sq := FigureAvatar.spring_f(_sq, _v_sq, 1.0, 0.09, delta)
	_sq = clampf(sq[0], 0.7, 1.3)
	_v_sq = sq[1]
	var nd := FigureAvatar.spring_f(_nudge, _v_nudge, 0.0, 0.08, delta)
	_nudge = clampf(nd[0], -0.25, 0.3)
	_v_nudge = nd[1]
	# dashes stretch him along the way he's going (wider, shorter)
	var dash_k := 0.12 if dashing else 0.0
	sprite.scale = Vector3((1.0 / sqrt(_sq)) + dash_k, _sq - dash_k * 0.6, 1.0)
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	sprite.position = Vector3(sprite.position.x, 0, 0) + fwd * _nudge
	if _accent and _accent.visible:   # just in front of the sprite, so it wins the depth test
		var toward := Vector3(0, 0, 1)
		if _cam:
			toward = _cam.global_transform.basis.z
			toward.y = 0.0
			toward = toward.normalized() if toward.length() > 0.01 else Vector3(0, 0, 1)
		_accent.scale = sprite.scale
		_accent.position = sprite.position + toward * 0.004
	# dust from running feet and the dash's afterimages
	var parent := get_parent()
	if parent == null or not model.visible:
		return
	if grounded and speed > Sim.WALK_SPEED * 0.9 and not dashing:
		_step_d += speed * delta
		if _step_d > 1.15:
			_step_d = 0.0
			MotionFx.puff(parent, position, 2 + int(speed > Sim.SPRINT_SPEED - 1.0), 0.6)
	if dashing:
		_ghost_t -= delta
		if _ghost_t <= 0.0:
			_ghost_t = 0.03
			MotionFx.ghost_sprite(parent, sprite, label.modulate)
			if grounded:
				MotionFx.puff(parent, position, 2, 1.2)


## Landing: squash by how hard he came down, and a ring of dust.
func _land(fall: float) -> void:
	_v_sq -= clampf(fall * 0.35, 0.8, 5.0)
	if fall > 4.0 and get_parent() != null and model.visible:
		MotionFx.land(get_parent(), position, clampf(fall / 14.0, 0.3, 1.4))


# ================================================================ the wizard garb
## Pip's head and body move from frame to frame, so where the hat, hood and robe go is read off the frame drawn now:
## the first row of the head, the middle of the head, and the shoulders (cached per frame).
static var _imgs: Array = []
static var _scan := {}


static func _cell_info(sheet: int, row: int, frame: int) -> Array:
	var key := sheet * 1000000 + row * 1000 + frame
	if _scan.has(key):
		return _scan[key]
	if _imgs.is_empty():
		for t in _textures:
			var im: Image = (t as Texture2D).get_image()
			if im.is_compressed():
				im.decompress()
			_imgs.append(im)
	var im: Image = _imgs[sheet]
	var x0 := frame * _cell.x
	var y0 := row * _cell.y
	var top := -1
	for y in _cell.y:
		var n := 0
		for x in _cell.x:
			if im.get_pixel(x0 + x, y0 + y).a > 0.5:
				n += 1
		if n >= 5:
			top = y
			break
	if top < 0:
		top = int(_anchor.y) - 42
	var neck := mini(top + 21, int(_anchor.y) - 6)
	var out := [top, _mean_x(im, x0, y0, top, top + 10), neck, _mean_x(im, x0, y0, neck, neck + 8)]
	_scan[key] = out
	return out


static func _mean_x(im: Image, x0: int, y0: int, ya: int, yb: int) -> float:
	var sum := 0.0
	var n := 0
	for y in range(maxi(ya, 0), mini(yb, _cell.y)):
		for x in _cell.x:
			if im.get_pixel(x0 + x, y0 + y).a > 0.5:
				sum += x
				n += 1
	return sum / n if n > 0 else _anchor.x


func _dress(_delta: float, cam: Camera3D) -> void:
	var k := WizardGarb.kind_for(state)
	if k != _garb_kind:
		var first := _garb_kind == 0
		_garb_kind = k
		# v0.9.0: his costume is painted into his sheets: one per weapon, switching with the weapon in his hand
		_tex = garb_textures(WizardGarb.LOOK.get(k, "brawler")) if k != WizardGarb.Kind.NONE else outfit_textures(_outfit)
		_show(cam)
		if not first and get_parent() != null and model.visible:   # a puff as it changes: sparkles for magic, dust
			var magic := k == WizardGarb.Kind.WIZARD or k == WizardGarb.Kind.SHADOW
			Fx.burst(get_parent(), position + Vector3(0, 1.0, 0), Vector3.UP, Color("c9a8ff") if magic else Color("e8dcc0"), 22, 3.0, 0.045)
			MotionFx.puff(get_parent(), position + Vector3(0, 0.3, 0), 6, 1.2)


## Where the staff's (or wand's) orb is now (for the shield pouring out of it); null without one.
func orb_position():
	if _carry == null or not _carry.visible or not (_carry_w in [Weapons.STAFF, Weapons.WAND]) and not (state != null and state.weapon in [Weapons.STAFF, Weapons.WAND]):
		return null
	var nm: String = CARRY.get(state.weapon if state != null else -1, "")
	if nm == "" or not (_carry_meta.get(nm, {}) as Dictionary).has("orb"):
		return null
	var m: Dictionary = _carry_meta[nm]
	var orb := Vector2(float(m.orb[0]), float(m.orb[1]))
	if _carry_mirror:
		orb.x = float(m.size[0]) - 1 - orb.x
	var right := Vector3(1, 0, 0)
	if _cam:
		right = _cam.global_transform.basis.x
		right.y = 0.0
		right = right.normalized()
	return _carry.global_position + right * (orb.x - _carry_px.x) * PIXEL + Vector3(0, (_carry_px.y - orb.y) * PIXEL, 0)

