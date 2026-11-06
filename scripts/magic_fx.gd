## What spells look like (Jacob 2026-11-04), drawn on every client from the server's spell events (Net.magic_fx) and
## from each player's state (shield bubbles, stuns):
##   lightning: a glowing warning ring where it will land, then a bolt from the sky that is never the same twice (a
##              fractal channel with branches that fork again), striking two to four times in quick flickers, arcs
##              crawling out over the ground, a lingering afterglow in the air, a flash that lights the sky, a scorch
##              with burnt cracks, and a thunderclap whose shake falls off with distance;
##   fireball:  a churning orb of flame (FireballView: each one a little different, wobbling, flickering, trailing embers,
##              smoke and sparks), bursting in an explosion that is never the same twice: a random cluster of fireballs
##              rolling up, a white-hot flash, a shock ring, burning debris thrown in arcs, sparks, a smoke column
##              (sometimes a mushroom), drifting embers, a flickering light and a ragged scorch with burn streaks;
##   casting:   a rune circle in the spell's colour turns under the caster as the spell builds, and flares as it goes off;
##   shield:    a see-through force field pouring out of the staff's orb (see BUBBLE_SHADER); wherever something strikes
##              it, a spot flares and a ring of shimmering light runs out across the dome from that point, sized by the hit;
##   stun:      a violet bolt from the wand that bursts in a crackling violet ring where it lands; everyone caught
##              gets a ring of spinning stars over their head;
##   teleport:  where you left, a column of violet light collapses inward with motes sucked into it; where you arrive,
##              a column bursts out with a shock ring; a fading streak joins them;
##   golems:    an amber rune circle and cracks splitting the ground as one rises in dust; a dust ring, cracks and a
##              thud when one slams;
##   stun:      (also) little violet arcs keep crackling round anyone stunned;
##   frost nova: a ring of ice racing out from the caster, ice shards bursting up along it, a cold flash, frost on the
##              ground, and a frosty ring at the feet of everyone it slowed;
##   spark beam: (v0.12.0) an instant thin white-blue zap from the wand along the aim, sparks where it ends;
##   life drain: (v0.12.0) a crimson stream pulled out of the victim, motes flowing back into the caster's wand, a
##              green "+N" over the caster for what came back;
##   fog:       (v0.12.0) drawn by FogView (the cloud, the outlines, the blindness), from the "fog" event;
##   meteor:    a red target ring, a burning rock streaking down from the sky trailing fire and smoke, then a huge
##              blast, flying rocks, a shockwave ring, a crater, and flames on the ground for 3 s;
##   gravity well: a dark violet vortex: a black core, spinning rings, motes spiralling in, a violet light pulsing;
##              then it collapses and bursts outward;
##   arcane storm: a dark churning cloud gathers high over the area, lit from inside by flickering violet-blue
##              flashes, and bolts rain down from it (each with its warning ring);
##   stone titan: it heaves up out of the ground in a great cloud of dust; its slams shake the ground;
##   level up:  a column of golden light round the player and the new spell's name;
##   shatter:   a shield that runs out of mana bursts into glowing shards;
##   mastery:   (v0.12.7) every spell looks bigger and brighter at mastery II and III, with new accents (shock rings,
##              a golden shield, ice spikes and blocks, fire bomblets, forks, arrival blasts, a charm swirl), and a
##              mastery level-up gets the golden column and "FIREBALL MASTERY II!".
## Every caster glows while casting (and while holding the shield up): a light in the spell's colour at the staff or
## wand, growing as the spell builds, with sparks drawn in toward it.
class_name MagicFx
extends Node3D

## The shield (v0.8.1): a see-through force field. It bends what's behind it a little (sampling the screen behind it,
## offset by the surface's slope), glows at the rim (fresnel), shimmers with drifting bands and a faint honeycomb, and
## energy pours out across it from the staff's orb (`emit`: the orb's direction from the centre), where it is
## brightest. Each hit sends a ring of light out across the dome from the exact point it struck, as big as the hit.
const BUBBLE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.45, 0.8, 1.0, 1.0);
uniform vec3 hits[6];
uniform float hit_t[6];
uniform float hit_s[6];
uniform float fade = 1.0;
uniform vec3 emit = vec3(0.0, 1.0, 0.0);
varying vec3 lpos;
void vertex() { lpos = normalize(VERTEX); }
void fragment() {
	float fres = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 3.0);
	float sh = (0.5 + 0.5 * sin(lpos.y * 18.0 + TIME * 2.4)) * (0.5 + 0.5 * sin((lpos.x - lpos.z) * 14.0 - TIME * 1.7));
	vec2 hv = vec2(atan(lpos.z, lpos.x) * 7.0, lpos.y * 10.0 + TIME * 0.15);
	vec2 hf = abs(fract(hv + vec2(0.5 * floor(hv.y), 0.0)) - 0.5);
	float hex = smoothstep(0.42, 0.5, max(hf.x, hf.y));
	float ea = acos(clamp(dot(lpos, normalize(emit)), -1.0, 1.0));
	float flow = pow(0.5 + 0.5 * sin(ea * 11.0 - TIME * 7.0), 6.0) * exp(-ea * 0.8);
	float src = exp(-pow(ea / 0.22, 2.0));
	float glow = 0.0;
	for (int i = 0; i < 6; i++) {
		float t = hit_t[i];
		if (t < 1.1) {
			float s = hit_s[i];
			float ang = acos(clamp(dot(lpos, hits[i]), -1.0, 1.0));
			float ring = exp(-pow((ang - t * 2.9) / (0.1 + 0.07 * s), 2.0)) * (1.0 - t / 1.1) * s;
			float spot = exp(-pow(ang / (0.18 + 0.12 * s), 2.0)) * max(0.0, 1.0 - t * 2.5) * s;
			float shimmer = (0.5 + 0.5 * sin(ang * 40.0 - t * 30.0)) * exp(-pow((ang - t * 2.9) / 0.35, 2.0)) * (1.0 - t / 1.1) * 0.5 * s;
			glow += ring * 1.2 + spot * 1.8 + shimmer;
		}
	}
	float edge = fres * 0.9 + sh * 0.05 + hex * 0.1 * (0.35 + fres) + flow * 0.3 + src * 1.3 + glow;
	vec2 off = NORMAL.xy * (0.01 + 0.025 * fres);
	vec3 bg = texture(screen_tex, SCREEN_UV + off).rgb;
	ALBEDO = mix(bg, tint.rgb, 0.07) + tint.rgb * edge * 1.5;
	ALPHA = clamp(fade, 0.0, 1.0);
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
var runes := {}              # player id -> the rune circle turning under them while they cast
const SPELL_COLOR := { "Lightning": Color("cfe6ff"), "Fireball": Color("ff8a2a"), "Shield": Color("7fd0ff"),
	"Frost Nova": Color("9fe8ff"), "Golem": Color("ffb02e"), "Teleport": Color("c070ff"), "Stun": Color("c070ff"),
	"Spark Beam": Color("bfe8ff"), "Life Drain": Color("d0203a"),
	"Fog": Color("b8c4cc"), "Heal Aura": Color("7dffa0"), "Meteor": Color("ff5a1a"), "Gravity Well": Color("8a3cff"),
	"Arcane Storm": Color("9fc4ff"), "Stone Titan": Color("ff5a1a") }
var _door_target := 0.0


func setup(n: Net, m: Node3D) -> void:
	net = n
	main = m
	_shader = Shader.new()
	_shader.code = BUBBLE_SHADER
	net.magic_fx.connect(_on_fx)


# ================================================================ events from the server
## v0.12.7 spell mastery: most events carry the caster's mastery level (1-3) as an extra last argument; older events
## without it are level 1.
static func _lv(a: Array, i: int) -> int:
	return clampi(int(a[i]), 1, 3) if a.size() > i else 1


