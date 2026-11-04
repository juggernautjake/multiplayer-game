## Runs the server ecology for simulated minutes with no players and with a player standing by a tree,
## then hits a fruit tree, and prints how many of each event happened. Checks that fruit falls, worms move in
## and birds come for them.   Godot --headless --path . -s tools/eco_test.gd
extends SceneTree

var counts := {}
var phases := {}


func _init() -> void:
	var eco := Ecology.new()
	eco.event.connect(func(kind: String, args: Array) -> void: _count(kind, args))
	var minutes := 20
	var far: Array = []   # no players nearby
	for now in range(1, minutes * 60 * Config.TICK_RATE):
		eco.tick(now, far)
		if now == 30 * Config.TICK_RATE:
			for tr in eco.trees:
				if tr.kind != "oak":
					eco.hit_tree(tr.i, 8, now, Vector3(1, 0, 0))
					break
	print("events: ", counts)
	print("worm/bird phases: ", phases)
	var ok: bool = counts.get("fruit_fall", 0) > 0 and counts.get("worm", 0) > 0 and counts.get("bird", 0) > 0 and counts.get("tree_hit", 0) > 0
	print("ECO ", "OK" if ok else "FAIL")
	quit(0 if ok else 1)


func _count(kind: String, args: Array) -> void:
	counts[kind] = int(counts.get(kind, 0)) + 1
	if kind == "worm" or kind == "bird":
		var k: String = kind + ":" + str(args[3])
		phases[k] = int(phases.get(k, 0)) + 1
