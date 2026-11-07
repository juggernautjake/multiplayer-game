## v0.12.15 (Jacob: "add sound for the animations for the sword, club, sling shot, arrow, staff and spells, and wand and
## spells, for jumping and all of that"). Every player's and fighter's actions make a sound now:
##  - weapons: the sword's swish (heavier on the combo's finisher), the club's whump, a punch's jab, each when the blow
##    lands in the animation; the bow's creak as it's drawn and its twang and the arrow's whizz on release; the
##    slingshot's stretch and snap; hits: a sword's slash (a metal ring), a club's bonk, a punch, an arrow's thunk, a
##    stone's clack; arrows thudding into the ground;
##  - magic: a cast for each kind (arcane, fire, ice, the wand's darker one), then each spell's own sound: thunder and
##    crackle for Lightning, a whoosh and a boom for Fireball, the shield's swell / ping / shatter, Frost Nova's ice,
##    a meteor's falling whistle and impact, Teleport's blink, Stun's zap, the gravity well's warble, Life Drain's
##    suck, golems and the titan rising and slamming, poison's bubbles, level-ups' chime;
##  - moving: a hop on a jump, a thud on landing (harder from higher), a whoosh on a dash, footsteps, a body falling.
## Every sound is made from scratch (like Synth's) and built in the background at start-up (Synth.warm). They play on the
## Effects channel, quieter with distance from you, a little louder for your own actions, and each with a slightly
## different pitch so repeats don't sound copied. Your own actions are read from your predicted state, so they sound
## the moment you act (no network delay); the spells' effects come from the host's events.
class_name ActionSounds
extends Node

const RATE := Synth.RATE
## kind -> seconds
const DUR := { "swish": 0.3, "swish_heavy": 0.42, "whump": 0.38, "jab": 0.16, "slash": 0.42, "bonk": 0.32, "punch": 0.2,
	"thunk": 0.22, "clack": 0.16, "creak": 0.5, "stretch": 0.35, "twang": 0.55, "snap": 0.22, "whizz": 0.45,
	"cast": 0.5, "cast_fire": 0.5, "cast_ice": 0.5, "cast_dark": 0.5, "fire_whoosh": 0.7, "boom": 1.4, "boom_small": 0.6,
	"shield_up": 0.7, "ping": 0.45, "shatter": 0.9, "blink": 0.35, "frost": 0.9, "ice": 0.45, "bubble": 0.3,
	"chime": 0.7, "levelup": 1.1, "fall": 1.3, "well": 1.4, "suck": 0.6, "jump": 0.2, "land": 0.28, "step0": 0.09,
	"step1": 0.09, "dash": 0.32, "zap_small": 0.22 }
## the air sounds (band-passed noise): the sweep's [from, to] in Hz
const AIR := { "swish": [900.0, 3400.0], "swish_heavy": [600.0, 2400.0], "whump": [240.0, 950.0], "jab": [1300.0, 2600.0],
	"dash": [700.0, 2600.0], "jump": [500.0, 1400.0], "whizz": [2600.0, 1100.0], "fire_whoosh": [350.0, 1800.0],
	"suck": [300.0, 1600.0] }
const HEAR := 70.0   # metres: further than this, not heard

var net: Net
var main: Node3D
var _prev := {}   # id -> what its state was last frame (to spot a new swing, a jump, a landing...)
var _log := OS.get_cmdline_user_args().has("--soundlog")


static func sound(kind: String) -> AudioStreamWAV:
	return Synth._memo("act " + kind, _make.bind(kind))


## Build every one (Synth._warm_all calls this on its background thread).
static func warm_all() -> void:
	for k in DUR.keys():
		sound(k)


func setup(n: Net, m: Node3D) -> void:
	net = n
	main = m
	net.magic_fx.connect(_on_fx)
	net.hit.connect(_on_hit)


