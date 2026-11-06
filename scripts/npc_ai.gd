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
##   staff (wizard):       keep its distance; raise the shield when shots are coming; frost nova anyone too close;
##                         lightning, fireballs (led) and, at higher levels, meteors and the arcane storm;
##   wand (wizard):        summon golems, stun then follow up (earth spikes, the gravity well), teleport away when
##                         someone gets into melee range.
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
const DODGE := [0.35, 0.6, 0.85]             # chance to dodge a threat it noticed

var id := 0
var owner := 0              # the player who pressed the stone
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
	var tgt: Net.ServerPlayer = _pick_target(net, me)
	var face := s.yaw
	var move := Vector2.ZERO
	var buttons := 0
	var aim_point := s.pos + Vector3(-sin(s.yaw), 1.0, -cos(s.yaw)) * 6.0
	var pitch := 0.0
	var spell := s.spell
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
	var low := float(s.hp) / float(Sim.MAX_HP) < 0.3
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
		if noticed and _react <= 0:
			_react = 30
			if archetype == "staff" and s.mana > 60 and rng.randf() < 0.7:
				_hold = 40   # the shield up
				_plan_spell = 2
			elif rng.randf() < DODGE[difficulty] and s.dash_cd == 0:
				buttons |= Sim.Btn.DASH
				move = threat
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
				if dist > 7.0:
					buttons |= Sim.Btn.SPRINT
			else:
				move += side * _strafe * 0.8 + dir * clampf(dist - reach, -1.0, 1.0)
				# strike when they're recovering (punish), or now and then; feint sometimes instead
				var opening: bool = tgt.state.atk_cd > 0 or (tgt.state.atk > 0 and tgt.state.charge == 0)
				var chance := 0.06 if opening else 0.018 + 0.01 * difficulty
				if _combo <= 0 and rng.randf() < chance:
					if rng.randf() < 0.15:
						_feint = 24
					else:
						_combo = rng.randi_range(1, 3)
				if _combo > 0 and dist <= reach + 0.6 and seq % 12 == 0:
					buttons |= Sim.Btn.ATTACK
					_combo -= 1
		"ranged":
			var want := ideal_range()
			if _retreat > 0 or dist < want - 3.0:
				move += -dir + side * _strafe * 0.5   # kite
			elif dist > want + 4.0:
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
				elif s.charge == 0 and s.atk_cd == 0 and rng.randf() < SHOT_START[difficulty]:
					buttons |= Sim.Btn.ATTACK   # start a draw, with this shot's error
					_full_t = 0
					var tv := Vector2(tgt.state.vel.x, tgt.state.vel.z).length()
					var spread: float = SHOT_ERR[difficulty] * (0.6 + dist / 25.0) * (1.0 + clampf(tv / 6.0, 0.0, 1.5)) * (1.8 if tgt.state.dash_ticks > 0 else 1.0)
					_shot_err = rng.randfn(0.0, spread)
					_shot_err_p = rng.randfn(0.0, spread * 0.5)
				elif full:   # let go: the shot leaves; then maybe a pause to reposition
					if rng.randf() < 0.4:
						_pause = rng.randi_range(40, 90)
		"staff", "wand":
			var want := ideal_range()
			if _retreat > 0 or dist < want - 3.0:
				move += -dir + side * _strafe * 0.5
			elif dist > want + 5.0:
				move += dir
			else:
				move += side * _strafe * 0.8
			var lv := s.staff_lvl if archetype == "staff" else s.wand_lvl
			if _hold > 0:
				_hold -= 1
				spell = 2
				buttons |= Sim.Btn.ATTACK
				if _hold == 0:
					_plan_spell = -1
			else:
				# a spell in mind until it's cast (re-thought now and then), picked for the distance and what's ready
				if _plan_spell < 0 or _plan_spell == 2 or rng.randf() < 0.01:
					_plan_spell = _pick_spell(s, archetype, lv, dist)
				if _plan_spell >= 0:
					spell = _plan_spell
					if s.spell == _plan_spell and s.atk == 0 and s.atk_cd == 0 and rng.randf() < 0.1:
						buttons |= Sim.Btn.ATTACK
						_cast_t = 4
						_plan_spell = -1
			if _cast_t > 0:
				_cast_t -= 1
				buttons |= Sim.Btn.ATTACK
			var sp := Weapons.spell(s.weapon, spell)
			var speed := float(sp.get("speed", 0.0))
			if speed > 0.0:
				aim_point = _lead(s, tgt, speed, float(sp.get("gravity", 0.0)))[2]
			else:
				aim_point = tp + Vector3(tgt.state.vel.x, 0, tgt.state.vel.z) * 0.4
			if str(sp.name) == "Teleport":   # away from them, out of their reach
				aim_point = s.pos + Vector3(-dir.x, 0, -dir.y) * 10.0 + Vector3(side.x, 0, side.y) * 4.0 * _strafe
			face = atan2(-(aim_point.x - s.pos.x), -(aim_point.z - s.pos.z))
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
	var err: float = AIM_ERR[difficulty] * rng.randfn(0.0, 1.0) if archetype != "ranged" else 0.0
	return Sim.PlayerInput.new(seq, buttons, face, pitch, s.weapon, net.server_tick, face + err, face, spell, aim_point)