func _on_fx(kind: String, a: Array) -> void:
	match kind:
		"lightning_warn":
			_warn_ring(a[0], float(a[1]) * Config.DT, _lv(a, 3))
		"lightning":
			_bolt(a[0], _lv(a, 1))
		"chain":
			_chain(a[0], a[1], float(a[2]) / maxf(float(a[3]), 1.0), _lv(a, 4))
		"fork":   # v0.12.7 Lightning mastery III: the strike forks sideways to one more enemy
			_chain(a[0] + Vector3(0, 0.3, 0), a[1] + Vector3(0, 1.1, 0), 1.0, 3)
			_flash_light(a[1] + Vector3(0, 1.0, 0), Color("dceeff"), 5.0, 8.0, 0.2)
		"explode":
			_explosion(a[0], float(a[1]), _lv(a, 2))
		"bomblet":   # v0.12.7 Fireball mastery III: a little fire bomb lobbed out of the blast (it pops as "explode")
			_bomblet(a[0], a[1], float(a[2]) * Config.DT)
		"cast":
			if avatars.has(a[0]):
				var av: Node3D = avatars[a[0]]
				var lv := _lv(a, 2)
				Fx.burst(main, av.position + Vector3(0, 1.5, 0), Vector3.UP, Color("ffb347") if lv < 3 else Color("fff0c0"), 10 * lv, 2.5, 0.05)
		"shield_up":
			if avatars.has(a[0]):
				var av: Node3D = avatars[a[0]]
				Fx.burst(main, av.position + Vector3(0, 1.0, 0), Vector3.UP, Color("8fd8ff") if _lv(a, 1) < 3 else Color("ffe08a"), 22, 3.0, 0.05)
		"reflect":   # v0.12.7 Shield mastery III: a shot sent back: a golden flare where it turned
			Fx.burst(main, a[1], Vector3.UP, Color("ffe08a"), 26, 5.0, 0.04)
			_flash_light(a[1], Color("ffd060"), 4.0, 5.0, 0.25)
			Fx.word(main, (a[1] as Vector3) + Vector3(0, 0.6, 0), "REFLECTED!", Color("ffe08a"))
		"tp_blast":   # v0.12.7 Teleport mastery II / III: the arrival burst
			_tp_blast(a[0], float(a[1]), _lv(a, 2))
		"freeze":   # v0.12.7 Frost Nova mastery III: frozen solid
			_freeze(int(a[0]), a[1], float(a[2]) * Config.DT)
		"poison":   # v0.12.7 Fog mastery II / III: a puff of green bubbles off whoever the fog poisons
			_poison_puff(int(a[0]))
		"charm":   # v0.12.7 Stun mastery III (the swirl over its head is drawn every frame from the roster)
			if avatars.has(a[0]):
				Fx.burst(main, (avatars[a[0]] as Node3D).position + Vector3(0, 2.2, 0), Vector3.UP, Color("f080e0"), 30, 3.0, 0.05)
				Fx.word(main, (avatars[a[0]] as Node3D).position + Vector3(0, 2.8, 0), "CHARMED!", Color("f8a0ff"))
		"uncharm":
			if avatars.has(a[0]):
				Fx.burst(main, (avatars[a[0]] as Node3D).position + Vector3(0, 2.2, 0), Vector3.UP, Color("b070ff"), 14, 2.0, 0.05)
		"mastery_up":
			_mastery_up(int(a[0]), int(a[1]), int(a[2]), int(a[3]))
		"shield_hit":
			_shield_hit(int(a[0]), a[1], float(a[2]) if a.size() > 2 else 8.0)
		"block":
			_block(int(a[0]), a[1], int(a[2]), int(a[3]))
		"gather":   # v0.12.7 stones dug out / arrows whittled: chips or shavings, and "+3 stones" over them
			var at: Vector3 = a[1]
			var stones := int(a[2]) == 0
			Fx.burst(main, at + Vector3(0, 0.4, 0), Vector3.UP, Color("9a9aa2") if stones else Color("c8955a"), 10, 2.5, 0.04)
			Fx.word(main, at + Vector3(0, 2.0, 0), "+%d %s" % [int(a[3]), "stones" if stones else "arrows"], Color("fff2a8"))
		"stun_beam":
			_stun_beam(a[1], a[2], int(a[3]) != 0, _lv(a, 4))
		"teleport":
			var tlv := _lv(a, 3)
			_blink(a[1], false, tlv)
			_blink(a[2], true, tlv)
			_streak(a[1] + Vector3(0, 1.0, 0), a[2] + Vector3(0, 1.0, 0), Color("c58cff") if tlv < 3 else Color("e8b8ff"), 0.35 + 0.15 * (tlv - 1))
		"golem_rise":
			var glv := _lv(a, 2)
			var gk: float = [1.0, 1.3, 1.6][glv - 1]
			_golem_dust(a[1], 0.9 * gk)
			_summon_circle(a[1], 1.3 * gk, Color("ffb02e") if glv < 3 else Color("ffd060"), Golems.RISE * Config.DT)
			_cracks(a[1], 1.6 * gk, 6 + 2 * glv)
		"golem_slam":
			var big: bool = a.size() > 2 and a[2]
			var gsz := float(a[3]) if a.size() > 3 else 1.0
			var aoe: bool = a.size() > 4 and a[4]   # v0.12.7 mastery III: a ground-slam / stomp shockwave
			_golem_dust(a[1], (2.8 if big else 0.9) * gsz)
			_shake_near_scaled(a[1], (0.4 if big else 0.14) * (1.0 + 0.5 * (gsz - 1.0)) + (0.12 if aoe else 0.0))
			_cracks(a[1], (3.0 if big else 1.0) * gsz, 7 if big else 4)
			if big:
				_flash_light(a[1] + Vector3(0, 0.5, 0), Color("ffb060"), 3.0, 6.0, 0.3)
			if aoe:
				_shock_ring(a[1], 6.0 if big else 2.2, Color("ffc070"), 0.45)
		"vault_door":
			_door_target = -1.7 if a[0] else 0.0
		"frost_nova":
			_frost_nova(a[1], float(a[2]), _lv(a, 3))
		"stun_burst":
			_stun_burst(a[0], float(a[1]), _lv(a, 2))
		"meteor_warn":
			_meteor_fall(a[0], float(a[1]) * Config.DT, float(a[2]), _lv(a, 3))
		"meteor":
			_meteor_hit(a[0], float(a[1]), float(a[2]) * Config.DT, float(a[3]), _lv(a, 4))
		"well":
			_well(a[0], float(a[1]) * Config.DT, float(a[2]), _lv(a, 3))
		"well_burst":
			_well_burst(a[0], float(a[1]), _lv(a, 2))
		"storm":
			_storm(a[0], float(a[1]) * Config.DT, float(a[2]), _lv(a, 3))
		"titan_rise":
			var tk := 1.0 + 0.2 * (_lv(a, 2) - 1)
			_golem_dust(a[1], 2.6 * tk)
			_summon_circle(a[1], 3.2 * tk, Color("ff5a1a") if _lv(a, 2) < 3 else Color("ffa030"), Golems.RISE * Config.DT)
			_cracks(a[1], 4.0 * tk, 10)
			_flash_light(a[1] + Vector3(0, 1, 0), Color("ff5a1a"), 6.0, 10.0, 0.8)
			_shake_near(a[1], 0.3)
		"npc_tell":   # v0.12.0: a challenger wizard winding a spell up: a growing glow and motes at its hand
			_npc_tell(int(a[0]), str(a[1]), float(a[2]) * Config.DT)
		"spark":
			_spark(a[1], a[2], bool(a[3]), _lv(a, 4), a[5] if a.size() > 5 else [], a[6] if a.size() > 6 else [])
		"drain":
			_drain(int(a[0]), a[1], a[2], int(a[3]), _lv(a, 4))
		"heal_pulse":   # v0.12.0 the staff's Heal Aura: a ring, rising motes, "+N" over everyone healed, a chime
			_heal_pulse(int(a[0]), a[1], float(a[2]), a[3], _lv(a, 4))
		"heal_stop":
			if avatars.has(a[0]):
				Fx.burst(main, (avatars[a[0]] as Node3D).position + Vector3(0, 2.0, 0), Vector3.UP, Color("b8ffb0"), 10, 1.5, 0.04)
		"drain_ally":   # v0.12.0: Life Drain on an ally: a green-gold stream from the caster into them, "+N" on them
			_drain_ally(a[1], a[2], int(a[3]), int(a[4]))
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
			# v0.12.7 Shield mastery: II a brighter cyan, III a golden sheen (it turns shots back)
			var slv := Weapons.mastery_named(st.mastery, Weapons.STAFF, "Shield")
			if slv >= 2:
				(bubbles[id].mat as ShaderMaterial).set_shader_parameter("tint", Color(0.5, 0.95, 1.0) if slv == 2 else Color(1.0, 0.82, 0.4))
				if slv == 3:
					(bubbles[id].light as OmniLight3D).light_color = Color("ffd070")
					(bubbles[id].glow as MeshInstance3D).material_override = _glow_mat(Color("fff0b0"), 8.0, 0.75)
		if bubbles.has(id):
			var b: Dictionary = bubbles[id]
			if not on:
				if not b.get("shattered", false):
					Fx.burst(main, (b.node as Node3D).global_position, Vector3.UP, Color("8fd8ff"), 18, 3.5, 0.05)
				(b.node as Node3D).queue_free()
				for n in b.get("extra", []):
					(n as Node).queue_free()
				bubbles.erase(id)
			else:
				var bc := (avatars[id] as Node3D).position + Vector3(0, Weapons.SHIELD_CENTER_Y, 0)
				(b.node as Node3D).global_position = bc
				_orb_emit(b, avatars[id], bc, delta)
				var low := float(st.mana) / float(Sim.MANA_FULL)
				var flicker := 1.0 if low > 0.25 else (0.5 + 0.5 * absf(sin(Time.get_ticks_msec() * 0.02)))
				var mat: ShaderMaterial = b.mat
				mat.set_shader_parameter("fade", flicker)
				var dirs := PackedVector3Array()
				var ts := PackedFloat32Array()
				var ss := PackedFloat32Array()
				for h in b.hits:
					h[1] += delta
				b.hits = b.hits.filter(func(h): return h[1] < 1.1)
				for i in 6:
					if i < b.hits.size():
						dirs.append(b.hits[i][0])
						ts.append(b.hits[i][1])
						ss.append(float(b.hits[i][2]) if (b.hits[i] as Array).size() > 2 else 1.0)
					else:
						dirs.append(Vector3.UP)
						ts.append(9.0)
						ss.append(0.0)
				mat.set_shader_parameter("hits", dirs)
				mat.set_shader_parameter("hit_t", ts)
				mat.set_shader_parameter("hit_s", ss)
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
				if randf() < delta * 7.0:   # little violet arcs crackling round the body
					var c0 := (avatars[id] as Node3D).position + Vector3(randf_range(-0.4, 0.4), randf_range(0.3, 1.9), randf_range(-0.4, 0.4))
					var arc := _ribbons([[_fractal(c0, c0 + Vector3(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), randf_range(-0.4, 0.4)), 2, 0.35), 0.03]], Color("d8a8ff"), 6.0)
					var atw := arc.create_tween()
					atw.tween_property(arc.material_override, "albedo_color:a", 0.0, 0.12)
					atw.tween_callback(arc.queue_free)
	_cast_glow(delta, states)
	_charm_swirls(delta)   # v0.12.7
	for id in bubbles.keys():
		if not states.has(id):
			for n in bubbles[id].get("extra", []):
				(n as Node).queue_free()
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


func _warn_ring(at: Vector3, life: float, lv := 1) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	# v0.12.10: the ring marks the strike's real area, which grows with mastery (3 / 3.75 / 4.5 m)
	var r := float(Weapons.spell_named_lv(Weapons.STAFF, "Lightning", lv).get("radius", 3.0))
	tm.inner_radius = r - (0.25 if lv < 3 else 0.4)   # v0.12.7 mastery: a bolder ring, white-gold at III
	tm.outer_radius = r
	ring.mesh = tm
	var m := _glow_mat([Color("bfe4ff"), Color("d8ecff"), Color("fff2c8")][lv - 1], 2.5 + lv * 0.5, 0.8)
	ring.material_override = m
	ring.scale = Vector3(1, 0.05, 1)
	main.add_child(ring)
	ring.global_position = at + Vector3(0, 0.05, 0)
	var inner := _disc(at, r, Color("9fd0ff"), 0.12)
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


## A crooked path from a to b by midpoint displacement: each level halves every segment and pushes its middle sideways
## by up to `rough` of the segment's length. Different every call.
static func _fractal(a: Vector3, b: Vector3, levels: int, rough: float) -> Array:
	var pts := [a, b]
	for lv in levels:
		var out := [pts[0]]
		for i in pts.size() - 1:
			var p: Vector3 = pts[i]
			var q: Vector3 = pts[i + 1]
			var d := q - p
			var side := d.cross(Vector3.UP)
			if side.length() < 1e-4:
				side = d.cross(Vector3.RIGHT)
			side = side.normalized()
			var side2 := d.cross(side).normalized()
			var len := d.length()
			out.append((p + q) * 0.5 + side * randf_range(-rough, rough) * len + side2 * randf_range(-rough, rough) * len)
			out.append(q)
		pts = out
	return pts


