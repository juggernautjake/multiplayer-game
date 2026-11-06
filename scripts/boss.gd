## Thunderhorn, the final boss: a giant storm bull (about 3.5x a player's height), run by the server (like the golems);
## every other tick his state goes to everyone (Net.boss_state) and BossView draws it. v0.10.0, reworked in v0.11.0.
##
## THE FIGHT, in order (a designed flow, not just random swings):
##   opener      he comes down out of a storm in a lightning strike, slams and roars; then circles you and charges.
##   rotation    he picks attacks by distance and how you play (weights, never the same twice running), moving between
##               them: circling (STRAFE), backing off (BACKOFF), pouncing hops to a new spot (HOP), snapping round to
##               face you (TURN) and short feint lunges (LUNGE).
##   Storm Leap  2-5 times a fight (rules below): leap, ring, homing static orbs, three slams, pawing, the rush.
##   enrage      below half health he stops, rears and transforms (PHASE 1): red-white lightning, faster, shorter
##               wind-ups, chaining attacks, the double charge, the beam sweeping both ways, static ball lightning,
##               the static roar, 5 stacks of Static stun instead of 6.
##   storm       below a quarter (PHASE 2): the storm breaks over the arena (strikes keep falling), called lightning
##               walks at you in lines, charges come three at a time.
##
## Attacks (each has a wind-up you can read, a sound and an impact):
##   charge        head down, a hoof scraping: a gallop in a straight line (enraged: twice; storm: three times)
##   stomp         he rears up and slams: three rings race out along the ground (jump them); enraged: four slams,
##                 the last one sending a double ring
##   horn beam     the horns crackle, then a beam sweeps the ground in front (enraged: back and forth)
##   call          warning circles under everyone, then bolts (enraged: extra ones; storm: lines walking at you)
##   roar          slows everyone near for 2 s (enraged: and adds a stack of Static)
##   ball lightning glowing balls drift after players (enraged: 5 static balls, each adds a stack)
##   gore          a hooking sweep of the horns in front, for anyone too close
##   tail lash     he pivots and the spiked tail sweeps round behind him, for anyone at his flank or back
##   static field  always on: anyone right next to him takes a shock every half second
##
## STATIC (v0.11.0): his homing orbs (and static ball lightning, and the static roar) add a stack of Static to a
## player (Sim.ZAP_STACK). 6 stacks (5 while he is enraged) = stunned for 7 s (Sim.STATIC_STUN). The meter holds 2.5 s
## after the last hit, then drains a stack every 3.3 s. A held shield blocks the orbs (they bounce off) and adds nothing.
##
## STORM LEAP (v0.11.0), the signature sequence:
##   LEAP_WIND 1.5 s  he crouches, lightning gathers, a charge-up roar; a glowing marker shows where he will land, far
##                    across the arena (never within 6 m of a player)
##   LEAP      1.4 s  a huge arc across the arena; landing on someone hurts (22)
##   landing          a low shockwave ring: JUMP it (it only hits players on the ground: 18)
##   HOWL      4.3 s  a long roar; 10 homing orbs (one player), 15 (two), +5 per extra player (24 at most), split
##                    evenly between the living players; limited turn (2.1 rad/s), speeding up 5 -> 14 m/s, gone after
##                    5 s; strafe or dash past them, hide behind a pillar or shield them (they bounce off). Each hit: 6
##                    damage and a stack of Static.
##   SLAMS     2.3 s  three ground slams, three rings in a row (9, 10.5, 12 m/s): jump each
##   PAW       1.6 s  he paws the ground and snorts, locked on the nearest player; a path glows on the ground
##   RUSH             a 24 m/s charge down that path: dash sideways in time (a dash is untouchable) or be hit for 30
##                    (35 enraged) and launched ~15 m, knocked down for 2.3 s (Sim.DOWN_TICKS), getting up at the end
##   RECOVER   1.2 s  he skids and pants; then back to the rotation
## When: a leap is guaranteed as his health falls past 80%, 55% and 30%; up to two more come when the players are doing
## well (average health 70% or more and little damage taken lately: an 18% chance each time he picks an attack, below
## 92% health); if 75 s pass with fewer than two leaps, he leaps anyway. At most 5 a fight, at least 25 s from the
## start of one to the start of the next. Phase changes come first; a pending leap waits for the next pick.
##
## TARGETING (_retarget): every pick scores each living player: closer is a little better; recent damage dealt to him
## (threat, fading over ~8 s) and total damage; anyone hanging back past 15 m for 4 s (then he favours charges, called
## lightning, balls); anyone casting; a finishing bonus for low health (under 35%) but never for someone stunned or
## knocked down (he lets them get up); no line of sight is a big minus. With two or more players a running share of
## his attention is kept: whoever has had more than their share is marked down, and after ~6 s on one target the
## pull to switch grows, so nobody is hunted forever. A golem right in his face counts too.
##
## Weaknesses (hurt()): Lightning x1/4 (he's made of it), Earth Spikes and Meteor x1.5 (spikes stop a charge or the rush
## dead), Fireball burns 3 s, Frost Nova slows a lot for 4 s, stuns only stagger (shorter each time), gravity wells
## can't move him. The Storm Leap is armoured against staggers except the rush (spikes stop it). Health: hp_for()
## (x1.7 for two), shorter wind-ups with two or more.
class_name Boss
extends RefCounted

const ID := -5000                # its id as a damage target
const NAME := "Thunderhorn"
## Health (v0.11.0): BASE_HP x (1 + 0.7 per extra player): 7000 alone, 11 900 for two (the old x1.7), 16 800 for three.
## The math: a level-3 wizard's sustained damage on him, dodging half the time, is about 15 a second (mana comes back
## at 12 a second: meteors 60 for 45 mana, fireballs ~20 for 22 plus 8 a second of burning, earth spikes 24 a spike
## from the wand's recharge, sword cuts 8 at most every 0.6 s up close; lightning only 7). 7000 / 15 = ~7.8 minutes.
const BASE_HP := 7000
const HP_PER_EXTRA := 0.7
const RADIUS := 2.8              # his body, for hits (v0.11.0: about 3.5x a player)
const HORN_REACH := 5.6          # v0.12.0: the nose spike's tip, metres ahead of his centre (head lowered)
const SPIKE_R := 1.4             # v0.12.0: how close to that tip skewers you
const HEIGHT := 6.4
const HEAD_Y := 4.7
const WALK := 6.0
const GALLOP := 19.0
const RUSH_V := 24.0
const LEAP_H := 34.0             # v0.12.0: the apex of the shortest leap (was 14 m); see leap_arc()
const LEAP_AIR := 135            # ticks in the air of the shortest leap (was 84)
const LEAP_MAX_D := 200.0        # v0.12.0: he can bound up to 200 m, anywhere on the map
const LEAP_EDGE := 10.0          # landing candidates keep this far inside the world's edge
var leap_h := LEAP_H             # this leap's apex and air time (leap_arc of its distance)
var leap_air := LEAP_AIR
const LEAP_HP := [0.8, 0.55, 0.3]
const LEAP_MAX := 5
const LEAP_GAP := 1500           # ticks between the starts of two sequences
const LEAP_FALLBACK := 4500      # 75 s without one (and fewer than two so far): leap anyway
const ORB_V0 := 6.0
const ORB_VMAX := 15.0
const ORB_ACC := 5.0
const ORB_TURN := 2.8            # rad/s
const ORB_LIFE := 330
## v0.12.0 map-wide shockwaves: the Storm Leap's landing ring and the three slam waves after the howl race out at one
## steady speed (WAVE_V) until they have swept the whole map (wave_max: past its farthest corner), so every grounded
## player is hit unless they jump as it passes, wherever they are. WAVE_GAP ticks between slam waves (1.25 s: time to
## land from one jump, ~0.7 s in the air, and jump the next).
const WAVE_V := 22.0
const WAVE_GAP := 75