# ================================================================ playing
## Play `kind` heard from `at`: quieter with distance from you (from the camera if you have no player), not at all
## past HEAR metres. var_pitch: how much the pitch may differ each time (+-).
func play(kind: String, at: Vector3, db := 0.0, delay := 0.0, var_pitch := 0.06) -> void:
	var me := _listener()
	var d := Vector2(at.x - me.x, at.z - me.z).length()
	if d > HEAR:
		return
	var vol := db - clampf(d * 0.35, 0.0, 30.0)
	if _log:   # --soundlog (testing): every sound as it plays
		print("[snd] %s %.0f dB" % [kind, vol])
	var st: AudioStream = Synth.thunder() if kind == "thunder" else (Synth.fx(kind.substr(3)) if kind.begins_with("fx ") else sound(kind))
	var pitch := 1.0 + randf_range(-var_pitch, var_pitch)
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(func(): Synth.play(main, st, vol, "Effects", pitch))
	else:
		Synth.play(main, st, vol, "Effects", pitch)


func _listener() -> Vector3:
	var avs: Dictionary = main.get("avatars")
	if avs != null and avs.has(net.my_id):
		return (avs[net.my_id] as Node3D).position
	var cam := main.get_viewport().get_camera_3d()
	return cam.global_position if cam else Vector3.ZERO


# ================================================================ every frame: what each character just did
func update(delta: float, avatars: Dictionary) -> void:
	for id in _prev.keys():
		if not avatars.has(id):
			_prev.erase(id)
	for id in avatars.keys():
		var av: Node3D = avatars[id]
		var st: Sim.PlayerState = av.get("state")
		if st == null or not av.visible:
			continue
		var pos := av.position
		var now := { "swing": st.swing_n, "charge": st.charge, "grounded": st.grounded, "dash": st.dash_ticks,
			"dead": st.dead, "shield": st.shield, "vy": st.vel.y, "step": 0.0, "weapon": st.weapon }
		if not _prev.has(id):
			_prev[id] = now
			continue
		var p: Dictionary = _prev[id]
		now.step = p.step
		var mine: bool = id == net.my_id
		var loud := 3.0 if mine else 0.0
		if st.dead == 0 and int(p.dead) == 0:
			if st.swing_n != int(p.swing) and st.weapon == int(p.weapon):
				_action(st, pos, loud)
			if st.charge > 0 and int(p.charge) == 0:   # drawing the bow / pulling the slingshot back
				if st.weapon == Weapons.BOW:
					play("creak", pos, -8.0 + loud)
				elif st.weapon == Weapons.SLING:
					play("stretch", pos, -9.0 + loud)
			if st.shield > 0 and int(p.shield) == 0:
				play("shield_up", pos, -4.0 + loud)
			if bool(p.grounded) and not st.grounded and st.vel.y > 2.0:
				play("jump", pos, -10.0 + loud, 0.0, 0.1)
			if not bool(p.grounded) and st.grounded and float(p.vy) < -4.0:   # landing: harder from higher
				play("land", pos, clampf(-16.0 + (-float(p.vy) - 4.0) * 0.9, -16.0, -2.0) + loud, 0.0, 0.1)
			if st.dash_ticks > 0 and int(p.dash) == 0:
				play("dash", pos, -6.0 + loud)
			# footsteps: faster the faster they move
			var speed := Vector2(st.vel.x, st.vel.z).length()
			if st.grounded and speed > 1.2:
				now.step = float(p.step) - delta
				if now.step <= 0.0:
					now.step = clampf(1.7 / speed, 0.24, 0.55)
					play("step0" if randf() < 0.5 else "step1", pos, (-17.0 if mine else -21.0) + minf(speed - 4.0, 4.0) * 0.6, 0.0, 0.12)
			else:
				now.step = 0.05
		elif st.dead > 0 and int(p.dead) == 0:   # knocked out: the body hits the ground
			play("land", pos, -3.0 + loud, 0.25, 0.08)
			play("punch", pos, -8.0 + loud, 0.3)
		_prev[id] = now


