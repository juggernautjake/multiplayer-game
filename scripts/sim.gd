## The movement simulation, run identically by the server (the authority) and the client (prediction).
## It must stay deterministic: the same state and input give the same result on both sides, so predictions match the
## server and corrections are rare and tiny. No randomness, no wall-clock time, only fixed DT steps.
class_name Sim

enum Btn { FORWARD = 1, BACK = 2, LEFT = 4, RIGHT = 8, JUMP = 16, SPRINT = 32, DASH = 64 }

const WALK_SPEED := 6.0
const SPRINT_SPEED := 10.0
const GROUND_ACCEL := 70.0  # m/s^2 toward the wanted velocity on the ground: snappy, not icy
const AIR_ACCEL := 18.0     # some air control
const GRAVITY := 28.0
const JUMP_SPEED := 10.0
# Dash: the first ability, and the pattern for the rest: deterministic, counted in ticks, part of the state, so the
# client predicts it exactly and the server confirms it.
const DASH_SPEED := 24.0
const DASH_TICKS := 9         # 0.15 s burst
const DASH_COOLDOWN := 54     # 0.9 s


## One tick of player intent. yaw: facing in radians, 0 = looking down -Z (chosen by the camera).
class PlayerInput:
	var seq := 0
	var buttons := 0
	var yaw := 0.0

	func _init(s := 0, b := 0, y := 0.0) -> void:
		seq = s
		buttons = b
		yaw = y


class PlayerState:
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var yaw := 0.0
	var grounded := true
	var dash_ticks := 0     # ticks of dash left
	var dash_cd := 0        # ticks until the dash is ready again

	func copy() -> PlayerState:
		var s := PlayerState.new()
		s.pos = pos
		s.vel = vel
		s.yaw = yaw
		s.grounded = grounded
		s.dash_ticks = dash_ticks
		s.dash_cd = dash_cd
		return s


static func spawn_state(slot: int) -> PlayerState:
	# spread spawns on a small ring (golden angle) so new players don't stack
	var a := fmod(slot * 2.399963, TAU)
	var s := PlayerState.new()
	s.pos = Vector3(sin(a) * 4.0, 0.0, cos(a) * 4.0)
	quantize(s)
	return s


## Advance a player one fixed tick with this input, in place.
static func step(s: PlayerState, inp: PlayerInput) -> void:
	s.yaw = inp.yaw

	var f := 0.0
	var r := 0.0
	if inp.buttons & Btn.FORWARD: f += 1.0
	if inp.buttons & Btn.BACK: f -= 1.0
	if inp.buttons & Btn.RIGHT: r += 1.0
	if inp.buttons & Btn.LEFT: r -= 1.0
	var sy := sin(s.yaw)
	var cy := cos(s.yaw)
	# forward is -Z at yaw 0, right is +X
	var wish := Vector2(-sy * f + cy * r, -cy * f - sy * r)
	var speed := SPRINT_SPEED if inp.buttons & Btn.SPRINT else WALK_SPEED
	if wish.length_squared() > 0.0:
		wish = wish.normalized() * speed

	if s.dash_cd > 0:
		s.dash_cd -= 1
	if inp.buttons & Btn.DASH and s.dash_cd == 0:
		# dash the way you're moving, or straight ahead if standing still
		var dir := wish.normalized() if wish.length_squared() > 0.0 else Vector2(-sy, -cy)
		s.vel.x = dir.x * DASH_SPEED
		s.vel.z = dir.y * DASH_SPEED
		s.dash_ticks = DASH_TICKS
		s.dash_cd = DASH_COOLDOWN

	if s.dash_ticks > 0:
		s.dash_ticks -= 1  # keep the burst: no steering, no gravity
		if s.vel.y < 0.0:
			s.vel.y = 0.0
	else:
		# accelerate the horizontal velocity toward the wanted one, at most accel * DT this tick
		var accel := (GROUND_ACCEL if s.grounded else AIR_ACCEL) * Config.DT
		var h := Vector2(s.vel.x, s.vel.z)
		var d := wish - h
		if d.length() <= accel:
			h = wish
		else:
			h += d.normalized() * accel
		s.vel.x = h.x
		s.vel.z = h.y

	if s.grounded and inp.buttons & Btn.JUMP:
		s.vel.y = JUMP_SPEED
		s.grounded = false
	if not s.grounded and s.dash_ticks == 0:
		s.vel.y -= GRAVITY * Config.DT

	s.pos += s.vel * Config.DT

	if s.pos.y <= 0.0:  # the ground plane
		s.pos.y = 0.0
		s.vel.y = 0.0
		s.grounded = true
	var lim := Config.WORLD_HALF  # the edge of the world
	if absf(s.pos.x) > lim:
		s.pos.x = clampf(s.pos.x, -lim, lim)
		s.vel.x = 0.0
	if absf(s.pos.z) > lim:
		s.pos.z = clampf(s.pos.z, -lim, lim)
		s.vel.z = 0.0

	quantize(s)


## Round to float32, the precision snapshots carry, so the server's state and the client's copy match bit for bit.
static func quantize(s: PlayerState) -> void:
	var a := PackedFloat32Array([s.pos.x, s.pos.y, s.pos.z, s.vel.x, s.vel.y, s.vel.z, s.yaw])
	s.pos = Vector3(a[0], a[1], a[2])
	s.vel = Vector3(a[3], a[4], a[5])
	s.yaw = a[6]
