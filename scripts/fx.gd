## Combat effects, purely visual: slash trails that sweep through the air on a swing, impact bursts (sparks, straw,
## dust) and short impact words. They make the hits read from any camera angle, even when Pip's body hides the weapon.
class_name Fx

const SLASH_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform vec4 col : source_color = vec4(1.0);
uniform float progress = 0.0;  // how far the leading edge has swept (0..1 along the arc)
uniform float fade = 1.0;
void fragment() {
	float u = UV.x;                       // along the arc
	float v = UV.y;                       // across the ribbon (0 inner, 1 outer)
	float head = step(u, progress);
	float tail = smoothstep(progress - 0.75, progress, u);
	float edge = smoothstep(0.0, 0.35, v) * (1.0 - smoothstep(0.75, 1.0, v));
	float a = head * tail * edge * fade;
	ALBEDO = col.rgb * (0.6 + 0.8 * smoothstep(0.4, 0.9, v));
	ALPHA = a * col.a;
}
"""

static var _shader: Shader


## A crescent ribbon around the player at `pos` facing `yaw`: radius r, `span` degrees, tilted for an overhead smash.
static func slash(parent: Node, pos: Vector3, yaw: float, r: float, span: float, color: Color, overhead := false, flip := false) -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SLASH_SHADER
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := 24
	var inner := r * 0.45
	for i in n + 1:
		var u := float(i) / n
		var a := deg_to_rad(lerpf(span / 2.0, -span / 2.0, u) * (-1.0 if flip else 1.0))
		var dir := Vector3(sin(a), 0, -cos(a))
		var droop := sin(u * PI) * 0.15
		st.set_uv(Vector2(u, 0.0))
		st.add_vertex(dir * inner + Vector3(0, -droop, 0))
		st.set_uv(Vector2(u, 1.0))
		st.add_vertex(dir * r + Vector3(0, droop * 0.5, 0))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("col", color)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, 1.15 if not overhead else 1.0, 0)
	mi.rotation = Vector3(0, yaw, 0)
	if overhead:   # a vertical arc, top to front-bottom
		mi.rotation = Vector3(0, yaw, 0)
		mi.rotate_object_local(Vector3(0, 0, 1), PI / 2.0)
	else:
		mi.rotate_object_local(Vector3(1, 0, 0), deg_to_rad(-12.0))   # a slight diagonal cut
	var tw := mi.create_tween()
	tw.tween_method(func(p: float): mat.set_shader_parameter("progress", p), 0.0, 1.35, 0.11)
	tw.tween_method(func(f: float): mat.set_shader_parameter("fade", f), 1.0, 0.0, 0.16)
	tw.tween_callback(mi.queue_free)


## A straight streak driven forward from the chest (a thrust or a punch).
static func thrust(parent: Node, pos: Vector3, yaw: float, reach: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.05, 1.0)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var start := pos + Vector3(0, 1.2, 0) + fwd * 0.4
	mi.global_position = start
	mi.rotation.y = yaw
	mi.scale = Vector3(1, 1, 0.05)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(1.6, 1.6, reach), 0.08).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "global_position", start + fwd * reach * 0.5, 0.08)
	tw.chain().tween_property(m, "albedo_color:a", 0.0, 0.14)
	tw.chain().tween_callback(mi.queue_free)


## A flat ring that grows along the ground (smash).
static func shockwave(parent: Node, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.5
	tm.outer_radius = 0.62
	mi.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	mi.material_override = m
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.05, 0)
	mi.scale = Vector3(0.4, 0.2, 0.4)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(3.2, 0.2, 3.2), 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.35)
	tw.chain().tween_callback(mi.queue_free)


## A one-shot burst of little cubes flying out from `pos` along `dir`: sparks (sword), straw (dummy), dust (club).
static func burst(parent: Node, pos: Vector3, dir: Vector3, color: Color, count := 14, speed := 5.0, size := 0.06) -> void:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = count
	p.lifetime = 0.45
	var bm := BoxMesh.new()
	bm.size = Vector3(size, size, size)
	p.mesh = bm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	p.material_override = m
	var d := dir.normalized() if dir.length_squared() > 1e-6 else Vector3.UP
	p.direction = (d + Vector3(0, 0.6, 0)).normalized()
	p.spread = 55.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -14, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


## A short word that pops at the hit ("Thock!", "Shing!").
static func word(parent: Node, pos: Vector3, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 52
	l.outline_size = 14
	l.modulate = color
	parent.add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.4, 0.4), 0.9, 0)
	l.scale = Vector3.ONE * 0.4
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector3.ONE * 1.15, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector3.ONE, 0.06)
	tw.tween_interval(0.25)
	tw.tween_property(l, "modulate:a", 0.0, 0.2)
	tw.tween_callback(l.queue_free)