## Glowing ribbons along paths, as one mesh: two crossed quads per segment, so they read from any side. paths: [[points,
## width], ...]. Additive and unshaded.
func _ribbons(paths: Array, c: Color, energy := 6.0) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for pw in paths:
		var pts: Array = pw[0]
		var w := float(pw[1])
		for i in pts.size() - 1:
			var p: Vector3 = pts[i]
			var q: Vector3 = pts[i + 1]
			var d := (q - p)
			if d.length() < 1e-4:
				continue
			var s1 := d.cross(Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT).normalized() * w * 0.5
			var s2 := d.cross(s1).normalized() * w * 0.5
			var taper := 1.0 - 0.5 * float(i) / float(pts.size())   # thinner toward the end
			for sv in [s1 * taper, s2 * taper]:
				st.add_vertex(p - sv)
				st.add_vertex(p + sv)
				st.add_vertex(q + sv)
				st.add_vertex(p - sv)
				st.add_vertex(q + sv)
				st.add_vertex(q - sv)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := _glow_mat(c, energy, 1.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(mi)
	return mi


## One lightning channel with its branches (and branches off those): [[points, width], ...].
func _bolt_paths(top: Vector3, at: Vector3) -> Array:
	var trunk := _fractal(top, at, 5, 0.18)
	var paths := [[trunk, 0.13]]
	for k in randi_range(3, 6):
		var from: Vector3 = trunk[randi_range(3, trunk.size() - 6)]
		var drop := randf_range(3.0, 9.0)
		var to := from + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(2.0, 6.0) + Vector3(0, -drop, 0)
		to.y = maxf(to.y, at.y + 0.5)
		var br := _fractal(from, to, 3, 0.25)
		paths.append([br, 0.06])
		if randf() < 0.4:   # a fork off the fork
			var f2: Vector3 = br[randi_range(2, br.size() - 2)]
			paths.append([_fractal(f2, f2 + Vector3(randf_range(-2, 2), randf_range(-3, -1), randf_range(-2, 2)), 2, 0.3), 0.035])
	return paths


## v0.12.7 lv: the caster's Lightning mastery: II a thicker, brighter channel with an extra stroke and more ground arcs;
## III a fat blue-white channel, a white-hot core, a second ground-arc burst and a ring of light on the ground.
func _bolt(at: Vector3, lv := 1) -> void:
	var top := at + Vector3(randf_range(-6, 6), randf_range(30, 38), randf_range(-6, 6))
	var strokes := randi_range(2, 4) + (lv - 1)   # it strikes, goes dark, and strikes again down nearly the same channel
	var t := 0.0
	var base_paths := _bolt_paths(top, at)
	var wk: float = [1.0, 1.45, 2.0][lv - 1]
	for k in strokes:
		var paths := base_paths if k == 0 else _jitter_paths(base_paths, 0.12)
		var glow := _ribbons(paths.map(func(pw): return [pw[0], float(pw[1]) * 4.0 * wk]), Color("6f9cff") if lv < 3 else Color("8fc8ff"), 2.5 + lv * 0.5)
		var core := _ribbons(paths.map(func(pw): return [pw[0], float(pw[1]) * (1.0 + (wk - 1.0) * 0.6)]), Color("f4f8ff") if lv < 3 else Color("ffffff"), 9.0 + lv * 2.0)
		(glow.material_override as StandardMaterial3D).albedo_color.a = 0.0
		(core.material_override as StandardMaterial3D).albedo_color.a = 0.0
		var on := randf_range(0.05, 0.08)
		for mi: MeshInstance3D in [glow, core]:
			var m: StandardMaterial3D = mi.material_override
			var tw := mi.create_tween()
			tw.tween_interval(t)
			tw.tween_property(m, "albedo_color:a", 1.0 if mi == core else 0.55, 0.01)
			tw.tween_interval(on)
			tw.tween_property(m, "albedo_color:a", 0.0, 0.05 if k < strokes - 1 else 0.25)
			tw.tween_callback(mi.queue_free)
		get_tree().create_timer(t).timeout.connect(func():
			_flash_light(at + Vector3(0, 3, 0), Color("dceeff"), 9.0 if k == 0 else 6.0, 18.0, 0.18)
			_flash_light(at + Vector3(0, 22, 0), Color("b8ccff"), 2.0, 70.0, 0.15)   # the sky lights up
			if k == 0:
				_ground_arcs(at)
				if lv >= 2:
					_ground_arcs(at)
				if lv >= 3:
					_shock_ring(at, 3.4, Color("cfe8ff"), 0.35)
				_shake_near_scaled(at, 0.32 + 0.06 * (lv - 1)))
		t += on + randf_range(0.04, 0.09)
	# the afterglow: the channel hangs in the air a moment, fading through violet
	var after := _ribbons(base_paths.slice(0, 1).map(func(pw): return [pw[0], 0.35]), Color("9a7cff"), 1.5)
	(after.material_override as StandardMaterial3D).albedo_color.a = 0.0
	var atw := after.create_tween()
	atw.tween_interval(t)
	atw.tween_property(after.material_override, "albedo_color:a", 0.35, 0.02)
	atw.tween_property(after.material_override, "albedo_color:a", 0.0, 0.7)
	atw.tween_callback(after.queue_free)
	Fx.burst(main, at + Vector3(0, 0.2, 0), Vector3.UP, Color("e8f6ff"), randi_range(24, 40), randf_range(6.0, 9.0), 0.05)
	Fx.burst(main, at + Vector3(0, 0.1, 0), Vector3.UP, Color("6b6b70"), 14, 2.0, 0.09)
	_smoke(at, randi_range(2, 4), 0.6, 2.5, 0.35)
	_scorch_ragged(at, randf_range(1.4, 2.2), randi_range(5, 9))


func _jitter_paths(paths: Array, amt: float) -> Array:
	var out := []
	for pw in paths:
		var pts: Array = (pw[0] as Array).duplicate()
		for i in range(1, pts.size() - 1):
			pts[i] = (pts[i] as Vector3) + Vector3(randf_range(-amt, amt), randf_range(-amt, amt), randf_range(-amt, amt)) * 3.0
		out.append([pts, pw[1]])
	return out


## Electric arcs crawling out over the ground from where lightning struck.
func _ground_arcs(at: Vector3) -> void:
	var paths := []
	for i in randi_range(4, 7):
		var a := randf() * TAU
		var l := randf_range(1.2, 3.2)
		var to := at + Vector3(cos(a) * l, 0.05, sin(a) * l)
		paths.append([_fractal(at + Vector3(0, 0.08, 0), to, 3, 0.3).map(func(p): return Vector3(p.x, at.y + 0.06 + randf() * 0.12, p.z)), 0.045])
	var arcs := _ribbons(paths, Color("cfe4ff"), 7.0)
	var tw := arcs.create_tween()
	for k in 3:   # crackle on and off
		tw.tween_property(arcs.material_override, "albedo_color:a", 0.2, 0.04)
		tw.tween_property(arcs.material_override, "albedo_color:a", 1.0, 0.03)
	tw.tween_property(arcs.material_override, "albedo_color:a", 0.0, 0.2)
	tw.tween_callback(arcs.queue_free)


## A shake for our camera that falls off with distance (a thunderclap: hard close by, a rumble far off, up to 45 m),
## arriving a moment later the farther it is.
func _shake_near_scaled(at: Vector3, amount: float) -> void:
	if not avatars.has(net.my_id):
		return
	var d := (avatars[net.my_id] as Node3D).position.distance_to(at)
	if d > 45.0:
		return
	var k := amount * clampf(1.0 - d / 45.0, 0.0, 1.0) * (1.0 if d < 8.0 else 0.7)
	get_tree().create_timer(d / 160.0).timeout.connect(func():
		main.set("shake", maxf(float(main.get("shake")), k)))


## Smoke puffs rising: n of them, spread `spread` m, rising `rise` m, `alpha` thick.
func _smoke(at: Vector3, n: int, spread: float, rise: float, alpha: float, delay := 0.0) -> void:
	for i in n:
		var puff := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = randf_range(0.35, 0.7)
		sm.height = sm.radius * 2.0
		sm.radial_segments = 10
		sm.rings = 5
		puff.mesh = sm
		var m := StandardMaterial3D.new()
		var g := randf_range(0.16, 0.32)
		m.albedo_color = Color(g, g * 0.95, g * 0.92, 0.0)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		puff.material_override = m
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		main.add_child(puff)
		puff.global_position = at + Vector3(randf_range(-spread, spread), randf_range(0.2, 0.9), randf_range(-spread, spread))
		var wind := Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8))
		var life := randf_range(1.2, 2.2)
		var tw := puff.create_tween().set_parallel(true)
		var d := delay + randf_range(0.0, 0.25)
		tw.tween_property(m, "albedo_color:a", alpha * randf_range(0.7, 1.0), 0.15).set_delay(d)
		tw.tween_property(puff, "global_position", puff.global_position + wind + Vector3(0, rise * randf_range(0.7, 1.3), 0), life).set_delay(d).set_ease(Tween.EASE_OUT)
		tw.tween_property(puff, "scale", Vector3.ONE * randf_range(1.8, 2.8), life).set_delay(d)
		tw.tween_property(m, "albedo_color:a", 0.0, life * 0.7).set_delay(d + life * 0.3)
		tw.chain().tween_callback(puff.queue_free)


## A burn mark that isn't a perfect circle: a few overlapping dark patches and streaks splashed outward.
func _scorch_ragged(at: Vector3, r: float, streaks: int) -> void:
	var g := Vector3(at.x, WorldLayout.ground_height(at.x, at.z, at.y + 0.3), at.z)
	var parts := []
	for i in randi_range(2, 4):
		var off := Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3)) * r
		var d := _disc(g + off + Vector3(0, 0.002 * i, 0), r * randf_range(0.45, 0.75), Color(0.07, 0.05, 0.04), 0.4)
		d.scale = Vector3(randf_range(0.8, 1.25), 1, randf_range(0.8, 1.25))
		d.rotation.y = randf() * TAU
		parts.append(d)
	for i in streaks:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var l := randf_range(0.5, 1.2) * r
		bm.size = Vector3(randf_range(0.06, 0.16), 0.01, l)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.06, 0.04, 0.03, 0.45)
		mi.material_override = m
		main.add_child(mi)
		var a := randf() * TAU
		mi.global_position = g + Vector3(cos(a), 0, sin(a)) * (r * 0.4 + l * 0.5) + Vector3(0, 0.025, 0)
		mi.rotation.y = -a + PI * 0.5
		parts.append(mi)
	for n in parts:
		_fade_out(n, (n as MeshInstance3D).material_override, 5.0, 5.0)


