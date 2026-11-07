## v0.13.0 what every screen shows of Smiguel (see SmiguelPeek for when and where):
##   - "smiguel_peek": he's there, half out from behind his cover (Avatar with the "smiguel" skin, no name, no ring),
##     behind the players (SmiguelPeek only picks spots they have their backs to), still, watching; the cover itself
##     hides the rest of him (it's drawn in front of him: nothing special needed);
##   - "smiguel_duck": he slips back behind it in a blink and is gone (if he was looked at: a whispered giggle, very
##     quiet, from where he was);
##   - "smiguel_say": a player or unit playing as Smiguel mutters one of his lines (assets/smiguel/line_NN.wav: original
##     lines, made with Windows' speech voice and the same raspy treatment as the prize's voice), from where they stand;
##   - "unlocked": "You unlocked Smiguel!" for the one who did.
class_name SmiguelView
extends Node3D

const LINES_DIR := "res://assets/smiguel/"
const LINE_COUNT := 12
const IN_T := 0.35       # seconds to slide back behind the cover
const LEAN := 0.9        # m he slides back toward the cover's middle as he hides
const TILT := 13.0       # degrees he leans out (the top of him away from the cover)
const PIC_H := 1.95      # m: the portrait's height (assets/smiguel/peek.png; tools/make_smiguel_peek.py)

var net: Net
var main: Node
var av: Avatar           # (unused for the peek since the portrait; kept for a spawned Smiguel's look)
var pic: MeshInstance3D  # the portrait leaning out from behind the cover
var _cover := Vector3.ZERO
var _lean := 0.0         # degrees now
var _state := ""         # "", "out", "watch", "in"
var _t := 0.0
var _pos := Vector3.ZERO
var _from := Vector3.ZERO
var _yaw := 0.0
var _lines: Array = []
var _giggle: AudioStream
var shown := false       # (tests)


func setup(n: Net, m: Node) -> void:
	net = n
	main = m
	net.magic_fx.connect(_on_fx)
	for i in LINE_COUNT:
		var p := LINES_DIR + "line_%02d.wav" % (i + 1)
		_lines.append(load(p) if ResourceLoader.exists(p) else null)
	_giggle = load(LINES_DIR + "giggle.wav") if ResourceLoader.exists(LINES_DIR + "giggle.wav") else null


## v0.13.1 YOUR OWN PEEK PICTURE: put a picture called smiguel_peek.png (or .jpg / .webp) in the "prize" folder next
## to the game's exe (or in user://prize/), and it peeks instead of the built-in one. It's read when the game starts,
## only on this computer (each player sees their own, or the built-in one). It stands PIC_H (1.95 m) tall, its width
## from its proportions, its bottom edge on the ground. A picture with no see-through pixels gets a plain light
## background removed (everything light and colourless joined to its edges); empty margins are trimmed.
const CUSTOM := ["smiguel_peek.png", "smiguel_peek.jpg", "smiguel_peek.jpeg", "smiguel_peek.webp"]
static var custom_path := ""   # (the file it used, for the console and tests)


static func custom_picture() -> Texture2D:
	var dirs := [OS.get_executable_path().get_base_dir().path_join("prize"), ProjectSettings.globalize_path("user://prize")]
	if not OS.has_feature("template"):
		dirs.append(ProjectSettings.globalize_path("res://").path_join("prize"))
	for d in dirs:
		for n in CUSTOM:
			var fp: String = d.path_join(n)
			if FileAccess.file_exists(fp):
				var img := Image.load_from_file(fp)
				if img == null or img.is_empty():
					continue
				img.convert(Image.FORMAT_RGBA8)
				img = prepare(img)
				custom_path = fp
				print("Smiguel's peek picture: ", fp)
				return ImageTexture.create_from_image(img)
	return null


