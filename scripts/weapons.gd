## Tier-one weapons (Jacob 2026-11-04: low damage, 6-10 a hit, about fist level), shared by the server and every client:
## the simulation reads the timings from here, so attacks are predicted exactly like movement. Times are in ticks
## (60 per second). Later this becomes data files, one per item.
##
## Every melee weapon is a combo of distinct moves: press attack again during the window after a move to chain the
## next one; the last is a finisher with its own feel. Ranged weapons draw while you hold and fire when you let go,
## and use ammo (arrows, rocks) that you pick up.
class_name Weapons

enum { FISTS, CLUB, SWORD, BOW, SLING }
const NAMES := ["Fists", "Club", "Sword", "Bow", "Slingshot"]
const COMBO_WINDOW := 18   # ticks after a move ends in which pressing attack chains the next

## Melee moves: windup (ticks before the hit lands), swing (whole move), recover (extra cooldown after it),
## range (m), arc (degrees in front), damage, knock (m/s), lunge (m/s forward during the windup), anim (Pip's row),
## shape: "arc" sweep, "thrust" narrow stab, "smash" overhead with a ground shockwave (aoe metres around the impact).
const DATA := [
	{ "kind": "melee", "slow": 0.8, "moves": [
		{ "name": "jab", "windup": 4, "swing": 14, "recover": 0, "range": 1.5, "arc": 50.0, "damage": 6, "knock": 1.0, "lunge": 2.0, "anim": "jab", "shape": "thrust" },
		{ "name": "cross", "windup": 5, "swing": 16, "recover": 0, "range": 1.6, "arc": 55.0, "damage": 6, "knock": 1.5, "lunge": 2.5, "anim": "cross", "shape": "thrust" },
		{ "name": "kick", "windup": 9, "swing": 26, "recover": 10, "range": 1.9, "arc": 80.0, "damage": 7, "knock": 3.5, "lunge": 1.5, "anim": "kick", "shape": "arc" },
	] },
	{ "kind": "melee", "slow": 0.55, "moves": [
		{ "name": "bash", "windup": 13, "swing": 30, "recover": 0, "range": 2.2, "arc": 120.0, "damage": 8, "knock": 3.5, "lunge": 2.5, "anim": "c_swing", "shape": "arc" },
		{ "name": "backhand", "windup": 11, "swing": 28, "recover": 0, "range": 2.2, "arc": 120.0, "damage": 8, "knock": 3.5, "lunge": 2.0, "anim": "c_back", "shape": "arc" },
		{ "name": "smash", "windup": 20, "swing": 42, "recover": 18, "range": 2.4, "arc": 70.0, "damage": 10, "knock": 6.0, "lunge": 1.5, "anim": "c_smash", "shape": "smash", "aoe": 2.3 },
	] },
	{ "kind": "melee", "slow": 0.75, "moves": [
		{ "name": "slash", "windup": 5, "swing": 17, "recover": 0, "range": 2.5, "arc": 100.0, "damage": 7, "knock": 1.5, "lunge": 4.0, "anim": "s_swing", "shape": "arc" },
		{ "name": "backslash", "windup": 5, "swing": 17, "recover": 0, "range": 2.5, "arc": 100.0, "damage": 7, "knock": 1.5, "lunge": 4.0, "anim": "s_back", "shape": "arc" },
		{ "name": "thrust", "windup": 9, "swing": 28, "recover": 14, "range": 3.3, "arc": 28.0, "damage": 10, "knock": 4.5, "lunge": 10.0, "anim": "s_smash", "shape": "thrust" },
	] },
	{ "kind": "ranged", "draw": 45, "min_speed": 22.0, "max_speed": 58.0, "min_damage": 6, "max_damage": 10,
	  "gravity": 9.8, "shot": 16, "cooldown": 28, "slow": 0.35, "projectile": "arrow", "ammo": "arrows" },
	{ "kind": "ranged", "draw": 20, "min_speed": 20.0, "max_speed": 36.0, "min_damage": 6, "max_damage": 8,
	  "gravity": 14.0, "shot": 12, "cooldown": 14, "slow": 0.85, "projectile": "stone", "ammo": "rocks" },
]


static func get_data(w: int) -> Dictionary:
	return DATA[clampi(w, 0, DATA.size() - 1)]


static func is_melee(w: int) -> bool:
	return get_data(w).kind == "melee"


## The move a melee weapon is on (combo step), or {} for ranged.
static func move(w: int, combo: int) -> Dictionary:
	var d := get_data(w)
	if d.kind != "melee":
		return {}
	var moves: Array = d.moves
	return moves[clampi(combo, 0, moves.size() - 1)]


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


# ---------------------------------------------------------------------------------------------- items on the ground
## Pick-ups: the four weapons and two kinds of ammo. Weapons are kept for good once picked up (one bit each in
## PlayerState.owned); ammo adds to a count.
enum Item { CLUB, SWORD, BOW, SLING, ARROWS, ROCKS }
const ITEM_NAMES := ["Club", "Sword", "Bow", "Slingshot", "Arrows", "Rocks"]
const ITEM_WEAPON := [CLUB, SWORD, BOW, SLING, -1, -1]
const MAX_AMMO := 60
