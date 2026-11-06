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
signal toast_msg(text: String)                      # v0.10.0: a message for this player's screen
signal boss_changed(tick: int, data: Array)         # Thunderhorn's state (BossView)
signal boss_result(kind: String)                    # "victory", "defeat" or "restart"
signal projectile_bounced(id: int, tick0: int, pos0: Vector3, vel0: Vector3)
signal local_shot(kind: int, pos0: Vector3, vel0: Vector3, g: float)
signal item_added(id: int, kind: int, pos: Vector3, count: int)
signal style_changed(style: String)
signal eco(kind: String, args: Array)   # the living yard (trees, fruit, worms, birds): see Ecology / EcoView
signal item_removed(id: int, taker: int)
signal magic_fx(kind: String, args: Array)        # spells: see MagicFx
signal golems_changed(tick: int, data: Array)   # golems' state from the server: see GolemView

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
	var target_buf := 3         # jitter buffer: inputs to hold before applying (grows when it runs dry; v0.8.0: starts at 3, fewer early stalls over the internet)
	var primed := false
	var calm := 0               # ticks since the buffer last ran dry
	var starves := 0            # times it ran dry (for the stats)
	var slot := 0               # spawn slot
	var hist: Array = []        # [tick, position] for the last 1.5 s: melee hits rewind to what the attacker saw
	var was_dead := false
	var character := "pip"
	var interact_prev := false
	var outfit := 0             # Pip's outfit: the host 0, then 1, 2, 3 by who joined
	var pvp := false            # player-versus-player on: can hurt and be hurt by other players with it on
	var kills := [0, 0]         # kills with the staff, with the wand (they level the weapon up)
	var npc := false            # v0.10.0: a Duel Stone challenger (no network peer: its NpcAI makes its inputs)
	var ai: NpcAI
	var air := false            # in the air last tick (landing on the Storm Altar presses it)


## Something lying on the ground to pick up (server). `spawn` >= 0: one of the fixed spawns, which comes back 20 s
## after it is taken; -1: dropped (a spent arrow or stone), gone after 60 s.
class Item:
	var id := 0
	var kind := 0
	var pos := Vector3.ZERO
	var count := 1
	var spawn := -1
	var born := 0

var items := {}           # id -> Item (server)
var next_item := 1
var respawns: Array = []  # [tick, spawn index]


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
	var immune := 0             # a shield's holder it bounced off: it can't hurt them (or bounce off them) again
	var bounces := 0

## How everyone is drawn, chosen by the host for the whole game: "pip" (sprite) or "figure" (3D test character).
var style := "pip"
var ecology: Ecology   # server only
var golems := Golems.new()   # server only: the wand's stone golems
var boss: Boss                # server only: Thunderhorn, while he's here (v0.10.0)
var boss_fighters := []       # the players in the fight (defeat: all of them down at once)
var defeated := false         # the defeat screen is up: waiting for a key to start again
var defeat_t := 0
var next_npc := 1000000       # NPC ids (they're players without a network peer)
const DUEL_REACH := 2.4
const ALTAR_R := 2.6
var pending_spells: Array = []   # [tick, kind, where, caster]: lightning that strikes after its warning
var vault_open_until := 0        # tick the vault's door shuts again (0 = shut)
var wells: Array = []             # gravity wells: [tick it bursts, centre, caster]
var storms: Array = []            # arcane storms: [tick it ends, centre, caster, tick of the next bolt]
var projectiles := {}  # id -> Proj (server)
var LOG := OS.get_cmdline_user_args().has("--log")   # print hits and pick-ups (testing)
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
var _offs: Array = []       # recent arrival offsets (ms): the window's minimum is the "on time" base
var _last_frame_us := 0
var _frame_us := 0          # how long the last frame took: samples taken right after a local hitch are skipped
var jitter_ms := 0.0        # how unevenly snapshots arrive (95th percentile lateness), for the readout
var tailscale_path := {}    # address -> "direct" / "relayed (DERP ...)" / "checking" / "": see check_tailscale_path()


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ================================================================ starting up
func host(port: int, player_name: String, with_player := true) -> Error:
	shutdown()   # anything left from an earlier game in this session lets go of its port first
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, Config.MAX_PLAYERS)
	var tries := 0
	while err != OK and tries < 5:   # the OS may need a moment to release a port that was just closed
		tries += 1
		OS.delay_msec(200)
		peer = ENetMultiplayerPeer.new()
		err = peer.create_server(port, Config.MAX_PLAYERS)
	if err != OK:
		peer = null
		return err
	peer.host.compress(ENetConnection.COMPRESS_NONE)  # tiny packets: compression only adds latency
	multiplayer.multiplayer_peer = peer
	dedicated = not with_player
	is_host_player = with_player
	my_id = 1
	for i in WorldLayout.ITEM_SPAWNS.size():
		_spawn_item_at(i)
	ecology = Ecology.new()
	ecology.event.connect(_on_eco_event)
	if with_player:
		_server_add_player(1, player_name, str(get_meta("character", "pip")))
		if OS.get_cmdline_user_args().has("--give-all"):   # testing: the host starts with every weapon
			players[1].state.owned = 0b1111111
			players[1].state.arrows = 30
			players[1].state.rocks = 30
		for gv in [["--give-staff", Weapons.STAFF], ["--give-wand", Weapons.WAND]]:   # testing: one of the two
			if OS.get_cmdline_user_args().has(gv[0]):
				players[1].state.owned = 0b11111 | (1 << int(gv[1]))
				players[1].state.arrows = 30
				players[1].state.rocks = 30
		if OS.get_cmdline_user_args().has("--max-level"):   # testing: every spell unlocked
			players[1].kills = [Weapons.LEVEL_KILLS[-1], Weapons.LEVEL_KILLS[-1]]
			players[1].state.staff_lvl = Weapons.MAX_LEVEL
			players[1].state.wand_lvl = Weapons.MAX_LEVEL
		predicted = players[1].state.copy()
		prev_pos = predicted.pos
		cur_pos = predicted.pos
	status.emit("Hosting on UDP port %d." % port)
	return OK


func join(address: String, port: int, player_name: String) -> Error:
	shutdown()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	set_meta("join_name", player_name)
	status.emit("Connecting to %s:%d ..." % [address, port])
	return OK


## Leave the game completely (v0.8.1): close the connection so its UDP port is free again (hosting again in the same
## session used to fail with "port 7777 is being used", because leaving only reloaded the scene and the old
## connection stayed open), and forget the whole world this side was running: players, items, shots, spells, golems.
## Safe to call any time; Main calls it on "Leave game", and it runs when Net leaves the scene tree.
func shutdown() -> void:
	if peer:
		peer.close()
		peer = null
	if is_inside_tree() and multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	players.clear()
	roster.clear()
	snapshots.clear()
	pending.clear()
	sent_recent.clear()
	items.clear()
	respawns.clear()
	projectiles.clear()
	pending_spells.clear()
	wells.clear()
	storms.clear()
	golems = Golems.new()
	ecology = null
	predicted = null
	my_id = 0
	latest_tick = -1
	server_tick = 0
	is_host_player = false
	_sim_out.clear()
	_sim_in.clear()


func _exit_tree() -> void:
	shutdown()


func _reset() -> void:
	if peer:
		peer.close()
		peer = null
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
	hello.rpc_id(1, str(get_meta("join_name", "Player")), str(get_meta("character", "pip")), Updater.running_version())
	status.emit("Connected.")


func _on_peer_connected(_id: int) -> void:
	pass  # a player only counts once it says hello


## One of a kind (Jacob 2026-11-04): only one player at a time can have the staff, and one the wand.
const UNIQUE := [Weapons.Item.STAFF, Weapons.Item.WAND]


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server() and players.has(id):
		print("- %s left" % players[id].name)
		_return_unique(players[id])
		for g: Golems.G in golems.list.values():   # their golems crumble
			if g.owner == id:
				g.hp = 0
				golems._to_state(g, Golems.State.DIE)
		players.erase(id)
		_server_send_roster()


# ================================================================ RPCs
@rpc("any_peer", "call_remote", "reliable")
func hello(player_name: String, character := "pip", version := "") -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var mine := Updater.running_version()
	if version != mine:   # host and guest must run the same version (the same rules and the same packets)
		turned_away.rpc_id(id, mine, version)
		print("- turned away a guest on v%s (host is v%s)" % [version, mine])
		get_tree().create_timer(1.0).timeout.connect(func():
			if multiplayer.multiplayer_peer:
				multiplayer.multiplayer_peer.disconnect_peer(id))
		return
	if players.has(id) or humans() >= Config.MAX_PLAYERS:
		return
	_server_add_player(id, player_name, character)
	welcome.rpc_id(id, server_tick)
	set_style.rpc_id(id, style)
	if ecology:
		for e in ecology.full_state(server_tick):
			eco_event.rpc_id(id, e[0], e[1])
	var list := []
	for it: Item in items.values():
		list.append([it.id, it.kind, it.pos, it.count])
	items_full.rpc_id(id, list)
	if vault_open_until > 0:
		spell_fx.rpc_id(id, "vault_door", [true])
	print("+ %s joined (%d online)" % [players[id].name, humans()])


@rpc("authority", "call_remote", "reliable")
func turned_away(host_version: String, my_version: String) -> void:
	var older := Updater.newer(host_version, my_version)
	status.emit(("The host is on v%s and you're on v%s. " % [host_version, my_version]) +
		("Restart the game to update, then join again." if older else "Ask the host to restart their game to update."))
	_reset()


@rpc("authority", "call_remote", "reliable")
func welcome(tick: int) -> void:
	latest_tick = tick
	render_tick = tick - Config.INTERP_DELAY_TICKS


