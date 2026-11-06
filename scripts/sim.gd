## The movement simulation, run identically by the server (the authority) and the client (prediction).
## It must stay deterministic: the same state and input give the same result on both sides, so predictions match the
## server and corrections are rare and tiny. No randomness, no wall-clock time, only fixed DT steps.
class_name Sim

## FACE_CAM: face where the camera looks (aiming, first person) instead of the way you walk.
## BLOCK (v0.12.5, the right mouse button): brace behind your weapon (Weapons.block_keep), facing the crosshair.
enum Btn { FORWARD = 1, BACK = 2, LEFT = 4, RIGHT = 8, JUMP = 16, SPRINT = 32, DASH = 64, ATTACK = 128, INTERACT = 256, FACE_CAM = 512, BLOCK = 1024 }

## What a step reports, for the server to act on (hit test, launch a projectile) and the client to show.
enum Ev { NONE, MELEE_HIT, SHOT, CAST }

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
const SLOW_FACTOR := 0.5     # how fast you move while slowed (frost nova)
const MANA_FULL := 500       # Weapons.MAX_MANA in fifths: one fifth comes back each tick (12 mana a second)
# v0.11.0 Static (Thunderhorn's build-up stun): every static hit adds ZAP_STACK; ZAP_HOLD ticks after the last hit it
# drains one point a tick (a stack every 3.3 s). The server stuns at Boss.static_need() stacks and marks the meter
# ZAP_STUN while that stun lasts; it empties when the stun ends.
const ZAP_STACK := 200
const ZAP_HOLD := 150
const ZAP_STUN := 4000
const STATIC_STUN := 420     # 7 s
# v0.11.0 knocked down (launched by Thunderhorn's rush): no control; the last DOWN_GETUP ticks are the get-up
const DOWN_TICKS := 140
const DOWN_GETUP := 45
# v0.12.0 thrown by a charge: bounces on hard landings, ricochets off walls (some speed lost each time)
const BOUNCE_MIN := 4.0
const BOUNCE_K := 0.5
const RICOCHET_K := 0.6
# v0.12.5 blocking: hold the block button to brace (not mid-swing, drawing, casting, shielded, stunned, down or
# dashing; a dash drops the guard). Braced: no attacking or casting, walking at GUARD_SLOW (no sprint), facing the
# crosshair. `guard` counts the ticks it has been up; a hit only counts as blocked from GUARD_UP on (raising it takes
# a moment), and only from the front (Weapons.GUARD_ARC).
const GUARD_SLOW := 0.5
const GUARD_UP := 5


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
	var face_yaw := 0.0     # where the body should face to attack: from the body to what the crosshair is on
	var spell := 0          # the spell picked for a staff or wand (0-2)
	var aim_point := Vector3.ZERO   # what the crosshair is on (spells land there; teleport goes toward it)

	func _init(s := 0, b := 0, y := 0.0, p := 0.0, w := 0, v := 0, ay := 0.0, fy := INF, sp := 0, ap := Vector3.ZERO) -> void:
		seq = s
		buttons = b
		yaw = y
		pitch = p
		weapon = w
		view_tick = v
		aim_yaw = ay
		face_yaw = y if is_inf(fy) else fy
		spell = sp
		aim_point = ap


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
	var mana := MANA_FULL   # magic power, in fifths of a point (Weapons.MAX_MANA * 5 when full)
	var spell := 0          # the spell picked for the staff / wand
	var shield := 0         # ticks the shield bubble has left
	var stun := 0           # ticks left held in place by a stun (no moving, attacking or casting)
	var recharge := [0, 0, 0, 0, 0, 0, 0, 0]   # the wand's spells (v0.12.0: 8): ticks until each can be cast again
	var slow := 0           # ticks left slowed (frost): moving at SLOW_FACTOR
	var staff_lvl := 1      # the staff's level (kills unlock spells: Weapons.LEVEL_KILLS)
	var wand_lvl := 1
	var zap := 0            # v0.11.0: static build-up (ZAP_STACK a hit), ZAP_STUN while static-stunned
	var zap_cd := 0         # ticks before the static starts draining
	var down := 0           # ticks left knocked down (launched): no control, getting up at the end
	var guard := 0          # v0.12.5: ticks the block has been held up (0 = not blocking), up to 255

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
		s.mana = mana
		s.spell = spell
		s.shield = shield
		s.stun = stun
		s.recharge = recharge.duplicate()
		s.slow = slow
		s.staff_lvl = staff_lvl
		s.wand_lvl = wand_lvl
		s.zap = zap
		s.zap_cd = zap_cd
		s.down = down
		s.guard = guard
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
	if s.shield > 0:
		s.shield -= 1
	if s.stun > 0:   # held in place: the input does nothing until it wears off
		s.stun -= 1
		inp = PlayerInput.new(inp.seq, 0, inp.yaw, inp.pitch, s.weapon, inp.view_tick, s.yaw, s.yaw, s.spell, s.pos)
		s.charge = 0
	if s.down > 0:   # knocked down: flying, sliding, lying, getting up; no control
		# v0.12.0: the clock waits while still tumbling or skidding, so the get-up never starts mid-flight
		if s.down > DOWN_GETUP + 20 or (s.grounded and Vector2(s.vel.x, s.vel.z).length() < 2.0):
			s.down -= 1
		inp = PlayerInput.new(inp.seq, 0, inp.yaw, inp.pitch, s.weapon, inp.view_tick, s.yaw, s.yaw, s.spell, s.pos)
		s.charge = 0
	if s.zap >= ZAP_STUN:
		if s.stun == 0:
			s.zap = 0
	elif s.zap > 0:
		if s.zap_cd > 0:
			s.zap_cd -= 1
		else:
			s.zap -= 1
	if s.dead > 0:
		s.zap = 0
		s.down = 0
	var ev := _combat(s, inp)
	if ev == Ev.CAST:
		_cast_self(s, inp)
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
	var busy: bool = s.charge > 0 or (s.atk > 0 and w.kind != "ranged") or s.guard > 0
	var speed := SPRINT_SPEED if inp.buttons & Btn.SPRINT and not busy else WALK_SPEED
	if s.guard > 0:
		speed *= GUARD_SLOW   # braced: a slow, guarded walk
	elif busy or s.shield > 0:
		speed *= w.slow   # drawing a bow, mid-swing, casting or holding the shield up: slower
	if s.slow > 0:
		speed *= SLOW_FACTOR
	if not alive or s.stun > 0 or s.down > 0:
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
		if s.down > 0:   # launched: no air control, a long slide on landing
			accel = (24.0 if s.grounded else 0.0) * Config.DT
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

	if s.grounded and inp.buttons & Btn.JUMP and alive and s.stun == 0 and s.down == 0:
		s.vel.y = JUMP_SPEED
		s.grounded = false
	if not s.grounded and s.dash_ticks == 0:
		s.vel.y -= GRAVITY * Config.DT

	var prev_y := s.pos.y
	s.pos += s.vel * Config.DT

	s.grounded = false
	var thrown := s.down > 0 and s.dead == 0
	if s.pos.y <= 0.0:  # the ground plane
		s.pos.y = 0.0
		if thrown and s.vel.y < -BOUNCE_MIN:   # v0.12.0 thrown: smashed into the ground, it bounces back up
			s.vel.y = -s.vel.y * BOUNCE_K
			s.vel.x *= 0.82
			s.vel.z *= 0.82
		else:
			s.vel.y = 0.0
			s.grounded = true
	var hv := Vector2(s.vel.x, s.vel.z)
	_collide_boxes(s, prev_y)
	_collide_altar(s, prev_y)
	_collide_dummies(s)
	if thrown and hv.length() > 4.0:   # ricochet off pillars, trunks and posts instead of sliding along them
		var nv := Vector2(s.vel.x, s.vel.z)
		var lost := hv - nv
		if lost.length() > 1.0:
			var n := lost.normalized()   # (the wall's normal, pointing into it)
			var rv := (hv - n * 2.0 * hv.dot(n)) * RICOCHET_K
			s.vel.x = rv.x
			s.vel.z = rv.y
			s.vel.y = maxf(s.vel.y, 3.0)
	var lim := Config.WORLD_HALF  # the edge of the world
	if thrown and (absf(s.pos.x) > lim or absf(s.pos.z) > lim):   # thrown into the edge: back off it
		if absf(s.pos.x) > lim:
			s.vel.x = -signf(s.pos.x) * absf(s.vel.x) * RICOCHET_K
		if absf(s.pos.z) > lim:
			s.vel.z = -signf(s.pos.z) * absf(s.vel.z) * RICOCHET_K
	if absf(s.pos.x) > lim:
		s.pos.x = clampf(s.pos.x, -lim, lim)
		s.vel.x = 0.0 if not thrown else s.vel.x
	if absf(s.pos.z) > lim:
		s.pos.z = clampf(s.pos.z, -lim, lim)
		s.vel.z = 0.0 if not thrown else s.vel.z

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
	if s.mana < MANA_FULL and s.shield == 0 and not (s.atk > 0 and Weapons.is_magic(s.weapon)):
		s.mana += 1   # not while casting, nor while the shield is held up
	for i in s.recharge.size():
		if s.recharge[i] > 0:
			s.recharge[i] -= 1
	if s.slow > 0:
		s.slow -= 1
	var want := inp.weapon
	if want != s.weapon and want >= 0 and want < Weapons.DATA.size() and (s.owned >> want) & 1 and s.atk == 0 and s.charge == 0:
		s.weapon = want
		s.combo = 0
		s.combo_t = 0
	var w := Weapons.get_data(s.weapon)
	var attack := inp.buttons & Btn.ATTACK != 0
	# v0.12.5: bracing behind the weapon (any weapon, fists too): no attacking or casting while it's up
	var brace: bool = inp.buttons & Btn.BLOCK != 0 and s.atk == 0 and s.charge == 0 and s.shield == 0 \
		and s.stun == 0 and s.down == 0 and s.dash_ticks == 0
	s.guard = mini(s.guard + 1, 255) if brace else 0
	if s.guard > 0:
		return ev
	if w.kind == "magic":
		var lvl := s.staff_lvl if s.weapon == Weapons.STAFF else s.wand_lvl
		if s.atk == 0 and s.shield == 0 and inp.spell != s.spell and Weapons.unlocked(s.weapon, inp.spell, lvl):
			s.spell = inp.spell
		var sp := Weapons.spell(s.weapon, s.spell)
		if sp.get("hold", false):   # the shield: up while the button is held; raising it costs its mana once
			if attack and s.shield > 0:
				s.shield = 2
			elif attack and s.atk_cd == 0 and s.mana >= int(sp.cost) * 5:
				s.mana -= int(sp.cost) * 5
				s.shield = 2
				s.atk_cd = int(sp.cooldown)
				s.swing_n = (s.swing_n + 1) % 256
				ev = Ev.CAST
			return ev
		if sp.get("channel", false):   # v0.12.0 Heal Aura: held; `atk` stays up while it channels (no mana back)
			if attack and s.atk_cd == 0 and s.mana >= int(sp.drain):
				s.mana -= int(sp.drain)
				if s.atk == 0:
					s.swing_n = (s.swing_n + 1) % 256
					ev = Ev.CAST
				s.atk = 2
			elif s.atk == 1:   # let go or out of mana: it ends
				s.atk_cd = int(sp.cooldown)
			return ev
		var ready: bool = s.recharge[s.spell] == 0 if w.get("uses", "mana") == "recharge" else s.mana >= int(sp.cost) * 5
		if attack and s.atk == 0 and s.atk_cd == 0 and ready:
			s.mana -= int(sp.cost) * 5
			if w.get("uses", "mana") == "recharge":
				s.recharge[s.spell] = int(sp.recharge)
			s.atk = int(sp.cast)
			s.atk_cd = int(sp.cast) + int(sp.cooldown)
			s.swing_n = (s.swing_n + 1) % 256
		elif s.atk > 0 and s.atk == int(sp.cast) - int(sp.windup):
			ev = Ev.CAST
		return ev
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


