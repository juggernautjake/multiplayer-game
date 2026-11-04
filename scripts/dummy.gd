## A practice dummy: a straw figure on a post. Hit it to see your damage: it rocks away from the blow on a spring
## and settles, and shows the last hit, the total and damage per second (reset after 4 s without a hit).
## Purely visual: the server decides hits (Net._damage with target ids -1, -2, ...).
class_name Dummy
extends Node3D

const STIFF := 70.0     # spring stiffness (1/s^2)
const DAMP := 7.0       # damping (1/s)

var pivot: Node3D       # tilts about the base of the post
var label: Label3D
var _tilt := Vector2.ZERO   # lean (x about X, y about Z), radians
var _tilt_v := Vector2.ZERO
var _total := 0
var _first_t := 0.0
var _last_t := -100.0
var _last_amount := 0
var _t := 0.0
var _mats: Array = []      # [material, colour] for the white hit flash
var _flash := 0.0


func _init() -> void:
	pivot = Node3D.new()
	add_child(pivot)
	var straw := Color("d9b56a")
	var wood := Color("7a4a2a")
	var burlap := Color("b89160")
	pivot.add_child(_part(_cyl(0.06, 1.0), Vector3(0, 0.5, 0), wood))               # post
	pivot.add_child(_part(_cyl(0.28, 0.75), Vector3(0, 1.25, 0), burlap))           # body (sack)
	pivot.add_child(_part(_sphere(0.2), Vector3(0, 1.82, 0), burlap.lightened(0.1))) # head
	var arms := _part(_cyl(0.07, 1.1), Vector3(0, 1.45, 0), straw)                   # cross-arm
	arms.rotation.z = PI / 2.0
	pivot.add_child(arms)
	for y in [1.05, 1.42]:                                                            # rope bands
		pivot.add_child(_part(_cyl(0.29, 0.04), Vector3(0, y, 0), wood.darkened(0.2)))
	var base := _part(_cyl(0.3, 0.08), Vector3(0, 0.04, 0), wood.darkened(0.3))
	add_child(base)
	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.45
	label.font_size = 40
	label.outline_size = 10
	label.no_depth_test = true
	label.modulate = Color("ffe08a")
	add_child(label)


## Hit for `amount`, from direction `dir` (attacker to dummy).
func hit(amount: int, dir: Vector3) -> void:
	if _t - _last_t > 4.0:
		_total = 0
		_first_t = _t
	_total += amount
	_last_amount = amount
	_last_t = _t
	var d := Vector2(dir.x, dir.z)
	if d.length_squared() > 1e-6:
		d = d.normalized()
	else:
		d = Vector2(0, -1)
	_flash = 0.09
	var kick := clampf(amount / 8.0, 0.4, 1.6) * 2.6
	_tilt_v += Vector2(d.y, -d.x) * kick   # lean away from the blow


func _process(delta: float) -> void:
	_t += delta
	# a damped spring back to upright
	var acc := -_tilt * STIFF - _tilt_v * DAMP
	_tilt_v += acc * delta
	_tilt += _tilt_v * delta
	_tilt = _tilt.limit_length(0.6)
	pivot.rotation = Vector3(_tilt.x, 0, _tilt.y)
	_flash = maxf(_flash - delta, 0.0)
	for mc in _mats:
		(mc[0] as StandardMaterial3D).albedo_color = Color.WHITE if _flash > 0.0 else mc[1]
	if _t - _last_t < 4.0:
		var span := maxf(_t - _first_t, 1.0)
		label.text = "-%d\ntotal %d   %.0f DPS" % [_last_amount, _total, _total / span]
	else:
		label.text = "Practice dummy"


func _part(m: Mesh, at: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = 0.9
	mi.material_override = mat
	_mats.append([mat, c])
	return mi


func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	return c


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s