## A new swing, shot or cast (its swing counter moved on).
func _action(st: Sim.PlayerState, pos: Vector3, loud: float) -> void:
	var w := st.weapon
	if Weapons.is_melee(w):
		var mv := Weapons.move(w, st.combo)
		var at := float(mv.windup) * Config.DT   # the blow lands this long into the move
		var last: bool = st.combo == (Weapons.get_data(w).moves as Array).size() - 1
		match w:
			Weapons.SWORD:
				play("swish_heavy" if last else "swish", pos, -5.0 + loud, maxf(at - 0.08, 0.0))
			Weapons.CLUB:
				play("whump", pos, -4.0 + loud, maxf(at - 0.1, 0.0))
			_:
				play("jab", pos, -8.0 + loud, maxf(at - 0.04, 0.0), 0.12)
	elif w == Weapons.BOW:
		play("twang", pos, -4.0 + loud)
		play("whizz", pos, -12.0 + loud, 0.04)
	elif w == Weapons.SLING:
		play("snap", pos, -5.0 + loud)
		play("whizz", pos, -16.0 + loud, 0.03, 0.15)
	elif Weapons.is_magic(w):
		var sp := Weapons.spell(w, st.spell)
		if sp.get("hold", false) or sp.get("channel", false):   # the shield and Heal Aura have their own sounds
			return
		var nm := str(sp.name)
		var k := "cast_dark" if w == Weapons.WAND else "cast"
		if nm in ["Fireball", "Meteor"]:
			k = "cast_fire"
		elif nm == "Frost Nova":
			k = "cast_ice"
		play(k, pos, -7.0 + loud)


## Someone was hit: the sound of what hit them.
func _on_hit(target: int, _amount: int, pos: Vector3, _dir: Vector3, killed: bool, attacker: int) -> void:
	var avs: Dictionary = main.get("avatars")
	if avs == null or not avs.has(attacker) or avs[attacker].get("state") == null:
		return
	var w: int = (avs[attacker].state as Sim.PlayerState).weapon
	match w:
		Weapons.SWORD:
			play("slash", pos, -3.0)
		Weapons.CLUB:
			play("bonk", pos, -2.0)
		Weapons.FISTS:
			play("punch", pos, -4.0, 0.0, 0.12)
		Weapons.BOW:
			play("thunk", pos, -3.0)
		Weapons.SLING:
			play("clack", pos, -4.0)
			play("punch", pos, -10.0)
	if killed and target > 0:
		play("land", pos, -4.0, 0.3)


## An arrow or a stone came down without hitting anyone (Main, when it's drawn ending).
func shot_landed(kind: int, pos: Vector3, stuck: bool) -> void:
	if kind == 0 and stuck:
		play("thunk", pos, -9.0, 0.0, 0.1)
	elif kind == 1:
		play("clack", pos, -10.0, 0.0, 0.15)