## v0.12.0: is this player channelling the Heal Aura right now?
static func channeling(s: PlayerState) -> bool:
	return s.atk > 0 and s.dead == 0 and Weapons.is_magic(s.weapon) and bool(Weapons.spell(s.weapon, s.spell).get("channel", false))


## The spells that change the caster (worked out here so the client predicts them exactly): the shield bubble, and
## the teleport: straight toward what the crosshair is on, in any direction (along the ground, up onto a pillar's top,
## or up into the air, to fall from there), as far as that point but never more than the spell's reach (five dashes);
## a blink, so only where you arrive matters: if you wouldn't fit there, you arrive a little short of it.
static func _cast_self(s: PlayerState, inp: PlayerInput) -> void:
	var sp := Weapons.spell(s.weapon, s.spell)
	if s.weapon == Weapons.WAND and sp.name == "Teleport":
		s.pos = teleport_target(s.pos, s.yaw, inp.aim_point, float(sp.range))
		s.vel = Vector3.ZERO
		s.grounded = false


static func teleport_target(from: Vector3, yaw: float, aim: Vector3, reach: float) -> Vector3:
	var to := aim - from
	if to.length() < 0.5:   # nothing under the crosshair: straight ahead
		to = Vector3(-sin(yaw), 0, -cos(yaw)) * reach
	var dist := minf(to.length(), reach)
	var dir := to.normalized()
	var best := dist   # a blink: only where you arrive matters; step back toward you until the body fits there
	while best > 0.0 and _body_in_box(_on_top(from + dir * best)):
		best = maxf(best - 0.25, 0.0)
	var e := _on_top(from + dir * best)
	return Vector3(e.x, e.y + 0.02, e.z)


