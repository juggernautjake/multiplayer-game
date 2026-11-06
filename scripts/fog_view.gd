## The wand's Fog on the screen (v0.12.0; the rules are in Fog). Keeps every client's copy of the fog list (from the
## server's "fog" events) and each frame, for the player at this screen:
##   - draws each cloud as layered billboard smoke puffs (a soft noise texture), drifting and thinning at the end:
##     thick and opaque for anyone it's hidden from, faint and see-through for the caster and allies;
##   - hides players, challengers and golems inside a cloud from those it's hidden from (their name, health and mana
##     bars go with them), in the 3D figure and the Pip views alike;
##   - outlines the caster's enemies inside (and the viewer themselves) with a glowing silhouette that shows through
##     everything: a rim-light overlay (next pass) on the figure's and golems' meshes, a glowing twin behind Pip's sprite;
##   - for an enemy of the caster inside it: a screen-space fog (reads the depth buffer, measures from the player's
##     body) closing in to 2-3 m, colours washed out and a dark vignette; the crosshair (UI) stays. It eases in and
##     clears within Fog.CLEAR ticks (half a second) of stepping out or as the cloud fades.
class_name FogView
extends Node3D

const PUFFS_SIDE := 6        # puffs per side per layer
const LAYERS := 3

const SCREEN_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 0.0;
uniform vec3 body = vec3(0.0);
uniform float near_m = 1.6;
uniform float far_m = 3.2;
uniform vec3 fog_col : source_color = vec3(0.6, 0.64, 0.68);
void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}
void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 v = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	v.xyz /= v.w;
	vec3 world = (INV_VIEW_MATRIX * vec4(v.xyz, 1.0)).xyz;
	float d = length(world - body);
	if (depth <= 0.00001) { d = 1000.0; }
	float wobble = 0.25 * sin(TIME * 1.3 + world.x * 0.7) * sin(TIME * 0.9 + world.z * 0.6);
	float f = smoothstep(near_m + wobble, far_m + wobble, d);
	vec3 bg = texture(screen_tex, SCREEN_UV).rgb;
	float grey = dot(bg, vec3(0.299, 0.587, 0.114));
	vec3 muted = mix(bg, vec3(grey) * 0.85 + fog_col * 0.15, 0.8 * amount);
	float vig = smoothstep(0.3, 0.75, length((SCREEN_UV - 0.5) * vec2(1.6, 1.0)));
	vec3 col = mix(muted, fog_col, clamp(f * amount, 0.0, 0.97));
	col = mix(col, fog_col * 0.35, vig * amount * 0.8);
	ALBEDO = col;
}
"""

const OUTLINE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.35, 0.2, 1.0);
void fragment() {
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 1.6);
	float pulse = 0.85 + 0.15 * sin(TIME * 6.0);
	ALBEDO = col.rgb * (0.18 + 2.6 * rim) * pulse;
}
"""