## The spells' effects, from the host.
func _on_fx(kind: String, a: Array) -> void:
	var avs: Dictionary = main.get("avatars")
	var at_id := func(i: int) -> Vector3:
		return (avs[a[i]] as Node3D).position if avs != null and avs.has(a[i]) else Vector3(INF, 0, INF)
	match kind:
		"lightning_warn":
			play("zap_small", a[0], -10.0)
		"lightning":
			play("thunder", a[0], -3.0, 0.0, 0.08)
			play("zap_small", a[0], 0.0)
		"chain", "fork":
			play("zap_small", a[1], -5.0, 0.0, 0.15)
		"explode":
			play("boom" if float(a[1]) >= 2.5 else "boom_small", a[0], 0.0)
		"cast":   # a fireball leaves the staff
			play("fire_whoosh", at_id.call(0), -4.0)
		"reflect":
			play("ping", a[1], 0.0, 0.0, 0.1)
		"shield_hit":
			play("ping", a[1], -5.0, 0.0, 0.1)
		"shield_shatter":
			play("shatter", a[1], -1.0)
		"teleport":
			play("blink", a[1], -6.0)
			play("blink", a[2], -3.0, 0.06)
		"tp_blast":
			play("boom_small", a[0], -3.0)
		"freeze":
			play("ice", a[1], -2.0)
		"frost_nova":
			play("frost", a[1], -1.0)
		"poison":
			play("bubble", at_id.call(0), -12.0, 0.0, 0.15)
		"charm":
			play("chime", at_id.call(0), -4.0)
		"uncharm":
			play("chime", at_id.call(0), -10.0, 0.0, 0.0)
		"mastery_up", "level_up":
			play("levelup", at_id.call(0), -2.0 if int(a[0]) == net.my_id else -10.0, 0.0, 0.0)
		"gather":
			if int(a[2]) == 0:
				play("clack", a[1], -6.0)
				play("clack", a[1], -8.0, 0.12)
			else:
				play("fx scrape", a[1], -10.0)
		"stun_beam":
			play("fx zap", a[2], -2.0)
		"stun_burst":
			play("fx zap", a[0], 0.0)
		"golem_rise":
			play("fx slam", a[1], -6.0)
			play("fx scrape", a[1], -6.0, 0.2)
		"golem_slam":
			if a.size() > 2 and a[2]:
				play("fx slam", a[1], 0.0)
			else:
				play("bonk", a[1], -4.0, 0.0, 0.1)
		"titan_rise":
			play("fx slam", a[1], 2.0)
			play("thunder", a[1], -10.0)
		"meteor_warn":   # its whistle ends as it lands
			play("fall", a[0], -3.0, maxf(float(a[1]) * Config.DT - DUR.fall, 0.0))
		"meteor":
			play("boom", a[0], 3.0)
			play("fx slam", a[0], -2.0)
		"well":
			play("well", a[0], -3.0)
		"well_burst":
			play("boom_small", a[0], -1.0)
		"storm":
			play("fx crackle", a[0], -4.0)
			play("thunder", a[0], -12.0, 0.3)
		"spark":
			play("zap_small", a[1], -6.0, 0.0, 0.12)
		"drain":
			play("suck", a[1], -5.0)
		"drain_ally":
			play("chime", a[1], -10.0)
		"vault_door":
			play("fx scrape", WorldLayout.VAULT_DOOR, -2.0, 0.0, 0.0)
			play("fx slam", WorldLayout.VAULT_DOOR, -10.0, 0.5)


