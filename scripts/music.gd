## v0.12.16 (Jacob: "game music that is appropriate for what is happening... different changes in the music for the
## cut scene and for the different stages of the boss... other kinds of music too, and level up noises too").
## The pieces are composed and synthesised by tools/make_music.py (assets/music/*.ogg). This decides what plays, each
## frame, from what is happening on this player's screen, and crossfades between them on the Music volume:
##  - the main menu: menu.ogg;
##  - out in the world: explore.ogg, calm;
##  - a fight (you hit someone or were hit in the last COMBAT_HOLD s, or a hostile fighter is within COMBAT_NEAR m):
##    combat.ogg;
##  - Thunderhorn (from the moment he appears until he falls): his theme, eight layers that always play together in
##    step and are faded in and out with the fight (`boss_layers`):
##        arriving                       pad + timpani
##        the fight                      + bass, drums and the brass theme
##        after the Duel Stone's corruption   + the corrupt choir and organ
##        enraged (half health)          + double-time drums and spiccato strings
##        the storm (his last quarter)   + tremolo strings, thunder and bells: everything
##        dazed                          the drums and the brass drop out: a breath while he's down
##    the corruption cutscene has its own score (cutscene.ogg) timed to the film; the theme fades under it and comes
##    back with the corruption layer as the minions draw their weapons;
##  - cues over the top (the music ducks under them): your weapon levelling up (levelup.ogg), a spell's mastery
##    (mastery.ogg), Thunderhorn falling (boss_fall.ogg), everyone down (defeat.ogg). The prize screen plays its own.
class_name Music
extends Node

const DIR := "res://assets/music/"
## Levels (dB) set from each piece's measured loudness (ffmpeg ebur128) so they sit together: exploring and the menu
## about -21 LUFS, a fight -19, the boss -20.6 (all eight layers -19.4), the cutscene -18, cues -16 to -18.
const LOOPS := { "menu": -9.0, "explore": -12.0, "combat": -10.0 }   # piece -> its level (dB)
const STEMS := ["pad", "timp", "bass", "drums", "lead", "corrupt", "fast", "storm"]
const STEM_DB := 0.0
const CUES := { "levelup": -9.0, "mastery": -9.0, "boss_fall": -11.0, "defeat": -4.0 }
const CUT_DB := -10.0
const FADE := 2.0          # seconds to crossfade between pieces
const LAYER_FADE := 1.6    # seconds for a boss layer to fade in or out
const COMBAT_HOLD := 9.0   # seconds a fight's music stays after the last blow
const COMBAT_NEAR := 22.0  # metres: a hostile fighter this close means a fight

var net: Net
var main: Node
var loops := {}     # name -> AudioStreamPlayer
var stems := {}     # layer -> AudioStreamPlayer
var gain := {}      # player -> 0..1 (faded)
var cut: AudioStreamPlayer
var mode := ""      # what's playing: "menu", "explore", "combat", "boss" or "" (nothing: the prize screen)
var layers: Array = []   # the boss layers wanted now
var _last_blow := -100000
var _duck := 0.0         # seconds left of ducking under a cue
var _boss_was := -1
var _cut_on := false
var _log := OS.get_cmdline_user_args().has("--musiclog")


func setup(n: Net, m: Node) -> void:
	net = n
	main = m
	for k in LOOPS.keys():
		loops[k] = _player(k, true)
	for k in STEMS:
		stems[k] = _player("boss_" + k, true)
	cut = _player("cutscene", false)
	net.hit.connect(_on_hit)
	net.magic_fx.connect(_on_fx)
	net.boss_result.connect(_on_result)


func _player(file: String, loop: bool) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var path := DIR + file + ".ogg"
	if ResourceLoader.exists(path):
		var st := load(path) as AudioStreamOggVorbis
		if st:
			st = st.duplicate()
			st.loop = loop
			p.stream = st
	p.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	p.volume_db = -80.0
	add_child(p)
	gain[p] = 0.0
	return p


# ================================================================ what's happening
func _on_hit(target: int, _amount: int, _pos: Vector3, _dir: Vector3, _killed: bool, attacker: int) -> void:
	if target == net.my_id or attacker == net.my_id:
		_last_blow = Time.get_ticks_msec()


func _on_fx(kind: String, a: Array) -> void:
	if kind != "level_up" and kind != "mastery_up":
		return
	if a.is_empty() or typeof(a[0]) != TYPE_INT or int(a[0]) != net.my_id:
		return
	if kind == "level_up":
		cue("levelup")
	elif kind == "mastery_up":
		cue("mastery")


func _on_result(kind: String) -> void:
	if kind == "defeat":
		cue("defeat")


