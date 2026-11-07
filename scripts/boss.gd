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
## STUN METER (v0.12.0, replaces the old "stuns only stagger, shorter each time" rule): every wand Stun that catches
## him adds 1 (stunned()); at STUN_NEED (7) he is DAZED for STUN_TICKS (7 s): he staggers, his legs buckle, he goes
## down on his knees and side, dazed (head swaying, stars, sparks), then struggles up. He takes normal damage and does
## nothing (no attacks, no static field). The meter holds stun_hold_ticks() after the last hit, then drains a point
## every STUN_DRAIN ticks (6 s); it empties completely when he gets up (he shakes it off), and Stuns landing while he's
## down don't count. The math: the wand's Stun recharges in 300 ticks and takes 26 to cast, so one player lands at most
## one every ~5.4 s; the hold is that recharge + cast + STUN_MARGIN (2.5 s) = ~8 s, longer than the gap, so a player
## stunning him on every recharge never loses a point: 7 Stuns fill it in ~33 s; missing every 4th cast costs half a
## point each time (~49 s). Two wand players fill it in about half that. Derived from
## Weapons in code, so it stays right if the recharge changes. Nothing is immune: a charge, the rush, a beam, the Storm Leap
## (in the air he lands first, then drops; the rest of the sequence is dropped and he goes back to his normal attacks).
## It is the ONLY way to stop a charge or the rush (no spell stops them any more; frost no longer slows them): fill it
## during the wind-up, the pawing or the gallop itself. Sent as extra[8]; BossView draws it under his health bar.
##
## DODGING (v0.12.0 audit; boss_test `_dodge_tests` runs a skilled-dodger bot against each): every attack has a tell
## (WIND states, never under MIN_TELL 0.4 s even enraged with two players) and one clear answer: side-dash the charge,
## rush and gore; jump the rings and waves; leave the marked spot (called lightning, the leap's landing); outrun, dash
## or take cover from orbs and ball lightning; back off from the tail lash, the roar and the static field (its edge is
## drawn); move out of the beam's sweep, get under it near him or jump it near its far end. A dash's i-frames (Sim
## dash_ticks) cover every one of his hits (`_dodging`: the hit is dropped, the attack counts as dodged).
##
## STORM LEAP (v0.11.0), the signature sequence:
##   LEAP_WIND 1.5 s  he crouches, lightning gathers, a charge-up roar; a glowing marker shows where he will land, far
##                    up to 200 m away (v0.12.0: the point of the map furthest from every player, see _leap_spot)
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
## pull to switch grows, so nobody is hunted forever.
##
## GOLEMS (v0.12.2): every golem (players' wand golems and Stone Titans, challengers' golems) is a first-class foe.
## _retarget scores them beside the players by threat (recent damage they did him, gthreat, fading like a player's),
## distance, being in his face and standing between him and a player, with a fairness cap: once more than GOLEM_SHARE
## of his recent attention went to golems, golems are marked down hard, so a wall of golems can't soak him while the
## players hit him for free. EVERY damaging attack hurts golems in reach exactly as it hurts players (charge and rush,
## which also throw them: launches with golem ids, Net tosses them; gore; stomp and phase rings and the map-wide waves;
## the horn beam; called lightning, which also falls on the golems he's fighting; ball lightning and the homing orbs,
## which home on and hit them; the tail lash; the static field; the leap's landing). Titans take TITAN_K of it. Golem
## ids are -1000 - golem id, as everywhere; a golem he kills gives nobody level credit (Net._damage never does).
##
## Weaknesses (hurt()): Lightning x1/4 (he's made of it), Meteor x1.5, Fireball burns 3 s, Frost Nova slows a lot for
## 4 s (not a charge or the rush), wand Stuns fill the stun meter (stunned(): the only way to stop a charge or the
## rush), gravity wells can't move him. Earth Spikes are gone from the game (their charge-stopping weakness with them);
## the wand's Fog doesn't touch him at all. v0.12.3: below 60% the Duel Stone's corruption cutscene plays once (S.CUTSCENE,
## cut_due; see scripts/cutscene.gd). Health: hp_for()
## (x1.7 for two), shorter wind-ups with two or more.
class_name Boss
extends RefCounted

const ID := -5000                # its id as a damage target
const NAME := "Thunderhorn"
## Health (v0.11.0, cut by 45% in v0.12.9: Jacob, "45% less health at each stage"): BASE_HP x (1 + 0.7 per extra
## player): 3850 alone (was 7000), 6545 for two (was 11 900), 9240 for three (was 16 800). Every stage (the leaps at
## 80/55/30%, the cutscene at 60%, enrage at 1/2, the storm at 1/4) is a fraction of max_hp, so they all come 45% sooner.
## The math: a level-3 wizard's sustained damage on him, dodging half the time, is about 15 a second (mana comes back
## at 12 a second: meteors 60 for 45 mana, fireballs ~20 for 22 plus 8 a second of burning, the wand's spark
## beam 7 a second and life drain 18 every 3 s, sword cuts 8 at most every 0.6 s up close; lightning only 7).
## 3850 / 15 = ~4.3 minutes alone (was ~7.8).
const BASE_HP := 3850
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
const ORB_COMMIT := 5.0          # v0.12.0: within this of the target an orb stops steering: a sidestep beats it
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
	RUSH, RECOVER, LUNGE, TREE, HOME, DAZED, CUTSCENE }