@rpc("authority", "call_remote", "reliable")
func roster_update(list: Array) -> void:
	roster.clear()
	for e in list:
		roster[int(e[0])] = { "name": str(e[1]), "color": e[2], "character": str(e[3]) if e.size() > 3 else "pip",
			"outfit": int(e[4]) if e.size() > 4 else 0, "pvp": bool(e[5]) if e.size() > 5 else false,
			"kills": e[6] if e.size() > 6 else [0, 0] }
	roster_changed.emit(roster)


## PvP on or off for the player who asks (P). Everyone sees it in the roster (crossed swords by the name).
@rpc("any_peer", "call_remote", "reliable")
func set_pvp(on: bool) -> void:
	if not multiplayer.is_server():
		return
	_server_set_pvp(multiplayer.get_remote_sender_id(), on)


func _server_set_pvp(id: int, on: bool) -> void:
	if players.has(id) and players[id].pvp != on:
		players[id].pvp = on
		print("%s turned PvP %s" % [players[id].name, "on" if on else "off"])
		_server_send_roster()


## Ask for PvP on or off (the host applies it at once; a guest asks the host).
func request_pvp(on: bool) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		_server_set_pvp(my_id if my_id != 0 else 1, on)
	else:
		set_pvp.rpc_id(1, on)


## Can `from` hurt player `target`? Only when both have PvP on (dummies and the yard can always be hit).
func can_hurt(from: int, target: int) -> bool:
	if target < 0 or from == target or not players.has(from) or not players.has(target):
		return true
	if players[from].npc or players[target].npc:   # challengers: always fair game, but never each other
		return not (players[from].npc and players[target].npc)
	return players[from].pvp and players[target].pvp


## The yard's events go to everyone, reliably and in order.
@rpc("authority", "call_remote", "reliable", 3)
func eco_event(kind: String, args: Array) -> void:
	eco.emit(kind, args)


func _on_eco_event(kind: String, args: Array) -> void:
	eco_event.rpc(kind, args)
	if is_host_player:
		eco.emit(kind, args)


## The look for everyone (Pip / 3D figure). Only the host sets it; it switches for every player at once, and
## players who join later get it on arrival.
@rpc("authority", "call_remote", "reliable")
func set_style(s: String) -> void:
	if s in ["pip", "figure"]:
		style = s
		style_changed.emit(s)


## Host only: change the look for everyone.
func host_set_style(s: String) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server() or not s in ["pip", "figure"]:
		return
	style = s
	set_style.rpc(s)
	style_changed.emit(s)


@rpc("authority", "call_remote", "reliable")
func items_full(list: Array) -> void:
	for e in list:
		item_added.emit(int(e[0]), int(e[1]), e[2], int(e[3]))


@rpc("authority", "call_remote", "reliable")
func item_add(id: int, kind: int, pos: Vector3, count: int) -> void:
	item_added.emit(id, kind, pos, count)


@rpc("authority", "call_remote", "reliable")
func item_remove(id: int, taker: int) -> void:
	item_removed.emit(id, taker)


@rpc("authority", "call_remote", "reliable", 6)
func proj_spawn(id: int, owner: int, kind: int, tick0: int, pos0: Vector3, vel0: Vector3, g: float) -> void:
	projectile_spawned.emit(id, owner, kind, tick0, pos0, vel0, g)


## A projectile bounced off a shield: it carries on from here on a new path.
@rpc("authority", "call_remote", "reliable", 6)
func proj_bounce(id: int, tick0: int, pos0: Vector3, vel0: Vector3) -> void:
	projectile_bounced.emit(id, tick0, pos0, vel0)


@rpc("authority", "call_remote", "reliable", 6)
func proj_end(id: int, tick: int, pos: Vector3, stuck: bool) -> void:
	projectile_ended.emit(id, tick, pos, stuck)


@rpc("authority", "call_remote", "reliable", 7)
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
func _server_add_player(id: int, player_name: String, character := "pip") -> void:
	var p := ServerPlayer.new()
	p.id = id
	p.character = character if character in ["pip", "figure"] else "pip"
	var clean := player_name.strip_edges().left(Config.MAX_NAME)
	p.name = clean if clean != "" else "Player %d" % (humans() + 1)
	p.color = COLORS[humans() % COLORS.size()]
	p.slot = humans() + 1
	p.outfit = (p.slot - 1) % 4
	p.state = Sim.spawn_state(p.slot)
	players[id] = p
	if boss != null and boss.state != Boss.S.DEATH and not boss_fighters.has(id):   # joining mid-fight: he grows
		boss_fighters.append(id)
		boss.add_fighter()
	_server_send_roster()
	if id != 1 and OS.get_cmdline_user_args().has("--give-guests"):   # testing: guests start with every weapon too
		p.state.owned = 0b1111111
		p.state.arrows = 30
		p.state.rocks = 30


func _server_send_roster() -> void:
	var list := []
	for p: ServerPlayer in players.values():
		list.append([p.id, p.name, p.color, p.character, p.outfit, p.pvp, p.kills])
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
	_server_npcs()
	for p: ServerPlayer in players.values():
		_server_step_player(p)
		p.hist.append([server_tick, p.state.pos])
		if p.hist.size() > 90:
			p.hist.pop_front()
	_server_altar()
	_server_boss()
	_server_projectiles()
	_server_items()
	_server_spells()
	if ecology:
		var people := []
		for p: ServerPlayer in players.values():
			if p.state.dead == 0:
				people.append([p.id, p.state.pos, Vector2(p.state.vel.x, p.state.vel.z).length(), Vector2(p.state.vel.x, p.state.vel.z)])
		ecology.tick(server_tick, people)
	if server_tick % Config.SNAPSHOT_EVERY == 0:
		var ents := []
		for p: ServerPlayer in players.values():
			ents.append([p.id, p.state])
		for p: ServerPlayer in players.values():
			var data := Codec.encode_snapshot(server_tick, p.last_applied, ents)
			if p.npc:
				continue
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
		if n >= p.target_buf or (p.id == 1 and is_host_player and n > 0) or (p.npc and n > 0):
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
		var before := p.state.pos
		var ev := Sim.step(p.state, inp)
		p.last_applied = inp.seq
		budget -= 1
		if ev == Sim.Ev.MELEE_HIT:
			_melee(p, inp)
		elif ev == Sim.Ev.SHOT:
			_shoot(p, inp)
		elif ev == Sim.Ev.CAST:
			_cast(p, inp, before)
		if p.was_dead and p.state.dead == 0 and not p.npc:  # back on your feet: a fresh spawn, keeping what you carry
			var old := p.state
			p.state = Sim.spawn_state(p.slot)
			p.state.weapon = old.weapon
			p.state.owned = old.owned
			p.state.arrows = old.arrows
			p.state.rocks = old.rocks
			p.state.staff_lvl = old.staff_lvl
			p.state.wand_lvl = old.wand_lvl
		p.was_dead = p.state.dead > 0
		var interact := inp.buttons & Sim.Btn.INTERACT != 0
		if interact and not p.interact_prev and p.state.dead == 0:
			if not _stone_interact(p) and not _vault_interact(p) and not _pick_up(p, 2.2, true) and ecology:
				var gain := ecology.try_eat(p.state.pos, server_tick)
				if gain > 0:
					p.state.hp = mini(p.state.hp + gain, Sim.MAX_HP)
		p.interact_prev = interact


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
	var w := Weapons.move(p.state.weapon, p.state.combo)
	var vt := clampi(inp.view_tick, server_tick - 30, server_tick)
	var me := p.state.pos
	var face := Vector2(-sin(p.state.yaw), -cos(p.state.yaw))
	var targets := []
	for q: ServerPlayer in players.values():
		if q.id != p.id and q.state.dead == 0:
			targets.append([q.id, _pos_at(q, vt)])
	for i in WorldLayout.DUMMIES.size():
		targets.append([-(i + 1), WorldLayout.DUMMIES[i]])
	for g: Golems.G in golems.list.values():
		if g.owner != p.id:
			targets.append([-1000 - g.id, g.pos])
	if boss != null:
		targets.append([Boss.ID, boss_surface(me)])
	var impact := me + Vector3(face.x, 0, face.y) * 1.3
	if ecology:   # a tree within reach in front: shake it (fruit trees drop fruit from the 3rd hit)
		for i in WorldLayout.TREES.size():
			var tp: Vector3 = WorldLayout.TREES[i][1]
			var td := Vector2(tp.x - me.x, tp.z - me.z)
			if td.length() <= float(w.range) + 0.5 and (td.length() < 0.6 or absf(face.angle_to(td)) <= deg_to_rad(float(w.arc) / 2.0)):
				ecology.hit_tree(i, int(w.damage), server_tick, Vector3(td.x, 0, td.y))
		ecology.hit_fruit(me, face, float(w.range), float(w.arc), float(w.knock), server_tick)
	for t in targets:
		var d: Vector3 = t[1] - me
		var flat := Vector2(d.x, d.z)
		var in_reach := flat.length() <= float(w.range) + Sim.RADIUS and absf(d.y) <= 1.8 \
			and (flat.length() <= 0.6 or absf(face.angle_to(flat)) <= deg_to_rad(float(w.arc) / 2.0))
		if in_reach:
			_damage(t[0], int(w.damage), p.id, Vector3(flat.x, 0, flat.y), float(w.knock))
		elif w.shape == "smash":
			# the smash's shockwave catches anyone standing close to where the club hits the ground
			var off: Vector3 = t[1] - impact
			if Vector2(off.x, off.z).length() <= float(w.aoe) and absf(off.y) < 1.2:
				_damage(t[0], maxi(int(w.damage) / 2, 3), p.id, Vector3(off.x, 0, off.z), float(w.knock) * 0.6)


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
	pr.vel0 = Weapons.aim_dir(inp.aim_yaw, inp.pitch) * float(sd[0])
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
			var shielded := _shield_at(pt, pr.owner, pr.immune)
			if shielded > 0:   # it bounces off the bubble (the holder pays mana for it), unless that shatters it
				if _shield_bounce(pr, players[shielded], pt, prev, cur):
					done = true
					break
			if boss != null and Vector2(pt.x - boss.pos.x, pt.z - boss.pos.z).length() < Boss.RADIUS and pt.y > boss.pos.y and pt.y < boss.pos.y + Boss.HEIGHT:
				if pr.kind == 2:
					_burst(pr, pt)
				else:
					_damage(Boss.ID, pr.damage, pr.owner, cur - prev, 0.0)
					_end_proj(pr, pt, false)
				done = true
				break
			var gh := _golem_at(pt, pr.owner)
			if gh > 0:
				if pr.kind == 2:
					_burst(pr, pt)
				else:
					_damage(-1000 - gh, pr.damage, pr.owner, cur - prev, 0.0)
					_end_proj(pr, pt, false)
				done = true
				break
			for q: ServerPlayer in players.values():
				if q.id == pr.owner or q.id == pr.immune or q.state.dead > 0 or not can_hurt(pr.owner, q.id):
					continue
				var qp := q.state.pos
				if Vector2(pt.x - qp.x, pt.z - qp.z).length() < 0.5 and pt.y > qp.y - 0.1 and pt.y < qp.y + 1.9:
					if pr.kind == 2:
						_burst(pr, pt)
					else:
						_damage(q.id, pr.damage, pr.owner, cur - prev, 1.5)
						_end_proj(pr, pt, false)
					done = true
					break
			if done:
				break
			for i in WorldLayout.DUMMIES.size():
				var dp: Vector3 = WorldLayout.DUMMIES[i]
				if Vector2(pt.x - dp.x, pt.z - dp.z).length() < 0.45 and pt.y > 0.0 and pt.y < 1.9:
					if pr.kind == 2:
						_burst(pr, pt)
					else:
						_damage(-(i + 1), pr.damage, pr.owner, cur - prev, 0.0)
						_end_proj(pr, pt, true)
					done = true
					break
			if done:
				break
			var tree := WorldLayout.tree_at(pt, 0.4)
			if tree >= 0 and ecology:
				if pr.kind == 2:
					_burst(pr, pt)
				else:
					ecology.hit_tree(tree, int(pr.damage * 0.6), server_tick, cur - prev)
					_end_proj(pr, pt, true)
				done = true
				break
			if pt.y <= 0.0 or WorldLayout.ground_height(pt.x, pt.z, pt.y + 0.05) > pt.y or _in_box(pt):
				if pr.kind == 2:
					_burst(pr, Vector3(pt.x, maxf(pt.y, 0.05), pt.z))
				else:
					_end_proj(pr, Vector3(pt.x, maxf(pt.y, 0.02), pt.z), true)
				done = true
				break
		if not done and n > 300:
			if pr.kind == 2:
				_burst(pr, cur)
			else:
				_end_proj(pr, cur, false)


