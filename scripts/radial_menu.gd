## v0.12.2 A radial wheel (hold Tab: weapons, hold R: spells, hold G: golem orders). The game doesn't pause (it's
## online): while the wheel is open the mouse moves a pointer from its centre instead of the camera, and you keep
## moving with WASD. The option the pointer leans toward is lit; let go of the key (or click) to take it, or let go
## with the pointer back in the middle to take nothing.
##
## Items: [{ icon (an Icons key), label, sub (a second line), enabled, tint }].
class_name RadialMenu
extends Control

const R_RING := 146.0     # centre of the ring of options
const R_BUBBLE := 34.0
const LIFT := 40.0        # the wheel sits a little above the middle of the screen, clear of the hotbar
const DEAD := 26.0        # pointer this close to the middle: nothing picked
const R_MAX := 120.0

var items: Array = []
var title := ""
var hint := ""
var cursor := Vector2.ZERO
var hovered := -1
var current := -1         # the one in use now (a thin ring)
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Open with these items; `cur` is the one in use now. The pointer starts in the middle.
func open(its: Array, ttl: String, cur := -1, hnt := "") -> void:
	items = its
	title = ttl
	hint = hnt
	current = cur
	cursor = Vector2.ZERO
	hovered = -1
	_t = 0.0
	visible = true
	queue_redraw()


## Mouse motion while open (relative pixels).
func push(rel: Vector2) -> void:
	cursor += rel
	if cursor.length() > R_MAX:
		cursor = cursor.normalized() * R_MAX
	hovered = _index_at(cursor)
	queue_redraw()


## Point the wheel at item i (bots and pictures).
func point_at(i: int) -> void:
	cursor = Vector2.ZERO
	push(_dir(i) * R_MAX)


## Close; -> the item picked (enabled and pointed at), or -1.
func close() -> int:
	visible = false
	var pick := hovered
	if pick >= 0 and not bool(items[pick].get("enabled", true)):
		pick = -1
	return pick


func _dir(i: int) -> Vector2:
	var a := -PI / 2.0 + TAU * float(i) / maxf(items.size(), 1.0)
	return Vector2(cos(a), sin(a))


func _index_at(p: Vector2) -> int:
	if p.length() < DEAD or items.is_empty():
		return -1
	var best := -1
	var best_d := -2.0
	for i in items.size():
		var d := _dir(i).dot(p.normalized())
		if d > best_d:
			best_d = d
			best = i
	return best


func _process(delta: float) -> void:
	if visible:
		_t += delta
		queue_redraw()


func _text(pos: Vector2, s: String, fs: int, col: Color, width := -1.0) -> void:
	var f := ThemeDB.fallback_font
	var align := HORIZONTAL_ALIGNMENT_CENTER if width > 0 else HORIZONTAL_ALIGNMENT_LEFT
	draw_string_outline(f, pos, s, align, width, fs, 5, Color(0, 0, 0, 0.85 * col.a))
	draw_string(f, pos, s, align, width, fs, col)


func _draw() -> void:
	var c := size * 0.5 - Vector2(0, LIFT)
	var pop := clampf(_t / 0.08, 0.0, 1.0)
	var n := items.size()
	draw_circle(c, (R_RING + R_BUBBLE + 30.0) * (0.85 + 0.15 * pop), Color(0.02, 0.03, 0.07, 0.55 * pop))
	draw_arc(c, R_RING + R_BUBBLE + 30.0, 0.0, TAU, 72, Color(1, 1, 1, 0.12 * pop), 2.0, true)
	# the lit wedge
	if hovered >= 0 and n > 0:
		var a := -PI / 2.0 + TAU * float(hovered) / n
		var half := PI / n
		var pts := PackedVector2Array([c + Vector2(cos(a - half), sin(a - half)) * 52.0])
		for s in 13:
			var aa := a - half + 2.0 * half * s / 12.0
			pts.append(c + Vector2(cos(aa), sin(aa)) * (R_RING + R_BUBBLE + 30.0))
		pts.append(c + Vector2(cos(a + half), sin(a + half)) * 52.0)
		var en := bool(items[hovered].get("enabled", true))
		draw_colored_polygon(pts, Color(1.0, 0.85, 0.4, 0.16) if en else Color(1, 0.3, 0.3, 0.1))
	for i in n:
		var it: Dictionary = items[i]
		var p := c + _dir(i) * R_RING * (0.8 + 0.2 * pop)
		var en := bool(it.get("enabled", true))
		var lit := i == hovered
		var rb := R_BUBBLE * (1.18 if lit else 1.0)
		draw_circle(p, rb, Color(0.08, 0.09, 0.14, 0.92) if en else Color(0.06, 0.06, 0.07, 0.85))
		var tint: Color = it.get("tint", Color.WHITE)
		Icons.draw(self, str(it.icon), p, rb * 0.62, tint, not en)
		var ring_col := Color(1, 1, 1, 0.25)
		var ring_w := 2.0
		if i == current:
			ring_col = Color(0.6, 0.85, 1.0, 0.9)
			ring_w = 3.0
		if lit:
			ring_col = Icons.GOLD if en else Color("ff6a6a")
			ring_w = 4.0
		draw_arc(p, rb, 0.0, TAU, 40, ring_col, ring_w, true)
		var sub := str(it.get("sub", ""))
		var lab_y := p.y + rb + 16.0   # under the bubble; over it for the top ones (the middle stays clear)
		if _dir(i).y < -0.3:
			lab_y = p.y - rb - (21.0 if sub != "" else 6.0)
		_text(Vector2(p.x - 80, lab_y), str(it.label), 15 if lit else 14, Color.WHITE if en else Color(0.6, 0.6, 0.6), 160)
		if sub != "":
			_text(Vector2(p.x - 80, lab_y + 15), sub, 12, Color(0.75, 0.82, 0.95) if en else Color(0.9, 0.5, 0.5), 160)
	# the middle: the title, then what's lit
	_text(Vector2(c.x - 120, c.y - 8), title, 16, Color(1, 1, 1, 0.75), 240)
	if hovered >= 0:
		_text(Vector2(c.x - 120, c.y + 14), str(items[hovered].label), 18, Icons.GOLD if bool(items[hovered].get("enabled", true)) else Color("ff8a8a"), 240)
	elif hint != "":
		_text(Vector2(c.x - 120, c.y + 14), hint, 12, Color(1, 1, 1, 0.55), 240)
	# the pointer
	var tip := c + cursor * 0.42
	draw_line(c, tip, Color(1, 1, 1, 0.5), 2.0, true)
	draw_circle(tip, 5.0, Color(1, 1, 1, 0.9))
