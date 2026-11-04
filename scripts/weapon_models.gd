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


static func make(kind: int) -> Node3D:
	match kind:
		Weapons.Item.CLUB: return club()
		Weapons.Item.SWORD: return sword()
		Weapons.Item.BOW: return bow()
		Weapons.Item.SLING: return sling()
		Weapons.Item.ARROWS: return quiver()
		_: return rocks()


## The model for a weapon slot (Weapons.FISTS has none).
static func for_weapon(w: int) -> Node3D:
	match w:
		Weapons.CLUB: return club()
		Weapons.SWORD: return sword()
		Weapons.BOW: return bow()
		Weapons.SLING: return sling()
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
	_box(n, Vector3(0.006, 1.24, 0.006), Vector3(0, 0, 0.0), STRING, 0.6)                  # string
	_cyl(n, 0.025, 0.14, Vector3(0, 0, -0.13), LEATHER)                                  # grip wrap
	return n


static func sling() -> Node3D:
	var n := Node3D.new()
	_cyl(n, 0.022, 0.2, Vector3(0, 0.0, 0), WOOD_DARK)                                   # handle
	for s in [-1.0, 1.0]:
		var prong := _cyl(n, 0.018, 0.2, Vector3(s * 0.06, 0.18, 0), WOOD)
		prong.rotation.z = -s * 0.5
	_box(n, Vector3(0.012, 0.012, 0.14), Vector3(-0.1, 0.27, 0.07), BAND, 0.7)           # band
	_box(n, Vector3(0.012, 0.012, 0.14), Vector3(0.1, 0.27, 0.07), BAND, 0.7)
	_box(n, Vector3(0.06, 0.03, 0.03), Vector3(0, 0.27, 0.14), LEATHER, 0.8)             # pouch
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
