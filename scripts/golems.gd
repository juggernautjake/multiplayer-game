## Stone golems (Jacob 2026-11-04), summoned with the magic wand. Run by the server only; every few ticks their state
## goes to every client (Net.golem_states) and GolemView draws and animates them.
##
## Each golem rises out of the ground, then picks a target: the nearest player its summoner may fight (both with PvP
## on) or another summoner's golem, within 25 m; with none, a practice dummy within 14 m; with nothing, it follows its
## summoner. Six golems per summoner at most (one every 10 s: the wand's recharge). It walks there round pillars and trunks (steering: the first free direction fanning out from the
## straight line, with a side it keeps to, and a detour when it notices it is stuck), and as it closes in it raises
## both arms and slams them down, still moving after its target while it swings. It crumbles when its health runs out or after 45 s.
##
## v0.8.0, smarter: several golems after the same target spread round it (each takes its own side) instead of queueing
## behind one another, and keep a little apart from each other; from 3-5.5 m away a small golem may leap at its target
## and come down on it (then can't leap again for 4 s); with nothing to fight they stand guard in a ring round their
## summoner, facing out; and they look further ahead for pillars so they curve round them sooner.
class_name Golems
extends RefCounted

const HP := 40
const SPEED := 8.0             # m/s: faster than a walking player (6), slower than a sprinting one (10)
const RADIUS := 0.3
const REACH := 1.1            # metres from its centre to the edge of what it hits
const WINDUP := 28            # ticks from raising its arms to the slam landing
const ATTACK := 52            # ticks of the whole attack
const COOLDOWN := 30
const DAMAGE := 8
const KNOCK := 5.0
const LIFE := 45 * 60
const RISE := 45
const DIE := 70
const MAX_PER_OWNER := 6
const ATTACK_SPEED := 0.5       # share of its speed after the slam lands (it runs flat out while winding up)
const START_AT := 0.9           # metres beyond its reach where it starts a swing on the run
const SENSE := 25.0            # metres: how far off it notices someone to chase
const SCALE := 0.6             # its size next to a person (small and quick)
## The Stone Titan (the wand's ultimate): one per summoner, not counted among the six; big, slow, tough, and its slam
## crushes everyone near where it lands, not just its target.
const TITAN_HP := 150
const TITAN_SPEED := 5.5
const TITAN_REACH := 1.9
const TITAN_DAMAGE := 18
const TITAN_KNOCK := 8.0
const TITAN_SLAM := 2.8        # metres round the slam's landing point that it crushes
const TITAN_SCALE := 1.5
const TITAN_LIFE := 30 * 60
enum State { RISE, IDLE, WALK, ATTACK, DIE, STUN, LEAP }
const LEAP_MIN := 3.0          # metres from its target where a leap can start
const LEAP_MAX := 5.5
const LEAP_T := 26             # ticks in the air
const LEAP_SPEED := 13.0       # m/s at most across the ground
const LEAP_DAMAGE := 10
const LEAP_CD := 240
const SPREAD := 0.75           # radians between golems closing in on the same target
const GUARD_R := 2.2           # the guard ring round the summoner
## v0.12.0: golems fight for their summoner. They always go for Thunderhorn, Duel Stone challengers, corrupted minions
## and those enemies' golems: first whatever has hurt their summoner in the last few seconds, else the nearest, but
## never further than LEASH from the summoner. Other players and their golems only with PvP on (both sides) and only
## after that player hurt the summoner or one of the summoner's golems in the last GRUDGE ticks (the grudge then
## expires). A challenger's golems fight for the challenger: against the players and the players' golems.
const LEASH := 18.0
const GRUDGE := 12 * 60
const ATTACKING := 4 * 60      # ticks a hit on the summoner keeps that attacker first in line
enum Who { PLAYER, NPC, BOSS, NEUTRAL }   # v0.12.6 NEUTRAL: a dev-console unit that fights only whoever hurt it
## v0.12.2 orders (G, the golem wheel, middle mouse): one standing order per summoner, for all their golems and the
## titan. FOLLOW (the default): the guard ring round the summoner, fighting within LEASH of them. STAY / GOTO: hold
## a point (where the summoner stood / the crosshair's spot on the ground): the guard ring round it, fighting only
## enemies within HOLD_R of it. ATTACK: everyone after one target first (whatever else is near), until it dies or
## stays more than ORDER_LEASH from the summoner for ORDER_OUT ticks; then FOLLOW. A player can be ordered against
## only when both have PvP on (no grudge needed: the order is the reason), and the order ends if either turns it off.
## REGROUP: drop everything and come back to the summoner; FOLLOW once they're all close or after REGROUP_T.
enum Order { FOLLOW, STAY, GOTO, ATTACK, REGROUP }
const ORDER_NAMES := ["follow", "stay", "go", "attack", "regroup"]
const HOLD_R := 8.0
const ORDER_LEASH := 30.0
const ORDER_OUT := 5 * 60
const REGROUP_T := 4 * 60
const REGROUP_NEAR := 3.5
const GOTO_MAX := 60.0         # metres from the summoner a Go there point may be


