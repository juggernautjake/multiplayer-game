extends SceneTree
## v0.12.0 challenger wizards, run offline on the server: their kit is their weapon's level-1 spells only; a staff
## wizard really runs out of mana (no top-ups), then rests and stops casting until it's back; a wand wizard doesn't
## land every spark on a strafing player (aim error, no lead); over a long fight each uses every spell of its kit and
## never casts the same one more than three times running; a visible wind-up before every cast.
##   Godot --headless --path . --script tools/wizard_test.gd   (prints harmless "not inside tree" RPC errors)

var bad := 0


func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		bad += 1


func max_run(list: Array) -> int:
	var best := 0
	var run := 0
	for i in list.size():
		run = run + 1 if i > 0 and list[i] == list[i - 1] else 1
		best = maxi(best, run)
	return best


func names(w: int, idx: Array) -> Array:
	var out := []
	for i in idx:
		out.append(str(Weapons.spell(w, i).name))
	return out


func _initialize() -> void:
	var net := Net.new()
	root.add_child(net)
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	net._server_add_player(1, "P1")
	var a: Net.ServerPlayer = net.players[1]
	a.state.staff_lvl = 4
	a.state.wand_lvl = 4
	var P := Vector3(90, 0, -90)

	# ---- kits
	var sk := names(Weapons.STAFF, NpcAI.kit(Weapons.STAFF))
	var wk := names(Weapons.WAND, NpcAI.kit(Weapons.WAND))
	print("      staff kit: ", sk, "   wand kit: ", wk)
	check(sk == ["Lightning", "Fireball", "Shield"], "staff wizards: Lightning, Fireball, Shield only (level 1)")
	check(wk == ["Spark Beam", "Golem", "Teleport", "Stun"], "wand wizards: Spark Beam, Golem, Teleport, Stun only (level 1)")

	# ---- a staff wizard's mana runs out; it rests and stops casting until it's back
	a.state.pos = P
	var wz := net.spawn_npc(a, Weapons.STAFF, 1)
	wz.state.pos = P + Vector3(0, 0, -11)
	var min_mana := 99999
	var cast_while_resting := 0
	var rested := false
	var n_before := 0
	var spent := 0
	var prev_mana := wz.state.mana
	for t in 2700:
		var resting_before: bool = wz.ai._resting
		n_before = wz.ai.casts.size()
		net._server_tick()
		a.state.hp = Sim.MAX_HP
		a.state.dead = 0
		if wz.state.mana < prev_mana:
			spent += prev_mana - wz.state.mana
		prev_mana = wz.state.mana
		min_mana = mini(min_mana, wz.state.mana)
		if resting_before and wz.ai._resting:
			rested = true
			if wz.ai.casts.size() > n_before and wz.ai.casts[-1] != "Shield":
				cast_while_resting += 1
	print("      staff wizard: %d casts in 45 s, %s" % [wz.ai.casts.size(), str(wz.ai.casts.slice(0, 16))])
	check(min_mana < NpcAI.LOW_MANA * 5, "its mana really runs low (down to %d)" % (min_mana / 5))
	check(rested and cast_while_resting == 0, "then it rests: no spells until its mana is back")
	check(spent / 5 <= 100 + 12 * 45, "it never spends more than it has plus what comes back (%d mana in 45 s)" % (spent / 5))
	check(wz.ai.casts.size() <= 30, "it doesn't spam (%d casts in 45 s)" % wz.ai.casts.size())
	net.players.erase(wz.id)

	# ---- a wand wizard against a strafing player: aim error, no lead -> not every spark lands
	for strafe in [false, true]:
		a.state = Sim.spawn_state(1)
		a.state.pos = P
		var wd := net.spawn_npc(a, Weapons.WAND, 2)
		wd.state.pos = P + Vector3(0, 0, -10)
		var sparks := 0
		var hits := 0
		var last_n := wd.state.swing_n
		var spark_i := Weapons.idx(Weapons.WAND, "Spark Beam")
		for t in 2400:
			if strafe:
				var x := 3.5 * sin(t * 0.035)
				a.state.pos = P + Vector3(x, 0, 0)
				a.state.vel = Vector3(3.5 * 0.035 * 60.0 * cos(t * 0.035), 0, 0)
			else:
				a.state.pos = P
				a.state.vel = Vector3.ZERO
			var hp0 := a.state.hp
			net._server_tick()
			if wd.state.swing_n != last_n:
				last_n = wd.state.swing_n
				if wd.state.spell == spark_i:
					sparks += 1
			if hp0 - a.state.hp == 7:
				hits += 1
			a.state.hp = Sim.MAX_HP
			a.state.dead = 0
			a.state.stun = 0
		print("      wand wizard vs %s player: %d sparks, %d hit" % ["a strafing" if strafe else "a still", sparks, hits])
		if strafe:
			check(sparks >= 5 and hits < sparks and hits > 0, "it doesn't land every spark on a strafing player (%d of %d)" % [hits, sparks])
		net.players.erase(wd.id)
		for g in net.golems.list.keys():
			net.golems.list.erase(g)

	# ---- long fights: every spell of the kit, never more than three of a kind in a row, wind-ups before casts
	for w in [Weapons.STAFF, Weapons.WAND]:
		a.state = Sim.spawn_state(1)
		a.state.pos = P
		a.state.weapon = Weapons.BOW
		var npc := net.spawn_npc(a, w, 1)
		npc.state.pos = P + Vector3(0, 0, -11)
		var tells := 0
		for t in 4800:
			var d := npc.state.pos - a.state.pos
			a.state.yaw = atan2(-d.x, -d.z)
			a.state.charge = 45 if t % 90 >= 40 and t % 90 < 75 else 0   # drawing a bow at it (a wizard sees that)
			if t % 90 == 75:   # and letting go
				var yaw := atan2(-d.x, -d.z)
				a.state.last_charge = 45
				net._shoot(a, Sim.PlayerInput.new(0, 0, yaw, 0.0, Weapons.BOW, 0, yaw))
			if t % 700 == 300:   # and closing right in on it
				a.state.pos = npc.state.pos + Vector3(1.5, 0, 1.0)
			if npc.ai._wind == NpcAI.WINDUP[1] - 1:
				tells += 1
			net._server_tick()
			a.state.hp = Sim.MAX_HP
			a.state.dead = 0
			a.state.stun = 0
			if npc.state.hp < 40:
				npc.state.hp = Sim.MAX_HP   # keep it in the fight
		var kit := names(w, NpcAI.kit(w))
		var used := {}
		for c in npc.ai.casts:
			used[c] = true
		var missing := kit.filter(func(k): return not used.has(k))
		print("      %s wizard over 80 s: %d casts, run %d, %s" % [Weapons.NAMES[w], npc.ai.casts.size(), max_run(npc.ai.casts), str(npc.ai.casts.slice(0, 20))])
		check(missing.is_empty(), "the %s wizard uses its whole kit (missing: %s)" % [Weapons.NAMES[w].to_lower(), str(missing)])
		check(max_run(npc.ai.casts) <= NpcAI.MAX_SAME, "and never the same spell more than 3 times in a row (%d)" % max_run(npc.ai.casts))
		check(tells >= 5, "with a wind-up before its casts (%d seen)" % tells)
		for c in npc.ai.casts:
			if not (c in kit):
				check(false, "cast something outside its kit: " + c)
				break
		net.players.erase(npc.id)
		for g in net.golems.list.keys():
			net.golems.list.erase(g)
	_npc_golems(net, a, P)
	print("%d failed" % bad)
	quit(1 if bad > 0 else 0)