static func wave_max(c: Vector3) -> float:
	var h := Config.WORLD_HALF
	var m := 0.0
	for k in [Vector2(h, h), Vector2(-h, h), Vector2(h, -h), Vector2(-h, -h)]:
		m = maxf(m, Vector2(c.x, c.z).distance_to(k))
	return m + 2.0
const ORB_FAR_V := 30.0          # v0.12.0 cruise speed while more than ORB_SLOW_R from the target
const ORB_SLOW_R := 30.0
const ORB_DMG := 6
enum S { ENTER, IDLE, WALK, CHARGE_WIND, CHARGE, STOMP_WIND, STOMP, BEAM_WIND, BEAM, CALL, ROAR, BALLS, STAGGER, DEATH,
	STRAFE, BACKOFF, HOP, TURN, GORE_WIND, GORE, TAIL_WIND, TAIL, PHASE, LEAP_WIND, LEAP, LEAP_LAND, HOWL, SLAMS, PAW,
	RUSH, RECOVER, LUNGE, TREE, HOME }
const SEQ := [S.LEAP_WIND, S.LEAP, S.LEAP_LAND, S.HOWL, S.SLAMS, S.PAW, S.RUSH, S.RECOVER]
const MOVES := [S.STRAFE, S.BACKOFF, S.HOP, S.TURN, S.LUNGE]

static var shown_enraged := false   # clients: set by BossView, read by the Static meters

var pos := Vector3.ZERO
var yaw := 0.0
var hp := BASE_HP
var max_hp := BASE_HP
var state := S.ENTER
var t := 0
var total_t := 0
var players_n := 1
var target := 0
var slow := 0
var burn := 0
var burn_from := 0
var enraged := false
var storm := false
var phase := 0
var want_phase := 0
var damage_by := {}
var threat := {}                 # player -> recent damage to him (fades)
var attention := {}              # player -> ticks he has spent on them
var focus_t := 0
var far_t := {}                  # player -> ticks spent hanging back
var last_hp := {}
var last_p := {}                 # player -> last position (to estimate velocity for the orbs' lead)
var pvel := {}                   # player -> smoothed velocity
var orb_sent := {}               # player -> orbs launched at them this fight
var hurt_recent := 0.0           # damage the players took lately (fades)
var recent: Array = []           # the last attacks
var plan: Array = []             # what comes next, before choosing (the opener, double charges)
var moved := false
var rep := 0                     # charges left in a multi-charge, slams left...
var variant := 0                 # the attack's variant (0 plain, 1 enraged form, 2 storm form)
var charge_dir := Vector2.ZERO
var charge_hit := {}
var beam_a := 0.0
var beam_from := 0.0
var beam_to := 0.0
var move_side := 1.0
var move_len := 60
var hop_from := Vector3.ZERO
var hop_to := Vector3.ZERO
var leap_from := Vector3.ZERO
var leap_to := Vector3.ZERO
var leaps := 0
var leap_sure := 0               # guaranteed leaps used (health marks and the fallback)
var leap_bonus := 0
var last_leap := -100000
var rush_target := 0
var orb_plan := 0                # orbs still to launch this howl
var orb_total := 0
var orb_rot := 0
var big_hit_t := -100000
var rings: Array = []            # [radius, hit ids, centre, speed, damage, kind]
var balls: Array = []            # [pos, vel, life, static]
var orbs: Array = []             # [pos, vel, target, life, age, spent]
var stuns: Array = []
var rng := RandomNumberGenerator.new()
var done := false
# what the server applies this tick (Net reads and clears them)
var hits: Array = []             # [target, amount, dir, knock]
var fx: Array = []               # [kind, args]
var slows: Array = []            # [player id, ticks]
var strikes: Array = []          # [point, delay ticks]: called lightning
var zaps: Array = []             # [player id, damage, dir, blocked]: static hits
var launches: Array = []         # [player id, dir]: the rush


func _init(at: Vector3, n_players: int, seed_v := 0) -> void:
	pos = at
	players_n = n_players
	max_hp = hp_for(n_players)
	hp = max_hp
	rng.seed = seed_v if seed_v != 0 else randi()
	fx.append(["boss_enter", [pos]])
	plan = ["strafe", "charge"]   # the opener


static func hp_for(n_players: int) -> int:
	return int(BASE_HP * (1.0 + HP_PER_EXTRA * (maxi(n_players, 1) - 1)))


## Someone joined the fight mid-way: more health, in proportion (he doesn't heal back to full).
func add_fighter() -> void:
	players_n += 1
	var k := float(hp) / float(max_hp)
	max_hp = hp_for(players_n)
	hp = maxi(int(round(max_hp * k)), 1)


static func static_need(is_enraged: bool) -> int:
	return 5 if is_enraged else 6


## Homing orbs in one howl: 10 alone, 15 with two, 5 more for each extra player, 24 at most.
static func homing_count(n_players: int) -> int:
	return mini(5 + 5 * maxi(n_players, 1), 24)


static func arena_c() -> Vector3:
	return Vector3(WorldLayout.ALTAR_C.x, 0, WorldLayout.ALTAR_C.y + 10.0)


func _go(s: int) -> void:
	state = s
	t = 0


func in_sequence() -> bool:
	return state in SEQ


func speed_k() -> float:
	return (1.3 if enraged else 1.0) * (0.4 if slow > 0 else 1.0)


func windup_k() -> float:
	return (0.68 if enraged else 1.0) * (0.85 if players_n >= 2 else 1.0)


## Damage him (after his resistances); from: the attacker (player id, -1000 - golem id, 0); spell: the spell's name, or
## "" for weapons, golems and anything else. -> what he really took.
func hurt(amount: int, from: int, spell: String) -> int:
	if state == S.ENTER or state == S.DEATH:
		return 0
	var k := 1.0
	match spell:
		"Lightning":
			k = 0.25
		"Earth Spikes":
			k = 1.5
			if state in [S.CHARGE, S.CHARGE_WIND, S.RUSH, S.PAW]:
				rep = 0
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
		threat[from] = float(threat.get(from, 0.0)) + dmg
	if not enraged and hp < max_hp / 2:
		enraged = true
		want_phase = maxi(want_phase, 1)
		fx.append(["boss_enrage", [pos]])
	if not storm and hp < max_hp / 4:
		storm = true
		want_phase = 2
		fx.append(["boss_storm", [pos]])
	if hp == 0:
		_go(S.DEATH)
		orbs.clear()
		fx.append(["boss_death", [pos]])
	elif dmg >= 60 and not in_sequence() and state not in [S.PHASE, S.STAGGER] and total_t - big_hit_t > 600:
		big_hit_t = total_t   # a really big hit staggers him (once in 10 s)
		_go(S.STAGGER)
		t = 15
		fx.append(["boss_stagger", [pos]])
	elif dmg >= 25 and state in [S.IDLE, S.WALK, S.STRAFE]:
		fx.append(["boss_flinch", [pos]])
	return dmg


## A stun only staggers him, shorter every time within 10 s (half, a quarter...); the Storm Leap shrugs it off.
func stunned(now: int) -> void:
	stuns = stuns.filter(func(x): return now - int(x) < 600)
	stuns.append(now)
	if state in [S.ENTER, S.DEATH, S.PHASE] or (in_sequence() and state != S.RUSH):
		return
	var ticks := int(45.0 * pow(0.5, stuns.size() - 1))
	if ticks >= 6:
		rep = 0
		_go(S.STAGGER)
		t = 45 - ticks
		fx.append(["boss_stagger", [pos]])


func frosted() -> void:
	slow = 240


# ================================================================ people: [id, pos, alive, shielded, hp, dash ticks,
# casting, helpless (stunned or knocked down)]; Net sends all of them, tests may send only the first four
static func _p_hp(p: Array) -> int:
	return int(p[4]) if p.size() > 4 else Sim.MAX_HP