## v0.12.7 lv: the caster's Fireball mastery (0: a bomblet's pop): II a second roll of flame and thicker smoke; III a
## white-hot flash that swells bigger, a golden shock ring and a ring of fire left on the ground.
func _explosion(at: Vector3, r: float, lv := 1) -> void:
	if lv >= 2:
		_smoke(at, 3 + lv, r * 0.35, 3.0, 0.55, 0.2)
		_shock_ring(at, r * 1.2, Color("ffb050") if lv == 2 else Color("fff0a0"), 0.4)
	if lv >= 3:
		var hot := MeshInstance3D.new()   # the white-hot heart, bigger and longer
		var hs := SphereMesh.new()
		hs.radius = 1.0
		hs.height = 2.0
		hot.mesh = hs
		var hm := _glow_mat(Color("ffffff"), 14.0, 1.0)
		hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hot.material_override = hm
		main.add_child(hot)
		hot.global_position = at
		hot.scale = Vector3.ONE * r * 0.2
		var htw := hot.create_tween().set_parallel(true)
		htw.tween_property(hot, "scale", Vector3.ONE * r * 0.55, 0.16)
		htw.tween_property(hm, "albedo_color:a", 0.0, 0.24)
		htw.chain().tween_callback(hot.queue_free)
		var ring := _disc(Vector3(at.x, WorldLayout.ground_height(at.x, at.z, at.y + 0.5), at.z), r * 0.75, Color("ff7a20"), 0.35)
		_fade_out(ring, ring.material_override, 1.2, 0.6)
		Fx.burst(main, at, Vector3.UP, Color("ffffff"), 18, 12.0, 0.03)
	# a cluster of fireballs rolling up and out, each its own size, colour and timing
	var palette := [Color("ff8a2a"), Color("ffb347"), Color("ff5a1a"), Color("ffe066"), Color("ff7a30")]
	for i in randi_range(4, 7):
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 14
		sm.rings = 7
		ball.mesh = sm
		var m := _glow_mat(palette[randi() % palette.size()], randf_range(3.0, 5.0), 0.85)
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		ball.material_override = m
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		main.add_child(ball)
		var off := Vector3(randf_range(-1, 1), randf_range(-0.2, 0.8), randf_range(-1, 1)) * r * 0.32
		ball.global_position = at + off
		ball.scale = Vector3.ONE * 0.15
		var size := r * randf_range(0.35, 0.7)
		var life := randf_range(0.28, 0.5)
		var d := randf_range(0.0, 0.09)
		var tw := ball.create_tween().set_parallel(true)
		tw.tween_property(ball, "scale", Vector3(size, size * randf_range(0.8, 1.2), size), life).set_delay(d).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(ball, "global_position", ball.global_position + off * 0.6 + Vector3(0, randf_range(0.3, 1.2), 0), life + 0.2).set_delay(d)
		tw.tween_property(m, "albedo_color:a", 0.0, life + 0.15).set_delay(d + 0.08)
		tw.chain().tween_callback(ball.queue_free)
	# the white-hot heart
	var core := MeshInstance3D.new()
	var cs := SphereMesh.new()
	cs.radius = 1.0
	cs.height = 2.0
	core.mesh = cs
	var cm := _glow_mat(Color("fff6d8"), 10.0, 1.0)
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core.material_override = cm
	main.add_child(core)
	core.global_position = at
	core.scale = Vector3.ONE * r * 0.15
	var ctw := core.create_tween().set_parallel(true)
	ctw.tween_property(core, "scale", Vector3.ONE * r * 0.35, 0.1)
	ctw.tween_property(cm, "albedo_color:a", 0.0, 0.14)
	ctw.chain().tween_callback(core.queue_free)
	# the shock ring
	var wave := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.92
	tm.outer_radius = 1.0
	tm.rings = 28
	wave.mesh = tm
	var wm := _glow_mat(Color("ffe3b0"), 2.5, 0.75)
	wave.material_override = wm
	main.add_child(wave)
	wave.global_position = at + Vector3(0, 0.15, 0)
	wave.rotation = Vector3(randf_range(-0.12, 0.12), 0, randf_range(-0.12, 0.12))
	wave.scale = Vector3(0.3, 0.4, 0.3)
	var wtw := wave.create_tween().set_parallel(true)
	wtw.tween_property(wave, "scale", Vector3(r * 1.35, 0.4, r * 1.35), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	wtw.tween_property(wm, "albedo_color:a", 0.0, 0.32)
	wtw.chain().tween_callback(wave.queue_free)
	# burning debris thrown out in arcs
	for i in randi_range(5, 11):
		var chunk := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(randf_range(0.06, 0.2), randf_range(0.06, 0.18), randf_range(0.06, 0.2))
		chunk.mesh = bm
		var km := StandardMaterial3D.new()
		km.albedo_color = Color("3a2a22")
		km.emission_enabled = true
		km.emission = Color("ff6a2a")
		km.emission_energy_multiplier = randf_range(0.8, 2.5)
		chunk.material_override = km
		main.add_child(chunk)
		chunk.global_position = at + Vector3(0, 0.3, 0)
		var dir := Vector3(randf_range(-1, 1), randf_range(0.5, 1.5), randf_range(-1, 1)).normalized()
		var peak := chunk.global_position + dir * randf_range(1.5, 1.0 + r)
		var gy := WorldLayout.ground_height(peak.x, peak.z, peak.y)
		var land := Vector3(peak.x + dir.x * randf_range(0.8, 2.0), gy + 0.05, peak.z + dir.z * randf_range(0.8, 2.0))
		var up_t := randf_range(0.22, 0.38)
		var dtw := chunk.create_tween()
		dtw.tween_property(chunk, "global_position", peak, up_t).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		dtw.parallel().tween_property(chunk, "rotation", Vector3(randf() * 9, randf() * 9, randf() * 9), up_t * 2.5)
		dtw.tween_property(chunk, "global_position", land, up_t * 1.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		dtw.tween_property(km, "emission_energy_multiplier", 0.0, 1.2)
		dtw.tween_property(chunk, "scale", Vector3.ZERO, 0.5)
		dtw.tween_callback(chunk.queue_free)
		if randf() < 0.5:   # some trail a thread of smoke
			var trail := CPUParticles3D.new()
			trail.amount = 12
			trail.lifetime = 0.5
			trail.local_coords = false
			trail.gravity = Vector3(0, 1.0, 0)
			trail.initial_velocity_max = 0.2
			var pm := SphereMesh.new()
			pm.radius = 0.05
			pm.height = 0.1
			trail.mesh = pm
			var grad := Gradient.new()
			grad.set_color(0, Color(1.0, 0.6, 0.2, 0.9))
			grad.set_color(1, Color(0.25, 0.22, 0.2, 0.0))
			trail.color_ramp = grad
			var tmat := StandardMaterial3D.new()
			tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			tmat.vertex_color_use_as_albedo = true
			tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			trail.material_override = tmat
			chunk.add_child(trail)
	Fx.burst(main, at, Vector3.UP, Color("ffcf5a"), randi_range(24, 44), randf_range(7.0, 10.0), 0.05)
	Fx.burst(main, at, Vector3.UP, Color("fff2b0"), randi_range(8, 16), randf_range(10.0, 14.0), 0.03)
	# smoke: a column rising (sometimes a mushroom cap on top), and drifting embers
	_smoke(at, randi_range(5, 9), r * 0.3, randf_range(2.0, 4.0), 0.6, 0.12)
	if randf() < 0.35:
		_smoke(at + Vector3(0, 2.2, 0), randi_range(3, 5), r * 0.35, 1.2, 0.5, 0.35)
	var embers := CPUParticles3D.new()
	embers.one_shot = true
	embers.explosiveness = 0.8
	embers.amount = randi_range(18, 34)
	embers.lifetime = randf_range(1.4, 2.2)
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = r * 0.4
	embers.direction = Vector3.UP
	embers.spread = 60.0
	embers.initial_velocity_min = 0.8
	embers.initial_velocity_max = 3.0
	embers.gravity = Vector3(randf_range(-0.4, 0.4), 0.7, randf_range(-0.4, 0.4))
	var em := SphereMesh.new()
	em.radius = 0.03
	em.height = 0.06
	embers.mesh = em
	var eg := Gradient.new()
	eg.set_color(0, Color(1.0, 0.8, 0.3, 1.0))
	eg.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
	embers.color_ramp = eg
	var emat := StandardMaterial3D.new()
	emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	emat.vertex_color_use_as_albedo = true
	emat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	emat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	embers.material_override = emat
	main.add_child(embers)
	embers.global_position = at + Vector3(0, 0.5, 0)
	embers.emitting = true
	embers.finished.connect(embers.queue_free)
	# the light: a big flash, then flickering down
	var l := OmniLight3D.new()
	l.light_color = Color("ffa040")
	l.light_energy = randf_range(7.0, 9.0)
	l.omni_range = r * 4.0
	l.shadow_enabled = l.light_energy >= 8.0
	main.add_child(l)
	l.global_position = at + Vector3(0, 1, 0)
	var ltw := l.create_tween()
	for k in randi_range(3, 5):
		ltw.tween_property(l, "light_energy", randf_range(2.0, 5.0) * (1.0 - k * 0.15), randf_range(0.04, 0.09))
	ltw.tween_property(l, "light_energy", 0.0, 0.3)
	ltw.tween_callback(l.queue_free)
	_scorch_ragged(at, r * 0.6, randi_range(5, 9))
	_shake_near_scaled(at, 0.22)


## The fireball in flight (FireballView). Main moves it along its path.
static func fireball_node() -> Node3D:
	return FireballView.new()


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
	# the orb it pours out of: a hot glow, a light, and sparks streaming out over the dome
	var glow := MeshInstance3D.new()
	var gs := SphereMesh.new()
	gs.radius = 0.16
	gs.height = 0.32
	glow.mesh = gs
	var gm := _glow_mat(Color("bfeaff"), 8.0, 0.75)
	gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.material_override = gm
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(glow)
	var light := OmniLight3D.new()
	light.light_color = Color("8fd8ff")
	light.light_energy = 2.5
	light.omni_range = 4.0
	main.add_child(light)
	var sparks := CPUParticles3D.new()
	sparks.amount = 40
	sparks.lifetime = 0.9
	sparks.local_coords = false
	sparks.direction = Vector3.UP
	sparks.spread = 75.0
	sparks.initial_velocity_min = 1.0
	sparks.initial_velocity_max = 2.2
	sparks.gravity = Vector3(0, -2.5, 0)
	var sm2 := SphereMesh.new()
	sm2.radius = 0.025
	sm2.height = 0.05
	sparks.mesh = sm2
	sparks.material_override = _glow_mat(Color("dff4ff"), 5.0)
	main.add_child(sparks)
	return { "node": mi, "mat": mat, "hits": [], "extra": [glow, light, sparks], "glow": glow, "light": light, "sparks": sparks }


## The bubble pours out of the staff's orb: put the glow, its light and the sparks there, tell the shader where the
## orb is (so the energy flows out across the dome from that point), and keep the sparks sliding over the surface.
func _orb_emit(b: Dictionary, av: Node3D, c: Vector3, delta: float) -> void:
	var orb := c + Vector3(0, Weapons.SHIELD_RADIUS, 0)
	if av.has_method("orb_position"):
		var op = av.orb_position()
		if op != null:
			orb = op
	var dir := (orb - c).normalized() if orb.distance_to(c) > 1e-3 else Vector3.UP
	(b.mat as ShaderMaterial).set_shader_parameter("emit", dir)
	var pulse := 1.0 + 0.15 * sin(Time.get_ticks_msec() * 0.012)
	(b.glow as Node3D).global_position = orb
	(b.glow as Node3D).scale = Vector3.ONE * pulse
	(b.light as Node3D).global_position = orb
	(b.light as OmniLight3D).light_energy = 2.0 + 0.8 * sin(Time.get_ticks_msec() * 0.02)
	(b.sparks as CPUParticles3D).global_position = orb
	(b.sparks as CPUParticles3D).direction = dir


func _shield_hit(id: int, at: Vector3, strength := 8.0) -> void:
	var k := clampf(strength / 10.0, 0.4, 2.2)   # how big the hit was: the ripple and the flash scale with it
	var c := at
	if bubbles.has(id):
		var b: Dictionary = bubbles[id]
		c = (b.node as Node3D).global_position
		var d := (at - c)
		b.hits.push_front([d.normalized() if d.length() > 1e-3 else Vector3.UP, 0.0, k])
		if b.hits.size() > 6:
			b.hits.resize(6)
	var out := (at - c).normalized() if at.distance_to(c) > 1e-3 else Vector3.UP
	Fx.burst(main, at, out, Color("cdeeff"), int(8 + 8 * k), 3.0 + 2.0 * k, 0.035)
	_flash_light(at, Color("8fd8ff"), 1.5 + 1.5 * k, 2.5 + 2.0 * k, 0.18)


func _stun_beam(from: Vector3, to: Vector3, hit: bool, lv := 1) -> void:
	var beam := _jag(from, to, maxi(3, int(from.distance_to(to) / 1.5)), 0.25, 0.06 + 0.025 * (lv - 1), Color("c070ff") if lv < 3 else Color("f070d8"))
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
		_rune(id, st, av, delta)
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


## v0.12.7 lv: II more shards and a second, slower ring; III great ice spikes erupting round the caster too.
func _frost_nova(at: Vector3, r: float, lv := 1) -> void:
	if lv >= 2:
		_shock_ring(at, r * 0.8, Color("dff8ff"), 0.6)
	if lv >= 3:
		for i in 10:   # ice spikes erupting close in: tall, jagged, glowing blue-white
			var a := TAU * float(i) / 10.0 + randf_range(-0.2, 0.2)
			var d := randf_range(1.2, 3.3)
			var sp := MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = Vector3(randf_range(0.25, 0.4), randf_range(1.3, 2.2), randf_range(0.25, 0.38))
			sp.mesh = pm
			var sm := _glow_mat(Color("7fcfff"), 1.1, 0.75)
			sp.material_override = sm
			main.add_child(sp)
			sp.global_position = at + Vector3(cos(a) * d, -1.4, sin(a) * d)
			sp.rotation = Vector3(randf_range(-0.35, 0.35), randf() * TAU, randf_range(-0.35, 0.35))
			var t := sp.create_tween()
			t.tween_interval(0.05 + 0.03 * i)
			t.tween_property(sp, "global_position:y", at.y + pm.size.y * 0.35, 0.09).set_ease(Tween.EASE_OUT)
			t.tween_interval(1.2)
			t.tween_property(sm, "albedo_color:a", 0.0, 0.7)
			t.tween_callback(sp.queue_free)
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
	for i in 22 + 12 * (lv - 1):   # ice shards bursting up round the ring, each a moment after the wave reaches it
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


## v0.12.0: a challenger wizard's wind-up tell: a light in the spell's colour at its hand, swelling until the cast,
## with motes drawn in.
func _npc_tell(id: int, spell: String, life: float) -> void:
	if not avatars.has(id):
		return
	var av: Node3D = avatars[id]
	var c: Color = SPELL_COLOR.get(spell, Color.WHITE)
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = 0.3
	l.omni_range = 3.0
	av.add_child(l)
	l.position = Vector3(0, 1.5, 0)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 3.5, maxf(life, 0.1))
	tw.tween_property(l, "light_energy", 0.0, 0.25)
	tw.tween_callback(l.queue_free)
	var motes := func() -> void:
		if is_instance_valid(av):
			Fx.burst(main, av.position + Vector3(0, 1.5, 0), Vector3.UP, c, 6, 1.2, 0.04)
	for k in 3:
		get_tree().create_timer(life * k / 3.0 + 0.01).timeout.connect(motes)


## v0.12.0 the Heal Aura's pulse: a green-gold ring spreading over the ground to its reach, motes rising round the
## caster and from everyone healed, "+N" over each, and a soft chime.
var _heal_snd: AudioStream


## v0.12.7 lv: II a brighter double ring; III gold-green with a column of rising sparkles (its cleanse).
func _heal_pulse(id: int, at: Vector3, r: float, got: Array, lv := 1) -> void:
	var c := at
	if avatars.has(id):
		c = (avatars[id] as Node3D).position
	if lv >= 2:
		_shock_ring(c, r, Color("b8ffb0") if lv == 2 else Color("ffe88a"), 0.5)
	if lv >= 3:
		Fx.burst(main, c + Vector3(0, 0.3, 0), Vector3.UP, Color("fff2a0"), 14, 3.5, 0.04)
	var ring := _disc(c, r, Color("9dff9a") if lv < 3 else Color("d8ff8a"), 0.22 + 0.06 * (lv - 1))
	ring.scale = Vector3(0.2, 1, 0.2)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(1, 1, 1), 0.45)
	tw.tween_property(ring.material_override, "albedo_color:a", 0.0, 0.5)
	tw.chain().tween_callback(ring.queue_free)
	Fx.burst(main, c + Vector3(0, 2.3, 0), Vector3.UP, Color("ffe27a"), 6, 1.4, 0.04)
	for g in got:
		var who := int(g[0])
		var amt := int(g[1])
		if not avatars.has(who) or amt <= 0:
			continue
		var p := (avatars[who] as Node3D).position
		Fx.burst(main, p + Vector3(0, 0.3, 0), Vector3.UP, Color("8aff8a") if who % 2 else Color("ffe27a"), 8, 2.2, 0.045)
		var l := Label3D.new()
		l.text = "+%d" % amt
		l.modulate = Color("7dffa0")
		l.font_size = 40
		l.outline_size = 8
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		main.add_child(l)
		l.global_position = p + Vector3(randf_range(-0.3, 0.3), 2.4, 0)
		var lt := l.create_tween().set_parallel(true)
		lt.tween_property(l, "global_position:y", l.global_position.y + 0.7, 0.8)
		lt.tween_property(l, "modulate:a", 0.0, 0.4).set_delay(0.4)
		lt.chain().tween_callback(l.queue_free)
	if _heal_snd == null:
		_heal_snd = Synth.fx("heal")
	if avatars.has(net.my_id) and (avatars[net.my_id] as Node3D).position.distance_to(c) < 30.0:
		Synth.play(main, _heal_snd, -10.0)


