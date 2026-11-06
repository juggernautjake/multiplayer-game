## Thunderhorn's body (v0.11.0, anatomy pass v0.12.0): a sculpted, skinned storm bull built in code, no model files.
##
## Skeleton (BONES, model space before the scale S, forward is -Z): a spine of hips (pelvis), loin, back, chest (the
## withers and shoulder hump), neck0, neck1, head and jaw; bovine legs: front s (scapula) -> u (shoulder joint) -> e
## (elbow) -> c (carpus, the "knee" that folds backwards) -> f (fetlock) -> h (hoof); hind u (hip) -> k (stifle) -> c
## (hock, the high reversed-looking joint) -> f (fetlock) -> h (hoof); eight tail bones t0..t7.
##
## One smooth body mesh lofted along the spine (a narrower rump and haunches, a deep barrel, the huge humped withers, a
## dewlap under the thick neck, a broad forehead, a heavy muzzle) through Catmull-Rom-smoothed cross sections with a
## keel (narrower underneath), a ridge (narrower on top), squarish super-ellipse sections and Gaussian muscle masses
## (shoulders, triceps, brisket, haunches, the neck crest, cheeks); a separate lower jaw (it really opens: a dark mouth,
## teeth, a tongue); the legs and the tail lofted along their joints. Every vertex is weighted to the bones.
##
## Legs are posed by procedural IK (apply(): `_leg_ik`): BossView gives each hoof a target (planted on the ground or
## swinging) plus how folded the leg is; the solver tilts the leg sideways (abduction), solves the upper two-bone
## triangle with a virtual lower bone whose length follows the carpus / hock fold, keeps the pastern at its standing
## angle to the ground and the hoof flat.
##
## On top (BoneAttachment3D): huge ridged, chipped, cracked horns sweeping out, up and forward with glowing tips and
## crack veins (HORN_SHADER), a smaller second pair below them, brow spikes; cloven obsidian hooves with dewclaws; a
## crest of spines on the hump; a spiked club at the tail's end. The face: glowing eyes with pupils that track the
## target, upper lids that narrow in anger and open wide in a roar, heavy brow ridges that furrow and lift, flaring
## nostrils, steam breath (breath()), fangs and teeth, a tongue. A mane of storm smoke.
##
## Shaders (cheap value-noise, no textures): HIDE_SHADER (storm-cloud hide, rim glow, fur, wet snout, scars, veins, a
## lightning skeleton, light cracking out when enraged); STONE_SHADER (polished obsidian with glowing veins); HORN_SHADER
## (weathered growth rings, scratches, chips, crack veins brightening in attacks, white-hot tips); SMOKE_SHADER (mane);
## STEAM_SHADER (breath).
##
## Trails (Trail): glowing ribbons streaming from his eyes, both pairs of horn tips, hooves and tail club; BossView lights
## each while that part attacks, in the attack's colour.
class_name BossModel
extends Node3D

const HIDE_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform vec4 storm : source_color = vec4(0.55, 0.75, 1.0, 1.0);
uniform float hot = 0.0;
uniform float crack = 0.0;
uniform float flash = 0.0;
uniform float detail = 0.0;
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
	float top = smoothstep(2.6, 6.0, lp.y) * (1.0 - detail);
	vec3 base = mix(vec3(0.018, 0.02, 0.032), vec3(0.15, 0.16, 0.22), clamp(pow(n, 1.6) * 1.8 - 0.15, 0.0, 1.0));
	base = mix(base, base * vec3(0.7, 0.75, 1.0) + vec3(0.02, 0.025, 0.04) * churn, 0.5);
	base *= mix(1.0, 0.5, smoothstep(4.6, 6.6, lp.y) * (1.0 - detail));                  // a darker back
	base *= mix(1.0, 0.55, smoothstep(3.4, 2.4, lp.y) * (1.0 - detail));                  // darker legs and belly
	float shag = smoothstep(-0.4, -2.4, lp.z) * smoothstep(3.4, 5.4, lp.y) * smoothstep(-4.2, -3.4, lp.z) * (1.0 - detail);
	float fur = vnoise(vec3(lp.x * 14.0, lp.y * 2.5 + lp.z * 1.5, lp.z * 14.0));
	base *= 1.0 + shag * (fur - 0.5) * 0.9;
	float curls = smoothstep(-3.5, -3.8, lp.z) * smoothstep(-4.4, -4.0, lp.z) * smoothstep(5.0, 5.4, lp.y);   // the forehead's curls
	base *= 1.0 + curls * (vnoise(lp * 18.0) - 0.5) * 0.8;
	float sc = abs(fract(dot(lp, vec3(0.55, 0.8, 0.25)) * 1.7) - 0.5);           // old scars
	float scar = smoothstep(0.03, 0.0, sc) * step(0.62, vnoise(lp * 1.3)) * (1.0 - shag) * (1.0 - detail);
	base = mix(base, vec3(0.32, 0.3, 0.36), scar * 0.6);
	float snout = smoothstep(-4.9, -5.5, lp.z) * (1.0 - detail);
	base = mix(base, vec3(0.03, 0.03, 0.04), snout * 0.7);
	float v = 1.0 - abs(fbm(lp * 1.5 + vec3(0.0, TIME * 0.05, 0.0)) * 2.0 - 1.0);
	float where = max(smoothstep(3.7, 2.7, lp.y), smoothstep(-0.3, -1.5, lp.z) * smoothstep(5.4, 4.2, lp.y) * smoothstep(-3.3, -2.6, lp.z));
	float vein = smoothstep(0.975, 0.997, v) * (0.15 + 0.85 * where) * (1.0 - detail);
	float pulse = 0.55 + 0.45 * sin(TIME * 3.0 + lp.z * 1.4);
	float ribs = pow(abs(sin(lp.z * 3.1)), 70.0) * step(0.55, vnoise(lp * 2.0 + vec3(0.0, TIME * 0.4, 0.0))) * smoothstep(1.6, -0.2, lp.z) * smoothstep(-2.6, -0.9, lp.z) * smoothstep(5.8, 3.4, lp.y) * smoothstep(2.4, 3.3, lp.y);
	float spine = smoothstep(0.22, 0.0, abs(lp.x)) * top;
	float skel = (ribs + spine) * (0.25 + 0.75 * pulse) * max(hot - 0.4, 0.0) * 0.45 * (1.0 - detail);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.6);
	ALBEDO = base;
	ROUGHNESS = mix(0.82, 0.15, snout);
	SPECULAR = mix(0.25, 0.9, snout);
	NORMAL = normalize(NORMAL + (vec3(n, churn, fur) - 0.5) * 0.35);
	float cracks = smoothstep(0.9, 0.98, v) * crack * (1.0 - detail);
	float h = min(hot, 1.4);
	EMISSION = storm.rgb * (fres * (0.18 + 0.45 * h) * (1.0 - detail * 0.7) + vein * (1.1 + 1.8 * h) * pulse + skel * 1.2 + cracks * 2.5)
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