## v0.12.0 the stun meter (header)
const STUN_NEED := 7          # Jacob: 7 wand Stuns
const STUN_TICKS := 420
const STUN_MARGIN := 150        # ticks of hold beyond the Stun's recharge + cast (stun_hold_ticks)
const STUN_DRAIN := 360          # then a point every 6 s
const STOMP_EVERY := 52          # v0.12.0 ticks between the stomp's slams (was 24: rings 0.3 s apart)
const STOMP_V := 9.5
const MIN_TELL := 24             # v0.12.0: no wind-up shorter than 0.4 s, enraged or not
var stun_m := 0.0
var stun_hold := 0
var daze_pending := false        # filled in mid-air: he drops as he lands
const SEQ := [S.LEAP_WIND, S.LEAP, S.LEAP_LAND, S.HOWL, S.SLAMS, S.PAW, S.RUSH, S.RECOVER]
const MOVES := [S.STRAFE, S.BACKOFF, S.HOP, S.TURN, S.LUNGE]
## v0.12.9 ATTACK TIMING (Jacob: "he begins his charge, but then it cuts off too soon and he begins a different
## attack"). Every attack plays its whole tell, action and recovery, one at a time:
##  - the tell (a WIND state) is as long as it was when it began (`wind_len`; enraging mid-tell no longer cuts it short);
##  - the action has a fixed length; the charge and the rush run a path planned as they set off (`charge_m` metres,
##    `charge_len` ticks, at a speed fixed then): CHARGE_D (30 m) for the charge (the glowing path BossView draws is
##    that path), the rush to its target and RUSH_OVER past; kept inside the world, and when it starts in or near the
##    arena it ends no further than CHARGE_EDGE outside it (never under CHARGE_MIN). It used to stop at once whenever he
##    was outside the arena (after a far leap, after the cutscene at the Duel Stone, at the arena's edge: most charges
##    ran 1 tick) or as soon as the target was 7 m behind him;
##  - then he recovers (REC ticks standing in IDLE: the skid, the slam settling, the lash swinging back) before he
##    chooses again, enraged or not (enraged he may go straight on once recovered; he used to skip the recovery);
##  - only the designed interrupts cut into an attack: the stun meter (dazed) and death. A big hit (60+) staggers him
##    only between attacks (`free_now`; it used to stagger him out of any attack), and the Duel Stone's cutscene waits
##    until he is free and recovered (it used to start in the middle of a beam or a stomp);
##  - a tree smashed in a charge is splintered on the run ("boss_smash"), not a skid (BossView played a stop for it).
## boss_test `_timing_tests` runs seeded fights with scripted players and checks all of it.
const REC := {S.CHARGE: 36, S.STOMP: 18, S.BEAM: 18, S.CALL: 20, S.ROAR: 12, S.BALLS: 12, S.GORE: 16, S.TAIL: 12,
	S.TREE: 20, S.HOP: 10}
const CHARGE_D := 30.0
const CHARGE_MIN := 14.0
const CHARGE_EDGE := 8.0
const RUSH_OVER := 10.0
const RUSH_MIN := 18.0
const RUSH_MAX := 34.0
const FREE := [S.IDLE, S.WALK, S.STRAFE, S.BACKOFF, S.TURN, S.LUNGE, S.HOME]
var wind_len := 0                # this tell's length (ticks), fixed as it starts
var charge_m := 0.0              # the charge's / rush's planned path (metres; while winding up: where it would go now)
var charge_len := 0              # and its ticks
var charge_v := GALLOP           # and its speed
var idle_wait := 20              # ticks in IDLE before he chooses again
var idle_rec := 0                # of which recovery (the cutscene waits for it)

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
var balls: Array = []            # [pos, vel, life, static, id]
var orbs: Array = []             # [pos, vel, target, life, age, spent, id]
var next_id := 1                 # v0.12.9 ids for balls and orbs, so clients can follow each one between updates
var rng := RandomNumberGenerator.new()
var done := false
# what the server applies this tick (Net reads and clears them)
var hits: Array = []             # [target, amount, dir, knock]
var fx: Array = []               # [kind, args]
var slows: Array = []            # [player id, ticks]
var strikes: Array = []          # [point, delay ticks]: called lightning
var zaps: Array = []             # [player id, damage, dir, blocked]: static hits
var launches: Array = []         # [player id, dir]: the rush
# v0.12.2 golems as foes (header): this tick's golems in the people format [-1000 - id, pos, alive, shielded, hp, dash,
# casting, helpless, titan]; their recent damage to him; decaying attention on golems / on players
const GOLEM_SHARE := 0.4
const TITAN_K := 0.6
var gols: Array = []
var gthreat := {}
var g_att := 0.0
var p_att := 0.0
# v0.12.3 the Duel Stone's corruption (Cutscene): armed by Net for a real fight (tests driving a bare Boss leave it off)
var cut_on := false
var cut_done := false            # it has started this fight (once only)
var cut_from := Vector3.ZERO     # where he was and which way he faced when it began
var cut_yaw0 := 0.0


func _init(at: Vector3, n_players: int, seed_v := 0) -> void:
	pos = at
	players_n = n_players
	max_hp = hp_for(n_players)
	hp = max_hp
	rng.seed = seed_v if seed_v != 0 else randi()
	fx.append(["boss_enter", [pos]])
	plan = ["strafe", "charge"]   # the opener


static func hp_for(n_players: int) -> int:
	return int(round(BASE_HP * (1.0 + HP_PER_EXTRA * (maxi(n_players, 1) - 1))))


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
	if s == S.IDLE:
		idle_rec = 0
		idle_wait = int(rng.randi_range(14, 36) * windup_k())


## v0.12.9 free to be interrupted by a non-designed event (header: ATTACK TIMING): between attacks, recovered.
func free_now() -> bool:
	return state in FREE and (state != S.IDLE or t >= idle_rec)


func in_sequence() -> bool:
	return state in SEQ


