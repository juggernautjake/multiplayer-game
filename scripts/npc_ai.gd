## The Duel Stone's challengers (v0.10.0): an NPC fighter's brain. It runs on the server and plays like a person: every
## tick it makes one PlayerInput (the same buttons, aim and spell a player sends), and the server steps the NPC's state
## with the shared simulation (Sim.step), so its moves, animations, costume, hits and syncing are a player's.
##
## Archetypes:
##   melee (sword, club):  close the distance; at its weapon's reach, circle-strafe and side-step, wait for an opening
##                         (the player recovering from a swing, or a lapse) and strike, chaining the combo; feint (step
##                         in and back out) to bait a swing; back off at low health;
##   ranged (bow, sling):  hold its ideal range (closer for the slingshot), kite away from anyone closing in, strafe
##                         between shots, and lead its shots (where the target will be, from the projectile's speed and
##                         the drop under gravity);
##   staff, wand (wizards; v0.12.0 rework, see the WIZARDS block below): only their weapon's level-1 spells, a
##                         real mana pool (the staff: the same costs and regen as a player, through Sim.step), a
##                         utility pick each time (situation, mana, its own per-spell cooldowns, a penalty for
##                         repeating itself, some chance), a visible wind-up before each cast and a pause after,
##                         archer-style aim error, backing off to let its mana come back.
## Everyone dodges: a dash sideways when a shot is about to hit or a big swing is winding up in reach, after a human
## reaction time (with some randomness; tiers: 0 easy, 1 medium, 2 hard).
class_name NpcAI
extends RefCounted

const REACT := [[22, 12], [14, 8], [8, 4]]   # [base ticks, random extra] before reacting, per difficulty
const AIM_ERR := [0.07, 0.035, 0.015]        # radians of aim error
# v0.11.0 archers and slingers were far too deadly: they aim where you STAND (no leading), with a real spread (more
# far away, more when you're running or dashing), draw less often, hold the full draw a moment first (a tell you can
# see), and stop shooting now and then to reposition. Better tiers aim tighter and shoot a little more often.
const SHOT_ERR := [0.1, 0.075, 0.055]        # radians, at 10 m, standing target
const SHOT_START := [0.02, 0.028, 0.036]     # chance a tick to start a draw when ready
const SHOT_HOLD := [32, 24, 16]              # ticks held at full draw before letting go
# v0.12.0 (Jacob): no dash-dodging at all at tier 1 (difficulty 0); it starts at tier 2 and grows at tier 3
const DODGE := [0.0, 0.6, 0.85]              # chance to dodge a threat it noticed
# v0.12.0 challengers learn to dash: area spells about to land on them (lightning, meteors, storm bolts, Thunderhorn's
# called lightning: their warning rings) and Thunderhorn's charge or rush coming down a line through them. Higher tiers
# see these more often (the same REACT delay first, plus SPELL_REACT for reading the warning), never always.
const SPELL_DODGE := [0.0, 0.4, 0.65]
const SPELL_REACT := [10, 6, 3]
var threat_kind := ""          # what _threat found: "shot", "draw", "melee", "spell", "charge"
var dodges := 0                # dashes made to dodge (tests)

var id := 0
var owner := 0              # the player who pressed the stone (0 for a corrupted minion: it fights everyone)
var reach := 45.0           # v0.12.3: how far off it looks for a player (minions rise far from the arena: Net.MINION_REACH)
var weapon := Weapons.SWORD
var archetype := "melee"
var difficulty := 1
var rng := RandomNumberGenerator.new()
var seq := 0
var _strafe := 1.0
var _strafe_t := 0
var _react := 0             # ticks until it can react to a threat again
var _threat_seen := -1      # tick it noticed the current threat
var _feint := 0             # ticks of a feint left
var _combo := 0             # presses left in a combo
var _hold := 0              # ticks it keeps a button held (drawing, the shield)
var _full_t := 0            # ticks held at full draw
var _pause := 0             # ticks repositioning without shooting
var _shot_err := 0.0        # this shot's aim error (picked when the draw starts)
var _shot_err_p := 0.0
var _plan_spell := -1
var _cast_t := 0
var _retreat := 0
## v0.12.9 the Duel Stone's corrupted minions (Net.spawn_minions sets it; Jacob: "very aggressive. They can still juke
## and dodge, but they should not get skittish whenever they get low health. They should continue trying to fight"):
## no backing off at low health (challengers still do), melee strikes and combos far more often with fewer feints and
## closing in at a sprint, archers and slingers start draws ~2.5x as readily, rarely pause after a shot and only kite
## when you're right on them (they keep shooting while they do), wizards pause half as long between casts, rest later
## and stay at their range when low on mana. Their dodges, dashes, shields, feints and the archers' full-draw tell
## are unchanged.
var aggressive := false
# v0.12.0 the wand's Fog: lost inside an enemy's fog it's confused: "thrash" (attacks random spots round it) or
# "stumble" (wanders, the heading jerking about, until it's out), picked again every FOG_ROLL ticks, still confused
# FOG_RECOVER ticks after getting out. Outside, it can't target anyone hidden in one and steers round the cloud.
const FOG_ROLL := 120
const FOG_RECOVER := 60
var fog_mode := ""
var _fog_t := 0
var _fog_roll := 0
var _wander := 0.0
var _thrash_at := Vector3.ZERO