static func _p_dash(p: Array) -> bool:
	return p.size() > 5 and int(p[5]) > 0


static func _p_cast(p: Array) -> bool:
	return p.size() > 6 and bool(p[6])


static func _p_helpless(p: Array) -> bool:
	return p.size() > 7 and bool(p[7])


## One server tick. people: as above; golems: [[golem id, position]].
func tick(now: int, people: Array, golems: Array) -> void:
	t += 1
	total_t += 1
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
	_track(living)
	# the static field: a shock to anyone right next to him, twice a second
	if now % 30 == 0 and state not in [S.ENTER, S.LEAP]:
		for p in living:
			var d := _flat(p[1] - pos)
			if d.length() < RADIUS + 1.4 and (p[1] as Vector3).y < pos.y + 3.0:
				hits.append([p[0], 6 if enraged else 4, Vector3(d.x, 0, d.y), 2.0])
	# the storm, below a quarter: strikes keep falling round the arena
	if storm and now % 50 == 0 and not living.is_empty():
		var p: Array = living[rng.randi() % living.size()]
		strikes.append([(p[1] as Vector3) + Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4)), 50])
	_tick_balls(living)
	_tick_rings(living, golems)
	_tick_orbs(living)
	var tp = _target_pos(living, golems)
	var wk := windup_k()
	_trees_and_apples(living)
	_drift_home(living)
	match state:
		S.ENTER:
			if t >= 150:
				fx.append(["boss_roar", [pos, 0]])
				_go(S.IDLE)
		S.IDLE:
			if tp != null:
				_turn_to(tp, 0.07)
			if t >= int(rng.randi_range(14, 36) * wk):
				_choose(living, golems)
		S.WALK:
			if tp == null:
				_go(S.IDLE)
			else:
				_turn_to(tp, 0.09)
				var d := _flat(tp - pos)
				if d.length() > RADIUS + 3.0:
					_step(d.normalized() * WALK * 1.2 * speed_k())
				if d.length() <= RADIUS + 3.5 or t > 150:
					_attack(str(plan.pop_front()) if not plan.is_empty() else "stomp", tp)
		# ---- manoeuvres
		S.STRAFE:   # circling the target, side-on, keeping 8-14 m
			if tp == null or t >= move_len:
				_after_move()
			else:
				_turn_to(tp, 0.12)
				var d := _flat(tp - pos)
				var tang := Vector2(-d.y, d.x).normalized() * move_side
				var radial := d.normalized() * clampf((d.length() - 11.0) * 0.25, -0.6, 0.6)
				_step((tang + radial).normalized() * WALK * speed_k())
		S.BACKOFF:  # backing away, still facing them
			if tp == null or t >= move_len:
				_after_move()
			else:
				_turn_to(tp, 0.12)
				_step(-_flat(tp - pos).normalized() * WALK * 0.9 * speed_k())
		S.HOP:      # a crouch, a pounce to a new spot, a heavy landing
			if t == 1:
				fx.append(["boss_hop", [pos, hop_to]])
			var u := clampf(float(t - 10) / 30.0, 0.0, 1.0)
			if t > 10:
				pos = hop_from.lerp(hop_to, u)
				pos.y = 4.0 * 3.0 * u * (1.0 - u)
			if tp != null:
				_turn_to(tp, 0.08)
			if t >= 40:
				pos = hop_to
				fx.append(["boss_hop_land", [pos]])
				_after_move()
		S.TURN:     # snapping round to face, hooves stamping
			if t == 1:
				fx.append(["boss_turn", [pos, yaw]])
			if tp != null:
				_turn_to(tp, 0.28)
			if t >= 22:
				_after_move()
		S.LUNGE:    # a short feint lunge, closing in
			if t == 1:
				fx.append(["boss_lunge", [pos, yaw]])
			if tp != null:
				var d := _flat(tp - pos)
				_turn_to(tp, 0.15)
				if t > 6 and d.length() > RADIUS + 3.0:
					_step(Vector2(-sin(yaw), -cos(yaw)) * 13.0 * speed_k())
			if t >= 26:
				_after_move()
		# ---- attacks
		S.CHARGE_WIND:   # head down, a hoof scraping: then he goes
			if t == 1:
				via_tree = _tree_on_line(tp)
			if tp != null and t < int(34 * wk):
				_turn_to(via_tree if via_tree != null else tp, 0.14)   # v0.12.0: lined up through a tree when he can
			if t % 18 == 9:
				fx.append(["boss_scrape", [pos, yaw]])
			if t >= int(50 * wk):
				charge_dir = Vector2(-sin(yaw), -cos(yaw))
				charge_hit = {}
				fx.append(["boss_charge", [pos, yaw]])
				_go(S.CHARGE)
		S.CHARGE:
			_step(charge_dir * GALLOP * speed_k())
			for p in living:
				var d := _flat(p[1] - pos)
				if (d.length() < RADIUS + 1.4 or _on_spike(d, charge_dir)) and not charge_hit.has(p[0]) and (p[1] as Vector3).y < 3.5:
					charge_hit[p[0]] = true
					var cdir := Vector3(charge_dir.x + d.normalized().x * 0.5, 0, charge_dir.y + d.normalized().y * 0.5).normalized()
					hits.append([p[0], 30 if enraged else 25, cdir, 0.0])
					launches.append([p[0], cdir])   # v0.12.0: the charge throws you too
			_trample_bystanders(RADIUS + 1.4, 25)
			for g in golems:
				var d := _flat(g[1] - pos)
				if d.length() < RADIUS + 1.2 and not charge_hit.has(-1000 - int(g[0])):
					charge_hit[-1000 - int(g[0])] = true
					hits.append([-1000 - int(g[0]), 25, Vector3(charge_dir.x, 0, charge_dir.y), 0.0])
			var past := true
			if tp != null:
				var d := _flat(tp - pos)
				past = d.dot(charge_dir) < -7.0
			if t >= 80 or (t > 30 and past) or _flat(pos - arena_c()).length() > WorldLayout.ARENA_R + 6.0:
				fx.append(["boss_skid", [pos, yaw]])
				if rep > 0:
					rep -= 1
					_go(S.CHARGE_WIND)
					t = int(16 * wk)   # a shorter wind-up for the next one
				else:
					_after()
		S.STOMP_WIND:   # he rears up
			if t >= int(40 * wk):
				_slam(9.0, 13)
				_go(S.STOMP)
		S.STOMP:
			var every := 24
			if t % every == 0 and t / every < (4 if variant > 0 else 3):
				_slam(9.0 + t / every, 13)
				if variant > 0 and t / every == 3:
					rings.append([RADIUS - 1.6, {}, Vector3(pos.x, 0, pos.z), 9.5, 15, 0])   # the double ring
			if t >= (4 if variant > 0 else 3) * every + 12:
				_after()
		S.BEAM_WIND:    # the horns crackle and glow
			if tp != null:
				_turn_to(tp, 0.1)
			if t >= int(45 * wk):
				var sweep := deg_to_rad(110.0 if variant == 0 else 150.0)
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				beam_from = yaw - side * sweep * 0.5
				beam_to = yaw + side * sweep * 0.5
				beam_a = beam_from
				fx.append(["boss_beam", [pos, beam_from, beam_to, 90 if variant == 0 else 160]])
				_go(S.BEAM)
		S.BEAM:
			var length := 90 if variant == 0 else 160
			if t <= 90:
				beam_a = lerp_angle(beam_from, beam_to, clampf(float(t) / 90.0, 0.0, 1.0))
			else:   # and back again
				beam_a = lerp_angle(beam_to, beam_from, clampf(float(t - 90) / 70.0, 0.0, 1.0))
			if t % 6 == 0:
				var dir := Vector2(-sin(beam_a), -cos(beam_a))
				for p in living:
					var rel := _flat(p[1] - pos)
					var along := rel.dot(dir)
					if along > RADIUS and along < 24.0 and absf(rel.cross(dir)) < 1.3 and (p[1] as Vector3).y < 2.6:
						hits.append([p[0], 7 if enraged else 5, Vector3(dir.x, 0, dir.y), 3.0])
			if t >= length:
				_after()
		S.CALL:         # he rears and bellows at the sky: warning circles under everyone, then bolts
			if t == 20:
				for p in living:
					var at: Vector3 = p[1]
					if variant == 2:   # storm: a line of strikes walking at them
						var from := _flat(at - pos).normalized()
						for i in 6:
							var q := at - Vector3(from.x, 0, from.y) * (10.0 - i * 2.0)
							strikes.append([Vector3(q.x, 0, q.z), 40 + i * 8])
						strikes.append([at + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)), 95])
					else:
						strikes.append([at + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)), 60])
						if variant == 1:
							strikes.append([at + Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4)), 75])
			if t >= 60:
				_after()
		S.ROAR:
			if t == 15:
				fx.append(["boss_roar", [pos, 1 if enraged else 2]])
				for p in living:
					var dd := (p[1] as Vector3).distance_to(pos)
					if dd < 16.0:
						slows.append([p[0], 120])
					if variant > 0 and dd < 13.0:
						zaps.append([p[0], 0, (p[1] as Vector3) - pos, bool(p[3])])   # the static roar
			if t >= 60:
				_after()
		S.BALLS:
			if t == 20:
				var n := 5 if variant > 0 else 3
				for i in n:
					var a := yaw + (float(i) - (n - 1) * 0.5) * 0.5
					balls.append([pos + Vector3(-sin(a) * 3.0, HEAD_Y - 0.5, -cos(a) * 3.0), Vector3(-sin(a), 0.2, -cos(a)) * 4.0, 360, variant > 0])
				fx.append(["boss_balls", [pos, variant]])
			if t >= 45:
				_after()
		S.GORE_WIND:   # the head drops and swings back to one side
			if tp != null:
				_turn_to(tp, 0.16)
			if t >= int(26 * wk):
				fx.append(["boss_gore", [pos, yaw]])
				_go(S.GORE)
		S.GORE:
			if t == 6:
				var fwd := Vector2(-sin(yaw), -cos(yaw))
				for p in living:
					var d := _flat(p[1] - pos)
					if ((d.length() < RADIUS + 4.6 and d.normalized().dot(fwd) > 0.25) or _on_spike(d, fwd)) and (p[1] as Vector3).y < 4.0:
						hits.append([p[0], 20 if enraged else 16, Vector3(d.x + fwd.x, 0.3, d.y + fwd.y), 11.0])
			if t >= 24:
				_after()
		S.TAIL_WIND:   # the body coils, the tail lifts
			if t >= int(24 * wk):
				fx.append(["boss_tail", [pos, yaw, move_side]])
				_go(S.TAIL)
		S.TAIL:
			if t < 14:
				yaw += 0.07 * move_side   # he pivots into it
			if t == 9:
				var fwd := Vector2(-sin(yaw), -cos(yaw))
				for p in living:
					var d := _flat(p[1] - pos)
					if d.length() < RADIUS + 4.8 and d.normalized().dot(fwd) < 0.3 and (p[1] as Vector3).y < 3.0:
						hits.append([p[0], 18 if enraged else 14, Vector3(d.x, 0.2, d.y), 12.0])
			if t >= 32:
				_after()
		S.STAGGER:     # stumbling
			if t >= 45:
				_go(S.IDLE)
		S.PHASE:       # he rears and transforms: the phase change
			if t == 40:
				fx.append(["boss_phase", [pos, phase]])
				rings.append([RADIUS, {}, Vector3(pos.x, 0, pos.z), 11.0, 10, 1])
				if phase == 2:
					for p in living:
						strikes.append([(p[1] as Vector3) + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3)), 50])
			if t >= 130:
				_go(S.IDLE)
				t = 999
		# ---- the Storm Leap
		S.LEAP_WIND:
			if tp != null and t < 40:
				_turn_to(tp, 0.05)
			if t >= 90:
				leap_from = Vector3(pos.x, 0, pos.z)
				var dl := _flat(leap_to - pos)
				if dl.length() > 0.1:
					yaw = atan2(-dl.x, -dl.y)
				fx.append(["boss_leap", [pos, leap_to, leap_air]])
				_go(S.LEAP)
		S.LEAP:
			var u := clampf(float(t) / leap_air, 0.0, 1.0)
			pos = leap_from.lerp(leap_to, u)
			pos.y = 4.0 * leap_h * u * (1.0 - u)
			if t >= leap_air:
				pos = leap_to
				fx.append(["boss_leap_land", [pos]])
				for p in living:   # right under him
					var d := _flat(p[1] - pos)
					if d.length() < RADIUS + 1.2:
						hits.append([p[0], 22, Vector3(d.x, 0, d.y), 12.0])
				rings.append([RADIUS, {}, Vector3(pos.x, 0, pos.z), WAVE_V, 18, 1, wave_max(pos)])   # v0.12.0: map-wide
				_go(S.LEAP_LAND)
		S.LEAP_LAND:
			if t >= 40:
				orb_total = homing_count(maxi(living.size(), 1))
				orb_plan = orb_total
				orb_rot = rng.randi() % 8
				fx.append(["boss_howl", [pos, orb_total]])
				_go(S.HOWL)
		S.HOWL:
			if tp != null:
				_turn_to(tp, 0.03)
			if orb_plan > 0 and t >= 30 and not living.is_empty():
				var at := 30 + int(170.0 * float(orb_total - orb_plan) / float(maxi(orb_total - 1, 1)))
				while orb_plan > 0 and t >= at:
					_launch_orb(living, orb_total - orb_plan)
					orb_plan -= 1
					at = 30 + int(170.0 * float(orb_total - orb_plan) / float(maxi(orb_total - 1, 1)))
			if t >= 260:
				_go(S.SLAMS)
		S.SLAMS:
			if t == 30 or t == 30 + WAVE_GAP or t == 30 + 2 * WAVE_GAP:   # v0.12.0: three map-wide waves
				rings.append([RADIUS, {}, Vector3(pos.x, 0, pos.z), WAVE_V, 12 + (2 if enraged else 0), 2, wave_max(pos)])
				fx.append(["boss_slam", [pos, 0]])
			if t >= 30 + 2 * WAVE_GAP + 40:
				var best = null
				var bd := INF
				for p in living:
					var dd := (p[1] as Vector3).distance_to(pos)
					if dd < bd and not _p_helpless(p):
						bd = dd
						best = p
				if best == null and not living.is_empty():
					best = living[0]
				if best == null:
					_end_leap()
				else:
					rush_target = int(best[0])
					target = rush_target
					fx.append(["boss_paw", [pos, yaw, rush_target]])
					_go(S.PAW)
		S.PAW:
			var rp = null
			for p in living:
				if int(p[0]) == rush_target:
					rp = p[1]
			if rp != null and t < 78:
				_turn_to(rp, 0.12)
			if t % 20 == 5:
				fx.append(["boss_scrape", [pos, yaw]])
			if t >= 96:
				charge_dir = Vector2(-sin(yaw), -cos(yaw))
				charge_hit = {}
				fx.append(["boss_rush", [pos, yaw]])
				_go(S.RUSH)
		S.RUSH:
			_step(charge_dir * RUSH_V * (0.6 if slow > 0 else 1.0))
			for p in living:
				var d := _flat(p[1] - pos)
				if (d.length() < RADIUS + 1.3 or _on_spike(d, charge_dir)) and not charge_hit.has(p[0]) and (p[1] as Vector3).y < 3.5:
					charge_hit[p[0]] = true
					if _p_dash(p):   # dashed: untouchable
						fx.append(["boss_dodged", [p[1]]])
						continue
					var side := d.normalized() * 0.5
					var dir := Vector3(charge_dir.x + side.x, 0, charge_dir.y + side.y).normalized()
					hits.append([p[0], 35 if enraged else 30, dir, 0.0])
					launches.append([p[0], dir])
			_trample_bystanders(RADIUS + 1.3, 30)
			var past := true
			for p in living:
				if int(p[0]) == rush_target:
					past = _flat(p[1] - pos).dot(charge_dir) < -8.0
			if t >= 70 or (t > 20 and past) or _flat(pos - arena_c()).length() > WorldLayout.ARENA_R + 7.0:
				fx.append(["boss_skid", [pos, yaw]])
				_go(S.RECOVER)
		S.HOME:   # v0.12.0: nobody near him, far from home: he gallops back to the arena
			var hd := _flat(arena_c() - pos)
			_turn_to(arena_c(), 0.1)
			_step(hd.normalized() * GALLOP * 0.75 * speed_k())
			if t % 24 == 0:
				fx.append(["boss_hoof", [pos, true]])
			if hd.length() < WorldLayout.ARENA_R * 0.6 or _nearest_living(living) < HOME_NEAR * 0.75:
				_after_move()
		S.TREE:   # v0.12.0: he goes for a tree, lowers his horns and splinters it
			if tree_target < 0 or not _tree_alive(tree_target) or t > 360:
				tree_target = -1
				_after()
			else:
				var tpos := _tree_pos(tree_target)
				var rel := _flat(tpos - pos)
				if rep == 0:
					_turn_to(tpos, 0.12)
					if rel.length() > RADIUS + 1.6:
						_step(rel.normalized() * WALK * 1.4 * speed_k())
					else:
						rep = 1
						t = 0
						fx.append(["boss_gore_wind", [pos, yaw]])
				elif t >= 28:
					_fell(tree_target, Vector3(rel.x, 0, rel.y))
					fx.append(["boss_gore", [pos, yaw]])
					tree_target = -1
					rep = 0
					_after()
		S.RECOVER:
			if t == 20:
				fx.append(["boss_pant", [pos]])
			if t >= 70:
				_end_leap()


