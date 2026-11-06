extends SceneTree
## v0.12.7 spell mastery, run offline on the server's side: every spell levels I -> II -> III from what it achieves
## (Weapons "mastery" / "by"), never on practice dummies; each level's numbers (Weapons.spell_lv); the teleport's reach
## predicted in Sim; the arrival burst; Shield III turning an arrow back into its shooter; Stun III charming an NPC to
## the caster's side and back; fog poison on enemies only; 1 / 3 / 5 meteors; bigger golems; the level kept across a
## respawn and a restart; the codec; the dev console's `mastery`.
##   Godot --headless --path . --script tools/mastery_test.gd   (prints harmless "not inside tree" RPC errors)

var bad := 0


func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		bad += 1


func slot(spell_name: String) -> int:
	var w := Net.spell_weapon(spell_name)
	return Weapons.mastery_slot(w, Weapons.idx(w, spell_name))


func xp(p: Net.ServerPlayer, spell_name: String) -> float:
	return float(p.mxp[slot(spell_name)])


func lv(p: Net.ServerPlayer, spell_name: String) -> int:
	return Weapons.mastery_of(p.state.mastery, slot(spell_name))


func setlv(net: Net, p: Net.ServerPlayer, spell_name: String, l: int) -> void:
	net.set_mastery(p, slot(spell_name), l)


## Cast the spell with this name the way the server does (Net._cast), from where p stands, at `aim`.
func cast(net: Net, p: Net.ServerPlayer, spell_name: String, aim: Vector3) -> void:
	var w := Net.spell_weapon(spell_name)
	p.state.weapon = w
	p.state.spell = Weapons.idx(w, spell_name)
	var to := aim - p.state.pos
	p.state.yaw = atan2(-to.x, -to.z)
	net._cast(p, Sim.PlayerInput.new(1, 0, p.state.yaw, 0.0, w, 0, p.state.yaw, INF, p.state.spell, aim), p.state.pos)


func fresh_npc(net: Net, a: Net.ServerPlayer, at: Vector3) -> Net.ServerPlayer:
	var q := net.spawn_npc(a, Weapons.SWORD, 0)
	q.state.pos = at
	q.state.hp = Sim.MAX_HP
	return q


