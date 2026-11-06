## Thunderhorn (v0.10.0), the final boss: a giant storm bull, run by the server (like the golems); every few ticks its
## state goes to everyone (Net.boss_state) and BossView draws it.
##
## It comes down out of a storm in a lightning strike, slams the ground and roars. Then it picks attacks by how far
## its target is and how they play (never the same pattern twice in a row; weights, not a script), each with a clear
## wind-up you can read:
##   charge         head down, a hoof scraping the ground, then a gallop in a straight line, trampling all in its path
##   stomp          it rears up and slams down: three shockwave rings race out along the ground (jump them)
##   horn beam      the horns crackle, then a beam of lightning sweeps across in front of it
##   call lightning warning circles under everyone, then bolts strike them
##   roar           everyone near it is slowed for 2 s
##   ball lightning glowing balls that drift after players and burst on them
##   static field   always on: anyone right next to it takes a shock every half second
## It goes after whoever is nearest or whoever has hurt it most, splits its attention between two players, and punishes
## anyone hanging back at range (charges and called lightning). Below half health it ENRAGES (faster, shorter wind-ups,
## chaining attacks, red-white lightning); below a quarter it calls a storm (strikes keep falling round the arena).
##
## Its weaknesses and resistances (hurt()):
##   Lightning, chain lightning: a quarter damage (it's made of lightning)   Fireball: full, and it burns for 3 s
##   Frost Nova: full, and slowed a lot for 4 s      Stun: only staggers it, shorter each time (diminishing returns)
##   Earth Spikes: half again as much, and they interrupt a charge      Gravity Well: damage only (can't pull it)
##   Meteor: half again as much      Arcane Storm, weapons, arrows, stones, golems and the titan: full
##   The shield blocks its beam and ball lightning (for mana, as usual); Teleport is a good way out of a charge.
## Two players: 1.7 times the health, and it attacks more often.
class_name Boss
extends RefCounted

const ID := -5000                # its id as a damage target
const NAME := "Thunderhorn"
const BASE_HP := 1200
const RADIUS := 1.7              # its body, for hits
const HEIGHT := 3.4
const WALK := 4.5
const GALLOP := 16.0
enum S { ENTER, IDLE, WALK, CHARGE_WIND, CHARGE, STOMP_WIND, STOMP, BEAM_WIND, BEAM, CALL, ROAR, BALLS, STAGGER, DEATH }

var pos := Vector3.ZERO
var yaw := 0.0
var hp := BASE_HP
var max_hp := BASE_HP
var state := S.ENTER
var t := 0
var players_n := 1
var target := 0
var slow := 0
var burn := 0
var burn_from := 0
var enraged := false
var storm := false
var damage_by := {}
var last_attack := ""
var cooldown := {}
var charge_dir := Vector2.ZERO
var charge_hit := {}
var beam_a := 0.0
var beam_from := 0.0
var beam_to := 0.0
var rings: Array = []            # stomp shockwaves: [radius, hit ids]
var balls: Array = []            # [pos, vel, life]
var stuns: Array = []            # ticks it was stunned (diminishing returns)
var far_t := 0                   # ticks its target has hung back at range
var rng := RandomNumberGenerator.new()
var done := false                # its death has played out
# what the server applies this tick (Net reads and clears them)
var hits: Array = []             # [target, amount, dir, knock]
var fx: Array = []               # [kind, args]
var slows: Array = []            # [player id, ticks]
var strikes: Array = []          # [point, delay ticks]: called lightning


func _init(at: Vector3, n_players: int, seed_v := 0) -> void:
	pos = at
	players_n = n_players
	max_hp = int(BASE_HP * (1.7 if n_players >= 2 else 1.0))
	hp = max_hp
	rng.seed = seed_v if seed_v != 0 else randi()
	fx.append(["boss_enter", [pos]])


func _go(s: int) -> void:
	state = s
	t = 0


func speed_k() -> float:
	return (1.3 if enraged else 1.0) * (0.4 if slow > 0 else 1.0)


func windup_k() -> float:
	return (0.68 if enraged else 1.0) * (0.85 if players_n >= 2 else 1.0)


