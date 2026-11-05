extends SceneTree
## The server's side of magic, run offline: a held shield soaks hits for mana (1.5 mana a point for weapons, 2 for
## spells, 25 for a stun), shatters when the mana runs out and lets the rest through; kills with the staff or wand
## level it up at 3, 8 and 18; players only hurt each other with PvP on.
##   Godot --headless --path . --script tools/net_magic_test.gd

var bad := 0

func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		bad += 1


func _initialize() -> void:
	var net := Net.new()
	root.add_child(net)
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	for id in [1, 2]:
		net._server_add_player(id, "P%d" % id)
	var a: Net.ServerPlayer = net.players[1]
	var b: Net.ServerPlayer = net.players[2]

	# PvP
	net._damage(2, 10, 1, Vector3(1, 0, 0), 0.0)
	check(b.state.hp == Sim.MAX_HP, "PvP off: no damage")
	a.pvp = true
	b.pvp = true
	net._damage(2, 10, 1, Vector3(1, 0, 0), 0.0)
	check(b.state.hp == Sim.MAX_HP - 10, "PvP on for both: 10 damage")
	b.state.hp = Sim.MAX_HP

	# shield soaks for mana
	b.state.shield = 2
	b.state.mana = 500
	net._damage(2, 8, 1, Vector3(1, 0, 0), 2.0)   # a sword slash
	check(b.state.hp == Sim.MAX_HP and b.state.mana == 500 - 60, "a slash of 8 on the shield: no damage, 12 mana (%d left)" % (b.state.mana / 5))
	net.dmg_src = Weapons.STAFF
	net._damage(2, 22, 1, Vector3(1, 0, 0), 2.0)   # a fireball's centre
	net.dmg_src = -1
	check(b.state.hp == Sim.MAX_HP and b.state.mana == 440 - 220, "a fireball of 22: 44 mana (%d left)" % (b.state.mana / 5))
	check(b.state.shield > 0, "the shield is still up")
	# not enough mana for the next big hit: it shatters, the rest goes through
	b.state.mana = 50   # 10 mana
	net.dmg_src = Weapons.STAFF
	net._damage(2, 28, 1, Vector3(1, 0, 0), 2.0)   # lightning: 56 mana, only 10 there
	net.dmg_src = -1
	check(b.state.shield == 0 and b.state.mana == 0, "out of mana: the shield shatters")
	check(b.state.hp == Sim.MAX_HP - 23, "the part the mana couldn't pay gets through (%d damage of 28)" % (Sim.MAX_HP - b.state.hp))
	check(b.state.atk_cd >= Weapons.SHIELD_BROKEN, "it can't be raised again for 2 s")
	b.state.hp = Sim.MAX_HP

	# kills level the weapons up
	for i in 3:
		b.state.hp = 5
		b.state.dead = 0
		net.dmg_src = Weapons.STAFF
		net._damage(2, 10, 1, Vector3(1, 0, 0), 0.0)
		net.dmg_src = -1
	check(a.kills[0] == 3 and a.state.staff_lvl == 2, "3 staff kills: staff level 2 (Frost Nova)")
	for i in 5:
		b.state.hp = 5
		b.state.dead = 0
		net.dmg_src = Weapons.WAND
		net._damage(2, 10, 1, Vector3(1, 0, 0), 0.0)
		net.dmg_src = -1
	check(a.kills[1] == 5 and a.state.wand_lvl == 2, "5 wand kills: wand level 2, not 3 yet (%d)" % a.state.wand_lvl)
	b.state.hp = 5
	b.state.dead = 0
	net._damage(2, 10, 1, Vector3(1, 0, 0), 0.0)   # a sword kill: doesn't count for magic
	check(a.kills == [3, 5], "a kill with a sword doesn't count toward magic levels")
	# the stun bursts in an area: someone 2 m from where it lands is caught
	a.state.pos = Vector3(60, 0, 60)
	b.state.pos = Vector3(60, 0, 48)
	b.state.dead = 0
	b.state.hp = Sim.MAX_HP
	b.state.shield = 0
	a.state.weapon = Weapons.WAND
	a.state.spell = 2
	a.state.yaw = 0.0
	net._cast(a, Sim.PlayerInput.new(1, 0, 0.0, 0.0, Weapons.WAND, 0, 0.0, INF, 2, Vector3(62, 0, 47.5)), a.state.pos)
	check(b.state.stun == int(Weapons.spell(Weapons.WAND, 2).duration), "a stun landing 2 m away catches them (held for 3 s)")
	b.state.stun = 0
	b.state.pos = Vector3(60, 0, 40)
	net._cast(a, Sim.PlayerInput.new(2, 0, 0.0, 0.0, Weapons.WAND, 0, 0.0, INF, 2, Vector3(64, 0, 47.5)), a.state.pos)
	check(b.state.stun == 0, "8 m away they're not caught")
	# your own blasts never hurt you
	a.state.hp = Sim.MAX_HP
	a.state.dead = 0
	a.state.shield = 0
	net._blast(a.state.pos + Vector3(0, 0.5, 0), Weapons.spell(Weapons.STAFF, 1), 1, Weapons.STAFF)
	net._damage(1, 20, 1, Vector3(1, 0, 0), 2.0)
	check(a.state.hp == Sim.MAX_HP, "a fireball at your own feet, and any damage you'd deal yourself: nothing")
	# the staff is one of a kind: taken, no new one appears; its holder leaves, it's back on the tower
	for i in WorldLayout.ITEM_SPAWNS.size():
		net._spawn_item_at(i)
	var staff_item: Net.Item = null
	for it: Net.Item in net.items.values():
		if it.kind == Weapons.Item.STAFF:
			staff_item = it
	a.state.owned |= 1 << Weapons.STAFF
	net._remove_item(staff_item, 1)
	var queued := net.respawns.filter(func(r): return int(WorldLayout.ITEM_SPAWNS[r[1]][0]) == Weapons.Item.STAFF)
	check(queued.is_empty(), "taking the staff: no second staff will appear")
	net._return_unique(a)
	var back := net.items.values().filter(func(it): return it.kind == Weapons.Item.STAFF)
	check(back.size() == 1 and absf(back[0].pos.y - WorldLayout.TOWER_TOP) < 0.01, "its holder leaves: it's back on top of the tower")
	# meteor: a big blast where it lands, then the ground burns
	a.state.pos = Vector3(60, 0, 60)
	a.state.weapon = Weapons.STAFF
	a.state.spell = 4
	b.state.pos = Vector3(60, 0, 50.5)
	b.state.hp = Sim.MAX_HP
	b.state.dead = 0
	b.state.shield = 0
	b.state.stun = 0
	net._cast(a, Sim.PlayerInput.new(3, 0, 0.0, 0.0, Weapons.STAFF, 0, 0.0, INF, 4, Vector3(60, 0, 50)), a.state.pos)
	var hp_after_hit := -1
	for t in 280:
		net.server_tick += 1
		net._server_spells()
		if hp_after_hit < 0 and b.state.hp < Sim.MAX_HP:
			hp_after_hit = b.state.hp
	check(hp_after_hit > 0 and Sim.MAX_HP - hp_after_hit >= 30, "a meteor landing 0.5 m off hits hard (%d)" % (Sim.MAX_HP - hp_after_hit))
	check(b.state.hp < hp_after_hit, "and standing in the flames keeps burning (%d more)" % (hp_after_hit - b.state.hp))
	# gravity well: someone 5 m away is dragged in
	b.state.hp = Sim.MAX_HP
	b.state.vel = Vector3.ZERO
	b.state.pos = Vector3(66, 0, 60)
	a.state.weapon = Weapons.WAND
	a.state.spell = 4
	net._cast(a, Sim.PlayerInput.new(4, 0, 0.0, 0.0, Weapons.WAND, 0, 0.0, INF, 4, Vector3(61, 0, 60)), a.state.pos)
	var d0 := Vector2(b.state.pos.x - 61, b.state.pos.z - 60).length()
	for t in 90:
		net.server_tick += 1
		net._server_spells()
		Sim.step(b.state, Sim.PlayerInput.new(10 + t, 0, 0.0))
	var d1 := Vector2(b.state.pos.x - 61, b.state.pos.z - 60).length()
	check(d1 < d0 - 2.0, "a gravity well drags someone 5 m off in (%.1f m -> %.1f m in 1.5 s)" % [d0, d1])
	for t in 120:
		net.server_tick += 1
		net._server_spells()
		Sim.step(b.state, Sim.PlayerInput.new(200 + t, 0, 0.0))
	check(b.state.hp < Sim.MAX_HP and net.wells.is_empty(), "it nibbles and then bursts (%d damage)" % (Sim.MAX_HP - b.state.hp))
	# arcane storm: bolts keep raining on someone under it
	b.state.hp = Sim.MAX_HP
	b.state.dead = 0
	b.state.pos = Vector3(60, 0, 50)
	b.state.vel = Vector3.ZERO
	a.state.pos = Vector3(60, 0, 62)
	a.state.weapon = Weapons.STAFF
	a.state.spell = 5
	net._cast(a, Sim.PlayerInput.new(5, 0, 0.0, 0.0, Weapons.STAFF, 0, 0.0, INF, 5, Vector3(60, 0, 50)), a.state.pos)
	var strikes := 0
	var last_hp := b.state.hp
	for t in 330:
		net.server_tick += 1
		net._server_spells()
		if b.state.hp < last_hp:
			strikes += 1
		last_hp = b.state.hp
		if b.state.dead > 0:
			b.state.dead = 0
			b.state.hp = Sim.MAX_HP
			last_hp = b.state.hp
		b.state.vel = Vector3.ZERO
	check(strikes >= 5 and net.storms.is_empty(), "the storm rains bolts on someone under it (%d hits in 5 s), then clears" % strikes)
	print("%d failed" % bad)
	quit(bad)