func _initialize() -> void:
	var net := Net.new()
	root.add_child(net)
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	for id in [1, 2]:
		net._server_add_player(id, "P%d" % id)
	var a: Net.ServerPlayer = net.players[1]
	var b: Net.ServerPlayer = net.players[2]
	net.server_tick = 1000

	# ---- the data: 15 spells, 2 bits each, thresholds and each level's numbers
	check(Weapons.MASTERY_SLOTS == (Weapons.get_data(Weapons.STAFF).spells as Array).size() + (Weapons.get_data(Weapons.WAND).spells as Array).size(),
		"15 mastery slots: the staff's 7 spells and the wand's 8")
	var all_have := true
	for s in Weapons.MASTERY_SLOTS:
		var ws := Weapons.slot_spell(s)
		var sp := Weapons.spell(ws[0], ws[1])
		all_have = all_have and sp.has("mastery") and sp.has("by") and sp.has("m2") and sp.has("m3") and int(sp.mastery[0]) < int(sp.mastery[1])
	check(all_have, "every spell has its thresholds, its metric and its II / III numbers")
	var m := Weapons.with_mastery(Weapons.with_mastery(0, 1, 3), 14, 2)
	check(Weapons.mastery_of(m, 1) == 3 and Weapons.mastery_of(m, 14) == 2 and Weapons.mastery_of(m, 0) == 1 and Weapons.mastery_all(3) < 1 << 30,
		"levels pack 2 bits a spell (fireball III, stone titan II, the rest I) in under 30 bits")
	var need := Weapons.mastery_need(slot("Fireball"))
	check(Weapons.mastery_for(slot("Fireball"), need[0] - 1) == 1 and Weapons.mastery_for(slot("Fireball"), need[0]) == 2
		and Weapons.mastery_for(slot("Fireball"), need[1]) == 3, "points reach II and III exactly at the thresholds (%s)" % str(need))
	var nums := []
	for l in [1, 2, 3]:
		var fb := Weapons.spell_named_lv(Weapons.STAFF, "Fireball", l)
		var li := Weapons.spell_named_lv(Weapons.STAFF, "Lightning", l)
		nums.append([float(fb.radius), int(fb.max_damage), float(li.chain_range), int(li.chain_max), int(li.max_damage)])
	check(nums == [[3.4, 24, 6.0, 5, 28], [4.25, 29, 8.0, 7, 35], [5.1, 34, 10.0, 9, 42]],
		"fireball radius x1.25 / x1.5 and +20% / +40%; lightning +25% / +50%, chains 8 / 10 m, 7 / 9 jumps")
	var st3 := Weapons.spell_named_lv(Weapons.WAND, "Stun", 3)
	check(int(Weapons.spell_named_lv(Weapons.WAND, "Stun", 2).duration) == 240 and int(st3.duration) == 300 and int(st3.charm) > 0
		and float(st3.radius) == 3.0, "stun 3 / 4 / 5 s, wider at II, charms at III")
	check(Weapons.spell_named_lv(Weapons.STAFF, "Shield", 1).cost == 10 and Weapons.spell_named_lv(Weapons.STAFF, "Shield", 2).cost == 5
		and bool(Weapons.spell_named_lv(Weapons.STAFF, "Shield", 3).get("reflect", false)), "shield: half the cost at II, reflects at III")
	check(Weapons.spell_named_lv(Weapons.WAND, "Fog", 1).get("poison", 0) == 0 and Weapons.spell_named_lv(Weapons.WAND, "Fog", 2).poison == 2
		and Weapons.spell_named_lv(Weapons.WAND, "Fog", 3).poison == 4 and float(Weapons.spell_named_lv(Weapons.WAND, "Fog", 3).half) == 15.0,
		"fog: no poison, 2 a second, 4 a second and 30 x 30 m")
	check(Weapons.spell_lv(Weapons.STAFF, 1, 1) == Weapons.spell(Weapons.STAFF, 1), "mastery I is the spell itself")

	# ---- points come from what a spell achieves; never from dummies; NPCs earn none
	var C := Vector3(80, 0, 80)
	var q := fresh_npc(net, a, C)
	var fsp := Weapons.spell_named(Weapons.STAFF, "Fireball")
	var x0 := xp(a, "Fireball")
	net._blast(C + Vector3(0, 0.9, 0), fsp, a.id, Weapons.STAFF)
	var took := Sim.MAX_HP - q.state.hp
	check(took > 0 and is_equal_approx(xp(a, "Fireball") - x0, float(took)), "a fireball dealing %d to a challenger earns %d Fireball points (%.0f)" % [took, took, xp(a, "Fireball") - x0])
	x0 = xp(a, "Fireball")
	q.state.pos = Vector3(150, 0, 150)
	net._blast(WorldLayout.DUMMIES[1] + Vector3(0, 0.9, 0), fsp, a.id, Weapons.STAFF)
	check(xp(a, "Fireball") == x0, "blasting a practice dummy earns nothing")
	var qx := xp(q, "Fireball")
	q.state.pos = C
	a.state.pos = C + Vector3(1, 0, 0)
	a.pvp = true
	net._blast(C + Vector3(1, 0.9, 0), fsp, q.id, Weapons.STAFF)
	check(xp(q, "Fireball") == qx and Weapons.mastery_of(q.state.mastery, slot("Fireball")) == 1, "a challenger earns no mastery (NPCs stay at I)")
	a.pvp = false
	a.state.hp = Sim.MAX_HP
	# levelling up at the thresholds
	a.mxp[slot("Fireball")] = 0.0
	net.mastery_add(a.id, "Fireball", float(need[0]) - 1.0)
	check(lv(a, "Fireball") == 1, "one point short of II: still I")
	net.mastery_add(a.id, "Fireball", 1.0)
	check(lv(a, "Fireball") == 2, "at %d points: Fireball II" % need[0])
	net.mastery_add(a.id, "Fireball", float(need[1] - need[0]))
	check(lv(a, "Fireball") == 3 and lv(a, "Lightning") == 1, "at %d: Fireball III (the others untouched)" % need[1])
	# lightning chain jumps count double
	setlv(net, a, "Lightning", 1)
	var q2 := fresh_npc(net, a, C + Vector3(3.5, 0, 0))
	q.state.pos = C
	q.state.hp = Sim.MAX_HP
	x0 = xp(a, "Lightning")
	net._chain_jump([net.server_tick, "chain", C, a.id, q.id, 28, { q.id: true }, 0], a.id)
	var jumped := Sim.MAX_HP - q2.state.hp
	check(jumped == 14 and xp(a, "Lightning") - x0 == 28.0, "a chain jump of %d earns double (%.0f)" % [jumped, xp(a, "Lightning") - x0])
	net.pending_spells.clear()
	# Lightning III forks to the nearest enemy outside the strike
	setlv(net, a, "Lightning", 3)
	a.state.pos = C + Vector3(0, 0, 20)
	q.state.hp = Sim.MAX_HP
	q2.state.hp = Sim.MAX_HP
	q2.state.pos = C + Vector3(6, 0, 0)
	net.pending_spells = [[net.server_tick, "lightning", C, a.id, 3]]
	net._server_spells()
	check(Sim.MAX_HP - q.state.hp == 42 and Sim.MAX_HP - q2.state.hp == int(round(42 * 0.7)),
		"Lightning III: 42 in the strike, and it forks 6 m to another for %d" % (Sim.MAX_HP - q2.state.hp))
	net.pending_spells.clear()
	# Frost Nova III freezes those close in; Gravity Well III bursts twice
	setlv(net, a, "Frost Nova", 3)
	a.state.pos = C + Vector3(0, 0, 2.5)
	q.state.stun = 0
	q2.state.stun = 0
	cast(net, a, "Frost Nova", C)
	check(q.state.stun == 60 and q2.state.stun == 0 and q2.state.slow == 180, "Frost Nova III: frozen solid close in (1 s), slowed 3 s further out")
	setlv(net, a, "Gravity Well", 3)
	net.wells.clear()
	cast(net, a, "Gravity Well", C)
	q.state.hp = Sim.MAX_HP
	var hits := []
	for k in 200:
		net.server_tick += 1
		var hp0 := q.state.hp
		net._server_wells()
		if hp0 - q.state.hp >= 8:
			hits.append(k)
	check(hits.size() == 2 and net.wells.is_empty(), "Gravity Well III bursts twice (at ticks %s)" % str(hits))
	q.state.stun = 0
	q.state.slow = 0
	net.players.erase(q2.id)

	# ---- teleport: the reach is predicted in Sim (18 / 25 / 32 m) and every metre counts
	var T := Vector3(120, 0, 120)
	for l in [1, 2, 3]:
		var s := Sim.spawn_state(1)
		s.pos = T
		s.owned = 0b1111111
		s.weapon = Weapons.WAND
		s.spell = Weapons.idx(Weapons.WAND, "Teleport")
		s.mastery = Weapons.with_mastery(0, slot("Teleport"), l)
		var aim := T + Vector3(-60, 0, 0)
		var before := s.pos
		var moved := 0.0
		for k in 30:
			var b4 := s.pos
			var ev := Sim.step(s, Sim.PlayerInput.new(k + 1, Sim.Btn.ATTACK, PI / 2.0, 0.0, Weapons.WAND, 0, PI / 2.0, PI / 2.0, s.spell, aim))
			if ev == Sim.Ev.CAST:
				moved = Vector2(s.pos.x - b4.x, s.pos.z - b4.z).length()
				break
		var want: float = [18.0, 25.0, 32.0][l - 1]
		check(absf(moved - want) < 0.3, "Teleport %s blinks %.1f m (Sim, predicted: %.0f)" % [Weapons.MASTERY_ROMAN[l - 1], moved, want])
		var copy := s.copy()
		check(copy.mastery == s.mastery, "  PlayerState.copy keeps the mastery")
	# the server: metres travelled, and the arrival burst (near takes it, far doesn't)
	setlv(net, a, "Teleport", 2)
	a.state.pos = T
	var near := fresh_npc(net, a, T + Vector3(-25, 0, 1.5))
	var far := fresh_npc(net, a, T + Vector3(-25, 0, 6.0))
	x0 = xp(a, "Teleport")
	a.state.weapon = Weapons.WAND
	a.state.spell = Weapons.idx(Weapons.WAND, "Teleport")
	var tin := Sim.PlayerInput.new(1, 0, PI / 2.0, 0.0, Weapons.WAND, 0, PI / 2.0, PI / 2.0, a.state.spell, T + Vector3(-60, 0, 0))
	var b4 := a.state.pos
	Sim._cast_self(a.state, tin)
	net._cast(a, tin, b4)
	var gain := xp(a, "Teleport") - x0
	check(absf(b4.distance_to(a.state.pos) - 25.0) < 0.3 and gain >= 25.0 - 0.3, "teleporting 25 m earns %.1f Teleport points (+ the burst)" % gain)
	check(near.state.hp == Sim.MAX_HP - 8 and far.state.hp == Sim.MAX_HP, "II's arrival burst: 8 to one 1.5 m away (%d), nothing at 6 m (%d)" % [Sim.MAX_HP - near.state.hp, Sim.MAX_HP - far.state.hp])
	check(near.state.vel.length() > 3.0, "and throws them back (%.1f m/s)" % near.state.vel.length())
	setlv(net, a, "Teleport", 3)
	near.state.hp = Sim.MAX_HP
	near.state.pos = a.state.pos + Vector3(-32, 0, 3.0)
	b4 = a.state.pos
	tin = Sim.PlayerInput.new(2, 0, PI / 2.0, 0.0, Weapons.WAND, 0, PI / 2.0, PI / 2.0, a.state.spell, a.state.pos + Vector3(-60, 0, 0))
	Sim._cast_self(a.state, tin)
	net._cast(a, tin, b4)
	check(near.state.hp == Sim.MAX_HP - 16, "III's shockwave: 16 to one 3 m away (%d)" % (Sim.MAX_HP - near.state.hp))
	net.players.erase(near.id)
	net.players.erase(far.id)

	# ---- Shield: II raises for half, III drains half and turns an arrow back into its shooter (PvP on)
	var s2 := Sim.spawn_state(1)
	s2.owned = 0b1111111
	s2.weapon = Weapons.STAFF
	s2.spell = Weapons.idx(Weapons.STAFF, "Shield")
	s2.mastery = Weapons.with_mastery(0, slot("Shield"), 2)
	var mana0 := s2.mana
	Sim.step(s2, Sim.PlayerInput.new(1, Sim.Btn.ATTACK, 0.0, 0.0, Weapons.STAFF, 0, 0.0, 0.0, s2.spell, Vector3.ZERO))
	check(s2.shield > 0 and mana0 - s2.mana == 25, "Shield II: raising it costs 5 mana (%d)" % ((mana0 - s2.mana) / 5))
	a.pvp = true
	b.pvp = true
	setlv(net, a, "Shield", 3)
	a.state.pos = Vector3(60, 0, 60)
	a.state.shield = 2
	a.state.mana = 500
	a.state.dead = 0
	a.state.hp = Sim.MAX_HP
	net._damage(1, 8, 2, Vector3(1, 0, 0), 0.0)
	check(a.state.mana == 500 - 30 and a.state.hp == Sim.MAX_HP, "Shield III: a slash of 8 costs 6 mana, not 12 (%d)" % ((500 - a.state.mana) / 5))
	x0 = xp(a, "Shield")
	b.state.pos = Vector3(60, 0, 72)
	b.state.hp = Sim.MAX_HP
	b.state.dead = 0
	var pr := Net.Proj.new()
	pr.id = 700
	pr.owner = 2
	pr.kind = 0
	pr.tick0 = net.server_tick
	pr.pos0 = Vector3(60, 1.3, 70.5)
	pr.vel0 = Vector3(0, 0, -40)
	pr.g = 9.8
	pr.damage = 9
	pr.weapon = Weapons.BOW
	pr.last = pr.pos0
	net.projectiles[pr.id] = pr
	var reflected := false
	for t in 90:
		net.server_tick += 1
		a.state.shield = 2
		net._server_projectiles()
		if pr.owner == 1:
			reflected = true
		if not net.projectiles.has(pr.id):
			break
	check(reflected and a.state.hp == Sim.MAX_HP, "the arrow is turned back (now the holder's), the holder unhurt")
	check(b.state.hp == Sim.MAX_HP - 9, "and it flies back into its shooter: 9 damage (%d)" % (Sim.MAX_HP - b.state.hp))
	check(xp(a, "Shield") > x0, "turning it away earns Shield points (+%.0f)" % (xp(a, "Shield") - x0))
	a.state.shield = 0
	b.state.hp = Sim.MAX_HP

	# ---- Stun: seconds held count; III charms an NPC to the caster's side, then it goes back; players aren't charmed
	var S := Vector3(-80, 0, 80)
	a.state.pos = S
	a.state.hp = Sim.MAX_HP
	var foe := fresh_npc(net, a, S + Vector3(0, 0, -6))
	setlv(net, a, "Stun", 2)
	x0 = xp(a, "Stun")
	cast(net, a, "Stun", foe.state.pos + Vector3(0, 1.0, 0))
	check(foe.state.stun == 240 and absf(xp(a, "Stun") - x0 - 4.0) < 0.01, "Stun II holds 4 s and earns 4 points (%d ticks, +%.1f)" % [foe.state.stun, xp(a, "Stun") - x0])
	check(foe.charm_until == 0, "II doesn't charm")
	x0 = xp(a, "Stun")
	net._damage(foe.id, 12, a.id, Vector3(0, 0, -1), 0.0)
	check(absf(xp(a, "Stun") - x0 - 3.0) < 0.01, "hitting it while it's held: a quarter of the damage counts too (+%.1f)" % (xp(a, "Stun") - x0))
	foe.state.stun = 0
	foe.state.hp = Sim.MAX_HP
	setlv(net, a, "Stun", 3)
	check(net.can_hurt(a.id, foe.id) and Net.side_of(foe) == Net.Side.HOSTILE, "before: a hostile challenger")
	cast(net, a, "Stun", foe.state.pos + Vector3(0, 1.0, 0))
	check(foe.state.stun == 300, "Stun III holds 5 s")
	check(foe.charm_until == net.server_tick + 300 + 360 and Net.side_of(foe) == Net.Side.ALLY and foe.ai.owner == a.id,
		"and charms it: on the caster's side for 6 s after (following them)")
	check(not net.can_hurt(a.id, foe.id) and not net.can_hurt(foe.id, a.id) and not net.npc_foe(foe, a) and not net.npc_foe(foe, b),
		"it can't hurt the caster or their allies, nor they it")
	var other := fresh_npc(net, a, S + Vector3(5, 0, -6))
	check(net.npc_foe(foe, other) and net.can_hurt(foe.id, other.id), "it fights the caster's enemies (another challenger)")
	check(foe.name.ends_with("(charmed)"), "its name says so (%s)" % foe.name)
	net._server_send_roster()
	net.server_tick = foe.charm_until - 1
	net._server_mastery()
	check(Net.side_of(foe) == Net.Side.ALLY, "still charmed a tick before the end")
	net.server_tick += 1
	net._server_mastery()
	check(Net.side_of(foe) == Net.Side.HOSTILE and net.can_hurt(a.id, foe.id) and foe.ai.owner == a.id and foe.charm_until == 0
		and not foe.name.ends_with("(charmed)"), "then back on its own side, its name back")
	# a player in PvP: just the longer stun
	b.state.pos = S + Vector3(-5, 0, -6)
	b.state.stun = 0
	cast(net, a, "Stun", b.state.pos + Vector3(0, 1.0, 0))
	check(b.state.stun == 300 and b.charm_until == 0 and Net.side_of(b) == Net.Side.ALLY, "a player hit by Stun III: 5 s held, never charmed")
	b.state.stun = 0
	net.players.erase(other.id)
	net.players.erase(foe.id)

	# ---- Fog: poison on enemies only (II: 2 a second), blind-time and damage inside count
	var F := Vector3(-120, 0, -120)
	a.pvp = false
	b.pvp = false
	a.state.pos = F
	b.state.pos = F + Vector3(3, 0, 0)
	b.state.hp = Sim.MAX_HP
	var enemy := fresh_npc(net, a, F + Vector3(-4, 0, 2))
	setlv(net, a, "Fog", 2)
	net.fogs.clear()
	net.server_tick = 6000
	cast(net, a, "Fog", F)
	check(net.fogs.size() == 1 and int(net.fogs[0].get("lv", 1)) == 2 and Fog.from_args(Fog.to_args(net.fogs[0])).lv == 2, "a mastery-II fog (its level goes out with it)")
	x0 = xp(a, "Fog")
	for k in 120:   # 2 s
		net.server_tick += 1
		net._server_mastery()
	check(enemy.state.hp == Sim.MAX_HP - 4, "2 s inside: the challenger takes 4 poison (%d)" % (Sim.MAX_HP - enemy.state.hp))
	check(b.state.hp == Sim.MAX_HP and a.state.hp == Sim.MAX_HP, "the caster and an ally inside take none")
	check(xp(a, "Fog") - x0 >= 2.0 + 4.0 - 0.01, "an enemy blind 2 s (2) + 4 poison damage: +%.1f Fog points" % (xp(a, "Fog") - x0))
	x0 = xp(a, "Fog")
	var x1 := xp(a, "Fireball")
	net._damage(enemy.id, 8, b.id, Vector3(1, 0, 0), 0.0)   # the ally (PvP off) punches it inside the fog
	check(absf(xp(a, "Fog") - x0 - 2.0) < 0.01 and xp(a, "Fireball") == x1, "an ally's hit of 8 on it inside the fog: +2 Fog for the caster")
	enemy.state.pos = F + Vector3(40, 0, 0)
	x0 = xp(a, "Fog")
	net._damage(enemy.id, 8, b.id, Vector3(1, 0, 0), 0.0)
	check(xp(a, "Fog") == x0, "outside the fog it doesn't")
	setlv(net, a, "Fog", 3)
	net.fogs.clear()
	cast(net, a, "Fog", F)
	enemy.state.pos = F + Vector3(13.5, 0, 0)   # inside the 30 x 30 m
	enemy.state.hp = Sim.MAX_HP
	for k in 60:
		net.server_tick += 1
		net._server_mastery()
	check(enemy.state.hp == Sim.MAX_HP - 4 and enemy.state.slow > 0, "Fog III: 30 x 30 m (13.5 m out is inside), 4 a second, slowed")
	net.fogs.clear()
	net.players.erase(enemy.id)

	# ---- Meteor: 1 / 3 / 5 rocks
	var M := Vector3(-60, 0, 120)
	a.state.pos = M
	for l in [1, 2, 3]:
		setlv(net, a, "Meteor", l)
		net.pending_spells.clear()
		cast(net, a, "Meteor", M + Vector3(0, 0, -15))
		var n := net.pending_spells.filter(func(e): return str(e[1]) == "meteor").size()
		check(n == [1, 3, 5][l - 1], "Meteor %s calls down %d (%d)" % [Weapons.MASTERY_ROMAN[l - 1], [1, 3, 5][l - 1], n])
	net.pending_spells.clear()

	# ---- Golem: bigger, tougher (II 1.3x, +40%; III 1.6x, +80%), titan too
	var G := Vector3(150, 0, -150)
	a.state.pos = G
	var sizes := []
	for l in [1, 2, 3]:
		setlv(net, a, "Golem", l)
		cast(net, a, "Golem", G + Vector3(0, 0, -4))
		var g: Golems.G = net.golems.list[net.golems.next_id - 1]
		sizes.append([g.size, g.max_hp, g.hp, net.golems._reach(g)])
	check(is_equal_approx(sizes[0][0], 1.0) and is_equal_approx(sizes[1][0], 1.3) and is_equal_approx(sizes[2][0], 1.6), "golems 1x, 1.3x, 1.6x (%s)" % str(sizes))
	check(sizes[0][1] == 40 and sizes[1][1] == 56 and sizes[2][1] == 72 and sizes[2][2] == 72, "with 40, 56, 72 health")
	check(sizes[2][3] > sizes[0][3] * 1.5, "and the reach to match")
	var row: Array = net.golems.pack()[0]
	check(row.size() >= 13, "their size and mastery go out with their state (%d fields)" % row.size())
	setlv(net, a, "Stone Titan", 3)
	cast(net, a, "Stone Titan", G + Vector3(4, 0, 0))
	var titan: Golems.G = net.golems.list[net.golems.next_id - 1]
	check(titan.titan and titan.max_hp == int(round(Golems.TITAN_HP * 1.7)) and titan.stomp > 0.0, "Stone Titan III: +70%% health (%d), the stomp" % titan.max_hp)
	# a golem's damage counts for its summoner's Golem mastery
	var gq := fresh_npc(net, a, G + Vector3(0, 0, -6))
	x0 = xp(a, "Golem")
	net.xp_spell = "Golem"
	net.dmg_src = Weapons.WAND
	net._damage(gq.id, 11, a.id, Vector3(1, 0, 0), 0.0)
	net.xp_spell = ""
	net.dmg_src = -1
	check(xp(a, "Golem") - x0 == 11.0, "a golem's punch of 11 earns 11 Golem points")
	for g: Golems.G in net.golems.list.values():
		g.state = Golems.State.DIE
	net.golems.list.clear()
	net.players.erase(gq.id)

	# ---- Heal Aura: health restored counts (not overheal); III cleanses
	a.state.pos = Vector3(-150, 0, -150)
	b.state.pos = a.state.pos + Vector3(2, 0, 0)
	setlv(net, a, "Heal Aura", 3)
	a.state.weapon = Weapons.STAFF
	a.state.spell = Weapons.idx(Weapons.STAFF, "Heal Aura")
	a.state.atk = 2
	a.state.hp = Sim.MAX_HP
	b.state.hp = Sim.MAX_HP - 3
	b.state.stun = 100
	b.state.slow = 100
	x0 = xp(a, "Heal Aura")
	net.server_tick += 7
	a.heal_last = -100
	net._server_heal_auras()
	check(b.state.hp == Sim.MAX_HP and absf(xp(a, "Heal Aura") - x0 - 3.0) < 0.01, "healing an ally 3 short earns 3 (overheal doesn't count)")
	check(b.state.stun == 0 and b.state.slow == 0 and b.regen_until > net.server_tick, "Heal Aura III: their stun and slow washed away, an afterglow")
	a.state.atk = 0

	# ---- Spark Beam III pierces 2 and arcs; Life Drain III jumps
	var P := Vector3(100, 0, -60)
	a.state.pos = P
	setlv(net, a, "Spark Beam", 3)
	var line := []
	for k in 3:
		line.append(fresh_npc(net, a, P + Vector3(0, 0, -5 - 3 * k)))
	var side := fresh_npc(net, a, P + Vector3(3, 0, -11))
	cast(net, a, "Spark Beam", P + Vector3(0, 1.4, -30))
	var dm := line.map(func(x): return Sim.MAX_HP - x.state.hp)
	check(dm == [11, 11, 11] and Sim.MAX_HP - side.state.hp == 7, "Spark Beam III: 11 to three in a line, an arc of 7 to one beside (%s, %d)" % [str(dm), Sim.MAX_HP - side.state.hp])
	for x in line:
		net.players.erase(x.id)
	net.players.erase(side.id)
	setlv(net, a, "Life Drain", 3)
	var d1 := fresh_npc(net, a, P + Vector3(0, 0, -6))
	var d2 := fresh_npc(net, a, P + Vector3(2, 0, -9))
	a.state.hp = 50
	x0 = xp(a, "Life Drain")
	cast(net, a, "Life Drain", P + Vector3(0, 1.4, -20))
	check(Sim.MAX_HP - d1.state.hp == 27 and Sim.MAX_HP - d2.state.hp == 16 and a.state.hp > 50,
		"Life Drain III: 27 to the first, jumps for 16 to a second, the caster drinks (%d hp)" % a.state.hp)
	check(xp(a, "Life Drain") - x0 == 43.0, "both count (+%.0f)" % (xp(a, "Life Drain") - x0))
	net.players.erase(d1.id)
	net.players.erase(d2.id)
	a.state.hp = Sim.MAX_HP

	# ---- the codec carries it; it's kept across a respawn and a restart; the dev console sets it
	var packed := Weapons.with_mastery(Weapons.mastery_all(3), slot("Fog"), 2)
	var s3 := Sim.spawn_state(2)
	s3.mastery = packed
	var back: Sim.PlayerState = Codec.decode_snapshot(Codec.encode_snapshot(9, 1, [[2, s3]])).ents[2]
	check(back.mastery == packed, "the snapshot carries the mastery (%d)" % back.mastery)
	a.state.mastery = packed
	a.state.dead = 1
	a.state.hp = 0
	a.was_dead = true
	a.primed = true
	a.queue.clear()
	a.queue[a.last_applied + 1] = Sim.PlayerInput.new(a.last_applied + 1, 0, 0.0, 0.0, a.state.weapon, 0)
	net._server_step_player(a)
	check(a.state.dead == 0 and a.state.hp == Sim.MAX_HP and a.state.mastery == packed, "back on their feet after a knock-out: mastery kept")
	net.defeated = true
	net.boss_fighters = [a.id]
	net.restart_after_defeat()
	check(a.state.mastery == packed, "and after a defeat's restart")
	a.state.mastery = 0
	print("      " + DevCmd.run(net, 1, "mastery fire 3"))
	check(lv(a, "Fireball") == 3 and lv(a, "Lightning") == 1 and xp(a, "Fireball") >= float(need[1]), "dev: mastery fire 3 (partial name)")
	print("      " + DevCmd.run(net, 1, "mastery WAND 2 p2"))
	check(lv(b, "Teleport") == 2 and lv(b, "Stone Titan") == 2 and lv(b, "Fireball") == 1, "dev: mastery wand 2 p2")
	DevCmd.run(net, 1, "mastery all 1 me")
	check(a.state.mastery == 0, "dev: mastery all 1")
	DevCmd.run(net, 1, "max")
	check(a.state.mastery == Weapons.mastery_all(3), "dev: max sets every mastery to III")
	check(DevCmd.run(net, 1, "help mastery").contains("damage dealt to enemies"), "help mastery explains what earns it")
	check(DevCmd.run(net, 1, "mastery nothing 2").begins_with("No spell"), "an unknown spell is refused")

	print("%d failed" % bad)
	if bad == 0:
		print("mastery: ALL OK")
	quit(1 if bad > 0 else 0)
