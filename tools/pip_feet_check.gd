## Visual check: Pip at the origin, camera level at ground height looking at him. His feet should sit exactly on the
## screen's middle row. Run windowed:  Godot.exe --path . -s tools/pip_feet_check.gd -- out.png
extends SceneTree

var frames := 0
var out := "user://pip_feet.png"


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	var root := Node3D.new()
	get_root().add_child(root)
	var av := Avatar.new("Pip", Color.YELLOW, false)
	root.add_child(av)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 4)
	root.add_child(cam)
	cam.make_current()
	var line := MeshInstance3D.new()  # a thin red bar along the ground line
	var bm := BoxMesh.new()
	bm.size = Vector3(3, 0.01, 0.01)
	line.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.RED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line.material_override = m
	root.add_child(line)
	av.set_meta("cam", cam)


func _process(_d: float) -> bool:
	frames += 1
	if frames == 30:
		get_root().get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		return true
	return false