func _in_box(pt: Vector3) -> bool:
	for b: WorldLayout.Box in WorldLayout.boxes():
		if absf(pt.x - b.cx) < b.hx and absf(pt.z - b.cz) < b.hz and pt.y < b.h and pt.y > 0.0:
			return true
	return false


## A fireball bursts: everything nearby takes area damage.
func _burst(pr: Proj, pos: Vector3) -> void:
	dmg_spell = "Fireball"
	projectiles.erase(pr.id)
	proj_end.rpc(pr.id, server_tick, pos, false)
	if is_host_player:
		proj_end(pr.id, server_tick, pos, false)
	var sp := Weapons.spell(Weapons.STAFF, 1)
	_fx("explode", [pos, float(sp.radius)])
	_blast(pos, sp, pr.owner, Weapons.STAFF)


## The player whose shield bubble the point is inside (not the shot's own), or 0.
func _shield_at(pt: Vector3, owner: int, immune := 0) -> int:
	for q: ServerPlayer in players.values():
		if q.id != owner and q.id != immune and q.state.shield > 0 and q.state.dead == 0 and can_hurt(owner, q.id) and pt.distance_to(shield_center(q.state)) < Weapons.SHIELD_RADIUS:
			return q.id
	return 0


static func shield_center(s: Sim.PlayerState) -> Vector3:
	return s.pos + Vector3(0, Weapons.SHIELD_CENTER_Y, 0)


## A projectile meets a shield (v0.8.1): the holder pays mana for the hit as before (a fireball at the spell rate).
## If that shatters the shield, the projectile goes on through (returns false). Otherwise it bounces: its velocity is
## mirrored about the bubble's surface at the point it struck, losing some speed, and it starts again just outside;
## it can't hurt the holder or bounce off them again. A fireball that has already bounced once bursts here instead,
## just outside the bubble, never inside it.
func _shield_bounce(pr: Proj, q: ServerPlayer, pt: Vector3, prev: Vector3, cur: Vector3) -> bool:
	var c := shield_center(q.state)
	var n := (pt - c).normalized() if pt.distance_to(c) > 1e-3 else (prev - c).normalized()
	var outside := c + n * (Weapons.SHIELD_RADIUS + 0.06)
	var rate := Weapons.SHIELD_MANA_SPELL if pr.kind == 2 else Weapons.SHIELD_MANA_WEAPON
	var dmg := pr.damage if pr.damage > 0 else 12   # a fireball carries no damage of its own (its burst does)
	var left := _shield_soak(q, int(ceil(dmg * rate * 5.0)), outside, dmg)
	if left > 0:
		return false   # it shattered: the projectile carries on through
	if pr.kind == 2 and pr.bounces >= 1:
		_burst(pr, outside)
		return true
	var v := Weapons.proj_vel(pr.vel0, pr.g, server_tick - pr.tick0)
	var r := (v - n * 2.0 * v.dot(n)) * Weapons.SHIELD_BOUNCE
	pr.pos0 = outside
	pr.vel0 = r
	pr.tick0 = server_tick
	pr.last = outside
	pr.immune = q.id
	pr.bounces += 1
	proj_bounce.rpc(pr.id, pr.tick0, pr.pos0, pr.vel0)
	if is_host_player:
		proj_bounce(pr.id, pr.tick0, pr.pos0, pr.vel0)
	return true


## The golem (not the shooter's) a point is inside, or 0.
func _golem_at(pt: Vector3, owner: int) -> int:
	for g: Golems.G in golems.list.values():
		if g.owner != owner and g.state != Golems.State.DIE and Vector2(pt.x - g.pos.x, pt.z - g.pos.z).length() < 0.4 and pt.y > g.pos.y and pt.y < g.pos.y + 1.3:
			return g.id
	return 0


func _end_proj(pr: Proj, pos: Vector3, stuck: bool) -> void:
	projectiles.erase(pr.id)
	if pr.kind > 1:
		return
	if stuck or pos.y < 0.1:   # it can be picked up again where it landed
		_add_item(Weapons.Item.ARROWS if pr.kind == 0 else Weapons.Item.ROCKS, Vector3(pos.x, maxf(WorldLayout.ground_height(pos.x, pos.z, pos.y + 0.1), 0.0), pos.z), 1, -1)
	proj_end.rpc(pr.id, server_tick, pos, stuck)
	if is_host_player:
		proj_end(pr.id, server_tick, pos, stuck)


# ---------------------------------------------------------------- server: items
func _spawn_item_at(i: int) -> void:
	var s: Array = WorldLayout.ITEM_SPAWNS[i]
	_add_item(int(s[0]), s[1], int(s[2]), i)


func _add_item(kind: int, pos: Vector3, count: int, spawn: int) -> void:
	var it := Item.new()
	it.id = next_item
	next_item += 1
	it.kind = kind
	it.pos = pos
	it.count = count
	it.spawn = spawn
	it.born = server_tick
	items[it.id] = it
	if spawn < 0:   # keep the ground tidy: at most 40 dropped things
		var dropped := items.values().filter(func(x): return x.spawn < 0)
		if dropped.size() > 40:
			_remove_item(dropped[0], 0)
	item_add.rpc(it.id, it.kind, it.pos, it.count)
	if is_host_player:
		item_add(it.id, it.kind, it.pos, it.count)


func _remove_item(it: Item, taker: int) -> void:
	items.erase(it.id)
	if it.spawn >= 0 and taker > 0 and it.kind in UNIQUE:
		pass   # the staff and the wand are one of a kind: no new one while someone has it (back when they leave)
	elif it.spawn >= 0:
		respawns.append([server_tick + 20 * Config.TICK_RATE, it.spawn])
	item_remove.rpc(it.id, taker)
	if is_host_player:
		item_remove(it.id, taker)


## Ammo is picked up by walking over it; a weapon by pressing the interact key (E) next to it.
func _server_items() -> void:
	for r in respawns.duplicate():
		if server_tick >= r[0]:
			respawns.erase(r)
			_spawn_item_at(r[1])
	for it: Item in items.values():
		if it.spawn < 0 and server_tick - it.born > 60 * Config.TICK_RATE:
			_remove_item(it, 0)
	for p: ServerPlayer in players.values():
		if p.state.dead == 0:
			_pick_up(p, 1.3, false)


func _pick_up(p: ServerPlayer, reach: float, weapons: bool) -> bool:
	var best: Item = null
	var best_d := reach
	for it: Item in items.values():
		var is_weapon: bool = Weapons.ITEM_WEAPON[it.kind] >= 0
		if is_weapon != weapons:
			continue
		if it.kind == Weapons.Item.WAND and vault_open_until == 0:   # behind the vault's door
			continue
		var d := Vector2(it.pos.x - p.state.pos.x, it.pos.z - p.state.pos.z).length()
		if d <= best_d and absf(it.pos.y - p.state.pos.y) < 1.6:
			best = it
			best_d = d
	if best == null:
		return false
	var s := p.state
	match best.kind:
		Weapons.Item.ARROWS:
			if s.arrows >= Weapons.MAX_AMMO:
				return false
			s.arrows = mini(s.arrows + best.count, Weapons.MAX_AMMO)
		Weapons.Item.ROCKS:
			if s.rocks >= Weapons.MAX_AMMO:
				return false
			s.rocks = mini(s.rocks + best.count, Weapons.MAX_AMMO)
		_:
			s.owned |= 1 << int(Weapons.ITEM_WEAPON[best.kind])
	if LOG:
		print("picked up %s" % Weapons.ITEM_NAMES[best.kind])
	_remove_item(best, p.id)
	return true