# ================================================================ WIZARDS (v0.12.0)
# Jacob: NPC wizards were too accurate, never ran out of mana and spammed one spell. Now:
#   - kit: only the level-1 spells of their weapon (KIT_LEVEL): the staff's Lightning, Fireball and Shield; the wand's
#     Spark Beam, Golem, Teleport and Stun. The basic attack (falling back on it) is Fireball / Spark Beam.
#   - mana: the staff's mana is the player's (Sim.step charges it and brings it back at 12 a second; nothing tops it
#     up). Below LOW_MANA it stops casting, backs off and strafes until it has REST_MANA again. The wand has no mana:
#     its recharges are the player's too.
#   - choice (_utility): each ready spell is scored for the situation (range, the target moving or standing, others
#     near the target, shots coming in -> Shield, its own health low, the mana it would leave), times REPEAT_K per
#     time it's among the last REPEAT_WINDOW casts, zero if the last MAX_SAME were all that spell, times a random
#     0.75-1.25; the best wins. Each spell also has its own AI cooldown (SPELL_CD) on top of the game's.
#   - aim: at the target's CURRENT position (no lead; the aim follows it with a lag, TRACK), with a random error
#     picked at the start of the wind-up, like
#     the archers: WIZ_ERR radians at 10 m, growing with distance (0.6 + d / 25) and the target's speed (up to x2.5),
#     x1.8 if they're dashing; better tiers aim a little tighter.
#   - tells: WINDUP[tier] ticks standing still facing the target (an "npc_tell" glow in the spell's colour) before the
#     button goes down, then the cast itself, then a PAUSE[tier] (random range) before it starts another.
const KIT_LEVEL := 1
const MAX_GOLEMS := 3         # a challenger / minion wand wizard's own golems alive at once (Jacob)
const LOW_MANA := 22          # mana (not fifths): below this it rests
const REST_MANA := 55
const REPEAT_WINDOW := 4
const REPEAT_K := 0.5
const MAX_SAME := 3
const WIZ_ERR := [0.09, 0.07, 0.055]
const WINDUP := [34, 26, 20]
const PAUSE := [[50, 90], [35, 70], [25, 55]]
const SPELL_CD := { "Lightning": 100, "Fireball": 40, "Shield": 150, "Spark Beam": 20, "Golem": 300, "Teleport": 120, "Stun": 180 }
var casts: Array = []          # every spell it has cast (names), oldest first (for tests and the repetition penalty)
var _resting := false
var _wind := 0                 # ticks of wind-up left
var _wind_spell := -1
var _gap := 0                  # ticks of pause before the next wind-up
var _ai_cd := {}               # spell name -> ticks left
var _err := 0.0
var _err_r := 0.0
var _track := Vector3.INF      # where it's aiming: follows the target's current position with a lag (TRACK a tick)
const TRACK := 0.08


func _init(npc_id: int, presser: int, w: int, diff := 1, seed_v := 0) -> void:
	id = npc_id
	owner = presser
	weapon = w
	difficulty = clampi(diff, 0, 2)
	rng.seed = seed_v if seed_v != 0 else randi()
	archetype = "melee" if w in [Weapons.SWORD, Weapons.CLUB, Weapons.FISTS] else ("ranged" if w in [Weapons.BOW, Weapons.SLING] else ("staff" if w == Weapons.STAFF else "wand"))


## The ideal fighting distance for its weapon.
func ideal_range() -> float:
	match weapon:
		Weapons.SWORD:
			return 2.0
		Weapons.CLUB:
			return 1.9
		Weapons.FISTS:
			return 1.3
		Weapons.BOW:
			return 12.0
		Weapons.SLING:
			return 8.0
		Weapons.STAFF:
			return 11.0
		Weapons.WAND:
			return 9.0
	return 3.0