## Damage it (after its resistances); from: the attacker (player id, -1000 - golem id, 0); spell: the spell's name, or
## "" for weapons, golems and anything else. -> what it really took.
func hurt(amount: int, from: int, spell: String) -> int:
	if state == S.ENTER or state == S.DEATH:
		return 0
	var k := 1.0
	match spell:
		"Lightning":
			k = 0.25
		"Earth Spikes":
			k = 1.5
			if state == S.CHARGE or state == S.CHARGE_WIND:
				_go(S.STAGGER)   # the spikes stop a charge dead
				fx.append(["boss_stagger", [pos]])
		"Meteor":
			k = 1.5
		"Fireball":
			burn = 180
			burn_from = from
	var dmg := maxi(int(round(amount * k)), 1 if k > 0.0 else 0)
	hp = maxi(hp - dmg, 0)
	if from != 0:
		damage_by[from] = int(damage_by.get(from, 0)) + dmg
	if not enraged and hp < max_hp / 2:
		enraged = true
		fx.append(["boss_enrage", [pos]])
	if not storm and hp < max_hp / 4:
		storm = true
		fx.append(["boss_storm", [pos]])
	if hp == 0:
		_go(S.DEATH)
		fx.append(["boss_death", [pos]])
	elif dmg >= 25 and state in [S.IDLE, S.WALK]:
		fx.append(["boss_flinch", [pos]])
	return dmg


## A stun only staggers it, shorter every time within 10 s (half, a quarter...).
func stunned(now: int) -> void:
	stuns = stuns.filter(func(x): return now - int(x) < 600)
	stuns.append(now)
	if state in [S.ENTER, S.DEATH]:
		return
	var ticks := int(45.0 * pow(0.5, stuns.size() - 1))
	if ticks >= 6:
		_go(S.STAGGER)
		t = 45 - ticks
		fx.append(["boss_stagger", [pos]])


func frosted() -> void:
	slow = 240


## One server tick. people: [[id, position, alive, shielded]]; golems: [[golem id, position]].
func tick(now: int, people: Array, golems: Array) -> void:
	t += 1
	if slow > 0:
		slow -= 1
	if burn > 0:
		burn -= 1
		if burn % 30 == 0:
			hurt(4, burn_from, "Burn")
	if state == S.DEATH:
		done = t > 180
		return
	var living := people.filter(func(p): return p[2])
	# the static field: a shock to anyone right next to it, twice a second
	if now % 30 == 0 and state != S.ENTER:
		for p in living:
			var d := _flat(p[1] - pos)
			if d.length() < RADIUS + 1.6:
				hits.append([p[0], 6 if enraged else 4, Vector3(d.x, 0, d.y), 2.0])
	# the storm, below a quarter: strikes keep falling round the arena
	if storm and now % 50 == 0 and not living.is_empty():
		var p: Array = living[rng.randi() % living.size()]
		strikes.append([(p[1] as Vector3) + Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4)), 50])
	_tick_balls(living)
	_tick_rings(living, golems)
	var tp = _target_pos(living, golems)
	match state:
		S.ENTER:
			if t >= 150:
				fx.append(["boss_roar", [pos, 0]])
				_go(S.IDLE)
		S.IDLE:
			if tp != null:
				_turn_to(tp, 0.06)
			if t >= int(rng.randi_range(18, 45) * windup_k()):
				_choose(living, golems, tp)
		S.WALK:
			if tp == null:
				_go(S.IDLE)
			else:
				_turn_to(tp, 0.08)
				var d := _flat(tp - pos)
				var want: float = cooldown.get("_want", 5.0)
				if d.length() > want:
					var step := d.normalized() * WALK * speed_k() * Config.DT
					pos += Vector3(step.x, 0, step.y)
				if d.length() <= want or t > 150:
					_attack(str(cooldown.get("_next", "stomp")), tp)
		S.CHARGE_WIND:   # head down, a hoof scraping: then it goes
			if tp != null and t < 30:
				_turn_to(tp, 0.12)
			if t >= int(50 * windup_k()):
				charge_dir = Vector2(-sin(yaw), -cos(yaw))
				charge_hit = {}
				fx.append(["boss_charge", [pos, yaw]])
				_go(S.CHARGE)
		S.CHARGE:
			var step := charge_dir * GALLOP * speed_k() * Config.DT
			pos += Vector3(step.x, 0, step.y)
			pos.x = clampf(pos.x, -Config.WORLD_HALF + 5, Config.WORLD_HALF - 5)
			pos.z = clampf(pos.z, -Config.WORLD_HALF + 5, Config.WORLD_HALF - 5)
			for p in living:
				var d := _flat(p[1] - pos)
				if d.length() < RADIUS + 0.9 and not charge_hit.has(p[0]):
					charge_hit[p[0]] = true
					hits.append([p[0], 30 if enraged else 25, Vector3(charge_dir.x + d.normalized().x, 0, charge_dir.y + d.normalized().y), 13.0])
			for g in golems:
				var d := _flat(g[1] - pos)
				if d.length() < RADIUS + 0.7 and not charge_hit.has(-1000 - int(g[0])):
					charge_hit[-1000 - int(g[0])] = true
					hits.append([-1000 - int(g[0]), 25, Vector3(charge_dir.x, 0, charge_dir.y), 0.0])
			if t >= 80:
				fx.append(["boss_skid", [pos]])
				_after()
		S.STOMP_WIND:   # it rears up
			if t >= int(40 * windup_k()):
				fx.append(["boss_stomp", [pos]])
				rings.append([RADIUS, {}])
				_go(S.STOMP)
		S.STOMP:
			if t == 24 or t == 48:
				rings.append([RADIUS, {}])
				fx.append(["boss_stomp", [pos]])
			if t >= 60:
				_after()
		S.BEAM_WIND:    # the horns crackle and glow
			if tp != null:
				_turn_to(tp, 0.1)
			if t >= int(45 * windup_k()):
				var sweep := deg_to_rad(110.0 if not enraged else 150.0)
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				beam_from = yaw - side * sweep * 0.5
				beam_to = yaw + side * sweep * 0.5
				beam_a = beam_from
				fx.append(["boss_beam", [pos, beam_from, beam_to, 90]])
				_go(S.BEAM)
		S.BEAM:
			beam_a = lerp_angle(beam_from, beam_to, clampf(float(t) / 90.0, 0.0, 1.0))
			if t % 6 == 0:
				var o := pos + Vector3(0, 2.4, 0)
				var dir := Vector3(-sin(beam_a), 0, -cos(beam_a))
				for p in living:
					var rel: Vector3 = (p[1] as Vector3) + Vector3(0, 1.0, 0) - o
					var along := rel.dot(dir)
					if along > 0.5 and along < 18.0 and (rel - dir * along).length() < 1.1:
						hits.append([p[0], 7 if enraged else 5, dir, 3.0])
			if t >= 90:
				_after()
		S.CALL:         # it rears and bellows at the sky: warning circles under everyone, then bolts
			if t == 20:
				for p in living:
					strikes.append([(p[1] as Vector3) + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)), 60])
					if enraged:
						strikes.append([(p[1] as Vector3) + Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4)), 75])
			if t >= 60:
				_after()
		S.ROAR:
			if t == 15:
				fx.append(["boss_roar", [pos, 1 if enraged else 2]])
				for p in living:
					if (p[1] as Vector3).distance_to(pos) < 15.0:
						slows.append([p[0], 120])
			if t >= 60:
				_after()
		S.BALLS:
			if t == 20:
				for i in (5 if enraged else 3):
					var a := yaw + (float(i) - 1.0) * 0.6
					balls.append([pos + Vector3(-sin(a) * 2.0, 2.2, -cos(a) * 2.0), Vector3(-sin(a), 0.2, -cos(a)) * 4.0, 360])
				fx.append(["boss_balls", [pos]])
			if t >= 45:
				_after()
		S.STAGGER:
			if t >= 45:
				_go(S.IDLE)


