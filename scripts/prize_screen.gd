## The end of the boss fight on screen (v0.10.0; v0.12.6 the fiesta went wild).
##
## Victory: confetti and "CONGRATULATIONS!", then "Now that you have beaten the boss, you get the final prize!",
## "Are you ready for your prize?", "Here it comes!" (the screen creeps in, a siren rises) -- and the prize: a
## full-screen fiesta for Smiguel el Magnifico, ported from LoadingFiesta in Jacob's 4X game. He slams in, bobs on the
## band's 165 bpm beat and sways; a trumpet blares, maracas shake, mariachi music plays; papel picado flags hang along
## the top, zarape stripes roll (and cycle through the rainbow) behind, maracas orbit, a disco ball spins, god rays
## turn behind him, coloured spotlights sweep on the beat, confetti falls; the music's credit sits at the bottom.
##
## v0.12.6 on top of that runs a 24-second show of meme moments, looping until a key ends it (see FIESTA_LEN and
## _fiesta_events; every moment also has a caption in bouncing, wobbling rainbow letters):
##    0.0  the slam: air horns (BWAAA BWA BWAAAA), a zoom punch, an RGB split, a short flash, a shake
##    1.6  "¡ÁNDALE! ¡ÁNDALE! ¡ARRIBA! ¡ARRIBA!": a cactus in a sombrero dances across the bottom in a cloud of dust
##    4.3  THE RING floats in (a gold band, glinting, its fiery inscription flickering, a warm glow). His eyes go huge
##         (cartoon eyes pop over his, springy) and the pupils follow it everywhere; "my precious" plays (see below);
##         "¡MI TESORO!"; he leans toward it
##    4.8  ...while an abuela rises from the corner, winds up and throws LA CHANCLA, which spins across and SMACKS him
##         at 6.25 (¡PUM!, he squashes and wobbles, dizzy spiral eyes, stars round his head); the ring is knocked
##         flying off the screen, and a sad, slow "precious..." trails after it
##    8.2  a star piñata swings down; a stick whacks it on the beat (¡PUM! ¡PAZ!) and the third whack bursts it into
##         candy, confetti and fireworks (bloom) -- and the ring falls out of it. Eyes huge again, "my precious"...
##   11.4  "¡AY, CARAMBA!": the screen folds into a spinning kaleidoscope, every colour cycling (six rings now!)
##   14.0  "¡TACOS PARA TODOS!": tacos and chillies rain and bounce (one knocks the ring away), a tortilla boings across
##   17.0  a lucha libre mask slams in over spinning sun rays, the screen bulging on every beat
##   19.0  "¡AY AY AYYYYY!": a rising siren, red and green beacon lights, VHS tears and a rocking tilt -- the ring
##         descends once more, eyes huge, "my precious"...
##   21.0  ...and a giant sombrero drops, sweeps the ring away and lands on the camera (slide whistle, thud: "¿Quién
##         apagó la luz?"), then flies off
##   22.6  the finale: fireworks, bloom, "¡VIVA SMIGUEL!" -- then it all starts again
## His eyes are found by EYE_FRAC (fractions of the picture, so they survive scaling); the stand-in's eyes are used
## without the picture. The "my precious" line is not made by the game: it is played from prize/precious_custom.wav
## (or .ogg) next to the exe or in the user folder, else assets/prize/precious_custom.wav/.ogg, else
## assets/prize/precious.wav/.ogg; with none of them the beat is silent.
## The distortions are a screen shader (FX_SHADER) over everything but the captions, the credit and the hint; flashes
## are short and no more than about two a second (none full-screen strobing). The taco, chilli, maracas and
## cactus-in-a-sombrero pictures are public-domain (CC0) clip art in assets/prize/ (see assets/prize/CREDITS.txt);
## everything else is drawn here, and the sounds are made in Synth.fiesta.
##
## The picture of Smiguel isn't part of the game (it isn't ours to publish): it's read at runtime from
## prize/smiguel_el_magnifico.png next to the game's exe (or user://prize/). Without it, a drawn stand-in -- a big
## sombrero and moustache -- takes his place.
##
## Defeat: "Awww, you didn't get the final prize! And you died! Better luck next time..." with a sad trombone, the
## colour drained and a little sombrero drifting down; any key starts again (Net.ask_restart): back at the spawn with
## full health, levels kept, the altar ready.
class_name PrizeScreen
extends CanvasLayer

const BPM := 165.0
const PIC := "smiguel_el_magnifico.png"
const CREDIT := "Music: \"Mariachi Snooze\" Kevin MacLeod (incompetech.com) — CC BY 3.0"
const LINES := ["CONGRATULATIONS!", "Now that you have beaten the boss, you get the final prize!",
	"Are you ready for your prize?", "Here it comes!"]
const FIESTA_LEN := 24.0   # the meme show's loop, in seconds

## The captions: [start, end, text, font size (at 720 p), height on screen (0-1), wobble]
const CAPTIONS := [
	[1.6, 4.6, "¡ÁNDALE! ¡ÁNDALE! ¡ARRIBA! ¡ARRIBA!", 50, 0.80, 1.0],
	[4.6, 6.2, "¡MI TESORO!", 64, 0.86, 1.4],
	[6.55, 8.0, "¡LA CHANCLA!", 92, 0.30, 1.2],
	[10.1, 11.4, "¡PIÑATA!", 100, 0.42, 1.3],
	[11.6, 14.0, "¡AY, CARAMBA!", 104, 0.50, 1.6],
	[14.0, 17.0, "¡TACOS PARA TODOS!", 66, 0.80, 1.0],
	[17.15, 19.0, "¡EL MAGNÍFICO!", 84, 0.86, 1.0],
	[19.0, 21.0, "¡AY AY AYYYYY!", 86, 0.78, 2.2],
	[21.85, 22.5, "¿Quién apagó la luz?", 44, 0.50, 0.5],
	[22.6, 24.0, "¡VIVA SMIGUEL!", 96, 0.78, 1.2],
]
const PIN_HITS := [9.0, 9.55, 10.1]                 # the stick's whacks (the third bursts it)
const TORT_BOUNCES := [14.95, 15.6, 16.25]          # the tortilla's boings
const FIREWORKS := [22.6, 22.95, 23.3, 23.65]
const STARE := [[4.5, 6.25], [10.3, 14.0], [19.3, 21.5]]   # his eyes go huge, fixed on the ring
const VOICE := [[4.5, 1.0], [10.3, 1.08], [19.3, 0.94]]    # "my precious": when, at what pitch
const SMACK := 6.25                                         # the chancla hits him
## Where his eyes are in the prize picture (fractions of its width and height) and their half-size (fractions of
## its width and height); measured on smiguel_el_magnifico.png (613 x 673).
const EYE_FRAC := [Vector2(0.41, 0.256), Vector2(0.51, 0.253)]
const EYE_SIZE := Vector2(0.028, 0.018)

enum Mode { NONE, VICTORY, FIESTA, DEFEAT }

var net: Net
var mode := Mode.NONE
var t := 0.0
var line := -1
var canvas: Control         # behind the picture: the stripes, flags, god rays, disco ball, maracas, stand-in
var fg: Control             # in front of the picture: the meme moments, confetti, candy, fireworks
var top: Control            # above the screen effects: the captions (kept readable)
var fx: ColorRect           # the screen shader
var title: Label
var sub: Label
var credit: Label
var pic: TextureRect
var pic_tex: Texture2D
var confetti: Array = []    # [pos, vel, colour, spin, size]
var candy: Array = []       # [pos, vel, rot, spin, colour]
var sparks: Array = []      # fireworks: [pos, vel, colour, life, max life]
var fallers: Array = []     # tacos and chillies: [pos, vel, rot, spin, texture, scale]
var music: AudioStreamPlayer
var shakers: AudioStreamPlayer
var hint: Label
var ready_at := 0.0         # keys count only after this (so a key held in the fight doesn't skip it)
var mouse_before := Input.MOUSE_MODE_VISIBLE
var cyc := 0.0              # where the fiesta is in its loop
var prev_cyc := -1.0
var loops := 0
var kick := {"zoom": 0.0, "chroma": 0.0, "flash": 0.0, "shake": 0.0, "bloom": 0.0, "bulge": 0.0, "vhs": 0.0}
var flash_col := Color.WHITE
var tex := {}               # the clip art
var precious: AudioStream   # "my precious" (null: silent)
const CONFETTI := [Color("e63946"), Color("f4a261"), Color("e9c46a"), Color("2a9d8f"), Color("8338ec"), Color("ff006e"), Color("3a86ff"), Color("06d6a0")]
const ZARAPE := [Color("d62828"), Color("f77f00"), Color("fcbf49"), Color("2a9d8f"), Color("6a4c93"), Color("e63946"), Color("1d3557"), Color("06d6a0")]
const KICK_DECAY := {"zoom": 7.0, "chroma": 5.0, "flash": 11.0, "shake": 5.0, "bloom": 3.0, "bulge": 7.0, "vhs": 2.5}

## The screen shader: zoom punches, shake, tilt, twist, a fisheye bulge, waves, a kaleidoscope, an RGB split, VHS
## tears and scanlines, bloom; then light: four coloured spotlights sweeping on the beat, a rotating red/green beacon,
## a hue cycle, a vignette, a (capped) flash, and the defeat's drained colour.
const FX_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float time = 0.0;
uniform float beat = 0.0;
uniform float aspect = 1.7778;
uniform float zoom = 1.0;
uniform vec2 shake = vec2(0.0);
uniform float tilt = 0.0;
uniform float twist = 0.0;
uniform float bulge = 0.0;
uniform float wave = 0.0;
uniform float kaleido = 0.0;
uniform float chroma = 0.0;
uniform float vhs = 0.0;
uniform float bloom = 0.0;
uniform float spots = 0.0;
uniform float siren = 0.0;
uniform float hue = 0.0;
uniform float hue_mix = 0.0;
uniform float flash = 0.0;
uniform vec3 flash_col = vec3(1.0);
uniform float desat = 0.0;
uniform float vignette = 0.25;