## Play a cue over the music (which ducks under it for a moment).
func cue(name: String) -> void:
	var path := DIR + name + ".ogg"
	if not ResourceLoader.exists(path):
		return
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	p.volume_db = float(CUES.get(name, -4.0))
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
	_duck = 2.2
	if _log:
		print("[music] cue ", name)


func _want_mode() -> String:
	var menu = main.get("menu")
	if menu != null and (menu as Control).visible:
		return "menu"
	var prize = main.get("prize")
	if prize != null and bool(prize.get("visible")):
		return ""
	var bv = main.get("boss_view")
	if bv != null and bv.alive:
		return "boss"
	if Time.get_ticks_msec() - _last_blow < COMBAT_HOLD * 1000.0 or _foe_near():
		return "combat"
	return "explore"


## A hostile fighter (a challenger, a minion, a spawned enemy) on its feet near you.
func _foe_near() -> bool:
	var avs = main.get("avatars")
	if avs == null or not (avs as Dictionary).has(net.my_id):
		return false
	var me: Vector3 = (avs[net.my_id] as Node3D).position
	for id in (avs as Dictionary).keys():
		var r: Dictionary = net.roster.get(id, {})
		if int(r.get("kind", 0)) == 0 or int(r.get("side", 1)) != Net.Side.HOSTILE or bool(r.get("charmed", false)):
			continue
		var av: Node3D = avs[id]
		var st = av.get("state")
		if st != null and (st as Sim.PlayerState).dead == 0 and av.position.distance_to(me) < COMBAT_NEAR:
			return true
	return false


## Which of his layers play now (from the boss state BossView has).
func boss_layers(bv) -> Array:
	var st: int = bv.state
	var fl: int = bv.flags
	if st == Boss.S.CUTSCENE or st == Boss.S.DEATH:
		return []
	if st == Boss.S.ENTER or st < 0:   # (or not known yet)
		return ["pad", "timp"]
	var out := ["pad", "timp", "bass", "drums", "lead"]
	if fl & 128:
		out.append("corrupt")
	if fl & 8 or fl & 32:
		out.append("fast")
	if fl & 32:
		out.append("storm")
	if fl & 64:   # dazed: the drums and the brass drop out
		out = out.filter(func(l): return l not in ["drums", "lead", "fast"])
	return out


# ================================================================ every frame
func update(delta: float) -> void:
	var want := _want_mode()
	if want != mode:
		if _log:
			print("[music] %s -> %s" % [mode, want])
		mode = want
		if mode == "boss":   # start every layer together (silent), so they stay in step
			for k in STEMS:
				var p: AudioStreamPlayer = stems[k]
				if p.stream:
					p.play()
	var bv = main.get("boss_view")
	# the cutscene's score
	var cut_now: bool = mode == "boss" and bv != null and bv.state == Boss.S.CUTSCENE
	if cut_now and not _cut_on and cut.stream:
		cut.play(clampf(float(bv.state_t), 0.0, 13.0))
		gain[cut] = 1.0
		if _log:
			print("[music] cutscene score from %.2f s" % float(bv.state_t))
	_cut_on = cut_now
	if mode == "boss" and bv != null:
		var l := boss_layers(bv)
		if l != layers and _log:
			print("[music] boss layers ", l)
		layers = l
		if bv.state == Boss.S.DEATH and _boss_was != Boss.S.DEATH:
			cue("boss_fall")
		_boss_was = bv.state
	else:
		_boss_was = -1
		layers = []
	_duck = maxf(_duck - delta, 0.0)
	var duck_db := -8.0 if _duck > 0.0 else 0.0
	for k in LOOPS.keys():
		_fade(loops[k], 1.0 if mode == k else 0.0, FADE, float(LOOPS[k]) + duck_db, delta)
	for k in STEMS:
		var on: bool = mode == "boss" and k in layers
		_fade(stems[k], 1.0 if on else 0.0, 0.6 if cut_now else LAYER_FADE, STEM_DB + duck_db, delta, mode == "boss")
	if cut.playing:
		cut.volume_db = CUT_DB + duck_db if mode == "boss" else -80.0
		if mode != "boss":
			cut.stop()


## Fade a player toward `to` (0..1) over `secs`; start it when it's heard, stop it when it's silent (unless `keep`:
## the boss layers keep running silently, so they stay in step).
func _fade(p: AudioStreamPlayer, to: float, secs: float, db: float, delta: float, keep := false) -> void:
	if p.stream == null:
		return
	var g: float = move_toward(float(gain[p]), to, delta / maxf(secs, 0.01))
	gain[p] = g
	if g > 0.0 and not p.playing:
		p.play()
	elif g <= 0.0 and p.playing and not keep:
		p.stop()
	p.volume_db = db + linear_to_db(maxf(g, 0.0001)) if g > 0.0 else -80.0
