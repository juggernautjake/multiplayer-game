## What spells look like (Jacob 2026-11-04), drawn on every client from the server's spell events (Net.magic_fx) and
## from each player's state (shield bubbles, stuns):
##   lightning: a glowing warning ring where it will land, then a jagged bolt from the sky with side forks, a white
##              flash, sparks and a scorch mark;
##   fireball:  a burning orb trailing embers (MagicFx.fireball_node, flown by Main like any projectile), bursting in a
##              growing ball of fire, smoke, sparks and a scorch mark;
##   shield:    a see-through bubble with a bright rim and drifting bands; wherever something strikes it, a bright spot
##              flares and a ring of light runs out across the bubble from that point;
##   stun:      a violet bolt from the wand that bursts in a crackling violet ring where it lands; everyone caught
##              gets a ring of spinning stars over their head;
##   teleport:  a violet puff where you left and where you arrive, joined by a fading streak;
##   golems:    dust and a cracked ring as one rises; a dust ring and a thud when one slams;
##   frost nova: a ring of ice racing out from the caster, ice shards bursting up along it, a cold flash, frost on the
##              ground, and a frosty ring at the feet of everyone it slowed;
##   earth spikes: stone spikes stabbing up out of the ground one after another, in dust;
##   meteor:    a red target ring, a burning rock streaking down from the sky trailing fire and smoke, then a huge
##              blast, flying rocks, a shockwave ring, a crater, and flames on the ground for 3 s;
##   gravity well: a dark violet vortex: a black core, spinning rings, motes spiralling in, a violet light pulsing;
##              then it collapses and bursts outward;
##   level up:  a column of golden light round the player and the new spell's name;
##   shatter:   a shield that runs out of mana bursts into glowing shards.
## Every caster glows while casting (and while holding the shield up): a light in the spell's colour at the staff or
## wand, growing as the spell builds, with sparks drawn in toward it.
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
var cast_lights := {}        # player id -> OmniLight3D at their staff / wand while casting
var frosts := {}             # player id -> the frosty ring at the feet of a slowed player
const SPELL_COLOR := { "Lightning": Color("cfe6ff"), "Fireball": Color("ff8a2a"), "Shield": Color("7fd0ff"),
	"Frost Nova": Color("9fe8ff"), "Golem": Color("ffb02e"), "Teleport": Color("c070ff"), "Stun": Color("c070ff"),
	"Earth Spikes": Color("d8a060"), "Meteor": Color("ff5a1a"), "Gravity Well": Color("8a3cff") }
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
		"frost_nova":
			_frost_nova(a[1], float(a[2]))
		"stun_burst":
			_stun_burst(a[0], float(a[1]))
		"meteor_warn":
			_meteor_fall(a[0], float(a[1]) * Config.DT, float(a[2]))
		"meteor":
			_meteor_hit(a[0], float(a[1]), float(a[2]) * Config.DT, float(a[3]))
		"well":
			_well(a[0], float(a[1]) * Config.DT, float(a[2]))
		"well_burst":
			_well_burst(a[0], float(a[1]))
		"spike":
			_spike(a[0])
		"level_up":
			_level_up(int(a[0]), int(a[1]), int(a[2]), str(a[3]))
		"shield_shatter":
			_shatter(int(a[0]), a[1])


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
				if not b.get("shattered", false):
					Fx.burst(main, (b.node as Node3D).global_position, Vector3.UP, Color("8fd8ff"), 18, 3.5, 0.05)
				(b.node as Node3D).queue_free()
				bubbles.erase(id)
			else:
				(b.node as Node3D).global_position = (avatars[id] as Node3D).position + Vector3(0, 0.95, 0)
				var low := float(st.mana) / float(Sim.MANA_FULL)
				var flicker := 1.0 if low > 0.25 else (0.5 + 0.5 * absf(sin(Time.get_ticks_msec() * 0.02)))
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
	_cast_glow(delta, states)
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
	l.shadow_enabled = energy >= 8.0   # only the biggest flashes throw shadows (they're costly)
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