## A summoner's standing order.
class Ord:
	var mode := Order.FOLLOW
	var point := Vector3.ZERO
	var target := 0
	var t0 := 0
	var out_t := 0             # ticks the attack target has been out of the leash


class G:
	var id := 0
	var owner := 0
	var pos := Vector3.ZERO
	var yaw := 0.0
	var hp := HP
	var state := State.RISE
	var t := 0                # ticks in this state
	var born := 0
	var target := 0           # player id, -(dummy + 1), or -1000 - golem id; 0 none
	var atk_cd := 0
	var side := 1.0           # which way it goes round things
	var detour := 0           # ticks left going round something it got stuck on
	var check_pos := Vector3.ZERO
	var stun := 0
	var titan := false
	var max_hp := HP
	var leap_cd := 0
	var leap_step := Vector2.ZERO   # metres a tick while leaping
	var slot := 0.0                 # its angle offset round a shared target
	var guard_a := 0.0              # its place in the guard ring
	var fog_t := 0                  # v0.12.0: ticks of confusion left (lost in an enemy's fog, and ~1 s after)
	var fog_mode := ""              # "thrash" or "stumble" while confused
	var fog_roll := 0               # ticks until it picks again
	var wander := 0.0               # its stumbling heading


## v0.12.0 the wand's Fog (see Fog): Net sets these before each tick. A golem whose summoner is an enemy of a fog's
## caster can't see into it; lost inside one it's confused (thrashes at nothing or stumbles about, re-picking every
## FOG_ROLL ticks, still confused FOG_RECOVER ticks after it gets out); outside it steers round.
var fogs: Array = []
var fog_pvp := {}
const FOG_ROLL := 120
const FOG_RECOVER := 60


var list := {}        # id -> G
var next_id := 1
var harm := {}        # victim player id -> { attacker id: tick of the last hit on them or their golems }
var _now := 0
var orders := {}      # summoner id -> Ord (only while it isn't FOLLOW)
var orders_dirty := {}   # summoner ids whose order changed since Net last sent them
var _pvp := {}
var _where := {}


## How many golems (and titan) a summoner has standing.
func count(owner: int) -> int:
	var n := 0
	for g: G in list.values():
		if g.owner == owner and g.state != State.DIE:
			n += 1
	return n


## The summoner's order as [mode, point, target].
func order_of(owner: int) -> Array:
	var o: Ord = orders.get(owner, null)
	return [Order.FOLLOW, Vector3.ZERO, 0] if o == null else [o.mode, o.point, o.target]


## May `owner`'s golems be ordered against `target` (a player, challenger, Thunderhorn, golem or dummy) now?
func may_attack(owner: int, target: int) -> bool:
	if target == 0 or target == owner:
		return false
	if target == Boss.ID:
		return true
	if target > 0:
		if _who.get(target, Who.PLAYER) != Who.PLAYER:
			return true
		return bool(_pvp.get(owner, false)) and bool(_pvp.get(target, false))
	if target <= -1000:
		var o: G = list.get(-1000 - target, null)
		if o == null or o.owner == owner or o.state == State.DIE:
			return false
		return o.owner != owner and (_who.get(o.owner, Who.PLAYER) != Who.PLAYER or (bool(_pvp.get(owner, false)) and bool(_pvp.get(o.owner, false))))
	return -target - 1 < WorldLayout.DUMMIES.size()   # a practice dummy


