## A player on screen, drawn as Pip (Jacob's sprite character from 04-games/pip): a pixel-art billboard that stands
## upright, picks the view (S, SE, E, NE, N drawn; SW, W, NW mirrored) from where the camera is relative to the way
## the player faces, and plays the animation that matches what the player is doing: idle, walk, run (sped up with
## speed), dash, jump start, in the air, land. Every client animates every player from movement it already has, so
## animation adds no network traffic.
class_name Avatar
extends Node3D

const SHEET := "res://assets/pip/pip-spritesheet.png"
const META := "res://assets/pip/pip-spritesheet.json"
const PIXEL := 0.04          # metres per sprite pixel: Pip (~45 px) stands ~1.8 m
const DIRS := ["S", "SE", "E", "NE", "N", "NW", "W", "SW"]   # clockwise from facing the camera
const MIRROR := {"SW": "SE", "W": "E", "NW": "NE"}

static var _texture: Texture2D
static var _anims := {}   # name -> { dir -> { row, frames, durations (s), loop } }
static var _cell := Vector2i(64, 64)
static var _anchor := Vector2(32, 58)

var yaw := 0.0
var grounded := true
var dashing := false

var model: Node3D         # hidden for your own player in first person
var sprite: Sprite3D
var blob: MeshInstance3D  # coloured ring / shadow at the feet
var label: Label3D

var _anim := "idle"
var _frame := 0
var _frame_t := 0.0
var _speed_scale := 1.0
var _last := Vector3.ZERO
var _vel := Vector3.ZERO
var _have_last := false
var _was_grounded := true
var _landing := 0.0


static func _load_sheet() -> void:
	if _texture != null:
		return
	_texture = load(SHEET)
	var f := FileAccess.open(META, FileAccess.READ)
	var meta: Dictionary = JSON.parse_string(f.get_as_text())
	_cell = Vector2i(int(meta.cell.w), int(meta.cell.h))
	_anchor = Vector2(float(meta.anchor.x), float(meta.anchor.y))
	for a in meta.animations:
		var by_dir: Dictionary = _anims.get(a.name, {})
		var durs := PackedFloat32Array()
		for ms in a.durationsMs:
			durs.append(float(ms) / 1000.0)
		by_dir[a.dir] = { "row": int(a.row), "frames": int(a.frames), "durations": durs, "loop": bool(a.loop) }
		_anims[a.name] = by_dir


func _init(player_name: String, color: Color, show_name: bool) -> void:
	_load_sheet()
	model = Node3D.new()
	add_child(model)
	sprite = Sprite3D.new()
	sprite.texture = _texture
	sprite.region_enabled = true
	sprite.pixel_size = PIXEL
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y   # stays upright, turns to face the camera
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST  # crisp pixels
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.shaded = false
	sprite.double_sided = true
	# put Pip's feet (the sheet's anchor) on the node's origin
	sprite.centered = true
	sprite.offset = Vector2(_cell.x / 2.0 - _anchor.x, _anchor.y - _cell.y / 2.0) * Vector2(1, 1)
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
	blob.top_level = true  # placed in world space, on whatever is underneath
	add_child(blob)

	label = Label3D.new()
	label.text = player_name
	label.modulate = color.lightened(0.35)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.2
	label.font_size = 44
	label.outline_size = 12
	label.no_depth_test = true
	label.visible = show_name
	add_child(label)
	_show()


## Call every frame after setting position, yaw, grounded and dashing.
func animate(delta: float, cam: Camera3D) -> void:
	if not _have_last:
		_last = position
		_have_last = true
	if delta > 0.0:
		var v := (position - _last) / delta
		_vel = _vel.lerp(v, clampf(delta * 12.0, 0.0, 1.0))
	_last = position
	var speed := Vector2(_vel.x, _vel.z).length()

	# choose the animation from what the player is doing
	var want := _anim
	if dashing:
		want = "dash"
	elif not grounded:
		if _was_grounded or (_anim != "jumpStart" and _anim != "air"):
			want = "jumpStart"
		elif _anim == "jumpStart" and _done():
			want = "air"
	else:
		if not _was_grounded:
			_landing = 0.21
		if _landing > 0.0 and speed < Sim.WALK_SPEED * 0.5:
			want = "land"
		elif speed < 0.4:
			want = "idle"
		elif speed < Sim.WALK_SPEED + 1.5:
			want = "walk"
		else:
			want = "run"
	_landing = maxf(_landing - delta, 0.0)
	_was_grounded = grounded
	if want != _anim:
		_anim = want
		_frame = 0
		_frame_t = 0.0
	_speed_scale = clampf(speed / Sim.WALK_SPEED, 0.6, 1.6) if _anim == "walk" else (clampf(speed / Sim.SPRINT_SPEED, 0.7, 1.4) if _anim == "run" else 1.0)

	# advance the frame
	var a := _clip(_dir_for(cam))
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

	# the ring sits on the surface below and shrinks with height above it
	var ground := WorldLayout.ground_height(position.x, position.z, position.y)
	blob.global_position = Vector3(position.x, ground + 0.012, position.z)
	var s := clampf(1.0 - (position.y - ground) / 6.0, 0.35, 1.0)
	blob.scale = Vector3(s, 1, s)


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
	var i := posmod(int(round(ang / (PI / 4.0))), 8)
	return DIRS[i]


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
	sprite.region_rect = Rect2(f * _cell.x, a.row * _cell.y, _cell.x, _cell.y)
	sprite.flip_h = MIRROR.has(dir)