## One tick of thinking: the input to step its state with. `net` gives the world (players, projectiles, golems).
func think(net: Net, me: Net.ServerPlayer) -> Sim.PlayerInput:
	seq += 1
	var s := me.state
	if not net.fogs.is_empty() or _fog_t > 0:
		if Fog.lost(id, s.pos, net.fogs, net.server_tick, net.fog_pvp()):
			_fog_t = FOG_RECOVER
		elif _fog_t > 0:
			_fog_t -= 1
		if _fog_t > 0 and s.dead == 0:
			return _confused(net, me)
	fog_mode = ""
	var tgt: Net.ServerPlayer = _pick_target(net, me)
	var face := s.yaw
	var move := Vector2.ZERO
	var buttons := 0
	var aim_point := s.pos + Vector3(-sin(s.yaw), 1.0, -cos(s.yaw)) * 6.0
	var pitch := 0.0
	var spell := s.spell
	if s.dead == 0 and tgt == null and Net.side_of(me) == Net.Side.ALLY and net.players.has(owner):
		# v0.12.6 a friendly unit with nobody to fight keeps near whoever spawned it (sprinting if far behind)
		var op: Vector3 = net.players[owner].state.pos
		var off := Vector2(op.x - s.pos.x, op.z - s.pos.z)
		if off.length() > 4.5:
			var fy := atan2(-off.x, -off.y)
			var bt := Sim.Btn.FORWARD | (Sim.Btn.SPRINT if off.length() > 12.0 else 0)
			return Sim.PlayerInput.new(seq, bt, fy, 0.0, s.weapon, net.server_tick, fy, fy, s.spell, op)
	if s.dead > 0 or tgt == null:
		return Sim.PlayerInput.new(seq, 0, s.yaw, 0.0, s.weapon, net.server_tick, s.yaw, s.yaw, s.spell, aim_point)
	var tp: Vector3 = tgt.state.pos
	var to := Vector2(tp.x - s.pos.x, tp.z - s.pos.z)
	var dist := to.length()
	var dir := to / maxf(dist, 0.01)
	face = atan2(-dir.x, -dir.y)
	var side := Vector2(-dir.y, dir.x)   # to its left
	_strafe_t -= 1
	if _strafe_t <= 0:   # change the side it circles to now and then, not on a beat
		_strafe = -_strafe if rng.randf() < 0.55 else _strafe
		_strafe_t = rng.randi_range(40, 110)
	var low := float(s.hp) / float(Sim.MAX_HP) < 0.3 and not aggressive   # (a minion fights on: v0.12.9)
	if low and _retreat <= 0 and rng.randf() < 0.01:
		_retreat = rng.randi_range(90, 160)
	_retreat -= 1
	# ---- threats: a shot about to hit, a big swing winding up in reach
	_react -= 1
	var threat := _threat(net, me, tgt, dist)
	if threat != Vector2.ZERO:
		if _threat_seen < 0:
			_threat_seen = net.server_tick
		var r: Array = REACT[difficulty]
		var noticed := net.server_tick - _threat_seen >= int(r[0]) + rng.randi_range(0, int(r[1]))
		if threat_kind == "spell" or threat_kind == "charge":
			noticed = net.server_tick - _threat_seen >= int(r[0]) / 2 + SPELL_REACT[difficulty] + rng.randi_range(0, int(r[1]))
		if noticed and _react <= 0 and (threat_kind == "spell" or threat_kind == "charge"):
			_react = 30
			if rng.randf() < SPELL_DODGE[difficulty] and s.dash_cd == 0:
				buttons |= Sim.Btn.DASH
				move = threat
				dodges += 1
		elif noticed and _react <= 0:
			_react = 30
			var sh := Weapons.idx(Weapons.STAFF, "Shield")
			if archetype == "staff" and s.atk == 0 and int(_ai_cd.get("Shield", 0)) == 0 and not _run_of("Shield") \
					and s.mana >= (int(Weapons.spell(Weapons.STAFF, sh).cost) + 8) * 5 and rng.randf() < 0.75:
				_hold = 40   # the shield up (dropping a spell it was winding up)
				_wind = 0
				_cast_t = 0
				_note_cast("Shield")
			elif rng.randf() < DODGE[difficulty] and s.dash_cd == 0:
				buttons |= Sim.Btn.DASH
				move = threat
				dodges += 1
	else:
		_threat_seen = -1
	# ---- how it moves and fights
	match archetype:
		"melee":
			var reach := ideal_range()
			if _retreat > 0:
				move += -dir + side * _strafe * 0.6
			elif _feint > 0:
				_feint -= 1
				move += dir if _feint > 12 else -dir
			elif dist > reach + 1.2:
				move += dir + side * _strafe * 0.25
				if dist > (4.0 if aggressive else 7.0):
					buttons |= Sim.Btn.SPRINT
			else:
				move += side * _strafe * 0.8 + dir * clampf(dist - reach, -1.0, 1.0)
				# strike when they're recovering (punish), or now and then; feint sometimes instead
				var opening: bool = tgt.state.atk_cd > 0 or (tgt.state.atk > 0 and tgt.state.charge == 0)
				var chance := 0.06 if opening else 0.018 + 0.01 * difficulty
				if aggressive:
					chance = 0.12 if opening else 0.05 + 0.01 * difficulty
				if _combo <= 0 and rng.randf() < chance:
					if rng.randf() < (0.08 if aggressive else 0.15):
						_feint = 24
					else:
						_combo = rng.randi_range(2, 4) if aggressive else rng.randi_range(1, 3)
				if _combo > 0 and dist <= reach + 0.6 and seq % 12 == 0:
					buttons |= Sim.Btn.ATTACK
					_combo -= 1
		"ranged":
			var want := ideal_range()
			if _retreat > 0 or dist < want - (6.0 if aggressive else 3.0):
				move += -dir + side * _strafe * 0.5   # kite (a minion only when you're on top of it)
			elif dist > want + (2.0 if aggressive else 4.0):
				move += dir
			else:
				move += side * _strafe
			var aim := _lead(s, tgt, Weapons.shot(s.weapon, int(Weapons.get_data(s.weapon).draw))[0], float(Weapons.get_data(s.weapon).gravity), 0.0)
			face = aim[0] + _shot_err
			pitch = aim[1] + _shot_err_p
			aim_point = aim[2]
			if _pause > 0:
				_pause -= 1
				move += side * _strafe
			elif dist < 34.0:
				var full := s.charge >= int(Weapons.get_data(s.weapon).draw)
				if s.charge > 0 and not full:
					buttons |= Sim.Btn.ATTACK   # keep drawing
				elif full and _full_t < SHOT_HOLD[difficulty]:
					_full_t += 1
					buttons |= Sim.Btn.ATTACK   # holding the full draw: the tell
				elif s.charge == 0 and s.atk_cd == 0 and rng.randf() < SHOT_START[difficulty] * (2.5 if aggressive else 1.0):
					buttons |= Sim.Btn.ATTACK   # start a draw, with this shot's error
					_full_t = 0
					var tv := Vector2(tgt.state.vel.x, tgt.state.vel.z).length()
					var spread: float = SHOT_ERR[difficulty] * (0.6 + dist / 25.0) * (1.0 + clampf(tv / 6.0, 0.0, 1.5)) * (1.8 if tgt.state.dash_ticks > 0 else 1.0)
					_shot_err = rng.randfn(0.0, spread)
					_shot_err_p = rng.randfn(0.0, spread * 0.5)
				elif full:   # let go: the shot leaves; then maybe a pause to reposition
					if rng.randf() < (0.12 if aggressive else 0.4):
						_pause = rng.randi_range(15, 35) if aggressive else rng.randi_range(40, 90)
		"staff", "wand":
			var want := ideal_range()
			var mana := s.mana / 5
			if archetype == "staff":
				if mana < (LOW_MANA / 2 if aggressive else LOW_MANA):
					_resting = true
				elif mana >= (REST_MANA - 20 if aggressive else REST_MANA):
					_resting = false
			for k in _ai_cd.keys():
				_ai_cd[k] = maxi(int(_ai_cd[k]) - 1, 0)
			if _resting and not aggressive:
				want += 5.0   # out of mana: keep away and let it come back
			if _wind > 0:
				pass   # winding up: planted, facing them (the tell)
			elif _retreat > 0 or dist < want - 3.0:
				move += -dir + side * _strafe * 0.5
			elif dist > want + 5.0:
				move += dir
			else:
				move += side * _strafe * 0.8
			if _hold > 0:
				_hold -= 1
				spell = Weapons.idx(Weapons.STAFF, "Shield")
				buttons |= Sim.Btn.ATTACK
			elif _wind > 0:
				_wind -= 1
				spell = _wind_spell
				if _wind == 0:
					buttons |= Sim.Btn.ATTACK   # release
					_cast_t = 3
			elif _cast_t > 0:
				_cast_t -= 1
				spell = _wind_spell
				buttons |= Sim.Btn.ATTACK
				if _cast_t == 0:
					_gap = rng.randi_range(int(PAUSE[difficulty][0]), int(PAUSE[difficulty][1]))
					if aggressive:
						_gap /= 2
			elif _gap > 0:
				_gap -= 1
			elif not _resting and s.atk == 0 and s.atk_cd == 0:
				var pick := _utility(s, dist, tgt, net)
				if pick >= 0:
					_wind_spell = pick
					_wind = WINDUP[difficulty]
					spell = pick
					var tv := Vector2(tgt.state.vel.x, tgt.state.vel.z).length()
					var spread: float = WIZ_ERR[difficulty] * (0.6 + dist / 25.0) * (1.0 + clampf(tv / 4.0, 0.0, 1.5)) * (1.8 if tgt.state.dash_ticks > 0 else 1.0)
					_err = rng.randfn(0.0, spread)
					_err_r = rng.randfn(0.0, spread * 0.6)
					var nm := str(Weapons.spell(s.weapon, pick).name)
					_note_cast(nm)
					net._fx("npc_tell", [id, nm, _wind])
			if _hold <= 0 and _wind_spell >= 0 and (_wind > 0 or _cast_t > 0):
				spell = _wind_spell
			var sp := Weapons.spell(s.weapon, spell)
			# aim at where they stand now (no lead), off by this cast's error: turned round the caster and short/long
			# the aim follows them with a human lag (a strafing target slips off it; a still one doesn't)
			if _track == Vector3.INF or _track.distance_to(tp) > 6.0:
				_track = tp
			_track = _track.lerp(tp, TRACK)
			var at := _track + Vector3(0, 1.0, 0)
			var rel := at - s.pos
			var flat := Vector2(rel.x, rel.z).rotated(-_err) * (1.0 + _err_r)
			aim_point = s.pos + Vector3(flat.x, rel.y, flat.y)
			if str(sp.name) == "Lightning" or str(sp.name) == "Golem":
				aim_point.y = tp.y
			if str(sp.name) == "Teleport":   # away from them, out of their reach
				aim_point = s.pos + Vector3(-dir.x, 0, -dir.y) * 10.0 + Vector3(side.x, 0, side.y) * 4.0 * _strafe
			face = atan2(-(aim_point.x - s.pos.x), -(aim_point.z - s.pos.z))
	if not net.fogs.is_empty() and move.length() > 0.2:   # v0.12.0: round an enemy's fog, never into it
		move = Fog.steer(id, s.pos, move.normalized(), net.fogs, net.server_tick, net.fog_pvp())
	# the buttons for moving that way while facing the target (a person strafing with the mouse on them)
	if move.length() > 0.2:
		move = move.normalized()
		var fwd := Vector2(-sin(face), -cos(face))
		var rgt := Vector2(cos(face), -sin(face))
		var f := move.dot(fwd)
		var r := move.dot(rgt)
		if f > 0.35:
			buttons |= Sim.Btn.FORWARD
		elif f < -0.35:
			buttons |= Sim.Btn.BACK
		if r > 0.35:
			buttons |= Sim.Btn.RIGHT
		elif r < -0.35:
			buttons |= Sim.Btn.LEFT
	buttons |= Sim.Btn.FACE_CAM
	var err: float = AIM_ERR[difficulty] * rng.randfn(0.0, 1.0) if archetype == "melee" else 0.0
	return Sim.PlayerInput.new(seq, buttons, face, pitch, s.weapon, net.server_tick, face + err, face, spell, aim_point)