## Give `owner`'s golems an order (server). people: as for tick (who is who, PvP, where), so the check is current.
## -> "" if it was taken, else why not (for the summoner's screen).
func order(owner: int, mode: int, point: Vector3, target: int, now: int, people: Array = []) -> String:
	if not people.is_empty():
		_read_people(people)
	if count(owner) == 0:
		return "You have no golems"
	if mode == Order.ATTACK:
		if not may_attack(owner, target):
			return "PvP is off: your golems won't attack players" if target > 0 or target <= -1000 else "Nothing to attack there"
	if mode == Order.GOTO and _where.has(owner):
		var me: Vector3 = _where[owner]
		var off := Vector2(point.x - me.x, point.z - me.z)
		if off.length() > GOTO_MAX:
			off = off.normalized() * GOTO_MAX
		point = Vector3(me.x + off.x, 0.0, me.z + off.y)
	if mode == Order.STAY and _where.has(owner):
		point = _where[owner]
	point.y = 0.0
	if mode == Order.FOLLOW:
		orders.erase(owner)
	else:
		var o := Ord.new()
		o.mode = mode
		o.point = point
		o.target = target if mode == Order.ATTACK else 0
		o.t0 = now
		orders[owner] = o
	orders_dirty[owner] = true
	for g: G in list.values():   # an order takes effect at once: drop what they were after
		if g.owner == owner and g.state != State.DIE:
			g.target = target if mode == Order.ATTACK else 0
	return ""


func _end_order(owner: int) -> void:
	if orders.has(owner):
		var o: Ord = orders[owner]
		orders.erase(owner)
		orders_dirty[owner] = true
		if o.mode == Order.ATTACK:   # let go of it now (it's picked again only if it's still a fair target)
			for g: G in list.values():
				if g.owner == owner and g.target == o.target:
					g.target = 0


func _read_people(people: Array) -> void:
	_pvp = {}
	_where = {}
	_who = {}
	for pe in people:
		_pvp[pe[0]] = pe[2]
		_who[pe[0]] = int(pe[4]) if pe.size() > 4 else Who.PLAYER
		if pe[3]:
			_where[pe[0]] = pe[1]


## Once a tick, before the golems move: attack orders end when the target is gone, can't be fought any more or has
## been out of reach too long; regroups end when everyone is back; orders end when the summoner has no golems left.
func _check_orders() -> void:
	for owner in orders.keys():
		var o: Ord = orders[owner]
		if count(owner) == 0:
			_end_order(owner)
			continue
		if o.mode == Order.ATTACK:
			var tp = _pos_of(o.target, _where)
			if tp == null or not may_attack(owner, o.target):
				_end_order(owner)
				continue
			var home = _where.get(owner, null)
			if home != null and Vector2(tp.x - home.x, tp.z - home.z).length() > ORDER_LEASH:
				o.out_t += 1
				if o.out_t >= ORDER_OUT:
					_end_order(owner)
			else:
				o.out_t = 0
		elif o.mode == Order.REGROUP:
			var home = _where.get(owner, null)
			var back := true
			if home != null:
				for g: G in list.values():
					if g.owner == owner and g.state != State.DIE and Vector2(g.pos.x - home.x, g.pos.z - home.z).length() > REGROUP_NEAR * (1.8 if g.titan else 1.0):
						back = false
			if back or _now - o.t0 >= REGROUP_T:
				_end_order(owner)


## Someone (a player, a challenger, Thunderhorn) hurt `victim` or one of `victim`'s golems.
func note_harm(victim: int, attacker: int, now: int) -> void:
	if victim == attacker or attacker == 0:
		return
	if not harm.has(victim):
		harm[victim] = {}
	harm[victim][attacker] = now


## Did `attacker` hurt `victim` (or victim's golems) within `ticks`?
func harmed(victim: int, attacker: int, ticks: int) -> bool:
	return harm.has(victim) and harm[victim].has(attacker) and _now - int(harm[victim][attacker]) <= ticks


