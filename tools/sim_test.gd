## Headless checks of the shared simulation. Run:
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/sim_test.gd
extends SceneTree

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func run(s: Sim.PlayerState, buttons: int, yaw: float, ticks: int) -> void:
	for i in ticks:
		Sim.step(s, Sim.PlayerInput.new(i, buttons, yaw))


func inside_any(s: Sim.PlayerState) -> bool:
	for b: WorldLayout.Box in WorldLayout.boxes():
		var nx := clampf(s.pos.x, b.cx - b.hx, b.cx + b.hx)
		var nz := clampf(s.pos.z, b.cz - b.hz, b.cz + b.hz)
		if Vector2(s.pos.x - nx, s.pos.z - nz).length() < Sim.RADIUS - 0.02 and s.pos.y < b.h - 0.02:
			return true
	return false


func _init() -> void:
	var step1: WorldLayout.Box = WorldLayout.boxes().filter(func(b): return b.cx == 6.0 and b.cz == -6.0)[0]  # the low step near spawn (0.9 m)
	var face := atan2(-(step1.cx - 0.0), -(step1.cz - 0.0))  # yaw that looks from the origin toward it

	# 1) walk into the step without jumping: stopped at its side, never inside
	var s := Sim.PlayerState.new()
	var ok := true
	for i in 240:
		Sim.step(s, Sim.PlayerInput.new(i, Sim.Btn.FORWARD, face))
		ok = ok and not inside_any(s)
	check(ok, "walking into a step never goes inside it")
	check(s.pos.y == 0.0 and Vector2(s.pos.x - step1.cx, s.pos.z - step1.cz).length() > step1.hx, "stopped beside the step, on the ground")

	# 2) jump while walking into it: ends standing on top
	run(s, Sim.Btn.FORWARD | Sim.Btn.JUMP, face, 1)
	run(s, Sim.Btn.FORWARD, face, 40)
	run(s, 0, face, 60)
	check(absf(s.pos.y - step1.h) < 0.01 and s.grounded, "jumped onto the step: standing on top at %.2f m" % s.pos.y)

	# 3) walk off the far side: falls back to the ground
	run(s, Sim.Btn.FORWARD, face, 120)
	run(s, 0, face, 60)
	check(s.pos.y == 0.0 and s.grounded, "walked off the step and landed on the ground")

	# 4) dash into a tall pillar: still never inside
	var tall: WorldLayout.Box = WorldLayout.boxes()[0]
	var t := Sim.PlayerState.new()
	t.pos = Vector3(tall.cx, 0, tall.cz + tall.hz + 3.0)
	ok = true
	for i in 120:
		Sim.step(t, Sim.PlayerInput.new(i, Sim.Btn.FORWARD | (Sim.Btn.DASH if i % 60 == 0 else 0), 0.0))
		ok = ok and not inside_any(t)
	check(ok, "dashing into a pillar never goes inside it")

	# 5) determinism: two runs of the same inputs agree bit for bit
	var a := Sim.PlayerState.new()
	var b := Sim.PlayerState.new()
	for i in 600:
		var btn: int = [Sim.Btn.FORWARD, Sim.Btn.FORWARD | Sim.Btn.JUMP, Sim.Btn.RIGHT | Sim.Btn.SPRINT, Sim.Btn.DASH][i % 4]
		Sim.step(a, Sim.PlayerInput.new(i, btn, i * 0.013))
		Sim.step(b, Sim.PlayerInput.new(i, btn, i * 0.013))
	check(a.pos == b.pos and a.vel == b.vel, "same inputs, same result")

	# 6) attacking with no movement keys stays in place; attacking while walking steps into it
	for w in [Weapons.FISTS, Weapons.CLUB, Weapons.SWORD]:
		var st := Sim.PlayerState.new()
		st.owned = 0b11111
		st.weapon = w
		var p0 := st.pos
		for i in 120:
			Sim.step(st, Sim.PlayerInput.new(i, Sim.Btn.ATTACK if i % 3 == 0 else 0, 0.0, 0.0, w))
		check(st.pos.distance_to(p0) < 0.001, "%s combo with no keys held: stays put (moved %.3f m)" % [Weapons.NAMES[w], st.pos.distance_to(p0)])
		var mv := Sim.PlayerState.new()
		mv.owned = 0b11111
		mv.weapon = w
		for i in 20:
			Sim.step(mv, Sim.PlayerInput.new(i, Sim.Btn.FORWARD | (Sim.Btn.ATTACK if i == 0 else 0), 0.0, 0.0, w))
		check(mv.pos.z < -0.3, "%s swing while walking: steps forward (%.2f m)" % [Weapons.NAMES[w], -mv.pos.z])

	# 7) walking turns the body toward the way you go; aiming faces the camera
	var f := Sim.PlayerState.new()
	for i in 60:
		Sim.step(f, Sim.PlayerInput.new(i, Sim.Btn.RIGHT, 0.0))
	check(absf(wrapf(f.yaw - (-PI / 2.0), -PI, PI)) < 0.01, "walking right turns to face right (yaw %.2f)" % f.yaw)
	Sim.step(f, Sim.PlayerInput.new(61, Sim.Btn.FACE_CAM, 1.0, 0.0, 0, 0, 1.3))
	check(absf(f.yaw - 1.0) < 0.001, "aiming faces where the camera looks (not the skewed line to a close crosshair point)")
	# 8) holding attack up close: the crosshair point's line is 0.3 rad off the camera heading; the body follows the
	#    camera heading, turns there over a few frames, and stays put once there
	var atk := Sim.PlayerState.new()
	atk.owned = 0b11111
	for i in 40:
		Sim.step(atk, Sim.PlayerInput.new(i, Sim.Btn.ATTACK if i % 2 == 0 else 0, 0.8, 0.0, Weapons.SWORD, 0, 0.8 + 0.3))
	check(absf(wrapf(atk.yaw - 0.8, -PI, PI)) < 0.05, "holding attack faces the camera heading, not the close crosshair point (yaw %.2f)" % atk.yaw)

	print("%d failed" % fails)
	quit(1 if fails else 0)