# ================================================================ casting glow, frost, spikes, level-ups, shatters
## While a player casts (or holds the shield), a light in the spell's colour burns at their staff / wand, swelling as
## the spell builds and flaring as it goes off; sparks are drawn in toward it. Slowed players get frost at their feet.
func _cast_glow(delta: float, states: Dictionary) -> void:
	for id in states.keys():
		var st: Sim.PlayerState = states[id]
		var av: Node3D = avatars.get(id, null)
		var on := st != null and av != null and st.dead == 0 and Weapons.is_magic(st.weapon) and (st.atk > 0 or st.shield > 0)
		if on and not cast_lights.has(id):
			var l := OmniLight3D.new()
			l.omni_range = 5.0
			main.add_child(l)
			cast_lights[id] = l
		if cast_lights.has(id):
			var l: OmniLight3D = cast_lights[id]
			if not on:
				l.queue_free()
				cast_lights.erase(id)
			else:
				var sp := Weapons.spell(st.weapon, st.spell)
				var c: Color = SPELL_COLOR.get(str(sp.name), Color.WHITE)
				var fwd := Vector3(-sin(av.yaw), 0, -cos(av.yaw))
				var hand := av.position + Vector3(0, 1.6 if st.shield > 0 else 1.45, 0) + fwd * 0.4
				var k := 1.0
				if st.atk > 0 and int(sp.cast) > 0:
					var into := int(sp.cast) - st.atk
					k = clampf(float(into) / float(maxi(int(sp.windup), 1)), 0.0, 1.0)
					if into >= int(sp.windup):
						k = clampf(1.6 - float(into - int(sp.windup)) * 0.08, 0.0, 1.6)   # the flare, then fading
				l.global_position = hand
				l.light_color = c
				l.light_energy = 0.6 + 3.2 * k + (0.4 * sin(Time.get_ticks_msec() * 0.03) if st.shield > 0 else 0.0)
				if randf() < delta * 30.0 * k:   # sparks drawn in toward the staff
					var off := Vector3(randf_range(-1, 1), randf_range(-0.6, 1), randf_range(-1, 1)).normalized() * 0.7
					Fx.burst(main, hand + off, -off, c, 1, 2.0, 0.035)
		var slowed := st != null and av != null and st.slow > 0 and st.dead == 0
		if slowed and not frosts.has(id):
			var d := _disc(av.position, 0.7, Color("bfefff"), 0.45)
			frosts[id] = d
		if frosts.has(id):
			var d: MeshInstance3D = frosts[id]
			if not slowed:
				d.queue_free()
				frosts.erase(id)
			else:
				d.global_position = Vector3(av.position.x, WorldLayout.ground_height(av.position.x, av.position.z, av.position.y) + 0.03, av.position.z)
				if randf() < delta * 10.0:
					Fx.burst(main, av.position + Vector3(randf_range(-0.4, 0.4), randf_range(0.2, 1.6), randf_range(-0.4, 0.4)), Vector3.DOWN, Color("dff6ff"), 1, 0.6, 0.03)