func spawn(owner: int, pos: Vector3, yaw: float, now: int, titan := false) -> G:
	var mine := list.values().filter(func(g): return g.owner == owner and g.state != State.DIE and g.titan == titan)
	if mine.size() >= (1 if titan else MAX_PER_OWNER):   # the oldest crumbles to make room
		mine.sort_custom(func(a, b): return a.born < b.born)
		_to_state(mine[0], State.DIE)
	var g := G.new()
	g.id = next_id
	next_id += 1
	g.owner = owner
	g.pos = pos
	g.yaw = yaw
	g.born = now
	g.check_pos = pos
	g.side = 1.0 if g.id % 2 == 0 else -1.0
	g.titan = titan
	g.max_hp = TITAN_HP if titan else HP
	g.hp = g.max_hp
	list[g.id] = g
	return g


## v0.12.0: an NPC wizard went down: its golems crumble with it.
func dissolve(owner: int) -> void:
	for g: G in list.values():
		if g.owner == owner and g.state != State.DIE:
			_to_state(g, State.DIE)


func _to_state(g: G, s: int) -> void:
	g.state = s
	g.t = 0


## Damage a golem (not by its own summoner). Returns true if that finished it.
func hurt(id: int, amount: int, from: int, dir: Vector3) -> bool:
	if not list.has(id):
		return false
	var g: G = list[id]
	if g.state == State.DIE or g.state == State.RISE or from == g.owner:
		return false
	g.hp = maxi(g.hp - amount, 0)
	var push := Vector2(dir.x, dir.z)
	if push.length() > 1e-4:
		_move(g, push.normalized() * 0.25)
	if g.hp == 0:
		_to_state(g, State.DIE)
		return true
	return false


func stun(id: int, ticks: int) -> void:
	if list.has(id) and list[id].state != State.DIE:
		list[id].stun = ticks


