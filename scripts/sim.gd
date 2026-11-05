## The movement simulation, run identically by the server (the authority) and the client (prediction).
## It must stay deterministic: the same state and input give the same result on both sides, so predictions match the
## server and corrections are rare and tiny. No randomness, no wall-clock time, only fixed DT steps.
class_name Sim

## FACE_CAM: face where the camera looks (aiming, first person) instead of the way you walk.
enum Btn { FORWARD = 1, BACK = 2, LEFT = 4, RIGHT = 8, JUMP = 16, SPRINT = 32, DASH = 64, ATTACK = 128, INTERACT = 256, FACE_CAM = 512 }

## What a step reports, for the server to act on (hit test, launch a projectile) and the client to show.
enum Ev { NONE, MELEE_HIT, SHOT }

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
const RADIUS := 0.4           # the player's collision radius
const TURN_RATE := 14.0       # rad/s: how fast you turn to face the way you walk
const ATTACK_TURN_RATE := 12.0  # rad/s: how fast you turn toward the crosshair while holding attack (mid-swing too)
const MAX_HP := 100
const RESPAWN_TICKS := 180    # 3 s on the ground after dying


## One tick of player intent. yaw: the camera's heading (radians, 0 = looking down -Z): WASD move relative to it.
## The body's facing is worked out in the simulation (it turns toward the way you walk). pitch: aim up/down
## (for projectiles). weapon: the slot wanted. view_tick: the tick the player was seeing other players at (the server
## rewinds to it for melee hits: lag compensation).
class PlayerInput:
	var seq := 0
	var buttons := 0
	var yaw := 0.0
	var pitch := 0.0
	var weapon := 0
	var view_tick := 0
	var aim_yaw := 0.0      # the shot's own direction (to the crosshair), apart from the body's facing

	func _init(s := 0, b := 0, y := 0.0, p := 0.0, w := 0, v := 0, ay := 0.0) -> void:
		seq = s
		buttons = b
		yaw = y
		pitch = p
		weapon = w
		view_tick = v
		aim_yaw = ay


class PlayerState:
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var yaw := 0.0
	var grounded := true
	var dash_ticks := 0     # ticks of dash left
	var dash_cd := 0        # ticks until the dash is ready again
	var weapon := 0         # Weapons.FISTS / CLUB / SWORD / BOW / SLING
	var owned := 1          # weapons picked up, one bit each (fists always)
	var arrows := 0
	var rocks := 0
	var combo := 0          # which move of the weapon's combo
	var combo_t := 0        # ticks left to chain the next move
	var atk := 0            # ticks left in the current swing or shot
	var atk_cd := 0         # ticks until the next attack
	var charge := 0         # ticks a bow / slingshot has been drawn
	var swing_n := 0        # counts attacks (0-255), so every client can tell a new swing started
	var hp := MAX_HP
	var dead := 0           # ticks until respawn (0 = alive)
	var last_charge := 0    # how far the last shot was drawn (not sent: the server reads it at the shot)

	func copy() -> PlayerState:
		var s := PlayerState.new()
		s.pos = pos
		s.vel = vel
		s.yaw = yaw
		s.grounded = grounded
		s.dash_ticks = dash_ticks
		s.dash_cd = dash_cd
		s.weapon = weapon
		s.owned = owned
		s.arrows = arrows
		s.rocks = rocks
		s.combo = combo
		s.combo_t = combo_t
		s.atk = atk
		s.atk_cd = atk_cd
		s.charge = charge
		s.swing_n = swing_n
		s.hp = hp
		s.dead = dead
		s.last_charge = last_charge
		return s


static func spawn_state(slot: int) -> PlayerState:
	# spread spawns on a small ring (golden angle) so new players don't stack
	var a := fmod(slot * 2.399963, TAU)
	var s := PlayerState.new()
	s.pos = Vector3(sin(a) * 4.0, 0.0, cos(a) * 4.0)
	quantize(s)
	return s


