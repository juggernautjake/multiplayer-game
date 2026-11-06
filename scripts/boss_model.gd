## Thunderhorn's body (v0.11.0): a sculpted, skinned creature built in code, no model files.
##
## One smooth body mesh lofted along his spine (rump, powerful haunches, a tapering waist, a huge humped chest and
## shoulders, a thick neck, a heavy head and muzzle) through Catmull-Rom-smoothed cross sections with muscle lumps,
## the legs and the tail lofted along their joints; every vertex weighted to the bones of a Skeleton3D (hips, spine,
## chest, neck, head, jaw, three bones a leg, six in the tail), so he bends, rears and thrashes like an animal instead of
## parts turning. On top (BoneAttachment3D): ridged, curving obsidian horns, obsidian hooves, armour plates on the
## shoulders and haunches, a crest of spines along the back, a spiked club at the tail's end, teeth bared in a snarl,
## heavy brow ridges slanting down over glowing eyes, flaring nostrils, a mane of storm smoke and cloud tendrils
## hanging from the belly.
##
## Shaders (cheap: value-noise fbm, no textures): HIDE_SHADER, a churning storm-cloud hide (darker underneath, a rim
## glow in his storm colour, fur streaks on the neck and shoulders, a wet glossy snout, scars, glowing veins and a
## lightning skeleton of ribs and spine that pulses brighter in attacks, plates of light cracking open when enraged);
## STONE_SHADER, polished obsidian with glowing crack veins (horns, hooves, plates, spines, tail club); SMOKE_SHADER,
## soft billboards of churning smoke (the mane, the tendrils).
##
## Trails (Trail): glowing ribbons of coloured smoke streaming from his eyes, horn tips, hooves and tail club; verlet
## points that follow with inertia and drift, drawn as camera-facing strips that fade; BossView lights each one while
## that part attacks, in the colour of the attack.
class_name BossModel
extends Node3D

const HIDE_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform vec4 storm : source_color = vec4(0.55, 0.75, 1.0, 1.0);
uniform float hot = 0.0;
uniform float crack = 0.0;
uniform float flash = 0.0;
varying vec3 lp;
float hash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float vnoise(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { float a = 0.5; float s = 0.0; for (int i = 0; i < 4; i++) { s += a * vnoise(p); p *= 2.03; a *= 0.5; } return s; }
void vertex() { lp = VERTEX; }
void fragment() {
	float n = fbm(lp * 0.8 + vec3(0.0, TIME * 0.12, TIME * 0.07));
	float churn = fbm(lp * 2.3 - vec3(TIME * 0.18, 0.0, TIME * 0.1));
	float top = smoothstep(2.6, 5.6, lp.y);
	vec3 base = mix(vec3(0.035, 0.04, 0.06), vec3(0.17, 0.19, 0.26), clamp(n * 0.9 + top * 0.35, 0.0, 1.0));
	float shag = smoothstep(-0.6, -2.6, lp.z) * smoothstep(3.6, 5.2, lp.y);   // fur on the neck and shoulders
	float fur = vnoise(vec3(lp.x * 14.0, lp.y * 2.5 + lp.z * 1.5, lp.z * 14.0));
	base *= 1.0 + shag * (fur - 0.5) * 0.7;
	float sc = abs(fract(dot(lp, vec3(0.55, 0.8, 0.25)) * 1.7) - 0.5);           // old scars
	float scar = smoothstep(0.03, 0.0, sc) * step(0.62, vnoise(lp * 1.3)) * (1.0 - shag);
	base = mix(base, vec3(0.32, 0.3, 0.36), scar * 0.6);
	float snout = smoothstep(-4.3, -5.1, lp.z);
	float v = 1.0 - abs(fbm(lp * 1.5 + vec3(0.0, TIME * 0.05, 0.0)) * 2.0 - 1.0);
	float vein = smoothstep(0.955, 0.995, v);
	float pulse = 0.55 + 0.45 * sin(TIME * 3.0 + lp.z * 1.4);
	float ribs = pow(abs(sin(lp.z * 3.1)), 30.0) * smoothstep(1.6, -0.2, lp.z) * smoothstep(-2.6, -0.9, lp.z) * smoothstep(5.8, 3.4, lp.y) * smoothstep(2.4, 3.3, lp.y);
	float spine = smoothstep(0.22, 0.0, abs(lp.x)) * top;
	float skel = (ribs + spine) * (0.25 + 0.75 * pulse) * (0.35 + hot);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.6);
	ALBEDO = base;
	ROUGHNESS = mix(0.82, 0.18, snout);
	SPECULAR = mix(0.25, 0.85, snout);
	NORMAL = normalize(NORMAL + (vec3(n, churn, fur) - 0.5) * 0.35);
	float cracks = smoothstep(0.9, 0.98, v) * crack;
	float h = min(hot, 1.4);
	EMISSION = storm.rgb * (fres * (0.3 + 0.45 * h) + vein * (0.5 + 1.4 * h) * pulse + skel * 1.2 + cracks * 2.5)
		+ vec3(1.0) * flash * 0.6;
}
"""

const STONE_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 glow : source_color = vec4(0.6, 0.8, 1.0, 1.0);
uniform float hot = 0.0;
uniform float crack = 0.0;
varying vec3 lp;
float hash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float vnoise(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() { lp = VERTEX; }
void fragment() {
	float n = vnoise(lp * 6.0) * 0.6 + vnoise(lp * 13.0) * 0.4;
	float c = 1.0 - abs(vnoise(lp * 4.0 + vec3(3.1)) * 2.0 - 1.0);
	float veins = smoothstep(0.9 - 0.08 * crack, 0.99, c);
	ALBEDO = vec3(0.03, 0.03, 0.045) + vec3(0.05) * n;
	METALLIC = 0.35;
	ROUGHNESS = 0.12 + 0.2 * n;
	SPECULAR = 0.9;
	NORMAL = normalize(NORMAL + (vec3(n, vnoise(lp * 9.0), 0.5) - 0.5) * 0.3);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = glow.rgb * (veins * (0.6 + 2.5 * hot + 2.0 * crack) * (0.7 + 0.3 * sin(TIME * 5.0 + lp.y * 3.0)) + fres * 0.25);
}
"""