func _frost_nova(at: Vector3, r: float) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.85
	tm.outer_radius = 1.0
	ring.mesh = tm
	var m := _glow_mat(Color("aeeeff"), 3.5, 0.9)
	ring.material_override = m
	main.add_child(ring)
	ring.global_position = at + Vector3(0, 0.15, 0)
	ring.scale = Vector3(0.3, 0.4, 0.3)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(r, 0.4, r), 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.5).set_delay(0.15)
	tw.chain().tween_callback(ring.queue_free)
	for i in 22:   # ice shards bursting up round the ring, each a moment after the wave reaches it
		var a := randf() * TAU
		var d := randf_range(1.2, r)
		var shard := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(randf_range(0.2, 0.4), randf_range(0.5, 1.2), randf_range(0.2, 0.35))
		shard.mesh = pm
		var sm := _glow_mat(Color("cdf6ff"), 1.2, 0.85)
		shard.material_override = sm
		main.add_child(shard)
		shard.global_position = at + Vector3(cos(a) * d, -0.6, sin(a) * d)
		shard.rotation = Vector3(randf_range(-0.4, 0.4), randf() * TAU, randf_range(-0.4, 0.4))
		var st := shard.create_tween()
		st.tween_interval(0.35 * d / r)
		st.tween_property(shard, "global_position:y", at.y + pm.size.y * 0.4, 0.08)
		st.tween_interval(0.9)
		st.tween_property(sm, "albedo_color:a", 0.0, 0.6)
		st.tween_callback(shard.queue_free)
	_flash_light(at + Vector3(0, 1.5, 0), Color("9fe8ff"), 6.0, r * 2.5, 0.5)
	Fx.burst(main, at + Vector3(0, 0.6, 0), Vector3.UP, Color("e6faff"), 40, 7.0, 0.04)
	var frost := _disc(at, r * 0.85, Color("d8f6ff"), 0.16)
	_fade_out(frost, frost.material_override, 2.5, 2.0)
	_shake_near(at, 0.1)


func _spike(at: Vector3) -> void:
	var spike := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.42
	cm.height = 1.7
	cm.radial_segments = 6
	spike.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("7a6a58")
	m.roughness = 0.95
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spike.material_override = m
	main.add_child(spike)
	spike.global_position = at + Vector3(0, -0.9, 0)
	spike.rotation = Vector3(randf_range(-0.2, 0.2), randf() * TAU, randf_range(-0.2, 0.2))
	var tw := spike.create_tween()
	tw.tween_property(spike, "global_position:y", at.y + 0.75, 0.07).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.7)
	tw.tween_property(spike, "global_position:y", at.y - 1.0, 0.5)
	tw.tween_callback(spike.queue_free)
	Fx.burst(main, at + Vector3(0, 0.2, 0), Vector3.UP, Color("9a8f80"), 14, 4.0, 0.07)
	_flash_light(at + Vector3(0, 0.6, 0), Color("ffb060"), 1.5, 3.0, 0.2)
	_shake_near(at, 0.06)


func _level_up(id: int, w: int, lv: int, spell: String) -> void:
	if not avatars.has(id):
		return
	var at: Vector3 = (avatars[id] as Node3D).position
	var col := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.7
	cm.bottom_radius = 0.9
	cm.height = 9.0
	col.mesh = cm
	var m := _glow_mat(Color("ffd86a"), 3.0, 0.45)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	col.material_override = m
	main.add_child(col)
	col.global_position = at + Vector3(0, 4.5, 0)
	var tw := col.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 1.6)
	tw.tween_callback(col.queue_free)
	_flash_light(at + Vector3(0, 2, 0), Color("ffd86a"), 6.0, 10.0, 1.2)
	Fx.burst(main, at + Vector3(0, 1.0, 0), Vector3.UP, Color("ffe9a0"), 50, 6.0, 0.05)
	var what := ("%s LEVEL %d!" % [Weapons.NAMES[w].to_upper(), lv]) + ("  New spell: " + spell if spell != "" else "")
	Fx.word(main, at + Vector3(0, 2.6, 0), what, Color("ffd86a"))
	if id == net.my_id and main.has_method("toast"):
		main.toast(what + ("  (R to pick it)" if spell != "" else ""))