## A point lifted onto the top under it, if it is just below a top (aimed at the top surface).
static func _on_top(q: Vector3) -> Vector3:
	var top := WorldLayout.ground_height(q.x, q.z, q.y + 0.6)
	return Vector3(q.x, maxf(maxf(q.y, top), 0.0), q.z)


static func _body_in_box(q: Vector3) -> bool:
	for b: WorldLayout.Box in WorldLayout.boxes():
		if absf(q.x - b.cx) < b.hx + RADIUS and absf(q.z - b.cz) < b.hz + RADIUS and q.y < b.h - 0.05 and q.y + 1.8 > 0.0:
			return true
	return false


## Which way the body faces: where the camera looks while aiming / drawing / in first person; otherwise it turns
## toward the way you walk. A melee swing is committed to its direction, except that pressing a direction as it starts
## turns you to it.
static func _face(s: PlayerState, inp: PlayerInput, wish: Vector2, w: Dictionary, mv: Dictionary, alive: bool) -> void:
	if not alive:
		return
	var moving := wish.length_squared() > 0.0
	var want := atan2(-wish.x, -wish.y) if moving else s.yaw
	# aiming or attacking, the body faces what the crosshair is on, measured from the body's centre (inp.face_yaw, worked
	# out on the client). Not the camera heading (the camera sits over the shoulder, so up close that misses the target
	# by the shoulder offset) and not the line from the weapon's tip (up close that swung the body sideways). Shots
	# still fly from the tip at the crosshair point (inp.aim_yaw, used where the projectile is made).
	if inp.buttons & Btn.FACE_CAM or s.charge > 0 or s.guard > 0:   # (braced: facing what you're guarding against)
		s.yaw = inp.face_yaw
		return
	# holding attack: keep turning toward where the camera looks, mid-swing too, so swinging the camera round steers the
	# blows. Fast while winding up; once a melee blow has landed the follow-through is committed, so it turns slower;
	# a tiny dead zone stops the body twitching on small mouse moves
	if inp.buttons & Btn.ATTACK:
		var rate := ATTACK_TURN_RATE
		if w.kind == "melee" and s.atk > 0 and int(mv.swing) - s.atk >= int(mv.windup):
			rate *= 0.4
		var da := wrapf(inp.face_yaw - s.yaw, -PI, PI)
		if absf(da) > 0.035:
			var st := rate * Config.DT
			s.yaw = wrapf(s.yaw + clampf(da, -st, st), -PI, PI)
		return
	if w.kind == "magic" and s.atk > 0:   # casting: stays facing where the spell was aimed
		return
	if s.stun > 0:
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