## One server tick. people: [id, position, pvp, alive, Who] for every player, challenger and the boss. Returns the
## slams that landed this tick: [golem, target id (player id, -(dummy + 1) or -1000 - golem id), damage, direction].
func tick(now: int, people: Array) -> Array:
	var hits := []
	_now = now
	_read_people(people)
	var pvp := _pvp
	var where := _where
	_check_orders()
	_assign_slots()
	for g: G in list.values().duplicate():
		g.t += 1
		if g.stun > 0:
			g.stun -= 1
			continue
		if g.state == State.DIE:
			if g.t >= DIE:
				list.erase(g.id)
			continue
		if now - g.born > (TITAN_LIFE if g.titan else LIFE):
			_to_state(g, State.DIE)
			continue
		if g.state == State.RISE:
			if g.t >= RISE:
				_to_state(g, State.IDLE)
			continue
		if g.atk_cd > 0:
			g.atk_cd -= 1
		if g.leap_cd > 0:
			g.leap_cd -= 1
		if g.state == State.LEAP:   # in the air: on across the ground, then down on whoever is there
			_move(g, g.leap_step)
			if g.t >= LEAP_T:
				var tp = _target_pos(g, where)
				if tp != null:
					var d := Vector2(tp.x - g.pos.x, tp.z - g.pos.z)
					if d.length() <= _reach(g) + 0.6:
						hits.append([g, g.target, LEAP_DAMAGE, Vector3(d.x, 0, d.y)])
				g.atk_cd = COOLDOWN + 10
				g.leap_cd = LEAP_CD
				_to_state(g, State.IDLE)
			continue
		if not fogs.is_empty() or g.fog_t > 0:
			if Fog.lost(g.owner, g.pos, fogs, now, fog_pvp):
				g.fog_t = FOG_RECOVER
			elif g.fog_t > 0:
				g.fog_t -= 1
			if g.fog_t > 0:
				_confused(g)
				continue
		if g.state == State.ATTACK:
			var chase = _target_pos(g, where)   # it keeps after its target while it swings
			if chase != null:
				var cd := Vector2(chase.x - g.pos.x, chase.z - g.pos.z)
				if cd.length() > 0.05:
					g.yaw = lerp_angle(g.yaw, atan2(-cd.x, -cd.y), 0.25)
				if cd.length() > _reach(g) * 0.6 and g.t < WINDUP + 6:
					var cdir := _steer(g, cd)
					if cdir != Vector2.ZERO:
						_move(g, cdir * _speed(g) * (1.0 if g.t < WINDUP else ATTACK_SPEED) * Config.DT)
			if g.t == WINDUP:
				var tp = _target_pos(g, where)
				if tp != null:
					var d := Vector2(tp.x - g.pos.x, tp.z - g.pos.z)
					var face := Vector2(-sin(g.yaw), -cos(g.yaw))
					if g.titan:   # the titan's slam crushes everyone near where it lands
						var at := g.pos + Vector3(face.x, 0, face.y) * TITAN_REACH
						for id in where.keys():
							if id != g.owner and pvp.get(id, false) and pvp.get(g.owner, false):
								var off: Vector3 = where[id] - at
								if Vector2(off.x, off.z).length() <= TITAN_SLAM:
									hits.append([g, id, TITAN_DAMAGE, Vector3(off.x, 0, off.z)])
						for o: G in list.values():
							if o.owner != g.owner and o.state != State.DIE and Vector2(o.pos.x - at.x, o.pos.z - at.z).length() <= TITAN_SLAM:
								hits.append([g, -1000 - o.id, TITAN_DAMAGE, o.pos - at])
						for i in WorldLayout.DUMMIES.size():
							if Vector2(WorldLayout.DUMMIES[i].x - at.x, WorldLayout.DUMMIES[i].z - at.z).length() <= TITAN_SLAM:
								hits.append([g, -(i + 1), TITAN_DAMAGE, WorldLayout.DUMMIES[i] - at])
					elif d.length() <= _reach(g) + 0.6 and (d.length() < 0.4 or absf(face.angle_to(d)) < deg_to_rad(75.0)):
						hits.append([g, g.target, DAMAGE, Vector3(d.x, 0, d.y)])
			if g.t >= ATTACK:
				g.atk_cd = COOLDOWN
				_to_state(g, State.IDLE)
			continue
		var ord: Ord = orders.get(g.owner, null)
		if ord != null and ord.mode == Order.ATTACK:   # ordered: that one first, whatever else is near
			g.target = ord.target
		elif ord != null and ord.mode == Order.REGROUP:   # back to the summoner, fighting nothing on the way
			g.target = 0
		elif g.t % 15 == 1 or g.target == 0 or _target_pos(g, where) == null:
			g.target = _pick(g, where, pvp)
		var goal = _target_pos(g, where)
		var keep := 0.0
		var guarding := false
		if goal == null or g.target == 0:   # nothing to fight: take its place in the guard ring round the summoner
			var home = where.get(g.owner, null)   # (or round the point it was told to hold)
			if ord != null and (ord.mode == Order.STAY or ord.mode == Order.GOTO):
				home = ord.point
			if home != null:
				goal = home + Vector3(cos(g.guard_a), 0, sin(g.guard_a)) * (GUARD_R * (1.8 if g.titan else 1.0))
				guarding = true
			keep = 0.5
		if goal == null:
			if g.state != State.IDLE:
				_to_state(g, State.IDLE)
			continue
		var to := Vector2(goal.x - g.pos.x, goal.z - g.pos.z)
		if guarding and to.length() <= keep:   # at its post: facing out, away from the summoner
			g.yaw = lerp_angle(g.yaw, atan2(-cos(g.guard_a), -sin(g.guard_a)), 0.1)
			if g.state != State.IDLE:
				_to_state(g, State.IDLE)
			continue
		# a leap at the target from a few metres out (small golems), when the way is clear
		if g.target != 0 and not g.titan and g.atk_cd == 0 and g.leap_cd == 0 and to.length() >= LEAP_MIN and to.length() <= LEAP_MAX:
			var mid := g.pos + Vector3(to.x, 0, to.y) * 0.5
			if _free(g, mid):
				var go := minf(to.length() - _reach(g) * 0.7, LEAP_SPEED * LEAP_T * Config.DT)
				g.leap_step = to.normalized() * (go / float(LEAP_T))
				g.yaw = atan2(-to.x, -to.y)
				_to_state(g, State.LEAP)
				continue
		# closing in on a target others are after too: aim for its own side of them, not the same spot
		if g.target != 0 and g.slot != 0.0 and to.length() > _reach(g) + 1.0:
			var from_t := Vector2(g.pos.x - goal.x, g.pos.z - goal.z)
			var side_pt := Vector2.from_angle(from_t.angle() + g.slot) * (_reach(g) + 0.5)
			to = Vector2(goal.x + side_pt.x - g.pos.x, goal.z + side_pt.y - g.pos.z)
		if g.target != 0 and to.length() <= _reach(g) + 0.35 and g.atk_cd > 0:
			g.yaw = atan2(-to.x, -to.y)   # in reach, waiting to swing again
			continue
		if g.target != 0 and g.atk_cd == 0 and to.length() <= _reach(g) + START_AT:
			_to_state(g, State.ATTACK)   # starts the swing on the run; it closes in while the arms come up
			continue
		if to.length() <= keep:
			if g.state != State.IDLE:
				_to_state(g, State.IDLE)
			continue
		var dir := _steer(g, to)
		if dir == Vector2.ZERO:
			continue
		dir = _separate(g, dir)
		if not fogs.is_empty():   # v0.12.0: round an enemy's fog, not into it
			dir = Fog.steer(g.owner, g.pos, dir, fogs, now, fog_pvp)
		if g.state != State.WALK:
			_to_state(g, State.WALK)
		_move(g, dir * _speed(g) * Config.DT)
		g.yaw = lerp_angle(g.yaw, atan2(-dir.x, -dir.y), 0.18)
		if g.t % 40 == 0:   # stuck: barely moved in 2/3 s: go the other way round for a while
			if g.pos.distance_to(g.check_pos) < 0.4:
				g.side = -g.side
				g.detour = 50
			g.check_pos = g.pos
	return hits


