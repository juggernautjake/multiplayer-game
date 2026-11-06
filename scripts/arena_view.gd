## The Duel Stone and the Storm Altar on screen (v0.10.0), and what they say to you.
##
## The Duel Stone: a rough standing stone carved with runes. They glow gold while it summons archers, slingers,
## swordsmen and clubbers; once you've levelled a staff or wand to 2 they turn violet (with motes of light rising off
## it) and it summons wizards too ("The Duel Stone now summons wizards!").
## The Storm Altar: a ring of dark stone round a giant round button, out past the far end of the field. It lies flat
## and dull until you reach level 3; then it rises out of the ground with a rumble, its rim crackling and a small
## storm cloud turning over it ("The Storm Altar has risen!"). Jump on it to summon Thunderhorn.
## The server decides everything (Net._stone_interact, Net._server_altar); this only draws it and the prompts.
class_name ArenaView
extends Node3D

var net: Net
var main: Node3D
var rune_mats: Array = []
var stone_light: OmniLight3D
var button: Node3D
var button_mat: StandardMaterial3D
var press := 0.0
var rim_mat: StandardMaterial3D
var altar_light: OmniLight3D
var swirl: Node3D
var wizards := false        # what the stone shows now
var risen := false
var rise := 0.0             # 0 sunk, 1 up
var lvl_seen := -1
var t := 0.0
var _mote_t := 0.0


func setup(n: Net, m: Node3D) -> void:
	net = n
	main = m
	_build_stone()
	_build_altar()


