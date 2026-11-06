## The end of the boss fight on screen (v0.10.0).
##
## Victory: confetti and "CONGRATULATIONS!", then "Now that you have beaten the boss, you get the final prize!",
## "Are you ready for your prize?", "Here it comes!" -- and the prize: a full-screen fiesta for Smiguel el Magnifico,
## ported from LoadingFiesta in Jacob's 4X game. He slams in, bobs on the band's 165 bpm beat and sways; a trumpet
## blares, maracas shake, mariachi music plays; papel picado flags hang along the top, zarape stripes roll behind,
## maracas orbit, confetti falls; the music's credit sits at the bottom. Any key ends it.
##
## The picture of Smiguel isn't part of the game (it isn't ours to publish): it's read at runtime from
## prize/smiguel_el_magnifico.png next to the game's exe (or user://prize/). Without it, a drawn stand-in -- a big
## sombrero and moustache -- takes his place.
##
## Defeat: "Awww, you didn't get the final prize! And you died! Better luck next time..." with a sad trombone; any key
## starts again (Net.ask_restart): back at the spawn with full health, levels kept, the altar ready.
class_name PrizeScreen
extends CanvasLayer

const BPM := 165.0
const PIC := "smiguel_el_magnifico.png"
const CREDIT := "Music: \"Mariachi Snooze\" Kevin MacLeod (incompetech.com) — CC BY 3.0"
const LINES := ["CONGRATULATIONS!", "Now that you have beaten the boss, you get the final prize!",
	"Are you ready for your prize?", "Here it comes!"]

enum Mode { NONE, VICTORY, FIESTA, DEFEAT }

var net: Net
var mode := Mode.NONE
var t := 0.0
var line := -1
var canvas: Control         # draws the stripes, flags, maracas, confetti, stand-in
var title: Label
var sub: Label
var credit: Label
var pic: TextureRect
var pic_tex: Texture2D
var confetti: Array = []    # [pos, vel, colour, spin, size]
var music: AudioStreamPlayer
var shakers: AudioStreamPlayer
var hint: Label
var ready_at := 0.0         # keys count only after this (so a key held in the fight doesn't skip it)
var mouse_before := Input.MOUSE_MODE_VISIBLE
const CONFETTI := [Color("e63946"), Color("f4a261"), Color("e9c46a"), Color("2a9d8f"), Color("8338ec"), Color("ff006e"), Color("3a86ff"), Color("06d6a0")]
const ZARAPE := [Color("d62828"), Color("f77f00"), Color("fcbf49"), Color("2a9d8f"), Color("6a4c93"), Color("e63946"), Color("1d3557"), Color("06d6a0")]


func setup(n: Net) -> void:
	net = n
	layer = 50
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	canvas = Control.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.draw.connect(_draw_canvas)
	add_child(canvas)
	pic = TextureRect.new()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.visible = false
	add_child(pic)
	title = _label(72, Color("ffd23f"), 14)
	sub = _label(36, Color.WHITE, 10)
	credit = _label(18, Color(1, 1, 1, 0.9), 6)
	credit.text = CREDIT
	hint = _label(20, Color(1, 1, 1, 0.75), 6)
	music = AudioStreamPlayer.new()
	add_child(music)
	shakers = AudioStreamPlayer.new()
	shakers.volume_db = -8.0
	add_child(shakers)
	net.boss_result.connect(_on_result)


