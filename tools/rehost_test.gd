extends SceneTree
## Leaving and starting again in the same session (v0.8.1). Hosts on a port, leaves, hosts on the same port again; a
## guest joins, leaves and joins again; then host -> leave -> join -> leave -> host. Before 0.8.1, leaving kept the
## old connection open, so hosting again failed with "port 7777 is being used".
##   Godot --headless --path . --script tools/rehost_test.gd
## Uses UDP 7777 if it's free (another copy of the game hosting there is fine: it falls back to 7797).
## The host and the guest each run in their own branch of the tree with their own multiplayer (like two programs).

var bad := 0
var port := 7777
var step := 0
var wait := 0
var host_net: Net
var guest_net: Net
var host_root: Node
var guest_root: Node


func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		bad += 1


func _initialize() -> void:
	var probe := PacketPeerUDP.new()
	if probe.bind(port) != OK:
		print("UDP %d is in use by another program: testing on 7797 instead" % port)
		port = 7797
	probe.close()
	host_root = _branch("H")
	guest_root = _branch("G")


## A branch of the tree with its own MultiplayerAPI, so a host and a guest can live in one process.
func _branch(nm: String) -> Node:
	var n := Node.new()
	n.name = nm
	root.add_child(n)
	set_multiplayer(SceneMultiplayer.new(), NodePath("/root/" + nm))
	return n


func _new_net(parent: Node) -> Net:
	for c in parent.get_children():
		c.free()   # the old Net leaves the tree: it must let go of its port
	var n := Net.new()
	n.name = "Net"
	parent.add_child(n)
	return n


func _process(_delta: float) -> bool:
	wait += 1
	match step:
		0:
			host_net = _new_net(host_root)
			check(host_net.host(port, "Host") == OK, "host on UDP %d" % port)
			host_net.free()
			host_net = _new_net(host_root)
			check(host_net.host(port, "Host") == OK, "leave, then host on UDP %d again" % port)
			_next()
		1:
			guest_net = _new_net(guest_root)
			check(guest_net.join("127.0.0.1", port, "Guest") == OK, "a guest starts joining")
			_next()
		2:
			if host_net.players.size() == 2 and guest_net.my_id != 0:
				check(true, "the guest is in")
				guest_net.shutdown()
				_next()
			elif wait > 600:
				check(false, "the guest is in")
				return true
		3:
			if host_net.players.size() == 1:
				check(true, "the guest leaves: the host sees them go")
				guest_net = _new_net(guest_root)
				guest_net.join("127.0.0.1", port, "Guest")
				_next()
			elif wait > 600:
				check(false, "the guest leaves: the host sees them go")
				return true
		4:
			if host_net.players.size() == 2 and guest_net.my_id != 0:
				check(true, "the guest joins again")
				_next()
			elif wait > 600:
				check(false, "the guest joins again")
				return true
		5:   # host -> leave -> join (as a guest, elsewhere) -> leave -> host
			guest_net.shutdown()
			host_net.shutdown()
			var other := 7798
			var helper := _new_net(guest_root)
			check(helper.host(other, "Other") == OK, "another game to join on %d" % other)
			host_net = _new_net(host_root)
			check(host_net.join("127.0.0.1", other, "Was host") == OK, "the old host joins someone else's game")
			_next()
		6:
			var helper: Net = guest_root.get_node("Net")
			if helper.players.size() == 2:
				check(true, "and gets in")
				host_net.shutdown()
				host_net = _new_net(host_root)
				check(host_net.host(port, "Host") == OK, "leaves, and hosts on UDP %d once more" % port)
				helper.shutdown()
				_next()
			elif wait > 600:
				check(false, "and gets in")
				return true
		7:
			print("%d failed" % bad)
			quit(bad)
			return true
	return false


func _next() -> void:
	step += 1
	wait = 0
