extends SceneTree
## v0.12.7 ammo: a spent arrow or stone comes back as ONE (and looks like one, not a quiver / pile), the map has more
## ammo spots (none inside a pillar), E gathers stones beside a pillar and whittles arrows beside a tree (with a wait),
## a beaten archer / slinger drops a bundle, and weapons on the ground turn round their middle.
##   Godot --headless --path . --script tools/ammo_test.gd

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
	var a: Net.ServerPlayer = net.players[1]

	# every ammo spot lies on open ground
	var inside := []
	for s in WorldLayout.ITEM_SPAWNS:
		var p: Vector3 = s[1]
		if int(s[0]) in [Weapons.Item.ARROWS, Weapons.Item.ROCKS] and (Sim._body_in_box(p) or WorldLayout.tree_at(p + Vector3(0, 1, 0), 0.3) >= 0):
			inside.append(p)
	var ammo_spots := WorldLayout.ITEM_SPAWNS.filter(func(s): return int(s[0]) in [Weapons.Item.ARROWS, Weapons.Item.ROCKS]).size()
	check(inside.is_empty() and ammo_spots >= 12, "%d ammo spots, none inside a pillar or a tree %s" % [ammo_spots, str(inside)])

	# a spent arrow lands: one arrow on the ground
	var pr := Net.Proj.new()
	pr.id = 5
	pr.kind = 0
	pr.owner = 1
	net.projectiles[5] = pr
	var n0 := net.items.size()
	net._end_proj(pr, Vector3(30, 0.0, 30), true)
	var dropped: Net.Item = null
	for it: Net.Item in net.items.values():
		if it.spawn < 0:
			dropped = it
	check(net.items.size() == n0 + 1 and dropped != null and dropped.count == 1 and dropped.kind == Weapons.Item.ARROWS, "a spent arrow comes back as 1 arrow")
	a.state.arrows = 0
	a.state.pos = Vector3(30, 0, 30)
	net._pick_up(a, 1.3, false)
	check(a.state.arrows == 1, "picking it up gives 1 (%d)" % a.state.arrows)

	# the models: one arrow looks like one
	var one := WeaponModels.make(Weapons.Item.ARROWS, 1)
	var many := WeaponModels.make(Weapons.Item.ARROWS, 12)
	var st1 := WeaponModels.make(Weapons.Item.ROCKS, 1)
	var st12 := WeaponModels.make(Weapons.Item.ROCKS, 12)
	var meshes := func(n: Node) -> int: return n.find_children("*", "MeshInstance3D", true, false).size()
	check(one.get_child_count() == 1 and many.get_child_count() > 1, "1 arrow: a single arrow (%d), 12: a quiver (%d parts)" % [one.get_child_count(), meshes.call(many)])
	check(meshes.call(st1) == 1 and meshes.call(st12) == 5, "1 stone: one stone, 12: a pile (%d, %d)" % [meshes.call(st1), meshes.call(st12)])
	var bow := WeaponModels.bow()
	var mid := WeaponModels.middle(bow)
	check(absf(mid.y) < 0.05 and mid.z < 0.0 and mid.z > -0.13, "the bow turns round its middle (%s)" % str(mid))
	var sw := WeaponModels.sword()
	check(WeaponModels.middle(sw).y > 0.3, "the sword's middle is up its blade, not at the grip (%s)" % str(WeaponModels.middle(sw)))
	for m in [one, many, st1, st12, bow, sw]:
		m.free()

	# gathering: stones at a pillar, arrows at a tree, with a wait
	var b: WorldLayout.Box = WorldLayout.boxes()[0]
	a.state.pos = Vector3(b.cx + b.hx + 0.5, 0, b.cz)
	check(WorldLayout.gather_at(a.state.pos) == "stones", "beside a pillar: stones")
	a.state.rocks = 0
	net.server_tick = 1000
	check(net._gather(a) and a.state.rocks == WorldLayout.GATHER_STONES, "E gathers %d stones" % a.state.rocks)
	check(not net._gather(a) and a.state.rocks == WorldLayout.GATHER_STONES, "not again straight away")
	net.server_tick += WorldLayout.GATHER_STONE_CD
	check(net._gather(a) and a.state.rocks == 2 * WorldLayout.GATHER_STONES, "again after the wait (%d)" % a.state.rocks)
	var tp: Vector3 = WorldLayout.TREES[2][1]
	a.state.pos = tp + Vector3(0.9, 0, 0)
	check(WorldLayout.gather_at(a.state.pos) == "arrows", "beside a tree: arrows")
	a.state.arrows = 0
	net.server_tick += 1000
	check(net._gather(a) and a.state.arrows == WorldLayout.GATHER_ARROWS, "E whittles %d arrows" % a.state.arrows)
	a.state.pos = Vector3(0, 0, -4)
	check(WorldLayout.gather_at(a.state.pos) == "" and not net._gather(a), "out in the open: nothing")
	a.state.arrows = Weapons.MAX_AMMO
	a.state.pos = tp + Vector3(0.9, 0, 0)
	net.server_tick += 1000
	check(not net._gather(a) and a.state.arrows == Weapons.MAX_AMMO, "not past the most you can carry")

	# a beaten archer drops a bundle
	a.state.pos = Vector3(40, 0, 40)
	var q := DevCmd.spawn_unit(net, 1, Weapons.BOW, 1, Net.Side.HOSTILE, 1.0, 1, Vector3(40, 0, 44))
	var before := net.items.size()
	q.state.hp = 5
	net._damage(q.id, 50, 1, Vector3(0, 0, 1), 0.0)
	var bundle: Net.Item = null
	for it: Net.Item in net.items.values():
		if it.spawn < 0 and it.count == Net.NPC_AMMO_DROP:
			bundle = it
	check(q.state.dead > 0 and net.items.size() == before + 1 and bundle != null and bundle.kind == Weapons.Item.ARROWS,
		"a beaten archer drops %d arrows" % Net.NPC_AMMO_DROP)

	print("ammo: %s" % ("ALL OK" if bad == 0 else "%d FAILED" % bad))
	quit(1 if bad > 0 else 0)
