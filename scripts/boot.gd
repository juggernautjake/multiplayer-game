## First scene: if an update has been downloaded (a newer game.pck in the updates folder next to the game), load it over
## the built-in files, then start the game. Uses no other script before the pack is loaded, so every script, scene and
## asset (the updater included) comes from the newest version.
extends Node

func _ready() -> void:
	if OS.has_feature("template"):
		var dir := OS.get_executable_path().get_base_dir().path_join("updates")
		if not FileAccess.file_exists(dir.path_join("game.pck")):
			dir = "user://updates"
		var have := _read("res://version.txt")
		var got := _read(dir.path_join("version.txt"))
		if _newer(got, have) and FileAccess.file_exists(dir.path_join("game.pck")):
			if ProjectSettings.load_resource_pack(dir.path_join("game.pck"), true):
				print("Running update v%s (built in: v%s)" % [got, have])
			else:
				push_warning("Could not load the downloaded update; running v%s" % have)
	get_tree().change_scene_to_file.call_deferred("res://main.tscn")


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path).strip_edges() if FileAccess.file_exists(path) else ""


func _newer(a: String, b: String) -> bool:
	if a == "":
		return false
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return x > y
	return false