## Remove a plain light background (only when the picture has no see-through pixels at all), then trim empty margins,
## and keep it to at most 1024 px tall.
static func prepare(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var has_alpha := false
	for y in range(0, h, maxi(h / 64, 1)):
		for x in range(0, w, maxi(w / 64, 1)):
			if img.get_pixel(x, y).a < 0.5:
				has_alpha = true
				break
		if has_alpha:
			break
	if not has_alpha:   # flood the light, colourless background in from the edges
		var seen := PackedByteArray()
		seen.resize(w * h)
		var stack: Array[Vector2i] = []
		for x in w:
			stack.append(Vector2i(x, 0))
			stack.append(Vector2i(x, h - 1))
		for y in h:
			stack.append(Vector2i(0, y))
			stack.append(Vector2i(w - 1, y))
		while not stack.is_empty():
			var q: Vector2i = stack.pop_back()
			if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h or seen[q.y * w + q.x]:
				continue
			seen[q.y * w + q.x] = 1
			var c := img.get_pixelv(q)
			if c.v < 0.86 or c.s > 0.12:
				continue
			img.set_pixelv(q, Color(c.r, c.g, c.b, 0.0))
			stack.append(q + Vector2i(1, 0))
			stack.append(q + Vector2i(-1, 0))
			stack.append(q + Vector2i(0, 1))
			stack.append(q + Vector2i(0, -1))
	var used := img.get_used_rect()
	if used.size.x > 0 and used.size.y > 0 and used.size != img.get_size():
		img = img.get_region(used)
	if img.get_height() > 1024:
		img.resize(int(img.get_width() * 1024.0 / img.get_height()), 1024, Image.INTERPOLATE_LANCZOS)
	return img


func _ensure() -> void:
	if pic != null:
		return
	var tex: Texture2D = custom_picture()
	if tex == null:
		tex = load("res://assets/smiguel/peek.png")
	var q := QuadMesh.new()
	var w := PIC_H * float(tex.get_width()) / float(tex.get_height())
	q.size = Vector2(w, PIC_H)
	q.center_offset = Vector3(0, PIC_H / 2.0, 0)   # its pivot at his feet: he leans from there
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST if custom_path == "" else BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	pic = MeshInstance3D.new()
	pic.name = "SmiguelPeeker"
	pic.mesh = q
	pic.material_override = m
	pic.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pic.visible = false
	add_child(pic)


func _on_fx(kind: String, a: Array) -> void:
	match kind:
		"smiguel_peek":
			_ensure()
			_pos = a[0]
			_yaw = float(a[1])
			_cover = a[3] if a.size() > 3 else _pos
			# where he slides back to as he hides: toward the cover's middle, across the players' view
			var to_c := Vector3(_cover.x - _pos.x, 0, _cover.z - _pos.z)
			var across := Vector3(cos(_yaw), 0, -sin(_yaw))
			_from = _pos + across * signf(to_c.dot(across)) * LEAN
			# (Jacob: "he shouldn't just pop out... while the players are looking at it": he only appears behind them,
			# so he's simply already there, leaning out, when they turn round)
			_state = "watch"
			_t = 0.0
			_lean = TILT
			pic.visible = true
			pic.position = _pos
		"smiguel_duck":
			if pic == null or _state == "":
				return
			_state = "in"
			_t = 0.0
			if str(a[1]) in ["look", "seen"] and _giggle != null:
				_play(_giggle, pic.position, -14.0, 0.95)
		"smiguel_say":
			var id := int(a[0])
			var n := int(a[1]) % LINE_COUNT
			var avs: Dictionary = main.get("avatars")
			if avs.has(id) and _lines[n] != null:
				_play(_lines[n], (avs[id] as Node3D).position + Vector3(0, 1.4, 0), -4.0, 1.0, avs[id])
		"unlocked":
			if int(a[0]) == net.my_id and str(a[1]) == "smiguel":
				main.toast("¡You unlocked SMIGUEL! Play as him: Esc > Character")


func _play(st: AudioStream, at: Vector3, db: float, pitch: float, follow: Node3D = null) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.volume_db = db
	p.pitch_scale = pitch
	p.unit_size = 9.0
	p.max_distance = 60.0
	p.bus = "Voice" if AudioServer.get_bus_index("Voice") >= 0 else "Master"
	(follow if follow != null else self).add_child(p)
	if follow != null:
		p.position = Vector3(0, 1.4, 0)
	else:
		p.global_position = at
	p.play()
	p.finished.connect(p.queue_free)


func update(delta: float, cam: Camera3D) -> void:
	if pic == null or _state == "":
		shown = false
		return
	_t += delta
	match _state:
		"watch":
			pic.position = _pos
		"in":   # slide back behind the cover, straightening up
			var k := clampf(_t / IN_T, 0.0, 1.0)
			k = k * k
			pic.position = _pos.lerp(_from, k)
			_lean = TILT * (1.0 - k)
			if _t >= IN_T:
				_state = ""
				pic.visible = false
	shown = pic.visible
	if cam != null and pic.visible:
		# face the camera (upright), leaning out: the top of him away from the cover, as this screen sees it
		var to_cam := cam.global_position - pic.global_position
		var face := atan2(to_cam.x, to_cam.z)
		var right := Vector3(cos(face), 0, -sin(face))
		var out_side := signf((pic.position - _cover).dot(right))
		if out_side == 0.0:
			out_side = 1.0
		pic.basis = Basis.from_euler(Vector3(0, face, -deg_to_rad(_lean) * out_side))