var _block_snd := {}


## v0.12.5 a blow caught on a block: sparks off the weapon (a shower for the sword, club and staff, a few dull chips
## for the rest), a quick flash, "BLOCKED" and how much it saved, the defender jolted back, and a clang (metal / wood)
## or a dull knock.
func _block(id: int, at: Vector3, w: int, saved: int) -> void:
	var hard := Weapons.block_keep(w) < 0.5
	var col := Color("fff0b0") if hard else Color("d8c7a0")
	var out := Vector3.UP
	if avatars.has(id):
		var av := avatars[id] as Node3D
		out = (at - av.position - Vector3(0, 1.15, 0)).normalized() + Vector3(0, 0.6, 0)
		if av.has_method("hitstop"):
			av.hitstop(0.06, false)
	Fx.burst(main, at, out, col, 22 if hard else 9, 5.5 if hard else 3.0, 0.035)
	_flash_light(at, col, 2.5 if hard else 1.0, 4.0, 0.15)
	Fx.word(main, at + Vector3(0, 0.9, 0), "BLOCKED" + (" -%d" % saved if saved > 0 else ""), Color("ffe08a") if hard else Color("e6dccb"))
	var kind := "clang" if hard else "thock"
	if not _block_snd.has(kind):
		_block_snd[kind] = Synth.fx(kind)
	if avatars.has(net.my_id) and (avatars[net.my_id] as Node3D).position.distance_to(at) < 35.0:
		Synth.play(main, _block_snd[kind], -6.0 if hard else -4.0)


## v0.12.0 Life Drain on an ally: a green-gold healing stream from the caster's wand into them, motes flowing along
## it, a soft green light and "+N" over them.
func _drain_ally(hand: Vector3, at: Vector3, heal: int, target: int) -> void:
	var beam := _jag(hand, at, maxi(3, int(at.distance_to(hand) / 1.2)), 0.12, 0.05, Color("b8ff6a"))
	var mat: StandardMaterial3D = beam.get_meta("mat")
	var tw := beam.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.6)
	tw.tween_callback(beam.queue_free)
	for k in 9:
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.07
		sm.height = 0.14
		m.mesh = sm
		m.material_override = _glow_mat(Color("7dffa0") if k % 2 else Color("ffd860"), 4.0)
		main.add_child(m)
		m.global_position = hand
		var side := Vector3(randf_range(-0.5, 0.5), randf_range(0.0, 0.6), randf_range(-0.5, 0.5))
		var fly := func(x: float) -> void:
			m.global_position = hand.lerp(at, x) + side * sin(x * PI)
		var t := m.create_tween()
		t.tween_interval(k * 0.05)
		t.tween_method(fly, 0.0, 1.0, 0.45)
		t.tween_callback(m.queue_free)
	Fx.burst(main, at, Vector3.UP, Color("9dff9a"), 16, 2.0, 0.05)
	_flash_light(at + Vector3(0, 0.3, 0), Color("8aff8a"), 2.0, 4.0, 0.5)
	var where := at + Vector3(0, 1.2, 0)
	if avatars.has(target):
		where = (avatars[target] as Node3D).position + Vector3(0, 2.5, 0)
	if heal > 0:
		var l := Label3D.new()
		l.text = "+%d" % heal
		l.modulate = Color("7dffa0")
		l.font_size = 52
		l.outline_size = 10
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		main.add_child(l)
		l.global_position = where
		var lt := l.create_tween().set_parallel(true)
		lt.tween_property(l, "global_position:y", where.y + 0.9, 1.0).set_delay(0.4)
		lt.tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.8)
		lt.chain().tween_callback(l.queue_free)


