extends SceneTree
## v0.12.2 golem orders (Golems.order): Follow keeps them round the summoner as they walk, Stay holds the spot (and
## fights only what comes within HOLD_R of it), Go there walks them to a point and holds it, Attack that sends every
## golem (and the titan) after one target first and ends when it dies or stays out of reach 5 s, Regroup brings them
## back, PvP off still blocks ordering them against players, Thunderhorn is fought (his id no longer reads as a
## golem's); and through Net: the order is checked on the server, refused with a toast, and synced to every screen.
##   Godot --headless --path . --script tools/order_test.gd

var bad := 0


func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		bad += 1


const C := Vector3(60, 0, 60)   # open ground, away from the pillars near the spawn


func me_at(p: Vector3, pvp := false) -> Array:
	return [1, p, pvp, true, Golems.Who.PLAYER]


## n small golems of player 1 round `at`, risen.
func squad(n: int, at := C, titan := false) -> Golems:
	var gs := Golems.new()
	for i in n:
		gs.spawn(1, at + Vector3(i * 1.2 - 1.0, 0, 0), 0.0, 0)
	if titan:
		gs.spawn(1, at + Vector3(0, 0, 2.5), 0.0, 0, true)
	for t in range(1, Golems.RISE + 2):
		gs.tick(t, [me_at(at)])
	return gs


func far_of(gs: Golems, p: Vector3) -> float:
	var worst := 0.0
	for g: Golems.G in gs.list.values():
		if g.state != Golems.State.DIE:
			worst = maxf(worst, Vector2(g.pos.x - p.x, g.pos.z - p.z).length())
	return worst


func _initialize() -> void:
	_follow()
	_stay()
	_go_there()
	_attack_first()
	_attack_ends()
	_pvp_rules()
	_regroup()
	_boss()


var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return false
	_done = true
	_through_net()   # once the tree is up (Net sends RPCs)
	print("%d failed" % bad)
	quit(bad)
	return false


func _follow() -> void:
	var gs := squad(3, C, true)
	var t := 100
	var me := C
	for k in 300:   # the summoner walks 18 m away
		me += Vector3(0, 0, -Sim.WALK_SPEED * Config.DT)
		gs.tick(t, [me_at(me)])
		t += 1
	for k in 240:
		gs.tick(t, [me_at(me)])
		t += 1
	var d := far_of(gs, me)
	check(d < Golems.GUARD_R * 1.8 + 1.0, "Follow: they keep up and stand round the summoner (farthest %.1f m)" % d)


func _stay() -> void:
	var gs := squad(3, C, true)
	check(gs.order(1, Golems.Order.STAY, Vector3.ZERO, 0, 100, [me_at(C)]) == "", "Stay here is taken")
	var t := 101
	var me := C
	var hits_far := 0
	var hits_near := 0
	var worst := 0.0
	for k in 600:   # the summoner walks off 30 m; a challenger stands 12 m from the spot (not near enough)
		if k < 300:
			me += Vector3(0, 0, -6.0 * Config.DT)
		for h in gs.tick(t, [me_at(me), [2000000, C + Vector3(12, 0, 0), true, true, Golems.Who.NPC]]):
			if int(h[1]) == 2000000:
				hits_far += 1
		worst = maxf(worst, far_of(gs, C))
		t += 1
	check(worst < Golems.HOLD_R and far_of(gs, C) < Golems.GUARD_R * 1.8 + 1.0, "Stay: they hold the spot while the summoner walks away (farthest ever %.1f m)" % worst)
	check(hits_far == 0, "Stay: an enemy 12 m from the spot is left alone (HOLD_R %.0f m)" % Golems.HOLD_R)
	worst = 0.0
	for k in 400:   # one comes within 5 m of the spot
		for h in gs.tick(t, [me_at(me), [2000000, C + Vector3(5, 0, 0), true, true, Golems.Who.NPC]]):
			if int(h[1]) == 2000000:
				hits_near += 1
		worst = maxf(worst, far_of(gs, C))
		t += 1
	check(hits_near > 0 and worst < Golems.HOLD_R + 2.0, "Stay: one who comes near the spot is fought, without straying (%d hits, farthest %.1f m)" % [hits_near, worst])


func _go_there() -> void:
	var gs := squad(2, C, true)
	var spot := C + Vector3(-16, 0, -6)
	check(gs.order(1, Golems.Order.GOTO, spot, 0, 100, [me_at(C)]) == "", "Go there is taken")
	var t := 101
	for k in 420:
		gs.tick(t, [me_at(C)])
		t += 1
	var d := far_of(gs, spot)
	check(d < Golems.GUARD_R * 1.8 + 1.0, "Go there: golems and titan walk 17 m to the spot and hold it (farthest %.1f m)" % d)
	var far_spot := C + Vector3(0, 0, -200)
	gs.order(1, Golems.Order.GOTO, far_spot, 0, t, [me_at(C)])
	var p: Vector3 = gs.order_of(1)[1]
	check(absf(Vector2(p.x - C.x, p.z - C.z).length() - Golems.GOTO_MAX) < 0.01, "a spot further than %d m is brought in to %d m" % [int(Golems.GOTO_MAX), int(Golems.GOTO_MAX)])


