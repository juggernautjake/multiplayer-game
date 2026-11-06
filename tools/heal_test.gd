extends SceneTree
## v0.12.0 the staff's level-3 Heal Aura, run offline on the server's side: held, it heals the caster and allies in
## reach (8 a second each), never enemies (challengers) or anyone out of reach, drains mana while it lasts, and stops
## when the button is let go, when the mana runs out, and when everyone in reach is full. NPC wizards never get it.
##   Godot --headless --path . --script tools/heal_test.gd   (prints harmless "not inside tree" RPC errors)

var bad := 0
var seq := 0


func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		bad += 1


func tick(net: Net, a: Net.ServerPlayer, hold: bool) -> void:
	seq += 1
	net.server_tick += 1
	var i := Weapons.idx(Weapons.STAFF, "Heal Aura")
	Sim.step(a.state, Sim.PlayerInput.new(seq, Sim.Btn.ATTACK if hold else 0, 0.0, 0.0, Weapons.STAFF, 0, 0.0, INF, i, a.state.pos))
	net._server_heal_auras()


func _initialize() -> void:
	var net := Net.new()
	root.add_child(net)
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	for id in [1, 2, 3]:
		net._server_add_player(id, "P%d" % id)
	var a: Net.ServerPlayer = net.players[1]
	var b: Net.ServerPlayer = net.players[2]
	var far: Net.ServerPlayer = net.players[3]
	var C := Vector3(70, 0, -70)
	var sp := Weapons.spell_named(Weapons.STAFF, "Heal Aura")
	var hi := Weapons.idx(Weapons.STAFF, "Heal Aura")
	check(int(sp.get("level", 1)) == 3 and Weapons.idx(Weapons.STAFF, "Meteor") >= 0 and int(Weapons.spell_named(Weapons.STAFF, "Meteor").level) == 3,
		"Heal Aura is a second level-3 staff spell, next to Meteor")
	check(not (hi in NpcAI.kit(Weapons.STAFF)), "challenger wizards never get it (level 1 only)")
	a.state.owned |= 1 << Weapons.STAFF
	a.state.weapon = Weapons.STAFF
	a.state.staff_lvl = 3
	a.state.pos = C
	a.state.hp = 50
	b.state.pos = C + Vector3(3, 0, 0)
	b.state.hp = 60
	far.state.pos = C + Vector3(12, 0, 0)
	far.state.hp = 50
	var foe := net.spawn_npc(a, Weapons.SWORD, 1)
	foe.state.pos = C + Vector3(0, 0, 4)
	foe.state.hp = 50
	var m0 := a.state.mana
	for t in 61:
		tick(net, a, true)
	check(Sim.channeling(a.state), "holding the button channels it")
	check(a.state.hp == 50 + 3 * int(sp.heal) and b.state.hp == 60 + 3 * int(sp.heal),
		"it heals the caster and an ally in reach (+%d, +%d in ~1 s)" % [a.state.hp - 50, b.state.hp - 60])
	check(foe.state.hp == 50 and far.state.hp == 50, "never an enemy challenger, nor anyone out of reach")
	check(m0 - a.state.mana == 61 * int(sp.drain), "it drains mana every tick (%d mana in ~1 s)" % ((m0 - a.state.mana) / 5))
	# stop 1: let go
	for t in 3:
		tick(net, a, false)
	var hb := b.state.hp
	for t in 60:
		tick(net, a, false)
	check(not Sim.channeling(a.state) and b.state.hp == hb, "letting go stops it")
	var m1 := a.state.mana
	check(m1 > m0 - 61 * int(sp.drain), "and the mana comes back after")
	# stop 2: everyone in reach full
	for t in 30:
		tick(net, a, true)
	a.state.hp = Sim.MAX_HP
	b.state.hp = Sim.MAX_HP
	tick(net, a, true)
	tick(net, a, true)
	check(not Sim.channeling(a.state), "everyone in reach full: it stops, even held")
	# stop 3: out of mana
	a.state.hp = 40
	a.state.mana = 40
	a.state.atk_cd = 0
	var stopped_at := -1
	var mana_then := -1
	for t in 120:
		tick(net, a, true)
		if stopped_at < 0 and t > 2 and not Sim.channeling(a.state):
			stopped_at = t
			mana_then = a.state.mana
	check(stopped_at >= 38 and stopped_at <= 44 and mana_then <= int(sp.drain), "out of mana: it stops (after %d ticks with 8 mana)" % stopped_at)
	print("%d failed" % bad)
	quit(1 if bad > 0 else 0)
