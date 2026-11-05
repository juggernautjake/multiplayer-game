## Updates from GitHub: each release carries game.pck (all the game's scripts, scenes and art, under 1 MB); its notes end
## with a line "godot: 4.7.2" (the Godot it was built with). At start the game asks GitHub for the latest release; if it is
## newer, it downloads game.pck into the updates folder beside the game (boot.gd loads it on the next start) and offers
## a restart. A release made with a different Godot version can't be patched in: then it points to the download page.
class_name Updater
extends Node

signal changed(text: String, can_restart: bool, page_url: String)

const REPO := "juggernautjake/multiplayer-game"
const API := "https://api.github.com/repos/%s/releases/latest" % REPO
const PAGE := "https://github.com/%s/releases/latest" % REPO

var current := ""
var _http: HTTPRequest
var _pck_url := ""
var _new_version := ""


static func update_dir() -> String:
	# beside the game (MultiplayerGame/updates) when that folder can be written, else the per-user data folder
	var d := OS.get_executable_path().get_base_dir().path_join("updates")
	if not OS.has_feature("template"):
		return "user://updates"
	if DirAccess.make_dir_recursive_absolute(d) == OK:
		var probe := FileAccess.open(d.path_join(".probe"), FileAccess.WRITE)
		if probe:
			probe.close()
			DirAccess.remove_absolute(d.path_join(".probe"))
			return d
	return "user://updates"


static func read_version(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path).strip_edges()


## The version actually running: the downloaded update if boot.gd loaded it, else the built-in one.
static func running_version() -> String:
	var got := read_version(update_dir().path_join("version.txt"))
	var have := read_version("res://version.txt")
	return got if OS.has_feature("template") and newer(got, have) else have


static func newer(a: String, b: String) -> bool:
	if a == "":
		return false
	if b == "":
		return true
	var pa := a.trim_prefix("v").split(".")
	var pb := b.trim_prefix("v").split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return x > y
	return false


func _ready() -> void:
	current = running_version()
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	add_child(_http)
	_http.request_completed.connect(_on_release)
	check()


func check() -> void:
	if not OS.has_feature("template"):
		changed.emit("v%s (running from the editor: updates come from git)" % current, false, "")
		return
	changed.emit("v%s · checking for updates…" % current, false, "")
	_http.request(API, ["User-Agent: MultiplayerGame", "Accept: application/vnd.github+json"])


func _on_release(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		changed.emit("v%s · couldn't check for updates (offline?)" % current, false, "")
		return
	var rel = JSON.parse_string(body.get_string_from_utf8())
	if typeof(rel) != TYPE_DICTIONARY:
		return
	var latest := str(rel.get("tag_name", "")).trim_prefix("v")
	if not newer(latest, current):
		changed.emit("v%s · up to date" % current, false, "")
		return
	var godot := ""
	for a in rel.get("assets", []):
		if str(a.get("name", "")) == "game.pck":
			_pck_url = str(a.get("browser_download_url", ""))
	var body_text := str(rel.get("body", ""))
	var m := RegEx.create_from_string("godot[: ]+([0-9.]+)").search(body_text.to_lower())
	if m:
		godot = m.get_string(1)
	var vi := Engine.get_version_info()
	var mine := "%d.%d.%d" % [vi.major, vi.minor, vi.patch]
	if _pck_url == "" or (godot != "" and godot != mine):
		changed.emit("v%s is out (you have v%s): it needs a full download." % [latest, current], false, PAGE)
		return
	_new_version = latest
	changed.emit("Downloading v%s…" % latest, false, "")
	var dir := update_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var dl := HTTPRequest.new()
	dl.download_file = dir.path_join("game.pck.part")
	dl.timeout = 300.0
	add_child(dl)
	dl.request_completed.connect(func(r, c, _h2, _b):
		dl.queue_free()
		if r != HTTPRequest.RESULT_SUCCESS or c != 200:
			changed.emit("v%s · the update download failed; it will try again next start" % current, false, PAGE)
			return
		DirAccess.remove_absolute(dir.path_join("game.pck"))
		DirAccess.rename_absolute(dir.path_join("game.pck.part"), dir.path_join("game.pck"))
		var f := FileAccess.open(dir.path_join("version.txt"), FileAccess.WRITE)
		f.store_string(_new_version)
		f.close()
		changed.emit("v%s downloaded. Restart to play it." % _new_version, true, ""))
	dl.request(_pck_url, ["User-Agent: MultiplayerGame"])


static func restart() -> void:
	OS.create_process(OS.get_executable_path(), OS.get_cmdline_args())
	Engine.get_main_loop().quit()