## v0.12.0 the arena is his home. After a far leap he works his way back while he fights: in the moments between
## attacks (idle, walking, strafing, backing off, turning, recovering) he drifts homeward, faster the further he is
## (up to HOME_DRIFT m/s); his attacks, targets and trees are chosen as always. With nobody within HOME_NEAR (40 m)
## he gallops home outright (S.HOME). No leash, no teleport; he walks through pillars and trunks, so nothing traps him.
const HOME_NEAR := 40.0
const HOME_DRIFT := 16.0


func _far_from_home() -> float:
	return maxf(_flat(pos - arena_c()).length() - WorldLayout.ARENA_R, 0.0)


func _nearest_living(living: Array) -> float:
	var m := INF
	for p in living:
		m = minf(m, _flat((p[1] as Vector3) - pos).length())
	return m


func _drift_home(_living: Array) -> void:
	var far := _far_from_home()
	if far <= 0.0 or state not in [S.IDLE, S.WALK, S.STRAFE, S.BACKOFF, S.TURN, S.RECOVER, S.TREE, S.STAGGER]:
		return
	var hd := _flat(arena_c() - pos).normalized()
	_step(hd * HOME_DRIFT * clampf(far / 30.0, 0.35, 1.0))


## v0.12.0 Thunderhorn knows apples heal. Net fills `trees` ([tree index, position] of the standing trees round the
## arena) and `apples` ([fruit id, position] on the ground there) each tick, and bumps `eaten` when a fighter eats one;
## he answers with `felled` ([tree, direction]) and `splats` (fruit ids), which Net passes to Ecology.
##  - Now and then (TREE_CD apart; more likely when someone is below half health or has just eaten) he goes for the
##    nearest tree within 24 m, gores it and it falls (S.TREE): no more apples from it this fight.
##  - Lining up a charge, he aims through a tree that stands near his line to the target (within 3 m of it, short of
##    the target): `_tree_on_line`; anything his charge or rush runs through is felled.
##  - Apples under his hooves while he moves are trampled; near an apple (APPLE_CD apart, shorter when they're low or
##    eating) he stomps it to mush, or bucks and stomps everything within 5 m.
const TREE_CD := 15 * 60
const APPLE_CD := 4 * 60
var trees: Array = []
var apples: Array = []
var eaten := 0.0
var felled: Array = []
var splats: Array = []
var tree_cd := 6 * 60
var apple_cd := 0
var tree_target := -1
var via_tree = null