## v0.12.0 lost in an enemy's fog: thrash or stumble (see FOG_ROLL). No target: it can't see anyone.
func _confused(net: Net, me: Net.ServerPlayer) -> Sim.PlayerInput:
	var s := me.state
	_fog_roll -= 1
	if _fog_roll <= 0 or fog_mode == "":
		fog_mode = "thrash" if rng.randf() < 0.5 else "stumble"
		_fog_roll = FOG_ROLL
		_wander = rng.randf() * TAU
		_thrash_at = s.pos
	var buttons := Sim.Btn.FACE_CAM
	var face := s.yaw
	var aim := s.pos + Vector3(-sin(face), 1.0, -cos(face)) * 4.0
	var spell := s.spell
	if fog_mode == "thrash":
		if seq % 30 == 0:   # a new random spot round it to swing, shoot or cast at
			var a := rng.randf() * TAU
			_thrash_at = s.pos + Vector3(cos(a), 0, sin(a)) * rng.randf_range(1.0, 4.0)
		var to := _thrash_at - s.pos
		face = atan2(-to.x, -to.z) if Vector2(to.x, to.z).length() > 0.1 else s.yaw
		aim = _thrash_at + Vector3(0, 1.0, 0)
		if seq % 30 < 22:
			buttons |= Sim.Btn.ATTACK   # (a bow draws, then lets go when the button comes up)
		if Weapons.is_magic(s.weapon):
			spell = _basic_spell(s.weapon)
	else:
		if rng.randf() < 0.05:
			_wander += rng.randf_range(-1.6, 1.6)
		face = _wander
		buttons |= Sim.Btn.FORWARD
	return Sim.PlayerInput.new(seq, buttons, face, 0.0, s.weapon, net.server_tick, face, face, spell, aim)