## After an attack: enraged, it often goes straight into the next one; otherwise a moment's pause.
func _after() -> void:
	if enraged and rng.randf() < 0.45:
		_go(S.IDLE)
		t = 999   # choose at once
	else:
		_go(S.IDLE)


## Pick the next attack: by the target's distance and habits, never the same one twice running if it can help it.
func _choose(living: Array, golems: Array, tp) -> void:
	_retarget(living, golems)
	tp = _target_pos(living, golems)
	if tp == null:
		return
	var d := _flat(tp - pos).length()
	if d > 14.0:
		far_t += 30
	else:
		far_t = maxi(far_t - 30, 0)
	var punish := 2.0 if far_t > 240 else 1.0   # hanging back at range for 4 s: charges and lightning
	var near_golem := false
	for g in golems:
		if (g[1] as Vector3).distance_to(pos) < RADIUS + 2.5:
			near_golem = true
	var w := {
		"charge": (3.0 if d > 8.0 else (1.2 if d > 4.0 else 0.2)) * punish,
		"call": (2.5 if d > 10.0 else 0.8) * punish,
		"balls": 2.0 if d > 8.0 else 0.6,
		"beam": 2.5 if d > 4.0 and d < 16.0 else 0.4,
		"stomp": (3.5 if d < 6.0 else 0.5) + (3.0 if near_golem else 0.0),
		"roar": 0.9 if d < 12.0 else 0.2,
	}
	for k in w.keys():
		if k == last_attack:
			w[k] *= 0.15
		if int(cooldown.get(k, 0)) > 0:
			w[k] *= 0.3
	var total := 0.0
	for k in w:
		total += float(w[k])
	var x := rng.randf() * total
	var pick := "stomp"
	for k in w:
		x -= float(w[k])
		if x <= 0.0:
			pick = k
			break
	# the stomp and the roar want it close: walk in first
	if pick in ["stomp", "roar"] and d > 6.0:
		cooldown["_want"] = 4.5
		cooldown["_next"] = pick
		_go(S.WALK)
		return
	_attack(pick, tp)