func speed_k() -> float:
	return (1.3 if enraged else 1.0) * (0.4 if slow > 0 else 1.0)


func windup_k() -> float:
	return (0.68 if enraged else 1.0) * (0.85 if players_n >= 2 else 1.0)


## Damage him (after his resistances); from: the attacker (player id, -1000 - golem id, 0); spell: the spell's name, or
## "" for weapons, golems and anything else. -> what he really took.
func hurt(amount: int, from: int, spell: String) -> int:
	if state == S.ENTER or state == S.DEATH or state == S.CUTSCENE:
		return 0
	var k := 1.0
	match spell:
		"Lightning":
			k = 0.25
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
	elif dmg >= 60 and free_now() and total_t - big_hit_t > 600:
		big_hit_t = total_t   # a really big hit staggers him (once in 10 s), only between attacks (v0.12.9)
		_go(S.STAGGER)
		t = 15
		fx.append(["boss_stagger", [pos]])
	elif dmg >= 25 and state not in [S.DAZED, S.LEAP]:
		fx.append(["boss_flinch", [pos]])   # (in an attack: a flinch of the hide, the attack goes on)
	return dmg


## v0.12.2 a golem's slam hurt him (Net calls this with what he really took): its threat, like a player's.
func note_golem_hit(golem_id: int, dmg: int) -> void:
	var k := -1000 - golem_id
	gthreat[k] = float(gthreat.get(k, 0.0)) + dmg


## Golems as Net sends them ([id, pos] and optionally titan, hp) -> foes in the people format (see `gols`).
static func golem_foes(golems: Array) -> Array:
	var out := []
	for g in golems:
		out.append([-1000 - int(g[0]), g[1], true, false, int(g[3]) if g.size() > 3 else Golems.HP, 0, false, false,
			bool(g[2]) if g.size() > 2 else false])
	return out


static func _is_golem(p: Array) -> bool:
	return int(p[0]) <= -1000


## v0.12.0 a wand Stun caught him: one point on the stun meter; at STUN_NEED he is dazed for 7 s (header).
func stunned(_now: int) -> void:
	if state in [S.ENTER, S.DEATH, S.DAZED, S.CUTSCENE]:
		return
	stun_m = minf(stun_m + 1.0, float(STUN_NEED))
	stun_hold = stun_hold_ticks()
	fx.append(["boss_stun_hit", [pos, int(stun_m)]])
	if stun_m >= STUN_NEED:
		if state == S.LEAP:
			daze_pending = true
		else:
			_daze()


## How long the meter holds after a Stun: the wand Stun's recharge + its cast + STUN_MARGIN (~8 s; see the header).
static func stun_hold_ticks() -> int:
	for sp in Weapons.get_data(Weapons.WAND).spells:
		if str(sp.name) == "Stun":
			return int(sp.get("recharge", 300)) + int(sp.get("cast", 26)) + STUN_MARGIN
	return 300 + 26 + STUN_MARGIN


## Down he goes, whatever he was doing (the meter stays full while he's down and empties as he gets up).
func _daze() -> void:
	daze_pending = false
	if state in [S.CHARGE, S.RUSH]:
		fx.append(["boss_skid", [pos, yaw]])
	rep = 0
	plan.clear()
	orb_plan = 0
	tree_target = -1
	pos.y = 0.0
	_go(S.DAZED)
	fx.append(["boss_dazed", [pos, yaw]])


## v0.12.3 the Duel Stone's corruption is due: armed, not played yet this fight, below Cutscene.CUT_HP and still
## alive, and not in the middle of something it mustn't cut into (a Storm Leap sequence, a daze or one waiting to
## land, a phase change, his arrival, v0.12.9: any attack or its recovery: he must be free_now()): those finish first.
func cut_due() -> bool:
	return cut_on and not cut_done and hp > 0 and float(hp) < Cutscene.CUT_HP * float(max_hp) and free_now() \
		and not daze_pending and pos.y < 0.01


func _start_cutscene() -> void:
	cut_done = true
	cut_from = Vector3(pos.x, 0, pos.z)
	cut_yaw0 = yaw
	pos.y = 0.0
	rings.clear()
	balls.clear()
	orbs.clear()
	plan.clear()
	rep = 0
	orb_plan = 0
	tree_target = -1
	charge_hit = {}
	_go(S.CUTSCENE)
	fx.append(["cutscene_start", [cut_from, yaw]])


## v0.12.9 how far a charge (or the rush) runs from `from` heading `yaw` (header: ATTACK TIMING): `full` metres, kept
## inside the world, and when it starts in or near the arena, ending no further than CHARGE_EDGE outside it (but never
## under CHARGE_MIN). BossView draws this path on the ground during the wind-up and the pawing.
static func charge_reach(from: Vector3, a: float, full: float) -> float:
	var dir := Vector2(-sin(a), -cos(a))
	var lim := Config.WORLD_HALF - 6.0
	var d := full
	if absf(dir.x) > 1e-4:
		d = minf(d, ((lim if dir.x > 0.0 else -lim) - from.x) / dir.x)
	if absf(dir.y) > 1e-4:
		d = minf(d, ((lim if dir.y > 0.0 else -lim) - from.z) / dir.y)
	var c := arena_c()
	var f := Vector2(from.x - c.x, from.z - c.z)
	var r := WorldLayout.ARENA_R + CHARGE_EDGE
	if f.length() <= r:
		var b := f.dot(dir)
		var s := -b + sqrt(maxf(b * b - (f.length_squared() - r * r), 0.0))   # where the line leaves that circle
		d = minf(d, maxf(s, CHARGE_MIN))
	return maxf(d, 0.0)