func _shatter(id: int, at: Vector3) -> void:
	if bubbles.has(id):
		bubbles[id].shattered = true
		(bubbles[id].node as Node3D).visible = false
	for i in 40:   # glowing glass shards flying out and falling
		var shard := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(randf_range(0.08, 0.22), randf_range(0.1, 0.28), 0.02)
		shard.mesh = pm
		var sm := _glow_mat(Color("aee6ff"), 2.5, 0.9)
		shard.material_override = sm
		main.add_child(shard)
		var dir := Vector3(randf_range(-1, 1), randf_range(-0.3, 1), randf_range(-1, 1)).normalized()
		shard.global_position = at + dir * Weapons.SHIELD_RADIUS
		shard.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var to := shard.global_position + dir * randf_range(1.5, 3.5) + Vector3(0, -1.2, 0)
		var tw := shard.create_tween().set_parallel(true)
		tw.tween_property(shard, "global_position", to, 0.7).set_ease(Tween.EASE_OUT)
		tw.tween_property(shard, "rotation", shard.rotation + Vector3(randf_range(-8, 8), randf_range(-8, 8), 0), 0.7)
		tw.tween_property(sm, "albedo_color:a", 0.0, 0.8).set_delay(0.2)
		tw.chain().tween_callback(shard.queue_free)
	_flash_light(at, Color("aee6ff"), 5.0, 7.0, 0.4)
	Fx.burst(main, at, Vector3.UP, Color("e6faff"), 30, 6.0, 0.04)
	Fx.word(main, at + Vector3(0, 1.4, 0), "SHATTERED!", Color("aee6ff"))
	_shake_near(at, 0.16)


func _stun_burst(at: Vector3, r: float) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	ring.mesh = tm
	var m := _glow_mat(Color("c070ff"), 4.0, 0.9)
	ring.material_override = m
	main.add_child(ring)
	ring.global_position = Vector3(at.x, WorldLayout.ground_height(at.x, at.z, at.y + 0.3) + 0.08, at.z)
	ring.scale = Vector3(0.2, 0.3, 0.2)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(r, 0.3, r), 0.22).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.5).set_delay(0.2)
	tw.chain().tween_callback(ring.queue_free)
	var dome := _disc(ring.global_position, r, Color("b066ff"), 0.14)
	_fade_out(dome, dome.material_override, 0.6)
	for k in 6:   # little arcs crackling round the edge
		var a := randf() * TAU
		var p0 := ring.global_position + Vector3(cos(a) * r, 0.1, sin(a) * r)
		var p1 := ring.global_position + Vector3(cos(a + 0.5) * r, randf_range(0.3, 0.9), sin(a + 0.5) * r)
		var arc := _jag(p0, p1, 3, 0.15, 0.04, Color("e0b0ff"))
		var am: StandardMaterial3D = arc.get_meta("mat")
		var at2 := arc.create_tween()
		at2.tween_property(am, "albedo_color:a", 0.0, 0.3)
		at2.tween_callback(arc.queue_free)
	_flash_light(at + Vector3(0, 1, 0), Color("b066ff"), 5.0, r * 3.0, 0.4)


func _meteor_fall(at: Vector3, fall: float, r: float) -> void:
	var ring := MeshInstance3D.new()   # the target: a red ring that tightens as the rock comes down
	var tm := TorusMesh.new()
	tm.inner_radius = 0.93
	tm.outer_radius = 1.0
	ring.mesh = tm
	var m := _glow_mat(Color("ff3a1a"), 3.0, 0.85)
	ring.material_override = m
	main.add_child(ring)
	ring.global_position = at + Vector3(0, 0.06, 0)
	ring.scale = Vector3(r * 1.4, 0.2, r * 1.4)
	var rt := ring.create_tween()
	rt.tween_property(ring, "scale", Vector3(r, 0.2, r), fall)
	rt.tween_callback(ring.queue_free)
	var rock := MeshInstance3D.new()   # the rock: dark, with glowing cracks, trailing fire
	var sm := SphereMesh.new()
	sm.radius = 0.9
	sm.height = 1.6
	rock.mesh = sm
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color("3a2a22")
	rm.emission_enabled = true
	rm.emission = Color("ff5a1a")
	rm.emission_energy_multiplier = 1.6
	rock.material_override = rm
	var trail: Node3D = fireball_node()
	trail.scale = Vector3.ONE * 3.0
	rock.add_child(trail)
	var l := OmniLight3D.new()
	l.light_color = Color("ff7a2a")
	l.light_energy = 4.0
	l.omni_range = 14.0
	rock.add_child(l)
	main.add_child(rock)
	var from := at + Vector3(-14, 42, 10)
	rock.global_position = from
	var ft := rock.create_tween()
	ft.tween_property(rock, "global_position", at, fall).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	ft.parallel().tween_property(rock, "rotation", Vector3(6, 3, 2), fall)
	ft.tween_callback(rock.queue_free)


