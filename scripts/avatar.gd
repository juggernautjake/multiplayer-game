## A player on screen, drawn as Pip (Jacob's sprite character from 04-games/pip): a pixel-art billboard that stands
## upright, picks the view (S, SE, E, NE, N drawn; SW, W, NW mirrored) from where the camera is relative to the way
## the player faces, and plays the animation that matches the player's state: idle, walk, run, dash, jump, air, land,
## club and sword swings (standing, walking, running, in the air), bow and slingshot draw and release, knocked down.
## Every client animates every player from the state it already has, so animation adds no network traffic.
class_name Avatar
extends Node3D

const SHEETS := [["res://assets/pip/pip-spritesheet.png", "res://assets/pip/pip-spritesheet.json"],
	["res://assets/pip/pip-weapons.png", "res://assets/pip/pip-weapons.json"]]
const PIXEL := 0.04          # metres per sprite pixel: Pip (~45 px) stands ~1.8 m
const DIRS := ["S", "SE", "E", "NE", "N", "NW", "W", "SW"]   # clockwise from facing the camera
const MIRROR := {"SW": "SE", "W": "E", "NW": "NE"}

static var _textures: Array = []
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


func _init(player_name: String, color: Color, show_name: bool) -> void:
	_load_sheets()
	model = Node3D.new()
	add_child(model)
	sprite = Sprite3D.new()
	sprite.texture = _textures[0]
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
	_show()


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
	if _hitstop > 0.0:
		_hitstop -= delta
		sprite.position.x = randf_range(-0.03, 0.03) if _hit_shake else 0.0
		if _hitstop <= 0.0:
			sprite.position.x = 0.0
			_hit_shake = false
		return
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
	if _anim.ends_with("Draw") and state != null:
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

	_flash = maxf(_flash - delta, 0.0)
	sprite.modulate = Color(1, 0.45, 0.45) if _flash > 0.0 else Color.WHITE
	if state != null:
		var k := float(state.hp) / float(Sim.MAX_HP)
		hp_bar.scale.x = maxf(0.9 * k, 0.001)
		hp_bar.modulate = Color(0.9, 0.2, 0.2).lerp(Color(0.3, 0.9, 0.3), k)
		hp_bar.visible = label.visible and state.dead == 0

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
		if not melee:
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
		_was_grounded = false
		return r
	if not _was_grounded:
		_landing = 0.21
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
	var tex: Texture2D = _textures[a.sheet]
	if sprite.texture != tex:
		sprite.texture = tex
	sprite.region_rect = Rect2(f * _cell.x, a.row * _cell.y, _cell.x, _cell.y)
	var by_dir: Dictionary = _anims.get(_anim, _anims["idle"])
	sprite.flip_h = MIRROR.has(dir) and by_dir.has(MIRROR[dir])