## Damage a player (knockback, death) or a dummy (it just shows the number), and tell everyone.
func _damage(target: int, amount: int, from: int, dir: Vector3, knock: float) -> void:
	if LOG and players.has(from):
		var ps: Sim.PlayerState = players[from].state
		var mv := Weapons.move(ps.weapon, ps.combo)
		print("hit %d for %d with %s %s" % [target, amount, Weapons.NAMES[ps.weapon], mv.get("name", "shot")])
	if from > 0 and from == target:   # nobody hurts themselves (their own blasts, spikes, golems)
		return
	if not can_hurt(from, target):
		return
	var killed := false
	var pos: Vector3
	if target == Boss.ID:   # Thunderhorn: his resistances and weaknesses decide what he takes
		if boss == null:
			return
		var took := boss.hurt(amount, from, dmg_spell)
		pos = boss.pos + Vector3(0, 2.4, 0)
		hit_fx.rpc(target, took, pos, dir, boss.hp == 0, from)
		if is_host_player:
			hit_fx(target, took, pos, dir, boss.hp == 0, from)
		return
	if target <= -1000:   # a golem
		var gid := -1000 - target
		if not golems.list.has(gid) or golems.list[gid].owner == from:
			return
		killed = golems.hurt(gid, amount, from, dir)
		pos = golems.list[gid].pos + Vector3(0, 0.9, 0)
		hit_fx.rpc(target, amount, pos, dir, killed, from)
		if is_host_player:
			hit_fx(target, amount, pos, dir, killed, from)
		return
	if target > 0 and players.has(target) and players[target].state.shield > 0:   # the bubble takes it, for mana
		var c: Vector3 = shield_center(players[target].state)
		var back := -Vector3(dir.x, 0, dir.z)
		if back.length() < 1e-4:
			back = Vector3(0, 1, 0)
		var at := c + back.normalized() * Weapons.SHIELD_RADIUS + Vector3(0, -0.2, 0)   # where a blow meets it
		var rate := Weapons.SHIELD_MANA_SPELL if dmg_src >= 0 else Weapons.SHIELD_MANA_WEAPON
		var left := _shield_soak(players[target], int(ceil(amount * rate * 5.0)), at, amount)
		if left <= 0:
			return
		amount = maxi(int(ceil(float(left) / (rate * 5.0))), 1)   # it shattered: the rest gets through
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
			q.state.shield = 0
			killed = true
			if dmg_src >= 0 and players.has(from) and from != target:
				_magic_kill(players[from], dmg_src)
		Sim.quantize(q.state)
		pos = q.state.pos + Vector3(0, 1.3, 0)
	hit_fx.rpc(target, amount, pos, dir, killed, from)
	if is_host_player:
		hit_fx(target, amount, pos, dir, killed, from)


# ---------------------------------------------------------------- client
func _process(_delta: float) -> void:
	var now_us := Time.get_ticks_usec()
	_frame_us = now_us - _last_frame_us if _last_frame_us > 0 else 0
	_last_frame_us = now_us
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
	var aim_yaw: float = PackedFloat32Array([float(b_y[4]) if b_y.size() > 4 else float(b_y[1])])[0]
	var face_yaw: float = PackedFloat32Array([float(b_y[5]) if b_y.size() > 5 else float(b_y[1])])[0]
	var spell: int = int(b_y[6]) if b_y.size() > 6 else 0
	var ap: Vector3 = b_y[7] if b_y.size() > 7 else Vector3.ZERO
	ap = Vector3(PackedFloat32Array([ap.x])[0], PackedFloat32Array([ap.y])[0], PackedFloat32Array([ap.z])[0])   # as sent
	var inp := Sim.PlayerInput.new(next_seq, int(b_y[0]), float(b_y[1]), pitch, int(b_y[3]), int(render_tick), aim_yaw, face_yaw, spell, ap)
	next_seq += 1
	# predict at once
	prev_pos = cur_pos
	var ev := Sim.step(predicted, inp)
	cur_pos = predicted.pos
	if ev == Sim.Ev.SHOT:  # show our own arrow or stone leaving at once; the server's launch follows
		var w := Weapons.get_data(predicted.weapon)
		var sd := Weapons.shot(predicted.weapon, predicted.last_charge)
		local_shot.emit(0 if w.projectile == "arrow" else 1, Weapons.muzzle(predicted.pos, inp.yaw),
			Weapons.aim_dir(inp.aim_yaw, inp.pitch) * float(sd[0]), float(w.gravity))
	elif ev == Sim.Ev.CAST and predicted.weapon == Weapons.STAFF and str(Weapons.spell(Weapons.STAFF, predicted.spell).name) == "Fireball":
		# our own fireball leaves the staff at once too (the same launch the server makes in _cast)
		var sp := Weapons.spell(Weapons.STAFF, predicted.spell)
		var hand := predicted.pos + Vector3(0, 1.45, 0) + Vector3(-sin(predicted.yaw), 0, -cos(predicted.yaw)) * 0.45
		var to := inp.aim_point - hand
		if to.length() < 1.0:
			to = Vector3(-sin(predicted.yaw), 0.05, -cos(predicted.yaw))
		local_shot.emit(2, hand, to.normalized() * float(sp.speed), float(sp.gravity))
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
		cur_pos = replay.pos
		prev_pos += diff
	# always take the server-based state: things only the server changes (health, pick-ups, ammo, a respawn) come in
	# this way, even when our position was predicted exactly
	predicted = replay


## Set the interpolation delay from how unevenly snapshots really arrive: enough to cover 95% of them late plus one
## snapshot interval, no more. Grows at once when the connection gets worse, shrinks slowly when it settles.
##
## v0.8.0: two fixes for others looking laggy. (1) The "on time" base is the fastest arrival in the last 4 s, not since
## the game began, so a slow drift between the two machines' clocks no longer looks like ever-growing lateness (it
## used to push the delay to its 333 ms cap and keep it there). (2) A snapshot handled right after a local hitch (a
## frame over 50 ms: loading, a first-time shader) arrived "late" only because this machine was busy; it says nothing
## about the network, so it's left out.
func _measure_jitter(tick: int) -> void:
	var now := Time.get_ticks_usec() / 1000.0
	var off := now - tick * Config.DT * 1000.0     # arrival time minus send time, plus an unknown constant
	if _frame_us > 50000:
		return
	_offs.append(off)
	if _offs.size() > 120:
		_offs.pop_front()
	var base: float = _offs.min()
	_late_ms.append(off - base)
	if _late_ms.size() > 90:
		_late_ms.pop_front()
	var sorted := _late_ms.duplicate()
	sorted.sort()
	var p95: float = sorted[int((sorted.size() - 1) * 0.95)]
	jitter_ms = p95
	var want := (p95 + 6.0) / (Config.DT * 1000.0) + Config.SNAPSHOT_EVERY
	want = clampf(want, Config.SNAPSHOT_EVERY + 1.0, 20.0)
	interp_delay = want if want > interp_delay else lerpf(interp_delay, want, 0.04)


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
	return (int(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if p else 0) + int(sim_lat_ms)


## Packets lost on the way to the host (%), as ENet sees it (plus the simulator's).
func loss_pct() -> float:
	if peer == null or multiplayer.multiplayer_peer == null or multiplayer.is_server():
		return 0.0
	var p := peer.get_peer(1)
	if p == null:
		return 0.0
	return float(p.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS)) / float(ENetPacketPeer.PACKET_LOSS_SCALE) * 100.0 + sim_loss * 100.0