func _meteor_hit(at: Vector3, r: float, burn: float, burn_r: float) -> void:
	_explosion(at + Vector3(0, 0.5, 0), r)
	_flash_light(at + Vector3(0, 3, 0), Color("ff8a3a"), 10.0, r * 6.0, 0.8)
	var wave := MeshInstance3D.new()   # a shockwave racing out along the ground
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	wave.mesh = tm
	var wm := _glow_mat(Color("ffd0a0"), 2.0, 0.7)
	wave.material_override = wm
	main.add_child(wave)
	wave.global_position = at + Vector3(0, 0.2, 0)
	wave.scale = Vector3(0.5, 0.6, 0.5)
	var wt := wave.create_tween().set_parallel(true)
	wt.tween_property(wave, "scale", Vector3(r * 2.4, 0.6, r * 2.4), 0.5).set_ease(Tween.EASE_OUT)
	wt.tween_property(wm, "albedo_color:a", 0.0, 0.55)
	wt.chain().tween_callback(wave.queue_free)
	for i in 14:   # rocks thrown out
		var chunk := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * randf_range(0.15, 0.4)
		chunk.mesh = bm
		var cm := StandardMaterial3D.new()
		cm.albedo_color = Color("4a3a30")
		cm.emission_enabled = true
		cm.emission = Color("ff6a2a")
		cm.emission_energy_multiplier = 0.8
		chunk.material_override = cm
		main.add_child(chunk)
		chunk.global_position = at + Vector3(0, 0.5, 0)
		var dir := Vector3(randf_range(-1, 1), randf_range(0.6, 1.4), randf_range(-1, 1)).normalized()
		var peak := chunk.global_position + dir * randf_range(2, 5)
		var land := Vector3(peak.x + dir.x * 2.0, at.y + 0.1, peak.z + dir.z * 2.0)
		var ct := chunk.create_tween()
		ct.tween_property(chunk, "global_position", peak, 0.35).set_ease(Tween.EASE_OUT)
		ct.parallel().tween_property(chunk, "rotation", Vector3(randf() * 8, randf() * 8, 0), 0.9)
		ct.tween_property(chunk, "global_position", land, 0.45).set_ease(Tween.EASE_IN)
		ct.tween_interval(2.0)
		ct.tween_property(chunk, "scale", Vector3.ZERO, 0.6)
		ct.tween_callback(chunk.queue_free)
	var crater := _disc(at, r * 0.55, Color(0.1, 0.06, 0.04), 0.7)
	_fade_out(crater, crater.material_override, 4.0, burn + 2.0)
	# the ground burns: flames dancing in a ring, an orange light flickering
	var fire := CPUParticles3D.new()
	fire.amount = 70
	fire.lifetime = 0.7
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fire.emission_sphere_radius = burn_r
	fire.direction = Vector3.UP
	fire.spread = 15.0
	fire.initial_velocity_min = 1.5
	fire.initial_velocity_max = 3.5
	fire.gravity = Vector3(0, 1.0, 0)
	var pm := SphereMesh.new()
	pm.radius = 0.16
	pm.height = 0.32
	fire.mesh = pm
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.8, 0.3, 1.0))
	grad.set_color(1, Color(0.6, 0.1, 0.0, 0.0))
	fire.color_ramp = grad
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.vertex_color_use_as_albedo = true
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fire.material_override = fm
	fire.scale = Vector3(1, 0.05, 1)
	main.add_child(fire)
	fire.global_position = at + Vector3(0, 0.1, 0)
	var fl := OmniLight3D.new()
	fl.light_color = Color("ff7a2a")
	fl.light_energy = 2.5
	fl.omni_range = burn_r * 3.0
	main.add_child(fl)
	fl.global_position = at + Vector3(0, 1.0, 0)
	var ftw := fl.create_tween().set_loops(int(burn / 0.2))
	ftw.tween_property(fl, "light_energy", 3.2, 0.1)
	ftw.tween_property(fl, "light_energy", 2.0, 0.1)
	get_tree().create_timer(burn).timeout.connect(func():
		fire.emitting = false
		fl.queue_free()
		get_tree().create_timer(1.0).timeout.connect(fire.queue_free))
	_shake_near(at, 0.35)