## v0.12.0 Spark Beam: a quick bright zap, gone in a tenth of a second or so.
## v0.12.7 lv: II a thicker blue beam that bursts through each one it pierces (`through`: those points); III thicker
## again with a white core and an arc leaping on to `arc` (a point, or none).
func _spark(from: Vector3, to: Vector3, hit: bool, lv := 1, through: Array = [], arc: Array = []) -> void:
	var beam := _jag(from, to, maxi(2, int(from.distance_to(to) / 2.5)), 0.08, 0.035 * (1.0 + 0.5 * (lv - 1)), Color("dff4ff") if lv == 1 else Color("9fd4ff"))
	var mat: StandardMaterial3D = beam.get_meta("mat")
	var tw := beam.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.14 + 0.04 * (lv - 1))
	tw.tween_callback(beam.queue_free)
	if lv >= 3:
		var core := _jag(from, to, 2, 0.02, 0.025, Color("ffffff"))
		var cmat: StandardMaterial3D = core.get_meta("mat")
		var ct := core.create_tween()
		ct.tween_property(cmat, "albedo_color:a", 0.0, 0.12)
		ct.tween_callback(core.queue_free)
	for p in through:
		Fx.burst(main, p, (to - from).normalized(), Color("bfe8ff"), 8, 3.0, 0.03)
	for p in arc:
		_chain(to, p, 0.6, lv)
	Fx.burst(main, to, (from - to).normalized(), Color("bfe8ff"), 10 if hit else 4, 3.0, 0.03)
	_flash_light(from, Color("bfe8ff"), 1.2, 3.0, 0.08)
	_flash_light(to, Color("9fd8ff"), 1.8 if hit else 0.8, 3.0, 0.12)


## v0.12.0 Life Drain: a dark red stream from the victim, and motes of life flowing along it back into the caster's
## wand (following the caster if they move), then "+N" over the caster.
func _drain(id: int, hand: Vector3, at: Vector3, heal: int, lv := 1) -> void:
	var beam := _jag(at, hand, maxi(3, int(at.distance_to(hand) / 1.2)), 0.18, 0.05 + 0.025 * (lv - 1), Color("d0203a") if lv < 3 else Color("ff2050"))
	if lv >= 2:   # v0.12.7: a darker second strand twisting round it
		var b2 := _jag(at, hand, maxi(4, int(at.distance_to(hand) / 0.9)), 0.3, 0.03, Color("7a0820"))
		var m2: StandardMaterial3D = b2.get_meta("mat")
		var t2 := b2.create_tween()
		t2.tween_property(m2, "albedo_color:a", 0.0, 0.6)
		t2.tween_callback(b2.queue_free)
	var mat: StandardMaterial3D = beam.get_meta("mat")
	var tw := beam.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.55)
	tw.tween_callback(beam.queue_free)
	Fx.burst(main, at, Vector3.UP, Color("ff3050"), 14, 2.5, 0.05)
	for k in 9:
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.07
		sm.height = 0.14
		m.mesh = sm
		m.material_override = _glow_mat(Color("ff4060") if k % 3 else Color("7dffa0"), 4.0)
		main.add_child(m)
		m.global_position = at
		var side := Vector3(randf_range(-0.6, 0.6), randf_range(0.0, 0.8), randf_range(-0.6, 0.6))
		var t := m.create_tween()
		t.tween_interval(k * 0.05)
		var fly := func(x: float) -> void:
			var end := hand
			if avatars.has(id):
				end = (avatars[id] as Node3D).position + Vector3(0, 1.4, 0)
			m.global_position = at.lerp(end, x) + side * sin(x * PI)
			m.scale = Vector3.ONE * (1.0 - 0.5 * x)
		t.tween_method(fly, 0.0, 1.0, 0.45)
		t.tween_callback(m.queue_free)
	_flash_light(at + Vector3(0, 0.3, 0), Color("ff2040"), 2.0, 4.0, 0.4)
	if heal > 0 and avatars.has(id):
		var l := Label3D.new()
		l.text = "+%d" % heal
		l.modulate = Color("7dffa0")
		l.font_size = 52
		l.outline_size = 10
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		main.add_child(l)
		l.global_position = (avatars[id] as Node3D).position + Vector3(0, 2.5, 0)
		var lt := l.create_tween().set_parallel(true)
		lt.tween_property(l, "global_position:y", l.global_position.y + 0.9, 1.0).set_delay(0.4)
		lt.tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.8)
		lt.chain().tween_callback(l.queue_free)


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
	# v0.12.0: the column rides along with the player (a child of their avatar) for ~3.5 s, then fades
	(avatars[id] as Node3D).add_child(col)
	col.position = Vector3(0, 4.5, 0)
	var glow := OmniLight3D.new()
	glow.light_color = Color("ffd86a")
	glow.light_energy = 3.0
	glow.omni_range = 7.0
	glow.position = Vector3(0, -2.5, 0)
	col.add_child(glow)
	var tw := col.create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(m, "albedo_color:a", 0.0, 1.4)
	tw.parallel().tween_property(glow, "light_energy", 0.0, 1.4)
	tw.tween_callback(col.queue_free)
	_flash_light(at + Vector3(0, 2, 0), Color("ffd86a"), 6.0, 10.0, 1.2)
	Fx.burst(main, at + Vector3(0, 1.0, 0), Vector3.UP, Color("ffe9a0"), 50, 6.0, 0.05)
	var what := ("%s LEVEL %d!" % [Weapons.NAMES[w].to_upper(), lv]) + ("  New spell: " + spell if spell != "" else "")
	if Weapons.is_arm(w):   # v0.12.5: the other weapons just hit harder
		what += "  Damage +%d%%" % int(round((float(Weapons.ARM_DAMAGE[clampi(lv, 1, Weapons.MAX_LEVEL) - 1]) - 1.0) * 100.0))
	Fx.word(main, at + Vector3(0, 2.6, 0), what, Color("ffd86a"))
	if id == net.my_id and main.has_method("toast"):
		main.toast(what + ("  (R to pick it)" if spell != "" else ""))


func _shatter(id: int, at: Vector3) -> void:
	if bubbles.has(id):
		bubbles[id].shattered = true
		(bubbles[id].node as Node3D).visible = false
		for n in bubbles[id].get("extra", []):
			(n as Node3D).visible = false
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


## v0.12.7 lv: II a second ring; III pink-violet (its charm) with a burst of pink motes.
func _stun_burst(at: Vector3, r: float, lv := 1) -> void:
	if lv >= 2:
		_shock_ring(at, r * 1.15, Color("e0b0ff") if lv == 2 else Color("ff90e8"), 0.4)
	if lv >= 3:
		Fx.burst(main, at + Vector3(0, 0.6, 0), Vector3.UP, Color("ff90e8"), 30, 3.5, 0.05)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	ring.mesh = tm
	var m := _glow_mat(Color("c070ff") if lv < 3 else Color("e070d0"), 4.0, 0.9)
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


## v0.12.7 lv: the caster's Meteor mastery: II / III rocks are bigger and burn hotter (III trails white fire).
func _meteor_fall(at: Vector3, fall: float, r: float, lv := 1) -> void:
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
	trail.scale = Vector3.ONE * (3.0 + 0.6 * (lv - 1))
	rock.add_child(trail)
	rock.scale = Vector3.ONE * (1.0 + 0.15 * (lv - 1))
	if lv >= 3:
		rm.emission = Color("ffb040")
		rm.emission_energy_multiplier = 2.6
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


func _meteor_hit(at: Vector3, r: float, burn: float, burn_r: float, lv := 1) -> void:
	_explosion(at + Vector3(0, 0.5, 0), r, lv)
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


## v0.12.7 lv: II / III a wider vortex with a fourth (and fifth) ring; III gold-flecked motes and a brighter heart.
func _well(at: Vector3, life: float, r: float, lv := 1) -> void:
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
	for i in 2 + lv:   # rings spinning at different tilts
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.9 + i * 0.5
		tm.outer_radius = 1.0 + i * 0.5
		ring.mesh = tm
		ring.material_override = _glow_mat(Color("a060ff") if i < 3 or lv < 3 else Color("ffc860"), 2.5, 0.55)
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
	motes.material_override = _glow_mat(Color("c090ff") if lv < 3 else Color("ffd890"), 3.0)
	motes.amount = 90 + 40 * (lv - 1)
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


func _well_burst(at: Vector3, r: float, lv := 1) -> void:
	if lv >= 2:
		_shock_ring(at + Vector3(0, -0.9, 0), r * 1.3, Color("c090ff") if lv == 2 else Color("ffd890"), 0.45)
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


## v0.12.7 lv: II / III a bigger, thicker cloud (III with gold-violet flashes inside).
func _storm(at: Vector3, life: float, area: float, lv := 1) -> void:
	var root := Node3D.new()
	main.add_child(root)
	root.global_position = at + Vector3(0, 12.0, 0)
	var puffs := []
	for i in 26 + 10 * (lv - 1):   # the cloud: dark puffs in a churning disc
		var p := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var r := randf_range(1.8, 3.4)
		sm.radius = r
		sm.height = r * 1.2
		p.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.16, 0.15, 0.22, 0.0)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.emission_enabled = true
		m.emission = Color("4a3a8a") if lv < 3 or i % 3 != 0 else Color("8a6a3a")
		m.emission_energy_multiplier = 0.0
		p.material_override = m
		var a := randf() * TAU
		var d := sqrt(randf()) * (area + 2.0)
		p.position = Vector3(cos(a) * d, randf_range(-0.8, 0.8), sin(a) * d)
		root.add_child(p)
		puffs.append([p, m])
		var tw := p.create_tween()
		tw.tween_property(m, "albedo_color:a", 0.88, 1.0)
	var l := OmniLight3D.new()
	l.light_color = Color("8fa8ff")
	l.omni_range = area * 3.5
	l.light_energy = 0.0
	root.add_child(l)
	l.position.y = -2.0
	var t0 := Time.get_ticks_msec()
	var timer := Timer.new()
	timer.wait_time = 1.0 / 30.0
	timer.autostart = true
	timer.timeout.connect(func():
		root.rotate_y(0.25 / 30.0)
		var flick := randf() < 0.12
		l.light_energy = randf_range(2.5, 5.0) if flick else maxf(l.light_energy - 0.6, 0.3)
		for pm in puffs:
			(pm[1] as StandardMaterial3D).emission_energy_multiplier = 1.4 if flick and randf() < 0.5 else 0.15)
	root.add_child(timer)
	var shade := _disc(at, area, Color(0.05, 0.04, 0.1), 0.0)   # the storm's shadow on the ground
	shade.create_tween().tween_property(shade.material_override, "albedo_color:a", 0.35, 1.0)
	get_tree().create_timer(life).timeout.connect(func():
		for pm in puffs:
			(pm[0] as Node3D).create_tween().tween_property(pm[1], "albedo_color:a", 0.0, 1.2)
		shade.create_tween().tween_property(shade.material_override, "albedo_color:a", 0.0, 1.2)
		get_tree().create_timer(1.3).timeout.connect(func():
			root.queue_free()
			shade.queue_free()))