static func _m(c: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	mi.rotation = rot
	parent.add_child(mi)
	return mi


# ================================================================ the Duel Stone
func _build_stone() -> void:
	var c := WorldLayout.DUEL_C
	var root := Node3D.new()
	root.position = Vector3(c.x, 0, c.y)
	add_child(root)
	var stone := _m(Color("6e6a73"))
	var hx := WorldLayout.DUEL_HALF.x
	var hz := WorldLayout.DUEL_HALF.y
	var h := WorldLayout.DUEL_H
	# the stone: a tapering slab, a little crooked, with a rough cap and a plinth of flat rocks round its foot
	_box(root, Vector3(hx * 2.0, h * 0.7, hz * 2.0), Vector3(0, h * 0.35, 0), stone)
	_box(root, Vector3(hx * 1.7, h * 0.32, hz * 1.75), Vector3(0.02, h * 0.82, 0), stone, Vector3(0, 0, 0.04))
	_box(root, Vector3(hx * 1.2, 0.22, hz * 1.4), Vector3(-0.03, h + 0.02, 0), _m(Color("5d5a62")), Vector3(0.05, 0, -0.08))
	for i in 7:
		var a := i * TAU / 7.0 + 0.3
		_box(root, Vector3(0.7, 0.14, 0.5), Vector3(cos(a) * 1.05, 0.07, sin(a) * 0.9), _m(Color("5a5750")), Vector3(0, a, 0.03 * i))
	# the runes: glowing glyph strokes on both broad faces
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for face in [-1.0, 1.0]:
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.albedo_color = Color("ffc65a")
		rune_mats.append(rm)
		for row in 4:
			for col in 2:
				var at := Vector3((col - 0.5) * 0.5, 0.35 + row * 0.33, face * (hz + 0.005))
				for s in 3:   # each glyph: three short strokes at angles
					var ang := rng.randf_range(-1.2, 1.2)
					var off := Vector3(rng.randf_range(-0.07, 0.07), rng.randf_range(-0.08, 0.08), 0)
					_box(root, Vector3(0.035, rng.randf_range(0.1, 0.2), 0.01), at + off, rm, Vector3(0, 0, ang))
	stone_light = OmniLight3D.new()
	stone_light.light_color = Color("ffc65a")
	stone_light.light_energy = 0.8
	stone_light.omni_range = 4.0
	stone_light.position = Vector3(0, 1.0, 0)
	root.add_child(stone_light)


# ================================================================ the Storm Altar
func _build_altar() -> void:
	var c := WorldLayout.ALTAR_C
	var root := Node3D.new()
	root.position = Vector3(c.x, 0, c.y)
	add_child(root)
	var dark := _m(Color("3c3c48"))
	# a low ring of stone blocks round the button, with four squat pillars
	for i in 16:
		var a := i * TAU / 16.0
		_box(root, Vector3(1.25, 0.3, 0.6), Vector3(cos(a) * 3.3, 0.15, sin(a) * 3.3), dark, Vector3(0, -a + PI / 2.0, 0))
	for i in 4:
		var a := i * TAU / 4.0 + PI / 4.0
		_box(root, Vector3(0.6, 1.4, 0.6), Vector3(cos(a) * 3.9, 0.7, sin(a) * 3.9), _m(Color("4a4a58")))
		var cap := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.44
		cap.mesh = sm
		cap.material_override = MagicFx._glow_mat(Color("8fb4ff"), 2.0)
		cap.position = Vector3(cos(a) * 3.9, 1.6, sin(a) * 3.9)
		root.add_child(cap)
	# the button: a wide drum with a lightning sigil on top, sunk into the ground until level 3
	button = Node3D.new()
	root.add_child(button)
	var drum := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = Net.ALTAR_R
	cm.bottom_radius = cm.top_radius + 0.1
	cm.height = 0.6
	cm.radial_segments = 40
	drum.mesh = cm
	button_mat = _m(Color("5a6078"), 0.6)
	button_mat.emission_enabled = true
	button_mat.emission = Color("3a5aa0")
	button_mat.emission_energy_multiplier = 0.0
	drum.material_override = button_mat
	drum.position.y = 0.3
	button.add_child(drum)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = cm.top_radius - 0.12
	tm.outer_radius = cm.top_radius + 0.05
	tm.rings = 40
	rim.mesh = tm
	rim_mat = MagicFx._glow_mat(Color("8fb4ff"), 0.0)
	rim.material_override = rim_mat
	rim.position.y = 0.6
	button.add_child(rim)
	# the sigil: a zig-zag bolt inlaid on the top
	var sig := MagicFx._glow_mat(Color("cfe4ff"), 0.0)
	var pts := [Vector3(-0.5, 0, -1.4), Vector3(0.3, 0, -0.2), Vector3(-0.3, 0, 0.1), Vector3(0.5, 0, 1.4)]
	for i in 3:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var seg := _box(button, Vector3(0.22, 0.03, a.distance_to(b) + 0.1), (a + b) / 2.0 + Vector3(0, 0.61, 0), sig)
		seg.rotation.y = atan2(b.x - a.x, b.z - a.z)
	rune_mats.append(sig)   # (only to keep a reference; coloured below)
	button.set_meta("sigil", sig)
	altar_light = OmniLight3D.new()
	altar_light.light_color = Color("8fb4ff")
	altar_light.light_energy = 0.0
	altar_light.omni_range = 9.0
	altar_light.position = Vector3(0, 2.0, 0)
	root.add_child(altar_light)
	# a small storm turning over it once it has risen
	swirl = Node3D.new()
	swirl.position = Vector3(0, 9.0, 0)
	swirl.visible = false
	root.add_child(swirl)
	for i in 10:
		var p := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var r := randf_range(0.9, 1.6)
		sm.radius = r
		sm.height = r * 1.1
		p.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.2, 0.2, 0.28, 0.85)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.emission_enabled = true
		m.emission = Color("4a5a9a")
		m.emission_energy_multiplier = 0.3
		p.material_override = m
		var a := i * TAU / 10.0
		p.position = Vector3(cos(a) * 2.2, randf_range(-0.4, 0.4), sin(a) * 2.2)
		swirl.add_child(p)
	button.position.y = -0.55