const SMOKE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.12, 0.13, 0.19, 1.0);
uniform vec4 storm : source_color = vec4(0.55, 0.75, 1.0, 1.0);
uniform float seed = 0.0;
uniform float yb = 0.0;
uniform float hot = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y); }
float fbm(vec2 p) { float a = 0.5; float s = 0.0; for (int i = 0; i < 4; i++) { s += a * vn(p); p *= 2.1; a *= 0.5; } return s; }
void vertex() {
	if (yb > 0.5) {
		vec3 x = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(x * length(MODEL_MATRIX[0].xyz), 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(cross(x, vec3(0.0, 1.0, 0.0)), 0.0), MODEL_MATRIX[3]);
	} else {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	}
}
void fragment() {
	vec2 uv = UV - 0.5;
	float r = length(uv * vec2(1.0, yb > 0.5 ? 0.55 : 1.0));
	float n = fbm(UV * 3.0 + vec2(seed, -TIME * 0.35 + seed));
	float a = smoothstep(0.5, 0.1, r) * smoothstep(0.25, 0.75, n + 0.25);
	if (yb > 0.5) { a *= smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.6, UV.y + n * 0.3); }
	ALBEDO = tint.rgb + storm.rgb * (pow(n, 3.0) * (0.25 + hot));
	ALPHA = clamp(a, 0.0, 1.0) * 0.85;
}
"""

const TRAIL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y); }
void fragment() {
	float edge = 1.0 - abs(UV.y * 2.0 - 1.0);
	float wisp = vn(vec2(UV.x * 6.0 - TIME * 2.0, UV.y * 3.0)) * 0.6 + 0.4;
	float a = COLOR.a * smoothstep(0.0, 0.8, edge) * wisp;
	ALBEDO = COLOR.rgb * a * 2.0;
	ALPHA = a;
}
"""

const S := 0.85   # the whole model's scale (he stands about 6.5 m to the hump: 3.6 players)

# bone: [name, parent, rest origin in model space (before S)]
const BONES := [
	["root", "", Vector3(0, 0, 0)], ["hips", "root", Vector3(0, 4.2, 2.2)], ["spine", "hips", Vector3(0, 4.4, 0.4)],
	["chest", "spine", Vector3(0, 4.7, -1.2)], ["neck", "chest", Vector3(0, 4.9, -2.5)], ["head", "neck", Vector3(0, 4.7, -3.5)],
	["jaw", "head", Vector3(0, 4.35, -3.9)],
	["FLu", "chest", Vector3(-1.15, 3.7, -1.5)], ["FLk", "FLu", Vector3(-1.2, 2.0, -1.35)], ["FLh", "FLk", Vector3(-1.2, 0.55, -1.5)],
	["FRu", "chest", Vector3(1.15, 3.7, -1.5)], ["FRk", "FRu", Vector3(1.2, 2.0, -1.35)], ["FRh", "FRk", Vector3(1.2, 0.55, -1.5)],
	["BLu", "hips", Vector3(-1.15, 3.9, 2.4)], ["BLk", "BLu", Vector3(-1.2, 1.9, 2.9)], ["BLh", "BLk", Vector3(-1.2, 0.55, 2.6)],
	["BRu", "hips", Vector3(1.15, 3.9, 2.4)], ["BRk", "BRu", Vector3(1.2, 1.9, 2.9)], ["BRh", "BRk", Vector3(1.2, 0.55, 2.6)],
	["t0", "hips", Vector3(0, 4.5, 3.5)], ["t1", "t0", Vector3(0, 4.25, 4.4)], ["t2", "t1", Vector3(0, 3.75, 5.2)],
	["t3", "t2", Vector3(0, 3.15, 5.85)], ["t4", "t3", Vector3(0, 2.5, 6.3)], ["t5", "t4", Vector3(0, 1.95, 6.6)],
]
const LEGS := ["FL", "FR", "BL", "BR"]

