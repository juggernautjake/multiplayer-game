extends SceneTree
## v0.12.7 progress survives a restart (an update) or a rejoin: the host saves each player's progress by name and
## gives it back when they join again; the staff / wand are given back too; nothing is saved unless persist is on.
## Uses its own file (user://progress_test.json), never the real one.
##   Godot --headless --path . --script tools/progress_test.gd

var bad := 0

func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		bad += 1


func _new_net(persist: bool) -> Net:
	var net := Net.new()
	root.add_child(net)
	net.persist = persist
	net.progress_path = "user://progress_test.json"
	for i in WorldLayout.ITEM_SPAWNS.size():
		net._spawn_item_at(i)
	net._load_progress()
	return net


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://progress_test.json"))
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()

	# ---- a session: Jacob and Bob play and earn things
	var net := _new_net(true)
	net._server_add_player(1, "Jacob")
	net._server_add_player(2, "Bob")
	var a: Net.ServerPlayer = net.players[1]
	var b: Net.ServerPlayer = net.players[2]
	a.state.owned = 0b1111111   # everything, the staff and the wand included
	a.state.staff_lvl = 3
	a.state.wand_lvl = 2
	a.kills = [7, 3]
	a.arms = [0, 2, 9, 1, 0]
	a.duel_wins = 5
	a.state.arrows = 17
	a.state.rocks = 4
	a.state.weapon = Weapons.SWORD
	a.state.pos = Vector3(30, 0, 12)
	a.pvp = true
	b.state.owned = 0b11
	b.arms = [4, 0, 0, 0, 0]
	a.mxp[0] = 750.0       # spell mastery points and levels come back too
	a.state.mastery = 0b1001
	net.save_progress()
	check(FileAccess.file_exists("user://progress_test.json"), "progress written to disk")
	net.shutdown()
	net.free()

	# ---- the host restarts (an update): a new world, then they join again
	var net2 := _new_net(true)
	var staff_items := net2.items.values().filter(func(it): return it.kind == Weapons.Item.STAFF).size()
	check(staff_items == 1, "the new world has its staff on the tower")
	net2._server_add_player(1, "jacob")   # (names match whatever the case)
	var a2: Net.ServerPlayer = net2.players[1]
	check(a2.state.owned == 0b1111111 and a2.state.staff_lvl == 3 and a2.state.wand_lvl == 2, "Jacob's weapons and staff / wand levels are back")
	check(a2.kills == [7, 3] and a2.arms == [0, 2, 9, 1, 0] and a2.duel_wins == 5, "his kills (magic and the others) and challengers beaten too")
	check(a2.state.arrows == 17 and a2.state.rocks == 4 and a2.state.weapon == Weapons.SWORD and a2.pvp, "ammo, the weapon in hand, PvP")
	check(a2.state.pos.distance_to(Vector3(30, 0, 12)) < 0.2, "and he's back where he was")
	check(is_equal_approx(float(a2.mxp[0]), 750.0) and a2.state.mastery == 0b1001, "his spell mastery points and levels too")
	check(net2.items.values().filter(func(it): return it.kind == Weapons.Item.STAFF).size() == 1, "v0.12.12: the tower keeps its staff for others")
	net2._server_add_player(2, "Bob")
	check(net2.players[2].arms == [4, 0, 0, 0, 0] and net2.players[2].state.owned == 0b11, "Bob's back too")
	net2._server_add_player(3, "Newcomer")
	check(net2.players[3].state.owned == 1 and net2.players[3].kills == [0, 0], "someone new starts fresh")

	# ---- v0.12.12 someone else took the wand meanwhile: he still gets his back (there can be several now)
	net2.players[3].state.owned |= 1 << Weapons.WAND
	net2.players.erase(1)
	net2._server_add_player(4, "Jacob")
	check((net2.players[4].state.owned >> Weapons.WAND) & 1 and (net2.players[4].state.owned >> Weapons.STAFF) & 1,
		"his staff and wand are given back even if someone else has one too")
	net2.shutdown()
	net2.free()

	# ---- tests / bots: nothing saved, nothing restored
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://progress_test.json"))
	var net3 := _new_net(false)
	net3._server_add_player(1, "Jacob")
	net3.players[1].state.owned = 0b1111111
	net3.save_progress()
	check(not FileAccess.file_exists("user://progress_test.json"), "with persist off nothing is written")
	net3.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://progress_test.json"))

	print("progress: %s" % ("ALL OK" if bad == 0 else "%d FAILED" % bad))
	quit(1 if bad > 0 else 0)