## v0.12.9 plan the run along charge_dir: its path (charge_reach of `full` metres), speed and ticks.
func _plan_run(full: float, v: float) -> void:
	charge_m = charge_reach(pos, atan2(-charge_dir.x, -charge_dir.y), full)
	charge_v = v
	charge_len = maxi(int(ceil(charge_m / v / Config.DT)), 1)


## The rush's full length: to its target (rp: where they are, or null) and RUSH_OVER past.
func charge_m_full(rp) -> float:
	var to: float = _flat((rp as Vector3) - pos).length() if rp != null else RUSH_MAX
	return clampf(to + RUSH_OVER, RUSH_MIN, RUSH_MAX)


## A wind-up of `base` ticks: shorter enraged and with two or more, never under MIN_TELL.
func _wind(base: int) -> int:
	return maxi(int(base * windup_k()), MIN_TELL)


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
	if state == S.CUTSCENE:   # v0.12.3: the film plays; every other clock of his is paused
		t += 1
		var at: Array = Cutscene.boss_at(t, cut_from, cut_yaw0)
		pos = at[0]
		yaw = at[1]
		if t >= Cutscene.LEN:
			fx.append(["boss_roar", [pos, 1]])
			_go(S.IDLE)
			moved = true
			idle_wait = 0   # straight back to choosing
		return
	if cut_due():
		_start_cutscene()
		return
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
	if state != S.DAZED and stun_m > 0.0:   # v0.12.0 the stun meter holds, then drains
		if stun_hold > 0:
			stun_hold -= 1
		else:
			stun_m = maxf(stun_m - 1.0 / STUN_DRAIN, 0.0)
	var living := people.filter(func(p): return p[2])
	gols = golem_foes(golems)
	var foes: Array = living + gols   # v0.12.2: everything his attacks can hurt (players and golems)
	_track(living)
	var n_hits := hits.size()
	var n_zaps := zaps.size()
	var n_launch := launches.size()
	# the static field: a shock to anyone right next to him, twice a second (not while he's dazed)
	if now % 30 == 0 and state not in [S.ENTER, S.LEAP, S.DAZED]:
		for p in foes:
			var d := _flat(p[1] - pos)
			if d.length() < RADIUS + 1.4 and (p[1] as Vector3).y < pos.y + 3.0:
				hits.append([p[0], 6 if enraged else 4, Vector3(d.x, 0, d.y), 2.0])
	# the storm, below a quarter: strikes keep falling round the arena
	if storm and now % 50 == 0 and not living.is_empty():
		var p: Array = living[rng.randi() % living.size()]
		strikes.append([(p[1] as Vector3) + Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4)), 50])
	_tick_balls(foes)
	_tick_rings(foes)
	_tick_orbs(living, foes)
	var tp = _target_pos(living, golems)
	var wk := windup_k()
	_trees_and_apples(living)
	_drift_home(living)
	_drift_trees()
	match state:
		S.ENTER:
			if t >= 150:
				fx.append(["boss_roar", [pos, 0]])
				_go(S.IDLE)
		S.IDLE:
			if tp != null:
				_turn_to(tp, 0.07)
			if t >= idle_wait:   # v0.12.9: the wait (with its recovery) is fixed as he stops (_go, _after)
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
				_step(_lean_tree((tang + radial).normalized() * WALK * speed_k(), 0.6))   # v0.12.9 toward a tree
		S.BACKOFF:  # backing away, still facing them
			if tp == null or t >= move_len:
				_after_move()
			else:
				_turn_to(tp, 0.12)
				_step(_lean_tree(-_flat(tp - pos).normalized() * WALK * 0.9 * speed_k(), 0.8))   # v0.12.9 toward a tree
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
			var cw := wind_len   # v0.12.0: never under MIN_TELL; the aim locks 16 ticks before he goes
			if tp != null and t < cw - 16:
				_turn_to(via_tree if via_tree != null else tp, 0.14)   # v0.12.0: lined up through a tree when he can
			charge_m = charge_reach(pos, yaw, CHARGE_D)   # v0.12.9: the path he will run (drawn on the ground)
			if t % 18 == 9:
				fx.append(["boss_scrape", [pos, yaw]])
			if t >= cw:
				charge_dir = Vector2(-sin(yaw), -cos(yaw))
				charge_hit = {}
				_plan_run(CHARGE_D, GALLOP * (1.3 if enraged else 1.0))
				fx.append(["boss_charge", [pos, yaw, charge_m]])
				_go(S.CHARGE)
		S.CHARGE:
			if charge_len <= 0:   # (set going directly, as the tests do)
				_plan_run(CHARGE_D, GALLOP * (1.3 if enraged else 1.0))
			_step(charge_dir * charge_v)   # v0.12.0: frost no longer slows a charge
			for p in foes:   # v0.12.2: golems too (thrown like players)
				var d := _flat(p[1] - pos)
				if (d.length() < RADIUS + 1.4 or _on_spike(d, charge_dir)) and not charge_hit.has(p[0]) and (p[1] as Vector3).y < 3.5:
					charge_hit[p[0]] = true
					var cdir := Vector3(charge_dir.x + d.normalized().x * 0.5, 0, charge_dir.y + d.normalized().y * 0.5).normalized()
					hits.append([p[0], 30 if enraged else 25, cdir, 0.0])
					launches.append([p[0], cdir])   # v0.12.0: the charge throws you too
			_trample_bystanders(RADIUS + 1.4, 25)
			if t >= charge_len:   # v0.12.9: the whole planned path, every time (header: ATTACK TIMING)
				charge_len = 0
				fx.append(["boss_skid", [pos, yaw]])
				if rep > 0:
					rep -= 1
					_go(S.CHARGE_WIND)
					wind_len = maxi(int(34 * wk), REC[S.CHARGE])   # a shorter wind-up for the next one, the skid included
					fx.append(["boss_charge_wind", [pos, yaw, rep]])
				else:
					_after()
		S.STOMP_WIND:   # he rears up
			if t >= wind_len:
				_slam(STOMP_V, 13)
				_go(S.STOMP)
		S.STOMP:   # v0.12.0: STOMP_EVERY apart at one speed, so every ring can be jumped on the beat
			var every := STOMP_EVERY
			if t % every == 0 and t / every < (4 if variant > 0 else 3):
				_slam(STOMP_V, 13)
				if variant > 0 and t / every == 3:
					rings.append([RADIUS - 1.6, {}, Vector3(pos.x, 0, pos.z), STOMP_V, 15, 0])   # the double ring
			if t >= (4 if variant > 0 else 3) * every + 12:
				_after()
		S.BEAM_WIND:    # the horns crackle and glow
			if tp != null:
				_turn_to(tp, 0.1)
			if t >= wind_len:
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
				for p in foes:
					if beam_hits(pos, beam_a, p[1], yaw):   # v0.12.0: the drawn beam, from the orb to the ground
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
				for g in gols:   # v0.12.2: and on the golems he's fighting (Net's strikes hurt golems too)
					if int(g[0]) == target or float(gthreat.get(int(g[0]), 0.0)) > 4.0:
						strikes.append([(g[1] as Vector3) * Vector3(1, 0, 1), 60])
			if t >= 60:
				_after()
		S.ROAR:
			if t == ROAR_AT:   # v0.12.0: a longer wind-up (it was 0.25 s)
				fx.append(["boss_roar", [pos, 1 if enraged else 2]])
				for p in living:
					var dd := (p[1] as Vector3).distance_to(pos)
					if dd < ROAR_R:
						slows.append([p[0], 120])
					if variant > 0 and dd < ROAR_R - 2.0:
						zaps.append([p[0], 0, (p[1] as Vector3) - pos, bool(p[3])])   # the static roar
			if t >= ROAR_AT + 45:
				_after()
		S.BALLS:
			if t == 20:
				var n := 5 if variant > 0 else 3
				for i in n:
					var a := yaw + (float(i) - (n - 1) * 0.5) * 0.5
					balls.append([pos + Vector3(-sin(a) * 3.0, HEAD_Y - 0.5, -cos(a) * 3.0), Vector3(-sin(a), 0.2, -cos(a)) * 4.0, 360, variant > 0, next_id])
				next_id += 1
				fx.append(["boss_balls", [pos, variant]])
			if t >= 45:
				_after()
		S.GORE_WIND:   # the head drops and swings back to one side
			if tp != null:
				_turn_to(tp, 0.16)
			if t >= wind_len:
				fx.append(["boss_gore", [pos, yaw]])
				_go(S.GORE)
		S.GORE:
			if t == 6:
				var fwd := Vector2(-sin(yaw), -cos(yaw))
				for p in foes:
					var d := _flat(p[1] - pos)
					if ((d.length() < RADIUS + 4.6 and d.normalized().dot(fwd) > 0.25) or _on_spike(d, fwd)) and (p[1] as Vector3).y < 4.0:
						hits.append([p[0], 20 if enraged else 16, Vector3(d.x + fwd.x, 0.3, d.y + fwd.y), 11.0])
			if t >= 24:
				_after()
		S.TAIL_WIND:   # the body coils, the tail lifts
			if t >= wind_len:
				fx.append(["boss_tail", [pos, yaw, move_side]])
				_go(S.TAIL)
		S.TAIL:
			if t < 14:
				yaw += 0.07 * move_side   # he pivots into it
			if t == 9:
				var fwd := Vector2(-sin(yaw), -cos(yaw))
				for p in foes:
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
				idle_wait = 0
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
				for p in foes:   # right under him
					var d := _flat(p[1] - pos)
					if d.length() < RADIUS + 1.2:
						hits.append([p[0], 22, Vector3(d.x, 0, d.y), 12.0])
				rings.append([RADIUS, {}, Vector3(pos.x, 0, pos.z), WAVE_V, 18, 1, wave_max(pos)])   # v0.12.0: map-wide
				_go(S.LEAP_LAND)
				if daze_pending:   # v0.12.0: the meter filled in the air: he lands and drops
					_daze()
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
			if t < 78 or charge_m <= 0.0:   # v0.12.9: the path: to them and RUSH_OVER past (drawn on the ground)
				charge_m = charge_reach(pos, yaw, charge_m_full(rp))
			if t % 20 == 5:
				fx.append(["boss_scrape", [pos, yaw]])
			if t >= 96:
				charge_dir = Vector2(-sin(yaw), -cos(yaw))
				charge_hit = {}
				_plan_run(charge_m_full(rp), RUSH_V)
				fx.append(["boss_rush", [pos, yaw, charge_m]])
				_go(S.RUSH)
		S.RUSH:
			if charge_len <= 0:   # (set going directly, as the tests do)
				var rp = null
				for p in living:
					if int(p[0]) == rush_target:
						rp = p[1]
				_plan_run(charge_m_full(rp), RUSH_V)
			_step(charge_dir * charge_v)   # v0.12.0: nor the rush (only the stun meter stops them)
			for p in foes:
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
			if t >= charge_len:   # v0.12.9: the whole planned path (it used to stop at once outside the arena: after
				charge_len = 0                         # a far leap, nearly always)
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
		S.DAZED:   # v0.12.0 stunned by the meter: down, dazed, then struggling up
			if t >= STUN_TICKS:
				stun_m = 0.0
				stun_hold = 0
				fx.append(["boss_get_up", [pos]])
				_go(S.IDLE)
				moved = true
	for i in range(n_hits, hits.size()):   # v0.12.2: Stone Titans are tougher
		if int(hits[i][0]) <= -1000:
			for g in gols:
				if int(g[0]) == int(hits[i][0]) and bool(g[8]):
					hits[i][1] = maxi(int(round(int(hits[i][1]) * TITAN_K)), 1)
	_dodging(living, n_hits, n_zaps, n_launch)