var skel: Skeleton3D
var bi := {}                 # bone name -> index
var rest := {}               # bone name -> local rest origin
var body_mat: ShaderMaterial
var stone_mat: ShaderMaterial
var smoke_mats: Array = []
var eyes: Array = []         # MeshInstance3D
var nostrils: Array = []
var anchors := {}            # "eye_l", "eye_r", "horn_l", "horn_r", "hoof_FL"..., "tail" -> Node3D
var trails := {}             # same keys -> Trail
var mane: Array = []         # smoke billboards (for sway)


func build() -> void:
	scale = Vector3.ONE * S
	skel = Skeleton3D.new()
	add_child(skel)
	for b in BONES:
		var i := skel.add_bone(b[0])
		bi[b[0]] = i
		var o: Vector3 = b[2]
		var po: Vector3 = Vector3.ZERO
		if b[1] != "":
			skel.set_bone_parent(i, bi[b[1]])
			po = _bone_origin(b[1])
		rest[b[0]] = o - po
		skel.set_bone_rest(i, Transform3D(Basis.IDENTITY, o - po))
		skel.set_bone_pose_position(i, o - po)
	body_mat = ShaderMaterial.new()
	body_mat.shader = _shader(HIDE_SHADER)
	stone_mat = ShaderMaterial.new()
	stone_mat.shader = _shader(STONE_SHADER)
	var mi := MeshInstance3D.new()
	mi.mesh = _body_mesh()
	mi.material_override = body_mat
	skel.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = skel.create_skin_from_rest_transforms()
	_details()


static var _shaders := {}


static func _shader(code: String) -> Shader:
	if not _shaders.has(code):
		var s := Shader.new()
		s.code = code
		_shaders[code] = s
	return _shaders[code]


func _bone_origin(name: String) -> Vector3:
	for b in BONES:
		if b[0] == name:
			return b[2]
	return Vector3.ZERO


# ================================================================ the mesh
var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedVector3Array()   # each vertex's ring centre (to point normals outward)
var _bo := PackedInt32Array()
var _we := PackedFloat32Array()
var _ix := PackedInt32Array()