func _attack(pick: String, tp) -> void:
	last_attack = pick
	for k in cooldown.keys():
		if not k.begins_with("_"):
			cooldown[k] = maxi(int(cooldown[k]) - 1, 0)
	cooldown[pick] = 2
	match pick:
		"charge":
			_go(S.CHARGE_WIND)
			fx.append(["boss_charge_wind", [pos, yaw]])
		"stomp":
			_go(S.STOMP_WIND)
			fx.append(["boss_rear", [pos]])
		"beam":
			_go(S.BEAM_WIND)
			fx.append(["boss_beam_wind", [pos]])
		"call":
			_go(S.CALL)
			fx.append(["boss_call", [pos]])
		"roar":
			_go(S.ROAR)
		"balls":
			_go(S.BALLS)


## Who it goes after: the nearest, or whoever has hurt it most (a golem standing in its way counts); with two players
## it switches between them.
func _retarget(living: Array, golems: Array) -> void:
	var best := 0
	var best_s := -INF
	for p in living:
		var d := (p[1] as Vector3).distance_to(pos)
		var s := -d + float(damage_by.get(p[0], 0)) * 0.05 + rng.randf_range(0.0, 6.0)
		if p[0] == target and players_n >= 2:
			s -= 4.0   # spread its attention
		if s > best_s:
			best_s = s
			best = p[0]
	for g in golems:
		var d := (g[1] as Vector3).distance_to(pos)
		if d < 4.0 and -d + 2.0 > best_s:
			best_s = -d + 2.0
			best = -1000 - int(g[0])
	target = best


func _target_pos(living: Array, golems: Array):
	for p in living:
		if p[0] == target:
			return p[1]
	for g in golems:
		if -1000 - int(g[0]) == target:
			return g[1]
	if not living.is_empty():
		target = living[0][0]
		return living[0][1]
	return null


func _turn_to(tp: Vector3, rate: float) -> void:
	var d := _flat(tp - pos)
	if d.length() > 0.1:
		yaw = lerp_angle(yaw, atan2(-d.x, -d.y), rate * speed_k())


func _tick_rings(living: Array, golems: Array) -> void:
	for r in rings:
		r[0] = float(r[0]) + 9.0 * Config.DT
		for p in living:
			var dp: Vector3 = p[1]
			var d := _flat(dp - pos).length()
			if absf(d - float(r[0])) < 0.7 and dp.y < pos.y + 0.5 and not (r[1] as Dictionary).has(p[0]):   # jump it
				r[1][p[0]] = true
				hits.append([p[0], 16 if enraged else 13, Vector3(dp.x - pos.x, 0, dp.z - pos.z), 7.0])
		for g in golems:
			var d := _flat((g[1] as Vector3) - pos).length()
			if absf(d - float(r[0])) < 0.7 and not (r[1] as Dictionary).has(-1000 - int(g[0])):
				r[1][-1000 - int(g[0])] = true
				hits.append([-1000 - int(g[0]), 13, Vector3.ZERO, 0.0])
	rings = rings.filter(func(r): return float(r[0]) < 14.0)


func _tick_balls(living: Array) -> void:
	for b in balls:
		b[2] = int(b[2]) - 1
		var near = null
		var nd := 30.0
		for p in living:
			var d := ((p[1] as Vector3) + Vector3(0, 1.1, 0)).distance_to(b[0])
			if d < nd:
				nd = d
				near = p
		if near != null:
			var want := (((near[1] as Vector3) + Vector3(0, 1.1, 0)) - (b[0] as Vector3)).normalized() * 6.5
			b[1] = (b[1] as Vector3).lerp(want, 0.03)
			if nd < 1.0:
				hits.append([near[0], 12, b[1], 3.0])
				fx.append(["boss_ball_pop", [b[0]]])
				b[2] = 0
		b[0] = (b[0] as Vector3) + (b[1] as Vector3) * Config.DT
	balls = balls.filter(func(b): return int(b[2]) > 0)


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## Its state, flat, for the network: [state, t, x, y, z, yaw, hp, max hp, status bits, beam angle, rings, balls].
## Status bits: 1 staggered, 2 slowed, 4 burning, 8 enraged, 16 shielded (untouchable while it arrives), 32 storm.
func pack() -> Array:
	var flags := (1 if state == S.STAGGER else 0) | (2 if slow > 0 else 0) | (4 if burn > 0 else 0) | (8 if enraged else 0) \
		| (16 if state == S.ENTER else 0) | (32 if storm else 0)
	return [state, t, pos.x, pos.y, pos.z, yaw, hp, max_hp, flags, beam_a, rings.map(func(r): return float(r[0])),
		balls.map(func(b): return b[0])]