## Advance a player one fixed tick with this input, in place. Returns what happened (Ev).
static func step(s: PlayerState, inp: PlayerInput) -> int:
	var ev := _combat(s, inp)
	var alive := s.dead == 0

	var f := 0.0
	var r := 0.0
	if inp.buttons & Btn.FORWARD: f += 1.0
	if inp.buttons & Btn.BACK: f -= 1.0
	if inp.buttons & Btn.RIGHT: r += 1.0
	if inp.buttons & Btn.LEFT: r -= 1.0
	# WASD relative to the camera: forward is -Z at yaw 0, right is +X
	var csy := sin(inp.yaw)
	var ccy := cos(inp.yaw)
	var wish := Vector2(-csy * f + ccy * r, -ccy * f - csy * r)
	var w := Weapons.get_data(s.weapon)
	var mv := Weapons.move(s.weapon, s.combo)
	var busy: bool = s.charge > 0 or (s.atk > 0 and w.kind == "melee")
	var speed := SPRINT_SPEED if inp.buttons & Btn.SPRINT and not busy else WALK_SPEED
	if busy:
		speed *= w.slow   # drawing a bow or mid-swing: slower
	if not alive:
		wish = Vector2.ZERO
	if wish.length_squared() > 0.0:
		wish = wish.normalized() * speed
	_face(s, inp, wish, w, mv, alive)
	var sy := sin(s.yaw)
	var cy := cos(s.yaw)

	if s.dash_cd > 0:
		s.dash_cd -= 1
	if inp.buttons & Btn.DASH and s.dash_cd == 0 and alive:
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
		# a melee swing steps into the blow only if you're moving: then, during the wind-up, drive forward at the
		# weapon's lunge speed; with no movement keys you attack where you stand
		if alive and s.grounded and w.kind == "melee" and s.atk > int(mv.swing) - int(mv.windup) and wish.length_squared() > 0.0:
			s.vel.x = -sy * float(mv.lunge)
			s.vel.z = -cy * float(mv.lunge)

	if s.grounded and inp.buttons & Btn.JUMP and alive:
		s.vel.y = JUMP_SPEED
		s.grounded = false
	if not s.grounded and s.dash_ticks == 0:
		s.vel.y -= GRAVITY * Config.DT

	var prev_y := s.pos.y
	s.pos += s.vel * Config.DT

	s.grounded = false
	if s.pos.y <= 0.0:  # the ground plane
		s.pos.y = 0.0
		s.vel.y = 0.0
		s.grounded = true
	_collide_boxes(s, prev_y)
	var lim := Config.WORLD_HALF  # the edge of the world
	if absf(s.pos.x) > lim:
		s.pos.x = clampf(s.pos.x, -lim, lim)
		s.vel.x = 0.0
	if absf(s.pos.z) > lim:
		s.pos.z = clampf(s.pos.z, -lim, lim)
		s.vel.z = 0.0

	quantize(s)
	return ev


## Weapons: switching, melee swings (the hit lands `windup` ticks in), drawing and releasing a bow or slingshot.
## All counted in ticks from the inputs, so the client predicts its own attacks exactly; the server alone decides hits.
static func _combat(s: PlayerState, inp: PlayerInput) -> int:
	var ev := Ev.NONE
	if s.atk_cd > 0:
		s.atk_cd -= 1
	if s.atk > 0:
		s.atk -= 1
	if s.combo_t > 0:
		s.combo_t -= 1
	if s.dead > 0:
		s.dead -= 1
		s.charge = 0
		return ev
	var want := inp.weapon
	if want != s.weapon and want >= 0 and want < Weapons.DATA.size() and (s.owned >> want) & 1 and s.atk == 0 and s.charge == 0:
		s.weapon = want
		s.combo = 0
		s.combo_t = 0
	var w := Weapons.get_data(s.weapon)
	var attack := inp.buttons & Btn.ATTACK != 0
	if w.kind == "melee":
		var moves: Array = w.moves
		var cur: Dictionary = moves[s.combo]
		var recovery := int(cur.swing) - int(cur.windup)
		# cancel into the next move late in this one's recovery (not after the finisher)
		var can_cancel: bool = s.atk > 0 and s.atk <= int(recovery * Weapons.CANCEL_AT) and s.combo < moves.size() - 1
		if attack and ((s.atk == 0 and s.atk_cd == 0) or can_cancel):
			# chain the next move if mid-move or still inside the window after the last one, else start the combo over
			s.combo = (s.combo + 1) % moves.size() if (s.combo_t > 0 or can_cancel) else 0
			var mv: Dictionary = moves[s.combo]
			s.atk = int(mv.swing)
			s.atk_cd = int(mv.swing) + int(mv.recover)
			s.combo_t = 0
			s.swing_n = (s.swing_n + 1) % 256
		elif s.atk > 0:
			var mv: Dictionary = moves[s.combo]
			if s.atk == int(mv.swing) - int(mv.windup):
				ev = Ev.MELEE_HIT
			if s.atk == 1:
				s.combo_t = Weapons.COMBO_WINDOW
	else:
		var ammo := s.arrows if w.ammo == "arrows" else s.rocks
		if attack and s.atk_cd == 0 and s.atk == 0 and ammo > 0:
			s.charge = mini(s.charge + 1, int(w.draw))
		elif not attack and s.charge > 0:
			s.last_charge = s.charge
			s.charge = 0
			s.atk = int(w.shot)
			s.atk_cd = int(w.cooldown)
			s.swing_n = (s.swing_n + 1) % 256
			if w.ammo == "arrows":
				s.arrows -= 1
			else:
				s.rocks -= 1
			ev = Ev.SHOT
	return ev