## v0.12.0 the Storm Altar's button: a solid drum for anyone at level 3 (below that it lies sunk in the ground).
## Coming down onto it you stand on its top; walking into its side pushes you out.
static func _collide_altar(s: PlayerState, prev_y: float) -> void:
	if maxi(s.staff_lvl, s.wand_lvl) < 3:
		return
	var c := WorldLayout.ALTAR_C
	var d := Vector2(s.pos.x - c.x, s.pos.y * 0.0 + s.pos.z - c.y)
	var r := WorldLayout.ALTAR_BTN_R
	if d.length() >= r + RADIUS * 0.5:
		return
	var top := WorldLayout.altar_top()
	if prev_y >= top - 0.01 and s.pos.y <= top + 0.01 and s.vel.y <= 0.0 and d.length() < r:
		s.pos.y = top   # standing on it
		s.vel.y = 0.0
		s.grounded = true
	elif s.pos.y < top - 0.01 and s.pos.y < prev_y + 0.5 and not (prev_y >= top - 0.01 and d.length() < r):
		var n := d.normalized() if d.length() > 1e-4 else Vector2(1, 0)
		var out := c + n * (r + RADIUS * 0.5)
		s.pos.x = out.x
		s.pos.z = out.y
		var into := s.vel.x * n.x + s.vel.z * n.y
		if into < 0.0:
			s.vel.x -= n.x * into
			s.vel.z -= n.y * into


## The practice dummies are solid: upright posts of radius DUMMY_RADIUS you can walk right up to but not through.
const DUMMY_RADIUS := 0.3

static func _collide_dummies(s: PlayerState) -> void:
	var r := RADIUS + DUMMY_RADIUS
	for dp: Vector3 in WorldLayout.DUMMIES:
		if s.pos.y > 1.9:
			continue
		var dx := s.pos.x - dp.x
		var dz := s.pos.z - dp.z
		var d2 := dx * dx + dz * dz
		if d2 >= r * r:
			continue
		var dl := sqrt(d2)
		var n := Vector2(dx, dz) / dl if dl > 1e-6 else Vector2(0, 1)
		s.pos.x = dp.x + n.x * r
		s.pos.z = dp.z + n.y * r
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
