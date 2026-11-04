## Networking: one node, present on every peer at /root/Main/Net, holding the server side, the client side, or both
## (a host is a server that also plays).
##
## The model (fast, no rubber-banding):
##  * Server-authoritative: only the server's simulation counts. It runs at a fixed 60 Hz.
##  * Client-side prediction: your own player moves the instant you press a key, using the same Sim.step as the server.
##  * Reconciliation: each snapshot says which of your inputs the server has applied (ack). The client resets to the
##    server's state and replays the inputs still in flight. Because both sides run identical, float32-rounded steps,
##    the result normally equals the prediction exactly; any real correction is blended out over a few frames.
##  * Interpolation: other players are drawn INTERP_DELAY_TICKS (100 ms) in the past, blending between two snapshots,
##    so they move smoothly however the packets arrive.
##  * Transport: ENet over UDP. Inputs and snapshots are unreliable (a late packet is useless; the next one carries
##    newer data), and every input packet repeats the last few inputs, so a lost packet costs nothing.
class_name Net
extends Node

signal roster_changed(players: Dictionary)  # id -> { name, color }
signal status(text: String)
## combat, for Main to show: a projectile launched / landed, something got hit, our own shot left the bow (at once)
signal projectile_spawned(id: int, owner: int, kind: int, tick0: int, pos0: Vector3, vel0: Vector3, g: float)
signal projectile_ended(id: int, tick: int, pos: Vector3, stuck: bool)
signal hit(target: int, amount: int, pos: Vector3, dir: Vector3, killed: bool, attacker: int)
signal local_shot(kind: int, pos0: Vector3, vel0: Vector3, g: float)

const COLORS := [Color("e6194b"), Color("3cb44b"), Color("ffe119"), Color("4363d8"), Color("f58231"), Color("911eb4"),
	Color("46f0f0"), Color("f032e6"), Color("bcf60c"), Color("fabebe"), Color("008080"), Color("e6beff")]

var peer: ENetMultiplayerPeer
var is_host_player := false  # this process is a server AND has its own player (host / solo)
var dedicated := false

# ---------------------------------------------------------------- server side
class ServerPlayer:
	var id := 0
	var name := ""
	var color := Color.WHITE
	var state: Sim.PlayerState
	var queue := {}             # seq -> PlayerInput, not yet applied (packets may arrive out of order)
	var last_applied := 0       # acked to the client
	var waited := 0             # ticks spent waiting for a missing input
	var target_buf := 2         # jitter buffer: inputs to hold before applying (grows when it runs dry)
	var primed := false
	var calm := 0               # ticks since the buffer last ran dry
	var starves := 0            # times it ran dry (for the stats)
	var slot := 0               # spawn slot
	var hist: Array = []        # [tick, position] for the last 1.5 s: melee hits rewind to what the attacker saw
	var was_dead := false


## A projectile in flight (server). Its path is fixed at launch (Weapons.proj_pos), so clients draw it from the
## launch message alone.
class Proj:
	var id := 0
	var owner := 0
	var kind := 0               # 0 arrow, 1 stone
	var tick0 := 0
	var pos0 := Vector3.ZERO
	var vel0 := Vector3.ZERO
	var g := 0.0
	var damage := 0
	var last := Vector3.ZERO

var projectiles := {}  # id -> Proj (server)
var next_proj := 1

var players := {}  # id -> ServerPlayer (server only)
var server_tick := 0