func _body_mesh() -> ArrayMesh:
	# the trunk, rump to nose: [z, y, half width, height up, height down, bone weights]
	var spine_b := [["hips", 2.2], ["spine", 0.4], ["chest", -1.2], ["neck", -2.5], ["head", -3.5]]
	var sec := [[3.75, 4.35, 0.5, 0.45, 0.5], [3.4, 4.45, 1.3, 1.1, 1.25], [2.9, 4.5, 1.75, 1.45, 1.55],
		[2.2, 4.5, 1.95, 1.6, 1.7], [1.4, 4.4, 1.7, 1.55, 1.45], [0.5, 4.5, 1.75, 1.75, 1.5],
		[-0.4, 4.65, 2.1, 2.1, 1.75], [-1.2, 4.75, 2.3, 2.45, 1.85], [-1.9, 4.8, 2.15, 2.4, 1.75],
		[-2.5, 4.85, 1.65, 1.85, 1.5], [-3.05, 4.8, 1.25, 1.35, 1.25], [-3.5, 4.75, 1.08, 1.05, 1.1],
		[-4.0, 4.62, 0.98, 0.9, 1.0], [-4.5, 4.45, 0.85, 0.72, 0.85], [-4.95, 4.33, 0.7, 0.55, 0.62],
		[-5.25, 4.27, 0.48, 0.38, 0.42], [-5.38, 4.25, 0.18, 0.15, 0.16]]
	var cs := []
	var rs := []
	var ws := []
	for s in sec:
		cs.append(Vector3(0, s[1], s[0]))
		rs.append(Vector3(s[2], s[3], s[4]))
		ws.append(_chain_w(spine_b, float(s[0])))
	_loft(cs, rs, ws, 28, 3, Vector3.UP, "body")
	# legs: shoulder/hip deep in the body, the knee, the fetlock
	for leg in LEGS:
		var u := _bone_origin(leg + "u")
		var k := _bone_origin(leg + "k")
		var h := _bone_origin(leg + "h")
		var back: bool = leg.begins_with("B")
		var top := u + Vector3(0, 0.9, 0.0)
		var mid1 := u.lerp(k, 0.45) + Vector3(0, 0, 0.25 if back else -0.05)
		var lc := [top, u, mid1, k, k.lerp(h, 0.5), h]
		var lr := [1.15, 1.05, 0.85 if back else 0.72, 0.42, 0.33, 0.3] if back else [1.0, 0.95, 0.68, 0.4, 0.32, 0.28]
		var lw := [[[leg + "u", 1.0]], [[leg + "u", 1.0]], [[leg + "u", 1.0]], [[leg + "u", 0.5], [leg + "k", 0.5]],
			[[leg + "k", 1.0]], [[leg + "k", 0.4], [leg + "h", 0.6]]]
		var parent := "hips" if back else "chest"
		lw[0] = [[leg + "u", 0.5], [parent, 0.5]]
		var rr := []
		for r in lr:
			rr.append(Vector3(r, r, r))
		_loft(lc, rr, lw, 16, 3, Vector3.FORWARD, "leg")
	# the tail
	var tc := []
	var tr := []
	var tw := []
	for i in 6:
		tc.append(_bone_origin("t%d" % i))
		var r := lerpf(0.55, 0.14, float(i) / 5.0)
		tr.append(Vector3(r, r, r))
		tw.append([["t%d" % i, 1.0]] if i == 0 else [["t%d" % (i - 1), 0.3], ["t%d" % i, 0.7]])
	tc.push_front(_bone_origin("t0") + Vector3(0, 0.1, -0.6))
	tr.push_front(Vector3(0.7, 0.7, 0.7))
	tw.push_front([["hips", 1.0]])
	_loft(tc, tr, tw, 12, 3, Vector3.UP, "tail")
	# normals: summed face normals, pointing away from each ring's centre
	_n.resize(_v.size())
	for i in _n.size():
		_n[i] = Vector3.ZERO
	for f in range(0, _ix.size(), 3):
		var a := _v[_ix[f]]
		var nb := (_v[_ix[f + 1]] - a).cross(_v[_ix[f + 2]] - a)
		for j in 3:
			_n[_ix[f + j]] += nb
	for i in _n.size():
		var nn := _n[i].normalized()
		if nn.dot(_v[i] - _c[i]) < 0.0:
			nn = -nn
		_n[i] = nn
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _v
	arr[Mesh.ARRAY_NORMAL] = _n
	arr[Mesh.ARRAY_BONES] = _bo
	arr[Mesh.ARRAY_WEIGHTS] = _we
	arr[Mesh.ARRAY_INDEX] = _ix
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Weights along a chain of [bone, z]: blended between the two bones either side of z.
func _chain_w(chain: Array, z: float) -> Array:
	if z >= float(chain[0][1]):
		return [[chain[0][0], 1.0]]
	for i in chain.size() - 1:
		var z0 := float(chain[i][1])
		var z1 := float(chain[i + 1][1])
		if z <= z0 and z >= z1:
			var k := (z0 - z) / (z0 - z1)
			return [[chain[i][0], 1.0 - k], [chain[i + 1][0], k]]
	return [[chain[-1][0], 1.0]]


static func _cr(p0, p1, p2, p3, t: float):
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)