# ================================================================ v0.8.0: runes, blinks, summoning circles, cracks
## A rune circle under someone casting: two rings and a band of glyphs turning opposite ways, in the spell's colour;
## it grows as the spell builds, flares as it goes off and shrinks away after.
func _rune(id: int, st: Sim.PlayerState, av: Node3D, delta: float) -> void:
	var casting := st != null and av != null and st.dead == 0 and Weapons.is_magic(st.weapon) and st.atk > 0 and st.shield == 0
	if casting and not runes.has(id):
		runes[id] = _make_rune()
	if not runes.has(id):
		return
	var r: Dictionary = runes[id]
	var root: Node3D = r.root
	if not casting:
		root.queue_free()
		runes.erase(id)
		return
	var sp := Weapons.spell(st.weapon, st.spell)
	var c: Color = SPELL_COLOR.get(str(sp.name), Color.WHITE)
	var into := float(int(sp.cast) - st.atk)
	var k := clampf(into / maxf(float(sp.windup), 1.0), 0.0, 1.0)
	var after := clampf((into - float(sp.windup)) / maxf(float(int(sp.cast) - int(sp.windup)), 1.0), 0.0, 1.0)
	var size := (0.35 + 0.85 * sqrt(k)) * (1.0 + 0.25 * sin(minf(after * 6.0, PI))) * (1.0 - after * 0.6)
	root.global_position = Vector3(av.position.x, WorldLayout.ground_height(av.position.x, av.position.z, av.position.y + 0.3) + 0.04, av.position.z)
	root.scale = Vector3(size, 1, size)
	(r.outer as Node3D).rotation.y += delta * 1.2
	(r.glyphs as Node3D).rotation.y -= delta * 2.2
	for m: StandardMaterial3D in r.mats:
		m.albedo_color = Color(c.r, c.g, c.b, (0.35 + 0.5 * k) * (1.0 - after * 0.8))
		m.emission = c
		m.emission_energy_multiplier = 2.0 + 4.0 * k + (6.0 * (1.0 - after) if into >= float(sp.windup) else 0.0)


func _make_rune() -> Dictionary:
	var root := Node3D.new()
	main.add_child(root)
	var mats := []
	var outer := Node3D.new()
	root.add_child(outer)
	for spec in [[1.0, 0.94], [0.72, 0.68]]:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.outer_radius = spec[0]
		tm.inner_radius = spec[1]
		tm.rings = 40
		tm.ring_segments = 4
		ring.mesh = tm
		ring.scale = Vector3(1, 0.15, 1)
		var m := _glow_mat(Color.WHITE, 3.0, 0.6)
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		ring.material_override = m
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		outer.add_child(ring)
		mats.append(m)
	var gm := _glow_mat(Color.WHITE, 3.0, 0.6)
	gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mats.append(gm)
	var glyphs := Node3D.new()
	root.add_child(glyphs)
	for i in 10:   # glyphs: little strokes and diamonds between the rings
		var g := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.01, 0.16) if i % 2 == 0 else Vector3(0.09, 0.01, 0.09)
		g.mesh = bm
		g.material_override = gm
		var a := TAU * i / 10.0
		g.position = Vector3(cos(a) * 0.83, 0.0, sin(a) * 0.83)
		g.rotation.y = -a + (PI * 0.25 if i % 2 == 1 else 0.0)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glyphs.add_child(g)
	for i in 3:   # a triangle inside
		var a0 := TAU * i / 3.0
		var a1 := TAU * (i + 1) / 3.0
		var p0 := Vector3(cos(a0), 0, sin(a0)) * 0.66
		var p1 := Vector3(cos(a1), 0, sin(a1)) * 0.66
		var e := MeshInstance3D.new()
		var em := BoxMesh.new()
		em.size = Vector3(0.025, 0.01, p0.distance_to(p1))
		e.mesh = em
		e.material_override = gm
		e.position = (p0 + p1) * 0.5
		e.rotation.y = atan2(p1.x - p0.x, p1.z - p0.z)
		glyphs.add_child(e)
	return { "root": root, "outer": outer, "glyphs": glyphs, "mats": mats }


## The teleport's two ends: leaving, a column of violet light collapses inward with motes sucked into it; arriving, a
## column bursts out with a shock ring and sparks. v0.12.7 lv: II / III taller, brighter columns (III gold-edged).
func _blink(at: Vector3, arrive: bool, lv := 1) -> void:
	var col := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.55
	cm.bottom_radius = 0.65
	cm.height = 2.6 + 0.8 * (lv - 1)
	cm.radial_segments = 16
	col.mesh = cm
	var m := _glow_mat(Color("c58cff") if lv < 3 else Color("e6b0ff"), 4.0 + lv, 0.55)
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	col.material_override = m
	col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(col)
	col.global_position = at + Vector3(0, 1.3, 0)
	var tw := col.create_tween().set_parallel(true)
	if arrive:
		col.scale = Vector3(0.1, 1.4, 0.1)
		tw.tween_property(col, "scale", Vector3(1.3, 0.6, 1.3), 0.3).set_ease(Tween.EASE_OUT)
		tw.tween_property(m, "albedo_color:a", 0.0, 0.35)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.9
		tm.outer_radius = 1.0
		ring.mesh = tm
		var rm := _glow_mat(Color("d8b0ff"), 3.0, 0.8)
		ring.material_override = rm
		main.add_child(ring)
		ring.global_position = at + Vector3(0, 0.1, 0)
		ring.scale = Vector3(0.3, 0.3, 0.3)
		var rtw := ring.create_tween().set_parallel(true)
		rtw.tween_property(ring, "scale", Vector3(2.4, 0.3, 2.4), 0.35).set_ease(Tween.EASE_OUT)
		rtw.tween_property(rm, "albedo_color:a", 0.0, 0.38)
		rtw.chain().tween_callback(ring.queue_free)
		Fx.burst(main, at + Vector3(0, 1.0, 0), Vector3.UP, Color("e2c4ff"), 26, 5.0, 0.04)
	else:
		col.scale = Vector3(1.2, 1.0, 1.2)
		tw.tween_property(col, "scale", Vector3(0.02, 1.6, 0.02), 0.28).set_ease(Tween.EASE_IN)
		tw.tween_property(m, "albedo_color:a", 0.0, 0.3).set_delay(0.05)
		var motes := CPUParticles3D.new()   # sucked in toward the middle
		motes.one_shot = true
		motes.explosiveness = 0.7
		motes.amount = 30
		motes.lifetime = 0.35
		motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		motes.emission_sphere_radius = 1.4
		motes.radial_accel_min = -40.0
		motes.radial_accel_max = -30.0
		motes.gravity = Vector3.ZERO
		var mm := SphereMesh.new()
		mm.radius = 0.035
		mm.height = 0.07
		motes.mesh = mm
		motes.material_override = _glow_mat(Color("e2c4ff"), 4.0)
		main.add_child(motes)
		motes.global_position = at + Vector3(0, 1.0, 0)
		motes.emitting = true
		motes.finished.connect(motes.queue_free)
	tw.chain().tween_callback(col.queue_free)
	_flash_light(at + Vector3(0, 1, 0), Color("b066ff"), 3.5, 6.0, 0.35)


## A summoning circle on the ground where a golem or the titan rises: it glows in, turns, and fades as it stands.
func _summon_circle(at: Vector3, r: float, c: Color, life: float) -> void:
	var rd := _make_rune()
	var root: Node3D = rd.root
	root.global_position = Vector3(at.x, WorldLayout.ground_height(at.x, at.z, at.y + 0.3) + 0.04, at.z)
	root.scale = Vector3(r * 0.3, 1, r * 0.3)
	for m: StandardMaterial3D in rd.mats:
		m.albedo_color = Color(c.r, c.g, c.b, 0.8)
		m.emission = c
		m.emission_energy_multiplier = 4.0
	var tw := root.create_tween().set_parallel(true)
	tw.tween_property(root, "scale", Vector3(r, 1, r), 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "rotation:y", TAU * 0.6, life + 0.6)
	for m: StandardMaterial3D in rd.mats:
		tw.tween_property(m, "albedo_color:a", 0.0, 0.6).set_delay(life)
	tw.chain().tween_callback(root.queue_free)
	_flash_light(at + Vector3(0, 0.5, 0), c, 3.0, r * 3.0, life)


## Dark cracks splitting the ground outward from a point.
func _cracks(at: Vector3, r: float, n: int) -> void:
	var g := Vector3(at.x, WorldLayout.ground_height(at.x, at.z, at.y + 0.3) + 0.03, at.z)
	var paths := []
	for i in n:
		var a := TAU * float(i) / n + randf_range(-0.3, 0.3)
		var to := g + Vector3(cos(a), 0, sin(a)) * r * randf_range(0.6, 1.0)
		paths.append([_fractal(g, to, 3, 0.18).map(func(p): return Vector3(p.x, g.y, p.z)), 0.07])
	var mi := _ribbons(paths, Color(0.05, 0.04, 0.03), 0.0)
	var m: StandardMaterial3D = mi.material_override
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.emission_enabled = false
	m.albedo_color = Color(0.06, 0.05, 0.04, 0.0)
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.7, 0.08)
	tw.tween_interval(3.0)
	tw.tween_property(m, "albedo_color:a", 0.0, 1.5)
	tw.tween_callback(mi.queue_free)


