## v0.12.6 the dev console (Jacob): ` (the key left of 1) opens and closes it. Type a command and press Enter; the
## host runs it (DevCmd) and the reply shows here. Tab completes the command, a weapon or a name; Up / Down go
## through what you typed before. While it's open the game doesn't take your keys or mouse.
class_name DevConsole
extends CanvasLayer

var net: Net
var panel: PanelContainer
var log_box: RichTextLabel
var edit: LineEdit
var history: Array = []
var hist_i := -1
var was_captured := false


func _init(n: Net) -> void:
	net = n
	layer = 90
	panel = PanelContainer.new()
	panel.anchor_right = 1.0
	panel.anchor_bottom = 0.5
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.08, 0.88)
	sb.border_color = Color("6ad1ff")
	sb.border_width_bottom = 2
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	log_box = RichTextLabel.new()
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.scroll_following = true
	log_box.selection_enabled = true
	log_box.bbcode_enabled = true
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Courier New", "monospace"])
	log_box.add_theme_font_override("normal_font", mono)
	log_box.add_theme_font_size_override("normal_font_size", 14)
	box.add_child(log_box)
	edit = LineEdit.new()
	edit.placeholder_text = "type a command (help lists them all), Enter to run, ` to close"
	edit.add_theme_font_override("font", mono)
	edit.add_theme_font_size_override("font_size", 16)
	edit.text_submitted.connect(_submit)
	edit.gui_input.connect(_edit_input)
	box.add_child(edit)
	visible = false
	net.dev_output.connect(_out)
	_print("[color=#6ad1ff]Dev console.[/color] Try:  [b]max[/b]   level staff max   give all   spawn sword 3 friendly tier 3   size me 2   help")


func toggle() -> void:
	visible = not visible
	if visible:
		was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		edit.text = ""
		edit.grab_focus()
		hist_i = -1
	else:
		edit.release_focus()
		if was_captured:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.physical_keycode == KEY_QUOTELEFT:
		if visible or _can_open():
			toggle()
			get_viewport().set_input_as_handled()
	elif visible and k and k.pressed and k.physical_keycode == KEY_ESCAPE:
		toggle()
		get_viewport().set_input_as_handled()


func _can_open() -> bool:
	return net != null and net.multiplayer.multiplayer_peer != null and net.predicted != null


func _submit(text: String) -> void:
	var t := text.strip_edges()
	edit.text = ""
	if t == "":
		return
	if history.is_empty() or history[-1] != t:
		history.append(t)
	hist_i = -1
	_print("[color=#a0a8b8]> %s[/color]" % t.replace("[", "[lb]"))
	if t.to_lower() in ["clear log", "cls"]:
		log_box.clear()
		return
	net.send_dev(t)


func _out(text: String) -> void:
	_print(text.replace("[", "[lb]"))


func _print(bb: String) -> void:
	log_box.append_text(bb + "\n")


func _edit_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	if k.keycode == KEY_UP and not history.is_empty():
		hist_i = history.size() - 1 if hist_i < 0 else maxi(hist_i - 1, 0)
		edit.text = history[hist_i]
		edit.caret_column = edit.text.length()
		edit.accept_event()
	elif k.keycode == KEY_DOWN and hist_i >= 0:
		hist_i += 1
		edit.text = history[hist_i] if hist_i < history.size() else ""
		if hist_i >= history.size():
			hist_i = -1
		edit.caret_column = edit.text.length()
		edit.accept_event()
	elif k.keycode == KEY_TAB:
		_complete()
		edit.accept_event()


## Tab: finish the word under the caret from the commands (first word), weapons, sides, targets and names.
func _complete() -> void:
	var t := edit.text
	var cut := t.rfind(" ") + 1
	var word := t.substr(cut).to_lower()
	var pool: Array = []
	if cut == 0:
		pool = DevCmd.HELP.keys() + ["maxall"]
	else:
		pool = DevCmd.WEAPON_WORDS.keys() + DevCmd.SIDE_WORDS.keys() + ["all", "me", "players", "units", "magic", "arms",
			"max", "tier", "size", "level", "name", "on", "off", "random", "mix"]
		for id in net.roster.keys():
			var nm := str(net.roster[id].get("name", ""))
			pool.append("\"%s\"" % nm if " " in nm else nm)
	var hits := pool.filter(func(s): return str(s).to_lower().begins_with(word))
	if hits.size() == 1:
		edit.text = t.left(cut) + str(hits[0]) + " "
		edit.caret_column = edit.text.length()
	elif hits.size() > 1:
		_print("[color=#7f8796]%s[/color]" % "   ".join(hits.map(func(s): return str(s))).replace("[", "[lb]"))