func _speed(g: G) -> float:
	return TITAN_SPEED if g.titan else SPEED


func _reach(g: G) -> float:
	return TITAN_REACH if g.titan else REACH


func _target_pos(g: G, where: Dictionary):
	if g.target == Boss.ID:   # Thunderhorn is big: go for the near side of him, not his middle
		var b = where.get(Boss.ID, null)
		if b == null:
			return null
		var off := Vector3(g.pos.x - b.x, 0.0, g.pos.z - b.z)
		if off.length() < 0.01:
			off = Vector3(0, 0, 1)
		return b + off.normalized() * (Boss.RADIUS - 0.6)
	return _pos_of(g.target, where)


## Where a target id is (a player / challenger, Thunderhorn, a golem, a dummy), or null if it's gone.
## (v0.12.2: Thunderhorn's id, Boss.ID = -5000, used to read as golem 4000, so golems never closed in on him.)
func _pos_of(t: int, where: Dictionary):
	if t > 0 or t == Boss.ID:
		return where.get(t, null)
	if t <= -1000:
		var o = list.get(-1000 - t, null)
		return o.pos if o != null and o.state != State.DIE else null
	if t < 0 and -t - 1 < WorldLayout.DUMMIES.size():
		return WorldLayout.DUMMIES[-t - 1]
	return null


var _who := {}


## May a golem of `owner` fight `other` (a player, challenger or the boss, or the summoner of a golem)?
func foe(owner: int, other: int, pvp: Dictionary) -> bool:
	if other == owner:
		return false
	var me: int = _who.get(owner, Who.PLAYER)
	var it: int = _who.get(other, Who.PLAYER)
	if me == Who.NPC:   # a challenger's golems: against players (and their golems) and nothing else
		return it == Who.PLAYER or (it == Who.NEUTRAL and harmed(owner, other, GRUDGE))
	if me == Who.NEUTRAL or it == Who.NEUTRAL:   # v0.12.6: neutrals and their golems: only after a hurt
		return harmed(owner, other, GRUDGE)
	if it == Who.BOSS or it == Who.NPC:
		return true
	return pvp.get(owner, false) and pvp.get(other, false) and harmed(owner, other, GRUDGE)


