## How the staff and the wand move while a spell is cast (v0.8.0), shared by Pip (his 3D staff / wand prop) and the 3D
## figure (its hands): every spell has its own gesture, each with anticipation (a pull back or a raise before it goes
## off), a fast release with overshoot, and a follow-through that settles back:
##   thrust  (Fireball, Stun, Teleport, Spark Beam, Life Drain): pull back and low, then drive forward past the arm's length, recoil, settle;
##   sky     (Lightning, Meteor, Arcane Storm): raise it high over the head with a slow twirl, then bring it down to
##            point at the target;
##   slam    (Frost Nova): raise it, then drive it into the ground (a crouch and a jolt);
##   summon  (Golem, Stone Titan): circle the tip over the ground in front, then point down hard;
##   vortex  (Gravity Well, Fog): the tip circles faster and faster, then thrusts.
## The wand adds a flourish (the tip traces small loops) while the spell builds. Purely visual: worked out from the
## player's state on every client.
class_name CastPose

const STYLE := { "Fireball": "thrust", "Stun": "thrust", "Teleport": "thrust", "Lightning": "sky", "Meteor": "sky",
	"Arcane Storm": "sky", "Frost Nova": "slam", "Golem": "summon", "Stone Titan": "summon",
	"Gravity Well": "vortex", "Fog": "vortex", "Spark Beam": "thrust", "Life Drain": "thrust" }


static func _ease_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


static func _smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## into: ticks since the cast began; windup: ticks until it goes off; cast: ticks of the whole move.
## -> reach (forward, -0.4 pulled back .. 1.2 overshoot), lift (m), side (m), aim (rad: 0 = the weapon straight up,
## PI/2 = pointing ahead, more = pointing down), crouch (m), lean (rad, + forward), flare (the orb's glow, 0..1.6),
## two_hand (the free hand joins on the staff).
static func at(w: int, spell: String, into: float, windup: float, cast: float) -> Dictionary:
	var staff := w == Weapons.STAFF
	var style: String = STYLE.get(spell, "thrust")
	var a := clampf(into / maxf(windup, 1.0), 0.0, 1.0)                       # through the wind-up
	var r := clampf((into - windup) / maxf(cast - windup, 1.0), 0.0, 1.0)     # through the release and recovery
	var released := into >= windup
	var settle := 1.0 - _smooth((r - 0.45) / 0.55)                            # back to rest at the end
	var rest_aim := 0.15 if staff else 1.35
	var o := { "reach": 0.0, "lift": 0.0, "side": 0.0, "aim": rest_aim, "crouch": 0.0, "lean": 0.0, "flare": 0.0, "two_hand": false }
	var spring := exp(-r * 6.0) * sin(r * 16.0)    # the overshoot wobble just after it goes off
	match style:
		"thrust":
			if not released:
				o.reach = -0.38 * _smooth(a)
				o.lift = 0.12 * a
				o.lean = -0.08 * a
				o.aim = lerpf(rest_aim, (0.9 if staff else 1.25), a)
			else:
				o.reach = (lerpf(-0.38, 1.0, _ease_out(r * 4.0)) + 0.18 * spring) * settle
				o.lift = 0.12 * settle
				o.lean = (0.14 * _ease_out(r * 4.0)) * settle
				o.aim = lerpf(rest_aim, PI * 0.5 if not staff else 1.05, settle)
			o.two_hand = staff
		"sky":
			if not released:
				o.lift = 0.62 * _smooth(a)
				o.reach = -0.1 * a
				o.side = 0.05 * sin(a * TAU)
				o.lean = -0.16 * a
				o.aim = lerpf(rest_aim, 0.0, a)
			else:
				var k := _ease_out(r * 3.5)
				o.lift = lerpf(0.62, 0.15, k) * settle
				o.reach = (0.85 * k + 0.12 * spring) * settle
				o.lean = 0.12 * k * settle
				o.aim = lerpf(0.0, 1.3, k) * settle + rest_aim * (1.0 - settle)
			o.two_hand = false
		"slam":
			if not released:
				o.lift = 0.5 * _smooth(a)
				o.reach = 0.1 * a
				o.lean = -0.12 * a
				o.aim = rest_aim
			else:
				var k := _ease_out(r * 6.0)
				o.lift = lerpf(0.5, -0.38, k) * settle
				o.reach = 0.3 * settle
				o.crouch = (0.2 * k + 0.05 * spring) * settle
				o.lean = 0.22 * k * settle
				o.aim = lerpf(rest_aim, 0.35 if staff else 2.1, k * settle)
			o.two_hand = staff
		"summon":
			var loop := a * TAU * 2.0
			if not released:
				o.reach = 0.35 * _smooth(a)
				o.lift = -0.05 * a + 0.07 * sin(loop) * a
				o.side = 0.09 * cos(loop) * a
				o.aim = lerpf(rest_aim, 2.0, a)
				o.lean = 0.1 * a
			else:
				var k := _ease_out(r * 5.0)
				o.reach = (0.35 + 0.35 * k + 0.1 * spring) * settle
				o.lift = -0.25 * k * settle
				o.aim = lerpf(2.0, 2.3, k) * settle + rest_aim * (1.0 - settle)
				o.crouch = 0.08 * k * settle
				o.lean = 0.16 * settle
			o.two_hand = staff
		"vortex":
			var spin := pow(a, 1.6) * TAU * 3.0
			if not released:
				o.side = 0.1 * cos(spin) * a
				o.lift = 0.15 * a + 0.1 * sin(spin) * a
				o.reach = 0.2 * a
				o.aim = lerpf(rest_aim, 1.2, a)
			else:
				o.reach = (lerpf(0.2, 1.0, _ease_out(r * 4.0)) + 0.15 * spring) * settle
				o.lift = 0.15 * settle
				o.aim = lerpf(rest_aim, 1.35, settle)
				o.lean = 0.12 * settle
	# the wand's flourish: the tip traces quick small loops while the spell builds
	if not staff and not released and style != "summon":
		var f := a * TAU * 2.5
		o.side = float(o.side) + 0.045 * cos(f) * a
		o.lift = float(o.lift) + 0.045 * sin(f) * a
	o.flare = (a if not released else clampf(1.6 - r * 3.0, 0.0, 1.6))
	return o
