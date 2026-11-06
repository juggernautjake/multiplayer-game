extends SceneTree
## v0.12.0 the wand's Fog, Spark Beam and Life Drain, run offline on the server's side: the cloud's size and life,
## who sees what (Fog.view_for / look_for: the caster and allies see enemies outlined and aren't blinded, enemies
## inside are blinded, outsiders see nothing inside), challengers lost in it (thrash or stumble, then recover),
## challengers outside walking round it, enemy golems confused, Thunderhorn not caring at all, Earth Spikes gone.
##   Godot --headless --path . --script tools/fog_test.gd   (prints harmless "not inside tree" RPC errors)

var bad := 0


func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		bad += 1


func _initialize() -> void:
	var net := Net.new()
	root.add_child(net)
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	for id in [1, 2, 3]:
		net._server_add_player(id, "P%d" % id)
	var a: Net.ServerPlayer = net.players[1]
	var b: Net.ServerPlayer = net.players[2]
	var c: Net.ServerPlayer = net.players[3]
	var C := Vector3(80, 0, 80)

	# ---- Earth Spikes are gone; the wand's new list
	check(Weapons.idx(Weapons.WAND, "Earth Spikes") < 0 and not CastPose.STYLE.has("Earth Spikes"), "Earth Spikes are gone")
	var names := []
	for sp in Weapons.get_data(Weapons.WAND).spells:
		names.append("%s(L%d)" % [sp.name, int(sp.get("level", 1))])
	print("      wand: ", ", ".join(names))

	# ---- casting it: 25 x 25 m round the caster, 10 s, thinning at the end
	a.state.pos = C
	a.state.weapon = Weapons.WAND
	a.state.spell = Weapons.idx(Weapons.WAND, "Fog")
	net.server_tick = 1000
	net._cast(a, Sim.PlayerInput.new(1, 0, 0.0, 0.0, Weapons.WAND, 0, 0.0, INF, a.state.spell, C), C)
	check(net.fogs.size() == 1, "the fog is cast")
	var f: Dictionary = net.fogs[0]
	check(int(f.dur) == 600 and int(f.fade) == 120, "it lasts 10 s, thinning over the last 2")
	var t := 1060.0
	var corners_in := Fog.covers(f, C + Vector3(12.3, 0, 12.3), t) and Fog.covers(f, C + Vector3(-12.3, 1, -12.3), t) \
		and Fog.covers(f, C + Vector3(12.3, 0, -12.3), t) and Fog.covers(f, C + Vector3(-12.3, 0, 12.3), t)
	check(corners_in and not Fog.covers(f, C + Vector3(14.0, 0, 0), t) and not Fog.covers(f, C + Vector3(0, 0, -14.0), t),
		"it covers 25 x 25 m round the caster (corners in, 14 m out)")
	check(Fog.covers(f, C, 1000.0 + 470) and Fog.density(f, 1000.0 + 470) == 1.0 and Fog.density(f, 1000.0 + 540) < 1.0
		and Fog.centre(f, 1000.0 + 590).distance_to(C) > 1.0, "thick for 8 s, then thinning and drifting off")
	for k in 600:
		net.server_tick += 1
		net._server_spells()
	check(net.fogs.is_empty(), "gone after 10 s")

	# ---- who sees what. 1 casts; 2 is an ally (PvP off); a challenger is an enemy.
	var npc := net.spawn_npc(a, Weapons.SWORD, 2)
	net.server_tick = 5000
	var fog := Fog.make(99, C, 1, 5000, { "duration": 3000 })
	net.fogs = [fog]
	var tick := 5060.0
	var pvp := net.fog_pvp()
	var in_a := C + Vector3(1, 0, 0)
	var in_b := C + Vector3(-3, 0, 2)
	var in_n := C + Vector3(6, 0, -4)
	check(Fog.look_for(1, in_a, npc.id, in_n, net.fogs, tick, pvp) == Fog.Look.OUTLINED, "the caster sees the enemy inside outlined")
	check(Fog.look_for(1, in_a, 1, in_a, net.fogs, tick, pvp, true) == Fog.Look.OUTLINED, "and themselves outlined")
	check(Fog.look_for(1, in_a, 2, in_b, net.fogs, tick, pvp) == Fog.Look.NORMAL, "an ally inside looks normal to the caster")
	var vb := Fog.view_for(2, in_b, net.fogs, tick, pvp)
	check(float(vb.impair) == 0.0 and 99 in vb.see_through, "an ally inside isn't blinded and sees through the fog")
	check(Fog.look_for(2, in_b, npc.id, in_n, net.fogs, tick, pvp) == Fog.Look.OUTLINED, "the ally sees the enemy outlined too")
	var va := Fog.view_for(1, in_a, net.fogs, tick, pvp)
	check(float(va.impair) == 0.0 and 99 in va.see_through, "the caster isn't blinded")
	var vn := Fog.view_for(npc.id, in_n, net.fogs, tick, pvp)
	check(float(vn.impair) > 0.9 and not (99 in vn.see_through), "an enemy inside is blinded (%.2f)" % float(vn.impair))
	check(Fog.look_for(npc.id, in_n, 1, in_a, net.fogs, tick, pvp) == Fog.Look.HIDDEN
		and Fog.look_for(npc.id, in_n, 1, in_n + Vector3(1.5, 0, 0), net.fogs, tick, pvp) == Fog.Look.NORMAL,
		"inside, the enemy sees nothing beyond ~2.5 m")
	check(float(Fog.view_for(npc.id, C + Vector3(20, 0, 0), net.fogs, tick, pvp).impair) == 0.0, "stepping out, the blindness lifts")
	# PvP on for 1 and 3: 3 is an enemy; outside, 3 sees nobody inside
	a.pvp = true
	c.pvp = true
	pvp = net.fog_pvp()
	var out_c := C + Vector3(0, 0, 20)
	check(Fog.look_for(3, out_c, 1, in_a, net.fogs, tick, pvp) == Fog.Look.HIDDEN and Fog.look_for(3, out_c, 2, in_b, net.fogs, tick, pvp) == Fog.Look.HIDDEN
		and not (99 in Fog.view_for(3, out_c, net.fogs, tick, pvp).see_through), "an enemy outside sees thick smoke hiding everyone inside")
	check(float(Fog.view_for(3, C, net.fogs, tick, pvp).impair) > 0.9, "a PvP enemy player inside is blinded")
	check(Fog.look_for(2, in_b, 3, C + Vector3(2, 0, 2), net.fogs, tick, pvp) == Fog.Look.OUTLINED, "the ally sees the caster's PvP enemy outlined")
	check(Fog.look_for(3, C + Vector3(2, 0, 2), 2, in_b, net.fogs, tick, pvp) == Fog.Look.HIDDEN, "and that enemy, inside, can't see the ally 4 m off")
	a.pvp = false
	c.pvp = false
	pvp = net.fog_pvp()

	# ---- overlapping clouds. Same side (1 and 2, PvP off): nothing changes; opposing sides (1 and the challenger):
	# everyone in the overlap is blind and there are no outlines there
	var f2 := Fog.make(98, C + Vector3(20, 0, 0), 2, 5000, { "duration": 3000 })   # 2's cloud: 7.5..32.5 m east
	net.fogs = [fog, f2]
	var ov := C + Vector3(10, 0, 0)
	var ov2 := C + Vector3(10, 0, 2)
	check(not Fog.overlap_at(ov, net.fogs, tick, pvp), "a same-side overlap (1 and 2) isn't an opposing one")
	check(float(Fog.view_for(1, ov, net.fogs, tick, pvp).impair) == 0.0 and float(Fog.view_for(2, ov, net.fogs, tick, pvp).impair) == 0.0
		and Fog.look_for(1, in_a, npc.id, ov, net.fogs, tick, pvp) == Fog.Look.OUTLINED, "same side: clear for them, the enemy in it outlined")
	check(float(Fog.view_for(npc.id, ov, net.fogs, tick, pvp).impair) > 0.9, "and the enemy in it blind as usual")
	var f3 := Fog.make(97, C + Vector3(20, 0, 0), npc.id, 5000, { "duration": 3000 })   # the challenger's cloud instead
	net.fogs = [fog, f3]
	check(Fog.overlap_at(ov, net.fogs, tick, pvp) and not Fog.overlap_at(in_a, net.fogs, tick, pvp), "an opposing overlap where 1's and the challenger's clouds meet")
	check(float(Fog.view_for(1, ov, net.fogs, tick, pvp).impair) > 0.9 and float(Fog.view_for(2, ov, net.fogs, tick, pvp).impair) > 0.9
		and float(Fog.view_for(npc.id, ov, net.fogs, tick, pvp).impair) > 0.9, "in it, both sides are blinded (1, ally 2 and the challenger)")
	check(float(Fog.view_for(1, in_a, net.fogs, tick, pvp).impair) == 0.0, "outside the overlap, in its own cloud, the caster sees as before")
	check(Fog.look_for(1, in_a, npc.id, ov, net.fogs, tick, pvp) == Fog.Look.HIDDEN, "an enemy standing in the overlap gets no outline: hidden")
	check(Fog.look_for(1, ov, 1, ov, net.fogs, tick, pvp, true) == Fog.Look.NORMAL, "nor does the caster in it (no outline on yourself)")
	check(Fog.look_for(1, ov, npc.id, in_n, net.fogs, tick, pvp) == Fog.Look.HIDDEN
		and Fog.look_for(1, ov, 2, ov2, net.fogs, tick, pvp) == Fog.Look.NORMAL, "from inside it: no outlines, only what's beside you")
	check(Fog.look_for(1, in_a, npc.id, in_n, net.fogs, tick, pvp) == Fog.Look.OUTLINED, "elsewhere the per-caster rules still apply")
	check(not Fog.can_see(npc.id, C + Vector3(0, 0, 30), 1, ov, net.fogs, tick, pvp) and Fog.lost(npc.id, ov, net.fogs, tick, pvp)
		and Fog.lost(1, ov, net.fogs, tick, pvp), "NPCs can't see into it, and anyone in it is lost (golems too)")
	net.fogs = [fog]

	# ---- a challenger inside loses its target and is confused; out again, it recovers after ~1 s
	npc.state.pos = in_n
	a.state.pos = in_a
	var modes := {}
	for k in 400:
		net.server_tick += 1
		npc.ai.think(net, npc)
		modes[npc.ai.fog_mode] = true
	check(npc.ai._pick_target(net, npc) == null, "inside, it can't target anyone")
	check(modes.size() >= 1 and (modes.has("thrash") or modes.has("stumble")) and not modes.has(""), "it thrashes or stumbles (%s)" % str(modes.keys()))
	var both := modes.has("thrash") and modes.has("stumble")
	for k in 2000:
		if both:
			break
		net.server_tick += 1
		npc.ai.think(net, npc)
		modes[npc.ai.fog_mode] = true
		both = modes.has("thrash") and modes.has("stumble")
	check(both, "picking again every ~2 s: both thrashing and stumbling seen")
	npc.state.pos = C + Vector3(30, 0, 0)
	for k in 30:
		net.server_tick += 1
		npc.ai.think(net, npc)
	check(npc.ai.fog_mode != "", "half a second out, still confused")
	for k in 40:
		net.server_tick += 1
		npc.ai.think(net, npc)
	check(npc.ai.fog_mode == "", "about a second out, it's itself again")
	check(npc.ai._pick_target(net, npc) == null, "from outside, it still can't target the caster inside")
	a.state.pos = C + Vector3(0, 0, 20)
	check(npc.ai._pick_target(net, npc) == a, "the caster outside: fair game again")

	# ---- outside, challengers walk round it to reach someone on the far side
	net.players.erase(npc.id)
	a.state = Sim.spawn_state(1)
	a.state.pos = C + Vector3(0, 0, 22)
	b.state.pos = C + Vector3(60, 0, 60)
	var walker := net.spawn_npc(a, Weapons.SWORD, 2)
	walker.state.pos = C + Vector3(1.5, 0, -22)
	net.fogs = [Fog.make(100, C, 2, net.server_tick, { "duration": 6000 })]   # 2's fog: 2 is the challenger's enemy too
	var entered := false
	var start_d := walker.state.pos.distance_to(a.state.pos)
	for k in 900:
		net._server_tick()
		a.state.hp = Sim.MAX_HP
		a.state.dead = 0
		if Fog.covers(net.fogs[0], walker.state.pos, net.server_tick):
			entered = true
	var end_d := walker.state.pos.distance_to(a.state.pos)
	check(not entered, "it never walks into the fog")
	check(end_d < start_d - 15.0, "and gets round it toward its target (%.0f -> %.0f m)" % [start_d, end_d])

	# ---- an enemy golem in the fog is confused too; the caster's own golem isn't
	net.players.erase(walker.id)
	var npc2 := net.spawn_npc(a, Weapons.WAND, 1)
	net.fogs = [Fog.make(101, C, 1, net.server_tick, { "duration": 6000 })]
	var eg := net.golems.spawn(npc2.id, C + Vector3(2, 0, 2), 0.0, net.server_tick)
	var og := net.golems.spawn(1, C + Vector3(-2, 0, -2), 0.0, net.server_tick)
	a.state.pos = C + Vector3(3, 0, 3)
	for k in 120:
		net.server_tick += 1
		net._server_spells()
	check(eg.fog_mode in ["thrash", "stumble"] and eg.target == 0, "the challenger's golem in 1's fog: confused (%s)" % eg.fog_mode)
	check(og.fog_mode == "", "1's own golem sees fine")

	# ---- Thunderhorn doesn't care: he picks his target the same with or without a fog over them
	var bs := Boss.new(C + Vector3(0, 0, 10), 1)
	var rows := [[1, C + Vector3(0, 0, 2), true, false, 100]]
	bs._retarget(rows, [])
	var t_plain := bs.target
	net.fogs = [Fog.make(102, C, 1, net.server_tick, { "duration": 6000 })]
	var bs2 := Boss.new(C + Vector3(0, 0, 10), 1)
	bs2._retarget(rows, [])
	check(t_plain == 1 and bs2.target == t_plain, "Thunderhorn's targeting is the same in the fog")
	var boss_src := FileAccess.get_file_as_string("res://scripts/boss.gd")
	check(boss_src.find("Fog.") < 0 and boss_src.find("fogs") < 0, "and boss.gd has no fog rules at all")

	_spells(net, a, b)
	print("%d failed" % bad)
	quit(1 if bad > 0 else 0)