## v0.12.0: a dash's i-frames cover every one of his hits this tick (the attack already counts them as hit, so the
## same charge, ring or swing won't catch them a moment later).
func _dodging(living: Array, n_hits: int, n_zaps: int, n_launch: int) -> void:
	var dashing := {}
	for p in living:
		if _p_dash(p):
			dashing[int(p[0])] = p[1]
	if dashing.is_empty():
		return
	for i in range(hits.size() - 1, n_hits - 1, -1):
		if dashing.has(int(hits[i][0])):
			fx.append(["boss_dodged", [dashing[int(hits[i][0])]]])
			hits.remove_at(i)
	for i in range(zaps.size() - 1, n_zaps - 1, -1):
		if dashing.has(int(zaps[i][0])) and not bool(zaps[i][3]):
			zaps.remove_at(i)
	for i in range(launches.size() - 1, n_launch - 1, -1):
		if dashing.has(int(launches[i][0])):
			launches.remove_at(i)


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
##    nearest tree within TREE_GO m, gores it and it falls (S.TREE): no more apples from it this fight.
##  - v0.12.9 (Jacob: "target the fruit trees a bit more often... destroyed all of them by around 50% of his health...
##    not a focus exactly, just something he does whenever he is near a tree, and he should wander towards the rest of
##    the trees more easily while still engaging"): between attacks he drifts toward the nearest standing tree within
##    TREE_SEEK (`_tree_lure`: idling he ambles to it at TREE_DRIFT, his circling and backing off lean its way, his hops
##    land nearer it), and a tree within TREE_NEAR when he chooses is swiped on the way most of the time (TREE_NEAR_CD
##    apart). boss_test `_tree_sim_tests`: in seeded fights he has felled ~90% of the arena's five apple trees by the
##    time he has lost half his health.
##  - Lining up a charge, he aims through a tree that stands near his line to the target (within 4 m of it, short of
##    the target): `_tree_on_line`; anything his charge or rush runs through is felled.
##  - Apples under his hooves while he moves are trampled; near an apple (APPLE_CD apart, shorter when they're low or
##    eating) he stomps it to mush, or bucks and stomps everything within 5 m.
const TREE_CD := 6 * 60          # v0.12.9 (was 15 s)
const TREE_NEAR_CD := 3 * 60
const TREE_GO := 30.0
const TREE_NEAR := RADIUS + 5.0
const TREE_SEEK := 36.0
const TREE_DRIFT := 2.4
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
	if tp == null or rng.randf() > 0.85:
		return null
	var to := _flat(tp - pos)
	if to.length() < 0.1:
		return null
	var best = null
	var best_d := 4.0
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
				fx.append(["boss_smash", [tr[1], yaw]])   # v0.12.9: splintered on the run (it played a skid)
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


