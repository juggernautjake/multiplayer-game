## 3D models of the weapons and ammo, built in code: used for items lying in the world and for the 3D figure's hands.
## Each is built standing along +Y with its grip (where a hand holds it) at the origin.
class_name WeaponModels

const STEEL := Color("c9d2dd")
const STEEL_DARK := Color("8a96a6")
const GOLD := Color("e0b23c")
const WOOD := Color("9a6634")
const WOOD_DARK := Color("6b4426")
const LEATHER := Color("4f2e1e")
const STRING := Color("ece4cc")
const BAND := Color("b83434")
const STONE := Color("8d8d95")


## count (v0.12.7): ammo looks like what it is: 1-2 arrows or stones lie loose, 3-6 a small bundle / a few stones, more
## a quiver / a pile (it used to be a full quiver or pile even for one spent arrow).
static func make(kind: int, count := 99) -> Node3D:
	match kind:
		Weapons.Item.CLUB: return club()
		Weapons.Item.SWORD: return sword()
		Weapons.Item.BOW: return bow()
		Weapons.Item.SLING: return sling()
		Weapons.Item.ARROWS: return quiver() if count >= 7 else loose_arrows(count)
		Weapons.Item.STAFF: return staff()
		Weapons.Item.WAND: return wand()
		_: return rocks() if count >= 7 else loose_stones(count)


## v0.12.7: n arrows lying on the ground, crossed a little (a bundle tied with a band from 3).
static func loose_arrows(n: int) -> Node3D:
	var root := Node3D.new()
	n = clampi(n, 1, 6)
	for i in n:
		var a := Node3D.new()
		root.add_child(a)
		_box(a, Vector3(0.016, 0.016, 0.72), Vector3.ZERO, WOOD, 0.8)                     # shaft along Z
		var head := _box(a, Vector3(0.035, 0.012, 0.07), Vector3(0, 0, -0.38), STEEL, 0.3, 0.7)
		head.rotation.y = PI / 4.0
		_box(a, Vector3(0.05, 0.004, 0.1), Vector3(0, 0.006, 0.32), BAND, 0.8)            # fletching
		a.position = Vector3((i - (n - 1) / 2.0) * 0.03, 0.012 + 0.012 * (i % 2), 0)
		a.rotation.y = (i - (n - 1) / 2.0) * 0.12 + 0.4
	if n >= 3:
		_cyl(root, 0.045, 0.04, Vector3(0, 0.02, 0.05), LEATHER).rotation.x = PI / 2.0
	return root


## v0.12.7: n stones lying loose.
static func loose_stones(n: int) -> Node3D:
	var root := Node3D.new()
	n = clampi(n, 1, 6)
	var spots := [Vector3(0, 0.05, 0), Vector3(0.1, 0.045, 0.04), Vector3(-0.08, 0.045, 0.07), Vector3(0.03, 0.045, -0.1),
		Vector3(-0.06, 0.045, -0.07), Vector3(0.02, 0.12, 0.01)]
	for i in n:
		_sphere(root, 0.05 if i else 0.055, spots[i], STONE.darkened(0.04 * float(i % 3)))
	return root


## v0.12.7 the middle of a model's meshes, in its own space (to turn it round its centre).
static func middle(m: Node3D) -> Vector3:
	var box := AABB()
	var first := true
	for c in m.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var t := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != m:   # its transform relative to the model's root
			t = (n as Node3D).transform * t
			n = n.get_parent()
		var b := t * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box.get_center()


## The model for a weapon slot (Weapons.FISTS has none).
static func for_weapon(w: int) -> Node3D:
	match w:
		Weapons.CLUB: return club()
		Weapons.SWORD: return sword()
		Weapons.BOW: return bow()
		Weapons.SLING: return sling()
		Weapons.STAFF: return staff()
		Weapons.WAND: return wand()
	return null


static func sword() -> Node3D:
	var n := Node3D.new()
	_box(n, Vector3(0.055, 0.78, 0.014), Vector3(0, 0.55, 0), STEEL, 0.25, 0.8)        # blade
	_box(n, Vector3(0.018, 0.74, 0.016), Vector3(0, 0.55, 0), STEEL_DARK, 0.3, 0.8)    # fuller
	var tip := _box(n, Vector3(0.04, 0.04, 0.014), Vector3(0, 0.95, 0), STEEL, 0.25, 0.8)
	tip.rotation.z = PI / 4.0
	_box(n, Vector3(0.24, 0.035, 0.05), Vector3(0, 0.15, 0), GOLD, 0.35, 0.7)           # crossguard
	_cyl(n, 0.022, 0.2, Vector3(0, 0.04, 0), LEATHER)                                   # grip
	_sphere(n, 0.035, Vector3(0, -0.075, 0), GOLD)                                      # pommel
	return n


static func club() -> Node3D:
	var n := Node3D.new()
	var head := CylinderMesh.new()
	head.top_radius = 0.085
	head.bottom_radius = 0.035
	head.height = 0.62
	_mesh(n, head, Vector3(0, 0.38, 0), WOOD)
	_sphere(n, 0.085, Vector3(0, 0.69, 0), WOOD)
	for y in [0.48, 0.6]:                                                                # knots
		_sphere(n, 0.03, Vector3(0.07, y, 0.02), WOOD_DARK)
	_cyl(n, 0.032, 0.16, Vector3(0, 0.0, 0), LEATHER)                                   # wrapped handle
	return n