## A smooth tube through centres cs with radii rs (x: half width, y: up, z: down), Catmull-Rom subdivided `sub` times
## between sections, `seg` around; muscle lumps on the body; capped at both ends; weights ws per section.
func _loft(cs: Array, rs: Array, ws: Array, seg: int, sub: int, ref: Vector3, kind: String) -> void:
	var rings := []   # [centre, radii, weights dict]
	var n := cs.size()
	for i in n - 1:
		for k in sub:
			var t := float(k) / sub
			var p0: Vector3 = cs[maxi(i - 1, 0)]
			var p3: Vector3 = cs[mini(i + 2, n - 1)]
			var c: Vector3 = _cr(p0, cs[i], cs[i + 1], p3, t)
			var r: Vector3 = _cr(rs[maxi(i - 1, 0)], rs[i], rs[i + 1], rs[mini(i + 2, n - 1)], t)
			var wd := {}
			for e in ws[i]:
				wd[e[0]] = float(wd.get(e[0], 0.0)) + float(e[1]) * (1.0 - t)
			for e in ws[i + 1]:
				wd[e[0]] = float(wd.get(e[0], 0.0)) + float(e[1]) * t
			rings.append([c, r, wd])
	rings.append([cs[n - 1], rs[n - 1], _wd(ws[n - 1])])
	var base := _v.size()
	for ri in rings.size():
		var c: Vector3 = rings[ri][0]
		var r: Vector3 = rings[ri][1]
		var tan: Vector3 = (rings[mini(ri + 1, rings.size() - 1)][0] - rings[maxi(ri - 1, 0)][0]).normalized()
		var rf := ref if absf(tan.dot(ref)) < 0.9 else Vector3.RIGHT
		var nx := rf.cross(tan).normalized()
		var by := tan.cross(nx).normalized()
		if kind == "leg":   # legs: x across the body, y forward
			nx = Vector3.RIGHT
			by = tan.cross(nx).normalized()
		var s := float(ri) / rings.size()
		for j in seg:
			var a := TAU * j / seg
			var ca := cos(a)
			var sa := sin(a)
			var lump := 1.0
			if kind == "body":
				lump = 1.0 + 0.05 * sin(3.0 * a + s * 9.0) + 0.035 * sin(5.0 * a - s * 13.0) + 0.03 * sin(s * 31.0) * absf(ca)
				if sa < -0.6:
					lump *= 0.94   # a flatter belly
			elif kind == "leg":
				lump = 1.0 + 0.07 * sin(2.0 * a + s * 6.0) * (1.0 - s)
			var h := r.y if sa > 0.0 else r.z
			var p := c + nx * ca * r.x * lump + by * sa * h * lump
			_add_v(p, c, rings[ri][2])
	for ri in rings.size() - 1:
		for j in seg:
			var a := base + ri * seg + j
			var b := base + ri * seg + (j + 1) % seg
			var c2 := a + seg
			var d := b + seg
			_ix.append_array([a, c2, b, b, c2, d])
	for end in [0, rings.size() - 1]:   # caps
		var c: Vector3 = rings[end][0]
		var ci := _v.size()
		_add_v(c + ((c - rings[1 if end == 0 else end - 1][0]) as Vector3).normalized() * 0.05, c - ((c - rings[1 if end == 0 else end - 1][0]) as Vector3).normalized(), rings[end][2])
		for j in seg:
			_ix.append_array([ci, base + end * seg + j, base + end * seg + (j + 1) % seg])


func _wd(list: Array) -> Dictionary:
	var d := {}
	for e in list:
		d[e[0]] = float(e[1])
	return d


func _add_v(p: Vector3, c: Vector3, wd: Dictionary) -> void:
	_v.append(p)
	_c.append(c)
	var keys := wd.keys()
	keys.sort_custom(func(x, y): return float(wd[x]) > float(wd[y]))
	var tot := 0.0
	for i in mini(4, keys.size()):
		tot += float(wd[keys[i]])
	for i in 4:
		if i < keys.size():
			_bo.append(bi[keys[i]])
			_we.append(float(wd[keys[i]]) / maxf(tot, 1e-5))
		else:
			_bo.append(0)
			_we.append(0.0)


# ================================================================ the details on the bones
func _attach(bone: String) -> BoneAttachment3D:
	var a := BoneAttachment3D.new()
	a.bone_name = bone
	skel.add_child(a)
	return a


## A node placed at a model-space point, on a bone (its attachment follows the bone).
func _on(bone: String, at: Vector3, mesh: Mesh, mat: Material, basis := Basis.IDENTITY) -> MeshInstance3D:
	var att := _attach(bone)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(basis, at - _bone_origin(bone))
	att.add_child(mi)
	return mi


func _sphere(r := 0.5, h := 1.0) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 16
	m.rings = 10
	return m