## Chain lightning (v0.8.2): a jagged arc leaping from one target to the next, thinner and dimmer as the damage
## halves (k: this jump's share of the strike's damage), crackling twice; sparks, a small flash and a crackle on the
## one it lands on.
func _chain(a: Vector3, b: Vector3, k: float, lv := 1) -> void:
	k = clampf(k, 0.1, 1.0)
	var mid := (a + b) * 0.5 + Vector3(0, a.distance_to(b) * 0.15, 0)
	var path := _fractal(a, mid, 3, 0.22)
	path.append_array(_fractal(mid, b, 3, 0.22).slice(1))
	var wk: float = [1.0, 1.3, 1.7][clampi(lv, 1, 3) - 1]   # v0.12.7: fatter, whiter arcs with mastery
	var glow := _ribbons([[path, (0.3 * k + 0.06) * wk]], Color("6f9cff") if lv < 3 else Color("8fc8ff"), 2.0)
	var core := _ribbons([[path, (0.08 * k + 0.025) * wk]], Color("eef4ff") if lv < 3 else Color("ffffff"), 4.0 + 6.0 * k + lv)
	for mi: MeshInstance3D in [glow, core]:
		var m: StandardMaterial3D = mi.material_override
		m.albedo_color.a = (0.5 if mi == glow else 1.0) * (0.45 + 0.55 * k)
		var tw := mi.create_tween()
		tw.tween_property(m, "albedo_color:a", 0.1, 0.04)
		tw.tween_property(m, "albedo_color:a", (0.5 if mi == glow else 1.0) * (0.45 + 0.55 * k), 0.03)
		tw.tween_property(m, "albedo_color:a", 0.0, 0.18)
		tw.tween_callback(mi.queue_free)
	Fx.burst(main, b, Vector3.UP, Color("e8f6ff"), int(8 + 14 * k), 3.0 + 4.0 * k, 0.035)
	_flash_light(b, Color("cfe4ff"), 2.0 + 3.0 * k, 3.0 + 3.0 * k, 0.15)
	var crackle := []   # little arcs round the one it hit
	for i in 3:
		var c0 := b + Vector3(randf_range(-0.35, 0.35), randf_range(-0.7, 0.5), randf_range(-0.35, 0.35))
		crackle.append([_fractal(c0, c0 + Vector3(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), randf_range(-0.4, 0.4)), 2, 0.35), 0.025])
	var cr := _ribbons(crackle, Color("d8e8ff"), 6.0)
	var ctw := cr.create_tween()
	ctw.tween_property(cr.material_override, "albedo_color:a", 0.0, 0.2)
	ctw.tween_callback(cr.queue_free)
	_shake_near_scaled(b, 0.06 + 0.1 * k)


# ================================================================ v0.12.7: spell mastery
## A flat ring of light racing out over the ground to radius r and fading (shockwaves, the mastery accents).
func _shock_ring(at: Vector3, r: float, c: Color, life: float) -> void:
	var g := Vector3(at.x, WorldLayout.ground_height(at.x, at.z, at.y + 0.5) + 0.12, at.z)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	tm.rings = 32
	ring.mesh = tm
	var m := _glow_mat(c, 3.0, 0.85)
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(ring)
	ring.global_position = g
	ring.scale = Vector3(0.2, 0.35, 0.2)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(r, 0.35, r), life).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(m, "albedo_color:a", 0.0, life * 1.1)
	tw.chain().tween_callback(ring.queue_free)


## Fireball mastery III: a small fire bomb lobbed in an arc from the blast to where it pops (`life` seconds later).
func _bomblet(from: Vector3, to: Vector3, life: float) -> void:
	var b := FireballView.new()
	b.scale = Vector3.ONE * 0.55
	main.add_child(b)
	b.global_position = from
	var peak := maxf(from.y, to.y) + 1.6 + from.distance_to(to) * 0.25
	var fly := func(x: float) -> void:
		var p := from.lerp(to, x)
		p.y = lerpf(from.y, to.y, x) + (peak - maxf(from.y, to.y)) * 4.0 * x * (1.0 - x)
		b.global_position = p
	var tw := b.create_tween()
	tw.tween_method(fly, 0.0, 1.0, maxf(life, 0.05))
	tw.tween_callback(b.queue_free)


## Teleport mastery II / III: where you arrive, a blast of violet force: a ring racing out to its reach, a flash, a
## burst of motes; III bigger, gold-edged, with a second ring, a shake and dust thrown up.
func _tp_blast(at: Vector3, r: float, lv: int) -> void:
	_shock_ring(at, r, Color("d8a0ff"), 0.3)
	_flash_light(at + Vector3(0, 1.0, 0), Color("c070ff"), 4.0 + 2.0 * lv, r * 3.0, 0.3)
	Fx.burst(main, at + Vector3(0, 0.6, 0), Vector3.UP, Color("e2c4ff"), 20 + 15 * lv, 4.0 + lv, 0.05)
	var dome := MeshInstance3D.new()   # a brief see-through dome of force swelling out
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 1.0
	dome.mesh = sm
	var dm := _glow_mat(Color("c58cff") if lv < 3 else Color("f0c8ff"), 2.0, 0.35)
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	dome.material_override = dm
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(dome)
	dome.global_position = at
	dome.scale = Vector3.ONE * 0.3
	var tw := dome.create_tween().set_parallel(true)
	tw.tween_property(dome, "scale", Vector3(r, r * 0.7, r), 0.22).set_ease(Tween.EASE_OUT)
	tw.tween_property(dm, "albedo_color:a", 0.0, 0.3)
	tw.chain().tween_callback(dome.queue_free)
	if lv >= 3:
		get_tree().create_timer(0.08).timeout.connect(func(): _shock_ring(at, r * 1.25, Color("ffd890"), 0.4))
		_golem_dust(at, r * 0.6)
		_cracks(at, r * 0.8, 8)
		_shake_near(at, 0.2)


## Frost Nova mastery III: a block of clear blue ice round someone for `life` seconds, then it cracks apart.
func _freeze(id: int, at: Vector3, life: float) -> void:
	var p := at
	var tall := 2.0
	if avatars.has(id):
		p = (avatars[id] as Node3D).position
		tall *= (avatars[id] as Node3D).scale.y
	var ice := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, tall, 1.0) if id > 0 else Vector3(0.9, 1.3, 0.9)
	ice.mesh = bm
	var m := _glow_mat(Color("bfeaff"), 0.8, 0.45)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	ice.material_override = m
	ice.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(ice)
	ice.global_position = p + Vector3(0, bm.size.y * 0.5, 0)
	ice.rotation.y = randf() * TAU
	ice.scale = Vector3(1, 0.1, 1)
	var tw := ice.create_tween()
	tw.tween_property(ice, "scale", Vector3.ONE, 0.12).set_ease(Tween.EASE_OUT)
	tw.tween_interval(maxf(life - 0.2, 0.1))
	tw.tween_callback(func(): Fx.burst(main, ice.global_position, Vector3.UP, Color("e6faff"), 24, 4.0, 0.05))
	tw.tween_property(m, "albedo_color:a", 0.0, 0.15)
	tw.tween_callback(ice.queue_free)


## Fog mastery II / III: a few green bubbles rising off whoever the poison stung.
func _poison_puff(id: int) -> void:
	if not avatars.has(id):
		return
	var p := (avatars[id] as Node3D).position
	Fx.burst(main, p + Vector3(randf_range(-0.2, 0.2), 1.2, randf_range(-0.2, 0.2)), Vector3.UP, Color("8aff5a"), 6, 1.2, 0.05)


## A golden column of light round the player that rides along with them for a few seconds, a flash and a burst: the
## level-up (and v0.12.7 the mastery-up) moment. `c`: the column's colour.
func _column(id: int, c: Color) -> void:
	var at: Vector3 = (avatars[id] as Node3D).position
	var col := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.7
	cm.bottom_radius = 0.9
	cm.height = 9.0
	col.mesh = cm
	var m := _glow_mat(c, 3.0, 0.45)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	col.material_override = m
	(avatars[id] as Node3D).add_child(col)
	col.position = Vector3(0, 4.5, 0)
	var glow := OmniLight3D.new()
	glow.light_color = c
	glow.light_energy = 3.0
	glow.omni_range = 7.0
	glow.position = Vector3(0, -2.5, 0)
	col.add_child(glow)
	var tw := col.create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(m, "albedo_color:a", 0.0, 1.4)
	tw.parallel().tween_property(glow, "light_energy", 0.0, 1.4)
	tw.tween_callback(col.queue_free)
	_flash_light(at + Vector3(0, 2, 0), c, 6.0, 10.0, 1.2)
	Fx.burst(main, at + Vector3(0, 1.0, 0), Vector3.UP, c.lightened(0.4), 50, 6.0, 0.05)


## A spell's mastery went up: the golden column (with the spell's colour swirling in it), "FIREBALL MASTERY II!" over
## them and, on their own screen, a toast with what it does now.
func _mastery_up(id: int, w: int, i: int, lv: int) -> void:
	if not avatars.has(id):
		return
	var sp := Weapons.spell(w, i)
	var name := str(sp.get("name", "?"))
	_column(id, Color("ffd86a"))
	var c: Color = SPELL_COLOR.get(name, Color.WHITE)
	var at: Vector3 = (avatars[id] as Node3D).position
	for k in 3:   # rings of the spell's colour rising up the column
		get_tree().create_timer(0.15 * k).timeout.connect(func():
			if is_instance_valid(avatars.get(id)):
				_shock_ring((avatars[id] as Node3D).position + Vector3(0, 0.2 + 1.2 * k, 0), 1.6, c, 0.6))
	var what := "%s MASTERY %s!" % [name.to_upper(), Weapons.MASTERY_ROMAN[clampi(lv, 1, 3) - 1]]
	Fx.word(main, at + Vector3(0, 2.6, 0), what, Color("ffd86a"))
	var line := str(sp.get("m%d" % lv, {}).get("text", ""))
	if id == net.my_id and main.has_method("toast"):
		main.toast(what + ("  " + line if line != "" else ""))


## Stun mastery III: a pink-violet swirl over the head of every charmed unit (the roster says who), turning.
var charms := {}   # id -> the swirl


func _charm_swirls(delta: float) -> void:
	var on := {}
	for id in net.roster.keys():
		if bool(net.roster[id].get("charmed", false)) and avatars.has(id):
			on[id] = true
	for id in charms.keys():
		if not on.has(id):
			(charms[id] as Node3D).queue_free()
			charms.erase(id)
	for id in on.keys():
		if not charms.has(id):
			var root := Node3D.new()
			main.add_child(root)
			for k in 3:
				var ring := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = 0.22 + 0.08 * k
				tm.outer_radius = 0.26 + 0.08 * k
				ring.mesh = tm
				ring.material_override = _glow_mat(Color("f080e0") if k != 1 else Color("b070ff"), 3.0, 0.8)
				ring.rotation = Vector3(0.5 * (k - 1), 0, 0.3 * (1 - k))
				ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				root.add_child(ring)
			charms[id] = root
		var sw: Node3D = charms[id]
		var av := avatars[id] as Node3D
		sw.global_position = av.position + Vector3(0, 2.3 * av.scale.y, 0)
		sw.rotation.y += delta * 4.0
		if randf() < delta * 6.0:
			Fx.burst(main, sw.global_position, Vector3.UP, Color("ffa0f0"), 1, 0.8, 0.04)