# ---------------------------------------------------------------- client side
var my_id := 0
var roster := {}            # id -> { name, color }
var predicted: Sim.PlayerState
var pending: Array = []     # PlayerInput not yet acked by the server
var next_seq := 1
var sent_recent: Array = [] # the last few inputs, resent every packet
var snapshots: Array = []   # [{ tick, ents }], oldest first
var latest_tick := -1
var render_tick := 0.0      # the tick other players are drawn at
var correction := Vector3.ZERO  # visual offset after a misprediction, decays to zero
var prev_pos := Vector3.ZERO    # own position before / after the last tick, for smooth drawing between ticks
var cur_pos := Vector3.ZERO
var input_source: Callable  # () -> [buttons, yaw], set by Main
var corrections := 0        # times the server disagreed with our prediction (should stay 0)
var interp_delay := float(Config.INTERP_DELAY_TICKS)  # ticks behind the newest snapshot that others are drawn
var _late_ms: Array = []    # how late each recent snapshot arrived, relative to the earliest seen
var _off_base := INF
var extrap_frames := 0      # frames where another player had to be guessed ahead (no newer snapshot yet)
var drawn_frames := 0
# network simulator (testing): extra one-way delay, jitter and loss on this client's traffic
var sim_lat_ms := 0.0
var sim_jit_ms := 0.0
var sim_loss := 0.0
var _sim_out: Array = []    # [deliver_ms, data]
var _sim_in: Array = []


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ================================================================ starting up
func host(port: int, player_name: String, with_player := true) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, Config.MAX_PLAYERS)
	if err != OK:
		return err
	peer.host.compress(ENetConnection.COMPRESS_NONE)  # tiny packets: compression only adds latency
	multiplayer.multiplayer_peer = peer
	dedicated = not with_player
	is_host_player = with_player
	my_id = 1
	if with_player:
		_server_add_player(1, player_name)
		predicted = players[1].state.copy()
		prev_pos = predicted.pos
		cur_pos = predicted.pos
	status.emit("Hosting on UDP port %d." % port)
	return OK


func join(address: String, port: int, player_name: String) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	set_meta("join_name", player_name)
	status.emit("Connecting to %s:%d ..." % [address, port])
	return OK


func _reset() -> void:
	if peer:
		peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	roster.clear()
	snapshots.clear()
	pending.clear()
	predicted = null
	my_id = 0
	roster_changed.emit(roster)


func _on_connection_failed() -> void:
	_reset()
	status.emit("Could not connect.")


func _on_server_disconnected() -> void:
	_reset()
	status.emit("Disconnected from the server.")


func _on_connected() -> void:
	my_id = multiplayer.get_unique_id()
	hello.rpc_id(1, str(get_meta("join_name", "Player")))
	status.emit("Connected.")


func _on_peer_connected(_id: int) -> void:
	pass  # a player only counts once it says hello


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server() and players.has(id):
		print("- %s left" % players[id].name)
		players.erase(id)
		_server_send_roster()


# ================================================================ RPCs
@rpc("any_peer", "call_remote", "reliable")
func hello(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id) or players.size() >= Config.MAX_PLAYERS:
		return
	_server_add_player(id, player_name)
	welcome.rpc_id(id, server_tick)
	print("+ %s joined (%d online)" % [players[id].name, players.size()])


@rpc("authority", "call_remote", "reliable")
func welcome(tick: int) -> void:
	latest_tick = tick
	render_tick = tick - Config.INTERP_DELAY_TICKS


@rpc("authority", "call_remote", "reliable")
func roster_update(list: Array) -> void:
	roster.clear()
	for e in list:
		roster[int(e[0])] = { "name": str(e[1]), "color": e[2] }
	roster_changed.emit(roster)


@rpc("authority", "call_remote", "reliable")
func proj_spawn(id: int, owner: int, kind: int, tick0: int, pos0: Vector3, vel0: Vector3, g: float) -> void:
	projectile_spawned.emit(id, owner, kind, tick0, pos0, vel0, g)


@rpc("authority", "call_remote", "reliable")
func proj_end(id: int, tick: int, pos: Vector3, stuck: bool) -> void:
	projectile_ended.emit(id, tick, pos, stuck)


@rpc("authority", "call_remote", "reliable")
func hit_fx(target: int, amount: int, pos: Vector3, dir: Vector3, killed: bool, attacker: int) -> void:
	hit.emit(target, amount, pos, dir, killed, attacker)


@rpc("any_peer", "call_remote", "unreliable", 1)
func inputs(data: PackedByteArray) -> void:
	if multiplayer.is_server():
		_server_receive_inputs(multiplayer.get_remote_sender_id(), Codec.decode_inputs(data))


@rpc("authority", "call_remote", "unreliable", 2)
func snapshot(data: PackedByteArray) -> void:
	if sim_lat_ms > 0.0 or sim_loss > 0.0:
		_sim_push(_sim_in, data)
	else:
		_client_receive_snapshot(Codec.decode_snapshot(data))