func _cone(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 8
	m.rings = 1
	return m


func _details() -> void:
	# horns: curving out, up and forward, ridged, tapering to a point
	for side in [-1.0, 1.0]:
		var pts := [Vector3(0.55 * side, 5.15, -3.45), Vector3(1.35 * side, 5.35, -3.35), Vector3(2.05 * side, 5.9, -3.6),
			Vector3(2.15 * side, 6.7, -4.15), Vector3(1.7 * side, 7.2, -4.75)]
		var hm := _tube(pts, [0.34, 0.3, 0.22, 0.12, 0.02], 10, true)
		var att := _attach("head")
		var mi := MeshInstance3D.new()
		mi.mesh = hm
		mi.material_override = stone_mat
		mi.position = -_bone_origin("head")
		att.add_child(mi)
		var tip := Node3D.new()
		tip.position = pts[4]
		mi.add_child(tip)
		anchors["horn_" + ("l" if side < 0 else "r")] = tip
		# a heavy brow ridge slanting down toward the middle: always scowling
		_on("head", Vector3(0.38 * side, 5.02, -3.95), _sphere(), body_mat, Basis(Vector3.FORWARD, 0.45 * side).scaled(Vector3(0.62, 0.2, 0.42)))
		# the eye under it, narrowed
		var e := _on("head", Vector3(0.43 * side, 4.86, -4.12), _sphere(), MagicFx._glow_mat(Color("cfe8ff"), 9.0), Basis(Vector3.FORWARD, 0.4 * side).scaled(Vector3(0.24, 0.1, 0.12)))
		eyes.append(e)
		anchors["eye_" + ("l" if side < 0 else "r")] = e
		# flaring nostrils
		var nmat := StandardMaterial3D.new()
		nmat.albedo_color = Color("07070b")
		nmat.roughness = 0.3
		nostrils.append(_on("head", Vector3(0.2 * side, 4.36, -5.33), _sphere(), nmat, Basis.IDENTITY.scaled(Vector3(0.14, 0.1, 0.08))))
	# teeth, bared: a row along the upper lip and up from the jaw
	var tooth := StandardMaterial3D.new()
	tooth.albedo_color = Color("d9d4c4")
	tooth.roughness = 0.35
	for i in 7:
		var x := (float(i) - 3.0) * 0.13
		var z := -5.12 + absf(x) * 0.6
		_on("head", Vector3(x, 4.02, z), _cone(0.05, 0.22), tooth, Basis(Vector3.RIGHT, PI))
		if i % 2 == 0:
			_on("jaw", Vector3(x * 1.05, 3.92, z + 0.06), _cone(0.045, 0.18), tooth)
	# a crest of spines along the back, armour plates on the shoulders and haunches
	for i in 9:
		var z := lerpf(-2.6, 2.6, float(i) / 8.0)
		var bone := "neck" if z < -2.2 else ("chest" if z < -0.4 else ("spine" if z < 1.3 else "hips"))
		var y := 4.85 + (2.35 if z < -0.5 and z > -2.2 else (1.85 if z <= -2.2 else 1.65))
		var hgt := 0.9 if z < 0.0 else 0.6
		_on(bone, Vector3(0, y + hgt * 0.4 - 0.1, z), _cone(0.2, hgt), stone_mat, Basis(Vector3.RIGHT, -0.5))
	for side in [-1.0, 1.0]:
		for spec in [["chest", Vector3(1.75, 5.6, -1.4), 0.5], ["chest", Vector3(1.45, 6.1, -0.6), 0.35], ["hips", Vector3(1.55, 5.4, 2.3), 0.4]]:
			var p: Vector3 = spec[1]
			_on(spec[0], Vector3(p.x * side, p.y, p.z), _sphere(), stone_mat,
				Basis(Vector3.FORWARD, float(spec[2]) * side).scaled(Vector3(1.0, 0.18, 0.8)))
	# hooves
	for leg in LEGS:
		var hm := CylinderMesh.new()
		hm.top_radius = 0.33
		hm.bottom_radius = 0.42
		hm.height = 0.55
		hm.radial_segments = 12
		var h := _bone_origin(leg + "h")
		var mi := _on(leg + "h", Vector3(h.x, 0.27, h.z - 0.05), hm, stone_mat)
		anchors["hoof_" + leg] = mi
	# the tail's spiked club
	var club := _on("t5", _bone_origin("t5") + Vector3(0, -0.15, 0.15), _sphere(), stone_mat, Basis.IDENTITY.scaled(Vector3(0.45, 0.55, 0.45)))
	anchors["tail"] = club
	for i in 7:
		var a := TAU * i / 7.0
		var d := Vector3(cos(a), 0.4 * sin(a * 2.0), sin(a)).normalized()
		var b := Basis(Vector3.UP.cross(d).normalized() if absf(d.y) < 0.99 else Vector3.RIGHT, Vector3.UP.angle_to(d))
		_on("t5", _bone_origin("t5") + Vector3(0, -0.15, 0.15) + d * 0.35, _cone(0.08, 0.45), stone_mat, b)
	for i in 3:
		_on("t%d" % (i + 2), _bone_origin("t%d" % (i + 2)) + Vector3(0, 0.3 - i * 0.04, 0), _cone(0.09, 0.4), stone_mat, Basis(Vector3.RIGHT, -0.7))
	# the mane of storm smoke over the neck and hump, tendrils hanging under the belly
	for i in 10:
		var z := lerpf(-3.2, 0.2, float(i) / 9.0)
		var bone := "neck" if z < -2.2 else "chest"
		var side := -1.0 if i % 2 == 0 else 1.0
		var y := 4.85 + (1.9 if z < -2.2 else 2.4) + 0.2
		mane.append(_smoke(bone, Vector3(0.6 * side, y, z), Vector2(2.2, 2.0), false))
	for i in 6:
		var z := lerpf(-1.6, 1.6, float(i) / 5.0)
		mane.append(_smoke("spine" if z > -0.4 else "chest", Vector3(0.8 * (-1.0 if i % 2 else 1.0), 2.4, z), Vector2(0.9, 2.6), true))
	for i in 4:
		mane.append(_smoke("FL" if i < 2 else "BL", Vector3(0, 0, 0), Vector2(1.2, 1.0), false, "u" if i % 2 == 0 else "k"))
	# trails
	for k in anchors.keys():
		trails[k] = Trail.new(self, 0.22 if k.begins_with("eye") else (0.32 if k.begins_with("horn") else 0.45))


func _smoke(bone: String, at: Vector3, size: Vector2, hang: bool, leg_part := "") -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var m := ShaderMaterial.new()
	m.shader = _shader(SMOKE_SHADER)
	m.set_shader_parameter("seed", randf() * 30.0)
	m.set_shader_parameter("yb", 1.0 if hang else 0.0)
	smoke_mats.append(m)
	var b := bone if leg_part == "" else bone + leg_part
	var p := at if leg_part == "" else _bone_origin(b) + Vector3(0, -0.1, 0)
	var mi := _on(b, p, q, m)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if hang:
		mi.position.y -= size.y * 0.5
	return mi


## A rigid tapered, ridged tube (the horns).
func _tube(pts: Array, radii: Array, seg: int, ridged: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := []
	var steps := 24
	for i in steps + 1:
		var u := float(i) / steps * (pts.size() - 1)
		var k := mini(int(u), pts.size() - 2)
		var f := u - k
		var c: Vector3 = _cr(pts[maxi(k - 1, 0)], pts[k], pts[k + 1], pts[mini(k + 2, pts.size() - 1)], f)
		var r := lerpf(float(radii[k]), float(radii[k + 1]), f)
		if ridged:
			r *= 1.0 + 0.1 * maxf(sin(float(i) * 2.2), 0.0)
		rings.append([c, r])
	for i in rings.size():
		var c: Vector3 = rings[i][0]
		var tan: Vector3 = (rings[mini(i + 1, rings.size() - 1)][0] - rings[maxi(i - 1, 0)][0]).normalized()
		var nx := Vector3.UP.cross(tan).normalized() if absf(tan.y) < 0.95 else Vector3.RIGHT
		var by := tan.cross(nx).normalized()
		rings[i].append([nx, by])
	for i in rings.size() - 1:
		for j in seg:
			var quad := []
			for e in [[i, j], [i + 1, j], [i, j + 1], [i + 1, j + 1]]:
				var rg: Array = rings[e[0]]
				var a := TAU * float(int(e[1]) % seg) / seg
				var d: Vector3 = rg[2][0] * cos(a) + rg[2][1] * sin(a)
				quad.append([rg[0] + d * float(rg[1]), d])
			for vi in [0, 1, 2, 2, 1, 3]:
				st.set_normal(quad[vi][1])
				st.add_vertex(quad[vi][0])
	return st.commit()


# ================================================================ posing
## Pose him: p is a dictionary of angles (radians) and offsets; missing ones are 0. gait: per leg [swing, bend].
func apply(p: Dictionary, legs: Array, tail_t: float, delta: float) -> void:
	var pitch := float(p.get("pitch", 0.0))
	var crouch := float(p.get("crouch", 0.0))
	_rot("hips", Vector3(pitch, float(p.get("twist", 0.0)) * 0.4, float(p.get("roll", 0.0))), Vector3(0, -crouch + float(p.get("bob", 0.0)), 0))
	_rot("spine", Vector3(-pitch * 0.15 + float(p.get("arch", 0.0)), float(p.get("bend", 0.0)) * 0.5, float(p.get("roll", 0.0)) * 0.5))
	_rot("chest", Vector3(float(p.get("arch", 0.0)), float(p.get("bend", 0.0)) * 0.5, 0.0))
	var hd := float(p.get("head_dip", 0.0))
	var hu := float(p.get("head_up", 0.0))
	var hy := float(p.get("head_yaw", 0.0))
	_rot("neck", Vector3((hu - hd) * 0.5 - pitch * 0.3, hy * 0.5, float(p.get("thrash", 0.0)) * 0.3))
	_rot("head", Vector3((hu - hd) * 0.6, hy * 0.5, float(p.get("thrash", 0.0))))
	_rot("jaw", Vector3(-float(p.get("jaw", 0.05)), 0, 0))
	for i in 4:
		var leg: String = LEGS[i]
		var g: Array = legs[i]
		var counter := -pitch if leg.begins_with("B") else 0.0   # the back legs stay planted as he rears
		var cr := crouch * (0.5 if leg.begins_with("B") else 0.35)
		_rot(leg + "u", Vector3(float(g[0]) + counter + cr, 0, 0))
		_rot(leg + "k", Vector3(-float(g[1]) - cr * 2.0, 0, 0))
		_rot(leg + "h", Vector3(float(g[1]) * 0.6 + cr, 0, 0))
	var lash := float(p.get("lash", 0.0))
	for i in 6:
		var w := sin(tail_t * 2.6 - i * 0.7) * (0.12 + 0.04 * i) + lash * (0.25 + 0.06 * i)
		_rot("t%d" % i, Vector3(-0.08 + sin(tail_t * 1.7 - i) * 0.05 + float(p.get("tail_up", 0.0)) * (0.3 if i < 2 else 0.1), w, 0))
	for nm in nostrils:
		var f := 1.0 + float(p.get("flare", 0.0)) * 0.6
		(nm as Node3D).scale = Vector3(0.14 * f, 0.1 * f, 0.08)
	var t := Time.get_ticks_msec() * 0.001
	for i in mane.size():   # the smoke sways and breathes
		var m: Node3D = mane[i]
		m.rotation.z = sin(t * 0.9 + i) * 0.2


func _rot(bone: String, e: Vector3, off := Vector3.ZERO) -> void:
	var i: int = bi[bone]
	skel.set_bone_pose_rotation(i, Quaternion.from_euler(e))
	skel.set_bone_pose_position(i, rest[bone] + off)


func set_look(col: Color, hot: float, crack: float, flash: float) -> void:
	body_mat.set_shader_parameter("storm", col)
	body_mat.set_shader_parameter("hot", hot)
	body_mat.set_shader_parameter("crack", crack)
	body_mat.set_shader_parameter("flash", flash)
	stone_mat.set_shader_parameter("glow", col)
	stone_mat.set_shader_parameter("hot", hot)
	stone_mat.set_shader_parameter("crack", crack)
	for m in smoke_mats:
		(m as ShaderMaterial).set_shader_parameter("storm", col)
		(m as ShaderMaterial).set_shader_parameter("hot", hot * 0.5)
	for e in eyes:
		var em: StandardMaterial3D = (e as MeshInstance3D).material_override
		em.emission = col.lightened(0.3)
		em.albedo_color = col.lightened(0.5)


func tick_trails(delta: float, on: Dictionary, col: Color) -> void:
	for k in trails.keys():
		(trails[k] as Trail).step((anchors[k] as Node3D).global_position, float(on.get(k, 0.0)), col, delta)


func free_trails() -> void:
	for k in trails.keys():
		(trails[k] as Trail).mi.queue_free()
	trails.clear()


## A ribbon of glowing smoke behind a point: verlet points pulled after the anchor with inertia (cloth-like lag),
## drifting up a little and fanning out, drawn as a strip that faces the camera and fades toward the end.
class Trail:
	const N := 14
	var pts: Array = []
	var prev: Array = []
	var mi: MeshInstance3D
	var mesh: ImmediateMesh
	var width := 0.3
	var level := 0.0
	var seg := 0.35

	func _init(owner: Node3D, w: float) -> void:
		width = w
		mesh = ImmediateMesh.new()
		mi = MeshInstance3D.new()
		mi.mesh = mesh
		var m := ShaderMaterial.new()
		m.shader = BossModel._shader(BossModel.TRAIL_SHADER)
		mi.material_override = m
		mi.top_level = true
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 20.0
		owner.add_child(mi)

	func step(anchor: Vector3, want: float, col: Color, dt: float) -> void:
		level = move_toward(level, want, dt * (4.0 if want > level else 1.5))
		if pts.is_empty():
			for i in N:
				pts.append(anchor)
				prev.append(anchor)
		pts[0] = anchor
		prev[0] = anchor
		var t := Time.get_ticks_msec() * 0.001
		for i in range(1, N):
			var p: Vector3 = pts[i]
			var v: Vector3 = (p - (prev[i] as Vector3)) * 0.9   # inertia with drag
			prev[i] = p
			p += v + Vector3(sin(t * 3.0 + i) * 0.004, 0.012, cos(t * 2.3 + i * 1.3) * 0.004) * (dt * 60.0)
			pts[i] = p
		for _k in 2:   # keep the links' length (the cloth's lag)
			for i in range(1, N):
				var a: Vector3 = pts[i - 1]
				var b: Vector3 = pts[i]
				var d := b - a
				var l := d.length()
				if l > seg:
					pts[i] = a + d / l * seg
		mesh.clear_surfaces()
		if level < 0.02:
			return
		var cam := mi.get_viewport().get_camera_3d() if mi.is_inside_tree() else null
		if cam == null:
			return
		var eye := cam.global_position
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in N:
			var p: Vector3 = pts[i]
			var dir: Vector3 = ((pts[mini(i + 1, N - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3))
			if dir.length() < 1e-4:
				dir = Vector3.UP
			var side := dir.cross(eye - p).normalized()
			var k := 1.0 - float(i) / (N - 1)
			var w := width * (0.35 + 0.65 * k) * (1.0 + 0.6 * (1.0 - k))
			var c := Color(col.r, col.g, col.b, level * k * k)
			mesh.surface_set_color(c)
			mesh.surface_set_uv(Vector2(float(i) / (N - 1), 0.0))
			mesh.surface_add_vertex(p - side * w)
			mesh.surface_set_color(c)
			mesh.surface_set_uv(Vector2(float(i) / (N - 1), 1.0))
			mesh.surface_add_vertex(p + side * w)
		mesh.surface_end()
