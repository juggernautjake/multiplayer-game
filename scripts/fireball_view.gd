## The fireball in flight (v0.8.0), purely visual: Main flies it along the server's path and turns it to face the way
## it's going; this makes it burn. Every fireball is a little different (its size, how red or yellow it burns, how fast
## it churns): a white-hot core inside two shells of flame that churn, swell and flicker at their own rates, the whole
## orb wobbling in flight; a flickering light; a trail of embers, a ribbon of smoke behind it, and sparks spitting off.
class_name FireballView
extends MeshInstance3D

var _t := 0.0
var _seed := 0.0
var _shells: Array = []
var _core: MeshInstance3D
var _light: OmniLight3D
var _size := 1.0


static func _glow(c: Color, energy: float, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _init() -> void:
	_seed = randf() * 100.0
	_size = randf_range(0.9, 1.15)
	var hot := randf_range(-0.04, 0.05)   # some burn redder, some yellower
	var sm := SphereMesh.new()
	sm.radius = 0.22 * _size
	sm.height = 0.44 * _size
	sm.radial_segments = 16
	sm.rings = 8
	mesh = sm
	material_override = _glow(Color.from_hsv(0.07 + hot, 0.9, 1.0), 5.0)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_core = MeshInstance3D.new()
	var cs := SphereMesh.new()
	cs.radius = 0.13 * _size
	cs.height = 0.26 * _size
	_core.mesh = cs
	_core.material_override = _glow(Color("fff4c0"), 9.0)
	add_child(_core)
	for i in 2:   # flame shells: see-through, added light, churning
		var sh := MeshInstance3D.new()
		var ss := SphereMesh.new()
		ss.radius = (0.3 + 0.08 * i) * _size
		ss.height = ss.radius * 2.0
		ss.radial_segments = 10
		ss.rings = 6
		sh.mesh = ss
		sh.material_override = _glow(Color.from_hsv(0.04 + hot + 0.03 * i, 0.95, 1.0), 3.0, 0.35 - 0.12 * i)
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sh)
		_shells.append(sh)
	_light = OmniLight3D.new()
	_light.light_color = Color("ff9a3a")
	_light.light_energy = 2.5
	_light.omni_range = 5.5
	add_child(_light)
	add_child(_particles(70, 0.5, 0.15, 0.3, 1.3, Vector3(0, 1.5, 0), 0.09, Color(1.0, 0.85, 0.3, 1.0), Color(0.7, 0.12, 0.04, 0.0), true))
	add_child(_particles(26, 1.1, 0.12, 0.1, 0.5, Vector3(0, 1.2, 0), 0.16, Color(0.3, 0.27, 0.25, 0.45), Color(0.2, 0.2, 0.2, 0.0), false, 2.2))
	var sparks := _particles(14, 0.35, 0.1, 2.5, 5.0, Vector3(0, -6.0, 0), 0.025, Color(1.0, 0.95, 0.6, 1.0), Color(1.0, 0.5, 0.1, 0.0), true)
	sparks.spread = 180.0
	add_child(sparks)


func _particles(n: int, life: float, rad: float, vmin: float, vmax: float, grav: Vector3, size: float, c0: Color,
		c1: Color, add: bool, grow := 1.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = n
	p.lifetime = life
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = rad * _size
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = grav
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	if grow != 1.0:
		var curve := Curve.new()
		curve.add_point(Vector2(0, 0.6))
		curve.add_point(Vector2(1, grow))
		p.scale_amount_curve = curve
	var pm := SphereMesh.new()
	pm.radius = size
	pm.height = size * 2.0
	pm.radial_segments = 6
	pm.rings = 3
	p.mesh = pm
	var grad := Gradient.new()
	grad.set_color(0, c0)
	grad.set_color(1, c1)
	p.color_ramp = grad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if add:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	p.material_override = m
	return p


func _process(delta: float) -> void:
	_t += delta
	var t := _t + _seed
	# the orb wobbles off its line a little and swells and shrinks as it burns
	_core.position = Vector3(sin(t * 13.0) * 0.03, cos(t * 11.0) * 0.03, 0)
	for i in _shells.size():
		var sh: MeshInstance3D = _shells[i]
		var k := 1.0 + 0.14 * sin(t * (17.0 + 6.0 * i)) + 0.08 * sin(t * (29.0 - 5.0 * i))
		sh.scale = Vector3(k, 1.0 + 0.12 * sin(t * (21.0 + 3.0 * i)), k * 1.15)
		sh.rotation = Vector3(t * (3.0 + i), t * (5.0 - 2.0 * i), 0)
		sh.position = Vector3(sin(t * (9.0 + i)) * 0.04, cos(t * (7.0 + 2.0 * i)) * 0.04, 0.05 * i)
	_light.light_energy = 2.2 + 0.6 * sin(t * 23.0) + 0.4 * sin(t * 37.0) + randf_range(-0.2, 0.2)