## v0.12.9 the nearest standing tree within TREE_SEEK (where he wanders between attacks), or null.
func _tree_lure():
	var best = null
	var best_d := TREE_SEEK
	for tr in trees:
		var d := _flat((tr[1] as Vector3) - pos).length()
		if d < best_d:
			best_d = d
			best = tr[1]
	return best


## v0.12.9 between attacks (idling) he ambles toward the nearest tree (header: knows apples heal).
func _drift_trees() -> void:
	if state != S.IDLE:
		return
	var lure = _tree_lure()
	if lure == null:
		return
	var d := _flat(lure - pos)
	if d.length() > RADIUS + 2.0:
		_step(d.normalized() * TREE_DRIFT * speed_k())


## A step direction leaning toward the tree lure (k: how much), for his manoeuvres.
func _lean_tree(dir: Vector2, k: float) -> Vector2:
	var lure = _tree_lure()
	if lure == null:
		return dir
	var d := _flat(lure - pos)
	if d.length() < RADIUS + 2.0:
		return dir
	return (dir.normalized() + d.normalized() * k).normalized() * dir.length()


## Go for a tree now? (from _choose)
func _want_tree(living: Array) -> bool:
	if trees.is_empty() or in_sequence():
		return false
	var best := -1
	var best_d := TREE_GO
	for tr in trees:
		var d := _flat((tr[1] as Vector3) - pos).length()
		if d < best_d:
			best_d = d
			best = int(tr[0])
	if best < 0:
		return false
	if best_d < TREE_NEAR:   # v0.12.9 right by one: a swipe on the way, most of the time
		if tree_cd > TREE_CD - TREE_NEAR_CD or rng.randf() > 0.6 + 0.2 * _pressure(living):
			return false
	elif tree_cd > 0 or rng.randf() > 0.25 + 0.3 * _pressure(living):
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