# ================================================================ the fixed tick
func _physics_process(_delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if my_id != 0 and predicted != null:
		_client_tick()
	if multiplayer.is_server():
		_server_tick()
	if my_id != 0:
		render_tick += 1.0
		# stay interp_delay ticks behind the newest snapshot; nudge gently so motion never jumps
		var target := latest_tick - interp_delay
		var err := target - render_tick
		if absf(err) > 30.0:
			render_tick = target
		else:
			render_tick += clampf(err * 0.05, -0.5, 0.5)


# ---------------------------------------------------------------- server
func _server_add_player(id: int, player_name: String) -> void:
	var p := ServerPlayer.new()
	p.id = id
	var clean := player_name.strip_edges().left(Config.MAX_NAME)
	p.name = clean if clean != "" else "Player %d" % (players.size() + 1)
	p.color = COLORS[players.size() % COLORS.size()]
	p.slot = players.size() + 1
	p.state = Sim.spawn_state(p.slot)
	players[id] = p
	_server_send_roster()


func _server_send_roster() -> void:
	var list := []
	for p: ServerPlayer in players.values():
		list.append([p.id, p.name, p.color])
	roster_update.rpc(list)
	if is_host_player:
		roster_update(list)


func _server_receive_inputs(id: int, list: Array) -> void:
	if not players.has(id):
		return
	var p: ServerPlayer = players[id]
	for inp: Sim.PlayerInput in list:
		if inp.seq > p.last_applied and not p.queue.has(inp.seq):
			p.queue[inp.seq] = inp
	while p.queue.size() > Config.MAX_INPUT_BACKLOG:
		p.queue.erase(p.queue.keys().min())


func _server_tick() -> void:
	server_tick += 1
	for p: ServerPlayer in players.values():
		_server_step_player(p)
		p.hist.append([server_tick, p.state.pos])
		if p.hist.size() > 90:
			p.hist.pop_front()
	_server_projectiles()
	if server_tick % Config.SNAPSHOT_EVERY == 0:
		var ents := []
		for p: ServerPlayer in players.values():
			ents.append([p.id, p.state])
		for p: ServerPlayer in players.values():
			var data := Codec.encode_snapshot(server_tick, p.last_applied, ents)
			if p.id == 1 and is_host_player:
				_client_receive_snapshot(Codec.decode_snapshot(data))
			else:
				snapshot.rpc_id(p.id, data)


## Each player's inputs pass through a small jitter buffer. Over the internet inputs arrive unevenly; applied as they
## land, a late one stalls the player for a tick and the next tick lurches, which everyone else sees as stutter. So the
## server waits until target_buf inputs are queued, then applies exactly one per tick. If the buffer runs dry it grows
## (up to 8 ticks); after 10 s without running dry it shrinks again. The player's own view never waits on this: their
## client predicts. Never moves a player on a guess: the server applies exactly the client's inputs, in order.
func _server_step_player(p: ServerPlayer) -> void:
	var n := p.queue.size()
	if not p.primed:
		if n >= p.target_buf or (p.id == 1 and is_host_player and n > 0):
			p.primed = true
		else:
			return
	if n == 0:
		p.primed = false
		p.starves += 1
		p.target_buf = mini(p.target_buf + 1, 8)
		p.calm = 0
		return
	p.calm += 1
	if p.calm > 600 and p.target_buf > 1:
		p.target_buf -= 1
		p.calm = 0
	# one input per tick; drain gently if too many have piled up (a burst after a hiccup)
	var budget := 2 if n > p.target_buf + 3 else 1
	while budget > 0 and not p.queue.is_empty():
		var nxt := p.last_applied + 1
		if not p.queue.has(nxt):
			# the next input is missing (lost or overtaken): wait a few ticks for it, then skip it
			p.waited += 1
			if p.waited < 8:
				break
			nxt = p.queue.keys().min()
		p.waited = 0
		var inp: Sim.PlayerInput = p.queue[nxt]
		p.queue.erase(nxt)
		var ev := Sim.step(p.state, inp)
		p.last_applied = inp.seq
		budget -= 1
		if ev == Sim.Ev.MELEE_HIT:
			_melee(p, inp)
		elif ev == Sim.Ev.SHOT:
			_shoot(p, inp)
		if p.was_dead and p.state.dead == 0:  # back on your feet: a fresh spawn, same weapon
			var w := p.state.weapon
			p.state = Sim.spawn_state(p.slot)
			p.state.weapon = w
		p.was_dead = p.state.dead > 0


# ---------------------------------------------------------------- server: combat
## Where a player was at tick t (from the history), for lag compensation.
func _pos_at(p: ServerPlayer, t: int) -> Vector3:
	for i in range(p.hist.size() - 1, -1, -1):
		if p.hist[i][0] <= t:
			return p.hist[i][1]
	return p.state.pos if p.hist.is_empty() else p.hist[0][1]


## A melee swing lands: everything within reach and inside the arc in front of the attacker takes the hit. Other
## players are rewound to where the attacker saw them (its view_tick, at most 0.5 s back), so what looked like a hit
## on your screen is a hit.
func _melee(p: ServerPlayer, inp: Sim.PlayerInput) -> void:
	var w := Weapons.get_data(p.state.weapon)
	var vt := clampi(inp.view_tick, server_tick - 30, server_tick)
	var me := p.state.pos
	var face := Vector2(-sin(p.state.yaw), -cos(p.state.yaw))
	var targets := []
	for q: ServerPlayer in players.values():
		if q.id != p.id and q.state.dead == 0:
			targets.append([q.id, _pos_at(q, vt)])
	for i in WorldLayout.DUMMIES.size():
		targets.append([-(i + 1), WorldLayout.DUMMIES[i]])
	for t in targets:
		var d: Vector3 = t[1] - me
		var flat := Vector2(d.x, d.z)
		if flat.length() > float(w.range) + Sim.RADIUS or absf(d.y) > 1.8:
			continue
		if flat.length() > 0.6 and absf(face.angle_to(flat)) > deg_to_rad(float(w.arc) / 2.0):
			continue
		_damage(t[0], int(w.damage), p.id, Vector3(flat.x, 0, flat.y), float(w.knock))


## A bow or slingshot is released: launch the projectile (speed and damage from how far it was drawn).
func _shoot(p: ServerPlayer, inp: Sim.PlayerInput) -> void:
	var w := Weapons.get_data(p.state.weapon)
	var sd := Weapons.shot(p.state.weapon, p.state.last_charge)
	var pr := Proj.new()
	pr.id = next_proj
	next_proj += 1
	pr.owner = p.id
	pr.kind = 0 if w.projectile == "arrow" else 1
	pr.tick0 = server_tick
	pr.pos0 = Weapons.muzzle(p.state.pos, inp.yaw)
	pr.vel0 = Weapons.aim_dir(inp.yaw, inp.pitch) * float(sd[0])
	pr.g = float(w.gravity)
	pr.damage = int(sd[1])
	pr.last = pr.pos0
	projectiles[pr.id] = pr
	proj_spawn.rpc(pr.id, pr.owner, pr.kind, pr.tick0, pr.pos0, pr.vel0, pr.g)
	if is_host_player:
		proj_spawn(pr.id, pr.owner, pr.kind, pr.tick0, pr.pos0, pr.vel0, pr.g)


## Move every projectile one tick along its fixed path; test 4 points along the step against players, dummies,
## pillars and the ground.
func _server_projectiles() -> void:
	for id in projectiles.keys():
		var pr: Proj = projectiles[id]
		var n := server_tick - pr.tick0
		var cur := Weapons.proj_pos(pr.pos0, pr.vel0, pr.g, n)
		var prev := pr.last
		pr.last = cur
		var done := false
		for k in range(1, 5):
			var pt := prev.lerp(cur, k / 4.0)
			for q: ServerPlayer in players.values():
				if q.id == pr.owner or q.state.dead > 0:
					continue
				var qp := q.state.pos
				if Vector2(pt.x - qp.x, pt.z - qp.z).length() < 0.5 and pt.y > qp.y - 0.1 and pt.y < qp.y + 1.9:
					_damage(q.id, pr.damage, pr.owner, cur - prev, 1.5)
					_end_proj(pr, pt, false)
					done = true
					break
			if done:
				break
			for i in WorldLayout.DUMMIES.size():
				var dp: Vector3 = WorldLayout.DUMMIES[i]
				if Vector2(pt.x - dp.x, pt.z - dp.z).length() < 0.45 and pt.y > 0.0 and pt.y < 1.9:
					_damage(-(i + 1), pr.damage, pr.owner, cur - prev, 0.0)
					_end_proj(pr, pt, true)
					done = true
					break
			if done:
				break
			if pt.y <= 0.0 or WorldLayout.ground_height(pt.x, pt.z, pt.y + 0.05) > pt.y or _in_box(pt):
				_end_proj(pr, Vector3(pt.x, maxf(pt.y, 0.02), pt.z), true)
				done = true
				break
		if not done and n > 300:
			_end_proj(pr, cur, false)


func _in_box(pt: Vector3) -> bool:
	for b: WorldLayout.Box in WorldLayout.boxes():
		if absf(pt.x - b.cx) < b.hx and absf(pt.z - b.cz) < b.hz and pt.y < b.h and pt.y > 0.0:
			return true
	return false


func _end_proj(pr: Proj, pos: Vector3, stuck: bool) -> void:
	projectiles.erase(pr.id)
	proj_end.rpc(pr.id, server_tick, pos, stuck)
	if is_host_player:
		proj_end(pr.id, server_tick, pos, stuck)


## Damage a player (knockback, death) or a dummy (it just shows the number), and tell everyone.
func _damage(target: int, amount: int, from: int, dir: Vector3, knock: float) -> void:
	var killed := false
	var pos: Vector3
	if target < 0:
		pos = WorldLayout.DUMMIES[-target - 1] + Vector3(0, 1.3, 0)
	else:
		if not players.has(target):
			return
		var q: ServerPlayer = players[target]
		q.state.hp = maxi(q.state.hp - amount, 0)
		var push := Vector3(dir.x, 0, dir.z)
		if push.length_squared() > 1e-6 and knock > 0.0:
			q.state.vel += push.normalized() * knock + Vector3(0, knock * 0.35, 0)
			q.state.grounded = false
		if q.state.hp == 0:
			q.state.dead = Sim.RESPAWN_TICKS
			q.state.charge = 0
			killed = true
		Sim.quantize(q.state)
		pos = q.state.pos + Vector3(0, 1.3, 0)
	hit_fx.rpc(target, amount, pos, dir, killed, from)
	if is_host_player:
		hit_fx(target, amount, pos, dir, killed, from)


# ---------------------------------------------------------------- client
func _process(_delta: float) -> void:
	if _sim_out.is_empty() and _sim_in.is_empty():
		return
	var now := Time.get_ticks_msec()
	while not _sim_out.is_empty() and _sim_out[0][0] <= now:
		var d: PackedByteArray = _sim_out.pop_front()[1]
		if multiplayer.multiplayer_peer != null:
			inputs.rpc_id(1, d)
	while not _sim_in.is_empty() and _sim_in[0][0] <= now:
		_client_receive_snapshot(Codec.decode_snapshot(_sim_in.pop_front()[1]))


func _sim_delay() -> float:
	return Time.get_ticks_msec() + sim_lat_ms / 2.0 + randf() * sim_jit_ms


## Queue for later delivery, in arrival order (a later send can overtake an earlier one, as on the real internet).
func _sim_push(q: Array, data: PackedByteArray) -> void:
	if randf() < sim_loss:
		return
	q.append([_sim_delay(), data])
	q.sort_custom(func(x, y): return x[0] < y[0])


func _client_tick() -> void:
	var b_y: Array = input_source.call() if input_source.is_valid() else [0, 0.0, 0.0, 0]
	var pitch: float = round(float(b_y[2]) * 10000.0) / 10000.0   # the precision the packet carries, so the server agrees
	var inp := Sim.PlayerInput.new(next_seq, int(b_y[0]), float(b_y[1]), pitch, int(b_y[3]), int(render_tick))
	next_seq += 1
	# predict at once
	prev_pos = cur_pos
	var ev := Sim.step(predicted, inp)
	cur_pos = predicted.pos
	if ev == Sim.Ev.SHOT:  # show our own arrow or stone leaving at once; the server's launch follows
		var w := Weapons.get_data(predicted.weapon)
		var sd := Weapons.shot(predicted.weapon, predicted.last_charge)
		local_shot.emit(0 if w.projectile == "arrow" else 1, Weapons.muzzle(predicted.pos, inp.yaw),
			Weapons.aim_dir(inp.yaw, inp.pitch) * float(sd[0]), float(w.gravity))
	pending.append(inp)
	if pending.size() > 240:
		pending = pending.slice(pending.size() - 240)
	# send (with the last few repeated)
	sent_recent.append(inp)
	if sent_recent.size() > Config.INPUT_REDUNDANCY:
		sent_recent.pop_front()
	if is_host_player:
		_server_receive_inputs(1, [inp])
	elif sim_lat_ms > 0.0 or sim_loss > 0.0:
		_sim_push(_sim_out, Codec.encode_inputs(sent_recent))
	else:
		inputs.rpc_id(1, Codec.encode_inputs(sent_recent))
	correction = correction.lerp(Vector3.ZERO, 0.15)


func _client_receive_snapshot(s: Dictionary) -> void:
	var tick: int = s.tick
	if tick <= latest_tick and not snapshots.is_empty():
		return
	latest_tick = tick
	snapshots.append(s)
	while snapshots.size() > 40:
		snapshots.pop_front()
	_measure_jitter(tick)
	# reconcile our own player
	var ents: Dictionary = s.ents
	if not ents.has(my_id):
		return
	var server_state: Sim.PlayerState = ents[my_id]
	if predicted == null:
		predicted = server_state.copy()
		prev_pos = predicted.pos
		cur_pos = predicted.pos
		return
	var ack: int = s.ack
	while not pending.is_empty() and (pending[0] as Sim.PlayerInput).seq <= ack:
		pending.pop_front()
	var replay := server_state.copy()
	for inp: Sim.PlayerInput in pending:
		Sim.step(replay, inp)
	var diff := replay.pos - predicted.pos
	if diff.length_squared() > 1e-10:
		corrections += 1
		if diff.length() > 4.0:  # far off (teleport, long stall): snap
			correction = Vector3.ZERO
		else:  # small: keep drawing where we were and blend the error away
			correction -= diff
		predicted = replay
		cur_pos = predicted.pos
		prev_pos += diff


## Set the interpolation delay from how unevenly snapshots really arrive: enough to cover 95% of them late plus one
## snapshot interval, no more. Grows at once when the connection gets worse, shrinks slowly when it settles.
func _measure_jitter(tick: int) -> void:
	var now := Time.get_ticks_usec() / 1000.0
	var off := now - tick * Config.DT * 1000.0     # arrival time minus send time, plus an unknown constant
	_off_base = minf(_off_base + 0.01, off)         # the fastest arrival seen (drifting up slowly, in case clocks move)
	_late_ms.append(off - _off_base)
	if _late_ms.size() > 90:
		_late_ms.pop_front()
	var sorted := _late_ms.duplicate()
	sorted.sort()
	var p95: float = sorted[int((sorted.size() - 1) * 0.95)]
	var want := (p95 + 6.0) / (Config.DT * 1000.0) + Config.SNAPSHOT_EVERY
	want = clampf(want, Config.SNAPSHOT_EVERY + 1.0, 20.0)
	interp_delay = want if want > interp_delay else lerpf(interp_delay, want, 0.02)


## Where to draw our own player this frame (between the last two ticks, plus any correction being blended out).
func own_draw_position(frac: float) -> Vector3:
	return prev_pos.lerp(cur_pos, frac) + correction


## Where to draw another player: interpolated between the two snapshots around render_tick.
## -> [position, yaw, grounded, dashing] or [] if unknown.
func remote_draw(id: int, frac: float) -> Array:
	drawn_frames += 1
	var t := render_tick + frac
	var a: Dictionary = {}
	var b: Dictionary = {}
	for s in snapshots:
		if not (s.ents as Dictionary).has(id):
			continue
		if s.tick <= t:
			a = s
		elif b.is_empty():
			b = s
			break
	if a.is_empty() and b.is_empty():
		return []
	if a.is_empty():
		var sb: Sim.PlayerState = b.ents[id]
		return [sb.pos, sb.yaw, sb.grounded, sb.dash_ticks > 0, sb]
	var sa: Sim.PlayerState = a.ents[id]
	if b.is_empty():  # nothing newer yet (packet loss): carry on along the velocity for up to 250 ms
		extrap_frames += 1
		var ahead := minf((t - a.tick) * Config.DT, 0.25)
		return [sa.pos + sa.vel * ahead, sa.yaw, sa.grounded, sa.dash_ticks > 0, sa]
	var sb2: Sim.PlayerState = b.ents[id]
	var w := clampf((t - a.tick) / float(b.tick - a.tick), 0.0, 1.0)
	var near := sa if w < 0.5 else sb2
	return [sa.pos.lerp(sb2.pos, w), lerp_angle(sa.yaw, sb2.yaw, w), near.grounded, near.dash_ticks > 0, near]


func ping_ms() -> int:
	if peer == null or multiplayer.multiplayer_peer == null or multiplayer.is_server():
		return 0
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return 0
	var p := peer.get_peer(1)
	return int(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if p else 0