## The spell a wizard falls back on: the wand's Spark Beam, the staff's Fireball.
static func _basic_spell(w: int) -> int:
	return Weapons.idx(w, "Spark Beam") if w == Weapons.WAND else Weapons.idx(w, "Fireball")


## The one it fights: whoever pressed the stone, while they're alive and near; else the nearest living player.
## v0.12.0: never anyone hidden from it in a fog.
func _pick_target(net: Net, me: Net.ServerPlayer):
	var best = null
	var best_d := reach
	var fogged := not net.fogs.is_empty()
	var pvp := net.fog_pvp() if fogged else {}
	for q: Net.ServerPlayer in net.players.values():
		if not net.npc_foe(me, q):   # v0.12.6: by sides (hostile, friendly, neutral), not just "every player"
			continue
		if fogged and not Fog.can_see(id, me.state.pos, q.id, q.state.pos, net.fogs, net.server_tick, pvp):
			continue
		var d := q.state.pos.distance_to(me.state.pos) - (6.0 if q.id == owner else 0.0)
		if d < best_d:
			best_d = d
			best = q
	# v0.12.0: a players' golem in its face (or one that just hit it) is dealt with first
	var gbest: Golems.G = null
	var gd := best_d if best != null else reach
	for g: Golems.G in net.golems.list.values():
		if g.state == Golems.State.DIE or g.state == Golems.State.RISE or g.owner == me.id:
			continue
		if net.players.has(g.owner) and not net.foe_side(me, net.players[g.owner]):
			continue
		if fogged and not Fog.can_see(id, me.state.pos, g.owner, g.pos, net.fogs, net.server_tick, pvp):
			continue
		var d := g.pos.distance_to(me.state.pos)
		var hit_me := net.golems.harmed(me.id, g.owner, 120) and d < 8.0
		if (d < 4.0 or hit_me) and d - (3.0 if hit_me else 0.0) < gd:
			gd = d
			gbest = g
	if gbest != null:
		if _golem_proxy == null:
			_golem_proxy = Net.ServerPlayer.new()
			_golem_proxy.state = Sim.PlayerState.new()
		_golem_proxy.id = -1000 - gbest.id
		_golem_proxy.state.pos = gbest.pos
		_golem_proxy.state.vel = Vector3.ZERO
		return _golem_proxy
	# v0.12.6: a friendly unit fights Thunderhorn too (at his flank), when nothing nearer needs it
	if net.boss != null and Net.side_of(me) == Net.Side.ALLY and net.boss.state != Boss.S.ENTER and net.boss.state != Boss.S.DEATH:
		var bp: Vector3 = net.boss.pos
		var bd := bp.distance_to(me.state.pos) - 2.0
		if bd < reach and (best == null or bd < best_d):
			if _boss_proxy == null:
				_boss_proxy = Net.ServerPlayer.new()
				_boss_proxy.state = Sim.PlayerState.new()
			_boss_proxy.id = Boss.ID
			_boss_proxy.state.pos = bp + (me.state.pos - bp).normalized() * 2.2
			_boss_proxy.state.vel = Vector3.ZERO
			return _boss_proxy
	return best


