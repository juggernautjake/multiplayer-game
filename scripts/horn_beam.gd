## Thunderhorn's horn beam on screen (v0.12.0), owned by BossView. The whole sequence, from his state:
##   BEAM_WIND  two thin feeder beams shoot from the tips of his curved side horns and meet just ahead of the nose
##              spike's tip, where an orb of light forms: a white-hot core in a cyan glow, three rings spinning on
##              different axes, crackling, growing and pulsing faster and brighter (its growth IS the telegraph), energy
##              packets running along the feeders into it, a rising whine (Synth "beam_hum").
##   BEAM       the main beam fires out of the orb (the orb stays as the emitter, flaring): a hot white core, a cyan glow
##              and a faint halo (BEAM_SHADER: additive, falling off from the centre line, packets flowing out along it,
##              the width and brightness pulsing, the core jittering), tendrils spiralling off it, three lights along
##              it lighting the ground and anyone near, a muzzle flare at the orb, a sparking, smoking impact where it
##              meets the ground and a glowing scorch trail along the sweep; a crackling, warbling roar (Synth "beam").
##              The feeders keep pumping while it fires.
##   after      everything collapses into the orb with a pop.
## Geometry: Boss.beam_ends(position, heading) - the orb (origin) and the ground point; the glow's radius is
## Boss.BEAM_R, the hitbox's radius: what you see is what hits you. The heading is the server's beam angle (smoothed),
## and the head turns with it, so the spike, the orb and the beam stay lined up through the sweep.
class_name HornBeam
extends Node3D