func _well(at: Vector3, life: float, r: float) -> void:
	var root := Node3D.new()
	main.add_child(root)
	root.global_position = at
	var core := MeshInstance3D.new()   # a black core with a violet rim
	var sm := SphereMesh.new()
	sm.radius = 0.55
	sm.height = 1.1
	core.mesh = sm
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.03, 0.0, 0.06)
	cm.rim_enabled = true
	cm.rim = 1.0
	cm.emission_enabled = true
	cm.emission = Color("6a2ad0")
	cm.emission_energy_multiplier = 0.6
	core.material_override = cm
	root.add_child(core)
	var rings := []
	for i in 3:   # rings spinning at different tilts
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.9 + i * 0.5
		tm.outer_radius = 1.0 + i * 0.5
		ring.mesh = tm
		ring.material_override = _glow_mat(Color("a060ff"), 2.5, 0.55)
		ring.rotation = Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
		root.add_child(ring)
		rings.append(ring)
	var motes := CPUParticles3D.new()   # motes spiralling in toward the core
	motes.amount = 90
	motes.lifetime = 0.9
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	motes.emission_sphere_radius = r * 0.8
	motes.radial_accel_min = -18.0
	motes.radial_accel_max = -12.0
	motes.tangential_accel_min = 8.0
	motes.tangential_accel_max = 12.0
	motes.gravity = Vector3.ZERO
	var mm := SphereMesh.new()
	mm.radius = 0.05
	mm.height = 0.1
	motes.mesh = mm
	motes.material_override = _glow_mat(Color("c090ff"), 3.0)
	root.add_child(motes)
	var l := OmniLight3D.new()
	l.light_color = Color("8a3cff")
	l.omni_range = r * 1.8
	l.light_energy = 3.0
	root.add_child(l)
	var floor_ring := _disc(Vector3(at.x, at.y - 1.0, at.z), r, Color("3a1060"), 0.25)
	var t0 := Time.get_ticks_msec()
	var spin := func():
		var t := (Time.get_ticks_msec() - t0) / 1000.0
		for i in rings.size():
			(rings[i] as Node3D).rotate_y((3.0 + i * 1.5) * get_process_delta_time())
		core.scale = Vector3.ONE * (1.0 + 0.12 * sin(t * 9.0))
		l.light_energy = 2.5 + 1.2 * sin(t * 7.0)
	var timer := Timer.new()
	timer.wait_time = 1.0 / 60.0
	timer.autostart = true
	timer.timeout.connect(spin)
	root.add_child(timer)
	get_tree().create_timer(life).timeout.connect(func():
		root.queue_free()
		floor_ring.queue_free())


func _well_burst(at: Vector3, r: float) -> void:
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	ball.mesh = sm
	var m := _glow_mat(Color("b070ff"), 4.0, 0.8)
	ball.material_override = m
	main.add_child(ball)
	ball.global_position = at
	ball.scale = Vector3.ONE * 0.1
	var tw := ball.create_tween().set_parallel(true)
	tw.tween_property(ball, "scale", Vector3.ONE * r, 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.4)
	tw.chain().tween_callback(ball.queue_free)
	_flash_light(at, Color("a050ff"), 8.0, r * 4.0, 0.5)
	Fx.burst(main, at, Vector3.UP, Color("d0a0ff"), 40, 8.0, 0.05)
	_shake_near(at, 0.25)