func _label(size: int, col: Color, outline: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _on_result(kind: String) -> void:
	match kind:
		"victory":
			start_victory()
		"defeat":
			start_defeat()
		"restart":
			if mode == Mode.DEFEAT:
				close()


## Where the prize picture is looked for, in order: prize/ next to the exe, prize/ next to the project when run from
## the editor, then user://prize/.
static func picture_paths() -> Array:
	var out := [OS.get_executable_path().get_base_dir().path_join("prize").path_join(PIC)]
	if not OS.has_feature("template"):
		out.append(ProjectSettings.globalize_path("res://").path_join("prize").path_join(PIC))
	out.append(ProjectSettings.globalize_path("user://prize").path_join(PIC))
	return out


static func load_picture() -> Texture2D:
	if OS.get_cmdline_user_args().has("--no-prize-pic"):   # testing: the stand-in
		return null
	for p in picture_paths():
		if FileAccess.file_exists(p):
			var img := Image.load_from_file(p)
			if img != null and not img.is_empty():
				return ImageTexture.create_from_image(img)
	return null


func _open() -> void:
	visible = true
	t = 0.0
	confetti.clear()
	mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ready_at = 1.2


func close() -> void:
	visible = false
	mode = Mode.NONE
	music.stop()
	shakers.stop()
	pic.visible = false
	if mouse_before == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func start_victory() -> void:
	_open()
	mode = Mode.VICTORY
	line = 0
	_burst_confetti(220)
	Synth.play(self, Synth.trumpet(), -6.0)


func start_fiesta() -> void:
	mode = Mode.FIESTA
	t = 0.0
	ready_at = 1.0
	pic_tex = load_picture()
	pic.texture = pic_tex
	pic.visible = pic_tex != null
	var mp := load("res://assets/audio/mariachi.mp3") as AudioStream
	if mp is AudioStreamMP3:
		(mp as AudioStreamMP3).loop = true
	music.stream = mp
	music.volume_db = -3.0
	music.play()
	shakers.stream = Synth.maracas()
	shakers.play()
	Synth.play(self, Synth.trumpet(), -2.0)
	_burst_confetti(300)


func start_defeat() -> void:
	_open()
	mode = Mode.DEFEAT
	Synth.play(self, Synth.sad_trombone(), -2.0)


func _burst_confetti(n: int) -> void:
	var sz := canvas.size if canvas.size.x > 0 else Vector2(1280, 720)
	for i in n:
		confetti.append([Vector2(randf() * sz.x, -randf() * sz.y * 0.6), Vector2(randf_range(-60, 60), randf_range(60, 220)),
			CONFETTI[randi() % CONFETTI.size()], randf() * TAU, randf_range(6, 13)])


func _input(event: InputEvent) -> void:
	if mode == Mode.NONE:
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed)
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()
	if not pressed or t < ready_at:
		return
	match mode:
		Mode.VICTORY:   # a key moves the words along
			_next_line()
		Mode.FIESTA:
			close()
		Mode.DEFEAT:
			net.ask_restart()
			close()


func _next_line() -> void:
	line += 1
	t = 0.0
	ready_at = 0.4
	if line >= LINES.size():
		start_fiesta()


func _process(delta: float) -> void:
	if mode == Mode.NONE:
		return
	t += delta
	var sz := canvas.size
	for c in confetti:
		c[1].y = minf(c[1].y + 160.0 * delta, 260.0)
		c[0] += Vector2(c[1].x + sin(t * 3.0 + c[3]) * 40.0, c[1].y) * delta
		c[3] += delta * 4.0
		if mode == Mode.FIESTA and c[0].y > sz.y + 20:
			c[0] = Vector2(randf() * sz.x, -20)
	if mode != Mode.FIESTA:
		confetti = confetti.filter(func(c): return c[0].y < sz.y + 20)
	title.visible = true
	sub.visible = false
	credit.visible = mode == Mode.FIESTA
	hint.visible = t > ready_at
	match mode:
		Mode.VICTORY:
			var big := line == 0
			title.text = LINES[line]
			title.add_theme_font_size_override("font_size", 84 if big else 46)
			title.add_theme_color_override("font_color", Color("ffd23f") if big else Color.WHITE)
			var pop := 1.0 + 0.5 * maxf(0.0, 1.0 - t / 0.25)
			_place(title, Vector2(0.05, 0.3), Vector2(0.95, 0.55), pop)
			hint.text = "press any key"
			_place(hint, Vector2(0.2, 0.86), Vector2(0.8, 0.94))
			if t > (3.2 if big else 2.6):
				_next_line()
		Mode.FIESTA:
			title.text = "¡¡¡AY AY AY!!!"
			title.add_theme_font_size_override("font_size", 64)
			title.add_theme_color_override("font_color", Color("ffd23f"))
			_place(title, Vector2(0.0, 0.1), Vector2(1.0, 0.24), 1.0 + 0.06 * sin(t * TAU * BPM / 60.0))
			title.rotation = sin(t * 5.45) * deg_to_rad(4.0)
			_place(credit, Vector2(0.02, 0.93), Vector2(0.98, 0.99))
			hint.text = "press any key"
			_place(hint, Vector2(0.3, 0.87), Vector2(0.7, 0.92))
			if pic.visible:
				var h := sz.y * 0.62
				var w := h * float(pic_tex.get_width()) / float(maxi(pic_tex.get_height(), 1))
				pic.size = Vector2(w, h)
				pic.pivot_offset = pic.size / 2.0
				pic.position = Vector2(sz.x / 2.0, sz.y * 0.56) - pic.size / 2.0 + _slam_shake()
				pic.scale = Vector2.ONE * _slam_scale() * _bob()
				pic.rotation = _sway()
		Mode.DEFEAT:
			title.text = "Awww, you didn't get the final prize!\nAnd you died! Better luck next time..."
			title.add_theme_font_size_override("font_size", 44)
			title.add_theme_color_override("font_color", Color("ffb3b3"))
			title.rotation = 0.0
			_place(title, Vector2(0.05, 0.3), Vector2(0.95, 0.6), 1.0 + 0.02 * sin(t * 2.0))
			hint.text = "press any key to try again"
			_place(hint, Vector2(0.2, 0.75), Vector2(0.8, 0.83))
	canvas.queue_redraw()