## Which way the body faces: where the camera looks while aiming / drawing / in first person; otherwise it turns
## toward the way you walk. A melee swing is committed to its direction, except that pressing a direction as it starts
## turns you to it.
static func _face(s: PlayerState, inp: PlayerInput, wish: Vector2, w: Dictionary, mv: Dictionary, alive: bool) -> void:
	if not alive:
		return
	var moving := wish.length_squared() > 0.0
	var want := atan2(-wish.x, -wish.y) if moving else s.yaw
	# the body faces the camera's heading when aiming or attacking. Not the line from the body to the crosshair point:
	# the camera sits over the shoulder, so up close (a dummy, a wall) that line swung the body 10-20 degrees sideways.
	# Shots still fly at the crosshair point (inp.aim_yaw, used where the projectile is made).
	if inp.buttons & Btn.FACE_CAM or s.charge > 0:
		s.yaw = inp.yaw
		return
	# holding attack: keep turning toward where the camera looks, mid-swing too, so swinging the camera round steers the
	# blows. Fast while winding up; once a melee blow has landed the follow-through is committed, so it turns slower;
	# a tiny dead zone stops the body twitching on small mouse moves
	if inp.buttons & Btn.ATTACK:
		var rate := ATTACK_TURN_RATE
		if w.kind == "melee" and s.atk > 0 and int(mv.swing) - s.atk >= int(mv.windup):
			rate *= 0.4
		var da := wrapf(inp.yaw - s.yaw, -PI, PI)
		if absf(da) > 0.035:
			var st := rate * Config.DT
			s.yaw = wrapf(s.yaw + clampf(da, -st, st), -PI, PI)
		return
	if w.kind == "melee" and s.atk > 0:
		if s.atk == int(mv.swing) and moving:
			s.yaw = want
		return
	if moving:
		var d := wrapf(want - s.yaw, -PI, PI)
		var step := TURN_RATE * Config.DT
		s.yaw = wrapf(s.yaw + clampf(d, -step, step), -PI, PI)


## The player is an upright cylinder (radius RADIUS) against the pillars: land on a top when coming down onto it,
## otherwise get pushed out sideways and lose the velocity into the wall (so you slide along it).
static func _collide_boxes(s: PlayerState, prev_y: float) -> void:
	for b: WorldLayout.Box in WorldLayout.boxes():
		var nx := clampf(s.pos.x, b.cx - b.hx, b.cx + b.hx)
		var nz := clampf(s.pos.z, b.cz - b.hz, b.cz + b.hz)
		var dx := s.pos.x - nx
		var dz := s.pos.z - nz
		var d2 := dx * dx + dz * dz
		if d2 >= RADIUS * RADIUS:
			continue
		if prev_y >= b.h - 0.01 and s.pos.y <= b.h + 0.01 and s.vel.y <= 0.0:
			s.pos.y = b.h  # standing on top
			s.vel.y = 0.0
			s.grounded = true
		elif s.pos.y < b.h - 0.01:
			var n := Vector2.ZERO
			var depth := 0.0
			if d2 > 1e-12:
				var dl := sqrt(d2)
				n = Vector2(dx, dz) / dl
				depth = RADIUS - dl
			else:  # centre inside the box: out through the nearest face
				var faces := [[b.cx + b.hx - s.pos.x, Vector2(1, 0)], [s.pos.x - (b.cx - b.hx), Vector2(-1, 0)],
					[b.cz + b.hz - s.pos.z, Vector2(0, 1)], [s.pos.z - (b.cz - b.hz), Vector2(0, -1)]]
				faces.sort_custom(func(p, q): return p[0] < q[0])
				n = faces[0][1]
				depth = faces[0][0] + RADIUS
			s.pos.x += n.x * depth
			s.pos.z += n.y * depth
			var into := s.vel.x * n.x + s.vel.z * n.y
			if into < 0.0:
				s.vel.x -= n.x * into
				s.vel.z -= n.y * into


## Round to float32, the precision snapshots carry, so the server's state and the client's copy match bit for bit.
static func quantize(s: PlayerState) -> void:
	var a := PackedFloat32Array([s.pos.x, s.pos.y, s.pos.z, s.vel.x, s.vel.y, s.vel.z, s.yaw])
	s.pos = Vector3(a[0], a[1], a[2])
	s.vel = Vector3(a[3], a[4], a[5])
	s.yaw = a[6]
