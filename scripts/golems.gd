## Stone golems (Jacob 2026-11-04), summoned with the magic wand. Run by the server only; every few ticks their state
## goes to every client (Net.golem_states) and GolemView draws and animates them.
##
## Each golem rises out of the ground, then picks a target: the nearest player its summoner may fight (both with PvP
## on) or another summoner's golem, within 25 m; with none, a practice dummy within 14 m; with nothing, it follows its
## summoner. Six golems per summoner at most (one every 10 s: the wand's recharge). It walks there round pillars and trunks (steering: the first free direction fanning out from the
## straight line, with a side it keeps to, and a detour when it notices it is stuck), and as it closes in it raises
## both arms and slams them down, still moving after its target while it swings. It crumbles when its health runs out or after 45 s.
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
enum State { RISE, IDLE, WALK, ATTACK, DIE, STUN }


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


var list := {}        # id -> G
var next_id := 1


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


## One server tick. people: [id, position, pvp, alive] for every player. Returns the slams that landed this tick:
## [golem, target id (player id, -(dummy + 1) or -1000 - golem id), damage, direction].
func tick(now: int, people: Array) -> Array:
	var hits := []
	var pvp := {}
	var where := {}
	for pe in people:
		pvp[pe[0]] = pe[2]
		if pe[3]:
			where[pe[0]] = pe[1]
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
		if g.t % 15 == 1 or g.target == 0 or _target_pos(g, where) == null:
			g.target = _pick(g, where, pvp)
		var goal = _target_pos(g, where)
		var keep := 0.0
		if goal == null or g.target == 0:   # nothing to fight: stay near the summoner
			goal = where.get(g.owner, null)
			keep = 2.5
		if goal == null:
			if g.state != State.IDLE:
				_to_state(g, State.IDLE)
			continue
		var to := Vector2(goal.x - g.pos.x, goal.z - g.pos.z)
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
	if g.target > 0:
		return where.get(g.target, null)
	if g.target <= -1000:
		var o = list.get(-1000 - g.target, null)
		return o.pos if o != null and o.state != State.DIE else null
	if g.target < 0:
		return WorldLayout.DUMMIES[-g.target - 1]
	return null


func _pick(g: G, where: Dictionary, pvp: Dictionary) -> int:
	var best := 0
	var best_d := SENSE
	if pvp.get(g.owner, false):
		for id in where.keys():
			if id != g.owner and pvp.get(id, false):
				var d: float = g.pos.distance_to(where[id])
				if d < best_d:
					best_d = d
					best = id
		for o: G in list.values():
			if o.owner != g.owner and o.state != State.DIE and o.state != State.RISE and pvp.get(o.owner, false):
				var d := g.pos.distance_to(o.pos)
				if d < best_d:
					best_d = d
					best = -1000 - o.id
	if best != 0:
		return best
	best_d = 14.0
	for i in WorldLayout.DUMMIES.size():
		var d := g.pos.distance_to(WorldLayout.DUMMIES[i])
		if d < best_d:
			best_d = d
			best = -(i + 1)
	return best


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