func _attack_first() -> void:
	var gs := squad(3, C, true)
	var near := [2000001, C + Vector3(0, 0, -3), true, true, Golems.Who.NPC]
	var far := [2000002, C + Vector3(10, 0, -6), true, true, Golems.Who.NPC]
	gs.tick(100, [me_at(C), near, far])
	check(gs.order(1, Golems.Order.ATTACK, Vector3.ZERO, 2000002, 101, [me_at(C), near, far]) == "", "Attack that is taken")
	var first := 0
	var all_on := true
	for t in range(102, 400):
		for h in gs.tick(t, [me_at(C), near, far]):
			if first == 0:
				first = int(h[1])
		for g: Golems.G in gs.list.values():
			if g.state != Golems.State.ATTACK and g.state != Golems.State.LEAP and g.target != 2000002:
				all_on = false
	check(first == 2000002, "the ordered target is hit first, though another enemy is nearer (first hit on %d)" % first)
	check(all_on, "every golem and the titan go after it")


func _attack_ends() -> void:
	# the target dies (drops out of the list of the living): back to Follow
	var gs := squad(2)
	var foe := [2000003, C + Vector3(0, 0, -6), true, true, Golems.Who.NPC]
	gs.order(1, Golems.Order.ATTACK, Vector3.ZERO, 2000003, 100, [me_at(C), foe])
	gs.orders_dirty.clear()
	gs.tick(101, [me_at(C), foe])
	var dead := [2000003, C + Vector3(0, 0, -6), true, false, Golems.Who.NPC]
	gs.tick(102, [me_at(C), dead])
	check(gs.order_of(1)[0] == Golems.Order.FOLLOW and gs.orders_dirty.has(1), "the attack order ends when the target dies (and is sent)")
	# out of reach: more than ORDER_LEASH from the summoner for 5 s
	var gl := squad(2)
	var runner := C + Vector3(0, 0, -8)
	gl.order(1, Golems.Order.ATTACK, Vector3.ZERO, 2000004, 100, [me_at(C), [2000004, runner, true, true, Golems.Who.NPC]])
	var ended_at := -1
	for t in range(101, 101 + 900):
		runner += Vector3(0, 0, -12.0 * Config.DT)   # faster than golems: it gets away
		gl.tick(t, [me_at(C), [2000004, runner, true, true, Golems.Who.NPC]])
		if ended_at < 0 and gl.order_of(1)[0] == Golems.Order.FOLLOW:
			ended_at = t
	var out_from := 101 + int((Golems.ORDER_LEASH - 8.0) / 12.0 * 60.0)
	check(ended_at > 0 and absi(ended_at - out_from - Golems.ORDER_OUT) < 30, "the attack order ends %.1f s after the target got out of reach (want 5)" % ((ended_at - out_from) / 60.0))


func _pvp_rules() -> void:
	# PvP off: refused, and nobody hits player 2
	var gs := squad(3)
	var p2off := [2, C + Vector3(0, 0, -4), false, true, Golems.Who.PLAYER]
	var why := gs.order(1, Golems.Order.ATTACK, Vector3.ZERO, 2, 100, [me_at(C, true), p2off])
	check(why != "" and gs.order_of(1)[0] == Golems.Order.FOLLOW, "PvP off: ordering them against a player is refused (\"%s\")" % why)
	var hits := 0
	for t in range(101, 400):
		for h in gs.tick(t, [me_at(C, true), p2off]):
			if int(h[1]) == 2:
				hits += 1
	check(hits == 0, "PvP off: player 2 is never hit")
	# PvP on for both: taken (no grudge needed), then player 2 turns PvP off: the order ends, the hits stop
	var go := squad(3)
	var p2on := [2, C + Vector3(0, 0, -4), true, true, Golems.Who.PLAYER]
	check(go.order(1, Golems.Order.ATTACK, Vector3.ZERO, 2, 100, [me_at(C, true), p2on]) == "", "PvP on for both: the order is taken without a grudge")
	var hits_on := 0
	for t in range(101, 300):
		hits_on += go.tick(t, [me_at(C, true), p2on]).size()
	check(hits_on > 0, "and they attack player 2 (%d hits)" % hits_on)
	var hits_after := 0
	for t in range(300, 600):
		for h in go.tick(t, [me_at(C, true), p2off]):
			if int(h[1]) == 2 and t > 300 + Golems.ATTACK:   # (a swing already coming down may land)
				hits_after += 1
	check(go.order_of(1)[0] == Golems.Order.FOLLOW and hits_after == 0, "player 2 turns PvP off: the order ends and the hits stop")
	# another player's golem: the same rule
	var gg := squad(1)
	var theirs := gg.spawn(2, C + Vector3(0, 0, -5), 0.0, 0)
	check(gg.order(1, Golems.Order.ATTACK, Vector3.ZERO, -1000 - theirs.id, 100, [me_at(C, true), p2off]) != "", "PvP off: their golem can't be ordered against either")
	check(gg.order(1, Golems.Order.ATTACK, Vector3.ZERO, -1000 - theirs.id, 101, [me_at(C, true), p2on]) == "", "PvP on: it can")
	# no golems: nothing to order
	check(Golems.new().order(1, Golems.Order.STAY, C, 0, 1, [me_at(C)]) != "", "no golems: the order is refused")