# ================================================================ every frame
func _process(delta: float) -> void:
	t += delta
	var st := net.predicted
	var lvl := 0
	if st != null:
		lvl = maxi(st.staff_lvl, st.wand_lvl)
	# the stone's change after the first level-up
	var want_wiz := lvl >= 2
	if want_wiz != wizards:
		wizards = want_wiz
		if wizards and lvl_seen >= 0 and lvl_seen < 2 and main.has_method("toast"):
			main.toast("The Duel Stone now summons wizards!")
			var at := Vector3(WorldLayout.DUEL_C.x, 1.0, WorldLayout.DUEL_C.y)
			Fx.burst(main, at, Vector3.UP, Color("b46bff"), 40, 5.0, 0.05)
	var rc := Color("b46bff") if wizards else Color("ffc65a")
	var pulse := 0.75 + 0.25 * sin(t * (3.0 if wizards else 1.6))
	for i in 2:
		(rune_mats[i] as StandardMaterial3D).albedo_color = rc * pulse + Color(0, 0, 0, 1)
	stone_light.light_color = rc
	stone_light.light_energy = (1.4 if wizards else 0.7) * pulse
	if wizards:
		_mote_t -= delta
		if _mote_t <= 0.0:
			_mote_t = 0.25
			var c := WorldLayout.DUEL_C
			Fx.burst(main, Vector3(c.x + randf_range(-0.5, 0.5), 1.8, c.y + randf_range(-0.4, 0.4)), Vector3.UP, rc, 2, 1.2, 0.03)
	# the altar rising at level 3
	var want_up := lvl >= 3
	if want_up and not risen:
		risen = true
		if lvl_seen >= 0 and lvl_seen < 3 and main.has_method("toast"):
			main.toast("The Storm Altar has risen! Jump on it to face Thunderhorn")
			var at := Vector3(WorldLayout.ALTAR_C.x, 0, WorldLayout.ALTAR_C.y)
			MotionFx.land(main, at, 2.0)
			Fx.burst(main, at + Vector3(0, 0.6, 0), Vector3.UP, Color("8fb4ff"), 50, 6.0, 0.05)
	elif not want_up:
		risen = false
	if lvl_seen != lvl:
		lvl_seen = lvl
	rise = move_toward(rise, 1.0 if risen else 0.0, delta / 2.5)
	var boss_up := _boss_up()
	# v0.12.0: pressed (the whole fight) it sinks with a clunk and stays down, then slowly rises again after
	var want_press := 1.0 if WorldLayout.altar_pressed else 0.0
	if want_press > 0.5 and press < 0.5 and rise > 0.5:
		var at := Vector3(WorldLayout.ALTAR_C.x, 0.4, WorldLayout.ALTAR_C.y)
		Synth.play(self, Synth.fx("slam"), 2.0)
		Synth.play(self, Synth.fx("hoof"), 4.0)
		MotionFx.land(get_parent(), at, 2.0)
		Fx.burst(get_parent(), at, Vector3.UP, Color("8fb4ff"), 30, 5.0, 0.06)
		altar_light.light_energy = 12.0
	press = move_toward(press, want_press, delta / (0.25 if want_press > 0.5 else 3.0))
	button.position.y = lerpf(-0.55, 0.0, rise) - (WorldLayout.ALTAR_UP - WorldLayout.ALTAR_DOWN) * press * rise + (randf_range(-0.02, 0.02) if rise > 0.0 and rise < 1.0 else 0.0)
	var glow := rise * (0.6 + 0.4 * sin(t * 4.0))
	button_mat.emission_energy_multiplier = glow * 0.8
	rim_mat.albedo_color = Color("8fb4ff")
	(rim_mat as StandardMaterial3D).emission_energy_multiplier = glow * 4.0
	(button.get_meta("sigil") as StandardMaterial3D).emission_energy_multiplier = glow * 6.0
	altar_light.light_energy = glow * 2.5 * (0.6 + randf() * 0.4 if randf() < 0.1 else 1.0)
	swirl.visible = rise > 0.5 and not boss_up
	if swirl.visible:
		swirl.rotate_y(delta * 0.6)
		if randf() < delta * 0.5:
			var a := Vector3(WorldLayout.ALTAR_C.x, 8.5, WorldLayout.ALTAR_C.y)
			var b := Vector3(WorldLayout.ALTAR_C.x + randf_range(-1, 1), 0.6, WorldLayout.ALTAR_C.y + randf_range(-1, 1))
			var mfx: MagicFx = main.magic_fx
			var arc := mfx._ribbons([[MagicFx._fractal(a, b, 4, 0.3), 0.05]], Color("cfe4ff"), 6.0)
			var tw := arc.create_tween()
			tw.tween_property(arc.material_override, "albedo_color:a", 0.0, 0.15)
			tw.tween_callback(arc.queue_free)


## What the prompt over the stone or altar says when you're close: [text, where] or [] if nothing.
func prompt_for(me: Vector3) -> Array:
	var st := net.predicted
	var lvl := maxi(st.staff_lvl, st.wand_lvl) if st != null else 0
	var c := WorldLayout.DUEL_C
	if Vector2(me.x - c.x, me.z - c.y).length() < Net.DUEL_REACH:
		var who := "bow, slingshot, sword, club or wizard" if lvl >= 2 else "bow, slingshot, sword or club"
		return ["E  summon a challenger (%s)" % who, Vector3(c.x, WorldLayout.DUEL_H + 0.6, c.y)]
	var a := WorldLayout.ALTAR_C
	if Vector2(me.x - a.x, me.z - a.y).length() < 5.0 and not _boss_up():
		if lvl >= 3:
			return ["SPACE  jump on the altar to summon Thunderhorn", Vector3(a.x, 2.2, a.y)]
		return ["The Storm Altar wakes at level 3 (you're level %d)" % maxi(lvl, 1), Vector3(a.x, 2.2, a.y)]
	return []


func _boss_up() -> bool:
	var bv = main.get("boss_view")
	return net.boss != null or (bv != null and bv.alive)