## v0.12.0 the horn beam's geometry, shared with BossView so the drawn beam IS the hitbox: it comes out of the orb
## just ahead of the nose spike's tip (BEAM_ORB metres out, BEAM_ORB_Y up, along where his head points: his body's
## heading turned BEAM_HEAD_K of the way to the beam's, as the neck turns the head) and slants down
## to the ground BEAM_REACH ahead of his centre; BEAM_R is the radius of its glow. A player (a capsule from 0.4 to
## 1.4 m up, radius Sim.RADIUS) is hit when it touches that segment. Close in under the orb it passes over your head;
## near its far end you can jump it; past BEAM_REACH it never reaches.
const BEAM_ORB := 7.0
const BEAM_ORB_Y := 3.9
const BEAM_REACH := 24.0
const BEAM_R := 0.75
const BEAM_HEAD_K := 0.6
const ROAR_AT := 45               # v0.12.0 the roar lands 0.75 s in (it was 0.25 s)
const ROAR_R := 12.0             # its slow reaches 12 m (was 16), the static roar 10 m (was 13)


static func beam_ends(at: Vector3, a: float, body_yaw: float) -> Array:
	var h := body_yaw + wrapf(a - body_yaw, -PI, PI) * BEAM_HEAD_K
	var d := Vector3(-sin(a), 0, -cos(a))
	var g := Vector3(at.x, 0, at.z)
	return [g + Vector3(-sin(h), 0, -cos(h)) * BEAM_ORB + Vector3(0, at.y + BEAM_ORB_Y, 0), g + d * BEAM_REACH + Vector3(0, minf(at.y, 0.0), 0)]


static func beam_hits(at: Vector3, a: float, p: Vector3, body_yaw: float) -> bool:
	var e := beam_ends(at, a, body_yaw)
	var g := Geometry3D.get_closest_points_between_segments(e[0], e[1], p + Vector3(0, 0.4, 0), p + Vector3(0, 1.4, 0))
	return (g[0] as Vector3).distance_to(g[1]) < BEAM_R + Sim.RADIUS


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


## After an attack: he recovers (REC of the attack just done: v0.12.9, header ATTACK TIMING); then enraged, he often
## goes straight into the next one; otherwise a moment's pause.
func _after() -> void:
	var rec := int(REC.get(state, 0))
	_go(S.IDLE)
	moved = false
	idle_rec = rec
	if enraged and rng.randf() < 0.45:
		idle_wait = rec   # choose as soon as he's recovered
	else:
		idle_wait += rec


func _after_move() -> void:
	var rec := int(REC.get(state, 0))   # (the hop's landing settles first)
	_go(S.IDLE)
	moved = true
	idle_rec = rec
	idle_wait = rec


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
		var lure = _tree_lure()   # v0.12.9 landing nearer a tree
		if lure != null:
			s -= _flat(lure - q).length() * 0.35
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
			wind_len = _wind(50)
			charge_m = charge_reach(pos, yaw, CHARGE_D)
			fx.append(["boss_charge_wind", [pos, yaw, rep]])
		"stomp":
			_go(S.STOMP_WIND)
			wind_len = _wind(48)
			fx.append(["boss_rear", [pos, variant]])
		"beam":
			_go(S.BEAM_WIND)
			wind_len = _wind(60)
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
			wind_len = _wind(32)
			fx.append(["boss_gore_wind", [pos, yaw]])
		"tail":
			move_side = 1.0 if rng.randf() < 0.5 else -1.0
			_go(S.TAIL_WIND)
			wind_len = _wind(30)
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
	for k in gthreat.keys():
		gthreat[k] = float(gthreat[k]) * 0.9985
	g_att *= 0.997   # v0.12.2: the golem / player split of his recent attention (~5 s memory)
	p_att *= 0.997
	if target <= -1000:
		g_att += 1.0
	elif target > 0:
		p_att += 1.0
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
	if target != 0:
		focus_t += 1


## Who he goes after (see the header): scores every living player and every golem.
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
	# v0.12.2 golems, first-class: threat, distance, in his face, standing between him and a player; capped (header)
	var g_share := g_att / maxf(g_att + p_att, 1.0)
	for g in golem_foes(golems):
		var id: int = g[0]
		var at: Vector3 = g[1]
		var d := _flat(at - pos).length()
		var s := -d * 0.25 + float(gthreat.get(id, 0.0)) * 0.05
		if d < RADIUS + 2.5:
			s += 1.5
		for p in living:   # in the way: on his line to a player, nearer than them
			var to := _flat((p[1] as Vector3) - pos)
			var along := _flat(at - pos).dot(to.normalized()) if to.length() > 0.1 else -1.0
			if along > 0.0 and along < to.length() and absf(_flat(at - pos).cross(to.normalized())) < 3.0:
				s += 2.0
				break
		if not _los(pos + Vector3(0, HEAD_Y, 0), at + Vector3(0, 1.0, 0)):
			s -= 4.0
		if not living.is_empty() and g_share > GOLEM_SHARE:
			s -= (g_share - GOLEM_SHARE) * 30.0   # the fairness cap: the players get his attention back
		if id == target:
			s += 1.0 if focus_t < 360 else -float(focus_t - 360) / 120.0
		s += rng.randf_range(0.0, 2.0)
		if s > best_s:
			best_s = s
			best = id
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
func _tick_rings(foes: Array) -> void:   # v0.12.2: players and golems alike
	for r in rings:
		r[0] = float(r[0]) + float(r[3]) * Config.DT
		var c: Vector3 = r[2]
		for p in foes:
			var dp: Vector3 = p[1]
			var d := _flat(dp - c).length()
			if absf(d - float(r[0])) < 0.7 and dp.y < c.y + 0.5 and not (r[1] as Dictionary).has(p[0]):
				r[1][p[0]] = true
				hits.append([p[0], int(r[4]), Vector3(dp.x - c.x, 0, dp.z - c.z), 7.0])
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
			if nd < 1.0 and not _p_dash(near):   # v0.12.0: a dash slips through
				if _is_golem(near):   # v0.12.2: a golem just takes the hit (no Static on stone)
					hits.append([near[0], 10 if b[3] else 12, b[1], 0.0])
				elif b[3]:
					zaps.append([near[0], 10, b[1], bool(near[3])])
				else:
					hits.append([near[0], 12, b[1], 3.0])
				fx.append(["boss_ball_pop", [b[0], b[3]]])
				b[2] = 0
		b[0] = (b[0] as Vector3) + (b[1] as Vector3) * Config.DT
	balls = balls.filter(func(b): return int(b[2]) > 0)


