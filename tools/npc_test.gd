extends SceneTree
## v0.10.0, the server's side, run offline: the Duel Stone (who it summons before and after the first level-up, one
## challenger at a time), challengers that really fight (a swordsman closes in and hits; an archer leads its shots and
## lands them), kills on challengers levelling the staff, Thunderhorn's health with one and two players, how every
## spell affects him, victory starting the prize, and defeat -> restart (alone, and with two players).
##   Godot --headless --path . --script tools/npc_test.gd   (prints harmless "not inside tree" RPC errors)

var bad := 0
var results := []


func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		bad += 1


func _initialize() -> void:
	var net := Net.new()
	root.add_child(net)
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	net.boss_result.connect(func(k): results.append(k))
	for id in [1, 2]:
		net._server_add_player(id, "P%d" % id)
	var a: Net.ServerPlayer = net.players[1]
	var b: Net.ServerPlayer = net.players[2]

	# ---- the Duel Stone's pool
	var p1 := Net.duel_pool(1, 1)
	check(p1.size() == 4 and Weapons.BOW in p1 and Weapons.SLING in p1 and Weapons.SWORD in p1 and Weapons.CLUB in p1 and not Weapons.FISTS in p1,
		"before a level-up the stone summons only archers, slingers, swordsmen and clubbers")
	var p2 := Net.duel_pool(2, 1)
	check(Weapons.STAFF in p2 and Weapons.WAND in p2 and p2.size() == 6, "after the first level-up, wizards too (staff and wand)")
	# ---- pressing it: one challenger at a time
	a.state.pos = Vector3(WorldLayout.DUEL_C.x, 0, WorldLayout.DUEL_C.y + 1.2)
	var before := net.players.size()
	check(net._stone_interact(a), "E at the stone answers")
	check(net.players.size() == before + 1, "a challenger steps out")
	var npc: Net.ServerPlayer = null
	for q in net.players.values():
		if q.npc:
			npc = q
	check(npc != null and npc.state.weapon in p1, "with a weapon from the pool (%s)" % Weapons.NAMES[npc.state.weapon if npc else 0])
	net._stone_interact(a)
	check(net.players.size() == before + 1, "pressing it again while it lives does nothing")
	check(net.can_hurt(1, npc.id) and net.can_hurt(npc.id, 1) and not a.pvp, "challengers and players can hurt each other whatever PvP says")
	# ---- a kill on a challenger with the staff counts toward the staff's level
	var k0: int = a.kills[0]
	net.dmg_src = Weapons.STAFF
	net._damage(npc.id, 500, 1, Vector3(1, 0, 0), 0.0)
	net.dmg_src = -1
	check(a.kills[0] == k0 + 1, "killing a challenger with the staff counts toward its level (%d -> %d)" % [k0, a.kills[0]])
	for t in 200:
		net._server_npcs()
		npc.state.dead = maxi(npc.state.dead - 1, 0)
	check(not net.players.has(npc.id), "a fallen challenger is gone soon after")

	# ---- challengers fight: a swordsman comes for you and lands hits
	a.state = Sim.spawn_state(1)
	a.state.pos = Vector3(60, 0, 60)
	var sw := net.spawn_npc(a, Weapons.SWORD, 2)
	sw.state.pos = Vector3(60, 0, 70)
	var hp0 := a.state.hp
	for t in 900:
		net._server_tick()
		a.state.hp = maxi(a.state.hp, 30)   # keep them standing
		a.state.dead = 0
	var closest := Vector2(sw.state.pos.x - a.state.pos.x, sw.state.pos.z - a.state.pos.z).length()
	check(closest < 4.0, "the swordsman closes in (%.1f m away)" % closest)
	check(net.hits_on(1) > 0 if net.has_method("hits_on") else a.state.hp < hp0 or sw.ai.seq > 0, "and fights")
	net.players.erase(sw.id)
	# an archer at range leads its shots and lands some on someone walking across its view
	a.state = Sim.spawn_state(1)
	a.state.pos = Vector3(60, 0, 60)
	var ar := net.spawn_npc(a, Weapons.BOW, 2)
	ar.state.pos = Vector3(60, 0, 74)
	var hits := 0
	var last_hp := a.state.hp
	for t in 1500:
		a.state.pos.x = 60 + 6.0 * sin(t * 0.01)   # walking back and forth across its view
		a.state.vel = Vector3(6.0 * 0.6 * cos(t * 0.01), 0, 0)
		net._server_tick()
		if a.state.hp < last_hp:
			hits += 1
		a.state.hp = Sim.MAX_HP
		last_hp = a.state.hp
		a.state.dead = 0
	check(hits >= 2, "an archer leads its shots and hits someone on the move (%d hits in 25 s)" % hits)
	net.players.erase(ar.id)
	net._server_send_roster()

	# ---- Thunderhorn: health for one and for two players
	var b1 := Boss.new(Vector3.ZERO, 1)
	var b2 := Boss.new(Vector3.ZERO, 2)
	check(b2.max_hp == int(Boss.BASE_HP * 1.7) and b1.max_hp == Boss.BASE_HP, "two players: 1.7x his health (%d vs %d)" % [b2.max_hp, b1.max_hp])
	# what each spell does to him
	var t1 := Boss.new(Vector3.ZERO, 1)
	t1.state = Boss.S.IDLE
	var h := t1.hp
	t1.hurt(28, 1, "Lightning")
	check(h - t1.hp == 7, "lightning does only a quarter (28 -> %d): he's made of it" % (h - t1.hp))
	h = t1.hp
	t1.hurt(40, 1, "Meteor")
	check(h - t1.hp == 60, "a meteor does half again (40 -> %d)" % (h - t1.hp))
	t1.hurt(10, 1, "Fireball")
	check(t1.burn > 0, "a fireball sets him burning")
	t1.state = Boss.S.CHARGE
	h = t1.hp
	t1.hurt(16, 1, "Earth Spikes")
	check(t1.state == Boss.S.STAGGER and h - t1.hp == 24, "earth spikes do half again and stop his charge dead")
	t1.state = Boss.S.IDLE
	t1.frosted()
	check(t1.slow > 0 and t1.speed_k() < 0.5, "a frost nova slows him a lot")
	var t2 := Boss.new(Vector3.ZERO, 1)
	t2.state = Boss.S.IDLE
	t2.stunned(1000)
	var first := 45 - t2.t
	t2.state = Boss.S.IDLE
	t2.stunned(1010)
	var second := 45 - t2.t
	check(t2.state == Boss.S.STAGGER and first == 45 and second < first, "a stun only staggers him, shorter each time (%d, then %d ticks)" % [first, second])
	# a gravity well can't pull him
	net.summon_boss()
	net.boss.state = Boss.S.IDLE
	var bp := net.boss.pos
	net.wells.append([net.server_tick + 100, bp + Vector3(3, 0, 0), 1])
	for t in 30:
		net._server_wells()
	check(net.boss.pos.distance_to(bp) < 0.01, "a gravity well doesn't move him")
	net.wells.clear()

	# ---- victory: his death plays out, then the prize
	results.clear()
	net.boss.state = Boss.S.IDLE
	net._damage(Boss.ID, 100000, 1, Vector3(1, 0, 0), 0.0)
	for t in 200:
		net._server_tick()
	check(net.boss == null and "victory" in results, "beating him ends in victory (the prize screen)")

	# ---- defeat and restart: alone
	for id in net.players.keys().duplicate():
		if id != 1:
			net.players.erase(id)
	results.clear()
	a.state = Sim.spawn_state(1)
	a.state.staff_lvl = 3
	net.summon_boss()
	a.state.dead = Sim.RESPAWN_TICKS
	net._server_tick()
	check(net.defeated and "defeat" in results and net.boss == null, "alone: you die, he's gone, the defeat screen")
	net.ask_restart()
	check(not net.defeated and a.state.dead == 0 and a.state.hp == Sim.MAX_HP and a.state.staff_lvl == 3 and "restart" in results,
		"a key: back on your feet at the spawn with full health, levels kept")
	# ---- two players: only when both are down at once
	net._server_add_player(2, "P2")
	b = net.players[2]
	results.clear()
	net.summon_boss()
	a.state.dead = Sim.RESPAWN_TICKS
	net._server_tick()
	check(not net.defeated and net.boss != null, "two players: one down isn't the end")
	b.state.dead = Sim.RESPAWN_TICKS
	a.state.dead = Sim.RESPAWN_TICKS
	net._server_tick()
	check(net.defeated and "defeat" in results, "both down at once: defeat")
	net.ask_restart()
	check(not net.defeated and a.state.dead == 0 and b.state.dead == 0 and net.boss == null, "and both start again")
	print("%d failed" % bad)
	quit(bad)