var _boss_proxy: Net.ServerPlayer = null


var _golem_proxy: Net.ServerPlayer = null   # a golem it fights, dressed as a player for the rest of its brain


## A threat to dodge, as the way to dash (sideways to it), or zero: a shot that will pass within a metre in the next
## half second, or the target's melee swing winding up while it's in reach.
func _threat(net: Net, me: Net.ServerPlayer, tgt: Net.ServerPlayer, dist: float) -> Vector2:
	var s := me.state
	threat_kind = ""
	# v0.12.0: Thunderhorn winding up or running a charge / rush down a line through it
	var bs = net.boss
	if bs != null and bs.state in [Boss.S.CHARGE_WIND, Boss.S.CHARGE, Boss.S.RUSH]:
		var along: Vector2 = bs.charge_dir if bs.state != Boss.S.CHARGE_WIND else Vector2(-sin(bs.yaw), -cos(bs.yaw))
		var rel := Vector2(s.pos.x - bs.pos.x, s.pos.z - bs.pos.z)
		var ahead := rel.dot(along)
		var off := rel.dot(Vector2(-along.y, along.x))
		if ahead > 0.0 and ahead < 28.0 and absf(off) < Boss.RADIUS + 1.6:
			threat_kind = "charge"
			var out := Vector2(-along.y, along.x) * (1.0 if off >= 0.0 else -1.0)
			return out
	# v0.12.0: an area spell's warning ring under it (lightning, a meteor, a storm bolt, his called lightning)
	for e in net.pending_spells:
		var kind := str(e[1])
		if not (kind in ["lightning", "meteor", "storm_bolt", "boss_strike"]) or int(e[3]) == me.id:
			continue
		if net.players.has(int(e[3])) and net.players[int(e[3])].npc:
			continue   # another challenger's: it can't hurt it
		var r := 3.0
		if kind == "meteor":
			r = float(Weapons.spell_named(Weapons.STAFF, "Meteor").radius)
		elif kind == "storm_bolt":
			r = float(Weapons.spell_named(Weapons.STAFF, "Arcane Storm").radius)
		var at: Vector3 = e[2]
		var away := Vector2(s.pos.x - at.x, s.pos.z - at.z)
		if away.length() < r + 0.8 and int(e[0]) - net.server_tick > 3:
			threat_kind = "spell"
			return away.normalized() if away.length() > 0.2 else Vector2(1, 0)
	for pr: Net.Proj in net.projectiles.values():
		if pr.owner == me.id:
			continue
		var n := net.server_tick - pr.tick0
		var p := Weapons.proj_pos(pr.pos0, pr.vel0, pr.g, n)
		var v := Weapons.proj_vel(pr.vel0, pr.g, n)
		var rel := s.pos + Vector3(0, 1.0, 0) - p
		var t := clampf(rel.dot(v) / maxf(v.length_squared(), 1e-4), 0.0, 0.5)
		if (p + v * t).distance_to(s.pos + Vector3(0, 1.0, 0)) < 1.1:
			threat_kind = "shot"
			var flat := Vector2(v.x, v.z).normalized()
			return Vector2(-flat.y, flat.x) * (1.0 if rng.randf() < 0.5 else -1.0)
	# v0.12.0: a bow or slingshot drawn at it, well into the draw: a wizard sees it coming and can get the shield up
	if archetype == "staff" and Weapons.is_ranged(tgt.state.weapon) and tgt.state.charge >= 20 and dist < 30.0:
		var to_me := Vector2(s.pos.x - tgt.state.pos.x, s.pos.z - tgt.state.pos.z).normalized()
		if Vector2(-sin(tgt.state.yaw), -cos(tgt.state.yaw)).dot(to_me) > 0.9:
			threat_kind = "draw"
			return Vector2(-to_me.y, to_me.x) * (1.0 if rng.randf() < 0.5 else -1.0)
	if Weapons.is_melee(tgt.state.weapon) and tgt.state.atk > 0:
		var mv := Weapons.move(tgt.state.weapon, tgt.state.combo)
		var winding := tgt.state.atk > int(mv.swing) - int(mv.windup)
		if winding and dist < float(mv.range) + 0.8:
			threat_kind = "melee"
			var away := Vector2(s.pos.x - tgt.state.pos.x, s.pos.z - tgt.state.pos.z).normalized()
			return (away + Vector2(-away.y, away.x) * _strafe).normalized()
	return Vector2.ZERO