func _place(l: Control, a: Vector2, b: Vector2, k := 1.0) -> void:
	var sz := canvas.size
	l.position = sz * a
	l.size = sz * (b - a)
	l.pivot_offset = l.size / 2.0
	l.scale = Vector2.ONE * k
	if l != title:
		l.rotation = 0.0


# the fiesta's motion, as in LoadingFiesta: a slam (in big, overshooting), a bob on the beat, a sway
func _slam_scale() -> float:
	if t < 0.18:
		return lerpf(3.0, 0.9, t / 0.18)
	if t < 0.35:
		return lerpf(0.9, 1.05, (t - 0.18) / 0.17)
	return lerpf(1.05, 1.0, clampf((t - 0.35) / 0.2, 0.0, 1.0))


func _slam_shake() -> Vector2:
	var k := clampf(1.0 - (t - 0.18) / 0.5, 0.0, 1.0) if t > 0.18 else 0.0
	return Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 18.0 * k


func _bob() -> float:
	return 1.0 + 0.04 * sin(t * 10.9)


func _sway() -> float:
	return deg_to_rad(sin(t * 5.45) * 6.0)


func _draw_canvas() -> void:
	var sz := canvas.size
	match mode:
		Mode.VICTORY:
			canvas.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.03, 0.02, 0.08, minf(t * 2.0, 0.55) if line == 0 else 0.62))
		Mode.DEFEAT:
			canvas.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.08, 0.0, 0.0, minf(t * 1.5, 0.75)))
			return
		Mode.FIESTA:
			_draw_zarape(sz)
			_draw_flags(sz)
			_draw_maracas(sz)
			if not pic.visible:
				_draw_stand_in(sz)
	for c in confetti:
		var s: float = c[4]
		var dx := Vector2(cos(c[3]), sin(c[3])) * s * 0.5
		var dy := Vector2(-sin(c[3]), cos(c[3])) * s * 0.3 * maxf(absf(sin(c[3] * 1.7)), 0.3)
		var p: Vector2 = c[0]
		canvas.draw_colored_polygon(PackedVector2Array([p - dx - dy, p + dx - dy, p + dx + dy, p - dx + dy]), c[2])


## Zarape stripes: bold coloured bands rolling slowly sideways, with thin dark lines between.
func _draw_zarape(sz: Vector2) -> void:
	var band := sz.y / 16.0
	var off := fmod(t * 40.0, band * ZARAPE.size())
	for i in range(-ZARAPE.size(), 18):
		var y := i * band + off
		canvas.draw_rect(Rect2(0, y, sz.x, band), ZARAPE[posmod(i, ZARAPE.size())])
		canvas.draw_rect(Rect2(0, y + band - 3, sz.x, 3), Color(0, 0, 0, 0.35))
	canvas.draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.18))


## Papel picado: sixteen paper flags on a string across the top, swinging, each with cut-out holes.
func _draw_flags(sz: Vector2) -> void:
	var n := 16
	var w := sz.x / n
	canvas.draw_line(Vector2(0, 18), Vector2(sz.x, 18), Color(0.1, 0.1, 0.1), 2.0)
	for i in n:
		var x := i * w + w * 0.08
		var swing := sin(t * 2.6 + i * 0.8) * 6.0
		var col: Color = CONFETTI[i % CONFETTI.size()]
		var fw := w * 0.84
		var fh := w * 0.95
		var pts := PackedVector2Array([Vector2(x, 18), Vector2(x + fw, 18), Vector2(x + fw + swing, 18 + fh),
			Vector2(x + fw * 0.75 + swing, 18 + fh * 0.88), Vector2(x + fw * 0.5 + swing, 18 + fh),
			Vector2(x + fw * 0.25 + swing, 18 + fh * 0.88), Vector2(x + swing, 18 + fh)])
		canvas.draw_colored_polygon(pts, col)
		for k in 3:   # the cut-outs
			var c := Vector2(x + fw * (0.25 + 0.25 * k) + swing * 0.5, 18 + fh * 0.45)
			canvas.draw_circle(c, fw * 0.08, ZARAPE[(i + 3) % ZARAPE.size()].darkened(0.2))
		canvas.draw_circle(Vector2(x + fw * 0.5 + swing * 0.7, 18 + fh * 0.72), fw * 0.06, ZARAPE[(i + 5) % ZARAPE.size()].darkened(0.2))


