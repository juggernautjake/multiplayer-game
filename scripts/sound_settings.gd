## v0.12.9 (Jacob) the sound settings: volume for Master, Effects (fighting, spells, Thunderhorn, the yard), Music (the
## prize fiesta's music) and Voice (spoken lines such as "my precious"), each 0-100%, plus mute. Kept in
## user://settings.cfg and applied at start. v0.12.13: and the output device (headphones), with a test sound. Every sound plays on one of these buses (Synth.play's `bus`).
class_name SoundSettings

const FILE := "user://settings.cfg"
const BUSES := ["Master", "Effects", "Music", "Voice"]
const NICE := { "Master": "Master volume", "Effects": "Effects (fights, spells, the boss, the yard)",
	"Music": "Music", "Voice": "Voices" }
const DEFAULT := { "Master": 0.8, "Effects": 0.8, "Music": 0.7, "Voice": 1.0 }

static var _ready := false


## Make the buses (once) and apply the saved volumes.
static func setup() -> void:
	if not _ready:
		_ready = true
		for b in BUSES:
			if AudioServer.get_bus_index(b) < 0:
				AudioServer.add_bus()
				var i := AudioServer.bus_count - 1
				AudioServer.set_bus_name(i, b)
				AudioServer.set_bus_send(i, "Master")
	for b in BUSES:
		set_volume(b, volume(b), false)
	set_muted(muted(), false)
	var dev := device()   # v0.12.13: the output picked in the menu (headphones), if it's plugged in
	if dev != "Default" and dev in AudioServer.get_output_device_list():
		AudioServer.output_device = dev


## v0.12.13 (Jacob: "not hearing the sounds... trying to listen through my headphones"): which output the game plays on.
## "Default" follows Windows' default device; with several outputs (speakers, a headset, Voicemeeter's virtual ones)
## that may not be the headphones, so the Sound menu lets you pick one, and it's remembered.
static func device() -> String:
	return str(_cfg().get_value("sound", "device", "Default"))


static func set_device(d: String) -> void:
	AudioServer.output_device = d
	var c := _cfg()
	c.set_value("sound", "device", d)
	c.save(FILE)


static func _cfg() -> ConfigFile:
	var c := ConfigFile.new()
	c.load(FILE)
	return c


## 0..1
static func volume(bus: String) -> float:
	return clampf(float(_cfg().get_value("sound", bus, DEFAULT.get(bus, 1.0))), 0.0, 1.0)


static func set_volume(bus: String, v: float, save := true) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.001 or (bus == "Master" and muted()))
	if save:
		var c := _cfg()
		c.set_value("sound", bus, v)
		c.save(FILE)


static func muted() -> bool:
	return bool(_cfg().get_value("sound", "muted", false))


static func set_muted(m: bool, save := true) -> void:
	AudioServer.set_bus_mute(0, m or volume("Master") <= 0.001)
	if save:
		var c := _cfg()
		c.set_value("sound", "muted", m)
		c.save(FILE)


## A panel of sliders (and a mute box) for a menu; `back` runs when Back is pressed.
static func panel(back: Callable) -> PanelContainer:
	setup()
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(420, 0)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	p.add_child(box)
	var title := Label.new()
	title.text = "Sound"
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	for b in BUSES:
		var l := Label.new()
		box.add_child(l)
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.01
		s.value = volume(b)
		var nm: String = NICE[b]
		l.text = "%s   %d%%" % [nm, int(round(s.value * 100.0))]
		s.value_changed.connect(func(v: float):
			set_volume(b, v)
			l.text = "%s   %d%%" % [nm, int(round(v * 100.0))])
		box.add_child(s)
	var dl := Label.new()
	dl.text = "Play sound on"
	box.add_child(dl)
	var pick := OptionButton.new()
	var devs := AudioServer.get_output_device_list()
	var cur := AudioServer.output_device
	for i in devs.size():
		pick.add_item("Windows default output" if devs[i] == "Default" else devs[i])
		pick.set_item_metadata(i, devs[i])
		if devs[i] == cur:
			pick.select(i)
	pick.item_selected.connect(func(i: int):
		set_device(str(pick.get_item_metadata(i)))
		Synth.play(pick, Synth.fx("chirp"), -4.0))
	box.add_child(pick)
	var test := Button.new()
	test.text = "Test sound"
	test.pressed.connect(func(): Synth.play(test, Synth.fx("hoof"), 0.0))
	box.add_child(test)
	var mute := CheckBox.new()
	mute.text = "Mute everything"
	mute.button_pressed = muted()
	mute.toggled.connect(func(on: bool): set_muted(on))
	box.add_child(mute)
	var bk := Button.new()
	bk.text = "Back"
	bk.pressed.connect(back)
	box.add_child(bk)
	return p