vec3 hue_rot(vec3 c, float a) {
	vec3 k = vec3(0.57735);
	float ca = cos(a);
	return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}
float hash(float n) { return fract(sin(n) * 43758.5453); }
vec2 mirror_uv(vec2 uv) { return 1.0 - abs(1.0 - mod(uv, 2.0)); }

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 p = uv - 0.5;
	p.x *= aspect;
	float band = floor(uv.y * 45.0);
	float tear = step(0.72, hash(band + floor(time * 14.0))) * (hash(band * 3.1 + floor(time * 20.0)) - 0.5);
	p.x += vhs * (tear * 0.12 + 0.006 * sin(uv.y * 220.0 + time * 30.0));
	p /= zoom;
	float r = length(p);
	float a = tilt + twist * max(0.0, 0.9 - r) * 2.0;
	p = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * p;
	p *= 1.0 - bulge * (0.6 - min(dot(p, p), 0.6));
	p.x += wave * 0.025 * sin(p.y * 16.0 + time * 6.0);
	p.y += wave * 0.018 * sin(p.x * 11.0 + time * 4.7);
	if (kaleido > 0.001) {
		float seg = TAU / 6.0;
		float ang = mod(atan(p.y, p.x) + time * 0.6, seg);
		ang = abs(ang - seg * 0.5);
		p = mix(p, length(p) * vec2(cos(ang), sin(ang)), kaleido);
	}
	p.x /= aspect;
	vec2 suv = mirror_uv(p + 0.5 + shake);
	vec2 dir = (suv - 0.5) * chroma;
	vec3 col;
	col.r = texture(screen_tex, mirror_uv(suv + dir)).r;
	col.g = texture(screen_tex, suv).g;
	col.b = texture(screen_tex, mirror_uv(suv - dir)).b;
	if (bloom > 0.001) {
		vec3 bl = textureLod(screen_tex, suv, 3.0).rgb * 0.5 + textureLod(screen_tex, suv, 5.0).rgb * 0.5;
		col += max(bl - 0.45, 0.0) * bloom * 2.2;
	}
	col = mix(col, hue_rot(col, hue), hue_mix);
	vec2 q = uv - 0.5;
	q.x *= aspect;
	vec3 light = vec3(0.0);
	float pulse = exp(-fract(beat) * 5.0);
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		bool low = i < 2;
		vec2 src = low ? vec2(fi < 0.5 ? -0.85 : 0.85, 0.56) : vec2(fi < 2.5 ? -0.35 : 0.35, -0.56);
		float base = low ? (fi < 0.5 ? 0.35 : -0.35) : (fi < 2.5 ? -0.3 : 0.3);
		float ang = base + 0.65 * sin(beat * TAU / 8.0 + fi * 1.7);
		vec2 v = low ? vec2(sin(ang), -cos(ang)) : vec2(sin(ang), cos(ang));
		vec2 d = q - src;
		float along = dot(d, v);
		float perp = abs(d.x * v.y - d.y * v.x);
		float w = 0.04 + along * 0.17;
		float beam = smoothstep(w, w * 0.25, perp) * step(0.0, along) * exp(-along * 0.8);
		light += beam * hue_rot(vec3(1.0, 0.25, 0.2), time * 0.45 + fi * 1.57);
	}
	col += light * spots * 0.3 * (0.85 + 0.15 * pulse);
	if (siren > 0.001) {
		float sa = atan(q.y + 0.45, q.x);
		float rb = pow(max(cos(sa - time * 6.0), 0.0), 12.0);
		float gb = pow(max(cos(sa - time * 6.0 + PI), 0.0), 12.0);
		col *= 1.0 - 0.45 * siren;   // the room goes dim so the beacon shows
		col += siren * 0.85 * (rb * vec3(1.0, 0.12, 0.1) + gb * vec3(0.1, 1.0, 0.35));
	}
	col *= 1.0 - vhs * 0.22 * (0.5 + 0.5 * sin(uv.y * 1080.0));
	col += vhs * 0.07 * (hash(uv.x * 91.0 + uv.y * 1733.0 + time) - 0.5);
	col = mix(col, vec3(dot(col, vec3(0.3, 0.59, 0.11))), desat);
	col *= 1.0 - vignette * smoothstep(0.3, 0.85, length(uv - 0.5) * 1.15);
	col = mix(col, flash_col, clamp(flash, 0.0, 0.5));
	COLOR = vec4(col, 1.0);
}
"""


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
	fg = _layer_control(_draw_fg)
	title = _label(72, Color("ffd23f"), 14)
	sub = _label(36, Color.WHITE, 10)
	fx = ColorRect.new()
	fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = FX_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	fx.material = mat
	add_child(fx)
	top = _layer_control(_draw_top)
	credit = _label(18, Color(1, 1, 1, 0.9), 6)
	credit.text = CREDIT
	hint = _label(20, Color(1, 1, 1, 0.75), 6)
	music = AudioStreamPlayer.new()
	music.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"   # v0.12.9: the sound menu's buses
	add_child(music)
	shakers = AudioStreamPlayer.new()
	shakers.volume_db = -8.0
	shakers.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	add_child(shakers)
	for k in ["taco", "chili", "maracas", "sombrero_cactus"]:
		tex[k] = load("res://assets/prize/%s.png" % k)
	precious = load_precious()
	net.boss_result.connect(_on_result)


## "My precious": a recording of your own (precious_custom.wav or .ogg) in the prize folder next to the exe or in the
## user folder, or in assets/prize/; else assets/prize/precious.wav (or .ogg); else nothing (the beat is silent).
static func load_precious() -> AudioStream:
	var tries: Array[String] = []
	for p in picture_paths():
		for ext in ["wav", "ogg"]:
			tries.append(str(p).get_base_dir().path_join("precious_custom." + ext))
	for n in ["precious_custom.wav", "precious_custom.ogg", "precious.wav", "precious.ogg"]:
		tries.append("res://assets/prize/" + n)
	for p in tries:
		var s := _load_audio(p)
		if s != null:
			return s
	return null


static func _load_audio(p: String) -> AudioStream:
	if p.begins_with("res://") and ResourceLoader.exists(p):
		return load(p) as AudioStream
	var fp := ProjectSettings.globalize_path(p) if p.begins_with("res://") else p
	if fp == "" or not FileAccess.file_exists(fp):
		return null
	match fp.get_extension().to_lower():
		"wav":
			return AudioStreamWAV.load_from_file(fp)
		"ogg":
			return AudioStreamOggVorbis.load_from_file(fp)
	return null


func _say(pitch: float, vol: float) -> void:
	if precious == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = precious
	p.pitch_scale = pitch
	p.volume_db = vol
	p.bus = "Voice" if AudioServer.get_bus_index("Voice") >= 0 else "Master"
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _layer_control(draw_fn: Callable) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(draw_fn)
	add_child(c)
	return c


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
	candy.clear()
	sparks.clear()
	fallers.clear()
	for k in kick:
		kick[k] = 0.0
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
	_kick("zoom", 0.15)
	_kick("flash", 0.25)
	_kick("bloom", 0.6)
	Synth.play(self, Synth.trumpet(), -6.0)


func start_fiesta() -> void:
	mode = Mode.FIESTA
	t = 0.0
	cyc = 0.0
	prev_cyc = -1.0
	loops = 0
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
	var sz := _size()
	for i in n:
		confetti.append([Vector2(randf() * sz.x, -randf() * sz.y * 0.6), Vector2(randf_range(-60, 60), randf_range(60, 220)),
			CONFETTI[randi() % CONFETTI.size()], randf() * TAU, randf_range(6, 13)])


## Confetti blown out from a point (the piñata, the finale).
func _blast_confetti(at: Vector2, n: int) -> void:
	for i in n:
		var a := randf() * TAU
		confetti.append([at, Vector2(cos(a), sin(a)) * randf_range(150, 650) + Vector2(0, -200),
			CONFETTI[randi() % CONFETTI.size()], randf() * TAU, randf_range(6, 13)])


func _firework(at: Vector2, n := 70) -> void:
	var c1: Color = CONFETTI[randi() % CONFETTI.size()].lightened(0.25)
	var c2: Color = CONFETTI[randi() % CONFETTI.size()].lightened(0.4)
	for i in n:
		var a := randf() * TAU
		var life := randf_range(0.9, 1.5)
		sparks.append([at, Vector2(cos(a), sin(a)) * randf_range(140, 380) * _size().y / 720.0, c1 if i % 2 == 0 else c2, life, life])


func _size() -> Vector2:
	return canvas.size if canvas.size.x > 0 else Vector2(1280, 720)


func _kick(k: String, v: float) -> void:
	kick[k] = maxf(kick[k], v)


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
		return
	_kick("zoom", 0.08)
	_kick("chroma", 0.006)
	if line == LINES.size() - 1:   # "Here it comes!"
		Synth.play(self, Synth.fiesta("siren"), -10.0)


## True once, the frame the fiesta's loop passes `e` seconds.
func _fired(e: float) -> bool:
	if cyc >= prev_cyc:
		return prev_cyc < e and e <= cyc
	return e > prev_cyc or e <= cyc   # wrapped round


## 0 -> 1 across [a, b] (clamped).
func _u(a: float, b: float) -> float:
	return clampf((cyc - a) / (b - a), 0.0, 1.0)


func _in(a: float, b: float) -> bool:
	return cyc >= a and cyc < b


func _process(delta: float) -> void:
	if mode == Mode.NONE:
		return
	t += delta
	var sz := canvas.size
	for k in kick:
		kick[k] *= exp(-float(KICK_DECAY[k]) * delta)
	if mode == Mode.FIESTA:
		prev_cyc = cyc
		cyc = fmod(t, FIESTA_LEN)
		if cyc < prev_cyc:
			loops += 1
		_fiesta_events(sz)
	_step_particles(delta, sz)
	title.visible = mode != Mode.FIESTA and not (mode == Mode.VICTORY and line == 0)
	sub.visible = false
	credit.visible = mode == Mode.FIESTA
	hint.visible = t > ready_at
	match mode:
		Mode.VICTORY:
			title.text = LINES[line]
			title.add_theme_font_size_override("font_size", 46)
			title.add_theme_color_override("font_color", Color.WHITE)
			title.rotation = sin(t * 3.0) * deg_to_rad(1.5)
			var pop := 1.0 + 0.5 * maxf(0.0, 1.0 - t / 0.25)
			_place(title, Vector2(0.05, 0.3), Vector2(0.95, 0.55), pop)
			hint.text = "press any key"
			_place(hint, Vector2(0.2, 0.86), Vector2(0.8, 0.94))
			if t > (3.2 if line == 0 else 2.6):
				_next_line()
		Mode.FIESTA:
			_place(credit, Vector2(0.02, 0.93), Vector2(0.98, 0.99))
			hint.text = "press any key"
			_place(hint, Vector2(0.3, 0.885), Vector2(0.7, 0.93))
			if pic.visible:
				var h := sz.y * 0.62
				var w := h * float(pic_tex.get_width()) / float(maxi(pic_tex.get_height(), 1))
				pic.size = Vector2(w, h)
				pic.pivot_offset = pic.size / 2.0
				pic.position = Vector2(sz.x / 2.0, sz.y * 0.56) - pic.size / 2.0 + _slam_shake() + _dance_offset(sz)
				pic.scale = Vector2.ONE * _slam_scale() * _bob() * _squash()
				pic.rotation = _sway()
		Mode.DEFEAT:
			title.text = "Awww, you didn't get the final prize!\nAnd you died! Better luck next time..."
			title.add_theme_font_size_override("font_size", 44)
			title.add_theme_color_override("font_color", Color("ffb3b3"))
			title.rotation = 0.0
			_place(title, Vector2(0.05, 0.3), Vector2(0.95, 0.6), 1.0 + 0.02 * sin(t * 2.0))
			hint.text = "press any key to try again"
			_place(hint, Vector2(0.2, 0.75), Vector2(0.8, 0.83))
	_update_fx(sz)
	canvas.queue_redraw()
	fg.queue_redraw()
	top.queue_redraw()


## The fiesta's one-off moments: sounds, kicks to the screen effects, bursts.
func _fiesta_events(sz: Vector2) -> void:
	var c := Vector2(sz.x / 2.0, sz.y / 2.0)
	if _fired(0.0):   # the slam (and every loop's restart)
		Synth.play(self, Synth.fiesta("airhorn"), -7.0)
		_kick("zoom", 0.35)
		_kick("chroma", 0.025)
		_kick("flash", 0.4)
		flash_col = Color(1, 0.95, 0.8)
		_kick("shake", 0.02)
		_kick("bloom", 0.8)
		if loops > 0:
			_burst_confetti(200)
	if _fired(1.6):
		Synth.play(self, Synth.fx("whoosh"), -4.0)
	if _fired(5.7):   # the chancla leaves her hand
		Synth.play(self, Synth.fx("whoosh"), -2.0)
	if _fired(SMACK):   # ...and smacks him; the ring goes flying
		Synth.play(self, Synth.fiesta("bonk"), -1.0)
		Synth.play(self, Synth.fiesta("ting"), -6.0)
		_kick("shake", 0.03)
		_kick("chroma", 0.035)
		_kick("zoom", 0.1)
		_kick("flash", 0.15)
		flash_col = Color(1, 0.6, 0.85)
	if _fired(SMACK + 0.35):   # a sad, slow "precious..." after it
		_say(0.78, -9.0)
	for v in VOICE:
		if _fired(v[0]):
			_say(v[1], 0.0)
	for e in [4.3, 19.0, 14.0]:   # the ring arrives (twice) / a taco knocks it away
		if _fired(e):
			Synth.play(self, Synth.fiesta("ting"), -7.0)
	for i in PIN_HITS.size():
		if _fired(PIN_HITS[i]):
			if i < PIN_HITS.size() - 1:
				Synth.play(self, Synth.fiesta("thwack"), -2.0)
				_kick("zoom", 0.06)
				_kick("chroma", 0.01)
				_kick("shake", 0.008)
			else:   # it bursts
				Synth.play(self, Synth.fiesta("pinata"), -1.0)
				var p := _pinata_pos(sz)
				for k in 80:
					var a := randf() * TAU
					candy.append([p, Vector2(cos(a), sin(a) - 0.6) * randf_range(200, 700), randf() * TAU, randf_range(-12, 12),
						CONFETTI[randi() % CONFETTI.size()]])
				_blast_confetti(p, 180)
				_firework(Vector2(sz.x * 0.3, sz.y * 0.3))
				_firework(Vector2(sz.x * 0.85, sz.y * 0.22))
				_kick("bloom", 1.2)
				_kick("flash", 0.3)
				flash_col = Color(1, 0.9, 0.6)
				_kick("zoom", 0.18)
				_kick("chroma", 0.025)
				_kick("shake", 0.025)
	if _fired(11.4):
		Synth.play(self, Synth.trumpet(), -5.0)
		_kick("zoom", 0.1)
	if _fired(14.0):   # taco rain
		for k in 16:
			fallers.append([Vector2(randf() * sz.x, -randf_range(40, sz.y * 0.9)), Vector2(randf_range(-80, 80), randf_range(0, 150)),
				randf() * TAU, randf_range(-5, 5), "taco" if k % 3 != 2 else "chili", randf_range(0.18, 0.3) * sz.y / 720.0])
	for b in TORT_BOUNCES:
		if _fired(b):
			Synth.play(self, Synth.fiesta("boing"), -3.0)
			_kick("bulge", 0.08)
	if _fired(17.0):   # the lucha libre mask
		Synth.play(self, Synth.fx("slam"), -3.0)
		_kick("flash", 0.25)
		flash_col = Color(1, 0.85, 0.3)
		_kick("zoom", 0.2)
		_kick("chroma", 0.02)
	if _in(17.0, 19.0):   # the screen bulges on every beat
		var bt := floorf(t * BPM / 60.0)
		if bt != floorf((t - get_process_delta_time()) * BPM / 60.0):
			_kick("bulge", 0.14)
	if _fired(19.0):
		Synth.play(self, Synth.fiesta("siren"), -5.0)
	for v in [19.2, 19.9, 20.6]:
		if _fired(v):
			_kick("vhs", 0.9)
	if _fired(21.0):
		Synth.play(self, Synth.fiesta("whistle"), -3.0)
	if _fired(21.8):   # the sombrero lands on the camera
		Synth.play(self, Synth.fx("slam"), -2.0)
		_kick("shake", 0.03)
		_kick("chroma", 0.02)
	if _fired(22.45):
		Synth.play(self, Synth.fx("whoosh"), -4.0)
	for i in FIREWORKS.size():
		if _fired(FIREWORKS[i]):
			Synth.play(self, Synth.fiesta("firework"), -9.0)
			_firework(Vector2(sz.x * [0.25, 0.75, 0.5, 0.35][i], sz.y * [0.28, 0.25, 0.18, 0.35][i]), 90)
			_kick("bloom", 0.6)
			_kick("flash", 0.08)
			flash_col = Color(1, 1, 1)
			if i == 0:
				_blast_confetti(c, 150)


func _step_particles(delta: float, sz: Vector2) -> void:
	for c in confetti:
		c[1].y = minf(c[1].y + 160.0 * delta, 260.0)
		c[1].x = lerpf(c[1].x, 0.0, minf(delta * 1.5, 1.0)) if absf(c[1].x) > 60.0 else c[1].x
		c[0] += Vector2(c[1].x + sin(t * 3.0 + c[3]) * 40.0, c[1].y) * delta
		c[3] += delta * 4.0
		if mode == Mode.FIESTA and c[0].y > sz.y + 20 and confetti.size() < 420:
			c[0] = Vector2(randf() * sz.x, -20)
			c[1] = Vector2(randf_range(-60, 60), randf_range(60, 220))
	confetti = confetti.filter(func(c): return c[0].y < sz.y + 20)
	for c in candy:
		c[1].y += 900.0 * delta
		c[0] += c[1] * delta
		c[2] += c[3] * delta
	candy = candy.filter(func(c): return c[0].y < sz.y + 40)
	for s in sparks:
		s[1] *= exp(-1.6 * delta)
		s[1].y += 90.0 * delta
		s[0] += s[1] * delta
		s[3] -= delta
	sparks = sparks.filter(func(s): return s[3] > 0.0)
	var floor_y := sz.y * 0.9
	for f in fallers:
		f[1].y += 900.0 * delta
		f[0] += f[1] * delta
		f[2] += f[3] * delta
		if f[0].y > floor_y and f[1].y > 0.0 and cyc < 16.7:
			f[0].y = floor_y
			f[1].y *= -0.55
			f[3] *= -0.8
	fallers = fallers.filter(func(f): return f[0].y < sz.y + 120)


## The screen shader's settings for this moment: the fiesta's timeline (or the victory/defeat look) plus the kicks.
func _update_fx(sz: Vector2) -> void:
	var beat := t * BPM / 60.0
	var zoom := 1.0
	var tilt := 0.0
	var twist := 0.0
	var wave := 0.0
	var kal := 0.0
	var spots := 0.0
	var siren := 0.0
	var hue := 0.0
	var hue_mix := 0.0
	var desat := 0.0
	var vig := 0.3
	var chroma := 0.0
	var shake := 0.0
	var bloom := 0.25
	var bulge := 0.0
	match mode:
		Mode.VICTORY:
			spots = 0.6
			wave = 0.06
			if line == LINES.size() - 1:   # "Here it comes!": the screen creeps in, shaking harder
				var u := clampf(t / 2.6, 0.0, 1.0)
				zoom = 1.0 + 0.2 * u * u
				chroma = 0.012 * u
				shake = 0.006 * u
				wave = 0.06 + 0.3 * u
				spots = 0.6 + 0.6 * u
				twist = 0.05 * u * sin(t * 9.0)
		Mode.FIESTA:
			spots = 1.0
			wave = 0.08
			if int(floorf(beat)) % 2 == 0:
				bulge = 0.04 * exp(-(beat - floorf(beat)) * 6.0)
			if _in(1.6, 4.6):
				wave = 0.35 * sin(_u(1.6, 4.6) * PI)
			if _in(11.4, 14.0):   # the kaleidoscope
				kal = smoothstep(0.0, 1.0, _u(11.4, 11.8)) * (1.0 - smoothstep(0.0, 1.0, _u(13.4, 14.0)))
				twist = 0.25 * kal * sin(t * 2.0)
				hue = cyc * 2.5
				hue_mix = kal
				wave = maxf(wave, 0.4 * kal)
			if _in(14.0, 17.0):
				wave = 0.18
			if _in(19.0, 21.0):   # the siren
				var u := _u(19.0, 21.0)
				siren = minf(u * 6.0, 1.0) * minf((1.0 - u) * 8.0, 1.0)
				tilt = sin(t * 6.0) * 0.06 * siren
				spots = 0.5
			if _in(21.8, 22.5):   # under the sombrero
				spots = 0.0
			if _in(22.6, 24.0):
				bloom = 0.4
		Mode.DEFEAT:
			desat = minf(t * 0.6, 0.6)
			wave = 0.12
			vig = 0.65
			bloom = 0.0
	var m := fx.material as ShaderMaterial
	var sh: float = kick["shake"] + shake
	m.set_shader_parameter("time", t)
	m.set_shader_parameter("beat", beat)
	m.set_shader_parameter("aspect", sz.x / maxf(sz.y, 1.0))
	m.set_shader_parameter("zoom", zoom + kick["zoom"])
	m.set_shader_parameter("shake", Vector2(randf_range(-1, 1), randf_range(-1, 1)) * sh)
	m.set_shader_parameter("tilt", tilt)
	m.set_shader_parameter("twist", twist)
	m.set_shader_parameter("bulge", bulge + kick["bulge"])
	m.set_shader_parameter("wave", wave)
	m.set_shader_parameter("kaleido", kal)
	m.set_shader_parameter("chroma", chroma + kick["chroma"])
	m.set_shader_parameter("vhs", kick["vhs"])
	m.set_shader_parameter("bloom", bloom + kick["bloom"])
	m.set_shader_parameter("spots", spots)
	m.set_shader_parameter("siren", siren)
	m.set_shader_parameter("hue", hue)
	m.set_shader_parameter("hue_mix", hue_mix)
	m.set_shader_parameter("flash", kick["flash"])
	m.set_shader_parameter("flash_col", Vector3(flash_col.r, flash_col.g, flash_col.b))
	m.set_shader_parameter("desat", desat)
	m.set_shader_parameter("vignette", vig)


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


## Smiguel joins in: he leans toward the ring while he stares at it, is knocked sideways by the chancla, and bounces
## along with the tacos.
func _dance_offset(sz: Vector2) -> Vector2:
	var o := Vector2.ZERO
	var st := _stare()
	if st > 0.0:
		var r := _ring()
		if r[0]:
			o += ((r[1] as Vector2) - Vector2(sz.x / 2.0, sz.y * 0.4)).normalized() * sz.y * 0.035 * minf(st, 1.0)
	if _in(SMACK, SMACK + 0.8):   # the hit knocks him back
		var a := cyc - SMACK
		o += Vector2(-sz.x * 0.05, sz.y * 0.01) * exp(-a * 5.0) * cos(a * 18.0)
	if _in(14.0, 17.0):   # bouncing with the tacos
		o.y -= absf(sin(t * PI * BPM / 60.0)) * sz.y * 0.03
	return o


## The squash and wobble when the chancla hits.
func _squash() -> Vector2:
	if mode != Mode.FIESTA or not _in(SMACK, SMACK + 1.0):
		return Vector2.ONE
	var j := exp(-(cyc - SMACK) * 5.0) * cos((cyc - SMACK) * 28.0) * 0.28
	return Vector2(1.0 + j, 1.0 - j)


## How huge his eyes are (0: his own; about 1, overshooting as they pop: staring at the ring).
func _stare() -> float:
	if mode != Mode.FIESTA:
		return 0.0
	for s in STARE:
		if _in(s[0], s[1] + 0.25):
			return _elastic(_u(s[0], s[0] + 0.5)) * (1.0 - _u(s[1], s[1] + 0.25))
	return 0.0


## The ring: [shown, screen position, size, spin]. It floats in and hovers (drifting) three times: knocked flying by
## the chancla, fallen out of the piñata (then knocked off by a taco), and descending in the siren (then swept away by
## the falling sombrero).
func _ring() -> Array:
	var none := [false, Vector2.ZERO, 0.0, 0.0]
	if mode != Mode.FIESTA:
		return none
	var sz := _size()
	var k := sz.y / 720.0
	var drift := Vector2(sin(t * 1.3) * 28.0, sin(t * 1.9) * 16.0) * k
	var spin := t * 2.2
	if _in(4.3, 7.0):
		var hover := Vector2(sz.x * 0.7, sz.y * 0.36) + drift
		if cyc < SMACK:
			var u := 1.0 - pow(1.0 - _u(4.3, 4.9), 3.0)
			return [true, Vector2(sz.x * 1.1, sz.y * 0.05).lerp(hover, u), 1.0, spin]
		var v := _u(SMACK, 7.0)
		return [true, hover + Vector2(v * sz.x * 0.6, -sin(v * PI * 0.6) * sz.y * 0.45 + v * v * sz.y * 0.1), 1.0 - v * 0.3, spin + v * 25.0]
	if _in(10.1, 14.6):
		var hover := Vector2(sz.x * 0.27, sz.y * 0.4) + drift
		if cyc < 10.6:
			var u := _u(10.1, 10.6)
			return [true, Vector2(sz.x * 0.74, sz.y * 0.36).lerp(hover, u) - Vector2(0, sin(u * PI) * sz.y * 0.2), lerpf(0.4, 1.0, u), spin]
		if cyc < 14.0:
			return [true, hover, 1.0, spin]
		var v := _u(14.0, 14.6)
		return [true, hover + Vector2(-v * 90.0 * k, v * v * sz.y * 0.8), 1.0, spin + v * 20.0]
	if _in(19.0, 21.8):
		var hover := Vector2(sz.x * 0.63, sz.y * 0.25) + drift * 0.6
		if cyc < 21.0:
			var u := 1.0 - pow(1.0 - _u(19.0, 19.7), 3.0)
			return [true, Vector2(sz.x * 0.63, -sz.y * 0.1).lerp(hover, u), 1.0, spin]
		var v := _u(21.0, 21.8)   # swept up by the falling sombrero
		return [true, hover.lerp(_sombrero_drop_pos(sz), minf(v * 2.5, 1.0)), 1.0 + v * v * v * 5.0, spin + v * 10.0]
	return none


## His eyes on screen: [[centre, half-size], ...] -- on the picture (EYE_FRAC) or on the drawn stand-in.
func _eyes() -> Array:
	var out := []
	if pic.visible and pic_tex != null:
		for f: Vector2 in EYE_FRAC:
			var lp := Vector2(f.x * pic.size.x, f.y * pic.size.y)
			var c := pic.position + pic.pivot_offset + ((lp - pic.pivot_offset) * pic.scale).rotated(pic.rotation)
			out.append([c, Vector2(EYE_SIZE.x * pic.size.x * pic.scale.x, EYE_SIZE.y * pic.size.y * pic.scale.y)])
	else:
		var sz := _size()
		var k := sz.y / 720.0 * _slam_scale() * _bob()
		var c0 := Vector2(sz.x / 2.0, sz.y * 0.58) + _dance_offset(sz)
		for x: float in [-41.0, 43.0]:
			out.append([c0 + (Vector2(x, 21.0) * k * _squash()).rotated(_sway()), Vector2(15, 15) * k])
	return out


func _face(sz: Vector2) -> Vector2:
	var e := _eyes()
	return ((e[0][0] as Vector2) + (e[1][0] as Vector2)) / 2.0 - Vector2(0, 8.0 * sz.y / 720.0)


func _elastic(u: float) -> float:
	if u <= 0.0:
		return 0.0
	if u >= 1.0:
		return 1.0
	return pow(2.0, -10.0 * u) * sin((u * 10.0 - 0.75) * TAU / 3.0) + 1.0


# ---------------------------------------------------------------- drawing: behind Smiguel

func _draw_canvas() -> void:
	var sz := canvas.size
	match mode:
		Mode.VICTORY:
			canvas.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.03, 0.02, 0.08, minf(t * 2.0, 0.55) if line == 0 else 0.62))
		Mode.DEFEAT:
			canvas.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.08, 0.0, 0.0, minf(t * 1.5, 0.75)))
		Mode.FIESTA:
			_draw_zarape(sz)
			_draw_god_rays(sz)
			_draw_flags(sz)
			_draw_disco_ball(sz)
			_draw_maracas(sz)
			if not pic.visible:
				_draw_stand_in(sz)


## Zarape stripes: bold coloured bands rolling slowly sideways, with thin dark lines between; their hues drift round
## the rainbow.
func _draw_zarape(sz: Vector2) -> void:
	var band := sz.y / 16.0
	var off := fmod(t * 40.0, band * ZARAPE.size())
	var shift := fmod(t * 0.06, 1.0)
	for i in range(-ZARAPE.size(), 18):
		var y := i * band + off
		var c0: Color = ZARAPE[posmod(i, ZARAPE.size())]
		canvas.draw_rect(Rect2(0, y, sz.x, band), Color.from_hsv(fmod(c0.h + shift, 1.0), c0.s, c0.v))
		canvas.draw_rect(Rect2(0, y + band - 3, sz.x, 3), Color(0, 0, 0, 0.35))
	canvas.draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.18))


## Sun rays turning slowly behind Smiguel.
func _draw_god_rays(sz: Vector2) -> void:
	var c := Vector2(sz.x / 2.0, sz.y * 0.56)
	var r := sz.length()
	var n := 14
	for i in n:
		var a := t * 0.35 + i * TAU / n
		var w := PI / n * 0.55
		var col := Color(1, 0.95, 0.6, 0.16) if i % 2 == 0 else Color(1, 1, 1, 0.1)
		canvas.draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(a - w), sin(a - w)) * r, c + Vector2(cos(a + w), sin(a + w)) * r]), col)


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


## A mirror ball hanging under the flags, its facets glinting as it turns.
func _draw_disco_ball(sz: Vector2) -> void:
	var k := sz.y / 720.0
	var c := Vector2(sz.x / 2.0, sz.y * 0.2)
	var r := 34.0 * k
	canvas.draw_line(Vector2(c.x, 18), c - Vector2(0, r), Color(0.75, 0.75, 0.8), 2.0)
	canvas.draw_circle(c, r + 2.0, Color(0.1, 0.1, 0.15))
	canvas.draw_circle(c, r, Color(0.55, 0.58, 0.65))
	var rows := 7
	for j in rows:
		var lat := -PI / 2.0 + (j + 0.5) * PI / rows
		var ring := cos(lat)
		var cols := maxi(int(12 * ring), 3)
		for i in cols:
			var lon := fmod(i * TAU / cols + t * 1.4, TAU)
			if cos(lon) < 0.0:
				continue
			var p := c + Vector2(sin(lon) * ring, sin(lat)) * r * 0.92
			var glint := pow(maxf(sin(lon * 3.0 + j * 1.3 + t * 5.0), 0.0), 8.0)
			var col := Color(0.6, 0.62, 0.7).lerp(Color.WHITE, glint)
			canvas.draw_rect(Rect2(p - Vector2(3, 3) * k, Vector2(6, 6) * k * cos(lon) + Vector2(1, 1)), col)


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
	var c := Vector2(sz.x / 2.0, sz.y * 0.58) + _slam_shake() + _dance_offset(sz)
	var k := sz.y / 720.0 * _slam_scale() * _bob()
	canvas.draw_set_transform(c, _sway(), Vector2(k, k) * _squash())
	canvas.draw_circle(Vector2(0, 50), 135, Color("d9a066"))             # the face
	canvas.draw_circle(Vector2(-42, 20), 14, Color.WHITE)
	canvas.draw_circle(Vector2(42, 20), 14, Color.WHITE)
	canvas.draw_circle(Vector2(-40, 22), 7, Color.BLACK)
	canvas.draw_circle(Vector2(44, 22), 7, Color.BLACK)
	canvas.draw_circle(Vector2(0, 56), 16, Color("c0784a"))              # the nose
	for side: float in [-1.0, 1.0]:   # the moustache: a grand handlebar, thick in the middle, curling up at the tips
		for i in 34:
			var u := float(i) / 33.0
			var p := Vector2(side * (8.0 + u * 120.0), 84.0 + 12.0 * sin(u * PI) - 46.0 * pow(u, 3.0))
			canvas.draw_circle(p, lerpf(22.0, 6.0, u), Color("2b1a10"))
	canvas.draw_arc(Vector2(0, 122), 30, 0.25, PI - 0.25, 16, Color("7a2a20"), 6.0)   # a big grin
	_draw_sombrero(canvas)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var lbl := "SMIGUEL EL MAGNÍFICO"
	var f := ThemeDB.fallback_font
	var w := f.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	canvas.draw_string_outline(f, Vector2(sz.x / 2.0 - w / 2.0, sz.y * 0.87), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, 10, Color.BLACK)
	canvas.draw_string(f, Vector2(sz.x / 2.0 - w / 2.0, sz.y * 0.87), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color("ffd23f"))


## The sombrero (in the current transform): a vast brim (600 wide, centred at y -40) and a tall crown with a zig-zag
## band.
func _draw_sombrero(ci: CanvasItem) -> void:
	var brim := PackedVector2Array()
	for i in 41:
		var a := PI + float(i) / 40.0 * PI
		brim.append(Vector2(cos(a) * 300, -40 + sin(a) * 50))
	for i in range(40, -1, -1):
		var a := PI + float(i) / 40.0 * PI
		brim.append(Vector2(cos(a) * 300, -40 - sin(a) * 18))
	ci.draw_colored_polygon(brim, Color("e0b040"))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-110, -60), Vector2(-80, -220), Vector2(0, -250),
		Vector2(80, -220), Vector2(110, -60)]), Color("e8bf4a"))
	var zig := PackedVector2Array()
	for i in 12:
		zig.append(Vector2(lerpf(-104, 104, i / 11.0), -96 if i % 2 == 0 else -76))
	ci.draw_polyline(zig, Color("d62828"), 10.0)
	var edge := PackedVector2Array()
	for i in 25:
		var a := PI + float(i) / 24.0 * PI
		edge.append(Vector2(cos(a) * 296, -40 - sin(a) * 15))
	ci.draw_polyline(edge, Color("2a9d8f"), 6.0)


# ---------------------------------------------------------------- drawing: in front of Smiguel

func _draw_fg() -> void:
	var sz := fg.size
	if mode == Mode.FIESTA:
		_draw_eyes(sz)
		_draw_corner_maracas(sz)
		_draw_reflections(sz)
		if _in(1.6, 4.7):
			_draw_cactus(sz)
		if _in(4.8, 8.0):
			_draw_abuela(sz)
		if _in(5.7, 7.3):
			_draw_flying_chancla(sz)
		if _in(8.2, 10.1):
			_draw_pinata(sz)
		if _in(8.6, 10.5):
			_draw_stick(sz)
		if _in(14.0, 17.2):
			_draw_tortilla(sz)
		if _in(17.0, 19.0):
			_draw_lucha(sz)
		var r := _ring()
		if r[0] and cyc < 21.0:
			_draw_ring(r[1], r[2], r[3], sz.y / 720.0)
	for f in fallers:
		var tx: Texture2D = tex.get(f[4])
		if tx != null:
			fg.draw_set_transform(f[0], f[2], Vector2(f[5], f[5]))
			fg.draw_texture(tx, -tx.get_size() / 2.0)
	fg.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for c in candy:
		_draw_candy(c[0], c[2], c[4], sz.y / 720.0)
	for c in confetti:
		var s: float = c[4]
		var dx := Vector2(cos(c[3]), sin(c[3])) * s * 0.5
		var dy := Vector2(-sin(c[3]), cos(c[3])) * s * 0.3 * maxf(absf(sin(c[3] * 1.7)), 0.3)
		var p: Vector2 = c[0]
		fg.draw_colored_polygon(PackedVector2Array([p - dx - dy, p + dx - dy, p + dx + dy, p - dx + dy]), c[2])
	for s in sparks:
		var a: float = s[3] / s[4]
		var col: Color = s[2]
		fg.draw_line(s[0], s[0] - s[1] * 0.06, Color(col.r, col.g, col.b, a), 3.0)
		fg.draw_circle(s[0], 2.5 + 2.0 * a, Color(1, 1, 1, a))
	if mode == Mode.FIESTA and _in(21.0, 22.8):
		var r := _ring()
		if r[0]:   # swept along in front of the falling sombrero
			_draw_ring(r[1], r[2], r[3], sz.y / 720.0)
		_draw_sombrero_drop(sz)
	if mode == Mode.DEFEAT:
		_draw_sad_sombrero(sz)


func _ellipse(ci: CanvasItem, c: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 28:
		var a := i * TAU / 28.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	ci.draw_colored_polygon(pts, col)


## The cartoon eyes over his own: they pop up huge (springy) while he stares at the ring, the pupils following it
## (trembling, obsessed); after the chancla, dizzy spirals and stars circling his head.
func _draw_eyes(sz: Vector2) -> void:
	var st := _stare()
	var dizzy := _in(SMACK, SMACK + 1.1)
	if st <= 0.01 and not dizzy:
		return
	var k := sz.y / 720.0
	var r := _ring()
	var a := 1.0 if dizzy else clampf(st * 3.0, 0.0, 1.0)
	var g := 1.6 if dizzy else 1.0 + 1.5 * st
	for e in _eyes():
		var c: Vector2 = e[0]
		var rad: Vector2 = e[1]
		var rr := Vector2(rad.x, maxf(rad.y, rad.x * 0.8)) * g
		if not dizzy:
			c += Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 1.2 * k * st
		_ellipse(fg, c, rr * 1.14, Color(0.05, 0.03, 0.02, a))
		_ellipse(fg, c, rr, Color(1, 1, 0.95, a))
		for i in 4:   # a few red veins
			var va := i * TAU / 4.0 + 0.6
			var p0 := c + Vector2(cos(va) * rr.x, sin(va) * rr.y) * 0.95
			fg.draw_line(p0, p0.lerp(c, 0.35) + Vector2(sin(i * 7.0), cos(i * 5.0)) * 2.0 * k, Color(0.85, 0.15, 0.15, 0.6 * a), 1.5)
		if dizzy:
			var pts := PackedVector2Array()
			for i in 40:
				var u := i / 39.0
				var sa := u * TAU * 2.5 - t * 12.0
				pts.append(c + Vector2(cos(sa) * rr.x, sin(sa) * rr.y) * u * 0.85)
			fg.draw_polyline(pts, Color(0.1, 0.05, 0.1), maxf(2.0, rr.x * 0.12))
			continue
		var pr := minf(rr.x, rr.y) * 0.48
		var d := ((r[1] as Vector2) - c) if r[0] else Vector2(0, -1)
		var dn := d.normalized()
		var off := Vector2(dn.x * (rr.x - pr), dn.y * (rr.y - pr)) * 0.85 * clampf(d.length() / (rr.x * 4.0), 0.4, 1.0)
		var pp := c + off
		fg.draw_circle(pp, pr, Color(0.35, 0.22, 0.08, a))   # the iris
		fg.draw_circle(pp, pr * 0.62, Color(0.03, 0.02, 0.02, a))
		fg.draw_circle(pp + Vector2(-0.3, -0.35) * pr, pr * 0.26, Color(1, 1, 1, a))
	if dizzy:   # stars round his head
		var f := _face(sz) - Vector2(0, 70.0 * k)
		for i in 5:
			var sa := t * 5.0 + i * TAU / 5.0
			_star(fg, f + Vector2(cos(sa) * 95.0, sin(sa) * 26.0) * k, 14.0 * k, Color(1, 0.9, 0.2, 0.95))


## The ring: a thick gold band (spinning about its upright axis, so it narrows and widens), with a warm glow, a bright
## glint that flares when it faces you, and an inscription of flickering fire-coloured script along the band.
func _draw_ring(p: Vector2, s: float, spin: float, k: float) -> void:
	var r := 44.0 * k * s
	var sx := maxf(absf(cos(spin)), 0.16)
	for i in 6:   # the glow
		fg.draw_circle(p, r * (1.3 + i * 0.32), Color(1, 0.55, 0.12, 0.07))
	fg.draw_set_transform(p, 0.25 * sin(t * 0.8), Vector2(sx, 1.0))
	fg.draw_arc(Vector2.ZERO, r, 0, TAU, 48, Color("6b4306"), r * 0.42)
	fg.draw_arc(Vector2.ZERO, r, 0, TAU, 48, Color("e0ac1c"), r * 0.32)
	fg.draw_arc(Vector2.ZERO, r * 0.93, 0, TAU, 48, Color("ffd34d"), r * 0.1)
	for i in 22:   # the fire-script
		var a0 := i * TAU / 22.0 + t * 0.4
		var fl := clampf(0.45 + 0.3 * sin(t * 13.0 + i * 2.3) + 0.25 * sin(t * 31.0 + i * 5.1), 0.0, 1.0)
		fg.draw_arc(Vector2.ZERO, r * 1.01, a0, a0 + 0.12 + 0.08 * sin(i * 3.7), 4, Color(1.0, 0.3 + 0.2 * fl, 0.05, fl * 0.85), r * 0.07)
	fg.draw_arc(Vector2.ZERO, r * 1.13, -2.6, -1.3, 16, Color(1, 0.98, 0.8, 0.95), r * 0.07)   # the shine
	fg.draw_arc(Vector2.ZERO, r * 0.85, 0.4, 1.6, 12, Color(1, 0.95, 0.7, 0.7), r * 0.05)
	fg.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var gl := pow(absf(cos(spin)), 6.0)
	_star(fg, p + Vector2(-r * 0.75 * sx, -r * 0.75), r * (0.45 + 0.9 * gl), Color(1, 1, 0.9, 0.55 + 0.45 * gl))
	_star(fg, p + Vector2(r * 0.6 * sx, r * 0.7), r * 0.3 * (0.5 + 0.5 * sin(t * 9.0)), Color(1, 0.9, 0.6, 0.6))


## The CC0 maracas picture in both bottom corners, shaking on the beat.
func _draw_corner_maracas(sz: Vector2) -> void:
	var tx: Texture2D = tex.get("maracas")
	if tx == null:
		return
	var beat := t * BPM / 60.0
	var k := sz.y / 720.0 * 0.32
	for side: float in [-1.0, 1.0]:
		var p := Vector2(sz.x / 2.0 + side * sz.x * 0.43, sz.y * 0.8)
		var rot: float = side * 0.3 + sin(beat * TAU * 0.5) * 0.35 * side
		fg.draw_set_transform(p, rot, Vector2(k * side, k))
		fg.draw_texture(tx, -tx.get_size() / 2.0)
	fg.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Specks of light thrown by the mirror ball, wheeling across everything, with a few twinkling stars.
func _draw_reflections(sz: Vector2) -> void:
	var c := Vector2(sz.x / 2.0, sz.y * 0.2)
	for i in 36:
		var a := i * 2.399 + t * 0.5
		var d := (0.2 + fmod(i * 0.618, 1.0)) * sz.x * 0.6
		var p := c + Vector2(cos(a) * d, sin(a) * d * 0.55 + d * 0.25)
		var tw := 0.5 + 0.5 * sin(t * 7.0 + i * 1.7)
		fg.draw_circle(p, 2.0 + 2.5 * tw, Color(1, 1, 1, 0.35 + 0.35 * tw))
		if i % 6 == 0:
			_star(fg, p, 10.0 + 10.0 * tw, Color(1, 1, 0.85, 0.5 * tw))


func _star(ci: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	if r < 1.0:
		return
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r * 0.18, -r * 0.18), p + Vector2(r, 0),
		p + Vector2(r * 0.18, r * 0.18), p + Vector2(0, r), p + Vector2(-r * 0.18, r * 0.18), p + Vector2(-r, 0),
		p + Vector2(-r * 0.18, -r * 0.18)]), col)


## ¡Ándale! The cactus in a sombrero (CC0 clip art) hops across the bottom on the beat, kicking up dust, speed lines
## streaming behind it.
func _draw_cactus(sz: Vector2) -> void:
	var tx: Texture2D = tex.get("sombrero_cactus")
	if tx == null:
		return
	var u := _u(1.6, 4.6)
	var beat := t * BPM / 60.0
	var k := sz.y / 720.0
	var x := lerpf(-0.15, 1.15, u) * sz.x
	var hop := absf(sin(beat * PI)) * 60.0 * k
	var p := Vector2(x, sz.y * 0.74 - hop)
	for i in 6:   # speed lines
		var y := p.y - 60 * k + i * 26 * k
		fg.draw_line(Vector2(x - 120 * k - i * 14 * k, y), Vector2(x - 320 * k - i * 30 * k, y), Color(1, 1, 1, 0.55), 4.0)
	for i in 5:   # dust
		var age := fmod(t * 2.0 + i * 0.2, 1.0)
		fg.draw_circle(Vector2(x - 60 * k - age * 140 * k, sz.y * 0.86 - age * 30 * k), (10 + age * 26) * k, Color(0.85, 0.7, 0.5, 0.6 * (1.0 - age)))
	var s := 0.55 * k
	fg.draw_set_transform(p, sin(beat * PI) * 0.25, Vector2(s * (1.0 + 0.08 * sin(beat * TAU)), s * (1.0 - 0.08 * sin(beat * TAU))))
	fg.draw_texture(tx, -tx.get_size() / 2.0)
	fg.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The abuela: a warm silhouette in her rebozo (shawl) and glasses rising from the bottom-left corner. She winds up
## and throws the chancla at 5.7 s, then sinks back down, satisfied.
func _draw_abuela(sz: Vector2) -> void:
	var k := sz.y / 720.0
	var rise := _u(4.8, 5.3) * (1.0 - _u(7.3, 7.9))
	rise = 1.0 - pow(1.0 - rise, 3.0)
	var b := Vector2(sz.x * 0.13, sz.y + 140 * k - rise * sz.y * 0.5)
	var body := Color("3b1f3a")
	var rim := Color("ff9f1c")
	fg.draw_set_transform(b, sin(t * 3.0) * 0.03, Vector2(k, k))
	var torso := PackedVector2Array([Vector2(-70, -150), Vector2(70, -150), Vector2(115, 140), Vector2(-115, 140)])
	var torso_rim := PackedVector2Array([Vector2(-75, -156), Vector2(75, -156), Vector2(121, 144), Vector2(-121, 144)])
	fg.draw_colored_polygon(torso_rim, rim)
	fg.draw_colored_polygon(torso, body)
	for i in 4:   # the rebozo's stripes
		var y := -120.0 + i * 16.0
		fg.draw_line(Vector2(-72 - i * 2.5, y), Vector2(72 + i * 2.5, y), ZARAPE[i * 2 % ZARAPE.size()].darkened(0.1), 5.0)
	fg.draw_circle(Vector2(0, -205), 56, rim)
	fg.draw_circle(Vector2(0, -205), 52, Color("2a1528"))
	fg.draw_circle(Vector2(0, -265), 32, rim)
	fg.draw_circle(Vector2(0, -265), 29, Color("2a1528"))   # the bun
	fg.draw_circle(Vector2(18, -280), 6, Color("e63946"))   # a flower in it
	for side: float in [-1.0, 1.0]:   # her glasses, glinting
		fg.draw_arc(Vector2(side * 21, -205), 14, 0, TAU, 20, Color("fff3b0"), 3.0)
		fg.draw_circle(Vector2(side * 21 - 5, -210), 3, Color(1, 1, 1, 0.5 + 0.5 * sin(t * 6.0)))
	fg.draw_line(Vector2(-6, -205), Vector2(6, -205), Color("fff3b0"), 3.0)
	# the throwing arm: down, wound back over her head, then a snap forward at 5.7 s
	var a := 0.9
	if cyc < 5.7:
		a = lerpf(0.9, -2.5, smoothstep(0.0, 1.0, _u(5.25, 5.65)))
	else:
		a = lerpf(-2.5, 0.1, smoothstep(0.0, 1.0, _u(5.7, 5.82)))
	var sh := Vector2(62, -140)
	var hand := sh + Vector2(cos(a), sin(a)) * 95.0
	fg.draw_line(sh, hand, rim, 30.0)
	fg.draw_line(sh, hand, body, 24.0)
	fg.draw_circle(hand, 16, body)
	if cyc < 5.7:   # the chancla, ready in her hand
		_draw_chancla(fg, hand, a + PI / 2.0, 1.1)
	fg.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Where her hand is when she lets go (screen space).
func _abuela_hand(sz: Vector2) -> Vector2:
	var k := sz.y / 720.0
	var b := Vector2(sz.x * 0.13, sz.y + 140 * k - sz.y * 0.5)
	return b + (Vector2(62, -140) + Vector2(cos(-2.5), sin(-2.5)) * 95.0) * k


## The chancla in flight: spinning in an arc from her hand straight at his face (he's busy staring at the ring),
## SMACK (an impact star and burst lines), then it bounces off and drops away.
func _draw_flying_chancla(sz: Vector2) -> void:
	var k := sz.y / 720.0
	var face := _face(sz)
	if cyc < SMACK:
		var u := _u(5.7, SMACK)
		var p := _abuela_hand(sz).lerp(face, u) - Vector2(0, sin(u * PI) * sz.y * 0.22)
		for i in 4:   # a whoosh trail
			var w := maxf(u - 0.06 * (i + 1), 0.0)
			var q := _abuela_hand(sz).lerp(face, w) - Vector2(0, sin(w * PI) * sz.y * 0.22)
			fg.draw_circle(q, (16.0 - i * 3.0) * k * (1.0 + u), Color(1, 1, 1, 0.3 - i * 0.06))
		_draw_chancla(fg, p, u * TAU * 3.0, (1.1 + u * 1.3) * k)
		return
	var v := _u(SMACK, 7.3)
	var ia := clampf(1.0 - (cyc - SMACK) / 0.35, 0.0, 1.0)
	if ia > 0.0:   # the impact
		_star(fg, face, 170.0 * k * (1.0 + 0.3 * ia), Color(1, 0.85, 0.2, 0.75 * ia))
		for i in 10:
			var a := i * TAU / 10.0 + 0.2
			fg.draw_line(face + Vector2(cos(a), sin(a)) * 90.0 * k, face + Vector2(cos(a), sin(a)) * (160.0 + 40.0 * sin(i * 3.7)) * k,
				Color(1, 1, 1, 0.85 * ia), 4.0)
	var p2 := face + Vector2(-v * sz.x * 0.18, -sin(v * PI) * sz.y * 0.15 + v * v * sz.y * 0.9)
	_draw_chancla(fg, p2, 0.4 - v * 14.0, 2.4 * k)


## A flip-flop (in local units about 120 long): a pink sole with a darker edge, a blue V strap and its toe post.
func _draw_chancla(ci: CanvasItem, p: Vector2, rot: float, s: float) -> void:
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in 28:
		var th := i * TAU / 28.0
		var w := 18.0 + 9.0 * absf(sin(th)) + (4.0 if sin(th) < 0.0 else 0.0)
		var v := Vector2(cos(th) * w, sin(th) * 60.0)
		outer.append(p + v.rotated(rot) * s * 1.08)
		inner.append(p + v.rotated(rot) * s)
	ci.draw_colored_polygon(outer, Color("b8236f"))
	ci.draw_colored_polygon(inner, Color("ff4fa3"))
	for d in [Vector2(-8, 20), Vector2(9, 32), Vector2(-4, 44), Vector2(6, 8)]:
		ci.draw_circle(p + d.rotated(rot) * s, 3.0 * s, Color("ffd6ec"))
	var post := p + Vector2(0, -36).rotated(rot) * s
	ci.draw_line(post, p + Vector2(-20, -2).rotated(rot) * s, Color("2ec4f1"), 6.0 * s)
	ci.draw_line(post, p + Vector2(20, -2).rotated(rot) * s, Color("2ec4f1"), 6.0 * s)
	ci.draw_circle(post, 4.0 * s, Color("1478a0"))


func _pinata_pos(sz: Vector2) -> Vector2:
	var anchor := Vector2(sz.x * 0.74, 0.0)
	var drop := 1.0 - pow(1.0 - _u(8.2, 8.7), 3.0)
	var length := sz.y * 0.36 * drop
	var jolt := 0.0
	for h in PIN_HITS:
		if cyc > h:
			jolt += exp(-(cyc - h) * 4.0) * sin((cyc - h) * 18.0) * 0.35
	var a := sin(t * 2.8) * 0.18 + jolt
	return anchor + Vector2(sin(a), cos(a)) * length


## A seven-pointed star piñata on its rope: a bright ball with cone points and tassels, swinging.
func _draw_pinata(sz: Vector2) -> void:
	var k := sz.y / 720.0
	var p := _pinata_pos(sz)
	fg.draw_line(Vector2(sz.x * 0.74, 0), p, Color("e9d8a6"), 3.0)
	var spin := sin(t * 1.3) * 0.3
	for i in 7:
		var a := spin + i * TAU / 7.0 - PI / 2.0
		var d := Vector2(cos(a), sin(a))
		var n := Vector2(-d.y, d.x)
		var tip := p + d * 112.0 * k
		var col: Color = CONFETTI[i % CONFETTI.size()]
		fg.draw_colored_polygon(PackedVector2Array([p + d * 30.0 * k + n * 22.0 * k, tip, p + d * 30.0 * k - n * 22.0 * k]), col)
		fg.draw_line(p + d * 70.0 * k + n * 9.0 * k, p + d * 70.0 * k - n * 9.0 * k, Color(1, 1, 1, 0.8), 3.0)
		for j in 3:   # tassels
			var sw := sin(t * 5.0 + i + j) * 0.3
			fg.draw_line(tip, tip + (d.rotated(sw + (j - 1) * 0.35)) * 26.0 * k, CONFETTI[(i + j + 2) % CONFETTI.size()], 3.0)
	fg.draw_circle(p, 48.0 * k, Color("ff4fa3"))
	for r in [40.0, 30.0, 20.0]:   # frilled rings of paper
		fg.draw_arc(p, r * k, 0, TAU, 28, CONFETTI[int(r) % CONFETTI.size()], 6.0 * k)
	fg.draw_circle(p, 9.0 * k, Color("ffd23f"))


## The stick: swung up from the bottom-right corner at the piñata on each whack, with a ¡PUM! at the hit.
func _draw_stick(sz: Vector2) -> void:
	var k := sz.y / 720.0
	var pivot := Vector2(sz.x * 1.0, sz.y * 1.08)
	var target := _pinata_pos(sz) if cyc < 10.1 else Vector2(sz.x * 0.74, sz.y * 0.36)
	var aim := (target - pivot).angle()
	var s := 0.0
	for h in PIN_HITS:
		s = maxf(s, exp(-pow((cyc - h) / 0.09, 2.0)))
	var a := lerpf(aim + 0.55, aim, s)
	var length := (target - pivot).length() * 1.02
	var tip := pivot + Vector2(cos(a), sin(a)) * length
	fg.draw_line(pivot, tip, Color("5c3b1e"), 18.0 * k)
	fg.draw_line(pivot, tip, Color("8a5a2b"), 12.0 * k)
	for i in 6:   # ribbon stripes
		var q := pivot.lerp(tip, 0.3 + i * 0.1)
		fg.draw_circle(q, 7.0 * k, CONFETTI[i % CONFETTI.size()])


func _draw_candy(p: Vector2, rot: float, col: Color, k: float) -> void:
	var d := Vector2(cos(rot), sin(rot))
	var n := Vector2(-d.y, d.x)
	for side: float in [-1.0, 1.0]:
		var e := p + d * side * 10.0 * k
		fg.draw_colored_polygon(PackedVector2Array([e, e + (d * side * 9.0 + n * 7.0) * k, e + (d * side * 9.0 - n * 7.0) * k]), col.lightened(0.3))
	fg.draw_circle(p, 9.0 * k, col)
	fg.draw_line(p - n * 8.0 * k, p + n * 8.0 * k, Color(1, 1, 1, 0.8), 2.0)


## A tortilla boinging across the screen: squashed when it lands, stretched as it flies, spinning.
func _draw_tortilla(sz: Vector2) -> void:
	var k := sz.y / 720.0
	var u := _u(14.3, 16.9)
	if u <= 0.0 or u >= 1.0:
		return
	var floor_y := sz.y * 0.82
	var arc := absf(sin(u * PI * 4.0))
	var p := Vector2(lerpf(-0.1, 1.1, u) * sz.x, floor_y - arc * sz.y * 0.4)
	var squash := 1.0 - 0.35 * maxf(0.0, 1.0 - arc * 6.0)
	fg.draw_set_transform(p, sin(u * 25.0) * 0.4, Vector2(k / squash, k * squash * (1.0 + 0.15 * arc)))
	fg.draw_circle(Vector2.ZERO, 74, Color("c99a4b"))
	fg.draw_circle(Vector2.ZERO, 70, Color("f2dc9b"))
	for i in 11:   # toasted spots
		var a := i * 2.399
		var r := 18.0 + fmod(i * 23.0, 44.0)
		fg.draw_circle(Vector2(cos(a), sin(a)) * r, 5.0 + fmod(i * 3.3, 5.0), Color("b5803a"))
	fg.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A lucha libre mask slamming in over spinning sun rays: blue with a gold forehead flame, white-trimmed eyes (with
## eyes in them, looking about) and a grinning mouth. It bulges in time with the screen.
func _draw_lucha(sz: Vector2) -> void:
	var k := sz.y / 720.0
	var c := Vector2(sz.x / 2.0, sz.y * 0.47)
	var u := _u(17.0, 17.45)
	var out := _u(18.6, 19.0)
	var s := _elastic(u) * (1.0 + out * 1.5) * k * 1.15
	var alpha := 1.0 - out
	for i in 18:   # the rays
		var a := t * 1.2 + i * TAU / 18.0
		var w := PI / 18.0 * 0.6
		var r := sz.length() * 0.6 * _elastic(u)
		var col := Color(1, 0.84, 0.2, 0.55 * alpha) if i % 2 == 0 else Color(0.9, 0.15, 0.2, 0.45 * alpha)
		fg.draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(a - w), sin(a - w)) * r, c + Vector2(cos(a + w), sin(a + w)) * r]), col)
	if s <= 0.01:
		return
	fg.draw_set_transform(c, sin(t * 4.0) * 0.06, Vector2(s, s))
	var head := PackedVector2Array()
	var trim := PackedVector2Array()
	for i in 40:
		var a := i * TAU / 40.0
		var v := Vector2(cos(a) * 118.0, sin(a) * 150.0 + (12.0 if sin(a) > 0.0 else 0.0) * sin(a))
		head.append(v)
		trim.append(v * 1.06)
	fg.draw_colored_polygon(trim, Color(1, 0.84, 0.25, alpha))
	fg.draw_colored_polygon(head, Color(0.12, 0.3, 0.85, alpha))
	fg.draw_colored_polygon(PackedVector2Array([Vector2(0, -148), Vector2(34, -90), Vector2(16, -40), Vector2(0, -20),
		Vector2(-16, -40), Vector2(-34, -90)]), Color(1, 0.84, 0.25, alpha))   # the forehead flame
	for side: float in [-1.0, 1.0]:
		fg.draw_colored_polygon(PackedVector2Array([Vector2(side * 118, -10), Vector2(side * 70, -40), Vector2(side * 96, 20),
			Vector2(side * 70, 60), Vector2(side * 115, 40)]), Color(0.9, 0.12, 0.2, alpha))   # flames at the temples
		var eye := PackedVector2Array()
		var eye_trim := PackedVector2Array()
		for i in 20:
			var a := i * TAU / 20.0
			var v := Vector2(side * 48 + cos(a) * 34.0 * (1.0 + 0.3 * side * cos(a)), -6 + sin(a) * 22.0)
			eye.append(v)
			eye_trim.append(Vector2(side * 48, -6) + (v - Vector2(side * 48, -6)) * 1.3)
		fg.draw_colored_polygon(eye_trim, Color(1, 1, 1, alpha))
		fg.draw_colored_polygon(eye, Color(0.08, 0.05, 0.1, alpha))
		var look := Vector2(sin(t * 3.0) * 10.0, cos(t * 2.3) * 4.0)
		fg.draw_circle(Vector2(side * 48, -6) + look * 0.5, 15, Color(1, 1, 1, alpha))
		fg.draw_circle(Vector2(side * 48, -6) + look, 7, Color(0.1, 0.05, 0.0, alpha))
	fg.draw_circle(Vector2(0, 92), 34, Color(1, 1, 1, alpha))
	fg.draw_circle(Vector2(0, 92), 28, Color(0.08, 0.05, 0.1, alpha))
	fg.draw_arc(Vector2(0, 86), 20, 0.3, PI - 0.3, 12, Color(1, 1, 1, alpha), 6.0)   # the grin
	fg.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _sombrero_drop_centre(sz: Vector2) -> Vector2:
	return Vector2(sz.x / 2.0, lerpf(-sz.y * 0.2, sz.y * 0.95, _u(21.0, 21.8)))


## Where the falling sombrero carries the ring: on its brim, in front of the crown.
func _sombrero_drop_pos(sz: Vector2) -> Vector2:
	var u := _u(21.0, 21.8)
	return _sombrero_drop_centre(sz) + Vector2(-90.0, -45.0) * lerpf(0.25, 7.5, u * u * u) * sz.y / 720.0


## The giant sombrero: falls from above (growing as it comes), lands on the camera -- we see its woven underside, dark
## -- and is flung off upward, spinning.
func _draw_sombrero_drop(sz: Vector2) -> void:
	var k := sz.y / 720.0
	if cyc < 21.8:
		var u := _u(21.0, 21.8)
		var s := lerpf(0.25, 7.5, u * u * u) * k
		fg.draw_set_transform(_sombrero_drop_centre(sz), sin(u * 7.0) * 0.25, Vector2(s, s))
		_draw_sombrero(fg)
		fg.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var lift := _u(22.45, 22.8)
	var off := Vector2(lift * sz.x * 0.3, -lift * lift * sz.y * 1.4)
	var c := sz / 2.0 + off
	fg.draw_set_transform(c, lift * 0.8, Vector2.ONE * (1.0 + lift * 0.3))
	var r := sz.length() * 0.75
	fg.draw_circle(Vector2.ZERO, r, Color("3a2510"))
	for i in 14:   # the weave
		fg.draw_arc(Vector2.ZERO, r * (0.12 + i * 0.065), 0, TAU, 64, Color("5a3a18"), 5.0 * k)
	for i in 24:
		var a := i * TAU / 24.0
		fg.draw_line(Vector2(cos(a), sin(a)) * r * 0.12, Vector2(cos(a), sin(a)) * r, Color("4a2e12"), 3.0 * k)
	fg.draw_circle(Vector2.ZERO, r * 0.12, Color("1a0f05"))   # inside the crown
	fg.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Defeat: a little sombrero drifting down like a leaf and landing sadly at the bottom.
func _draw_sad_sombrero(sz: Vector2) -> void:
	var k := sz.y / 720.0
	var u := clampf(t / 3.0, 0.0, 1.0)
	var swing := sin(t * 3.0) * 0.4 * (1.0 - u)
	var p := Vector2(sz.x * 0.5 + sin(t * 3.0) * sz.x * 0.08 * (1.0 - u), lerpf(-sz.y * 0.1, sz.y * 0.9, u))
	fg.draw_set_transform(p, swing, Vector2(0.22, 0.22) * k)
	_draw_sombrero(fg)
	fg.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------- drawing: captions (above the screen effects)

func _draw_top() -> void:
	var sz := top.size
	var k := sz.y / 720.0
	match mode:
		Mode.VICTORY:
			if line == 0:
				_wobble_text("CONGRATULATIONS!", Vector2(sz.x / 2.0, sz.y * 0.42), int(84 * k), t, 99.0, 1.0, 0.0)
		Mode.FIESTA:
			var hidden := _in(19.0, 21.0) or _in(21.8, 22.5)
			if not hidden:
				var y := sz.y * (0.17 if not _in(17.0, 19.0) else 0.12)
				_wobble_text("¡¡¡AY AY AY!!!", Vector2(sz.x / 2.0, y), int(60 * k), t, 99.0, 0.8, kick["chroma"] * 300.0)
			for cp in CAPTIONS:
				if _in(cp[0], cp[1]):
					var age: float = cyc - cp[0]
					var life: float = cp[1] - cp[0]
					var fs := int(float(cp[3]) * k)
					var y: float = sz.y * cp[4]
					if cp[2] == "¡AY AY AYYYYY!":   # rising with the siren
						y -= _u(19.0, 21.0) * sz.y * 0.25
					_wobble_text(cp[2], Vector2(sz.x / 2.0, y), fs, age, life, cp[5], kick["chroma"] * 400.0)
			if _in(SMACK, SMACK + 0.7):   # the chancla's ¡PUM!
				_wobble_text("¡PUM!", _face(sz) + Vector2(200, 40) * k, int(78 * k), cyc - SMACK, 0.7, 0.8, 4.0)
			for i in PIN_HITS.size() - 1:   # ¡PUM! ¡PAZ! at the piñata's whacks
				var h: float = PIN_HITS[i]
				if _in(h, h + 0.5):
					var p := _pinata_pos(sz) + Vector2(-90, 60) * k
					_wobble_text(["¡PUM!", "¡PAZ!"][i], p, int(54 * k), cyc - h, 0.5, 0.6, 3.0)


## Bouncy, wobbly text: each letter pops in after the one before (elastic), bobs and rocks on its own, and cycles
## through the rainbow; `rgb` > 0 adds red/cyan ghost copies (an RGB split) that far apart. Scaled down to fit the
## screen's width.
func _wobble_text(text: String, center: Vector2, fsize: int, age: float, life: float, wob: float, rgb: float) -> void:
	var f := ThemeDB.fallback_font
	var widths: Array[float] = []
	var total := 0.0
	for ch in text:
		var w := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		widths.append(w)
		total += w
	var fit := minf(1.0, top.size.x * 0.94 / maxf(total, 1.0))
	var out := clampf((life - age) / 0.2, 0.0, 1.0)
	var x := -total / 2.0
	var outline := maxi(4, fsize / 7)
	for i in text.length():
		var ch := text[i]
		var pop := _elastic(clampf((age - i * minf(0.03, 0.3 / text.length())) / 0.35, 0.0, 1.0)) * out
		if pop > 0.01 and ch != " ":
			var cx := x + widths[i] / 2.0
			var y := sin(t * 9.0 + i * 0.7) * fsize * 0.1 * wob
			var rot := sin(t * 7.0 + i * 1.3) * 0.12 * wob
			var stretch := 1.0 + 0.12 * wob * sin(t * 11.0 + i)
			top.draw_set_transform(center + Vector2(cx * fit, y), rot, Vector2(pop * fit, pop * fit * stretch))
			var base := Vector2(-widths[i] / 2.0, fsize * 0.35)
			if rgb > 0.5:
				top.draw_string(f, base + Vector2(-rgb, 0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(1, 0, 0.2, 0.6))
				top.draw_string(f, base + Vector2(rgb, 0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0, 0.9, 1, 0.6))
			top.draw_string_outline(f, base, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, outline, Color.BLACK)
			top.draw_string(f, base, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color.from_hsv(fmod(i * 0.07 + t * 0.4, 1.0), 0.75, 1.0))
		x += widths[i]
	top.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