func _tree_alive(i: int) -> bool:
	for tr in trees:
		if int(tr[0]) == i:
			return true
	return false


func _tree_pos(i: int) -> Vector3:
	for tr in trees:
		if int(tr[0]) == i:
			return tr[1]
	return pos


func _fell(i: int, dir: Vector3) -> void:
	felled.append([i, dir])
	for k in range(trees.size() - 1, -1, -1):
		if int(trees[k][0]) == i:
			trees.remove_at(k)


func _pressure(living: Array) -> float:
	var low := 0.0
	for p in living:
		if _p_hp(p) < Sim.MAX_HP / 2:
			low = 1.0
	return low + minf(eaten, 1.0)


## A standing tree near his line to the target (and short of it): where to aim so the charge goes through it.
func _tree_on_line(tp):
	if tp == null or rng.randf() > 0.7:
		return null
	var to := _flat(tp - pos)
	if to.length() < 0.1:
		return null
	var best = null
	var best_d := 3.0
	for tr in trees:
		var rel := _flat((tr[1] as Vector3) - pos)
		var along := rel.dot(to.normalized())
		if along < 4.0 or along > to.length() + 2.0:
			continue
		var side := absf(rel.cross(to.normalized()))
		if side < best_d:
			best_d = side
			best = tr[1]
	return best


func _trees_and_apples(living: Array) -> void:
	eaten *= 0.996
	if tree_cd > 0:
		tree_cd -= 1
	if apple_cd > 0:
		apple_cd -= 1
	if state in [S.CHARGE, S.RUSH]:   # smashing through
		for tr in trees.duplicate():
			if _flat((tr[1] as Vector3) - pos).length() < RADIUS + 0.7:
				_fell(int(tr[0]), Vector3(charge_dir.x, 0, charge_dir.y))
				fx.append(["boss_skid", [pos, yaw]])
	if state in [S.LEAP, S.ENTER, S.DEATH]:
		return
	var moving := state in [S.CHARGE, S.RUSH, S.WALK, S.STRAFE, S.BACKOFF, S.LUNGE, S.TREE, S.HOP]
	for a in apples:
		var d := _flat((a[1] as Vector3) - pos).length()
		if moving and d < RADIUS * 0.8 and not int(a[0]) in splats:
			splats.append(int(a[0]))
	if apple_cd == 0 and state in [S.IDLE, S.WALK, S.STRAFE, S.TURN]:
		var near := false
		for a in apples:
			if _flat((a[1] as Vector3) - pos).length() < RADIUS + 2.2:
				near = true
		if near:
			var buck := rng.randf() < 0.35
			var r := 5.0 if buck else RADIUS + 2.4
			for a in apples:
				if _flat((a[1] as Vector3) - pos).length() < r and not int(a[0]) in splats:
					splats.append(int(a[0]))
			fx.append(["boss_snort", [pos]] if buck else ["boss_scrape", [pos, yaw]])
			apple_cd = int(APPLE_CD / (1.0 + _pressure(living)))


## Go for a tree now? (from _choose)
func _want_tree(living: Array) -> bool:
	if tree_cd > 0 or trees.is_empty() or in_sequence():
		return false
	if rng.randf() > 0.1 + 0.3 * _pressure(living):
		return false
	var best := -1
	var best_d := 24.0
	for tr in trees:
		var d := _flat((tr[1] as Vector3) - pos).length()
		if d < best_d:
			best_d = d
			best = int(tr[0])
	if best < 0:
		return false
	tree_target = best
	tree_cd = TREE_CD
	rep = 0
	_go(S.TREE)
	fx.append(["boss_snort", [pos]])
	return true


