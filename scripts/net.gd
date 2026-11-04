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


@rpc("any_peer", "call_remote", "unreliable", 1)
func inputs(data: PackedByteArray) -> void:
	if multiplayer.is_server():
		_server_receive_inputs(multiplayer.get_remote_sender_id(), Codec.decode_inputs(data))


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func snapshot(data: PackedByteArray) -> void:
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
		# stay INTERP_DELAY_TICKS behind the newest snapshot; nudge gently so motion never jumps
		var target := latest_tick - Config.INTERP_DELAY_TICKS
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
	p.state = Sim.spawn_state(players.size() + 1)
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
		# one input per tick; if some bunched up on the network, catch up a little faster
		var budget := 3 if p.queue.size() > 4 else 1
		while budget > 0 and not p.queue.is_empty():
			var nxt := p.last_applied + 1
			if not p.queue.has(nxt):
				# the next input is missing (lost or overtaken): wait a few ticks for it to arrive, then skip it
				p.waited += 1
				if p.waited < 8:
					break
				nxt = p.queue.keys().min()
			p.waited = 0
			var inp: Sim.PlayerInput = p.queue[nxt]
			p.queue.erase(nxt)
			Sim.step(p.state, inp)
			p.last_applied = inp.seq
			budget -= 1
		# no input arrived this tick: the player does not move on the server's own guess. The client predicted this
		# step with its real input, which will arrive and be applied, so both sides apply exactly the same inputs.
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


# ---------------------------------------------------------------- client
func _client_tick() -> void:
	var b_y: Array = input_source.call() if input_source.is_valid() else [0, 0.0]
	var inp := Sim.PlayerInput.new(next_seq, int(b_y[0]), float(b_y[1]))
	next_seq += 1
	# predict at once
	prev_pos = cur_pos
	Sim.step(predicted, inp)
	cur_pos = predicted.pos
	pending.append(inp)
	if pending.size() > 240:
		pending = pending.slice(pending.size() - 240)
	# send (with the last few repeated)
	sent_recent.append(inp)
	if sent_recent.size() > Config.INPUT_REDUNDANCY:
		sent_recent.pop_front()
	if is_host_player:
		_server_receive_inputs(1, [inp])
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


## Where to draw our own player this frame (between the last two ticks, plus any correction being blended out).
func own_draw_position(frac: float) -> Vector3:
	return prev_pos.lerp(cur_pos, frac) + correction


## Where to draw another player: interpolated between the two snapshots around render_tick.
## -> [position, yaw] or [] if unknown.
func remote_draw(id: int, frac: float) -> Array:
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
		return [sb.pos, sb.yaw]
	var sa: Sim.PlayerState = a.ents[id]
	if b.is_empty():  # nothing newer yet (packet loss): carry on along the velocity for up to 250 ms
		var ahead := minf((t - a.tick) * Config.DT, 0.25)
		return [sa.pos + sa.vel * ahead, sa.yaw]
	var sb2: Sim.PlayerState = b.ents[id]
	var w := clampf((t - a.tick) / float(b.tick - a.tick), 0.0, 1.0)
	return [sa.pos.lerp(sb2.pos, w), lerp_angle(sa.yaw, sb2.yaw, w)]


func ping_ms() -> int:
	if peer == null or multiplayer.multiplayer_peer == null or multiplayer.is_server():
		return 0
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return 0
	var p := peer.get_peer(1)
	return int(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if p else 0
