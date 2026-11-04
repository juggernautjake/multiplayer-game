## Tier-one weapons (Jacob 2026-11-04: low damage, 6-10 a hit, about fist level). Weapon definitions, shared by the server and every client (the simulation reads timings from here, so attacks are
## predicted exactly like movement). Times are in ticks (60 per second). Later this becomes data files, one per item.
class_name Weapons

enum { CLUB, SWORD, BOW, SLING }
const NAMES := ["Club", "Sword", "Bow", "Slingshot"]

## Melee: the hit lands `windup` ticks into a swing lasting `swing` ticks; you can't swing again for `cooldown`.
## Ranged: hold to draw (up to `draw` ticks), release to shoot; speed and damage scale with how far you drew.
const DATA := [
	{ "kind": "melee", "range": 2.3, "arc": 115.0, "damage": 9, "windup": 9, "swing": 25, "cooldown": 32, "knock": 3.5, "slow": 0.55, "lunge": 3.2 },
	{ "kind": "melee", "range": 2.6, "arc": 90.0, "damage": 8, "windup": 6, "swing": 20, "cooldown": 22, "knock": 2.0, "slow": 0.7, "lunge": 4.0 },
	{ "kind": "ranged", "draw": 45, "min_speed": 22.0, "max_speed": 58.0, "min_damage": 6, "max_damage": 10,
	  "gravity": 9.8, "shot": 16, "cooldown": 28, "slow": 0.45, "projectile": "arrow" },
	{ "kind": "ranged", "draw": 16, "min_speed": 22.0, "max_speed": 38.0, "min_damage": 6, "max_damage": 8,
	  "gravity": 14.0, "shot": 12, "cooldown": 14, "slow": 0.75, "projectile": "stone" },
]


static func get_data(w: int) -> Dictionary:
	return DATA[clampi(w, 0, DATA.size() - 1)]


static func is_melee(w: int) -> bool:
	return get_data(w).kind == "melee"


## Where a shot starts: chest height, half a metre in front.
static func muzzle(pos: Vector3, yaw: float) -> Vector3:
	return pos + Vector3(0, 1.35, 0) + Vector3(-sin(yaw), 0, -cos(yaw)) * 0.5


static func aim_dir(yaw: float, pitch: float) -> Vector3:
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))


## A projectile's position n ticks after launch. Closed form of the per-tick steps (gravity, then move), so the
## server and every client get exactly the same flight with no position updates sent at all.
static func proj_pos(pos0: Vector3, vel0: Vector3, g: float, n: float) -> Vector3:
	var t := n * Config.DT
	return pos0 + vel0 * t - Vector3(0, g * Config.DT * Config.DT * n * (n + 1.0) / 2.0, 0)


static func proj_vel(vel0: Vector3, g: float, n: float) -> Vector3:
	return vel0 - Vector3(0, g * Config.DT * n, 0)


## Launch speed and damage for a ranged shot drawn `charge` ticks.
static func shot(w: int, charge: int) -> Array:
	var d := get_data(w)
	var k := clampf(float(charge) / float(d.draw), 0.0, 1.0)
	return [lerpf(d.min_speed, d.max_speed, k), int(round(lerpf(d.min_damage, d.max_damage, k)))]