## v0.12.0: challengers and corrupted minions caught in a charge or the rush are hurt and thrown like players
## (`bystanders`: [[id, pos]] from Net; he never picks them as targets).
var bystanders: Array = []


## v0.12.0: is a point (d: flat offset from his centre) on the nose spike, HORN_REACH ahead along `dir`?
static func _on_spike(d: Vector2, dir: Vector2) -> bool:
	return (d - dir.normalized() * HORN_REACH).length() < SPIKE_R


func _trample_bystanders(reach: float, dmg: int) -> void:
	for b in bystanders:
		var d := _flat(b[1] - pos)
		if d.length() < reach and not charge_hit.has(b[0]) and (b[1] as Vector3).y < 3.5:
			charge_hit[b[0]] = true
			var n := d.normalized() if d.length() > 0.01 else Vector2.ZERO
			var dir := Vector3(charge_dir.x + n.x * 0.5, 0, charge_dir.y + n.y * 0.5).normalized()
			hits.append([b[0], dmg, dir, 0.0])
			launches.append([b[0], dir])


func _end_leap() -> void:
	_go(S.IDLE)
	moved = true


## A slam: a ring racing out over the ground from his front hooves, and its fx.
func _slam(speed: float, dmg: int) -> void:
	var c := Vector3(pos.x, 0, pos.z)
	rings.append([RADIUS, {}, c, speed, dmg + (3 if enraged else 0), 0])
	fx.append(["boss_stomp", [c, rings.size()]])


func _step(v: Vector2) -> void:
	pos += Vector3(v.x, 0, v.y) * Config.DT
	pos.x = clampf(pos.x, -Config.WORLD_HALF + 6, Config.WORLD_HALF - 6)
	pos.z = clampf(pos.z, -Config.WORLD_HALF + 6, Config.WORLD_HALF - 6)


## After an attack: enraged, he often goes straight into the next one; otherwise a moment's pause.
func _after() -> void:
	_go(S.IDLE)
	moved = false
	if enraged and rng.randf() < 0.45:
		t = 999   # choose at once


func _after_move() -> void:
	_go(S.IDLE)
	moved = true
	t = 999


# ================================================================ choosing
func _choose(living: Array, golems: Array) -> void:
	if want_phase > phase:   # the phase change comes first
		phase = want_phase
		plan.clear()
		_go(S.PHASE)
		fx.append(["boss_phase_wind", [pos, phase]])
		return
	if _want_leap(living):
		_start_leap(living)
		return
	if _want_tree(living):
		return
	if _far_from_home() > 0.0 and _nearest_living(living) > HOME_NEAR:
		_go(S.HOME)
		return
	if not plan.is_empty():
		_retarget(living, golems)
		var tp0 = _target_pos(living, golems)
		if tp0 != null:
			_do(str(plan.pop_front()), tp0)
		return
	_retarget(living, golems)
	var tp = _target_pos(living, golems)
	if tp == null:
		return
	var rel := _flat(tp - pos)
	var d := rel.length()
	var ang := absf(wrapf(atan2(-rel.x, -rel.y) - yaw, -PI, PI))
	var los := _los(pos + Vector3(0, HEAD_Y, 0), (tp as Vector3) + Vector3(0, 1.2, 0))
	# a manoeuvre first, now and then (never two in a row)
	if not moved:
		if ang > 1.9 and d > RADIUS + 3.0:
			_do("turn", tp)
			return
		if not los:
			_do("hop" if rng.randf() < 0.6 else "call", tp)
			return
		var r := rng.randf()
		if d < RADIUS + 2.2 and r < 0.3:
			_do("backoff", tp)
			return
		if r < 0.18:
			_do("strafe", tp)
			return
		if r < 0.26 and d > 9.0 and d < 18.0:
			_do("hop", tp)
			return
		if r < 0.34 and d > 8.0 and d < 14.0:
			_do("lunge", tp)
			return
	moved = false
	var far := 0
	if target > 0:
		far = int(far_t.get(target, 0))
	var punish := 2.0 if far > 240 else 1.0   # hanging back at range for 4 s: charges and lightning
	var casting := false
	for p in living:
		if p[0] == target and _p_cast(p):
			casting = true
	var near_golem := false
	for g in golems:
		if (g[1] as Vector3).distance_to(pos) < RADIUS + 2.5:
			near_golem = true
	var close := RADIUS + 4.0
	var w := {
		"charge": (3.0 if d > 14.0 else (1.4 if d > close else 0.2)) * punish,
		"call": ((2.5 if d > 14.0 else 0.8) + (1.0 if casting else 0.0)) * punish,
		"balls": (2.0 if d > 14.0 else (1.2 if d > close else 0.4)) + (1.0 if casting else 0.0),
		"beam": 2.5 if d > close and d < 20.0 else 0.4,
		"stomp": (3.0 if d < close + 2.0 else 0.4) + (3.0 if near_golem else 0.0),
		"roar": 0.9 if d < 14.0 else 0.2,
		"gore": 3.0 if d < close and ang < 0.8 else 0.0,
		"tail": (4.0 if ang > 0.9 else 1.0) if d < close + 1.0 else 0.0,
	}
	for k in w.keys():
		if recent.size() > 0 and k == recent[-1]:
			w[k] *= 0.12
		elif k in recent:
			w[k] *= 0.45
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
	# the stomp and the roar want him close: he walks in first
	if pick in ["stomp", "roar"] and d > close + 3.0:
		plan = [pick]
		_go(S.WALK)
		return
	_attack(pick, tp)


func _do(name: String, tp) -> void:
	var rel := _flat(tp - pos)
	match name:
		"strafe":
			move_side = 1.0 if rng.randf() < 0.5 else -1.0
			move_len = rng.randi_range(55, 100)
			_go(S.STRAFE)
			fx.append(["boss_snort", [pos]])
		"backoff":
			move_len = rng.randi_range(40, 60)
			_go(S.BACKOFF)
			fx.append(["boss_snort", [pos]])
		"turn":
			_go(S.TURN)
		"lunge":
			_go(S.LUNGE)
		"hop":
			hop_from = Vector3(pos.x, 0, pos.z)
			hop_to = _hop_spot(tp)
			_go(S.HOP)
		_:
			_attack(name, tp)


## A pounce: off to one side of the target (and toward it if far), staying in the arena, preferring a clear view.
func _hop_spot(tp: Vector3) -> Vector3:
	var best := Vector3(pos.x, 0, pos.z)
	var best_s := -INF
	var c := arena_c()
	for i in 10:
		var a := rng.randf() * TAU
		var r := rng.randf_range(5.0, 9.0)
		var q := Vector3(pos.x + cos(a) * r, 0, pos.z + sin(a) * r)
		var off := _flat(q - c).length()
		if off > WorldLayout.ARENA_R - 2.0:
			continue
		var dt := _flat(tp - q).length()
		var s := -absf(dt - 11.0) - off * 0.05
		if _los(q + Vector3(0, HEAD_Y, 0), tp + Vector3(0, 1.2, 0)):
			s += 6.0
		if s > best_s:
			best_s = s
			best = q
	return best