## One line on how the connection is doing, for the HUD. A client: round trip, jitter, loss, and whether Tailscale
## goes straight to the host or through a relay. The host: each guest's round trip and input buffer (how many ticks
## of their inputs it holds to ride out jitter; times it ran dry).
func quality_line() -> String:
	if multiplayer.multiplayer_peer == null:
		return ""
	if multiplayer.is_server():
		var parts := []
		for p: ServerPlayer in players.values():
			if (p.id == 1 and is_host_player) or p.npc:
				continue
			var pp := peer.get_peer(p.id) if peer else null
			var rtt := int(pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if pp else 0
			var addr := pp.get_remote_address() if pp else ""
			parts.append("%s %d ms, buffer %d, dry %d%s" % [roster.get(p.id, {}).get("name", "?"), rtt, p.target_buf, p.starves, _path_note(addr)])
		return "guests: " + ("  |  ".join(parts) if not parts.is_empty() else "none")
	var addr := peer.get_peer(1).get_remote_address() if peer and peer.get_peer(1) else ""
	return "link: %d ms round trip   jitter %d ms   loss %.1f%%%s" % [ping_ms(), int(jitter_ms), loss_pct(), _path_note(addr)]


func _path_note(addr: String) -> String:
	if not _is_tailscale(addr):
		return ""
	var st: String = tailscale_path.get(addr, "")
	if st == "":
		check_tailscale_path(addr)
		return "   Tailscale: checking"
	return "   Tailscale: " + st


static func _is_tailscale(addr: String) -> bool:
	var p := addr.split(".")
	return p.size() == 4 and int(p[0]) == 100 and int(p[1]) >= 64 and int(p[1]) <= 127


## Ask Tailscale how packets reach this address: "tailscale ping" says "via <ip:port>" for a direct path or
## "via DERP(<city>)" when a relay server carries them (slower and jitterier). Runs in a thread; checked again every
## 30 s, since Tailscale often upgrades a relayed path to a direct one after a while.
func check_tailscale_path(addr: String) -> void:
	tailscale_path[addr] = "checking"
	var th := Thread.new()
	th.start(func():
		var out := []
		var exe := "tailscale"
		if OS.get_name() == "Windows" and FileAccess.file_exists("C:/Program Files/Tailscale/tailscale.exe"):
			exe = "C:/Program Files/Tailscale/tailscale.exe"
		var code := OS.execute(exe, ["ping", "-c", "3", "--timeout", "3s", addr], out, true)
		var text := "\n".join(out)
		var res := "unknown (tailscale CLI not found)" if code == -1 else "unknown"
		var m := RegEx.create_from_string("via DERP\\(([^)]*)\\)").search(text)
		if m:
			res = "RELAYED via DERP %s (slower: see docs/networking.md)" % m.get_string(1)
		elif text.contains("via "):
			res = "direct"
		(func():
			tailscale_path[addr] = res
			th.wait_to_finish()
			get_tree().create_timer(30.0).timeout.connect(func(): tailscale_path.erase(addr))).call_deferred())


# ================================================================ magic (server)
## A spell goes off (the moment in the cast the simulation reports Ev.CAST). Shield and teleport already happened in
## the simulation; here: lightning, fireballs, golems, stuns, and the effects everyone sees.
func _cast(p: ServerPlayer, inp: Sim.PlayerInput, before: Vector3) -> void:
	var s := p.state
	var sp := Weapons.spell(s.weapon, s.spell)
	var hand := s.pos + Vector3(0, 1.45, 0) + Vector3(-sin(s.yaw), 0, -cos(s.yaw)) * 0.45
	match str(sp.name):
		"Lightning":
			var at := _aim_ground(s.pos, inp.aim_point, float(sp.range), s.yaw)
			pending_spells.append([server_tick + int(sp.delay), "lightning", at, p.id])
			_fx("lightning_warn", [at, int(sp.delay), p.id])
		"Fireball":
			var to := inp.aim_point - hand
			if to.length() < 1.0:
				to = Vector3(-sin(s.yaw), 0.05, -cos(s.yaw))
			var pr := Proj.new()
			pr.id = next_proj
			next_proj += 1
			pr.owner = p.id
			pr.kind = 2
			pr.tick0 = server_tick
			pr.pos0 = hand
			pr.vel0 = to.normalized() * float(sp.speed)
			pr.g = float(sp.gravity)
			pr.last = pr.pos0
			projectiles[pr.id] = pr
			proj_spawn.rpc(pr.id, pr.owner, pr.kind, pr.tick0, pr.pos0, pr.vel0, pr.g)
			if is_host_player:
				proj_spawn(pr.id, pr.owner, pr.kind, pr.tick0, pr.pos0, pr.vel0, pr.g)
			_fx("cast", [p.id, "fire"])
		"Shield":
			_fx("shield_up", [p.id])
		"Golem":
			var at := _aim_ground(s.pos, inp.aim_point, float(sp.range), s.yaw)
			at.y = 0.0
			var g := golems.spawn(p.id, at, s.yaw, server_tick)
			_fx("golem_rise", [g.id, at])
		"Teleport":
			_fx("teleport", [p.id, before, s.pos])
		"Meteor":
			var at := _aim_ground(s.pos, inp.aim_point, float(sp.range), s.yaw)
			pending_spells.append([server_tick + int(sp.delay), "meteor", at, p.id])
			_fx("meteor_warn", [at, int(sp.delay), float(sp.radius)])
		"Arcane Storm":
			var at := _aim_ground(s.pos, inp.aim_point, float(sp.range), s.yaw)
			storms.append([server_tick + int(sp.duration), at, p.id, server_tick + 10])
			_fx("storm", [at, int(sp.duration), float(sp.area)])
		"Stone Titan":
			var at := _aim_ground(s.pos, inp.aim_point, float(sp.range), s.yaw)
			at.y = 0.0
			var g := golems.spawn(p.id, at, s.yaw, server_tick, true)
			_fx("titan_rise", [g.id, at])
		"Gravity Well":
			var at := _aim_ground(s.pos, inp.aim_point, float(sp.range), s.yaw)
			wells.append([server_tick + int(sp.duration), at + Vector3(0, 1.0, 0), p.id])
			_fx("well", [at + Vector3(0, 1.0, 0), int(sp.duration), float(sp.pull_radius)])
		"Frost Nova":
			_fx("frost_nova", [p.id, s.pos, float(sp.radius)])
			_blast(s.pos + Vector3(0, 0.5, 0), sp, p.id, Weapons.STAFF)
			for q: ServerPlayer in players.values():   # everyone caught in it is slowed (not through a shield)
				if q.id != p.id and q.state.dead == 0 and q.state.shield == 0 and can_hurt(p.id, q.id) \
						and _dist_to_body(s.pos + Vector3(0, 0.5, 0), q.state.pos) <= float(sp.radius):
					q.state.slow = int(sp.slow)
			if boss != null and _dist_to_body(s.pos + Vector3(0, 0.5, 0), boss_surface(s.pos)) <= float(sp.radius):
				boss.frosted()
		"Earth Spikes":
			var d := Vector2(inp.aim_point.x - s.pos.x, inp.aim_point.z - s.pos.z)
			if d.length() < 0.5:
				d = Vector2(-sin(s.yaw), -cos(s.yaw))
			d = d.normalized()
			for k in int(sp.spikes):
				var at := s.pos + Vector3(d.x, 0, d.y) * (1.6 + k * float(sp.spacing))
				at.y = WorldLayout.ground_height(at.x, at.z, s.pos.y + 0.5)
				if _in_box(at + Vector3(0, 0.3, 0)) or Vector2(at.x - s.pos.x, at.z - s.pos.z).length() > float(sp.range):
					break   # the line stops at a pillar
				pending_spells.append([server_tick + 3 + k * 3, "spike", at, p.id])
			_fx("cast", [p.id, "earth"])
		"Stun":
			var tgt := _stun_target(p, hand, inp.aim_point, float(sp.range))
			var end: Vector3 = tgt[1]
			if tgt[0] == 0 and hand.distance_to(inp.aim_point) < hand.distance_to(end) and inp.aim_point.length() > 0.0:
				end = inp.aim_point   # nobody in the way: it bursts at the crosshair point
			var r := float(sp.radius)
			var caught := 0
			for q: ServerPlayer in players.values():   # every enemy in the burst is held (a shield soaks it for mana)
				if q.id == p.id or q.state.dead > 0 or not can_hurt(p.id, q.id) or _dist_to_body(end, q.state.pos) > r:
					continue
				if q.state.shield > 0 and _shield_soak(q, Weapons.SHIELD_MANA_STUN * 5, end, 12) <= 0:
					continue
				q.state.stun = int(sp.duration)
				q.state.charge = 0
				caught += 1
			for g: Golems.G in golems.list.values():
				if g.owner != p.id and _dist_to_body(end, g.pos) <= r:
					golems.stun(g.id, int(sp.duration))
					caught += 1
			if boss != null and _dist_to_body(end, boss_surface(end)) <= r:
				boss.stunned(server_tick)   # it only staggers him (shorter each time)
				caught += 1
			_fx("stun_beam", [p.id, hand, end, caught])
			_fx("stun_burst", [end, r])


## A point on the ground (or a pillar top) under where the crosshair is, no further than `reach` from `from`.
func _aim_ground(from: Vector3, aim: Vector3, reach: float, yaw: float) -> Vector3:
	var d := Vector2(aim.x - from.x, aim.z - from.z)
	if d.length() < 0.5:
		d = Vector2(-sin(yaw), -cos(yaw)) * minf(reach, 8.0)
	if d.length() > reach:
		d = d.normalized() * reach
	var x := from.x + d.x
	var z := from.z + d.y
	return Vector3(x, WorldLayout.ground_height(x, z, maxf(aim.y, from.y) + 0.3), z)


## Who the stun bolt hits: the first player (that the caster may fight) or other summoner's golem along the line from
## the wand toward the crosshair point, within reach. -> [target id or 0, where the bolt ends].
func _stun_target(p: ServerPlayer, from: Vector3, aim: Vector3, reach: float) -> Array:
	var dir := aim - from
	if dir.length() < 0.5:
		dir = Vector3(-sin(p.state.yaw), 0, -cos(p.state.yaw))
	dir = dir.normalized()
	var best := 0
	var best_t := reach
	for q: ServerPlayer in players.values():
		if q.id == p.id or q.state.dead > 0 or not can_hurt(p.id, q.id):
			continue
		var t := _ray_cyl(from, dir, q.state.pos, 0.6, 1.9)
		if t < best_t:
			best_t = t
			best = q.id
	for g: Golems.G in golems.list.values():
		if g.owner != p.id and g.state != Golems.State.DIE:
			var t := _ray_cyl(from, dir, g.pos, 0.45, 1.3)
			if t < best_t:
				best_t = t
				best = -1000 - g.id
	var wall := WorldLayout.ray_hit(from, dir, best_t)
	if wall < best_t:
		return [0, from + dir * wall]
	return [best, from + dir * best_t]


func _ray_cyl(o: Vector3, d: Vector3, c: Vector3, r: float, h: float) -> float:
	var oc := Vector2(o.x - c.x, o.z - c.z)
	var dd := Vector2(d.x, d.z)
	var a := dd.dot(dd)
	if a < 1e-8:
		return INF
	var b := 2.0 * oc.dot(dd)
	var cc := oc.dot(oc) - r * r
	var disc := b * b - 4.0 * a * cc
	if disc < 0.0:
		return INF
	var t := (-b - sqrt(disc)) / (2.0 * a)
	if t < 0.0:
		t = (-b + sqrt(disc)) / (2.0 * a)
	if t < 0.0:
		return INF
	var y := o.y + d.y * t
	return t if y > c.y - 0.2 and y < c.y + h else INF


## Area damage round a point (lightning, a fireball's blast): the closer to the centre, the harder it hits (full
## damage at the centre down to the spell's minimum at its edge), and the further it throws. Shields soak it.
## -> the enemies it struck (ids as _damage takes them: players, -(dummy + 1), -1000 - golem), for chain lightning.
func _blast(center: Vector3, sp: Dictionary, owner: int, src := Weapons.STAFF) -> Array:
	dmg_src = src
	dmg_spell = str(sp.get("name", "Burn"))
	if boss != null:   # Thunderhorn
		var bd := _dist_to_body(center, boss_surface(center))
		var bdmg := Weapons.area_damage(sp, bd)
		if bdmg > 0:
			hit_list_boss = true
			_damage(Boss.ID, bdmg, owner, boss.pos - center, 0.0)
	var hit := []
	var r := float(sp.radius)
	for q: ServerPlayer in players.values():
		if q.state.dead > 0 or q.id == owner:
			continue
		var body := q.state.pos + Vector3(0, 0.9, 0)
		var d := _dist_to_body(center, q.state.pos)
		var dmg := Weapons.area_damage(sp, d)
		if dmg > 0:
			var dir := body - center
			if can_hurt(owner, q.id):
				hit.append(q.id)
			_damage(q.id, dmg, owner, Vector3(dir.x, 0, dir.z), float(sp.knock) * (1.0 - 0.5 * d / r))
	for i in WorldLayout.DUMMIES.size():
		var d := _dist_to_body(center, WorldLayout.DUMMIES[i])
		var dmg := Weapons.area_damage(sp, d)
		if dmg > 0:
			hit.append(-(i + 1))
			_damage(-(i + 1), dmg, owner, WorldLayout.DUMMIES[i] - center, 0.0)
	for g: Golems.G in golems.list.values().duplicate():
		var d := _dist_to_body(center, g.pos)
		var dmg := Weapons.area_damage(sp, d)
		if dmg > 0:
			if g.owner != owner:
				hit.append(-1000 - g.id)
			_damage(-1000 - g.id, dmg, owner, g.pos - center, 0.0)
	if ecology:
		for i in WorldLayout.TREES.size():
			var tp: Vector3 = WorldLayout.TREES[i][1]
			if Vector2(tp.x - center.x, tp.z - center.z).length() < r + 0.4:
				ecology.hit_tree(i, Weapons.area_damage(sp, 0.0), server_tick, tp - center)
		ecology.blast_fruit(center, r, server_tick)
	dmg_src = -1
	dmg_spell = ""
	if hit_list_boss:
		hit.append(Boss.ID)
		hit_list_boss = false
	return hit


## Chain lightning (v0.8.2): one jump. e = [tick, "chain", where, caster, from (the one it's jumping from), the damage
## it hit them with, everyone hit by this cast, jumps so far]. It jumps to the nearest enemy of the caster not yet hit,
## within chain_range of `from` (body to body), for half the damage; a shield soaks it and the branch ends there.
func _chain_jump(e: Array, owner: int) -> void:
	var sp := Weapons.spell(Weapons.STAFF, 0)
	var from = _target_feet(int(e[4]))
	var dmg := maxi(int(round(float(e[5]) / 2.0)), 1)
	var jumps := int(e[7]) + 1
	if from == null or dmg < 2 or jumps > int(sp.chain_max):
		return
	var seen: Dictionary = e[6]
	var best := 0
	var best_d := float(sp.chain_range)
	for t in _chain_candidates(e[3]):
		if seen.has(t):
			continue
		var at = _target_feet(t)
		if at == null:
			continue
		var d := (at as Vector3).distance_to(from)
		if d < best_d:
			best_d = d
			best = t
	if best == 0:
		return
	seen[best] = true
	var to: Vector3 = _target_feet(best)
	var shielded := _shield_up(best)
	_fx("chain", [from + Vector3(0, 1.1, 0), to + Vector3(0, 1.1, 0), dmg, int(sp.max_damage)])
	dmg_src = Weapons.STAFF
	dmg_spell = "Lightning"
	_damage(best, dmg, owner, to - from, 2.0)
	dmg_src = -1
	dmg_spell = ""
	if not shielded:
		pending_spells.append([server_tick + int(sp.chain_every), "chain", to, e[3], best, dmg, seen, jumps])


## Who chain lightning may jump to: the same rules as everything else: players the caster may hurt (PvP), other
## summoners' golems and titans, practice dummies; never the caster or their own golems.
func _chain_candidates(caster: int) -> Array:
	var out := []
	for q: ServerPlayer in players.values():
		if q.id != caster and q.state.dead == 0 and can_hurt(caster, q.id):
			out.append(q.id)
	for g: Golems.G in golems.list.values():
		if g.owner != caster and g.state != Golems.State.DIE:
			out.append(-1000 - g.id)
	for i in WorldLayout.DUMMIES.size():
		out.append(-(i + 1))
	if boss != null:
		out.append(Boss.ID)
	return out


func _target_feet(t: int):
	if t == Boss.ID:
		return boss.pos if boss != null else null
	if t > 0:
		return players[t].state.pos if players.has(t) and players[t].state.dead == 0 else null
	if t <= -1000:
		var g = golems.list.get(-1000 - t, null)
		return g.pos if g != null and g.state != Golems.State.DIE else null
	if -t - 1 < WorldLayout.DUMMIES.size():
		return WorldLayout.DUMMIES[-t - 1]
	return null


func _shield_up(t: int) -> bool:
	return t > 0 and players.has(t) and players[t].state.shield > 0


## Distance from a point to a standing body (an upright segment from its feet to 1.8 m up).
func _dist_to_body(c: Vector3, feet: Vector3) -> float:
	var y := clampf(c.y, feet.y, feet.y + 1.8)
	return c.distance_to(Vector3(feet.x, y, feet.z))


func _server_spells() -> void:
	for e in pending_spells.duplicate():
		if server_tick >= e[0]:
			pending_spells.erase(e)
			var owner: int = e[3] if players.has(e[3]) else 0
			match str(e[1]):
				"lightning":
					_fx("lightning", [e[2]])
					var lsp := Weapons.spell(Weapons.STAFF, 0)
					var struck := _blast(e[2], lsp, owner, Weapons.STAFF)
					var seen := {}   # everyone hit by this cast (each at most once)
					for t in struck:
						seen[t] = true
					for t in struck:   # each one struck starts a chain at half the damage
						if not _shield_up(t):
							pending_spells.append([server_tick + int(lsp.chain_every), "chain", e[2], e[3], t, int(lsp.max_damage), seen, 0])
				"chain":
					_chain_jump(e, owner)
				"boss_strike":   # Thunderhorn's called lightning
					_fx("lightning", [e[2]])
					for q: ServerPlayer in players.values():
						if q.state.dead == 0 and not q.npc and _dist_to_body(e[2], q.state.pos) <= 2.5:
							_damage(q.id, 18, Boss.ID, q.state.pos - e[2], 4.0)
				"spike":
					_fx("spike", [e[2]])
					_blast(e[2], Weapons.spell(Weapons.WAND, 3), owner, Weapons.WAND)
				"meteor":
					var sp := Weapons.spell(Weapons.STAFF, 4)
					_fx("meteor", [e[2], float(sp.radius), int(sp.burn_ticks), float(sp.burn_radius)])
					_blast(e[2], sp, owner, Weapons.STAFF)
					for k in int(sp.burn_ticks) / int(sp.burn_every):
						pending_spells.append([server_tick + int(sp.burn_every) * (k + 1), "burn", e[2], e[3]])
				"storm_bolt":
					_fx("lightning", [e[2]])
					_blast(e[2], Weapons.spell(Weapons.STAFF, 5), owner, Weapons.STAFF)
				"burn":
					var sp := Weapons.spell(Weapons.STAFF, 4)
					var burn := { "radius": sp.burn_radius, "max_damage": sp.burn_damage, "min_damage": sp.burn_damage, "knock": 0.0 }
					_blast(e[2], burn, owner, Weapons.STAFF)
	_server_wells()
	_server_storms()
	# golems
	var people := []
	for p: ServerPlayer in players.values():
		people.append([p.id, p.state.pos, p.pvp or p.npc, p.state.dead == 0])
	if boss != null and boss.state != Boss.S.ENTER and boss.state != Boss.S.DEATH:
		people.append([Boss.ID, boss.pos, true, true])   # everyone's golems fight him
	for h in golems.tick(server_tick, people):
		var g: Golems.G = h[0]
		var tid: int = h[1]
		dmg_src = Weapons.WAND
		if tid <= -1000:
			_damage(tid, int(h[2]), g.owner, h[3], 0.0)
		else:
			_damage(tid, int(h[2]), g.owner, h[3], Golems.TITAN_KNOCK if g.titan else Golems.KNOCK)
		dmg_src = -1
		_fx("golem_slam", [g.id, g.pos + Vector3(-sin(g.yaw), 0, -cos(g.yaw)) * (Golems.TITAN_REACH if g.titan else 0.7), g.titan])
	if server_tick % 3 == 0 and (not golems.list.is_empty() or _golems_were):
		_golems_were = not golems.list.is_empty()
		var data := golems.pack()
		golem_states.rpc(server_tick, data)
		if is_host_player:
			golem_states(server_tick, data)
	# the vault door shuts itself after a while
	if vault_open_until > 0 and server_tick >= vault_open_until:
		vault_open_until = 0
		_fx("vault_door", [false])


var _golems_were := false


## E at the vault's door: open it (it shuts itself after 25 s). True if this press was used on the door.
func _vault_interact(p: ServerPlayer) -> bool:
	var d := WorldLayout.VAULT_DOOR
	var me := p.state.pos
	if vault_open_until > 0 or Vector2(me.x - d.x, me.z - d.z).length() > 2.0 or me.x < d.x - 0.3 or me.y > 1.5:
		return false
	vault_open_until = server_tick + 25 * Config.TICK_RATE
	_fx("vault_door", [true])
	return true


## A spell effect for everyone to see (reliable, in order); the host's own screen gets it too.
func _fx(kind: String, args: Array) -> void:
	spell_fx.rpc(kind, args)
	if is_host_player:
		magic_fx.emit(kind, args)


@rpc("authority", "call_remote", "reliable", 4)
func spell_fx(kind: String, args: Array) -> void:
	magic_fx.emit(kind, args)


## Golems, a few times a second: [id, owner, x, y, z, yaw, state, t, hp, stunned] each.
@rpc("authority", "call_remote", "unreliable_ordered", 5)
func golem_states(tick: int, data: Array) -> void:
	golems_changed.emit(tick, data)


var dmg_src := -1
var dmg_spell := ""        # v0.10.0: the spell dealing the damage right now (Thunderhorn resists some)
var hit_list_boss := false   # while a spell's damage is being dealt: the weapon it counts for (Weapons.STAFF / WAND), else -1


## A player was knocked out with the staff or wand: count it; at 3, 8 and 18 kills the weapon levels up and gains its
## next spell (Weapons.LEVEL_KILLS), with a burst of light for everyone and the news on the killer's screen.
func _magic_kill(p: ServerPlayer, w: int) -> void:
	var i := 0 if w == Weapons.STAFF else 1
	p.kills[i] += 1
	var lv := Weapons.level_for(int(p.kills[i]))
	var cur := p.state.staff_lvl if w == Weapons.STAFF else p.state.wand_lvl
	if lv > cur:
		if w == Weapons.STAFF:
			p.state.staff_lvl = lv
		else:
			p.state.wand_lvl = lv
		var spells: Array = Weapons.get_data(w).spells
		var name := ""
		for sp in spells:
			if int(sp.get("level", 1)) == lv:
				name = str(sp.name)
		_fx("level_up", [p.id, w, lv, name])
		print("%s's %s reached level %d: %s" % [p.name, Weapons.NAMES[w], lv, name])
	_server_send_roster()


## A hit on a held shield, costing `cost` (fifths of a mana point). Paid in full: a ripple, returns 0. Not enough
## mana: the shield shatters, the mana is gone, it can't be raised for a moment; returns what the mana couldn't pay.
func _shield_soak(q: ServerPlayer, cost: int, at: Vector3, strength := 8) -> int:
	var s := q.state
	if s.mana >= cost:
		s.mana -= cost
		_fx("shield_hit", [q.id, at, strength])   # a ripple from that point, as big as the hit
		return 0
	var left := cost - s.mana
	s.mana = 0
	s.shield = 0
	s.atk_cd = maxi(s.atk_cd, Weapons.SHIELD_BROKEN)
	_fx("shield_shatter", [q.id, shield_center(s), at])
	return left


## A player who had the staff or the wand leaves: it goes back where it came from (the tower's top, the vault).
func _return_unique(p: ServerPlayer) -> void:
	for kind in UNIQUE:
		var w: int = Weapons.ITEM_WEAPON[kind]
		if (p.state.owned >> w) & 1:
			for i in WorldLayout.ITEM_SPAWNS.size():
				if int(WorldLayout.ITEM_SPAWNS[i][0]) == kind:
					_spawn_item_at(i)


## Gravity wells: each tick, enemies within reach are dragged toward the centre (harder the closer they are, like real
## gravity, up to a cap) and the caster's enemies' golems slide in too; every half second those near its heart take a
## nibble; at the end it bursts outward.
func _server_wells() -> void:
	var sp := Weapons.spell(Weapons.WAND, 4)
	for e in wells.duplicate():
		var c: Vector3 = e[1]
		var owner: int = e[2]
		if server_tick >= e[0]:
			wells.erase(e)
			_fx("well_burst", [c, float(sp.radius)])
			_blast(c, sp, owner if players.has(owner) else 0, Weapons.WAND)
			continue
		for q: ServerPlayer in players.values():
			if q.id == owner or q.state.dead > 0 or not can_hurt(owner, q.id):
				continue
			var d := Vector2(c.x - q.state.pos.x, c.z - q.state.pos.z)
			if d.length() > float(sp.pull_radius) or d.length() < 0.3:
				continue
			# stronger the closer you are; on top of cancelling the ground's grip, so standing still you drift in and
			# running away you lose ground
			var k := clampf(1.2 - d.length() / float(sp.pull_radius), 0.35, 1.0)
			var pull := d.normalized() * (float(sp.pull) * k + Sim.GROUND_ACCEL) * Config.DT
			q.state.vel.x += pull.x
			q.state.vel.z += pull.y
			var hv := Vector2(q.state.vel.x, q.state.vel.z)
			if hv.length() > 8.0:
				hv = hv.normalized() * 8.0
				q.state.vel.x = hv.x
				q.state.vel.z = hv.y
			Sim.quantize(q.state)
			if server_tick % 30 == 0 and d.length() <= float(sp.nibble_radius):
				dmg_src = Weapons.WAND
				_damage(q.id, int(sp.nibble), owner, Vector3(-d.x, 0, -d.y), 0.0)
				dmg_src = -1
		for g: Golems.G in golems.list.values():
			if g.owner != owner and g.state != Golems.State.DIE:
				var d := Vector2(c.x - g.pos.x, c.z - g.pos.z)
				if d.length() < float(sp.pull_radius) and d.length() > 0.3:
					golems._move(g, d.normalized() * 3.0 * Config.DT)


## Arcane storms: every `every` ticks a bolt is called down: on an enemy under the cloud (a little off, so a moving
## target can dodge the warning ring) two times in three, else anywhere under it; each bolt warns, then strikes.
func _server_storms() -> void:
	var sp := Weapons.spell(Weapons.STAFF, 5)
	for e in storms.duplicate():
		if server_tick >= e[0]:
			storms.erase(e)
			continue
		if server_tick < e[3]:
			continue
		e[3] = server_tick + int(sp.every)
		var c: Vector3 = e[1]
		var owner: int = e[2]
		var area := float(sp.area)
		var targets := []
		for q: ServerPlayer in players.values():
			if q.id != owner and q.state.dead == 0 and can_hurt(owner, q.id) and Vector2(q.state.pos.x - c.x, q.state.pos.z - c.z).length() <= area:
				targets.append(q.state.pos)
		for g: Golems.G in golems.list.values():
			if g.owner != owner and g.state != Golems.State.DIE and Vector2(g.pos.x - c.x, g.pos.z - c.z).length() <= area:
				targets.append(g.pos)
		var at: Vector3
		if not targets.is_empty() and randf() < 0.67:
			at = targets[randi() % targets.size()] + Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8))
		else:
			var a := randf() * TAU
			var r := sqrt(randf()) * area
			at = c + Vector3(cos(a) * r, 0, sin(a) * r)
		at.y = WorldLayout.ground_height(at.x, at.z, c.y + 3.0)
		pending_spells.append([server_tick + int(sp.warn), "storm_bolt", at, owner])
		_fx("lightning_warn", [at, int(sp.warn), owner])