## The i-th orb of the howl: split evenly (round robin from a random start), flung up out of his back.
func _launch_orb(living: Array, i: int) -> void:
	var pool := living.duplicate()   # v0.12.2: the golems he's fighting get their share too
	for g in gols:
		if int(g[0]) == target or float(gthreat.get(int(g[0]), 0.0)) > 4.0:
			pool.append(g)
	var p: Array = pool[(i + orb_rot) % pool.size()]
	var a := rng.randf() * TAU
	var from := pos + Vector3(rng.randf_range(-1.5, 1.5), HEIGHT - 0.8, rng.randf_range(-1.5, 1.5))
	var v := Vector3(cos(a) * 3.0, 7.0, sin(a) * 3.0)
	# v0.12.0 after a far leap: enough life to cross the distance (at the far cruise speed), never less than before
	var far := _flat((p[1] as Vector3) - pos).length()
	orbs.append([from, v, int(p[0]), maxi(ORB_LIFE, int(far / ORB_FAR_V * 60.0) + 240), 0, false, next_id])
	next_id += 1
	orb_sent[int(p[0])] = int(orb_sent.get(int(p[0]), 0)) + 1


func _tick_orbs(living: Array, foes: Array) -> void:   # v0.12.2: they home on and hit golems too
	for o in orbs:
		o[3] = int(o[3]) - 1
		o[4] = int(o[4]) + 1
		var op: Vector3 = o[0]
		var ov: Vector3 = o[1]
		if o[5]:   # spent (bounced): drifting, fading
			ov *= 0.97
		else:
			var tgt = null
			for p in foes:
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
				if op.distance_to((tgt[1] as Vector3) + Vector3(0, 1.0, 0)) < ORB_COMMIT and ov.length() > 0.01:
					mx = 0.0   # v0.12.0 committed: straight on for the last few metres
				var dir := want if ang <= mx else cur.slerp(want, mx / ang).normalized()
				ov = dir * sp
		op += ov * Config.DT
		op.y = maxf(op.y, 0.35)
		if _in_pillar(op):
			o[3] = 0
		if not o[5] and int(o[3]) > 0:
			for p in foes:
				var at: Vector3 = p[1]
				if _is_golem(p):
					if op.distance_to(at + Vector3(0, 0.8, 0)) < 0.85:
						hits.append([p[0], ORB_DMG, ov, 0.0])
						fx.append(["boss_orb_pop", [op]])
						o[3] = 0
						break
				elif p[3]:   # a held shield: it bounces off
					var c := at + Vector3(0, Weapons.SHIELD_CENTER_Y, 0)
					if op.distance_to(c) < Weapons.SHIELD_RADIUS:
						var n := (op - c).normalized()
						ov = (ov - n * 2.0 * ov.dot(n)) * 0.7
						op = c + n * (Weapons.SHIELD_RADIUS + 0.08)
						o[5] = true
						o[3] = mini(int(o[3]), 50)
						zaps.append([p[0], ORB_DMG, -n, true])
						break
				elif op.distance_to(at + Vector3(0, 1.0, 0)) < 0.75 and not _p_dash(p):   # v0.12.0: a dash slips through
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
## extra, orb ids]. Rings: [r, cx, cz, kind, speed (v0.12.9)]; balls: [pos, static, id (v0.12.9)]; orbs: positions as
## one PackedVector3Array, their ids (v0.12.9) as a PackedInt32Array after extra; extra: [leap x,
## leap z, variant, phase, target, rush target, rep, leap air ticks, stun meter (v0.12.0, 0..STUN_NEED), the charge's
## or rush's path in metres (v0.12.9), this tell's length in ticks (v0.12.9)]. Status bits:
## 1 staggered, 2 slowed, 4 burning, 8 enraged, 16 untouchable (arriving), 32 storm, 64 dazed (v0.12.0), 128 the Duel
## Stone is corrupted (v0.12.3: from the slam in the cutscene until the fight ends).
func pack() -> Array:
	var flags := (1 if state == S.STAGGER else 0) | (2 if slow > 0 else 0) | (4 if burn > 0 else 0) | (8 if enraged else 0) \
		| (16 if state == S.ENTER or state == S.CUTSCENE else 0) | (32 if storm else 0) | (64 if state == S.DAZED else 0) \
		| (128 if cut_done and not (state == S.CUTSCENE and t < Cutscene.CORRUPT_AT) else 0)
	var ov := PackedVector3Array()
	var oi := PackedInt32Array()
	for o in orbs:
		ov.append(o[0])
		oi.append(int(o[6]) if o.size() > 6 else 0)
	return [state, t, pos.x, pos.y, pos.z, yaw, hp, max_hp, flags, beam_a,
		rings.map(func(r): return [float(r[0]), (r[2] as Vector3).x, (r[2] as Vector3).z, int(r[5]), float(r[3])]),
		balls.map(func(b): return [b[0], b[3], int(b[4]) if b.size() > 4 else 0]), ov,
		[leap_to.x, leap_to.z, variant, phase, target, rush_target, rep, leap_air, snappedf(stun_m, 0.01),
			snappedf(charge_m, 0.01), wind_len], oi]