## The horns: UV.x runs 0 at the skull to 1 at the tip. Weathered growth rings and scratches near the base, polished
## black toward the tip, dark-edged cracks with glowing veins in them (brighter with `hot`, the attacks, and `crack`, the
## rage), and white-hot glowing points.
const HORN_SHADER := """
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
	float u = UV.x;
	float n = vnoise(lp * 5.0) * 0.6 + vnoise(lp * 14.0) * 0.4;
	float rings = 0.5 + 0.5 * sin(u * 120.0 + n * 3.0);
	float wear = smoothstep(0.1, 0.8, u);
	vec3 base = mix(vec3(0.2, 0.18, 0.15), vec3(0.04, 0.04, 0.055), wear);
	base *= 0.7 + 0.45 * rings * (1.0 - wear * 0.8);
	float scratch = smoothstep(0.93, 1.0, vnoise(vec3(lp.x * 2.0 + lp.z * 2.0, lp.y * 30.0, lp.z * 3.0)));
	base += vec3(0.18, 0.17, 0.16) * scratch * (1.0 - wear * 0.6);
	float c = 1.0 - abs(vnoise(lp * 1.9 + vec3(7.3)) * 2.0 - 1.0);
	float c2 = 1.0 - abs(vnoise(lp * 6.0 + vec3(1.7)) * 2.0 - 1.0);
	float veins = smoothstep(0.968 - 0.03 * crack - 0.025 * hot, 0.997, c) + 0.6 * smoothstep(0.978 - 0.02 * hot, 0.999, c2);
	base *= 1.0 - 0.75 * smoothstep(0.9, 0.965, c);
	ALBEDO = base;
	METALLIC = 0.25;
	ROUGHNESS = mix(0.7, 0.14, wear);
	SPECULAR = 0.75;
	NORMAL = normalize(NORMAL + (vec3(n, rings, vnoise(lp * 9.0)) - 0.5) * 0.3);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float tip = smoothstep(0.78, 1.0, u);
	float pulse = 0.7 + 0.3 * sin(TIME * 6.0 - u * 14.0);
	EMISSION = glow.rgb * (veins * (0.35 + 3.0 * hot + 1.6 * crack) * pulse + tip * tip * (0.7 + 3.0 * hot) * pulse + fres * 0.2)
		+ vec3(1.0) * pow(tip, 6.0) * (0.6 + hot);
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

## Breath: soft round billboards of pale steam, fading with `fade`.
const STEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.86, 0.9, 1.0, 1.0);
uniform float fade = 0.0;
uniform float seed = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y); }
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	float r = length(UV - 0.5);
	float n = vn(UV * 3.0 + vec2(seed, -TIME * 0.8)) * 0.6 + vn(UV * 7.0 + vec2(-TIME, seed)) * 0.4;
	float a = smoothstep(0.5, 0.05, r) * smoothstep(0.15, 0.65, n + 0.15);
	ALBEDO = tint.rgb;
	ALPHA = clamp(a * fade, 0.0, 1.0);
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

const S := 0.85   # the whole model's scale (about 6 m to the hump: 3.5 players)
const HOOF_Y := 0.24   # the hoof bone's height over the sole

# bone: [name, parent, rest origin in model space (before S)]
const BONES := [
	["root", "", Vector3(0, 0, 0)],
	["hips", "root", Vector3(0, 4.45, 2.5)], ["loin", "hips", Vector3(0, 4.65, 1.2)], ["back", "loin", Vector3(0, 4.85, -0.1)],
	["chest", "back", Vector3(0, 5.05, -1.35)], ["neck0", "chest", Vector3(0, 5.05, -2.35)], ["neck1", "neck0", Vector3(0, 4.95, -3.0)],
	["head", "neck1", Vector3(0, 4.8, -3.6)], ["jaw", "head", Vector3(0, 4.3, -3.95)],
	["FLs", "chest", Vector3(-1.05, 5.5, -1.0)], ["FLu", "FLs", Vector3(-1.25, 3.95, -2.15)], ["FLe", "FLu", Vector3(-1.2, 2.85, -1.35)],
	["FLc", "FLe", Vector3(-1.15, 1.35, -1.6)], ["FLf", "FLc", Vector3(-1.15, 0.62, -1.62)], ["FLh", "FLf", Vector3(-1.15, 0.24, -1.9)],
	["FRs", "chest", Vector3(1.05, 5.5, -1.0)], ["FRu", "FRs", Vector3(1.25, 3.95, -2.15)], ["FRe", "FRu", Vector3(1.2, 2.85, -1.35)],
	["FRc", "FRe", Vector3(1.15, 1.35, -1.6)], ["FRf", "FRc", Vector3(1.15, 0.62, -1.62)], ["FRh", "FRf", Vector3(1.15, 0.24, -1.9)],
	["BLu", "hips", Vector3(-1.15, 4.35, 2.55)], ["BLk", "BLu", Vector3(-1.3, 2.95, 1.75)], ["BLc", "BLk", Vector3(-1.2, 1.8, 3.05)],
	["BLf", "BLc", Vector3(-1.15, 0.62, 2.85)], ["BLh", "BLf", Vector3(-1.15, 0.24, 2.6)],
	["BRu", "hips", Vector3(1.15, 4.35, 2.55)], ["BRk", "BRu", Vector3(1.3, 2.95, 1.75)], ["BRc", "BRk", Vector3(1.2, 1.8, 3.05)],
	["BRf", "BRc", Vector3(1.15, 0.62, 2.85)], ["BRh", "BRf", Vector3(1.15, 0.24, 2.6)],
	["t0", "hips", Vector3(0, 5.1, 3.7)], ["t1", "t0", Vector3(0, 5.0, 4.3)], ["t2", "t1", Vector3(0, 4.6, 4.85)],
	["t3", "t2", Vector3(0, 4.0, 5.2)], ["t4", "t3", Vector3(0, 3.35, 5.45)], ["t5", "t4", Vector3(0, 2.7, 5.6)],
	["t6", "t5", Vector3(0, 2.1, 5.68)], ["t7", "t6", Vector3(0, 1.6, 5.72)],
]
const LEGS := ["FL", "FR", "BL", "BR"]
const LEG_J := {"F": ["s", "u", "e", "c", "f", "h"], "B": ["u", "k", "c", "f", "h"]}
const TAIL_N := 8

# the trunk, rump to nose: [z, y, half width, height up, height down, keel (narrower underneath), ridge (narrower on top)]
const SECTIONS := [
	[3.98, 4.78, 0.3, 0.26, 0.3, 0.0, 0.0], [3.82, 4.72, 1.0, 0.6, 0.92, 0.1, 0.25],
	[3.45, 4.64, 1.52, 0.84, 1.32, 0.15, 0.28], [2.9, 4.56, 1.78, 0.98, 1.52, 0.15, 0.28],
	[2.3, 4.5, 1.84, 1.02, 1.6, 0.15, 0.22], [1.6, 4.45, 1.76, 1.05, 1.55, 0.1, 0.16],
	[0.8, 4.45, 1.9, 1.18, 1.6, 0.12, 0.16], [0.0, 4.5, 2.05, 1.36, 1.66, 0.16, 0.22],
	[-0.7, 4.6, 2.15, 1.78, 1.76, 0.2, 0.32], [-1.35, 4.65, 2.2, 2.42, 1.86, 0.26, 0.44],
	[-2.0, 4.6, 2.0, 2.26, 1.98, 0.42, 0.46], [-2.5, 4.6, 1.6, 1.7, 2.1, 0.72, 0.34],
	[-2.95, 4.66, 1.28, 1.2, 1.8, 0.8, 0.2], [-3.35, 4.76, 1.24, 1.02, 1.35, 0.62, 0.05],
	[-3.75, 4.84, 1.3, 0.88, 1.0, 0.18, 0.0], [-4.15, 4.74, 1.18, 0.74, 0.84, 0.1, 0.03],
	[-4.6, 4.56, 0.97, 0.6, 0.56, 0.08, 0.08], [-5.05, 4.44, 0.9, 0.5, 0.4, 0.0, 0.1],
	[-5.42, 4.38, 0.86, 0.46, 0.34, 0.0, 0.05], [-5.7, 4.35, 0.66, 0.36, 0.27, 0.0, 0.0], [-5.84, 4.34, 0.42, 0.22, 0.16, 0.0, 0.0],
]
# muscle masses: [centre (mirrored when x != 0), radius, height]
const BUMPS := [
	[Vector3(2.05, 4.3, -1.6), 0.95, 0.2], [Vector3(1.85, 3.35, -1.1), 0.6, 0.12], [Vector3(1.1, 3.1, -2.45), 0.65, 0.12],
	[Vector3(1.85, 4.4, 2.85), 1.0, 0.16], [Vector3(1.75, 3.4, 1.85), 0.6, 0.08], [Vector3(0.0, 6.6, -2.3), 0.75, 0.2],
	[Vector3(0.0, 7.05, -1.3), 0.8, 0.08], [Vector3(1.05, 4.4, -3.95), 0.45, 0.14], [Vector3(0.0, 5.6, -3.8), 0.55, 0.1], [Vector3(0.0, 2.6, -3.0), 0.5, 0.12],
	[Vector3(1.3, 5.6, -0.6), 0.8, 0.08], [Vector3(0.0, 2.7, -2.55), 0.45, 0.1],
]

var skel: Skeleton3D
var bi := {}                 # bone name -> index
var rest := {}               # bone name -> local rest origin
var parent := {}             # bone name -> parent name
var body_mat: ShaderMaterial
var detail_mat: ShaderMaterial   # the hide on small parts (brows, lids)
var stone_mat: ShaderMaterial
var horn_mat: ShaderMaterial
var smoke_mats: Array = []
var eyes: Array = []         # MeshInstance3D
var nostrils: Array = []
var anchors := {}            # trail points: "eye_l", "eye_r", "horn_l", "horn_r", "horn2_l", "horn2_r", "hoof_FL"..., "tail"
var points := {}             # other points: "nose_l", "nose_r", "mouth", "brow"
var trails := {}             # anchor key -> Trail
var mane: Array = []         # smoke billboards (for sway)
var look_target = null       # a world position his eyes follow (or null)
var _brows: Array = []       # [node, rest transform, side]
var _lids: Array = []
var _pupils: Array = []      # [node, eye centre (head space), side]
var _eye_c: Array = []
var _tongue: Node3D
var _puffs: Array = []
var _lx := {}                # bone -> local transform posed this frame
var _gx := {}                # bone -> model-space transform (cache)


func build() -> void:
	scale = Vector3.ONE * S
	skel = Skeleton3D.new()
	add_child(skel)
	for b in BONES:
		var i := skel.add_bone(b[0])
		bi[b[0]] = i
		parent[b[0]] = b[1]
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
	detail_mat = ShaderMaterial.new()
	detail_mat.shader = _shader(HIDE_SHADER)
	detail_mat.set_shader_parameter("detail", 1.0)
	stone_mat = ShaderMaterial.new()
	stone_mat.shader = _shader(STONE_SHADER)
	horn_mat = ShaderMaterial.new()
	horn_mat.shader = _shader(HORN_SHADER)
	var mi := MeshInstance3D.new()
	mi.mesh = _body_mesh()
	mi.material_override = body_mat
	skel.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = skel.create_skin_from_rest_transforms()
	_details()
	_puff_pool()


static var _shaders := {}


static func _shader(code: String) -> Shader:
	if not _shaders.has(code):
		var s := Shader.new()
		s.code = code
		_shaders[code] = s
	return _shaders[code]


static func _bone_origin(name: String) -> Vector3:
	for b in BONES:
		if b[0] == name:
			return b[2]
	return Vector3.ZERO


## Where a leg's hoof bone stands at rest (model space, before S): the gait's home for that foot.
static func foot_home(leg: String) -> Vector3:
	var h := _bone_origin(leg + "h")
	return Vector3(h.x, HOOF_Y, h.z)


# ================================================================ the mesh
var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedVector3Array()   # each vertex's ring centre (to point normals outward)
var _bo := PackedInt32Array()
var _we := PackedFloat32Array()
var _ix := PackedInt32Array()


func _body_mesh() -> ArrayMesh:
	var spine_b := [["hips", 2.5], ["loin", 1.2], ["back", -0.1], ["chest", -1.35], ["neck0", -2.35], ["neck1", -3.0], ["head", -3.6]]
	var cs := []
	var rs := []
	var ws := []
	var sh := []
	for s in SECTIONS:
		cs.append(Vector3(0, s[1], s[0]))
		rs.append(Vector3(s[2], s[3], s[4]))
		sh.append(Vector2(s[5], s[6]))
		ws.append(_chain_w(spine_b, float(s[0])))
	_loft(cs, rs, ws, 36, 3, Vector3.UP, "body", sh)
	# the lower jaw: its own tube under the muzzle, so the mouth really opens
	var jaw := [[-3.75, 4.17, 0.84, 0.2, 0.4], [-4.25, 4.1, 0.8, 0.16, 0.37], [-4.75, 4.04, 0.74, 0.14, 0.32],
		[-5.15, 4.0, 0.68, 0.13, 0.27], [-5.47, 3.99, 0.48, 0.11, 0.18]]
	cs = []
	rs = []
	ws = []
	sh = []
	for s in jaw:
		cs.append(Vector3(0, s[1], s[0]))
		rs.append(Vector3(s[2], s[3], s[4]))
		sh.append(Vector2(0.25, 0.0))
		ws.append([["jaw", 1.0]] if float(s[0]) < -3.9 else [["jaw", 0.6], ["head", 0.4]])
	_loft(cs, rs, ws, 20, 3, Vector3.UP, "jaw", sh)
	for leg in LEGS:
		_leg_mesh(leg)
	# the tail: thick at the root, hanging in an arc to a club
	var tc := [_bone_origin("t0") + Vector3(0, -0.15, -0.6)]
	var tr := [Vector3(0.62, 0.62, 0.62)]
	var tw := [[["hips", 1.0]]]
	for i in TAIL_N:
		tc.append(_bone_origin("t%d" % i))
		var r := lerpf(0.42, 0.12, float(i) / (TAIL_N - 1))
		tr.append(Vector3(r, r, r))
		tw.append([["t%d" % i, 1.0]] if i == 0 else [["t%d" % (i - 1), 0.35], ["t%d" % i, 0.65]])
	_loft(tc, tr, tw, 12, 3, Vector3.FORWARD, "tail")
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


## A leg's tube through its joints: [centre, radii (side, back, front), weights]; big muscle at the top (the shoulder
## and forearm in front, the thigh and gaskin behind), knobbly carpus, hock and fetlock, thin cannons.
func _leg_mesh(leg: String) -> void:
	var front := leg.begins_with("F")
	var pts := []
	var rad := []
	var w := []
	if front:
		var s := _bone_origin(leg + "s")
		var u := _bone_origin(leg + "u")
		var e := _bone_origin(leg + "e")
		var c := _bone_origin(leg + "c")
		var f := _bone_origin(leg + "f")
		var h := _bone_origin(leg + "h")
		pts = [s, s.lerp(u, 0.5) + Vector3(0, 0, -0.1), u, u.lerp(e, 0.5) + Vector3(0, 0, 0.1), e, e.lerp(c, 0.22),
			e.lerp(c, 0.62), c, c.lerp(f, 0.5), f, f.lerp(h, 0.55), h]
		rad = [Vector3(0.6, 0.65, 0.65), Vector3(0.85, 0.9, 0.9), Vector3(0.78, 0.75, 0.82), Vector3(0.74, 0.9, 0.66),
			Vector3(0.66, 0.78, 0.56), Vector3(0.66, 0.64, 0.7), Vector3(0.48, 0.46, 0.5), Vector3(0.38, 0.36, 0.4),
			Vector3(0.22, 0.21, 0.21), Vector3(0.28, 0.3, 0.26), Vector3(0.23, 0.23, 0.23), Vector3(0.25, 0.25, 0.26)]
		w = [[["chest", 0.4], [leg + "s", 0.6]], [[leg + "s", 1.0]], [[leg + "s", 0.35], [leg + "u", 0.65]], [[leg + "u", 1.0]],
			[[leg + "u", 0.5], [leg + "e", 0.5]], [[leg + "e", 1.0]], [[leg + "e", 1.0]], [[leg + "e", 0.5], [leg + "c", 0.5]],
			[[leg + "c", 1.0]], [[leg + "c", 0.5], [leg + "f", 0.5]], [[leg + "f", 1.0]], [[leg + "f", 0.4], [leg + "h", 0.6]]]
	else:
		var u := _bone_origin(leg + "u")
		var k := _bone_origin(leg + "k")
		var c := _bone_origin(leg + "c")
		var f := _bone_origin(leg + "f")
		var h := _bone_origin(leg + "h")
		pts = [u + Vector3(0, 0.7, 0.2), u, u.lerp(k, 0.5) + Vector3(0, 0, 0.3), k, k.lerp(c, 0.3) + Vector3(0, 0, 0.08),
			k.lerp(c, 0.7), c, c.lerp(f, 0.5), f, f.lerp(h, 0.55), h]
		rad = [Vector3(0.85, 0.9, 0.9), Vector3(1.0, 1.1, 0.95), Vector3(0.88, 1.05, 0.8), Vector3(0.6, 0.68, 0.66),
			Vector3(0.45, 0.6, 0.38), Vector3(0.31, 0.38, 0.27), Vector3(0.27, 0.36, 0.25), Vector3(0.22, 0.22, 0.21),
			Vector3(0.28, 0.29, 0.27), Vector3(0.23, 0.23, 0.23), Vector3(0.25, 0.25, 0.26)]
		w = [[["hips", 0.6], [leg + "u", 0.4]], [["hips", 0.3], [leg + "u", 0.7]], [[leg + "u", 1.0]], [[leg + "u", 0.5], [leg + "k", 0.5]],
			[[leg + "k", 1.0]], [[leg + "k", 1.0]], [[leg + "k", 0.5], [leg + "c", 0.5]], [[leg + "c", 1.0]],
			[[leg + "c", 0.5], [leg + "f", 0.5]], [[leg + "f", 1.0]], [[leg + "f", 0.4], [leg + "h", 0.6]]]
	_loft(pts, rad, w, 16, 3, Vector3.FORWARD, "leg")


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


## A smooth tube through centres cs with radii rs (x: half width, y: up / back, z: down / front), Catmull-Rom
## subdivided `sub` times between sections, `seg` around; the body and jaw get squarish sections, a keel and ridge
## (shape: Vector2(keel, ridge) per section) and muscle masses; capped at both ends; weights ws per section.
func _loft(cs: Array, rs: Array, ws: Array, seg: int, sub: int, ref: Vector3, kind: String, shape: Array = []) -> void:
	var rings := []   # [centre, radii, weights dict, shape]
	var n := cs.size()
	for i in n - 1:
		for k in sub:
			var t := float(k) / sub
			var p0: Vector3 = cs[maxi(i - 1, 0)]
			var p3: Vector3 = cs[mini(i + 2, n - 1)]
			var c: Vector3 = _cr(p0, cs[i], cs[i + 1], p3, t)
			var r: Vector3 = _cr(rs[maxi(i - 1, 0)], rs[i], rs[i + 1], rs[mini(i + 2, n - 1)], t)
			var shp := Vector2.ZERO
			if not shape.is_empty():
				shp = (shape[i] as Vector2).lerp(shape[i + 1], t)
			var wd := {}
			for e in ws[i]:
				wd[e[0]] = float(wd.get(e[0], 0.0)) + float(e[1]) * (1.0 - t)
			for e in ws[i + 1]:
				wd[e[0]] = float(wd.get(e[0], 0.0)) + float(e[1]) * t
			rings.append([c, r, wd, shp])
	rings.append([cs[n - 1], rs[n - 1], _wd(ws[n - 1]), Vector2.ZERO if shape.is_empty() else shape[n - 1]])
	var base := _v.size()
	var shaped := kind == "body" or kind == "jaw"
	for ri in rings.size():
		var c: Vector3 = rings[ri][0]
		var r: Vector3 = rings[ri][1]
		var shp: Vector2 = rings[ri][3]
		var tan: Vector3 = (rings[mini(ri + 1, rings.size() - 1)][0] - rings[maxi(ri - 1, 0)][0]).normalized()
		var rf := ref if absf(tan.dot(ref)) < 0.9 else Vector3.RIGHT
		var nx := rf.cross(tan).normalized()
		var by := tan.cross(nx).normalized()
		if kind == "leg":   # legs: x across the body, y back
			nx = Vector3.RIGHT
			by = tan.cross(nx).normalized()
		var s := float(ri) / rings.size()
		for j in seg:
			var a := TAU * j / seg
			var ca := cos(a)
			var sa := sin(a)
			var lump := 1.0
			var cx := ca
			var sy := sa
			var xs := 1.0
			if shaped:
				cx = signf(ca) * pow(absf(ca), 0.8)
				sy = signf(sa) * pow(absf(sa), 0.9)
				xs = 1.0 - shp.x * pow(maxf(-sa, 0.0), 1.5) - shp.y * maxf(sa, 0.0) * maxf(sa, 0.0)
				if kind == "body":
					lump = 1.0 + 0.02 * sin(3.0 * a + s * 9.0) + 0.015 * sin(5.0 * a - s * 13.0)
			elif kind == "leg":
				lump = 1.0 + 0.05 * sin(2.0 * a + s * 6.0) * (1.0 - s)
			var h := r.y if sa > 0.0 else r.z
			var p := c + nx * cx * r.x * lump * xs + by * sy * h * lump
			if kind == "body":
				p = _bump(p, c)
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
		var out: Vector3 = (c - (rings[1 if end == 0 else end - 1][0] as Vector3)).normalized()
		_add_v(c + out * 0.05, c - out, rings[end][2])
		for j in seg:
			_ix.append_array([ci, base + end * seg + j, base + end * seg + (j + 1) % seg])


func _bump(p: Vector3, c: Vector3) -> Vector3:
	var d := p - c
	if d.length() < 1e-4:
		return p
	var o := 0.0
	for b in BUMPS:
		var q: Vector3 = b[0]
		var r := float(b[1])
		for sx in ([1.0, -1.0] if q.x != 0.0 else [1.0]):
			o += float(b[2]) * exp(-p.distance_squared_to(Vector3(q.x * sx, q.y, q.z)) / (r * r))
	return p + d.normalized() * o


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


func _point(bone: String, at: Vector3) -> Node3D:
	var att := _attach(bone)
	var n := Node3D.new()
	n.position = at - _bone_origin(bone)
	att.add_child(n)
	return n


func _sphere(r := 0.5, h := 1.0, seg := 16, rings := 10) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = seg
	m.rings = rings
	return m


func _cone(r: float, h: float, seg := 8) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = r
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m


## A basis whose Y axis points along d (cones point along their Y).
static func _along(d: Vector3) -> Basis:
	var y := d.normalized()
	var ref: Vector3 = Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	return Basis(x, y, x.cross(y))


func _mat(c: Color, rough := 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _details() -> void:
	# ---- the horns: huge, thick at the skull, out, up and hooking forward to points; a smaller pair below
	for side: float in [-1.0, 1.0]:
		var sd := "l" if side < 0 else "r"
		var pts := [Vector3(0.5, 5.25, -3.6), Vector3(1.45, 5.5, -3.45), Vector3(2.5, 5.85, -3.35), Vector3(3.3, 6.5, -3.55),
			Vector3(3.65, 7.2, -4.25), Vector3(3.45, 7.55, -5.15), Vector3(2.95, 7.4, -5.95)]
		var tip := _horn(pts, [0.66, 0.6, 0.5, 0.38, 0.26, 0.14, 0.012], side, 7 if side < 0 else 13, 1.0)
		anchors["horn_" + sd] = tip
		var p2 := [Vector3(0.9, 4.98, -3.45), Vector3(1.5, 4.9, -3.4), Vector3(2.05, 4.75, -3.65), Vector3(2.25, 4.65, -4.15),
			Vector3(2.15, 4.7, -4.65)]
		anchors["horn2_" + sd] = _horn(p2, [0.27, 0.24, 0.17, 0.09, 0.01], side, 21 if side < 0 else 29, 0.5)
		# brow spikes along the ridge over the eye
		for i in 3:
			var at := Vector3((0.5 + 0.27 * i) * side, 5.45 - 0.04 * i, -4.02 + 0.05 * i)
			var dir := Vector3(0.45 * side, 1.0, -0.55 - 0.1 * i)
			_on("head", at + dir.normalized() * 0.18, _cone(0.075, 0.42 - 0.06 * i), stone_mat, _along(dir))
		# a heavy brow ridge (posed: it furrows and lifts), the eye under it, the upper lid, a pupil that looks
		var eye_c := Vector3(1.08 * side, 5.02, -4.18)
		_eye_c.append(eye_c)
		var bb := Basis(Vector3.BACK, 0.38 * side) * Basis.from_scale(Vector3(0.58, 0.2, 0.42))
		var brow := _on("head", Vector3(0.9 * side, 5.27, -4.16), _sphere(0.5, 1.0, 14, 8), detail_mat, bb)
		_brows.append([brow, brow.transform, side])
		var e := _on("head", eye_c, _sphere(0.5, 1.0, 14, 8), MagicFx._glow_mat(Color("cfe8ff"), 14.0), Basis.from_scale(Vector3(0.3, 0.22, 0.34)))
		eyes.append(e)
		anchors["eye_" + sd] = e
		var lb := Basis(Vector3.BACK, 0.3 * side) * Basis.from_scale(Vector3(0.32, 0.26, 0.38))
		var lid := _on("head", eye_c + Vector3(0.015 * side, 0.12, 0.0), _sphere(0.5, 1.0, 14, 8), detail_mat, lb)
		_lids.append([lid, lid.transform, side])
		var pm := _mat(Color("05060a"), 0.2)
		var pu := _on("head", eye_c, _sphere(0.5, 1.0, 10, 6), pm)
		_pupils.append([pu, eye_c - _bone_origin("head"), side])
		# flaring nostrils, steam comes out of them
		var nmat := _mat(Color("07070b"), 0.3)
		var nos := _on("head", Vector3(0.33 * side, 4.5, -5.74), _sphere(0.5, 1.0, 12, 8), nmat,
			Basis(Vector3.UP, -0.35 * side) * Basis.from_scale(Vector3(0.21, 0.15, 0.12)))
		nostrils.append(nos)
		points["nose_" + sd] = nos
	# the skewering spike out of the nose ridge, straight ahead along the snout (about 13 degrees up): a lance when his
	# head is down
	var sp := [Vector3(0, 4.85, -4.45), Vector3(0, 5.0, -5.05), Vector3(0, 5.15, -5.75), Vector3(0, 5.33, -6.55), Vector3(0, 5.55, -7.45)]
	anchors["spike"] = _horn(sp, [0.4, 0.33, 0.22, 0.11, 0.01], 1.0, 41, 0.8)
	points["mouth"] = _point("jaw", Vector3(0, 4.08, -5.3))
	points["brow"] = _point("head", Vector3(0, 5.2, -4.3))
	# ---- the mouth: a dark throat, teeth, fangs, a tongue
	_on("head", Vector3(0, 4.13, -4.6), _sphere(0.5, 1.0, 14, 8), _mat(Color("2a0a0e"), 0.6), Basis.from_scale(Vector3(1.2, 0.5, 1.7)))
	var tooth := _mat(Color("d9d4c4"), 0.35)
	var old := _mat(Color("a89f86"), 0.5)
	var molar := BoxMesh.new()
	molar.size = Vector3(0.13, 0.1, 0.15)
	var spade := BoxMesh.new()
	spade.size = Vector3(0.09, 0.15, 0.05)
	for side: float in [-1.0, 1.0]:
		for i in 4:   # grinding molars along both jaws
			var z := -4.35 - 0.17 * i
			_on("head", Vector3((0.62 - 0.03 * i) * side, 4.07, z), molar, old)
			_on("jaw", Vector3((0.6 - 0.03 * i) * side, 4.13, z), molar, old)
		for i in 3:   # spade incisors at the front of the lower jaw
			_on("jaw", Vector3((0.07 + 0.13 * i) * side, 4.12, -5.38 + 0.04 * i), spade, tooth, Basis(Vector3.RIGHT, -0.35))
		# a cracked fang at each corner of the mouth, and tusk-like lower fangs outside the lip, always showing
		_on("head", Vector3(0.7 * side, 4.12, -5.0), _cone(0.085, 0.4, 6), tooth, _along(Vector3(0.12 * side, -1, -0.15)))
		_on("jaw", Vector3(0.78 * side, 4.25, -4.95), _cone(0.09, 0.52, 6), tooth, _along(Vector3(0.25 * side, 1, -0.2)))
	_tongue = _on("jaw", Vector3(0, 4.1, -4.75), _sphere(0.5, 1.0, 12, 8), _mat(Color("6a2430"), 0.35), Basis.from_scale(Vector3(0.75, 0.2, 1.15)))
	# ---- a crest of spines on the hump and back
	for i in 7:
		var z := lerpf(-2.4, 1.2, float(i) / 6.0)
		var bone := "neck0" if z < -2.2 else ("chest" if z < -0.7 else ("back" if z < 0.5 else "loin"))
		var y := _top_y(z)
		var hgt := lerpf(1.0, 0.45, float(i) / 6.0)
		_on(bone, Vector3(0, y + hgt * 0.3 - 0.15, z), _cone(0.18, hgt), stone_mat, Basis(Vector3.RIGHT, -0.55))
	# ---- cloven hooves with dewclaws
	for leg in LEGS:
		var h := _bone_origin(leg + "h")
		var f := _bone_origin(leg + "f")
		for sx: float in [-1.0, 1.0]:
			var toe := CylinderMesh.new()
			toe.top_radius = 0.15
			toe.bottom_radius = 0.2
			toe.height = 0.36
			toe.radial_segments = 10
			toe.rings = 1
			_on(leg + "h", Vector3(h.x + 0.115 * sx, 0.18, h.z - 0.08), toe, stone_mat,
				Basis(Vector3.RIGHT, -0.22) * Basis.from_scale(Vector3(1.0, 1.0, 1.45)))
			_on(leg + "f", Vector3(f.x + 0.13 * sx, 0.5, f.z + 0.22), _cone(0.06, 0.18), stone_mat, _along(Vector3(0.1 * sx, -1, 0.6)))
		anchors["hoof_" + leg] = _point(leg + "h", Vector3(h.x, 0.05, h.z - 0.08))
	# ---- the tail's spiked club and a tuft of storm smoke
	var tail_end := _bone_origin("t7")
	var club := _on("t7", tail_end + Vector3(0, -0.25, 0.02), _sphere(), stone_mat, Basis.from_scale(Vector3(0.42, 0.55, 0.42)))
	anchors["tail"] = club
	for i in 6:
		var a := TAU * i / 6.0
		var d := Vector3(cos(a), -0.35, sin(a)).normalized()
		_on("t7", tail_end + Vector3(0, -0.25, 0.02) + d * 0.32, _cone(0.07, 0.4), stone_mat, _along(d))
	_on("t7", tail_end + Vector3(0, -0.6, 0), _cone(0.08, 0.45), stone_mat, _along(Vector3.DOWN))
	# ---- the mane of storm smoke over the neck and hump
	for i in 9:
		var z := lerpf(-3.3, -0.2, float(i) / 8.0)
		var bone := "neck1" if z < -2.9 else ("neck0" if z < -2.2 else "chest")
		var side := -1.0 if i % 2 == 0 else 1.0
		mane.append(_smoke(bone, Vector3(0.55 * side, _top_y(z) + 0.1, z), Vector2(2.0, 1.8), false))
	mane.append(_smoke("t7", tail_end + Vector3(0, -0.3, 0), Vector2(1.1, 1.1), false))
	# trails
	for k in anchors.keys():
		var w := 0.45
		if k.begins_with("eye"):
			w = 0.22
		elif k.begins_with("horn2") or k == "spike":
			w = 0.26
		elif k.begins_with("horn"):
			w = 0.34
		trails[k] = Trail.new(self, w)


## The body's top line at z (from SECTIONS).
func _top_y(z: float) -> float:
	for i in SECTIONS.size() - 1:
		var a: Array = SECTIONS[i]
		var b: Array = SECTIONS[i + 1]
		if z <= float(a[0]) and z >= float(b[0]):
			var k := (float(a[0]) - z) / (float(a[0]) - float(b[0]))
			return lerpf(float(a[1]) + float(a[3]), float(b[1]) + float(b[3]), k)
	return 5.0


## A horn on the head through pts (left side mirrored by `side`), its tip as a Node3D.
func _horn(pts: Array, radii: Array, side: float, seed: int, rough: float) -> Node3D:
	var mp := []
	for p in pts:
		mp.append(Vector3((p as Vector3).x * side, (p as Vector3).y, (p as Vector3).z))
	var mi := _on("head", Vector3.ZERO, _horn_mesh(mp, radii, 14, 44, seed, rough), horn_mat)
	var tip := Node3D.new()
	tip.position = mp[-1]
	mi.add_child(tip)
	return tip


## A rigid tapered horn tube with UVs (x along, y around): growth-ring ridges near the base, an oval section, chips
## knocked out of it, a long crack groove; parallel-transport frames so it doesn't twist.
func _horn_mesh(pts: Array, radii: Array, seg: int, steps: int, seed: int, rough: float) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var chips := []
	for i in int(5 * rough) + 1:
		chips.append([rng.randf_range(0.12, 0.85), rng.randf() * TAU, rng.randf_range(0.12, 0.3)])
	var groove_a := rng.randf() * TAU
	var groove_u := Vector2(rng.randf_range(0.1, 0.3), rng.randf_range(0.5, 0.75))
	var cs := []
	var rs := []
	for i in steps + 1:
		var u := float(i) / steps
		var x := u * (pts.size() - 1)
		var k := mini(int(x), pts.size() - 2)
		var f := x - k
		cs.append(_cr(pts[maxi(k - 1, 0)], pts[k], pts[k + 1], pts[mini(k + 2, pts.size() - 1)], f))
		rs.append(lerpf(float(radii[k]), float(radii[k + 1]), f))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := Vector3.ZERO
	for i in cs.size():
		var c: Vector3 = cs[i]
		var tan: Vector3 = ((cs[mini(i + 1, cs.size() - 1)] as Vector3) - (cs[maxi(i - 1, 0)] as Vector3)).normalized()
		if i == 0:
			nx = Vector3.UP.cross(tan).normalized()
		else:
			nx = (nx - tan * nx.dot(tan)).normalized()
		var by := tan.cross(nx).normalized()
		var u := float(i) / steps
		var ridge := 1.0 + 0.08 * pow(maxf(sin(u * 70.0), 0.0), 4.0) * (1.0 - smoothstep(0.45, 0.8, u))
		for j in seg + 1:
			var a := TAU * float(j) / seg
			var r := float(rs[i]) * ridge
			for ch in chips:
				r *= 1.0 - float(ch[2]) * exp(-pow((u - float(ch[0])) / 0.035, 2.0)) * pow(maxf(cos(a - float(ch[1])), 0.0), 6.0)
			if u > groove_u.x and u < groove_u.y:
				r *= 1.0 - 0.07 * pow(maxf(cos(a - groove_a), 0.0), 60.0)
			var d := nx * cos(a) + by * sin(a) * 0.82
			st.set_uv(Vector2(u, float(j) / seg))
			st.add_vertex(c + d * r)
	for i in cs.size() - 1:
		for j in seg:
			var a := i * (seg + 1) + j
			var b := a + 1
			var c2 := a + seg + 1
			var d2 := c2 + 1
			for q in [a, c2, b, b, c2, d2]:
				st.add_index(q)
	st.generate_normals()
	return st.commit()


func _smoke(bone: String, at: Vector3, size: Vector2, hang: bool) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var m := ShaderMaterial.new()
	m.shader = _shader(SMOKE_SHADER)
	m.set_shader_parameter("seed", randf() * 30.0)
	m.set_shader_parameter("yb", 1.0 if hang else 0.0)
	smoke_mats.append(m)
	var mi := _on(bone, at, q, m)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if hang:
		mi.position.y -= size.y * 0.5
	return mi


# ================================================================ steam breath
func _puff_pool() -> void:
	for i in 20:
		var q := QuadMesh.new()
		var m := ShaderMaterial.new()
		m.shader = _shader(STEAM_SHADER)
		m.set_shader_parameter("seed", randf() * 20.0)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.top_level = true
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_puffs.append({"mi": mi, "m": m, "v": Vector3.ZERO, "age": 1.0, "life": 1.0, "size": 1.0})


## A breath of steam: from the nostrils (a snort when k is near 1), or a gust from the open mouth.
func breath(k: float, mouth := false) -> void:
	if not is_inside_tree():
		return
	var hw := _head_world()
	var fwd := -hw.basis.z.normalized()
	var dn := -hw.basis.y.normalized()
	var srcs: Array = [points["mouth"]] if mouth else [points["nose_l"], points["nose_r"]]
	for s in srcs:
		for j in (3 if mouth else (2 if k > 0.6 else 1)):
			var p: Dictionary = _puffs[0]
			for q in _puffs:   # the oldest one
				if float(q.age) / float(q.life) > float(p.age) / float(p.life):
					p = q
			var mi: MeshInstance3D = p.mi
			mi.visible = true
			mi.global_position = (s as Node3D).global_position
			var side := hw.basis.x.normalized() * (randf_range(-0.6, 0.6) + (0.5 if s == points.get("nose_r") else (-0.5 if s == points.get("nose_l") else 0.0)))
			p.v = (fwd * (2.5 + 4.5 * k) + dn * (1.2 if not mouth else 0.4) + side) * S + Vector3(randf_range(-0.4, 0.4), randf_range(-0.2, 0.3), randf_range(-0.4, 0.4))
			p.age = 0.0
			p.life = randf_range(0.8, 1.3) * (0.8 + 0.7 * k)
			p.size = (0.35 + 0.45 * k + (0.4 if mouth else 0.0)) * S


func _tick_puffs(dt: float) -> void:
	for p in _puffs:
		var mi: MeshInstance3D = p.mi
		if float(p.age) >= float(p.life):
			mi.visible = false
			continue
		p.age = float(p.age) + dt
		var v: Vector3 = p.v
		v *= pow(0.15, dt)
		v.y += 0.9 * dt
		p.v = v
		mi.global_position += v * dt
		var k := float(p.age) / float(p.life)
		mi.scale = Vector3.ONE * float(p.size) * (1.0 + 2.8 * k)
		(p.m as ShaderMaterial).set_shader_parameter("fade", (1.0 - k) * (1.0 - k) * 0.55 * minf(1.0, float(p.age) * 12.0))


# ================================================================ posing
## Pose him. p: angles (radians) and offsets, missing ones 0: pitch, crouch, bob, surge, roll, twist, bend, arch,
## hump_roll, head_dip, head_up, head_yaw, thrash, jaw, lash, tail_up, flare, brow (-1 furrowed .. 1 lifted), lid (0 wide
## .. 1 shut), tongue. legs: per leg (FL, FR, BL, BR) a Dictionary: "t" a hoof target in model space (before S) and/or
## "rel" an offset from the leg's root in the model's axes, blended in by "k"; "flex" (0..~1.8: how folded the carpus /
## hock is) and "curl" (the hoof flipping back in the swing).
func apply(p: Dictionary, legs: Array, tail_t: float, delta: float) -> void:
	_gx.clear()
	var pitch := float(p.get("pitch", 0.0))
	var crouch := float(p.get("crouch", 0.0))
	var roll := float(p.get("roll", 0.0))
	var bend := float(p.get("bend", 0.0))
	var arch := float(p.get("arch", 0.0))
	var hr := float(p.get("hump_roll", 0.0))
	_rot("hips", Vector3(pitch, float(p.get("twist", 0.0)) * 0.4, roll), Vector3(0, -crouch + float(p.get("bob", 0.0)), float(p.get("surge", 0.0))))
	_rot("loin", Vector3(-pitch * 0.08 + arch * 0.5, bend * 0.25 - float(p.get("twist", 0.0)) * 0.2, roll * 0.2))
	_rot("back", Vector3(-pitch * 0.07 + arch * 0.5, bend * 0.3, roll * 0.15 + hr * 0.5))
	_rot("chest", Vector3(arch * 0.3, bend * 0.3, hr))
	var hd := float(p.get("head_dip", 0.0))
	var hu := float(p.get("head_up", 0.0))
	var hy := float(p.get("head_yaw", 0.0))
	var th := float(p.get("thrash", 0.0))
	var nod := hu - hd
	_rot("neck0", Vector3(nod * 0.3 - pitch * 0.25, hy * 0.3 + bend * 0.2, -hr * 0.6))
	_rot("neck1", Vector3(nod * 0.3, hy * 0.3, th * 0.3))
	_rot("head", Vector3(nod * 0.45, hy * 0.4, th))
	_rot("jaw", Vector3(-float(p.get("jaw", 0.05)), 0, 0))
	# the tail: a wave down it, the lash's whip, lifted for the lash
	var lash := float(p.get("lash", 0.0))
	var tu := float(p.get("tail_up", 0.0))
	for i in TAIL_N:
		var b := "t%d" % i
		var d: Vector3 = rest["t%d" % (i + 1)] if i < TAIL_N - 1 else rest[b]
		var ax := d.cross(Vector3.RIGHT).normalized()
		var w := sin(tail_t * 2.4 - i * 0.6) * (0.05 + 0.025 * i) + lash * (0.12 + 0.045 * i) + bend * 0.1
		var lift := 0.04 * sin(tail_t * 1.5 - i) - tu * (0.4 if i < 3 else 0.12)
		_pose_bone(b, Basis(ax, w) * Basis(Vector3.RIGHT, lift))
	for i in 4:
		_leg_ik(LEGS[i], legs[i] if i < legs.size() else {})
	_face(p, delta)
	var t := Time.get_ticks_msec() * 0.001
	for i in mane.size():   # the smoke sways and breathes
		var m: Node3D = mane[i]
		m.rotation.z = sin(t * 0.9 + i) * 0.2
	_tick_puffs(delta)


func _rot(bone: String, e: Vector3, off := Vector3.ZERO) -> void:
	_pose_bone(bone, Basis.from_euler(e), off)


func _pose_bone(bone: String, b: Basis, off := Vector3.ZERO) -> void:
	var i: int = bi[bone]
	var q := b.get_rotation_quaternion()
	skel.set_bone_pose_rotation(i, q)
	skel.set_bone_pose_position(i, rest[bone] + off)
	_lx[bone] = Transform3D(Basis(q), rest[bone] + off)
	_gx.clear()


## A bone's posed transform in model space (before S).
func _g(bone: String) -> Transform3D:
	if bone == "":
		return Transform3D.IDENTITY
	if _gx.has(bone):
		return _gx[bone]
	var t: Transform3D = _g(parent[bone]) * (_lx.get(bone, Transform3D(Basis.IDENTITY, rest[bone])) as Transform3D)
	_gx[bone] = t
	return t


func _head_world() -> Transform3D:
	return skel.global_transform * _g("head")


static func _a2(v: Vector3) -> float:   # a vector's angle in the leg's plane (rotation about X)
	return atan2(v.z, v.y)


## Procedural leg IK (see the header).
func _leg_ik(leg: String, spec: Dictionary) -> void:
	var front := leg.begins_with("F")
	var js: Array = LEG_J["F" if front else "B"]
	var o := 1 if front else 0
	var b0: String = leg + js[o]
	var b1: String = leg + js[o + 1]
	var b2: String = leg + js[o + 2]
	var b3: String = leg + js[o + 3]
	var b4: String = leg + js[o + 4]
	var home := foot_home(leg)
	var tgt: Vector3 = spec.get("t", home)
	var flex := float(spec.get("flex", 0.0))
	var curl := float(spec.get("curl", 0.0))
	if front:   # the shoulder blade swings with the leg
		var sc := clampf((home.z - tgt.z) * 0.1, -0.25, 0.25) if not spec.has("rel") else clampf(-float((spec.rel as Vector3).z) * 0.12, -0.3, 0.3)
		_rot(leg + "s", Vector3(sc, 0, 0))
	var pg := _g(parent[b0])
	var P: Vector3 = rest[b0]
	var T: Vector3 = pg.affine_inverse() * tgt
	if spec.has("rel"):
		var rt := P + pg.basis.orthonormalized().inverse() * (spec.rel as Vector3)   # rel: in the model's axes
		T = T.lerp(rt, clampf(float(spec.get("k", 1.0)), 0.0, 1.0))
	var A0: Vector3 = rest[b1]
	var B0: Vector3 = rest[b2]
	var C0: Vector3 = rest[b3]
	var D0: Vector3 = rest[b4]
	# abduction: the hoof's sideways offset becomes a tilt about Z; the rest is solved in that tilted plane
	var dx := (T.x - P.x) - (A0.x + B0.x + C0.x + D0.x)
	var psi := clampf(atan2(dx, maxf(P.y - T.y, 0.5)), -0.5, 0.5)
	var rz := Basis(Vector3.BACK, psi)
	var Tl := P + rz.inverse() * (T - P)
	var down := (pg.basis.orthonormalized() * rz).inverse() * Vector3.DOWN
	var g := wrapf(_a2(down) - PI, -PI, PI)   # the ground's tilt in this plane
	var ang_pa := _a2(D0) + g - curl
	var ft := Vector2(Tl.y, Tl.z) - Vector2(cos(ang_pa), sin(ang_pa)) * Vector2(D0.y, D0.z).length()
	var la := Vector2(A0.y, A0.z).length()
	var lb := Vector2(B0.y, B0.z).length()
	var lc := Vector2(C0.y, C0.z).length()
	var d0 := wrapf(_a2(C0) - _a2(B0), -PI, PI)
	var dl := d0 + (-1.0 if front else 1.0) * flex
	var lv := sqrt(maxf(lb * lb + lc * lc + 2.0 * lb * lc * cos(dl), 1e-4))
	var phi := atan2(lc * sin(dl), lb + lc * cos(dl))
	var p2 := Vector2(P.y, P.z)
	var pf := ft - p2
	var d := clampf(pf.length(), absf(la - lv) + 0.01, la + lv - 0.01)
	var alpha := acos(clampf((la * la + d * d - lv * lv) / (2.0 * la * d), -1.0, 1.0))
	var s1 := signf(wrapf(_a2(A0) - _a2(A0 + B0 + C0), -PI, PI))
	var ang_a := atan2(pf.y, pf.x) + s1 * alpha
	var k2 := p2 + Vector2(cos(ang_a), sin(ang_a)) * la
	var kf := ft - k2
	var ang_b := atan2(kf.y, kf.x) - phi
	var ang_c := ang_b + dl
	var th0 := ang_a - _a2(A0)
	var th1 := ang_b - _a2(B0) - th0
	var th2 := ang_c - _a2(C0) - th0 - th1
	var th3 := ang_pa - _a2(D0) - th0 - th1 - th2
	var th4 := g - curl * 0.7 - (th0 + th1 + th2 + th3)
	_pose_bone(b0, rz * Basis(Vector3.RIGHT, wrapf(th0, -PI, PI)))
	_pose_bone(b1, Basis(Vector3.RIGHT, wrapf(th1, -PI, PI)))
	_pose_bone(b2, Basis(Vector3.RIGHT, wrapf(th2, -PI, PI)))
	_pose_bone(b3, Basis(Vector3.RIGHT, wrapf(th3, -PI, PI)))
	_pose_bone(b4, Basis(Vector3.RIGHT, wrapf(th4, -PI, PI)))


var _blink := 0.0
var _blink_t := 3.0


## Brows, lids, pupils, nostrils, tongue.
func _face(p: Dictionary, delta: float) -> void:
	var brow := clampf(float(p.get("brow", 0.0)), -1.0, 1.0)
	var lid := clampf(float(p.get("lid", 0.3)), 0.0, 1.0)
	_blink_t -= delta
	if _blink_t <= 0.0:
		_blink_t = randf_range(2.5, 6.0)
		_blink = 0.14
	if _blink > 0.0:
		_blink -= delta
		lid = 1.0
	for b in _brows:
		var n: Node3D = b[0]
		var r: Transform3D = b[1]
		var side := float(b[2])
		# furrowed (brow < 0): the inner ends drop and come forward; lifted: up and level
		var tilt := Basis(Vector3.BACK, (-brow * 0.28) * side)
		n.transform = Transform3D(tilt * r.basis, r.origin + Vector3(0, 0.1 * brow, -0.05 * minf(brow, 0.0)))
	for l in _lids:
		var n: Node3D = l[0]
		var r: Transform3D = l[1]
		var side := float(l[2])
		var tilt := Basis(Vector3.BACK, (0.25 * lid - 0.1 * maxf(brow, 0.0)) * side)
		n.transform = Transform3D(tilt * r.basis, r.origin + Vector3(0, -0.13 * lid + 0.05 * maxf(brow, 0.0), 0))
	# the pupils look at the target (or ahead)
	var hw := _head_world()
	for pe in _pupils:
		var n: Node3D = pe[0]
		var ec: Vector3 = pe[1]
		var side := float(pe[2])
		var out := Vector3(side, 0.05, -0.75).normalized()
		var dir := out
		if look_target != null:
			var tl: Vector3 = hw.affine_inverse() * (look_target as Vector3)
			dir = (tl - ec).normalized()
			var ang := out.angle_to(dir)
			if ang > 0.75:
				dir = out.slerp(dir, 0.75 / ang).normalized()
		var bs := Basis.looking_at(dir, Vector3.UP) * Basis.from_scale(Vector3(0.075, 0.045, 0.03))
		n.transform = Transform3D(bs, ec + Vector3(dir.x * 0.15, dir.y * 0.11, dir.z * 0.17))
	var f := 1.0 + float(p.get("flare", 0.0)) * 0.7
	for i in nostrils.size():
		var side := -1.0 if i == 0 else 1.0
		(nostrils[i] as Node3D).basis = Basis(Vector3.UP, -0.35 * side) * Basis.from_scale(Vector3(0.21 * f, 0.15 * f, 0.12))
	var tg := float(p.get("tongue", 0.0))
	var t := Time.get_ticks_msec() * 0.001
	_tongue.basis = Basis(Vector3.RIGHT, -0.35 * tg + sin(t * 14.0) * 0.08 * tg) * Basis.from_scale(Vector3(0.75, 0.2, 1.15))


func set_look(col: Color, hot: float, crack: float, flash: float) -> void:
	body_mat.set_shader_parameter("storm", col)
	body_mat.set_shader_parameter("hot", hot)
	body_mat.set_shader_parameter("crack", crack)
	body_mat.set_shader_parameter("flash", flash)
	detail_mat.set_shader_parameter("storm", col)
	detail_mat.set_shader_parameter("flash", flash)
	stone_mat.set_shader_parameter("glow", col)
	stone_mat.set_shader_parameter("hot", hot)
	stone_mat.set_shader_parameter("crack", crack)
	horn_mat.set_shader_parameter("glow", col)
	horn_mat.set_shader_parameter("hot", hot)
	horn_mat.set_shader_parameter("crack", crack)
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