func _regroup() -> void:
	var gs := squad(3)
	var foe := [2000005, C + Vector3(0, 0, -12), true, true, Golems.Who.NPC]
	for t in range(100, 220):   # they go after it
		gs.tick(t, [me_at(C), foe])
	var was := far_of(gs, C)
	check(gs.order(1, Golems.Order.REGROUP, Vector3.ZERO, 0, 220, [me_at(C), foe]) == "", "Regroup is taken")
	var ended := -1
	var max_targets := 0
	for t in range(221, 221 + Golems.REGROUP_T + 10):
		gs.tick(t, [me_at(C), foe])
		if gs.order_of(1)[0] == Golems.Order.FOLLOW:   # (then they may well go back for it: they're following again)
			ended = t
			break
		for g: Golems.G in gs.list.values():
			if g.target != 0:
				max_targets += 1
	var back := far_of(gs, C)
	check(was > 5.0 and max_targets == 0 and ended > 0 and back <= Golems.REGROUP_NEAR + 0.2,"Regroup: they drop the fight and come back (%.1f m out -> %.1f m), then follow again after %.1f s" % [was, back, (ended - 221) / 60.0])


func _boss() -> void:
	var gs := squad(2)
	var boss := [Boss.ID, C + Vector3(0, 0, -10), true, true, Golems.Who.BOSS]
	var hits := 0
	for t in range(100, 500):
		for h in gs.tick(t, [me_at(C), boss]):
			if int(h[1]) == Boss.ID:
				hits += 1
	check(hits > 0, "golems close in on Thunderhorn and hit him (%d hits; his id used to read as a golem's)" % hits)
	check(gs.order(1, Golems.Order.ATTACK, Vector3.ZERO, Boss.ID, 500, [me_at(C), boss]) == "", "and can be ordered against him")


func _through_net() -> void:
	var net := Net.new()
	root.add_child(net)
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	net.is_host_player = true
	net.my_id = 1
	for id in [1, 2]:
		net._server_add_player(id, "P%d" % id)
	var toasts := []
	net.toast_msg.connect(func(s): toasts.append(s))
	var synced := []
	net.golem_order_changed.connect(func(o, m, p, t): synced.append([o, m, t]))
	net.request_golem_order(Golems.Order.STAY, Vector3.ZERO, 0)
	check(toasts.size() == 1 and synced.is_empty(), "no golems: the server says so (\"%s\")" % (toasts[0] if toasts.size() > 0 else ""))
	net.golems.spawn(1, net.players[1].state.pos + Vector3(2, 0, 0), 0.0, 0)
	net.request_golem_order(Golems.Order.ATTACK, Vector3.ZERO, 2)
	check(toasts.size() == 2 and synced.is_empty(), "PvP off: an attack order on player 2 is refused with a toast (\"%s\")" % (toasts[-1] if toasts.size() > 1 else ""))
	net.request_golem_order(Golems.Order.GOTO, net.players[1].state.pos + Vector3(6, 0, 6), 0)
	check(synced.size() == 1 and int(synced[0][1]) == Golems.Order.GOTO and net.golem_orders.has(1), "Go there is taken and synced to every screen")
	net.players[1].pvp = true
	net.players[2].pvp = true
	net.request_golem_order(Golems.Order.ATTACK, Vector3.ZERO, 2)
	check(synced.size() == 2 and int(synced[1][1]) == Golems.Order.ATTACK and int(synced[1][2]) == 2, "PvP on for both: the attack order on player 2 is taken")
	net.players[2].pvp = false
	net._server_spells()   # one tick of the golems: the order ends, and that's synced too
	check(synced.size() == 3 and int(synced[2][1]) == Golems.Order.FOLLOW and not net.golem_orders.has(1), "player 2 turns PvP off: the order ends and everyone hears")
	net.queue_free()