## The one it fights: whoever pressed the stone, while they're alive and near; else the nearest living player.
func _pick_target(net: Net, me: Net.ServerPlayer):
	var best = null
	var best_d := 45.0
	for q: Net.ServerPlayer in net.players.values():
		if q.npc or q.state.dead > 0:
			continue
		var d := q.state.pos.distance_to(me.state.pos) - (6.0 if q.id == owner else 0.0)
		if d < best_d:
			best_d = d
			best = q
	return best


## A threat to dodge, as the way to dash (sideways to it), or zero: a shot that will pass within a metre in the next
## half second, or the target's melee swing winding up while it's in reach.
func _threat(net: Net, me: Net.ServerPlayer, tgt: Net.ServerPlayer, dist: float) -> Vector2:
	var s := me.state
	for pr: Net.Proj in net.projectiles.values():
		if pr.owner == me.id:
			continue
		var n := net.server_tick - pr.tick0
		var p := Weapons.proj_pos(pr.pos0, pr.vel0, pr.g, n)
		var v := Weapons.proj_vel(pr.vel0, pr.g, n)
		var rel := s.pos + Vector3(0, 1.0, 0) - p
		var t := clampf(rel.dot(v) / maxf(v.length_squared(), 1e-4), 0.0, 0.5)
		if (p + v * t).distance_to(s.pos + Vector3(0, 1.0, 0)) < 1.1:
			var flat := Vector2(v.x, v.z).normalized()
			return Vector2(-flat.y, flat.x) * (1.0 if rng.randf() < 0.5 else -1.0)
	if Weapons.is_melee(tgt.state.weapon) and tgt.state.atk > 0:
		var mv := Weapons.move(tgt.state.weapon, tgt.state.combo)
		var winding := tgt.state.atk > int(mv.swing) - int(mv.windup)
		if winding and dist < float(mv.range) + 0.8:
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


## Which spell now (or -1): what its level has, what's ready, what suits the distance.
func _pick_spell(s: Sim.PlayerState, kind: String, lv: int, dist: float) -> int:
	var w := Weapons.STAFF if kind == "staff" else Weapons.WAND
	var opts := []
	if kind == "staff":
		if dist < 5.0 and Weapons.unlocked(w, 3, lv):
			opts.append([3, 3.0])          # frost nova, up close
		opts.append([0, 2.0])               # lightning
		opts.append([1, 2.5])               # fireball
		if Weapons.unlocked(w, 4, lv):
			opts.append([4, 1.2])           # meteor
		if Weapons.unlocked(w, 5, lv) and s.mana > 400:
			opts.append([5, 0.5])           # arcane storm
	else:
		if s.recharge[0] == 0 and dist < 22.0:
			opts.append([0, 2.0])           # a golem
		if s.recharge[1] == 0 and dist < 3.5:
			opts.append([1, 6.0])           # teleport out of melee
		if s.recharge[2] == 0 and dist < 15.0:
			opts.append([2, 2.0])           # stun
		if Weapons.unlocked(w, 3, lv) and s.recharge[3] == 0:
			opts.append([3, 1.8])           # earth spikes
		if Weapons.unlocked(w, 4, lv) and s.recharge[4] == 0:
			opts.append([4, 1.2])           # gravity well
		if Weapons.unlocked(w, 5, lv) and s.recharge[5] == 0:
			opts.append([5, 1.0])           # the titan
	var total := 0.0
	for o in opts:
		total += float(o[1])
	if total <= 0.0:
		return -1
	var x := rng.randf() * total
	for o in opts:
		x -= float(o[1])
		if x <= 0.0:
			return int(o[0])
	return int(opts[-1][0])