func _attack(pick: String, tp) -> void:
	recent.append(pick)
	if recent.size() > 3:
		recent.pop_front()
	variant = 2 if storm else (1 if enraged else 0)
	match pick:
		"charge":
			rep = 0 if variant == 0 else (1 if variant == 1 and rng.randf() < 0.5 else (2 if variant == 2 else 0))
			_go(S.CHARGE_WIND)
			fx.append(["boss_charge_wind", [pos, yaw, rep]])
		"stomp":
			_go(S.STOMP_WIND)
			fx.append(["boss_rear", [pos, variant]])
		"beam":
			_go(S.BEAM_WIND)
			fx.append(["boss_beam_wind", [pos, variant]])
		"call":
			_go(S.CALL)
			fx.append(["boss_call", [pos, variant]])
		"roar":
			_go(S.ROAR)
			fx.append(["boss_roar_wind", [pos]])
		"balls":
			_go(S.BALLS)
		"gore":
			_go(S.GORE_WIND)
			fx.append(["boss_gore_wind", [pos, yaw]])
		"tail":
			move_side = 1.0 if rng.randf() < 0.5 else -1.0
			_go(S.TAIL_WIND)
			fx.append(["boss_tail_wind", [pos, yaw]])


# ================================================================ the Storm Leap's rules
func _want_leap(living: Array) -> bool:
	if leaps >= LEAP_MAX or living.is_empty():
		return false
	if total_t - last_leap < LEAP_GAP:
		return false
	var frac := float(hp) / float(max_hp)
	var due := 0
	for m in LEAP_HP:
		if frac <= float(m):
			due += 1
	if leap_sure < due:
		leap_sure += 1
		return true
	if leaps < 2 and leap_sure < LEAP_HP.size() and total_t - maxi(last_leap, 150) > LEAP_FALLBACK:
		leap_sure += 1
		return true
	if leap_bonus < 2 and frac < 0.92 and _doing_well(living) and rng.randf() < 0.18:
		leap_bonus += 1
		return true
	return false


## The players are doing well: average health 70% or more and little damage taken lately.
func _doing_well(living: Array) -> bool:
	var sum := 0.0
	for p in living:
		sum += float(_p_hp(p)) / float(Sim.MAX_HP)
	return sum / living.size() >= 0.7 and hurt_recent / living.size() < 15.0


func _start_leap(living: Array) -> void:
	leaps += 1
	last_leap = total_t
	plan.clear()
	rep = 0
	leap_to = _leap_spot(living)
	var arc := leap_arc(_flat(leap_to - pos).length())
	leap_h = arc[0]
	leap_air = int(arc[1])
	_go(S.LEAP_WIND)
	fx.append(["boss_leap_wind", [pos, leap_to, 90 + leap_air]])


## Where he lands (v0.12.0, Jacob: "very far across the map"): the point of the whole map furthest from every living
## player, no more than LEAP_MAX_D (200 m) from where he takes off. Candidates are a LEAP_GRID (5 m) grid over the
## world (400 x 400 m) kept LEAP_EDGE inside its edge and within 200 m of the take-off, minus anything within
## RADIUS + 1 m of an obstacle (`WorldLayout.boxes()`: pillars, trunks, the tower, the vault, the altar, the stone).
## Each scores its distance to the NEAREST living player; the highest wins (maximin). Ties within 1 cm go to the one
## nearer the arena's centre, then grid order: deterministic on the server. With nobody alive: the arena's centre.
const LEAP_GRID := 5.0
const LEAP_MARGIN := 3.0   # (kept for the arena's own spots)


static func leap_candidates(from: Vector3) -> Array:
	var lim := Config.WORLD_HALF - LEAP_EDGE
	var out := []
	var n := int(lim / LEAP_GRID)
	var boxes := WorldLayout.boxes()
	for i in range(-n, n + 1):
		for j in range(-n, n + 1):
			var q := Vector3(i * LEAP_GRID, 0, j * LEAP_GRID)
			if Vector2(q.x - from.x, q.z - from.z).length() > LEAP_MAX_D:
				continue
			var blocked := false
			for b: WorldLayout.Box in boxes:
				var nx := clampf(q.x, b.cx - b.hx, b.cx + b.hx)
				var nz := clampf(q.z, b.cz - b.hz, b.cz + b.hz)
				if Vector2(q.x - nx, q.z - nz).length() < RADIUS + 1.0:
					blocked = true
					break
			if not blocked:
				out.append(q)
	return out


## The smallest flat distance from q to any of the points.
static func min_dist(q: Vector3, pts: Array) -> float:
	var m := INF
	for p: Vector3 in pts:
		m = minf(m, Vector2(p.x - q.x, p.z - q.z).length())
	return m


static func maximin_spot(pts: Array, from: Vector3) -> Vector3:
	var c := arena_c()
	if pts.is_empty():
		return c
	var best := c
	var best_s := -INF
	var best_c := INF
	for q: Vector3 in leap_candidates(from):
		var s := min_dist(q, pts)
		var dc := Vector2(q.x - c.x, q.z - c.z).length()
		if s > best_s + 0.01 or (absf(s - best_s) <= 0.01 and dc < best_c):
			best_s = maxf(s, best_s)
			best_c = dc
			best = q
	return best


## The arc for a leap of d metres: [apex (m), ticks in the air]. 34 m / 2.25 s for a short one, growing to
## 75 m / 3.4 s for a 200 m bound.
static func leap_arc(d: float) -> Array:
	var k := clampf((d - 20.0) / (LEAP_MAX_D - 20.0), 0.0, 1.0)
	return [lerpf(LEAP_H, 75.0, k), int(lerpf(LEAP_AIR, 205.0, k))]


func _leap_spot(living: Array) -> Vector3:
	var pts := []
	for p in living:
		pts.append(p[1] as Vector3)
	return maximin_spot(pts, Vector3(pos.x, 0, pos.z))


# ================================================================ targeting
func _track(living: Array) -> void:
	hurt_recent *= 0.9992
	for k in threat.keys():
		threat[k] = float(threat[k]) * 0.9985
	for p in living:
		var id: int = p[0]
		var h := _p_hp(p)
		if last_hp.has(id) and h < int(last_hp[id]):
			hurt_recent += int(last_hp[id]) - h
		last_hp[id] = h
		var at: Vector3 = p[1]
		if last_p.has(id):
			var v: Vector3 = (at - (last_p[id] as Vector3)) / Config.DT
			if v.length() > 30.0:   # a teleport, not a run
				v = Vector3.ZERO
			pvel[id] = (pvel.get(id, Vector3.ZERO) as Vector3).lerp(v, 0.15)
		last_p[id] = at
		if _flat((p[1] as Vector3) - pos).length() > 15.0:
			far_t[id] = int(far_t.get(id, 0)) + 1
		else:
			far_t[id] = maxi(int(far_t.get(id, 0)) - 2, 0)
	if target > 0:
		attention[target] = int(attention.get(target, 0)) + 1
		focus_t += 1


## Who he goes after (see the header): scores every living player; a golem right in his face counts too.
func _retarget(living: Array, golems: Array) -> void:
	var best := 0
	var best_s := -INF
	var tot := 0.0
	for p in living:
		tot += float(attention.get(p[0], 0))
	var share := tot / maxf(living.size(), 1)
	for p in living:
		var id: int = p[0]
		var at: Vector3 = p[1]
		var d := _flat(at - pos).length()
		var s := -d * 0.25
		s += float(threat.get(id, 0.0)) * 0.05 + float(damage_by.get(id, 0)) * 0.004
		if int(far_t.get(id, 0)) > 240:
			s += 2.0
		if _p_cast(p):
			s += 1.5
		if _p_helpless(p):
			s -= 4.0   # he lets them get up
		elif _p_hp(p) < 35:
			s += 2.0
		if not _los(pos + Vector3(0, HEAD_Y, 0), at + Vector3(0, 1.2, 0)):
			s -= 4.0
		if living.size() >= 2:
			s -= (float(attention.get(id, 0)) - share) / 60.0 * 0.35
			if id == target:
				s += 1.0 if focus_t < 360 else -float(focus_t - 360) / 120.0
		s += rng.randf_range(0.0, 2.0)
		if s > best_s:
			best_s = s
			best = id
	for g in golems:
		var d := (g[1] as Vector3).distance_to(pos)
		if d < RADIUS + 1.5 and -d + 2.0 > best_s:
			best_s = -d + 2.0
			best = -1000 - int(g[0])
	if best != target:
		focus_t = 0
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


