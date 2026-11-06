## v0.12.2 Simple procedural icons for the HUD: every staff and wand spell, every weapon and every golem order, each a
## few lines, circles and polygons in a unit square (x and y from -1 to 1, y down). The same glyph draws on a 2D
## CanvasItem (the spell hotbar and the radial wheels: `draw`) and rasterises into a small texture for 3D (the order
## icon over golems: `texture`), so the two always match.
##
## A glyph is a list of commands:
##   ["l", points, width, colour]           a polyline
##   ["c", centre, radius, colour]          a filled circle
##   ["r", centre, radius, width, colour]   a ring
##   ["p", points, colour]                  a filled polygon
class_name Icons

const GOLD := Color("ffd86a")

static var _cache := {}
static var _tex := {}


static func _pts(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, a.size(), 2):
		out.append(Vector2(a[i], a[i + 1]))
	return out


static func _arc(c: Vector2, r: float, a0: float, a1: float, n := 16) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


static func _star(c: Vector2, r_out: float, r_in: float, points := 5, rot := -PI / 2.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points * 2:
		var a := rot + PI * i / points
		out.append(c + Vector2(cos(a), sin(a)) * (r_out if i % 2 == 0 else r_in))
	return out


## The glyph for a key: a spell name ("Fireball"), "w:<weapon index>" or "o:<order name>".
static func glyph(key: String) -> Array:
	if _cache.has(key):
		return _cache[key]
	var g := _make(key)
	_cache[key] = g
	return g


static func _make(key: String) -> Array:
	match key:
		# ---------------------------------------------------------------- the staff
		"Lightning":
			return [["p", _pts([0.25, -0.95, -0.45, 0.1, -0.02, 0.1, -0.3, 0.95, 0.5, -0.2, 0.06, -0.2, 0.4, -0.95]), Color("ffe14d")],
				["l", _pts([0.25, -0.95, -0.45, 0.1, -0.02, 0.1, -0.3, 0.95]), 0.06, Color("fff8c8")]]
		"Fireball":
			return [["p", _pts([0.05, -0.55, 0.85, -0.85, 0.55, -0.05, 0.85, 0.15, 0.35, 0.3]), Color("ff7a1a")],
				["c", Vector2(-0.12, 0.2), 0.58, Color("ff5a1a")],
				["c", Vector2(-0.18, 0.26), 0.36, Color("ffb02e")],
				["c", Vector2(-0.22, 0.3), 0.17, Color("fff2a8")]]
		"Shield":
			return [["p", _pts([0.0, -0.9, 0.75, -0.6, 0.65, 0.25, 0.0, 0.92, -0.65, 0.25, -0.75, -0.6]), Color("3d7fd9")],
				["l", _pts([0.0, -0.9, 0.75, -0.6, 0.65, 0.25, 0.0, 0.92, -0.65, 0.25, -0.75, -0.6, 0.0, -0.9]), 0.1, Color("bfe0ff")],
				["l", _pts([0.0, -0.6, 0.0, 0.6]), 0.1, Color("bfe0ff")]]
		"Frost Nova":
			var out := [["r", Vector2.ZERO, 0.82, 0.08, Color("7fdcff", 0.7)]]
			for k in 3:
				var a := PI * k / 3.0 + PI / 2.0
				var d := Vector2(cos(a), sin(a))
				out.append(["l", PackedVector2Array([-d * 0.7, d * 0.7]), 0.12, Color("d8f6ff")])
				for s: float in [-1.0, 1.0]:
					var tip: Vector2 = d * 0.45 * s
					var back: Vector2 = d * 0.68 * s
					var n := Vector2(-d.y, d.x) * 0.18
					out.append(["l", PackedVector2Array([back + n, tip, back - n]), 0.08, Color("d8f6ff")])
			return out
		"Meteor":
			return [["l", _pts([-0.9, -0.9, 0.1, 0.1]), 0.2, Color("ff9a3a", 0.6)],
				["l", _pts([-0.55, -0.95, 0.3, -0.1]), 0.12, Color("ffd060", 0.6)],
				["l", _pts([-0.95, -0.5, -0.1, 0.3]), 0.12, Color("ffd060", 0.6)],
				["c", Vector2(0.28, 0.3), 0.52, Color("ff6a1a")],
				["c", Vector2(0.32, 0.34), 0.42, Color("6a3a2a")],
				["c", Vector2(0.2, 0.2), 0.1, Color("3a2018")], ["c", Vector2(0.45, 0.45), 0.08, Color("3a2018")]]
		"Heal Aura":
			return [["r", Vector2.ZERO, 0.8, 0.1, Color("8affb0", 0.7)],
				["l", _pts([0.0, -0.55, 0.0, 0.55]), 0.36, Color("4fe07a")],
				["l", _pts([-0.55, 0.0, 0.55, 0.0]), 0.36, Color("4fe07a")],
				["l", _pts([0.0, -0.45, 0.0, 0.45]), 0.12, Color("d8ffe2")],
				["l", _pts([-0.45, 0.0, 0.45, 0.0]), 0.12, Color("d8ffe2")]]
		"Arcane Storm":
			return [["c", Vector2(-0.4, -0.25), 0.36, Color("6a4aa8")], ["c", Vector2(0.05, -0.45), 0.45, Color("7a58c0")],
				["c", Vector2(0.45, -0.2), 0.36, Color("6a4aa8")], ["p", _pts([-0.75, -0.2, 0.8, -0.2, 0.7, 0.05, -0.65, 0.05]), Color("5a3e98")],
				["p", _pts([0.05, 0.0, -0.3, 0.5, -0.05, 0.5, -0.2, 0.95, 0.3, 0.35, 0.05, 0.35, 0.25, 0.0]), Color("e6c8ff")],
				["p", _pts([-0.55, 0.15, -0.68, 0.45, -0.55, 0.45, -0.62, 0.7, -0.4, 0.38, -0.5, 0.38, -0.4, 0.15]), Color("c8a8ff")]]
		# ---------------------------------------------------------------- the wand
		"Spark Beam":
			return [["l", _pts([-0.9, 0.75, 0.55, -0.5]), 0.26, Color("5ad8ff", 0.45)],
				["l", _pts([-0.9, 0.75, 0.55, -0.5]), 0.1, Color("e8fbff")],
				["p", _star(Vector2(0.6, -0.55), 0.42, 0.14, 4, 0.0), Color("bff2ff")]]
		"Golem":
			return _golem(Color("8a857c"), Color("ffb02e"), 1.0)
		"Stone Titan":
			var t := _golem(Color("5d5a55"), Color("ff3a1a"), 1.15)
			t.append(["p", _pts([-0.32, -0.92, -0.2, -0.72, -0.08, -0.95, 0.04, -0.72, 0.16, -0.95, 0.28, -0.72, 0.36, -0.92, 0.36, -0.66, -0.32, -0.66]), GOLD])
			return t
		"Teleport":
			return [["r", Vector2(-0.5, 0.35), 0.32, 0.1, Color("b070ff", 0.55)],
				["r", Vector2(0.5, -0.35), 0.36, 0.12, Color("d8b0ff")],
				["c", Vector2(0.5, -0.35), 0.16, Color("f4e8ff")],
				["l", _pts([-0.3, 0.2, 0.18, -0.15]), 0.1, Color("e6d0ff")],
				["p", _pts([0.28, -0.24, 0.02, -0.3, 0.16, -0.02]), Color("e6d0ff")]]
		"Stun":
			return [["r", Vector2.ZERO, 0.85, 0.08, Color("ffe14d", 0.55)],
				["p", _star(Vector2.ZERO, 0.7, 0.3), Color("ffe14d")],
				["c", Vector2.ZERO, 0.16, Color("fff8d0")]]
		"Fog":
			return [["c", Vector2(-0.45, 0.1), 0.38, Color("9aa3ad")], ["c", Vector2(0.0, -0.15), 0.48, Color("b8c0c8")],
				["c", Vector2(0.45, 0.1), 0.38, Color("a8b0ba")], ["p", _pts([-0.8, 0.1, 0.8, 0.1, 0.8, 0.45, -0.8, 0.45]), Color("a8b0ba")],
				["l", _pts([-0.85, 0.65, 0.5, 0.65]), 0.1, Color("d0d6dc", 0.8)], ["l", _pts([-0.4, 0.85, 0.85, 0.85]), 0.1, Color("d0d6dc", 0.6)]]
		"Life Drain":
			var drop := _arc(Vector2(0, 0.25), 0.55, -0.15, PI + 0.15, 18)
			drop.append(Vector2(0, -0.9))
			return [["p", drop, Color("c0203a")], ["c", Vector2(-0.18, 0.3), 0.14, Color("ff8a9a")],
				["l", _pts([-0.85, -0.55, -0.5, -0.3]), 0.08, Color("ff5a6a", 0.7)], ["l", _pts([0.85, -0.55, 0.5, -0.3]), 0.08, Color("ff5a6a", 0.7)]]
		"Gravity Well":
			var sp := PackedVector2Array()
			for i in 48:
				var u := float(i) / 47.0
				var a := u * TAU * 2.2
				sp.append(Vector2(cos(a), sin(a)) * (0.08 + 0.8 * u))
			return [["c", Vector2.ZERO, 0.85, Color("2a1a48", 0.6)], ["l", sp, 0.11, Color("b070ff")], ["c", Vector2.ZERO, 0.16, Color("e6c8ff")]]
		# ---------------------------------------------------------------- weapons ("w:<index>")
		"w:0":   # fists
			return [["c", Vector2(0, 0.1), 0.55, Color("e0b090")], ["l", _pts([-0.35, -0.2, -0.35, 0.25]), 0.06, Color("8a6040")],
				["l", _pts([0.0, -0.3, 0.0, 0.25]), 0.06, Color("8a6040")], ["l", _pts([0.35, -0.2, 0.35, 0.25]), 0.06, Color("8a6040")],
				["p", _pts([-0.4, 0.55, 0.4, 0.55, 0.3, 0.95, -0.3, 0.95]), Color("c08868")]]
		"w:1":   # club
			return [["l", _pts([-0.7, 0.8, 0.1, -0.1]), 0.2, Color("8a5a32")], ["c", Vector2(0.35, -0.38), 0.45, Color("7a5232")],
				["c", Vector2(0.2, -0.5), 0.09, Color("5a3a22")], ["c", Vector2(0.5, -0.25), 0.08, Color("5a3a22")]]
		"w:2":   # sword
			return [["p", _pts([0.85, -0.85, 0.7, -0.45, -0.25, 0.5, -0.45, 0.3, 0.45, -0.7]), Color("d8dde8")],
				["l", _pts([-0.55, 0.15, -0.15, 0.55]), 0.14, GOLD], ["l", _pts([-0.35, 0.35, -0.8, 0.8]), 0.14, Color("6a4a2a")]]
		"w:3":   # bow
			return [["l", _arc(Vector2(-0.55, 0.0), 1.0, -1.1, 1.1, 20), 0.14, Color("9a6a3a")], ["l", _pts([-0.1, -0.9, -0.1, 0.9]), 0.04, Color("f0f0f0")],
				["l", _pts([-0.1, 0.0, 0.95, 0.0]), 0.06, Color("d0c0a0")], ["p", _pts([0.95, 0.0, 0.7, -0.14, 0.7, 0.14]), Color("c0c8d0")]]
		"w:4":   # slingshot
			return [["l", _pts([0.0, 0.95, 0.0, 0.15, -0.55, -0.7]), 0.16, Color("8a5a32")], ["l", _pts([0.0, 0.15, 0.55, -0.7]), 0.16, Color("8a5a32")],
				["l", _pts([-0.55, -0.7, 0.0, -0.3, 0.55, -0.7]), 0.05, Color("d07050")], ["c", Vector2(0.0, -0.3), 0.14, Color("9a9a9a")]]
		"w:5":   # staff
			return [["l", _pts([-0.55, 0.95, 0.3, -0.45]), 0.14, Color("7a5232")], ["c", Vector2(0.42, -0.62), 0.3, Color("5aa8ff")],
				["c", Vector2(0.38, -0.66), 0.12, Color("e0f2ff")]]
		"w:6":   # wand
			return [["l", _pts([-0.7, 0.8, 0.3, -0.25]), 0.1, Color("3a2a22")], ["p", _star(Vector2(0.45, -0.42), 0.42, 0.16), Color("d8b0ff")]]
		# ---------------------------------------------------------------- golem orders ("o:<name>")
		"o:follow":   # two chevrons: after me
			return [["l", _pts([-0.6, 0.15, 0.0, -0.45, 0.6, 0.15]), 0.2, Color.WHITE], ["l", _pts([-0.6, 0.65, 0.0, 0.05, 0.6, 0.65]), 0.2, Color.WHITE]]
		"o:stay":     # a hand held up: stop (a palm and fingers)
			return [["p", _pts([-0.5, -0.1, 0.5, -0.1, 0.45, 0.6, 0.2, 0.9, -0.2, 0.9, -0.45, 0.6]), Color.WHITE],
				["l", _pts([-0.38, -0.05, -0.38, -0.6]), 0.2, Color.WHITE], ["l", _pts([-0.12, -0.05, -0.12, -0.8]), 0.2, Color.WHITE],
				["l", _pts([0.14, -0.05, 0.14, -0.78]), 0.2, Color.WHITE], ["l", _pts([0.38, -0.05, 0.38, -0.55]), 0.2, Color.WHITE],
				["l", _pts([-0.48, 0.25, -0.78, -0.12]), 0.18, Color.WHITE]]
		"o:go":       # an arrow down onto a spot
			return [["r", Vector2(0, 0.62), 0.5, 0.1, Color.WHITE], ["l", _pts([0.0, -0.9, 0.0, 0.2]), 0.2, Color.WHITE],
				["p", _pts([-0.35, 0.05, 0.35, 0.05, 0.0, 0.5]), Color.WHITE]]
		"o:attack":   # crossed swords
			return [["l", _pts([-0.8, -0.8, 0.55, 0.55]), 0.14, Color.WHITE], ["l", _pts([0.8, -0.8, -0.55, 0.55]), 0.14, Color.WHITE],
				["l", _pts([0.25, 0.75, 0.75, 0.25]), 0.12, Color.WHITE], ["l", _pts([-0.25, 0.75, -0.75, 0.25]), 0.12, Color.WHITE],
				["l", _pts([0.55, 0.55, 0.85, 0.85]), 0.16, Color.WHITE], ["l", _pts([-0.55, 0.55, -0.85, 0.85]), 0.16, Color.WHITE]]
		"o:regroup":  # arrows closing in on a dot
			var out := [["c", Vector2.ZERO, 0.2, Color.WHITE]]
			for k in 4:
				var a := PI * 0.25 + PI * 0.5 * k
				var d := Vector2(cos(a), sin(a))
				var n := Vector2(-d.y, d.x)
				out.append(["l", PackedVector2Array([d * 0.9, d * 0.5]), 0.14, Color.WHITE])
				out.append(["p", PackedVector2Array([d * 0.32, d * 0.55 + n * 0.2, d * 0.55 - n * 0.2]), Color.WHITE])
			return out
	return [["c", Vector2.ZERO, 0.5, Color(0.7, 0.7, 0.7)]]


static func _golem(stone: Color, eye: Color, s: float) -> Array:
	return [["p", _pts([-0.32 * s, -0.66, 0.32 * s, -0.66, 0.3 * s, -0.2, -0.3 * s, -0.2]), stone.lightened(0.1)],   # head
		["p", _pts([-0.55 * s, -0.15, 0.55 * s, -0.15, 0.42 * s, 0.45, -0.42 * s, 0.45]), stone],                      # chest
		["p", _pts([-0.82 * s, -0.12, -0.6 * s, -0.12, -0.6 * s, 0.55, -0.85 * s, 0.55]), stone.darkened(0.15)],         # arms
		["p", _pts([0.82 * s, -0.12, 0.6 * s, -0.12, 0.6 * s, 0.55, 0.85 * s, 0.55]), stone.darkened(0.15)],
		["p", _pts([-0.38 * s, 0.5, -0.08, 0.5, -0.08, 0.95, -0.4 * s, 0.95]), stone.darkened(0.15)],                    # legs
		["p", _pts([0.08, 0.5, 0.38 * s, 0.5, 0.4 * s, 0.95, 0.08, 0.95]), stone.darkened(0.15)],
		["c", Vector2(-0.13, -0.42), 0.07, eye], ["c", Vector2(0.13, -0.42), 0.07, eye],
		["p", _pts([-0.5 * s, -0.17, -0.15, -0.17, -0.15, -0.05, -0.5 * s, -0.05]), Color("5f7f3a")]]   # moss


static func _tone(c: Color, tint: Color, grey: bool) -> Color:
	var out := c * tint
	if grey:
		var l := out.get_luminance() * 0.6 + 0.1
		out = Color(l, l, l, out.a * 0.75)
	return out


## Draw the glyph `key` on a CanvasItem, centred at `c`, `half` pixels from the centre to an edge. `tint` multiplies
## every colour (order icons are white, tinted with the owner's colour); `grey` washes it out (locked or unaffordable).
static func draw(ci: CanvasItem, key: String, c: Vector2, half: float, tint := Color.WHITE, grey := false) -> void:
	for cmd in glyph(key):
		match str(cmd[0]):
			"l":
				var pts := PackedVector2Array()
				for p: Vector2 in cmd[1]:
					pts.append(c + p * half)
				ci.draw_polyline(pts, _tone(cmd[3], tint, grey), maxf(float(cmd[2]) * half, 1.0), true)
			"c":
				ci.draw_circle(c + (cmd[1] as Vector2) * half, float(cmd[2]) * half, _tone(cmd[3], tint, grey))
			"r":
				ci.draw_arc(c + (cmd[1] as Vector2) * half, float(cmd[2]) * half, 0.0, TAU, 40, _tone(cmd[4], tint, grey), maxf(float(cmd[3]) * half, 1.0), true)
			"p":
				var pts := PackedVector2Array()
				for p: Vector2 in cmd[1]:
					pts.append(c + p * half)
				ci.draw_colored_polygon(pts, _tone(cmd[2], tint, grey))


## The glyph rasterised into a square texture (`size` pixels, transparent background, a dark outline so it reads over
## anything), for Sprite3D icons. Cached by key and tint.
static func texture(key: String, tint := Color.WHITE, size := 64) -> ImageTexture:
	var ck := "%s|%s|%d" % [key, tint.to_html(), size]
	if _tex.has(ck):
		return _tex[ck]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cmds := glyph(key)
	var px := 2.0 / size
	for y in size:
		for x in size:
			var p := Vector2((x + 0.5) / size * 2.0 - 1.0, (y + 0.5) / size * 2.0 - 1.0) * 1.12   # a margin for the outline
			var col := Color(0, 0, 0, 0)
			var near := INF   # distance to the shape (for the outline)
			for cmd in cmds:
				var d := _sdf(cmd, p)
				near = minf(near, d)
				var a := clampf(0.5 - d / px, 0.0, 1.0)
				if a > 0.0:
					var cc: Color = _tone(_col(cmd), tint, false)
					col = col.blend(Color(cc.r, cc.g, cc.b, cc.a * a))
			if col.a < 0.99 and near < 0.16:   # outline
				var oa := clampf((0.16 - near) / 0.06, 0.0, 1.0) * 0.85
				col = Color(0, 0, 0, oa).blend(col)
			img.set_pixel(x, y, col)
	var t := ImageTexture.create_from_image(img)
	_tex[ck] = t
	return t


static func _col(cmd: Array) -> Color:
	match str(cmd[0]):
		"r":
			return cmd[4]
		"p":
			return cmd[2]
	return cmd[3]


## Signed-ish distance from p to a command's shape (<= 0 inside).
static func _sdf(cmd: Array, p: Vector2) -> float:
	match str(cmd[0]):
		"l":
			var pts: PackedVector2Array = cmd[1]
			var best := INF
			for i in pts.size() - 1:
				best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])))
			return best - float(cmd[2]) * 0.5
		"c":
			return p.distance_to(cmd[1]) - float(cmd[2])
		"r":
			return absf(p.distance_to(cmd[1]) - float(cmd[2])) - float(cmd[3]) * 0.5
		"p":
			var pts: PackedVector2Array = cmd[1]
			var best := INF
			for i in pts.size():
				best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i], pts[(i + 1) % pts.size()])))
			return -best if Geometry2D.is_point_in_polygon(p, pts) else best
	return INF