## Spark Beam and Life Drain on the server.
func _spells(net: Net, a: Net.ServerPlayer, b: Net.ServerPlayer) -> void:
	net.fogs = []
	for q in net.players.values().duplicate():
		if q.npc:
			net.players.erase(q.id)
	a.pvp = true
	b.pvp = true
	a.state = Sim.spawn_state(1)
	a.state.pos = Vector3(60, 0, 60)
	a.state.yaw = 0.0
	a.state.weapon = Weapons.WAND
	b.state = Sim.spawn_state(2)
	b.state.pos = Vector3(60, 0, 50)
	var sb := Weapons.spell_named(Weapons.WAND, "Spark Beam")
	a.state.spell = Weapons.idx(Weapons.WAND, "Spark Beam")
	net._cast(a, Sim.PlayerInput.new(1, 0, 0.0, 0.0, Weapons.WAND, 0, 0.0, INF, a.state.spell, Vector3(60, 1.2, 40)), a.state.pos)
	check(b.state.hp == Sim.MAX_HP - int(sb.damage), "a spark beam zaps the first enemy along the aim (%d)" % (Sim.MAX_HP - b.state.hp))
	b.state.pos = Vector3(66, 0, 50)
	var h := b.state.hp
	net._cast(a, Sim.PlayerInput.new(2, 0, 0.0, 0.0, Weapons.WAND, 0, 0.0, INF, a.state.spell, Vector3(60, 1.2, 40)), a.state.pos)
	check(b.state.hp == h, "and misses someone off the line")
	b.state.pos = Vector3(60, 0, 50)
	b.state.hp = Sim.MAX_HP
	a.state.hp = 50
	var ld := Weapons.spell_named(Weapons.WAND, "Life Drain")
	a.state.spell = Weapons.idx(Weapons.WAND, "Life Drain")
	net._cast(a, Sim.PlayerInput.new(3, 0, 0.0, 0.0, Weapons.WAND, 0, 0.0, INF, a.state.spell, Vector3(60, 1.2, 40)), a.state.pos)
	var dealt := Sim.MAX_HP - b.state.hp
	check(dealt == int(ld.damage), "life drain hits for %d" % dealt)
	check(a.state.hp == 50 + int(round(dealt * 0.45)), "and gives 45%% back to the caster (+%d)" % (a.state.hp - 50))
	b.state.hp = 5
	a.state.hp = 50
	net._cast(a, Sim.PlayerInput.new(4, 0, 0.0, 0.0, Weapons.WAND, 0, 0.0, INF, a.state.spell, Vector3(60, 1.2, 40)), a.state.pos)
	check(a.state.hp == 50 + 2, "it only gives back what it really took (5 -> +2)")
	b.state.shield = 0
	a.pvp = false
	b.pvp = false