const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(0.6, 0.95, 1.0, 1.0);
uniform float energy = 3.0;
uniform float power = 2.0;
uniform float flow = 0.35;
uniform float speed = 1.6;
uniform float len = 20.0;
uniform float fade = 1.0;
float h(float n) { return fract(sin(n) * 43758.5453); }
float n1(float x) { float i = floor(x); float f = fract(x); return mix(h(i), h(i + 1.0), f * f * (3.0 - 2.0 * f)); }
void fragment() {
	float f = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float rad = pow(f, power);
	float y = UV.y * len;
	float run = y * flow - TIME * speed * 6.0;
	float packets = 0.55 + 0.45 * smoothstep(0.35, 0.95, n1(run)) + 0.25 * sin(run * 3.1);
	float flick = 0.85 + 0.15 * n1(TIME * 31.0 + y * 0.7);
	float ends = smoothstep(0.0, 0.03, UV.y) * smoothstep(1.0, 0.97, UV.y);
	ALBEDO = col.rgb * energy * rad * packets * flick * fade * mix(1.0, ends, 0.6);
}
"""

const CORE := Color("ffffff")
const GLOW := Color("5fe8ff")
const HALO := Color("2a8cff")

var view: Node3D          # the BossView (for _arc and sounds)
var fx: MagicFx
var main: Node3D
var core: MeshInstance3D
var glow: MeshInstance3D
var halo: MeshInstance3D
var feeders: Array = []   # [glow, core] per side
var orb: Node3D
var orb_core: MeshInstance3D
var orb_glow: MeshInstance3D
var orb_rings: Array = []
var flare: MeshInstance3D
var lights: Array = []
var impact_light: OmniLight3D
var _aim := 0.0
var _was := false
var _t_trail := 0.0
var _t_spark := 0.0
var _mats: Array = []


func setup(v: Node3D, m: Node3D, mfx: MagicFx) -> void:
	view = v
	main = m
	fx = mfx
	var sh := Shader.new()
	sh.code = BEAM_SHADER
	core = _tube(sh, CORE, 3.2, 1.2)
	glow = _tube(sh, GLOW, 1.3, 1.6)
	halo = _tube(sh, HALO, 0.4, 3.0)
	for i in 2:
		feeders.append([_tube(sh, GLOW, 1.4, 1.8), _tube(sh, CORE, 2.6, 1.4)])
	orb = Node3D.new()
	add_child(orb)
	orb_glow = MeshInstance3D.new()
	orb_glow.mesh = _sphere(1.0)
	orb_glow.material_override = _mat(sh, GLOW, 3.5, 1.6)
	orb.add_child(orb_glow)
	orb_core = MeshInstance3D.new()
	orb_core.mesh = _sphere(0.45)
	orb_core.material_override = MagicFx._glow_mat(CORE, 9.0)
	orb.add_child(orb_core)
	for i in 3:
		var r := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.92
		tm.outer_radius = 1.0
		tm.rings = 40
		tm.ring_segments = 6
		r.mesh = tm
		var rm := MagicFx._glow_mat(GLOW.lerp(CORE, 0.4), 6.0, 0.85)
		rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		r.material_override = rm
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		orb.add_child(r)
		orb_rings.append(r)
	flare = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	flare.mesh = q
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.albedo_texture = _flare_tex()
	fm.albedo_color = Color(0.75, 0.95, 1.0)
	fm.no_depth_test = false
	flare.material_override = fm
	flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flare)
	for i in 3:
		var l := OmniLight3D.new()
		l.light_color = GLOW
		l.omni_range = 9.0
		l.shadow_enabled = false
		add_child(l)
		lights.append(l)
	_hide_all()


func _tube(sh: Shader, c: Color, energy: float, power: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 1.0
	cm.radial_segments = 20
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	mi.mesh = cm
	mi.material_override = _mat(sh, c, energy, power)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _mat(sh: Shader, c: Color, energy: float, power: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("col", c)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("power", power)
	_mats.append(m)
	return m


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 20
	s.rings = 12
	return s


## A soft round flare with four thin rays (made once).
static var _ftex: ImageTexture
static func _flare_tex() -> ImageTexture:
	if _ftex != null:
		return _ftex
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0
			var v := (y + 0.5) / n * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			var a := exp(-r * r * 9.0) + 0.35 * exp(-r * 2.5)
			a += 0.6 * exp(-absf(u) * 60.0) * maxf(1.0 - absf(v), 0.0) + 0.6 * exp(-absf(v) * 60.0) * maxf(1.0 - absf(u), 0.0)
			a = clampf(a, 0.0, 1.0)
			img.set_pixel(x, y, Color(a, a, a, a))   # premultiplied: it is drawn additively
	_ftex = ImageTexture.create_from_image(img)
	return _ftex


func _hide_all() -> void:
	for n in [core, glow, halo, orb, flare]:
		(n as Node3D).visible = false
	for f in feeders:
		(f[0] as Node3D).visible = false
		(f[1] as Node3D).visible = false
	for l in lights:
		(l as OmniLight3D).visible = false


## Place a tube from a to b with radius r.
static func _place(t: MeshInstance3D, a: Vector3, b: Vector3, r: float) -> void:
	var x := WizardGarb._xf(a, b)
	t.global_transform = Transform3D(Basis(x.basis.x * r, x.basis.y, x.basis.z * r), x.origin)


## Every frame. st: the boss state, st_t: seconds in it, base: his position (smoothed x/z, server y), yaw: his body
## heading, beam_a: the server's beam angle, model: his BossModel (horn tips), enraged: red-shifted colours.
func tick(delta: float, st: int, st_t: float, base: Vector3, yaw: float, beam_a: float, model: BossModel, enraged: bool) -> void:
	var winding := st == Boss.S.BEAM_WIND
	var firing := st == Boss.S.BEAM
	if not winding and not firing:
		if _was:   # everything collapses into the orb with a pop
			_was = false
			var at := orb.global_position
			Fx.burst(main, at, Vector3.UP, GLOW, 26, 7.0, 0.05)
			fx._flash_light(at, GLOW, 7.0, 12.0, 0.2)
			if view.has_method("_sound"):
				view._sound("pop", at, 4.0)
			_hide_all()
		return
	var tint := Color("ff9a8a") if enraged else GLOW
	for m: ShaderMaterial in _mats:
		m.set_shader_parameter("col", CORE if m == (core.material_override as ShaderMaterial) else (tint if m != (halo.material_override as ShaderMaterial) else (Color("ff4a3a") if enraged else HALO)))
	if not _was:
		_aim = yaw
	_was = true
	_aim = lerp_angle(_aim, beam_a if firing else yaw, clampf(delta * 45.0, 0.0, 1.0))
	var ends := Boss.beam_ends(base, _aim, yaw)
	var o: Vector3 = ends[0]
	var e: Vector3 = ends[1]
	var now := Time.get_ticks_msec() * 0.001
	# the orb: grows through the wind-up (the tell), then stays as the emitter, flaring
	var grow := 1.0 - exp(-st_t * 2.6) if winding else 1.0
	var pulse := 1.0 + (0.08 + 0.12 * grow) * sin(now * (10.0 + 22.0 * grow)) + randf_range(-0.04, 0.04)
	var orb_r := (0.18 + 0.72 * grow) * pulse * (1.15 if firing else 1.0)
	orb.visible = true
	orb.global_position = o
	orb.scale = Vector3.ONE * orb_r
	(orb_glow.material_override as ShaderMaterial).set_shader_parameter("energy", 1.0 + 1.8 * grow + (1.0 if firing else 0.0))
	for i in orb_rings.size():
		var r: MeshInstance3D = orb_rings[i]
		var sp := (3.0 + 5.0 * grow) * (1.0 + i * 0.4)
		r.rotation = Vector3(now * sp * (0.7 if i == 0 else 0.2), now * sp * (1.0 if i == 1 else 0.3), now * sp * (0.9 if i == 2 else 0.15)) \
			+ Vector3(i * 1.1, i * 0.7, i * 2.0)
		r.scale = Vector3.ONE * (1.15 + 0.2 * i + 0.1 * sin(now * 7.0 + i))
	# the feeders: from the side horns' tips into the orb, shooting out over the first 0.2 s
	var tips := [model.anchors["horn_l"], model.anchors["horn_r"]]
	var reach := clampf(st_t / 0.2, 0.0, 1.0) if winding else 1.0
	for i in 2:
		var a: Vector3 = (tips[i] as Node3D).global_position
		var b := a.lerp(o, reach)
		var fw: MeshInstance3D = feeders[i][0]
		var fc: MeshInstance3D = feeders[i][1]
		fw.visible = true
		fc.visible = true
		var wob := 1.0 + 0.25 * sin(now * 37.0 + i * 2.0)
		_place(fw, a, b, 0.16 * wob * (0.7 + 0.5 * grow))
		_place(fc, a, b, 0.05 * wob)
		(fw.material_override as ShaderMaterial).set_shader_parameter("len", a.distance_to(b))
		(fw.material_override as ShaderMaterial).set_shader_parameter("speed", -1.2 - 1.5 * grow)
		(fc.material_override as ShaderMaterial).set_shader_parameter("speed", -1.2 - 1.5 * grow)
		if randf() < delta * (6.0 + 14.0 * grow):   # crackling along the feeders
			view._arc(a.lerp(b, randf()), a.lerp(b, randf()) + Vector3(randf_range(-0.6, 0.6), randf_range(-0.6, 0.6), randf_range(-0.6, 0.6)), tint, 0.08)
	if winding and randf() < delta * (8.0 + 20.0 * grow):   # the orb crackles
		var d := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		view._arc(o + d * orb_r * 0.6, o + d * orb_r * randf_range(1.6, 2.6), tint, 0.07)
	# the lights: at the orb while charging; along the beam while it fires
	var l0: OmniLight3D = lights[0]
	l0.visible = true
	l0.global_position = o
	l0.light_color = tint
	l0.light_energy = (1.0 + 4.0 * grow) * pulse * (1.6 if firing else 1.0)
	l0.omni_range = 6.0 + 6.0 * grow
	flare.visible = firing or grow > 0.6
	flare.global_position = o
	var fs := (3.0 + 1.5 * sin(now * 41.0) + randf_range(-0.4, 0.4)) if firing else 2.2 * grow
	flare.scale = Vector3.ONE * fs
	if not firing:
		for n in [core, glow, halo]:
			(n as Node3D).visible = false
		(lights[1] as OmniLight3D).visible = false
		(lights[2] as OmniLight3D).visible = false
		return
	# the beam: three layers, the visible glow's radius = the hitbox (Boss.BEAM_R)
	var w := 1.0 + 0.1 * sin(now * 23.0) + 0.06 * sin(now * 57.0) + randf_range(-0.04, 0.04)
	var j := Vector3(randf_range(-0.05, 0.05), randf_range(-0.05, 0.05), randf_range(-0.05, 0.05))
	var blen := o.distance_to(e)
	_place(core, o + j, e + j * 0.5, 0.2 * w)
	_place(glow, o, e, Boss.BEAM_R * w)
	_place(halo, o, e, Boss.BEAM_R * 2.2 * w)
	for n in [core, glow, halo]:
		(n as Node3D).visible = true
		((n as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("len", blen)
	(core.material_override as ShaderMaterial).set_shader_parameter("energy", 3.2 + 1.0 * sin(now * 31.0))
	var l1: OmniLight3D = lights[1]
	var l2: OmniLight3D = lights[2]
	l1.visible = true
	l2.visible = true
	l1.global_position = o.lerp(e, 0.5) + Vector3(0, 0.6, 0)
	l2.global_position = e + Vector3(0, 0.8, 0)
	for l: OmniLight3D in [l1, l2]:
		l.light_color = tint
		l.light_energy = (3.0 + randf() * 1.5) * w
		l.omni_range = 10.0
	# tendrils spiralling off the beam
	if randf() < delta * 22.0:
		var u0 := randf_range(0.05, 0.85)
		var axis := (e - o).normalized()
		var side := axis.cross(Vector3.UP).normalized()
		var up := side.cross(axis).normalized()
		var pts := PackedVector3Array()
		var a0 := randf() * TAU
		var turns := randf_range(1.0, 2.0) * (1.0 if randf() < 0.5 else -1.0)
		var span := randf_range(2.0, 4.5)
		for k in 14:
			var s := float(k) / 13.0
			var ang := a0 + turns * TAU * s
			var rr := Boss.BEAM_R * (0.7 + 1.4 * s)
			pts.append(o.lerp(e, u0) + axis * span * s + (side * cos(ang) + up * sin(ang)) * rr)
		var arc := fx._ribbons([[pts, 0.035]], tint.lightened(0.3), 7.0)
		var tw := arc.create_tween()
		tw.tween_property(arc.material_override, "albedo_color:a", 0.0, 0.14)
		tw.tween_callback(arc.queue_free)
	# the impact: sparks, smoke, and a glowing scorch trail along the sweep
	_t_spark -= delta
	if _t_spark <= 0.0:
		_t_spark = 0.04
		Fx.burst(main, e + Vector3(0, 0.15, 0), Vector3.UP, tint.lightened(0.4), 6, 7.0, 0.04)
		if randf() < 0.3:
			Fx.burst(main, e + Vector3(0, 0.1, 0), Vector3.UP, Color("ffcf70"), 3, 5.0, 0.03)
	_t_trail -= delta
	if _t_trail <= 0.0:
		_t_trail = 0.035
		_scorch(e)
		if randf() < 0.35:
			fx._smoke(e, 1, 0.8, 1.0, 0.35)
		if randf() < 0.25:
			fx._scorch_ragged(e, 0.9, 3)


## A glowing scorch mark that cools from white-cyan to a dark burn over ~2 s.
func _scorch(at: Vector3) -> void:
	var m := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.3, 1.3)
	m.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = _flare_tex()
	mat.albedo_color = Color(0.7, 0.95, 1.0, 0.9)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(m)
	m.global_position = Vector3(at.x, at.y + 0.04 + randf() * 0.01, at.z)
	m.rotation.y = randf() * TAU
	var tw := m.create_tween()
	tw.tween_property(mat, "albedo_color", Color(1.0, 0.45, 0.15, 0.6), 0.5)
	tw.tween_property(mat, "albedo_color", Color(0.4, 0.1, 0.02, 0.0), 1.6)
	tw.tween_callback(m.queue_free)