## Eight maracas orbiting the middle, each shaking on the beat.
func _draw_maracas(sz: Vector2) -> void:
	var c := Vector2(sz.x / 2.0, sz.y * 0.56)
	var r := Vector2(sz.x * 0.4, sz.y * 0.33)
	var beat := t * BPM / 60.0
	for i in 8:
		var a := t * 0.9 + i * TAU / 8.0
		var p := c + Vector2(cos(a) * r.x, sin(a) * r.y)
		var tilt := a + PI / 2.0 + sin(beat * TAU + i) * 0.5
		var dir := Vector2(cos(tilt), sin(tilt))
		var head: Color = CONFETTI[i]
		canvas.draw_line(p, p + dir * 46.0, Color("8a5a2b"), 8.0)
		canvas.draw_circle(p - dir * 6.0, 24.0, head)
		canvas.draw_circle(p - dir * 6.0, 24.0, Color.BLACK, false, 2.0)
		for k in 3:
			var q := p - dir * 6.0 + Vector2(-dir.y, dir.x) * (k - 1) * 10.0
			canvas.draw_circle(q, 4.0, Color.WHITE)


## Smiguel's stand-in when his picture isn't there: a huge sombrero over a round face with a grand moustache, slamming,
## bobbing and swaying like the real one.
func _draw_stand_in(sz: Vector2) -> void:
	var c := Vector2(sz.x / 2.0, sz.y * 0.58) + _slam_shake()
	var k := sz.y / 720.0 * _slam_scale() * _bob()
	canvas.draw_set_transform(c, _sway(), Vector2(k, k))
	canvas.draw_circle(Vector2(0, 50), 135, Color("d9a066"))             # the face
	canvas.draw_circle(Vector2(-42, 20), 14, Color.WHITE)
	canvas.draw_circle(Vector2(42, 20), 14, Color.WHITE)
	canvas.draw_circle(Vector2(-40, 22), 7, Color.BLACK)
	canvas.draw_circle(Vector2(44, 22), 7, Color.BLACK)
	canvas.draw_circle(Vector2(0, 56), 16, Color("c0784a"))              # the nose
	for side in [-1.0, 1.0]:   # the moustache: a grand handlebar, thick in the middle, curling up at the tips
		for i in 34:
			var u := float(i) / 33.0
			var p := Vector2(side * (8.0 + u * 120.0), 84.0 + 12.0 * sin(u * PI) - 46.0 * pow(u, 3.0))
			canvas.draw_circle(p, lerpf(22.0, 6.0, u), Color("2b1a10"))
	canvas.draw_arc(Vector2(0, 122), 30, 0.25, PI - 0.25, 16, Color("7a2a20"), 6.0)   # a big grin
	# the sombrero: a vast brim and a tall crown, with a zig-zag band
	var brim := PackedVector2Array()
	for i in 41:
		var a := PI + float(i) / 40.0 * PI
		brim.append(Vector2(cos(a) * 300, -40 + sin(a) * 50))
	for i in range(40, -1, -1):
		var a := PI + float(i) / 40.0 * PI
		brim.append(Vector2(cos(a) * 300, -40 - sin(a) * 18))
	canvas.draw_colored_polygon(brim, Color("e0b040"))
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(-110, -60), Vector2(-80, -220), Vector2(0, -250),
		Vector2(80, -220), Vector2(110, -60)]), Color("e8bf4a"))
	var zig := PackedVector2Array()
	for i in 12:
		zig.append(Vector2(lerpf(-104, 104, i / 11.0), -96 if i % 2 == 0 else -76))
	canvas.draw_polyline(zig, Color("d62828"), 10.0)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var lbl := "SMIGUEL EL MAGNÍFICO"
	var f := ThemeDB.fallback_font
	var w := f.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	canvas.draw_string_outline(f, Vector2(sz.x / 2.0 - w / 2.0, sz.y * 0.87), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, 10, Color.BLACK)
	canvas.draw_string(f, Vector2(sz.x / 2.0 - w / 2.0, sz.y * 0.87), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color("ffd23f"))
