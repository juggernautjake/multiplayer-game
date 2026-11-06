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

	# v0.8.1: projectiles bounce off a shield and can't hurt its holder afterwards
	for kind in [0, 2]:   # an arrow, then a fireball
		b.state.pos = Vector3(60, 0, 60)
		b.state.shield = 2
		b.state.mana = 500
		b.state.atk_cd = 0
		var pr := Net.Proj.new()
		pr.id = 900 + kind
		pr.owner = 1
		pr.kind = kind
		pr.tick0 = net.server_tick
		pr.pos0 = Vector3(60, 1.2, 66)
		pr.vel0 = Vector3(0, 0, -40)
		pr.g = 0.0
		pr.damage = 9 if kind == 0 else 0
		pr.last = pr.pos0
		net.projectiles[pr.id] = pr
		var bounced := false
		var hp0 := b.state.hp
		for t in 40:
			net.server_tick += 1
			b.state.shield = 2   # held
			net._server_projectiles()
			if net.projectiles.has(pr.id) and pr.bounces > 0:
				bounced = true
		check(bounced and pr.vel0.z > 0.0, "%s bounces off the shield (flying back at %.1f m/s)" % ["an arrow" if kind == 0 else "a fireball", pr.vel0.z])
		check(b.state.hp == hp0 and b.state.mana < 500, "it doesn't hurt the holder, who pays mana for it (%d left)" % (b.state.mana / 5))
		check(pr.vel0.length() < 40.0 * Weapons.SHIELD_BOUNCE + 0.5, "and it loses some speed")
		net.projectiles.erase(pr.id)
	# a fireball that has already bounced bursts on the next shield, outside it
	var fb := Net.Proj.new()
	fb.id = 950
	fb.owner = 1
	fb.kind = 2
	fb.tick0 = net.server_tick
	fb.pos0 = Vector3(60, 1.2, 66)
	fb.vel0 = Vector3(0, 0, -40)
	fb.bounces = 1
	fb.last = fb.pos0
	net.projectiles[fb.id] = fb
	for t in 30:
		net.server_tick += 1
		b.state.shield = 2
		net._server_projectiles()
	check(not net.projectiles.has(fb.id) and b.state.hp == Sim.MAX_HP, "a fireball that already bounced bursts on the shield, outside it (the holder unhurt)")
	b.state.shield = 0
	b.state.pos = Vector3.ZERO

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

	# v0.8.2: chain lightning (nothing left over from the tests above: burning ground, storms, wells)
	net.pending_spells.clear()
	net.storms.clear()
	net.wells.clear()
	for id in [3, 4, 5, 6, 7]:
		net._server_add_player(id, "P%d" % id)
	var line := [net.players[3], net.players[4], net.players[5]]
	for i in 3:
		line[i].state.pos = Vector3(120 + 4.0 * i, 0, 120)
		line[i].pvp = true
	var far: Net.ServerPlayer = net.players[6]      # 8 m past the end of the line: out of the chain's reach
	far.state.pos = Vector3(136, 0, 120)
	far.pvp = true
	var nopvp: Net.ServerPlayer = net.players[7]    # PvP off: never chained
	nopvp.state.pos = Vector3(122, 0, 123)
	nopvp.pvp = false
	a.state.pos = Vector3(118, 0, 117)              # the caster, close by: never chained
	var mine := net.golems.spawn(1, Vector3(126, 0, 122), 0.0, net.server_tick - 100)   # the caster's own golem
	mine.state = Golems.State.IDLE
	mine.stun = 100000   # it stands still (it would otherwise go and fight them)
	b.state.pos = Vector3(300, 0, 300)
	for q in net.players.values():
		q.state.hp = Sim.MAX_HP
		q.state.shield = 0
		q.state.dead = 0
	var run_cast := func(at: Vector3):
		net.pending_spells.append([net.server_tick, "lightning", at, 1])
		for t in 60:
			net._server_spells()
			net.server_tick += 1
	run_cast.call(line[0].state.pos)
	var got := line.map(func(q): return Sim.MAX_HP - q.state.hp)
	check(got == [28, 14, 7], "lightning on the first of three in a line 4 m apart: 28, then it chains for 14 and 7 (%s)" % str(got))
	check(far.state.hp == Sim.MAX_HP, "one 8 m further on is out of the chain's reach")
	check(a.state.hp == Sim.MAX_HP and nopvp.state.hp == Sim.MAX_HP and mine.hp == Golems.HP, "never the caster, their own golem, or someone with PvP off")
	# a shield soaks the jump and ends that branch
	for q in net.players.values():
		q.state.hp = Sim.MAX_HP
	line[1].state.shield = 2
	line[1].state.mana = 500
	run_cast.call(line[0].state.pos)
	check(line[1].state.hp == Sim.MAX_HP and line[1].state.mana < 500 and line[2].state.hp == Sim.MAX_HP, "a shielded one soaks the jump (mana) and the chain stops there")
	line[1].state.shield = 0
	# two inside the strike both take the full damage (no falloff for lightning)
	for q in net.players.values():
		q.state.hp = Sim.MAX_HP
	line[1].state.pos = line[0].state.pos + Vector3(2.4, 0, 0)
	line[2].state.pos = Vector3(200, 0, 200)
	run_cast.call(line[0].state.pos)
	check(Sim.MAX_HP - line[0].state.hp == 28 and Sim.MAX_HP - line[1].state.hp == 28, "two inside the strike both take the full 28 (%d, %d)" % [Sim.MAX_HP - line[0].state.hp, Sim.MAX_HP - line[1].state.hp])
	# golems and the titan never count toward magic levels (only players do)
	var kills0: Array = a.kills.duplicate()
	var lv0 := [a.state.staff_lvl, a.state.wand_lvl]
	for src in [Weapons.STAFF, Weapons.WAND]:
		for titan in [false, true]:
			var g := net.golems.spawn(2, Vector3(80, 0, 80), 0.0, net.server_tick - 100, titan)
			g.state = Golems.State.IDLE
			net.dmg_src = src
			net._damage(-1000 - g.id, 500, 1, Vector3(1, 0, 0), 0.0)
			net.dmg_src = -1
			check(g.state == Golems.State.DIE, "%s kills another player's %s" % [Weapons.NAMES[src], "titan" if titan else "golem"])
	check(a.kills == kills0 and [a.state.staff_lvl, a.state.wand_lvl] == lv0, "killing golems and the titan doesn't count toward levels (kills still %s)" % str(a.kills))
	print("%d failed" % bad)
	quit(bad)