static func bow() -> Node3D:
	var n := Node3D.new()
	# the stave: segments along an arc, belly toward -Z (forward); grip at the middle
	var pts := []
	for i in 11:
		var t := (i - 5) / 5.0
		pts.append(Vector3(0, t * 0.62, -0.13 * (1.0 - t * t)))
	for i in 10:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var seg := _box(n, Vector3(0.03, (b - a).length() + 0.01, 0.03), (a + b) / 2.0, WOOD, 0.8)
		seg.rotation.x = atan2(b.z - a.z, b.y - a.y) * -1.0
	_box(n, Vector3(0.006, 1.24, 0.006), Vector3(0, 0, 0.0), STRING, 0.6).name = "string"   # (the 3D figure draws it live when drawing)
	_cyl(n, 0.025, 0.14, Vector3(0, 0, -0.13), LEATHER)                                  # grip wrap
	return n


static func sling() -> Node3D:
	var n := Node3D.new()
	_cyl(n, 0.022, 0.2, Vector3(0, 0.0, 0), WOOD_DARK)                                   # handle
	for s in [-1.0, 1.0]:
		var prong := _cyl(n, 0.018, 0.2, Vector3(s * 0.06, 0.18, 0), WOOD)
		prong.rotation.z = -s * 0.5
	_box(n, Vector3(0.012, 0.012, 0.14), Vector3(-0.1, 0.27, 0.07), BAND, 0.7).name = "band_l"   # bands and pouch at rest
	_box(n, Vector3(0.012, 0.012, 0.14), Vector3(0.1, 0.27, 0.07), BAND, 0.7).name = "band_r"
	_box(n, Vector3(0.06, 0.03, 0.03), Vector3(0, 0.27, 0.14), LEATHER, 0.8).name = "pouch"
	return n


static func quiver() -> Node3D:
	var n := Node3D.new()
	_cyl(n, 0.07, 0.5, Vector3(0, 0.25, 0), LEATHER)
	for i in 4:
		var a := i * TAU / 4.0
		var p := Vector3(cos(a) * 0.035, 0.6, sin(a) * 0.035)
		_cyl(n, 0.008, 0.3, p, WOOD)
		_box(n, Vector3(0.05, 0.07, 0.006), p + Vector3(0, 0.12, 0), BAND, 0.8)
	return n


static func rocks() -> Node3D:
	var n := Node3D.new()
	for p in [Vector3(0, 0.05, 0), Vector3(0.09, 0.04, 0.03), Vector3(-0.07, 0.04, 0.06), Vector3(0.02, 0.12, 0.02), Vector3(-0.03, 0.04, -0.08)]:
		_sphere(n, 0.055, p, STONE.darkened(randf() * 0.15))
	return n


# ---------------------------------------------------------------------------------------------- helpers
static func _mat(c: Color, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, c: Color, rough := 0.7, metal := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	mi.material_override = _mat(c, rough, metal)
	parent.add_child(mi)
	return mi


static func _box(parent: Node3D, size: Vector3, at: Vector3, c: Color, rough := 0.7, metal := 0.0) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mesh(parent, b, at, c, rough, metal)


static func _cyl(parent: Node3D, r: float, h: float, at: Vector3, c: Color) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	return _mesh(parent, cm, at, c)


static func _sphere(parent: Node3D, r: float, at: Vector3, c: Color) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return _mesh(parent, s, at, c)


## The wizard's staff: a long dark shaft, silver bands, a three-pronged claw at the top holding a glowing blue orb.
## Gripped at the origin (about a third of the way down from the top).
static func staff() -> Node3D:
	var n := Node3D.new()
	_box(n, Vector3(0.05, 1.62, 0.05), Vector3(0, -0.21, 0), WOOD_DARK, 0.85, 0.0)
	for y in [-0.85, -0.2, 0.42]:
		_box(n, Vector3(0.068, 0.04, 0.068), Vector3(0, y, 0), STEEL, 0.3, 0.8)
	for k in 3:
		var a := TAU * k / 3.0
		var prong := _box(n, Vector3(0.026, 0.2, 0.026), Vector3(cos(a) * 0.06, 0.66, sin(a) * 0.06), WOOD, 0.8, 0.0)
		prong.rotation = Vector3(sin(a) * 0.35, 0, -cos(a) * 0.35)
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.085
	sm.height = 0.17
	orb.mesh = sm
	var om := StandardMaterial3D.new()
	om.albedo_color = Color("7fd8ff")
	om.emission_enabled = true
	om.emission = Color("4fb4ff")
	om.emission_energy_multiplier = 2.6
	orb.material_override = om
	orb.position = Vector3(0, 0.76, 0)
	orb.name = "Orb"
	n.add_child(orb)
	var light := OmniLight3D.new()
	light.light_color = Color("6cc6ff")
	light.light_energy = 0.8
	light.omni_range = 2.2
	light.position = orb.position
	n.add_child(light)
	return n


## The magic wand: a slim dark wand with a silver grip ring and a glowing violet tip. Gripped at the origin.
static func wand() -> Node3D:
	var n := Node3D.new()
	_box(n, Vector3(0.028, 0.36, 0.028), Vector3(0, 0.12, 0), Color("3a2418"), 0.7, 0.0)
	_box(n, Vector3(0.04, 0.06, 0.04), Vector3(0, -0.03, 0), STEEL, 0.3, 0.8)
	_box(n, Vector3(0.036, 0.03, 0.036), Vector3(0, 0.05, 0), GOLD, 0.3, 0.8)
	var tip := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.03
	sm.height = 0.06
	tip.mesh = sm
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color("d9a8ff")
	tm.emission_enabled = true
	tm.emission = Color("b066ff")
	tm.emission_energy_multiplier = 3.0
	tip.material_override = tm
	tip.position = Vector3(0, 0.31, 0)
	tip.name = "Orb"
	n.add_child(tip)
	return n

