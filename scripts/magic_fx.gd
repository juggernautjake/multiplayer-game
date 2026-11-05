## What spells look like (Jacob 2026-11-04), drawn on every client from the server's spell events (Net.magic_fx) and
## from each player's state (shield bubbles, stuns):
##   lightning: a glowing warning ring where it will land, then a jagged bolt from the sky with side forks, a white
##              flash, sparks and a scorch mark;
##   fireball:  a burning orb trailing embers (MagicFx.fireball_node, flown by Main like any projectile), bursting in a
##              growing ball of fire, smoke, sparks and a scorch mark;
##   shield:    a see-through bubble with a bright rim and drifting bands; wherever something strikes it, a bright spot
##              flares and a ring of light runs out across the bubble from that point;
##   stun:      a violet bolt from the wand, then a ring of spinning stars over the stunned player's head;
##   teleport:  a violet puff where you left and where you arrive, joined by a fading streak;
##   golems:    dust and a cracked ring as one rises; a dust ring and a thud when one slams.
class_name MagicFx
extends Node3D

const BUBBLE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.35, 0.75, 1.0, 1.0);
uniform vec3 hits[6];
uniform float hit_t[6];
uniform float fade = 1.0;
varying vec3 lpos;
void vertex() { lpos = normalize(VERTEX); }
void fragment() {
	float fres = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.6);
	float a = 0.05 + fres * 0.6;
	a += (0.5 + 0.5 * sin(lpos.y * 16.0 + TIME * 2.2)) * 0.035;
	a += (0.5 + 0.5 * sin((lpos.x + lpos.z) * 11.0 - TIME * 1.5)) * 0.025;
	float glow = 0.0;
	for (int i = 0; i < 6; i++) {
		float t = hit_t[i];
		if (t < 1.1) {
			float ang = acos(clamp(dot(lpos, hits[i]), -1.0, 1.0));
			float ring = exp(-pow((ang - t * 2.9) / 0.17, 2.0)) * (1.0 - t / 1.1);
			float spot = exp(-pow(ang / 0.28, 2.0)) * max(0.0, 1.0 - t * 2.5);
			glow += ring * 1.3 + spot * 2.0;
		}
	}
	ALBEDO = tint.rgb * (1.0 + glow * 2.2);
	ALPHA = clamp((a + glow) * fade, 0.0, 1.0);
}
"""

var net: Net
var main: Node3D
var avatars := {}            # set by Main every frame: id -> avatar
var bubbles := {}            # player id -> { node, mat, hits: [[dir, t]] }
var stuns := {}              # player id -> Node3D (the star ring)
var _shader: Shader
var _vault_door: Node3D      # set by Main: the door's hinge
var _door_target := 0.0


func setup(n: Net, m: Node3D) -> void:
	net = n
	main = m
	_shader = Shader.new()
	_shader.code = BUBBLE_SHADER
	net.magic_fx.connect(_on_fx)


# ================================================================ events from the server
func _on_fx(kind: String, a: Array) -> void:
	match kind:
		"lightning_warn":
			_warn_ring(a[0], float(a[1]) * Config.DT)
		"lightning":
			_bolt(a[0])
		"explode":
			_explosion(a[0], float(a[1]))
		"cast":
			if avatars.has(a[0]):
				var av: Node3D = avatars[a[0]]
				Fx.burst(main, av.position + Vector3(0, 1.5, 0), Vector3.UP, Color("ffb347"), 10, 2.5, 0.05)
		"shield_up":
			if avatars.has(a[0]):
				var av: Node3D = avatars[a[0]]
				Fx.burst(main, av.position + Vector3(0, 1.0, 0), Vector3.UP, Color("8fd8ff"), 22, 3.0, 0.05)
		"shield_hit":
			_shield_hit(int(a[0]), a[1])
		"stun_beam":
			_stun_beam(a[1], a[2], int(a[3]) != 0)
		"teleport":
			_puff(a[1])
			_puff(a[2])
			_streak(a[1] + Vector3(0, 1.0, 0), a[2] + Vector3(0, 1.0, 0), Color("c58cff"), 0.35)
		"golem_rise":
			_golem_dust(a[1], 0.9)
		"golem_slam":
			_golem_dust(a[1], 0.9)
			_shake_near(a[1], 0.12)
		"vault_door":
			_door_target = -1.7 if a[0] else 0.0


# ================================================================ every frame
func update(delta: float, states: Dictionary) -> void:
	# shield bubbles follow their players; impacts age
	for id in states.keys():
		var st: Sim.PlayerState = states[id]
		var on := st != null and st.shield > 0 and st.dead == 0 and avatars.has(id)
		if on and not bubbles.has(id):
			bubbles[id] = _make_bubble()
		if bubbles.has(id):
			var b: Dictionary = bubbles[id]
			if not on:
				Fx.burst(main, (b.node as Node3D).global_position, Vector3.UP, Color("8fd8ff"), 18, 3.5, 0.05)
				(b.node as Node3D).queue_free()
				bubbles.erase(id)
			else:
				(b.node as Node3D).global_position = (avatars[id] as Node3D).position + Vector3(0, 0.95, 0)
				var flicker := 1.0 if st.shield > 60 else (0.45 + 0.55 * absf(sin(st.shield * 0.35)))
				var mat: ShaderMaterial = b.mat
				mat.set_shader_parameter("fade", flicker)
				var dirs := PackedVector3Array()
				var ts := PackedFloat32Array()
				for h in b.hits:
					h[1] += delta
				b.hits = b.hits.filter(func(h): return h[1] < 1.1)
				for i in 6:
					if i < b.hits.size():
						dirs.append(b.hits[i][0])
						ts.append(b.hits[i][1])
					else:
						dirs.append(Vector3.UP)
						ts.append(9.0)
				mat.set_shader_parameter("hits", dirs)
				mat.set_shader_parameter("hit_t", ts)
		# stars over a stunned head
		var stunned := st != null and st.stun > 0 and st.dead == 0 and avatars.has(id)
		if stunned and not stuns.has(id):
			stuns[id] = _make_stars()
		if stuns.has(id):
			var ring: Node3D = stuns[id]
			if not stunned:
				ring.queue_free()
				stuns.erase(id)
			else:
				ring.global_position = (avatars[id] as Node3D).position + Vector3(0, 2.15, 0)
				ring.rotation.y += delta * 5.0
	for id in bubbles.keys():
		if not states.has(id):
			(bubbles[id].node as Node3D).queue_free()
			bubbles.erase(id)
	if _vault_door:
		_vault_door.rotation.y = lerpf(_vault_door.rotation.y, _door_target, clampf(delta * 4.0, 0.0, 1.0))


# ================================================================ pieces
static func _glow_mat(c: Color, energy := 3.0, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _flash_light(at: Vector3, c: Color, energy: float, reach: float, life: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = reach
	main.add_child(l)
	l.global_position = at
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, life)
	tw.tween_callback(l.queue_free)


func _fade_out(n: Node3D, mat: StandardMaterial3D, life: float, delay := 0.0) -> void:
	var tw := n.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(mat, "albedo_color:a", 0.0, life)
	tw.tween_callback(n.queue_free)


func _disc(at: Vector3, r: float, c: Color, alpha: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.01
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	mi.material_override = m
	main.add_child(mi)
	mi.global_position = at + Vector3(0, 0.02, 0)
	return mi


func _scorch(at: Vector3, r: float) -> void:
	var d := _disc(at, r, Color(0.08, 0.06, 0.05), 0.55)
	_fade_out(d, d.material_override, 6.0, 4.0)


func _warn_ring(at: Vector3, life: float) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.75
	tm.outer_radius = 3.0
	ring.mesh = tm
	var m := _glow_mat(Color("bfe4ff"), 2.5, 0.8)
	ring.material_override = m
	ring.scale = Vector3(1, 0.05, 1)
	main.add_child(ring)
	ring.global_position = at + Vector3(0, 0.05, 0)
	var inner := _disc(at, 3.0, Color("9fd0ff"), 0.12)
	var tw := ring.create_tween().set_loops(int(ceil(life / 0.16)))
	tw.tween_property(m, "albedo_color:a", 0.25, 0.08)
	tw.tween_property(m, "albedo_color:a", 0.9, 0.08)
	get_tree().create_timer(life + 0.05).timeout.connect(func():
		ring.queue_free()
		inner.queue_free())
	Fx.burst(main, at + Vector3(0, 0.2, 0), Vector3.UP, Color("cfe8ff"), 8, 1.5, 0.04)


## A jagged line of glowing boxes from a to b, kinked `kinks` times by up to `wild` metres.
func _jag(a: Vector3, b: Vector3, kinks: int, wild: float, width: float, c: Color) -> Node3D:
	var root := Node3D.new()
	main.add_child(root)
	var pts := [a]
	for i in range(1, kinks):
		var t := float(i) / kinks
		pts.append(a.lerp(b, t) + Vector3(randf_range(-wild, wild), randf_range(-wild, wild) * 0.3, randf_range(-wild, wild)))
	pts.append(b)
	var mat := _glow_mat(c, 6.0, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in pts.size() - 1:
		var p: Vector3 = pts[i]
		var q: Vector3 = pts[i + 1]
		var seg := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(width, width, p.distance_to(q) + width)
		seg.mesh = bm
		seg.material_override = mat
		root.add_child(seg)
		seg.global_position = (p + q) / 2.0
		if p.distance_to(q) > 1e-3:
			seg.look_at_from_position(seg.global_position, q, Vector3.UP if absf((q - p).normalized().y) < 0.99 else Vector3.RIGHT)
	root.set_meta("mat", mat)
	root.set_meta("pts", pts)
	return root


func _bolt(at: Vector3) -> void:
	var top := at + Vector3(randf_range(-3, 3), 34.0, randf_range(-3, 3))
	var main_bolt := _jag(top, at, 14, 1.6, 0.16, Color("e8f4ff"))
	var parts := [main_bolt]
	var pts: Array = main_bolt.get_meta("pts")
	for k in 3:   # forks off the main bolt
		var from: Vector3 = pts[randi_range(4, pts.size() - 4)]
		var to := from + Vector3(randf_range(-5, 5), randf_range(-7, -3), randf_range(-5, 5))
		parts.append(_jag(from, to, 5, 0.9, 0.07, Color("b8dcff")))
	for p: Node3D in parts:   # flicker, then fade
		var mat: StandardMaterial3D = p.get_meta("mat")
		var tw := p.create_tween()
		tw.tween_property(mat, "albedo_color:a", 0.2, 0.05)
		tw.tween_property(mat, "albedo_color:a", 1.0, 0.04)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.3)
		tw.tween_callback(p.queue_free)
	_flash_light(at + Vector3(0, 3, 0), Color("dceeff"), 9.0, 18.0, 0.35)
	Fx.burst(main, at + Vector3(0, 0.2, 0), Vector3.UP, Color("e8f6ff"), 30, 7.0, 0.05)
	Fx.burst(main, at + Vector3(0, 0.1, 0), Vector3.UP, Color("6b6b70"), 14, 2.0, 0.09)
	_scorch(at, 1.8)
	_shake_near(at, 0.2)


func _explosion(at: Vector3, r: float) -> void:
	for spec in [[Color("ff8a2a"), 0.95, 0.35], [Color("ffe066"), 0.55, 0.22]]:
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		ball.mesh = sm
		var m := _glow_mat(spec[0], 4.0, 0.9)
		ball.material_override = m
		main.add_child(ball)
		ball.global_position = at
		ball.scale = Vector3.ONE * 0.2
		var tw := ball.create_tween().set_parallel(true)
		tw.tween_property(ball, "scale", Vector3.ONE * r * float(spec[1]), float(spec[2])).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(m, "albedo_color:a", 0.0, float(spec[2]) + 0.15).set_delay(0.06)
		tw.chain().tween_callback(ball.queue_free)
	for i in 6:   # smoke puffs drifting up
		var puff := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = randf_range(0.35, 0.6)
		sm.height = sm.radius * 2.0
		puff.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.25, 0.23, 0.22, 0.6)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		puff.material_override = m
		main.add_child(puff)
		puff.global_position = at + Vector3(randf_range(-1, 1), randf_range(0.2, 1.0), randf_range(-1, 1))
		var tw := puff.create_tween().set_parallel(true)
		tw.tween_property(puff, "global_position", puff.global_position + Vector3(randf_range(-0.6, 0.6), 2.2, randf_range(-0.6, 0.6)), 1.4)
		tw.tween_property(puff, "scale", Vector3.ONE * 1.8, 1.4)
		tw.tween_property(m, "albedo_color:a", 0.0, 1.4)
		tw.chain().tween_callback(puff.queue_free)
	_flash_light(at + Vector3(0, 1, 0), Color("ffa040"), 7.0, r * 4.0, 0.45)
	Fx.burst(main, at, Vector3.UP, Color("ffcf5a"), 36, 8.0, 0.05)
	_scorch(Vector3(at.x, WorldLayout.ground_height(at.x, at.z, at.y + 0.2), at.z), r * 0.6)
	_shake_near(at, 0.18)


## The fireball in flight: a burning orb with a light, trailing embers. Main moves it along its path.
static func fireball_node() -> Node3D:
	var n := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	n.mesh = sm
	n.material_override = _glow_mat(Color("ff7a1a"), 5.0)
	var core := MeshInstance3D.new()
	var cs := SphereMesh.new()
	cs.radius = 0.13
	cs.height = 0.26
	core.mesh = cs
	core.material_override = _glow_mat(Color("fff0a0"), 8.0)
	n.add_child(core)
	var l := OmniLight3D.new()
	l.light_color = Color("ff9a3a")
	l.light_energy = 2.5
	l.omni_range = 5.0
	n.add_child(l)
	var trail := CPUParticles3D.new()
	trail.amount = 60
	trail.lifetime = 0.45
	trail.local_coords = false
	trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	trail.emission_sphere_radius = 0.15
	trail.direction = Vector3.UP
	trail.spread = 180.0
	trail.initial_velocity_min = 0.3
	trail.initial_velocity_max = 1.2
	trail.gravity = Vector3(0, 1.5, 0)
	trail.scale_amount_min = 0.5
	trail.scale_amount_max = 1.0
	var pm := SphereMesh.new()
	pm.radius = 0.09
	pm.height = 0.18
	trail.mesh = pm
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.3, 1.0))
	grad.set_color(1, Color(0.6, 0.1, 0.05, 0.0))
	trail.color_ramp = grad
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.vertex_color_use_as_albedo = true
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail.material_override = tm
	n.add_child(trail)
	return n


func _make_bubble() -> Dictionary:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = Weapons.SHIELD_RADIUS
	sm.height = Weapons.SHIELD_RADIUS * 2.0
	sm.radial_segments = 48
	sm.rings = 24
	mi.mesh = sm
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(mi)
	mi.scale = Vector3.ONE * 0.2
	mi.create_tween().tween_property(mi, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return { "node": mi, "mat": mat, "hits": [] }


func _shield_hit(id: int, at: Vector3) -> void:
	if bubbles.has(id):
		var b: Dictionary = bubbles[id]
		var c := (b.node as Node3D).global_position
		var d := (at - c)
		b.hits.push_front([d.normalized() if d.length() > 1e-3 else Vector3.UP, 0.0])
		if b.hits.size() > 6:
			b.hits.resize(6)
	Fx.burst(main, at, (at - (avatars[id].position + Vector3(0, 0.95, 0)) if avatars.has(id) else Vector3.UP), Color("aee6ff"), 12, 4.0, 0.04)
	_flash_light(at, Color("8fd8ff"), 2.0, 4.0, 0.2)


func _stun_beam(from: Vector3, to: Vector3, hit: bool) -> void:
	var beam := _jag(from, to, maxi(3, int(from.distance_to(to) / 1.5)), 0.25, 0.06, Color("c070ff"))
	var mat: StandardMaterial3D = beam.get_meta("mat")
	var tw := beam.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tw.tween_callback(beam.queue_free)
	Fx.burst(main, to, Vector3.UP, Color("d39bff"), 18 if hit else 8, 3.5, 0.05)
	_flash_light(to, Color("b066ff"), 2.5, 5.0, 0.3)


func _make_stars() -> Node3D:
	var ring := Node3D.new()
	main.add_child(ring)
	for i in 4:
		var s := MeshInstance3D.new()
		var sm := PrismMesh.new()
		sm.size = Vector3(0.14, 0.14, 0.04)
		s.mesh = sm
		s.material_override = _glow_mat(Color("ffe46b") if i % 2 == 0 else Color("d39bff"), 3.0)
		var a := TAU * i / 4.0
		s.position = Vector3(cos(a) * 0.38, 0.0, sin(a) * 0.38)
		ring.add_child(s)
	return ring


func _puff(at: Vector3) -> void:
	Fx.burst(main, at + Vector3(0, 1.0, 0), Vector3.UP, Color("c58cff"), 28, 3.5, 0.06)
	_flash_light(at + Vector3(0, 1, 0), Color("b066ff"), 3.0, 5.0, 0.35)


func _streak(a: Vector3, b: Vector3, c: Color, life: float) -> void:
	var s := _jag(a, b, 2, 0.0, 0.25, c)
	var mat: StandardMaterial3D = s.get_meta("mat")
	mat.albedo_color.a = 0.5
	var tw := s.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, life)
	tw.tween_callback(s.queue_free)


func _golem_dust(at: Vector3, r: float) -> void:
	Fx.burst(main, at + Vector3(0, 0.2, 0), Vector3.UP, Color("9a8f80"), 24, 3.0, 0.08)
	var ring := _disc(at, r, Color(0.35, 0.3, 0.26), 0.5)
	ring.scale = Vector3(0.3, 1, 0.3)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(1.6, 1, 1.6), 0.5)
	tw.tween_property(ring.material_override, "albedo_color:a", 0.0, 0.6)
	tw.chain().tween_callback(ring.queue_free)


func _shake_near(at: Vector3, amount: float) -> void:
	if avatars.has(net.my_id) and (avatars[net.my_id] as Node3D).position.distance_to(at) < 12.0:
		main.set("shake", maxf(float(main.get("shake")), amount))