## Pip's outline: his sprite's own shape grown by a few pixels (the alpha sampled round each point), flat glowing
## colour, drawn just behind him; billboarded upright like his sprite.
const TWIN_SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D tex : filter_nearest;
uniform vec4 col : source_color = vec4(1.0, 0.35, 0.2, 1.0);
uniform vec2 px = vec2(0.002);
uniform bool upright = true;
void vertex() {
	if (upright) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
			vec4(0.0, 1.0, 0.0, 0.0), vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0), MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	}
}
void fragment() {
	float a = 0.0;
	for (int i = 0; i < 12; i++) {
		float ang = float(i) * 0.5235988;
		a = max(a, texture(tex, UV + vec2(cos(ang), sin(ang)) * px * 2.5).a);
	}
	float pulse = 0.85 + 0.15 * sin(TIME * 6.0);
	ALBEDO = col.rgb * 2.2 * pulse;
	ALPHA = step(0.5, a) * 0.95;
}
"""

var net: Net
var main: Node3D
var fogs: Array = []          # Fog records, the same as the server's
var clouds := {}              # fog id -> { root, puffs: [[MeshInstance3D, offset, size, phase]], mat }
var _screen: MeshInstance3D
var _screen_mat: ShaderMaterial
var _impair := 0.0            # eased blindness shown
var _outline_enemy: ShaderMaterial
var _outline_self: ShaderMaterial
var _twins := {}              # Pip avatar -> its glowing twin sprite
var _outlined := {}           # node -> true: what has an outline now
static var _cloud_tex: Texture2D


func setup(n: Net, m: Node3D) -> void:
	net = n
	main = m
	net.magic_fx.connect(_on_fx)
	_outline_enemy = _outline_mat(Color(1.0, 0.32, 0.18))
	_outline_self = _outline_mat(Color(0.45, 0.85, 1.0))


static func _outline_mat(c: Color) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = OUTLINE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("col", c)
	return mat


func _on_fx(kind: String, a: Array) -> void:
	if kind == "fog":
		var f := Fog.from_args(a)
		fogs.append(f)
		_build(f)


## The tick everything is drawn at (other players are drawn at the render tick).
func now_tick() -> float:
	return net.render_tick if net.render_tick > 0.0 else float(net.server_tick)


func pvp_map() -> Dictionary:
	var d := {}
	for id in net.roster.keys():
		d[id] = bool(net.roster[id].get("pvp", false))
	return d


# ================================================================ the cloud
static func cloud_texture() -> Texture2D:
	if _cloud_tex != null:
		return _cloud_tex
	var n := FastNoiseLite.new()
	n.seed = 7
	n.frequency = 0.06
	n.fractal_octaves = 4
	var sz := 96
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	for y in sz:
		for x in sz:
			var dx := (x - sz / 2.0) / (sz / 2.0)
			var dy := (y - sz / 2.0) / (sz / 2.0)
			var r := sqrt(dx * dx + dy * dy)
			var fall := clampf(1.0 - r, 0.0, 1.0)
			var v := 0.55 + 0.45 * n.get_noise_2d(x, y)
			var a := clampf(fall * fall * (0.6 + 0.8 * v), 0.0, 1.0)
			var shade := 0.82 + 0.18 * v
			img.set_pixel(x, y, Color(shade, shade, shade * 1.03, a))
	_cloud_tex = ImageTexture.create_from_image(img)
	return _cloud_tex


func _build(f: Dictionary) -> void:
	var root := Node3D.new()
	add_child(root)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = cloud_texture()
	mat.albedo_color = Color(0.72, 0.75, 0.78, 0.0)
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f.id) * 7919
	var h := float(f.half)
	var puffs := []
	for layer in LAYERS:
		for i in PUFFS_SIDE:
			for j in PUFFS_SIDE:
				var u := (i + 0.5) / PUFFS_SIDE * 2.0 - 1.0
				var v := (j + 0.5) / PUFFS_SIDE * 2.0 - 1.0
				var off := Vector3(u * h * 0.92 + rng.randf_range(-1.2, 1.2), 0.9 + layer * 1.9 + rng.randf_range(-0.4, 0.5),
					v * h * 0.92 + rng.randf_range(-1.2, 1.2))
				var size := rng.randf_range(6.5, 9.0) * (1.0 if layer < 2 else 1.25)
				var mi := MeshInstance3D.new()
				var q := QuadMesh.new()
				q.size = Vector2(size, size)
				mi.mesh = q
				mi.material_override = mat
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				root.add_child(mi)
				puffs.append([mi, off, size, rng.randf() * TAU])
	clouds[f.id] = { "root": root, "puffs": puffs, "mat": mat }


# ================================================================ every frame (Main calls this after placing avatars)
func update(delta: float, avatars: Dictionary, golem_view: GolemView, cam: Camera3D) -> void:
	var tick := now_tick()
	fogs = Fog.prune(fogs, tick)
	for id in clouds.keys():
		var alive := false
		for f in fogs:
			if f.id == id:
				alive = true
		if not alive:
			(clouds[id].root as Node3D).queue_free()
			clouds.erase(id)
	var me: int = net.my_id
	var mpos := Vector3.ZERO
	if avatars.has(me):
		mpos = (avatars[me] as Node3D).position
	var pvp := pvp_map()
	var view := Fog.view_for(me, mpos, fogs, tick, pvp)
	var t := Time.get_ticks_msec() * 0.001
	for f: Dictionary in fogs:
		if not clouds.has(f.id):
			_build(f)
		var cl: Dictionary = clouds[f.id]
		var dens := Fog.density(f, tick)
		var c := Fog.centre(f, tick)
		var grow := Fog.half_now(f, tick) / float(f.half)
		var thru: bool = f.id in view.see_through
		var mat: StandardMaterial3D = cl.mat
		var appear := clampf((tick - float(f.t0)) / 30.0, 0.0, 1.0)   # it billows out over half a second
		mat.albedo_color.a = (0.12 if thru else 0.8) * dens * appear
		for p in cl.puffs:
			var mi: MeshInstance3D = p[0]
			var off: Vector3 = p[1]
			var ph: float = p[3]
			mi.position = c + Vector3(off.x * grow * appear, off.y, off.z * grow * appear) \
				+ Vector3(sin(t * 0.4 + ph) * 0.6, sin(t * 0.3 + ph * 2.0) * 0.25, cos(t * 0.35 + ph) * 0.6)
			mi.scale = Vector3.ONE * (0.4 + 0.6 * appear) * (1.0 + 0.3 * (1.0 - dens))
	# who's hidden, who's outlined
	for id in avatars.keys():
		var av: Node3D = avatars[id]
		if not av.visible and id != me:
			continue
		var look := Fog.look_for(me, mpos, int(id), av.position, fogs, tick, pvp, id == me)
		if look == Fog.Look.HIDDEN:
			av.visible = false
		_set_outline(av, look == Fog.Look.OUTLINED, id == me)
	if golem_view:
		for gid in golem_view.golems.keys():
			var g: Dictionary = golem_view.golems[gid]
			var root: Node3D = g.root
			if root == null or not is_instance_valid(root):
				continue
			var look := Fog.look_for(me, mpos, int(g.get("owner", 0)), root.position, fogs, tick, pvp)
			root.visible = look != Fog.Look.HIDDEN
			_set_outline(root, look == Fog.Look.OUTLINED, false)
	# the blindness, for an enemy of the caster inside it
	var want := float(view.impair)
	var rate := delta * Config.TICK_RATE / float(Fog.CLEAR)
	_impair = move_toward(_impair, want, rate * (2.0 if want > _impair else 1.0))
	_screen_fog(cam, mpos)


func _screen_fog(cam: Camera3D, body: Vector3) -> void:
	if _impair <= 0.001:
		if _screen:
			_screen.visible = false
		return
	if _screen == null or not is_instance_valid(_screen):
		_screen = MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(2, 2)
		q.flip_faces = true
		_screen.mesh = q
		var sh := Shader.new()
		sh.code = SCREEN_SHADER
		_screen_mat = ShaderMaterial.new()
		_screen_mat.shader = sh
		_screen_mat.render_priority = 120
		_screen.material_override = _screen_mat
		_screen.extra_cull_margin = 16384.0
		_screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if cam != null and _screen.get_parent() != cam:
		if _screen.get_parent():
			_screen.get_parent().remove_child(_screen)
		cam.add_child(_screen)
		_screen.position = Vector3(0, 0, -0.5)
	_screen.visible = true
	_screen_mat.set_shader_parameter("amount", _impair)
	_screen_mat.set_shader_parameter("body", body + Vector3(0, 1.0, 0))


## The glow: a rim-light overlay on every mesh under the node (figure, golem), or a glowing twin behind Pip's sprite.
func _set_outline(node: Node3D, on: bool, own: bool) -> void:
	var was := _outlined.has(node)
	if not on and not was:
		return
	if on:
		_outlined[node] = true
	else:
		_outlined.erase(node)
	if node is Avatar:
		_pip_twin(node as Avatar, on, own)
		return
	var mat: Material = (_outline_self if own else _outline_enemy) if on else null
	for c in node.find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).material_overlay = mat


func _pip_twin(av: Avatar, on: bool, own: bool) -> void:
	var tw: Sprite3D = _twins.get(av, null)
	if tw != null and not is_instance_valid(tw):
		tw = null
	if not on:
		if tw:
			tw.queue_free()
		_twins.erase(av)
		av.sprite.no_depth_test = false
		av.sprite.render_priority = 0
		return
	if tw == null:
		tw = Sprite3D.new()
		var sh := Shader.new()
		sh.code = TWIN_SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		m.render_priority = -1
		tw.material_override = m
		av.sprite.get_parent().add_child(tw)
		_twins[av] = tw
	var s := av.sprite
	av.sprite.no_depth_test = true
	av.sprite.render_priority = 2
	tw.texture = s.texture
	tw.region_enabled = s.region_enabled
	tw.region_rect = s.region_rect
	tw.offset = s.offset
	tw.centered = s.centered
	tw.flip_h = s.flip_h
	tw.pixel_size = s.pixel_size
	tw.billboard = s.billboard
	tw.double_sided = s.double_sided
	tw.transform = s.transform
	tw.visible = s.visible
	var m: ShaderMaterial = tw.material_override
	m.set_shader_parameter("tex", s.texture)
	if s.texture:
		m.set_shader_parameter("px", Vector2(1.0, 1.0) / Vector2(s.texture.get_size()))
	m.set_shader_parameter("upright", s.billboard != BaseMaterial3D.BILLBOARD_DISABLED)
	m.set_shader_parameter("col", Color(0.45, 0.85, 1.0) if own else Color(1.0, 0.32, 0.18))