func _pick(g: G, where: Dictionary, pvp: Dictionary) -> int:
	var best := 0
	var best_d := INF
	var home = where.get(g.owner, null)
	var centre: Vector3 = home if home != null else g.pos
	var leash := LEASH if home != null else SENSE
	var ord: Ord = orders.get(g.owner, null)
	if ord != null and (ord.mode == Order.STAY or ord.mode == Order.GOTO):   # holding a point: only what comes near it
		centre = ord.point
		leash = HOLD_R
	for id in where.keys():
		if not foe(g.owner, id, pvp):
			continue
		var at: Vector3 = where[id]
		if not fogs.is_empty() and not Fog.can_see(g.owner, g.pos, id, at, fogs, _now, fog_pvp):
			continue   # v0.12.0: hidden in a fog
		if _who.get(id, Who.PLAYER) == Who.BOSS:   # measured to his flank, not his middle
			at = at + (g.pos - at).normalized() * 2.0
		if Vector2(at.x - centre.x, at.z - centre.z).length() > leash or g.pos.distance_to(at) > SENSE:
			continue
		var d := g.pos.distance_to(at) - (100.0 if harmed(g.owner, id, ATTACKING) else 0.0)
		if d < best_d:
			best_d = d
			best = id
	for o: G in list.values():
		if o.owner == g.owner or o.state == State.DIE or o.state == State.RISE or not foe(g.owner, o.owner, pvp):
			continue
		if not fogs.is_empty() and not Fog.can_see(g.owner, g.pos, o.owner, o.pos, fogs, _now, fog_pvp):
			continue
		if Vector2(o.pos.x - centre.x, o.pos.z - centre.z).length() > leash or g.pos.distance_to(o.pos) > SENSE:
			continue
		var d := g.pos.distance_to(o.pos) - (100.0 if harmed(g.owner, o.owner, ATTACKING) else 0.0)
		if d < best_d:
			best_d = d
			best = -1000 - o.id
	if best != 0:
		return best
	best_d = 14.0
	for i in WorldLayout.DUMMIES.size():
		if ord != null and (ord.mode == Order.STAY or ord.mode == Order.GOTO) and Vector2(WorldLayout.DUMMIES[i].x - centre.x, WorldLayout.DUMMIES[i].z - centre.z).length() > HOLD_R:
			continue
		var d := g.pos.distance_to(WorldLayout.DUMMIES[i])
		if d < best_d:
			best_d = d
			best = -(i + 1)
	return best


## v0.12.0 lost in an enemy's fog: thrash (slam at random spots round it) or stumble (wander, the heading jerking
## about), picked again every FOG_ROLL ticks. It hits nothing it can't see: a thrash is a swing at the air.
func _confused(g: G) -> void:
	g.target = 0
	g.fog_roll -= 1
	if g.fog_roll <= 0 or g.fog_mode == "":
		g.fog_mode = "thrash" if randf() < 0.5 else "stumble"
		g.fog_roll = FOG_ROLL
		g.wander = randf() * TAU
	if g.state == State.ATTACK:
		if g.t >= ATTACK:
			g.atk_cd = COOLDOWN
			_to_state(g, State.IDLE)
		return
	if g.fog_mode == "thrash":
		if g.atk_cd == 0 and randf() < 0.05:
			g.yaw = randf() * TAU
			_to_state(g, State.ATTACK)
		return
	if randf() < 0.04:
		g.wander += randf_range(-1.4, 1.4)
	var dir := Vector2(cos(g.wander), sin(g.wander))
	if not _free(g, g.pos + Vector3(dir.x, 0, dir.y) * 0.8):
		g.wander += PI * 0.5
		return
	if g.state != State.WALK:
		_to_state(g, State.WALK)
	_move(g, dir * _speed(g) * 0.55 * Config.DT)
	g.yaw = lerp_angle(g.yaw, atan2(-dir.x, -dir.y), 0.2)


