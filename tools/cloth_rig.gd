## A 3D figure (FigureAvatar) driven through every move by the real simulation (Sim.step), for checking its cloth:
## standing, walking, sprinting, strafing, backpedalling, a running jump and its landing, a dash, every move of the
## weapon's combo (stepping into it), a bow / slingshot draw and release, a spell, a block, and being thrown (tumbling,
## lying, getting up). Used by tools/cloth_test.gd (headless: no cloth point inside the body) and tools/cloth_shots.gd
## (pictures).   var rig = preload("res://tools/cloth_rig.gd").new(parent, Weapons.SWORD)
extends RefCounted

var fig: FigureAvatar
var st: Sim.PlayerState
var weapon := 0
var tick := 0
var label := ""            # the moment this tick is (a picture / check point), or ""
var phase := ""            # the move going on now
var _plan: Array = []      # [name, ticks, buttons, {offset: label}, {offset: extra buttons}]
var _seg := 0
var _off := 0
var _yaw := 0.0
var ticks_per_frame := 1   # 2: the figure drawn at 30 fps (two simulation ticks a frame)
var drawn := false         # the figure was drawn (animated) this tick


func _init(parent: Node, w: int, pos := Vector3.ZERO, outfit := 0) -> void:
	weapon = w
	fig = FigureAvatar.new("x", Color("4363d8"), false, outfit)
	st = Sim.PlayerState.new()
	st.pos = pos
	st.owned = 0b1111111
	st.arrows = 30
	st.rocks = 30
	st.weapon = w
	fig.state = st
	fig.position = pos
	parent.add_child(fig)
	var B := Sim.Btn
	_plan = [
		["idle", 50, 0, {49: "idle"}, {}],
		["walk", 50, B.FORWARD, {49: "walk"}, {}],
		["sprint", 50, B.FORWARD | B.SPRINT, {49: "sprint"}, {}],
		["strafe", 40, B.RIGHT | B.FACE_CAM, {39: "strafe"}, {}],
		["backpedal", 40, B.BACK | B.FACE_CAM, {39: "backpedal"}, {}],
		["turn", 30, B.LEFT, {12: "turn"}, {}],
		["jump", 64, B.FORWARD | B.SPRINT, {30: "jump", 56: "land"}, {8: B.JUMP}],
		["dash", 34, B.FORWARD, {9: "dash", 15: "dash_end"}, {4: B.DASH}],
		["stop", 30, 0, {6: "stop"}, {}],
	]
	var d := Weapons.get_data(w)
	if Weapons.is_melee(w):
		for k in (d.moves as Array).size():
			var mv := Weapons.move(w, k)
			_plan.append(["swing%d" % (k + 1), int(mv.swing) + 2, B.FORWARD, {int(mv.windup) - 2: "swing%d_wind" % (k + 1), int(mv.windup) + 3: "swing%d" % (k + 1)}, {0: B.ATTACK}])
		_plan.append(["rest", 40, 0, {}, {}])
	elif Weapons.is_magic(w):
		var sp := Weapons.spell(w, 0)
		_plan.append(["cast", int(sp.cast) + 30, 0, {int(sp.windup) + 2: "cast"}, {0: B.ATTACK}])
	else:
		_plan.append(["draw", int(d.draw) + 20, B.ATTACK, {int(d.draw) + 18: "draw"}, {}])
		_plan.append(["release", 40, 0, {3: "release"}, {}])
	_plan.append(["block", 40, B.BLOCK, {38: "block"}, {}])
	_plan.append(["blockwalk", 30, B.BLOCK | B.FORWARD, {28: "block_walk"}, {}])
	_plan.append(["thrown", 220, 0, {10: "thrown", 30: "tumble"}, {}])
	_plan.append(["after", 30, B.FORWARD | B.SPRINT, {29: "run_again"}, {}])


func done() -> bool:
	return _seg >= _plan.size()


## One tick (1/60 s): the simulation, then the figure (animation and cloth).
func step() -> void:
	label = ""
	if done():
		return
	var s: Array = _plan[_seg]
	phase = s[0]
	var b: int = s[2]
	var extra: Dictionary = s[4]
	b |= int(extra.get(_off, 0))
	if phase == "thrown" and _off == 0:   # launched by a charge: up and backwards, tumbling
		st.down = Sim.DOWN_TICKS
		st.vel = Basis(Vector3.UP, st.yaw) * Vector3(0, 9.0, 9.0)
		st.grounded = false
	if phase == "turn":
		_yaw += 0.0
	var inp := Sim.PlayerInput.new(tick, b, _yaw, 0.0, weapon, 0, st.yaw, INF, 0, st.pos + Basis(Vector3.UP, st.yaw) * Vector3(0, 1, -8))
	Sim.step(st, inp)
	if phase == "thrown":
		if st.down == 60:
			label = "lying"
		elif st.down == 22:
			label = "getup"
	var caps: Dictionary = s[3]
	if caps.has(_off):
		label = caps[_off]
	fig.position = st.pos
	fig.yaw = st.yaw
	fig.grounded = st.grounded
	fig.dashing = st.dash_ticks > 0
	drawn = (tick + 1) % ticks_per_frame == 0
	if drawn:
		fig.animate(Config.DT * ticks_per_frame, null)
	tick += 1
	_off += 1
	if _off >= int(s[1]) and not (phase == "thrown" and st.down > 0 and _off < 600):
		_seg += 1
		_off = 0


const ARM_PARTS := ["upper_r", "upper_l", "fore_r", "fore_l", "elbow_r", "elbow_l", "hand_r", "hand_l"]
var _body_parts := []


## The cloth now, against the body: {depth (deepest point inside the body as drawn, arms apart, m), part, piece,
## arm (deepest inside an arm or hand), arm_part, nan (any bad number), reach (most any point of the tabard, cloak or
## tails is past its own length from its anchor, m), reach_robe (the same for the robe and kilt), points}.
func measure() -> Dictionary:
	if _body_parts.is_empty():
		for nm in FigureAvatar._DEPTH_PARTS:
			if not nm in ARM_PARTS:
				_body_parts.append(nm)
	var r := { "depth": 0.0, "part": "", "piece": "", "arm": 0.0, "arm_part": "", "nan": false, "reach": 0.0,
		"reach_robe": 0.0, "points": 0, "at": Vector3.ZERO }
	var g: WizardGarb = fig._garb
	for cp in g.cloth_points():
		var p: Vector3 = cp[0]
		r.points += 1
		if not p.is_finite():
			r.nan = true
			continue
		var bd := fig.body_depth(p, _body_parts)
		if float(bd[0]) > float(r.depth):
			r.depth = bd[0]
			r.part = bd[1]
			r.piece = cp[1]
			r.at = p
		var ad := fig.body_depth(p, ARM_PARTS)
		if float(ad[0]) > float(r.arm):
			r.arm = ad[0]
			r.arm_part = "%s/%s" % [cp[1], ad[1]]
	for cr in g.cloth_reach():
		var p: Vector3 = cr[0]
		if not p.is_finite():
			r.nan = true
			continue
		var key := "reach_robe" if cr.size() > 3 and cr[3] == "robe" else "reach"
		r[key] = maxf(float(r[key]), p.distance_to(cr[1]) - float(cr[2]))
	return r