## How many real players are here (challengers don't count).
func humans() -> int:
	var n := 0
	for p: ServerPlayer in players.values():
		if not p.npc:
			n += 1
	return n


# ================================================================ v0.10.0: the Duel Stone, NPCs, the Storm Altar, Thunderhorn
## The point on Thunderhorn's body nearest to `from` (his body is a column RADIUS wide): what melee, blasts and chains
## measure to.
func boss_surface(from: Vector3) -> Vector3:
	var d := Vector2(from.x - boss.pos.x, from.z - boss.pos.z)
	var r := minf(d.length(), Boss.RADIUS)
	var n := d.normalized() if d.length() > 1e-3 else Vector2(0, 1)
	return boss.pos + Vector3(n.x * r, clampf(from.y - boss.pos.y, 0.0, Boss.HEIGHT - 1.8), n.y * r)


## The weapons a challenger may have: bow, slingshot, sword, club; once the presser has levelled the staff or the wand
## up (level 2), wizards too.
static func duel_pool(staff_lvl: int, wand_lvl: int) -> Array:
	var pool := [Weapons.BOW, Weapons.SLING, Weapons.SWORD, Weapons.CLUB]
	if maxi(staff_lvl, wand_lvl) >= 2:
		pool.append_array([Weapons.STAFF, Weapons.WAND])
	return pool


