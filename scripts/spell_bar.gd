## v0.12.2 The spell hotbar over the health bar while the staff or wand is in hand: one slot per spell, in order.
## Each slot shows the spell's icon (Icons), its key (Ctrl + the number), and
##   staff: its mana cost (a rate for the held Heal Aura); greyed out while you can't pay for it; a dark sweep falling
##          from the top while the staff is busy (casting or cooling down);
##   wand:  a clock sweep over the icon while it recharges, with the seconds left; its full recharge time when ready;
##   locked: a dark slot with a padlock and "Lv N" (the level that unlocks it).
## The selected spell has a gold frame and its name and cost over the bar; a newly picked one flashes.
class_name SpellBar
extends Control

const SLOT := 52.0
const GAP := 6.0

var st: Sim.PlayerState
var sel := 0
var _flash := 0.0
var _flash_i := -1
var _busy_max := 1     # the longest the staff has been busy lately (for the sweep's scale)


## Called every frame by Main with the predicted state and the selected slot.
func show_state(state: Sim.PlayerState, selected: int) -> void:
	if selected != sel:
		_flash = 0.35
		_flash_i = selected
	sel = selected
	st = state
	visible = st != null and Weapons.is_magic(st.weapon) and st.dead == 0
	_flash = maxf(_flash - get_process_delta_time(), 0.0)
	queue_redraw()


## Screen rectangle of slot i (for tests and the tutorial pictures).
func slot_rect(i: int, n: int) -> Rect2:
	var total := n * SLOT + (n - 1) * GAP
	var x0 := (size.x - total) * 0.5
	return Rect2(Vector2(x0 + i * (SLOT + GAP), size.y - SLOT), Vector2(SLOT, SLOT))


func _text(pos: Vector2, s: String, fs: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var f := ThemeDB.fallback_font
	draw_string_outline(f, pos, s, align, width, fs, 4, Color(0, 0, 0, 0.9 * col.a))
	draw_string(f, pos, s, align, width, fs, col)


func _draw() -> void:
	if st == null or not Weapons.is_magic(st.weapon):
		return
	var w := st.weapon
	var d := Weapons.get_data(w)
	var spells: Array = d.spells
	var n := spells.size()
	var lv := st.staff_lvl if w == Weapons.STAFF else st.wand_lvl
	var wand := str(d.get("uses", "mana")) == "recharge"
	var busy := maxi(st.atk, st.atk_cd)
	if busy > _busy_max or busy == 0:
		_busy_max = maxi(busy, 1)
	for i in n:
		var sp: Dictionary = spells[i]
		var r := slot_rect(i, n)
		var c := r.get_center()
		var unlocked := Weapons.unlocked(w, i, lv)
		draw_rect(r, Color(0.04, 0.05, 0.09, 0.78))
		if not unlocked:
			Icons.draw(self, str(sp.name), c + Vector2(0, -4), SLOT * 0.3, Color(1, 1, 1, 0.35), true)
			draw_rect(r, Color(0, 0, 0, 0.45))
			# a padlock
			var lk := c + Vector2(0, -8)
			draw_arc(lk + Vector2(0, -5), 5.5, PI, TAU, 10, Color(0.75, 0.75, 0.8, 0.9), 2.0, true)
			draw_rect(Rect2(lk + Vector2(-7, -5), Vector2(14, 11)), Color(0.75, 0.75, 0.8, 0.9))
			_text(Vector2(r.position.x, r.end.y - 6), "Lv %d" % int(sp.get("level", 1)), 13, Color("c9c9d6"), HORIZONTAL_ALIGNMENT_CENTER, SLOT)
		else:
			var ready := true
			var cost_txt := ""
			if wand:
				var left: int = st.recharge[i] if i < st.recharge.size() else 0
				var full := maxi(int(sp.get("recharge", 1)), 1)
				ready = left == 0
				Icons.draw(self, str(sp.name), c, SLOT * 0.36, Color.WHITE, not ready)
				if not ready:   # the recharge: a dark clock sweep that unwinds, and the seconds left
					var k := clampf(float(left) / full, 0.0, 1.0)
					var pts := PackedVector2Array([c])
					var steps := maxi(int(48 * k), 2)
					for s in steps + 1:
						var a := -PI / 2.0 + TAU * k * float(s) / steps
						pts.append(c + Vector2(cos(a), sin(a)) * SLOT * 0.75)
					var poly := Geometry2D.intersect_polygons(pts, PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]))
					for pg in poly:
						draw_colored_polygon(pg, Color(0, 0, 0, 0.55))
					_text(Vector2(r.position.x, c.y + 7), "%d" % int(ceil(left * Config.DT)), 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, SLOT)
				else:
					cost_txt = "%ds" % int(round(full * Config.DT))
			else:
				var cost := int(sp.cost)
				if bool(sp.get("channel", false)):
					ready = st.mana > 0
					cost_txt = "%d/s" % int(round(float(sp.get("drain", 1)) * Config.TICK_RATE / 5.0))
				else:
					ready = st.mana >= cost * 5
					cost_txt = str(cost)
				Icons.draw(self, str(sp.name), c, SLOT * 0.36, Color.WHITE, not ready)
				if busy > 0:   # the staff is busy: a shade falling from the top
					var k := clampf(float(busy) / _busy_max, 0.0, 1.0)
					draw_rect(Rect2(r.position, Vector2(SLOT, SLOT * k)), Color(0, 0, 0, 0.45))
			if cost_txt != "":
				_text(Vector2(r.position.x, r.end.y - 3), cost_txt, 12, Color("8fc0ff") if not wand else Color("c9c9d6"), HORIZONTAL_ALIGNMENT_RIGHT, SLOT - 4)
			if not ready and not wand:
				_text(Vector2(r.position.x, r.end.y - 3), "mana", 11, Color("ff8a8a"), HORIZONTAL_ALIGNMENT_LEFT, -1)
		_text(r.position + Vector2(4, 14), str(i + 1), 13, Color("ffe9a8") if unlocked else Color(0.7, 0.7, 0.7, 0.7))
		var frame := Color(1, 1, 1, 0.18)
		var fw := 1.0
		if i == sel:
			frame = Icons.GOLD
			fw = 3.0
			if _flash > 0.0 and _flash_i == i:
				draw_rect(r.grow(2.0), Color(1, 0.9, 0.5, _flash * 1.6), false, 2.0)
		draw_rect(r, frame, false, fw)
	# the picked spell's name and cost over the bar, and how to pick
	var s0: Dictionary = spells[clampi(sel, 0, n - 1)]
	var info := str(s0.name)
	if not wand:
		info += "   %s mana" % (("%d/s" % int(round(float(s0.get("drain", 1)) * Config.TICK_RATE / 5.0))) if bool(s0.get("channel", false)) else str(int(s0.cost)))
	else:
		info += "   recharge %d s" % int(round(int(s0.get("recharge", 0)) * Config.DT))
	var top := slot_rect(0, n).position.y
	_text(Vector2(0, top - 8), info, 17, Color("ffe9a8"), HORIZONTAL_ALIGNMENT_CENTER, size.x)
	var hint := "Ctrl+1-%d pick    R next    Shift+R back    hold R: wheel    RMB + wheel: scroll" % n
	_text(Vector2(0, top - 28), hint, 12, Color(0.85, 0.88, 1.0, 0.7), HORIZONTAL_ALIGNMENT_CENTER, size.x)
