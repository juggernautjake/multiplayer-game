## Movement effects (v0.8.0), purely visual: dust kicked up by running feet, a ring of dust on a hard landing,
## afterimages streaking behind a dash (Pip: fading copies of his sprite; the 3D figure: speed lines), so moving reads
## as fast and weighty from any camera.
class_name MotionFx

static var _dust_mat: StandardMaterial3D


static func _dust() -> StandardMaterial3D:
	if _dust_mat == null:
		_dust_mat = StandardMaterial3D.new()
		_dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dust_mat.vertex_color_use_as_albedo = true
	return _dust_mat


## A few soft puffs at the feet: `count` of them, spread `spread` metres.
static func puff(parent: Node, at: Vector3, count := 2, spread := 0.6) -> void:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = maxi(count, 1)
	p.lifetime = 0.55
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	sm.radial_segments = 6
	sm.rings = 3
	p.mesh = sm
	p.material_override = _dust()
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.15 * spread
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.4 * spread
	p.gravity = Vector3(0, 0.6, 0)
	p.damping_min = 2.0
	p.damping_max = 3.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.6
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, Color(0.72, 0.66, 0.56, 0.55))
	g.set_color(1, Color(0.72, 0.66, 0.56, 0.0))
	p.color_ramp = g
	parent.add_child(p)
	p.global_position = at + Vector3(0, 0.08, 0)
	p.emitting = true
	p.finished.connect(p.queue_free)


## A hard landing: a flat ring of dust racing out and a few puffs; `k` 0.3 (a hop) .. 1.4 (a long fall).
static func land(parent: Node, at: Vector3, k: float) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.75
	tm.outer_radius = 1.0
	tm.rings = 20
	tm.ring_segments = 4
	ring.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.7, 0.6, 0.5 * clampf(k, 0.3, 1.0))
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ring)
	ring.global_position = at + Vector3(0, 0.05, 0)
	ring.scale = Vector3(0.3, 0.12, 0.3)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(1.0 + k, 0.12, 1.0 + k), 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.4)
	tw.chain().tween_callback(ring.queue_free)
	puff(parent, at, 3 + int(k * 4.0), 0.8 + k)


## Pip's dash: a fading copy of the frame he's showing, tinted with his colour.
static func ghost_sprite(parent: Node, sprite: Sprite3D, tint: Color) -> void:
	var g := Sprite3D.new()
	g.texture = sprite.texture
	g.region_enabled = true
	g.region_rect = sprite.region_rect
	g.pixel_size = sprite.pixel_size
	g.billboard = sprite.billboard
	g.texture_filter = sprite.texture_filter
	g.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	g.transparent = true
	g.shaded = false
	g.double_sided = true
	g.centered = sprite.centered
	g.offset = sprite.offset
	g.flip_h = sprite.flip_h
	g.modulate = Color(tint.r, tint.g, tint.b, 0.5)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(g)
	g.global_transform = sprite.global_transform
	var tw := g.create_tween()
	tw.tween_property(g, "modulate:a", 0.0, 0.22)
	tw.tween_callback(g.queue_free)


## The figure's dash: thin bright lines streaking back from the body.
static func speed_lines(parent: Node, at: Vector3, dir: Vector3, tint: Color) -> void:
	var d := Vector3(dir.x, 0, dir.z)
	if d.length() < 0.1:
		return
	d = d.normalized()
	for i in 3:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.025, 0.025, 1.0)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(tint.r, tint.g, tint.b, 0.6)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		var side := d.cross(Vector3.UP) * randf_range(-0.35, 0.35)
		var start := at + Vector3(0, randf_range(0.4, 1.6), 0) + side
		mi.global_position = start - d * 0.6
		mi.look_at(mi.global_position + d, Vector3.UP)
		mi.scale = Vector3(1, 1, randf_range(0.8, 1.6))
		var tw := mi.create_tween().set_parallel(true)
		tw.tween_property(mi, "global_position", start - d * 1.6, 0.18)
		tw.tween_property(m, "albedo_color:a", 0.0, 0.18)
		tw.chain().tween_callback(mi.queue_free)