## Lead a shot: aim where the target will be when it arrives (its speed and gravity), on the low arc.
## -> [yaw, pitch, the point]
func _lead(s: Sim.PlayerState, tgt: Net.ServerPlayer, speed: float, g: float, lead := 1.0) -> Array:
	var muzzle := s.pos + Vector3(0, 1.45, 0)
	var at: Vector3 = tgt.state.pos + Vector3(0, 1.1, 0)
	for i in 3:   # refine: time of flight -> where they'll be -> time of flight
		var tof := muzzle.distance_to(at) / maxf(speed, 1.0)
		at = tgt.state.pos + Vector3(0, 1.1, 0) + Vector3(tgt.state.vel.x, 0, tgt.state.vel.z) * tof * lead
	var d := at - muzzle
	var dx := Vector2(d.x, d.z).length()
	var yaw := atan2(-d.x, -d.z)
	var pitch := 0.0
	if g > 0.0 and dx > 0.1:
		var v2 := speed * speed
		var disc := v2 * v2 - g * (g * dx * dx + 2.0 * d.y * v2)
		pitch = atan((v2 - sqrt(maxf(disc, 0.0))) / (g * dx))
	else:
		pitch = atan2(d.y, dx)
	return [yaw, pitch, at]


## v0.12.0: the spells it may use: its weapon's level-1 spells.
static func kit(w: int) -> Array:
	var out := []
	var sp: Array = Weapons.get_data(w).spells
	for i in sp.size():
		if int(sp[i].get("level", 1)) <= KIT_LEVEL:
			out.append(i)
	return out