## NPC wand wizards' golems: at most 3 of their own; they go for players (PvP or not) and players' golems; players'
## golems go for them; killing one gives no level; they crumble when their wizard falls.
func _npc_golems(net: Net, a: Net.ServerPlayer, P: Vector3) -> void:
	a.state = Sim.spawn_state(1)
	a.state.pos = P
	a.pvp = false
	var wd := net.spawn_npc(a, Weapons.WAND, 1)
	wd.state.pos = P + Vector3(0, 0, -10)
	var most := 0
	for t in 3600:
		a.state.pos = P
		net._server_tick()
		a.state.hp = Sim.MAX_HP
		a.state.dead = 0
		a.state.stun = 0
		if wd.state.hp < 40:
			wd.state.hp = Sim.MAX_HP
		var n := 0
		for g: Golems.G in net.golems.list.values():
			if g.owner == wd.id and g.state != Golems.State.DIE:
				n += 1
		most = maxi(most, n)
	check(most == NpcAI.MAX_GOLEMS, "an NPC wand wizard summons golems but never more than 3 at once (%d)" % most)
	# its golem goes for a player with PvP off
	var ng: Golems.G = null
	for g: Golems.G in net.golems.list.values():
		if g.owner == wd.id and g.state != Golems.State.DIE:
			ng = g
	var hits := 0
	for t in 300:
		net.server_tick += 1
		var hp0 := a.state.hp
		net._server_spells()
		if a.state.hp < hp0:
			hits += 1
		a.state.hp = Sim.MAX_HP
		a.state.pos = ng.pos + Vector3(1.0, 0, 0)
	check(not a.pvp and hits > 0, "its golems attack players, PvP or not (%d hits)" % hits)
	# a player's golem goes for the NPC's golem; killing it gives no level
	var pg := net.golems.spawn(1, ng.pos + Vector3(2.5, 0, 0), 0.0, net.server_tick)
	a.state.pos = ng.pos + Vector3(6, 0, 0)   # within the golem's leash of its summoner
	var picked := false
	for t in 120:
		net.server_tick += 1
		net._server_spells()
		if pg.target == -1000 - ng.id or (pg.target <= -1000 and net.golems.list.has(-1000 - pg.target) and net.golems.list[-1000 - pg.target].owner == wd.id):
			picked = true
	check(picked, "players' golems attack the NPC's golems")
	var k0: Array = a.kills.duplicate()
	net.dmg_src = Weapons.WAND
	net._damage(-1000 - ng.id, 500, 1, Vector3(1, 0, 0), 0.0)
	net.dmg_src = -1
	check(a.kills == k0, "killing an NPC's golem gives no level credit")
	# the wizard falls: its golems crumble
	net._damage(wd.id, 500, 1, Vector3(1, 0, 0), 0.0)
	net._server_npcs()
	var left := 0
	for g: Golems.G in net.golems.list.values():
		if g.owner == wd.id and g.state != Golems.State.DIE:
			left += 1
	check(left == 0, "when the wizard falls its golems crumble")
	check(net.golems.foe(1, wd.id, {}) and not net.golems.foe(wd.id, wd.id, {}), "players' golems count challengers / minions as foes (golem_test covers Thunderhorn)")