const NPC_NAMES := ["Brutus", "Grizelda", "Morwen", "Tobias", "Ragnhild", "Corvin", "Ysolde", "Barnaby", "Thane", "Vesper",
	"Odalric", "Mirela", "Fenwick", "Sable"]


## E at the Duel Stone: a challenger arrives (one at a time per player).
func _stone_interact(p: ServerPlayer) -> bool:
	if p.npc or Vector2(p.state.pos.x - WorldLayout.DUEL_C.x, p.state.pos.z - WorldLayout.DUEL_C.y).length() > DUEL_REACH:
		return false
	for q: ServerPlayer in players.values():
		if q.npc and q.ai.owner == p.id and q.state.dead == 0:
			_toast(p.id, "Defeat your challenger first")
			return true
	spawn_npc(p, -1)
	return true


## A challenger for `presser`: weapon -1 picks one from the stone's pool. Returns the new NPC.
func spawn_npc(presser: ServerPlayer, weapon := -1, difficulty := 1) -> ServerPlayer:
	var pool := duel_pool(presser.state.staff_lvl, presser.state.wand_lvl)
	var w: int = weapon if weapon >= 0 else pool[randi() % pool.size()]
	var q := ServerPlayer.new()
	q.id = next_npc
	next_npc += 1
	q.npc = true
	q.name = "Challenger " + NPC_NAMES[randi() % NPC_NAMES.size()]
	q.color = Color("d23a2a")
	q.character = presser.character
	q.outfit = 3
	q.pvp = true
	q.slot = 0
	q.state = Sim.PlayerState.new()
	var away := Vector2(presser.state.pos.x - WorldLayout.DUEL_C.x, presser.state.pos.z - WorldLayout.DUEL_C.y)
	away = away.normalized() if away.length() > 0.1 else Vector2(0, 1)
	var at := Vector3(WorldLayout.DUEL_C.x, 0, WorldLayout.DUEL_C.y) - Vector3(away.x, 0, away.y) * 5.0
	q.state.pos = at
	q.state.yaw = atan2(away.x, away.y)
	q.state.owned = 1 | (1 << w)
	q.state.weapon = w
	q.state.arrows = 99
	q.state.rocks = 99
	var lv := maxi(presser.state.staff_lvl, presser.state.wand_lvl)   # wizards never above the presser's level
	q.state.staff_lvl = clampi(lv, 1, Weapons.MAX_LEVEL)
	q.state.wand_lvl = clampi(lv, 1, Weapons.MAX_LEVEL)
	Sim.quantize(q.state)
	q.primed = true
	q.ai = NpcAI.new(q.id, presser.id, w, difficulty)
	players[q.id] = q
	_server_send_roster()
	_fx("npc_arrive", [q.id, at])
	_toast(presser.id, "%s steps out to fight you with the %s!" % [q.name, Weapons.NAMES[w].to_lower()])
	return q