## Were the last MAX_SAME casts all this spell?
func _run_of(nm: String) -> bool:
	if casts.size() < MAX_SAME:
		return false
	for k in range(casts.size() - MAX_SAME, casts.size()):
		if casts[k] != nm:
			return false
	return true


func _note_cast(nm: String) -> void:
	casts.append(nm)
	if casts.size() > 200:
		casts.pop_front()
	_ai_cd[nm] = int(SPELL_CD.get(nm, 60))


## Is a spell ready (the game's recharge or mana, and its own AI cooldown)?
func _ready_to(s: Sim.PlayerState, i: int) -> bool:
	var sp := Weapons.spell(s.weapon, i)
	if int(_ai_cd.get(str(sp.name), 0)) > 0:
		return false
	if Weapons.get_data(s.weapon).get("uses", "mana") == "recharge":
		return s.recharge[i] == 0
	return s.mana >= int(sp.cost) * 5


## The best spell for now, or -1 (see the WIZARDS block): the highest _score.
func _utility(s: Sim.PlayerState, dist: float, tgt, net: Net) -> int:
	var best := -1
	var best_v := 0.0
	for i in kit(s.weapon):
		if not _ready_to(s, i):
			continue
		var v := _score(s, i, dist, tgt, false, net)
		if v > best_v:
			best_v = v
			best = i
	return best


## How good spell i is right now (0 = not at all). threat: shots are coming at it.
func _score(s: Sim.PlayerState, i: int, dist: float, tgt, threat: bool, net: Net) -> float:
	var sp := Weapons.spell(s.weapon, i)
	var nm := str(sp.name)
	var tv := Vector2(tgt.state.vel.x, tgt.state.vel.z).length() if tgt != null else 0.0
	var low_hp := float(s.hp) / float(Sim.MAX_HP) < 0.35
	var crowd := 0
	if tgt != null:
		for q: Net.ServerPlayer in net.players.values():
			if q != tgt and not q.npc and q.state.dead == 0 and q.state.pos.distance_to(tgt.state.pos) < 6.0:
				crowd += 1
	var v := 0.0
	match nm:
		"Lightning":
			v = 1.0 + (0.6 if tv < 2.0 else 0.0) + 0.5 * crowd - (0.6 if dist < 5.0 else 0.0)
			if dist > float(sp.range):
				v = 0.0
		"Fireball":
			v = 1.1 + (0.4 if dist > 5.0 and dist < 20.0 else 0.0) - (0.3 if tv > 5.0 else 0.0) + 0.3 * crowd
		"Shield":
			v = (2.5 if threat else 0.0) + (0.6 if low_hp and dist < 8.0 else 0.0)
		"Spark Beam":
			v = 1.0 if dist <= float(sp.range) - 2.0 else 0.0
		"Golem":
			var mine := 0
			for g: Golems.G in net.golems.list.values():
				if g.owner == id and g.state != Golems.State.DIE:
					mine += 1
			if dist < 22.0 and mine < MAX_GOLEMS:   # never more than MAX_GOLEMS of its own at once
				v = (1.3 if mine < 2 else 0.4) + (0.4 if low_hp else 0.0)
		"Teleport":
			v = 2.6 if dist < 4.0 else (1.4 if low_hp and dist < 8.0 else 0.0)
		"Stun":
			var busy: bool = tgt != null and (tgt.state.atk > 0 or tgt.state.charge > 0)
			if dist < float(sp.range) - 4.0:
				v = 0.9 + (0.7 if tv > 4.0 else 0.0) + (0.5 if busy else 0.0)
	if v <= 0.0:
		return 0.0
	# the mana it would leave (the staff)
	if Weapons.get_data(s.weapon).get("uses", "mana") == "mana" and int(sp.cost) > 0:
		if s.mana / 5 - int(sp.cost) < 10:
			v *= 0.6
	# repeating itself: never more than MAX_SAME in a row, less likely the more it's among the last few
	if _run_of(nm):
		return 0.0
	var same := 0
	for k in range(maxi(casts.size() - REPEAT_WINDOW, 0), casts.size()):
		if casts[k] == nm:
			same += 1
	v *= pow(REPEAT_K, same)
	return v * rng.randf_range(0.75, 1.25)