## The way to go: the straight line if it's clear, else the first clear direction fanning out to the golem's side.
func _steer(g: G, to: Vector2) -> Vector2:
	var base := to.angle()
	if g.detour > 0:
		g.detour -= 1
		base += g.side * deg_to_rad(80.0)
	for off in [0.0, 25.0, 50.0, 75.0, 100.0, 130.0, 160.0]:
		for sgn in ([1.0] if off == 0.0 else [g.side, -g.side]):
			var d := Vector2.from_angle(base + sgn * deg_to_rad(off))
			var p1 := g.pos + Vector3(d.x, 0, d.y) * 0.7
			var p2 := g.pos + Vector3(d.x, 0, d.y) * 1.4
			if _free(g, p1) and _free(g, p2):
				# straight ahead is clear for now, but a pillar further on: start curving round it already
				if off == 0.0 and to.length() > 3.0 and not _free_static(g, g.pos + Vector3(d.x, 0, d.y) * 2.6):
					continue
				return d
	return Vector2.ZERO


func _free(g: G, p: Vector3) -> bool:
	var rad := RADIUS * (TITAN_SCALE / SCALE if g.titan else 1.0)
	for b: WorldLayout.Box in WorldLayout.boxes():
		if b.h > 0.5 and absf(p.x - b.cx) < b.hx + rad and absf(p.z - b.cz) < b.hz + rad:
			return false
	for d: Vector3 in WorldLayout.DUMMIES:
		if Vector2(p.x - d.x, p.z - d.z).length() < Sim.DUMMY_RADIUS + RADIUS:
			return false
	for o: G in list.values():
		if o != g and o.state != State.DIE and Vector2(p.x - o.pos.x, p.z - o.pos.z).length() < RADIUS * 2.0:
			return false
	return absf(p.x) < Config.WORLD_HALF and absf(p.z) < Config.WORLD_HALF


## Pillars and trunks only (not other golems): for looking further ahead.
func _free_static(g: G, p: Vector3) -> bool:
	var rad := RADIUS * (TITAN_SCALE / SCALE if g.titan else 1.0)
	for b: WorldLayout.Box in WorldLayout.boxes():
		if b.h > 0.5 and absf(p.x - b.cx) < b.hx + rad and absf(p.z - b.cz) < b.hz + rad:
			return false
	return true


## Keep a little apart from other golems nearby: bend the way it's going away from them.
func _separate(g: G, dir: Vector2) -> Vector2:
	var push := Vector2.ZERO
	for o: G in list.values():
		if o == g or o.state == State.DIE:
			continue
		var d := Vector2(g.pos.x - o.pos.x, g.pos.z - o.pos.z)
		var l := d.length()
		if l < 1.1 and l > 1e-4:
			push += d / l * (1.1 - l)
	if push == Vector2.ZERO:
		return dir
	var nd := (dir + push * 0.9).normalized()
	var p := g.pos + Vector3(nd.x, 0, nd.y) * 0.7
	return nd if _free(g, p) else dir


## Who goes where: golems after the same target fan out round it (each its own angle offset); each summoner's golems
## share out the guard ring.
func _assign_slots() -> void:
	var by_target := {}
	var by_owner := {}
	for g: G in list.values():
		if g.state == State.DIE:
			continue
		if g.target != 0:
			if not by_target.has(g.target):
				by_target[g.target] = []
			by_target[g.target].append(g)
		if not by_owner.has(g.owner):
			by_owner[g.owner] = []
		by_owner[g.owner].append(g)
	for k in by_target:
		var gs: Array = by_target[k]
		gs.sort_custom(func(a, b): return a.id < b.id)
		for i in gs.size():
			gs[i].slot = 0.0 if gs.size() == 1 else (float(i) - float(gs.size() - 1) * 0.5) * SPREAD
	for k in by_owner:
		var gs: Array = by_owner[k]
		gs.sort_custom(func(a, b): return a.id < b.id)
		for i in gs.size():
			gs[i].guard_a = TAU * float(i) / float(gs.size()) + PI * 0.5


func _move(g: G, step: Vector2) -> void:
	var np := g.pos + Vector3(step.x, 0, step.y)
	if _free(g, np):
		g.pos = np
	g.pos.y = 0.0


## Every golem, flat for the network: [id, owner, x, y, z, yaw, state, t, hp, stunned, titan].
func pack() -> Array:
	var out := []
	for g: G in list.values():
		out.append([g.id, g.owner, g.pos.x, g.pos.y, g.pos.z, g.yaw, g.state, g.t, g.hp, 1 if g.stun > 0 else 0, 1 if g.titan else 0])
	return out