## Every tick: each challenger thinks (its input goes in its queue like a player's), keeps its ammo, and once it has
## lain on the ground a moment after falling, it's gone.
func _server_npcs() -> void:
	for q: ServerPlayer in players.values().duplicate():
		if not q.npc:
			continue
		if q.state.dead > 0 and q.state.dead < Sim.RESPAWN_TICKS - 90:
			_fx("npc_leave", [q.id, q.state.pos])
			players.erase(q.id)
			_server_send_roster()
			continue
		q.state.arrows = 99
		q.state.rocks = 99
		var inp := q.ai.think(self, q)
		inp.seq = q.last_applied + 1
		q.queue[inp.seq] = inp


@rpc("authority", "call_remote", "reliable")
func toast(text: String) -> void:
	toast_msg.emit(text)


func _toast(id: int, text: String) -> void:
	if id == my_id:
		toast_msg.emit(text)
	elif id > 0 and id < 1000000 and is_inside_tree() and multiplayer.multiplayer_peer != null:
		toast.rpc_id(id, text)


## Landing on the Storm Altar (from a jump), at level 3 or more, with no boss about: Thunderhorn comes.
func _server_altar() -> void:
	for p: ServerPlayer in players.values():
		if p.npc:
			continue
		var landed := p.air and p.state.grounded
		p.air = not p.state.grounded
		if not landed or boss != null or defeated or p.state.dead > 0:
			continue
		if Vector2(p.state.pos.x - WorldLayout.ALTAR_C.x, p.state.pos.z - WorldLayout.ALTAR_C.y).length() > ALTAR_R:
			continue
		if maxi(p.state.staff_lvl, p.state.wand_lvl) < 3:
			_toast(p.id, "The Storm Altar answers only to level 3")
			continue
		summon_boss()


func summon_boss() -> void:
	boss_fighters = []
	for p: ServerPlayer in players.values():
		if not p.npc:
			boss_fighters.append(p.id)
	var at := Vector3(WorldLayout.ALTAR_C.x, 0, WorldLayout.ALTAR_C.y + 14.0)
	boss = Boss.new(at, boss_fighters.size())
	boss.yaw = 0.0


## Thunderhorn each tick: his brain, then what he did (hits, slows, called lightning, effects); his state to everyone;
## victory when his death has played out; defeat when every fighter is down at once.
func _server_boss() -> void:
	if defeated:
		defeat_t += 1
		return
	if boss == null:
		return
	var people := []
	for id in boss_fighters:
		if players.has(id):
			var p: ServerPlayer = players[id]
			var s := p.state
			people.append([id, s.pos, s.dead == 0, s.shield > 0, s.hp, s.dash_ticks,
				Weapons.is_magic(s.weapon) and (s.atk > 0 or s.shield > 0), s.stun > 0 or s.down > 0])
	var gl := []
	for g: Golems.G in golems.list.values():
		if g.state != Golems.State.DIE:
			gl.append([g.id, g.pos])
	boss.tick(server_tick, people, gl)
	for h in boss.hits:
		_damage(int(h[0]), int(h[1]), Boss.ID, h[2], float(h[3]))
	boss.hits.clear()
	for z in boss.zaps:   # static: damage, and a stack unless a shield took it
		_boss_zap(int(z[0]), int(z[1]), z[2], bool(z[3]))
	boss.zaps.clear()
	for l in boss.launches:   # the rush: thrown across the arena, knocked down
		boss_launch(int(l[0]), l[1])
	boss.launches.clear()
	for sl in boss.slows:
		if players.has(sl[0]) and players[sl[0]].state.shield == 0:
			players[sl[0]].state.slow = maxi(players[sl[0]].state.slow, int(sl[1]))
	boss.slows.clear()
	for st in boss.strikes:
		_fx("lightning_warn", [st[0], int(st[1]), 0])
		pending_spells.append([server_tick + int(st[1]), "boss_strike", st[0], 0])
	boss.strikes.clear()
	for e in boss.fx:
		_fx(str(e[0]), e[1])
	boss.fx.clear()
	if server_tick % 2 == 0:
		var data := boss.pack()
		boss_state.rpc(server_tick, data)
		if is_host_player:
			boss_state(server_tick, data)
	if boss.done:   # victory!
		boss = null
		boss_state.rpc(server_tick, [])
		if is_host_player:
			boss_state(server_tick, [])
		_result("victory")
		return
	var down := 0
	for id in boss_fighters:
		if not players.has(id) or players[id].state.dead > 0:
			down += 1
	if down == boss_fighters.size() and boss_fighters.size() > 0:
		_fx("boss_leave", [boss.pos])
		boss = null
		boss_state.rpc(server_tick, [])
		if is_host_player:
			boss_state(server_tick, [])
		defeated = true
		defeat_t = 0
		for id in boss_fighters:   # they stay down until someone presses a key
			if players.has(id):
				players[id].state.dead = Sim.RESPAWN_TICKS + 99999
		_result("defeat")


## A static hit from Thunderhorn (v0.11.0): the damage, then a stack of Static; at Boss.static_need stacks (6, 5 while
## he's enraged) a 7 s stun. A shield takes the hit (for mana) and no stack; a static-stunned player takes no more.
func _boss_zap(id: int, dmg: int, dir: Vector3, blocked: bool) -> void:
	if not players.has(id):
		return
	var q: ServerPlayer = players[id]
	if q.state.dead > 0:
		return
	var shielded := q.state.shield > 0
	if dmg > 0:
		_damage(id, dmg, Boss.ID, dir, 1.5)
	if blocked or shielded or q.state.dead > 0 or q.state.zap >= Sim.ZAP_STUN:
		return
	add_static(q, Boss.static_need(boss != null and boss.enraged))


func add_static(q: ServerPlayer, need: int) -> void:
	var s := q.state
	s.zap = mini(s.zap + Sim.ZAP_STACK, Sim.ZAP_STACK * need)
	s.zap_cd = Sim.ZAP_HOLD
	if s.zap >= Sim.ZAP_STACK * need:
		s.zap = Sim.ZAP_STUN
		s.stun = Sim.STATIC_STUN
		s.charge = 0
		s.shield = 0
		_fx("static_stun", [q.id, s.pos])
	else:
		_fx("static_hit", [q.id, s.pos + Vector3(0, 1.0, 0), s.zap / Sim.ZAP_STACK])


## Thrown by the rush: flying ~15 m, then knocked down (Sim.DOWN_TICKS). A held shield that survives the hit stops it.
func boss_launch(id: int, dir: Vector3) -> void:
	if not players.has(id):
		return
	var s: Sim.PlayerState = players[id].state
	if s.dead > 0 or s.shield > 0:
		return
	var d := Vector3(dir.x, 0, dir.z).normalized()
	s.vel = d * 17.0 + Vector3(0, 10.0, 0)
	s.grounded = false
	s.dash_ticks = 0
	s.charge = 0
	s.down = Sim.DOWN_TICKS
	Sim.quantize(s)
	_fx("boss_launch", [id, s.pos, d])


## After a defeat: everyone back on their feet at the spawn with full health, the boss gone and the altar ready again.
## Their weapons and levels stay (so they can try again).
func restart_after_defeat() -> void:
	if not defeated:
		return
	defeated = false
	for id in boss_fighters:
		if players.has(id):
			var p: ServerPlayer = players[id]
			var old := p.state
			p.state = Sim.spawn_state(p.slot)
			p.state.weapon = old.weapon
			p.state.owned = old.owned
			p.state.arrows = old.arrows
			p.state.rocks = old.rocks
			p.state.staff_lvl = old.staff_lvl
			p.state.wand_lvl = old.wand_lvl
			p.was_dead = false
	boss_fighters = []
	_result("restart")


@rpc("any_peer", "call_remote", "reliable")
func request_restart() -> void:
	if multiplayer.is_server():
		restart_after_defeat()


## The player pressed a key on the defeat screen.
func ask_restart() -> void:
	if not is_inside_tree() or multiplayer.multiplayer_peer == null or multiplayer.is_server():
		restart_after_defeat()
	else:
		request_restart.rpc_id(1)


func _result(kind: String) -> void:
	if is_inside_tree() and multiplayer.multiplayer_peer != null:
		boss_end.rpc(kind)
	boss_result.emit(kind)   # here too (the host's own screen; a dedicated server has nobody listening)


@rpc("authority", "call_remote", "reliable")
func boss_end(kind: String) -> void:
	boss_result.emit(kind)


@rpc("authority", "call_remote", "unreliable_ordered", 5)
func boss_state(tick: int, data: Array) -> void:
	boss_changed.emit(tick, data)

