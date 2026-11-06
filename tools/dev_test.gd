extends SceneTree
## v0.12.6 the dev console's commands (DevCmd), run offline through Net like the host typing them: grant weapons and
## levels, max everything, spawn units on each side with tier / level / size / name, sides deciding who fights whom,
## size changing reach, god mode, rename, guests needing `cheats on`, funny names.
##   Godot --headless --path . --script tools/dev_test.gd

var bad := 0

func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		bad += 1


func _initialize() -> void:
	var net := Net.new()
	root.add_child(net)
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	net._server_add_player(1, "Jacob")
	net._server_add_player(2, "Friend Bob")
	var a: Net.ServerPlayer = net.players[1]
	var b: Net.ServerPlayer = net.players[2]
	var run := func(line: String, who := 1) -> String:
		var r := DevCmd.run(net, who, line)
		print("   > %s\n     %s" % [line, r.replace("\n", "\n     ")])
		return r

	# grants and levels
	run.call("give staff")
	check((a.state.owned >> Weapons.STAFF) & 1 == 1 and a.state.weapon == Weapons.STAFF, "give staff: owned and in hand")
	run.call("level staff max")
	check(a.state.staff_lvl == 4 and a.kills[0] == 12, "level staff max: staff level 4 (%d)" % a.state.staff_lvl)
	run.call("level sword 3 bob")
	check(Net.arm_level(b, Weapons.SWORD) == 3 and (b.state.owned >> Weapons.SWORD) & 1 == 1, "level sword 3 bob: Bob's sword level 3, and he has one")
	check(Net.arm_level(a, Weapons.SWORD) == 1, "mine untouched")
	run.call("level wand 2 \"Friend Bob\"")
	check(b.state.wand_lvl == 2, "a quoted full name works")
	run.call("max bob")
	var all_max := b.state.staff_lvl == 4 and b.state.wand_lvl == 4 and b.state.owned == 127
	for w in [Weapons.FISTS, Weapons.CLUB, Weapons.SWORD, Weapons.BOW, Weapons.SLING]:
		all_max = all_max and Net.arm_level(b, w) == 4
	check(all_max and b.state.arrows == Weapons.MAX_AMMO, "max bob: every weapon, every level 4, full ammo")
	run.call("maxall")
	check(a.state.owned == 127 and a.state.wand_lvl == 4 and Net.arm_level(a, Weapons.BOW) == 4, "maxall (me): everything")
	run.call("take bow bob")
	check((b.state.owned >> Weapons.BOW) & 1 == 0, "take bow bob")

	# guests need cheats on; anyone can rename themselves
	var r := str(run.call("give all", 2))
	check(r.begins_with("Only the host"), "a guest can't use dev commands")
	run.call("name Bobbert the Brave", 2)
	check(b.name == "Bobbert the Brave", "but anyone can change their own name (%s)" % b.name)
	run.call("cheats on")
	run.call("give club", 2)
	check((b.state.owned >> Weapons.CLUB) & 1 == 1, "after cheats on, guests can")
	run.call("cheats off")

	# spawning
	a.state.pos = Vector3(20, 0, 20)
	a.state.yaw = 0.0
	run.call("spawn sword 3 friendly tier 3 level 4 size 1.5")
	var friends := net.players.values().filter(func(p): return p.npc and Net.side_of(p) == Net.Side.ALLY)
	check(friends.size() == 3, "spawn 3 friendly swords (%d)" % friends.size())
	var f0: Net.ServerPlayer = friends[0]
	check(f0.ai.difficulty == 2 and f0.name.ends_with("(tier 3)") and is_equal_approx(f0.size, 1.5) and Net.arm_level(f0, Weapons.SWORD) == 4,
		"tier 3, level 4, size 1.5: %s" % f0.name)
	run.call("spawn club hostile name \"Gary the Unkillable\"")
	var foes := net.players.values().filter(func(p): return p.npc and Net.side_of(p) == Net.Side.HOSTILE)
	check(foes.size() == 1 and foes[0].name.begins_with("Gary the Unkillable"), "a hostile one with a chosen name")
	run.call("spawn bow neutral")
	var neu := net.players.values().filter(func(p): return p.npc and Net.side_of(p) == Net.Side.NEUTRAL)
	check(neu.size() == 1, "a neutral one")
	var h: Net.ServerPlayer = foes[0]
	var n: Net.ServerPlayer = neu[0]

	# who fights whom
	check(net.npc_foe(h, a) and net.npc_foe(h, f0), "hostile goes after players and friendly units")
	check(net.npc_foe(f0, h) and not net.npc_foe(f0, a) and not net.npc_foe(f0, friends[1]), "friendly goes after hostile, never players or friends")
	check(not net.npc_foe(n, a) and not net.npc_foe(n, h) and not net.npc_foe(h, n), "neutral fights nobody, and nobody goes for it")
	check(not net.can_hurt(f0.id, 1) and not net.can_hurt(1, f0.id), "players and friendly units can't hurt each other")
	check(net.can_hurt(f0.id, h.id) and net.can_hurt(h.id, 1) and net.can_hurt(1, n.id), "friendly vs hostile, hostile vs player, anyone vs neutral: yes")
	net._damage(n.id, 5, 1, Vector3(1, 0, 0), 0.0)   # Jacob pokes the neutral one
	net.golems._now = net.server_tick
	check(net.npc_foe(n, a), "a neutral one hurt by you fights you back")
	check(not net.npc_foe(n, b), "but not someone else")
	# friendly units go after a neutral only once it has hurt them or you
	net._damage(1, 5, n.id, Vector3(1, 0, 0), 0.0)
	check(net.npc_foe(f0, n), "a neutral that hurt you: your friendly units go after it")
	# their brains really pick by side
	for q in [f0, h]:
		q.ai.reach = 200.0
	var ft = f0.ai._pick_target(net, f0)
	check(ft != null and ft.id != 1 and Net.side_of(ft) != Net.Side.ALLY, "a friendly unit's brain picks an enemy, not you (%s)" % (ft.name if ft else "nobody"))

	# size: reach and hitbox
	run.call("size me 3")
	check(is_equal_approx(a.size, 3.0), "size me 3")
	run.call("size me 99")
	check(is_equal_approx(a.size, DevCmd.SIZE_MAX), "size is clamped to %.1f" % DevCmd.SIZE_MAX)
	a.size = 1.0
	b.size = 1.0
	b.pvp = true
	a.pvp = true
	a.state.pos = Vector3(60, 0, 60)
	a.state.yaw = 0.0
	a.state.weapon = Weapons.SWORD
	a.state.combo = 0
	b.state.pos = Vector3(60, 0, 60 - 4.5)   # beyond a sword's 2.5 m (+0.4)
	b.state.hp = Sim.MAX_HP
	b.state.dead = 0
	b.hist = []
	var inp := Sim.PlayerInput.new()
	inp.view_tick = net.server_tick
	net._melee(a, inp)
	check(b.state.hp == Sim.MAX_HP, "a normal-sized sword can't reach 4.5 m")
	a.size = 2.0
	net._melee(a, inp)
	check(b.state.hp < Sim.MAX_HP, "a size-2 one can (%d damage)" % (Sim.MAX_HP - b.state.hp))
	a.size = 1.0

	# god, heal, kill, rename, tier, side, clear, list
	run.call("god")
	check(a.god and not net.can_hurt(2, 1), "god: nobody can hurt you")
	run.call("god off")
	check(not a.god, "god off")
	run.call("kill bob")
	check(b.state.dead > 0, "kill bob")
	run.call("rename gary \"Gary the Very Killable\"")
	check(h.name == "Gary the Very Killable", "rename (%s)" % h.name)
	run.call("tier gary 1")
	check(h.ai.difficulty == 0 and h.name.ends_with("(tier 1)"), "tier gary 1 (%s)" % h.name)
	run.call("side gary friendly")
	check(Net.side_of(h) == Net.Side.ALLY, "side gary friendly")
	var lst := str(run.call("list"))
	check("Jacob" in lst and "friendly" in lst and "#" in lst, "list shows everyone")
	check(str(run.call("help")).contains("spawn"), "help lists the commands")
	check(str(run.call("frobnicate")).begins_with("Unknown"), "an unknown command says so")
	var units := net.players.values().filter(func(p): return p.npc).size()
	run.call("clear")
	check(net.players.values().filter(func(p): return p.npc).is_empty() and units == 5, "clear removes all %d units" % units)

	# names
	var nm := Names.npc(12345)
	check(nm.length() > 3, "a funny name: " + nm)
	check(Names.golem(7, false) == Names.golem(7, false) and Names.golem(7, true) in Names.TITAN, "golem names come from the id: %s, titan %s" % [Names.golem(7, false), Names.golem(7, true)])

	print("dev: %s" % ("ALL OK" if bad == 0 else "%d FAILED" % bad))
	quit(1 if bad > 0 else 0)