func _los(a: Vector3, b: Vector3) -> bool:
	var d := b - a
	var l := d.length()
	if l < 0.5:
		return true
	return WorldLayout.ray_hit(a, d / l, l) >= l - 0.3


func _turn_to(tp: Vector3, rate: float) -> void:
	var d := _flat(tp - pos)
	if d.length() > 0.1:
		yaw = lerp_angle(yaw, atan2(-d.x, -d.y), rate * speed_k())


# ================================================================ rings, balls, orbs
## Rings race out over the ground; they only hit those on the ground (jump them). [r, hit, centre, speed, dmg, kind]
func _tick_rings(living: Array, golems: Array) -> void:
	for r in rings:
		r[0] = float(r[0]) + float(r[3]) * Config.DT
		var c: Vector3 = r[2]
		for p in living:
			var dp: Vector3 = p[1]
			var d := _flat(dp - c).length()
			if absf(d - float(r[0])) < 0.7 and dp.y < c.y + 0.5 and not (r[1] as Dictionary).has(p[0]):
				r[1][p[0]] = true
				hits.append([p[0], int(r[4]), Vector3(dp.x - c.x, 0, dp.z - c.z), 7.0])
		for g in golems:
			var d := _flat((g[1] as Vector3) - c).length()
			if absf(d - float(r[0])) < 0.7 and not (r[1] as Dictionary).has(-1000 - int(g[0])):
				r[1][-1000 - int(g[0])] = true
				hits.append([-1000 - int(g[0]), 13, Vector3.ZERO, 0.0])
	rings = rings.filter(func(r): return float(r[0]) < (float(r[6]) if r.size() > 6 else 24.0))


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
				if b[3]:
					zaps.append([near[0], 10, b[1], bool(near[3])])
				else:
					hits.append([near[0], 12, b[1], 3.0])
				fx.append(["boss_ball_pop", [b[0], b[3]]])
				b[2] = 0
		b[0] = (b[0] as Vector3) + (b[1] as Vector3) * Config.DT
	balls = balls.filter(func(b): return int(b[2]) > 0)


## The i-th orb of the howl: split evenly (round robin from a random start), flung up out of his back.
func _launch_orb(living: Array, i: int) -> void:
	var p: Array = living[(i + orb_rot) % living.size()]
	var a := rng.randf() * TAU
	var from := pos + Vector3(rng.randf_range(-1.5, 1.5), HEIGHT - 0.8, rng.randf_range(-1.5, 1.5))
	var v := Vector3(cos(a) * 3.0, 7.0, sin(a) * 3.0)
	# v0.12.0 after a far leap: enough life to cross the distance (at the far cruise speed), never less than before
	var far := _flat((p[1] as Vector3) - pos).length()
	orbs.append([from, v, int(p[0]), maxi(ORB_LIFE, int(far / ORB_FAR_V * 60.0) + 240), 0, false])
	orb_sent[int(p[0])] = int(orb_sent.get(int(p[0]), 0)) + 1


func _tick_orbs(living: Array) -> void:
	for o in orbs:
		o[3] = int(o[3]) - 1
		o[4] = int(o[4]) + 1
		var op: Vector3 = o[0]
		var ov: Vector3 = o[1]
		if o[5]:   # spent (bounced): drifting, fading
			ov *= 0.97
		else:
			var tgt = null
			for p in living:
				if int(p[0]) == int(o[2]):
					tgt = p
			if tgt == null and not living.is_empty():   # their target fell: the nearest instead
				var nd := INF
				for p in living:
					var dd := (p[1] as Vector3).distance_to(op)
					if dd < nd:
						nd = dd
						tgt = p
				o[2] = int(tgt[0])
			# v0.12.0: far from its target (after a far leap) it cruises faster, then slows to the usual dodgeable
			# top speed for the last ORB_SLOW_R metres
			var top := ORB_FAR_V if tgt != null and (tgt[1] as Vector3).distance_to(op) > ORB_SLOW_R else ORB_VMAX
			var sp := minf(ORB_V0 + ORB_ACC * float(o[4]) * Config.DT * (3.0 if top > ORB_VMAX else 1.0), top)
			if int(o[4]) <= 24 or tgt == null:   # launching: up and out, slowing
				ov = ov * 0.96 + Vector3(0, -0.15, 0)
			else:
				# aim a little ahead of them (half the time it would take to get there): hard to outrun in a straight
				# line, but a sharp turn or a dash at the last moment still beats the turn limit
				var aim: Vector3 = (tgt[1] as Vector3) + Vector3(0, 1.0, 0)
				var tgo := clampf(aim.distance_to(op) / maxf(sp, 1.0), 0.0, 1.2)
				aim += (pvel.get(int(tgt[0]), Vector3.ZERO) as Vector3) * Vector3(1, 0, 1) * tgo * 0.6
				var want := (aim - op).normalized()
				var cur := ov.normalized() if ov.length() > 0.01 else want
				var ang := cur.angle_to(want)
				var mx := ORB_TURN * Config.DT
				var dir := want if ang <= mx else cur.slerp(want, mx / ang).normalized()
				ov = dir * sp
		op += ov * Config.DT
		op.y = maxf(op.y, 0.35)
		if _in_pillar(op):
			o[3] = 0
		if not o[5] and int(o[3]) > 0:
			for p in living:
				var at: Vector3 = p[1]
				if p[3]:   # a held shield: it bounces off
					var c := at + Vector3(0, Weapons.SHIELD_CENTER_Y, 0)
					if op.distance_to(c) < Weapons.SHIELD_RADIUS:
						var n := (op - c).normalized()
						ov = (ov - n * 2.0 * ov.dot(n)) * 0.7
						op = c + n * (Weapons.SHIELD_RADIUS + 0.08)
						o[5] = true
						o[3] = mini(int(o[3]), 50)
						zaps.append([p[0], ORB_DMG, -n, true])
						break
				elif op.distance_to(at + Vector3(0, 1.0, 0)) < 0.75:
					zaps.append([p[0], ORB_DMG, ov, false])
					fx.append(["boss_orb_pop", [op]])
					o[3] = 0
					break
		o[0] = op
		o[1] = ov
	orbs = orbs.filter(func(o): return int(o[3]) > 0)


func _in_pillar(q: Vector3) -> bool:
	for b: WorldLayout.Box in WorldLayout.boxes():
		if absf(q.x - b.cx) < b.hx and absf(q.z - b.cz) < b.hz and q.y < b.h:
			return true
	return false


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## His state, flat, for the network: [state, t, x, y, z, yaw, hp, max hp, status bits, beam angle, rings, balls, orbs,
## extra]. Rings: [r, cx, cz, kind]; balls: [pos, static]; orbs: positions as one PackedVector3Array; extra: [leap x,
## leap z, variant, phase, target, rush target, rep]. Status bits: 1 staggered, 2 slowed, 4 burning, 8 enraged,
## 16 untouchable (arriving), 32 storm.
func pack() -> Array:
	var flags := (1 if state == S.STAGGER else 0) | (2 if slow > 0 else 0) | (4 if burn > 0 else 0) | (8 if enraged else 0) \
		| (16 if state == S.ENTER else 0) | (32 if storm else 0)
	var ov := PackedVector3Array()
	for o in orbs:
		ov.append(o[0])
	return [state, t, pos.x, pos.y, pos.z, yaw, hp, max_hp, flags, beam_a,
		rings.map(func(r): return [float(r[0]), (r[2] as Vector3).x, (r[2] as Vector3).z, int(r[5])]),
		balls.map(func(b): return [b[0], b[3]]), ov,
		[leap_to.x, leap_to.z, variant, phase, target, rush_target, rep, leap_air]]