# ================================================================ making the sounds
static func _make(kind: String) -> AudioStreamWAV:
	var dur: float = DUR.get(kind, 0.3)
	var n := int(RATE * dur)
	var d := PackedFloat32Array()
	d.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("act_" + kind)
	if kind == "twang":   # a plucked string (Karplus-Strong) with a little thump of the limbs
		var period := int(RATE / 98.0)
		var buf := PackedFloat32Array()
		buf.resize(period)
		for i in period:
			buf[i] = rng.randf_range(-1.0, 1.0)
		var idx := 0
		for i in n:
			var t := float(i) / RATE
			var nxt := (idx + 1) % period
			var o := buf[idx]
			buf[idx] = 0.5 * (buf[idx] + buf[nxt]) * 0.994
			idx = nxt
			d[i] = o * 0.8 + sin(TAU * 70.0 * t) * exp(-t * 30.0) * 0.6
		return _finish(d)
	var pings := []   # the shatter's shards: [start, freq, size]
	if kind == "shatter" or kind == "frost":
		for k in 26:
			pings.append([rng.randf_range(0.0, dur * 0.55), rng.randf_range(2200.0, 7000.0), rng.randf_range(0.3, 1.0)])
	var f0: float = AIR.get(kind, [0.0, 0.0])[0]   # the air sounds' sweep: from, to (Hz)
	var f1: float = AIR.get(kind, [0.0, 0.0])[1]
	var low := 0.0
	var band := 0.0
	var lp := 0.0
	var lp2 := 0.0
	var ph := 0.0
	var ph2 := 0.0
	var ph3 := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / dur
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.08
		lp2 += (noise - lp2) * 0.02
		var v := 0.0
		match kind:
			"swish", "swish_heavy", "whump", "jab", "dash", "jump", "whizz", "fire_whoosh", "suck":
				# air: band-passed noise sweeping in pitch, swelling and fading
				var shape := sin(PI * u)
				var fc := f0 + (f1 - f0) * (u if kind == "whizz" or kind == "suck" else shape)
				var res := _svf(noise, fc, 0.45 if kind != "whump" else 0.7, low, band)
				low = res[0]
				band = res[1]
				var env := pow(shape, 1.4)
				if kind == "suck":
					env = pow(u, 2.0) * clampf((1.0 - u) * 12.0, 0.0, 1.0)
				if kind == "whizz":
					env = minf(u * 8.0, 1.0) * pow(1.0 - u, 1.5)
				v = band * env * 2.2
				if kind == "whump" or kind == "swish_heavy":
					v += sin(TAU * 70.0 * t) * env * 0.35 + low * env * 0.6
				if kind == "fire_whoosh":
					v += lp * env * 2.5 + (1.0 if rng.randf() < 0.004 else 0.0) * rng.randf_range(-1, 1) * env
			"slash":   # a blade biting: a burst, a ringing of metal, a thud under it
				v = noise * exp(-t * 90.0) * 0.8
				for pr in [[2310.0, 9.0], [3480.0, 12.0], [5120.0, 16.0], [6930.0, 21.0]]:
					v += sin(TAU * float(pr[0]) * t) * exp(-t * float(pr[1])) * 0.22
				v += lp * exp(-t * 30.0) * 1.4
			"bonk":   # wood on a body: a falling thump and a knock
				ph += (115.0 - 55.0 * minf(t / 0.08, 1.0)) / RATE
				v = sin(TAU * ph) * exp(-t * 14.0) + sin(TAU * 420.0 * t) * exp(-t * 35.0) * 0.5 + noise * exp(-t * 200.0) * 0.6
			"punch":
				ph += (95.0 - 45.0 * minf(t / 0.06, 1.0)) / RATE
				v = sin(TAU * ph) * exp(-t * 22.0) + lp * exp(-t * 40.0) * 1.2
			"thunk":   # an arrow sinking in
				ph += (190.0 - 70.0 * minf(t / 0.05, 1.0)) / RATE
				v = sin(TAU * ph) * exp(-t * 30.0) + sin(TAU * 680.0 * t) * exp(-t * 45.0) * 0.45 + noise * exp(-t * 300.0) * 0.5
			"clack":   # stone on stone
				var res := _svf(noise, 2600.0, 0.3, low, band)
				low = res[0]
				band = res[1]
				v = band * exp(-t * 45.0) * 1.6 + (sin(TAU * 1830.0 * t) + sin(TAU * 2710.0 * t)) * exp(-t * 55.0) * 0.4
			"creak":   # the bow bending: stick-slip clicks through a wooden resonance, quickening
				ph += (22.0 + 45.0 * u) / RATE
				var kick := 0.0
				if ph >= 1.0:
					ph -= 1.0
					kick = rng.randf_range(0.6, 1.0)
				var res := _svf(kick + noise * 0.02, 720.0 + 120.0 * u, 0.08, low, band)
				low = res[0]
				band = res[1]
				v = band * 3.0 * minf(u * 6.0, 1.0) * minf((1.0 - u) * 6.0, 1.0)
			"stretch":   # rubber pulled: a rising squeak
				ph += (300.0 + 240.0 * u + 18.0 * sin(t * 40.0)) / RATE
				v = (sin(TAU * ph) * 0.5 + (2.0 * fposmod(ph, 1.0) - 1.0) * 0.2) * sin(PI * u) * 0.8 + lp * sin(PI * u) * 0.6
			"snap":   # the band let go: a crack and a whip of air
				var res := _svf(noise, 3200.0 - 2000.0 * u, 0.5, low, band)
				low = res[0]
				band = res[1]
				v = (noise - lp) * exp(-t * 70.0) * 1.2 + band * pow(sin(PI * u), 2.0) * 1.2
			"cast", "cast_ice", "cast_dark", "cast_fire":
				var env := minf(u * 3.0, 1.0) * clampf((1.0 - u) * 4.0, 0.0, 1.0)
				if kind == "cast":   # arcane shimmer, rising
					for f in [660.0, 990.0, 1320.0]:
						v += sin(TAU * f * (1.0 + 0.4 * u) * t) * 0.25
					v *= 0.7 + 0.3 * sin(t * 50.0)
					var res := _svf(noise, 6000.0, 0.4, low, band)
					low = res[0]
					band = res[1]
					v += band * 0.25
				elif kind == "cast_ice":   # crystalline
					for f in [1800.0, 2700.0, 3900.0]:
						v += sin(TAU * f * t) * 0.18 * (0.6 + 0.4 * sin(t * 70.0 + f))
					v += (noise - lp) * 0.15
				elif kind == "cast_dark":   # the wand's: a lower warble
					ph += (220.0 * (1.0 + 0.06 * sin(TAU * 7.0 * t)) * (1.0 + 0.3 * u)) / RATE
					ph2 += (331.0 * (1.0 + 0.06 * sin(TAU * 7.0 * t + 1.0)) * (1.0 + 0.3 * u)) / RATE
					v = sin(TAU * ph) * 0.4 + sin(TAU * ph2) * 0.3 + lp * 0.4
				else:   # fire catching
					v = lp * 2.0 + lp2 * 2.0 + (rng.randf_range(-1, 1) if rng.randf() < 0.01 else 0.0)
				v *= env
			"boom", "boom_small":   # an explosion: a crack, a roar of noise closing down, a deep thump
				var k := 1.0 if kind == "boom" else 2.2
				var fc := 200.0 + 3000.0 * exp(-t * 6.0 * k)
				var res := _svf(noise, fc, 0.9, low, band)
				low = res[0]
				band = res[1]
				v = low * exp(-t * 3.0 * k) * 1.4 + sin(TAU * (55.0 - 20.0 * u) * t) * exp(-t * 5.0 * k) * 0.9 + noise * exp(-t * 120.0) * 0.6
			"shield_up":   # a shimmering swell
				for f in [400.0, 404.0, 600.0, 806.0]:
					v += sin(TAU * f * (1.0 + u) * t) * 0.22
				v *= sin(PI * u) * (0.75 + 0.25 * sin(t * 60.0))
			"ping":   # glass
				v = sin(TAU * 1900.0 * t) * exp(-t * 8.0) * 0.5 + sin(TAU * 2850.0 * t) * exp(-t * 11.0) * 0.35 + sin(TAU * 4300.0 * t) * exp(-t * 15.0) * 0.25
			"shatter", "frost":
				for pg in pings:
					var dt := t - float(pg[0])
					if dt >= 0.0 and dt < 0.3:
						v += sin(TAU * float(pg[1]) * dt) * exp(-dt * 25.0) * float(pg[2]) * 0.3
				v += (noise - lp) * exp(-t * (8.0 if kind == "shatter" else 4.0)) * 0.6
				if kind == "frost":
					v += sin(TAU * (4000.0 - 2000.0 * u) * t) * 0.15 * (1.0 - u)
			"blink":   # a zip down and a pop
				ph += (1600.0 - 1400.0 * u) / RATE
				v = sin(TAU * ph) * (1.0 - u) * 0.8 + noise * exp(-pow((t - dur * 0.8) * 60.0, 2.0)) * 0.6
			"ice":   # freezing solid: a crack and a ring
				v = noise * exp(-t * 60.0) + sin(TAU * 140.0 * t) * exp(-t * 12.0) * 0.4 + sin(TAU * 3100.0 * t) * exp(-t * 10.0) * 0.3
			"bubble":   # three blips
				var bt := fmod(t, 0.1)
				v = sin(TAU * (300.0 + 4000.0 * bt) * bt) * exp(-bt * 30.0) * 0.8
			"chime":
				for pr in [[880.0, 4.0], [1320.0, 5.0], [1760.0, 6.0], [2640.0, 8.0]]:
					v += sin(TAU * float(pr[0]) * t) * exp(-t * float(pr[1])) * 0.25
			"levelup":   # a rising arpeggio of bells
				var notes := [523.25, 659.25, 783.99, 1046.5]
				for j in notes.size():
					var nt := t - j * 0.11
					if nt >= 0.0:
						var f: float = notes[j]
						v += (sin(TAU * f * nt) + sin(TAU * f * 2.0 * nt) * 0.3) * exp(-nt * (3.0 if j == 3 else 7.0)) * 0.3
			"fall":   # a meteor coming down: a falling whistle over a growing rumble
				ph += (1800.0 - 1300.0 * u) / RATE
				v = sin(TAU * ph) * 0.35 * u + lp2 * 3.0 * u * u
			"well":   # space bending: a deep warble and a rush pulled in
				ph += (60.0 * (1.0 - 0.3 * u) * (1.0 + 0.15 * sin(TAU * 4.0 * t))) / RATE
				ph2 += (91.0 * (1.0 - 0.3 * u)) / RATE
				v = (sin(TAU * ph) * 0.6 + sin(TAU * ph2) * 0.3 + lp * 1.5 * u) * minf(u * 5.0, 1.0) * minf((1.0 - u) * 5.0, 1.0)
			"land":   # feet hitting the ground: a thud and a little dirt
				ph += (80.0 - 35.0 * minf(t / 0.08, 1.0)) / RATE
				v = sin(TAU * ph) * exp(-t * 18.0) + lp * exp(-t * 25.0) * 0.9
			"step0", "step1":
				var fc := 1300.0 if kind == "step0" else 950.0
				var res := _svf(noise, fc, 0.6, low, band)
				low = res[0]
				band = res[1]
				v = band * exp(-t * 55.0) * 1.4 + sin(TAU * 70.0 * t) * exp(-t * 60.0) * 0.6
			"zap_small":   # a spark: a jittery buzz, crackling out
				ph3 += (1200.0 + rng.randf_range(-300.0, 300.0)) / RATE
				v = (2.0 * fposmod(ph3, 1.0) - 1.0) * exp(-t * 14.0) * (0.5 + 0.5 * float(rng.randf() < 0.6)) * 0.7 + (noise - lp) * exp(-t * 30.0) * 0.4
		d[i] = v
	return _finish(d)


## A state-variable filter step: x through a band-pass at fc (q: lower is sharper). -> [low, band]
static func _svf(x: float, fc: float, q: float, low: float, band: float) -> Array:
	var f := 2.0 * sin(PI * clampf(fc, 20.0, RATE * 0.24) / RATE)
	low += f * band
	var high := x - low - q * band
	band += f * high
	return [low, band]


## Even out the loudness (every sound peaks at the same level; Main and the callers set how loud each plays), with a
## few milliseconds' fade at each end so nothing clicks.
static func _finish(d: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0001
	for x in d:
		peak = maxf(peak, absf(x))
	var g := 0.85 / peak
	var fade := int(RATE * 0.004)
	for i in d.size():
		var e := 1.0
		if i < fade:
			e = float(i) / fade
		elif i > d.size() - fade:
			e = float(d.size() - i) / fade
		d[i] = d[i] * g * e
	return Synth._wav(d)
