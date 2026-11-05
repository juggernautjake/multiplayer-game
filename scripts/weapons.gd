## Tier-one weapons (Jacob 2026-11-04: low damage, 6-10 a hit, about fist level; the sword a little above the club), shared by the server and every client:
## the simulation reads the timings from here, so attacks are predicted exactly like movement. Times are in ticks
## (60 per second). Later this becomes data files, one per item.
##
## Every melee weapon is a combo of distinct moves: press attack again during the window after a move to chain the
## next one; the last is a finisher with its own feel. Ranged weapons draw while you hold and fire when you let go,
## and use ammo (arrows, rocks) that you pick up.
class_name Weapons

enum { FISTS, CLUB, SWORD, BOW, SLING, STAFF, WAND }
const NAMES := ["Fists", "Club", "Sword", "Bow", "Slingshot", "Staff", "Wand"]
const COMBO_WINDOW := 18   # ticks after a move ends in which pressing attack chains the next
const CANCEL_AT := 0.35    # a combo can cancel into its next move once only this much of the recovery is left

## Timings follow how souls-likes feel (readable wind-up, a very fast strike, a long committed recovery; the next
## combo move can cancel in 65% of the way through the recovery).
## Melee moves: windup (ticks before the hit lands), swing (whole move), recover (extra cooldown after it),
## range (m), arc (degrees in front), damage, knock (m/s), lunge (m/s forward during the windup), anim (Pip's row),
## shape: "arc" sweep, "thrust" narrow stab, "smash" overhead with a ground shockwave (aoe metres around the impact).
const DATA := [
	{ "kind": "melee", "slow": 0.8, "moves": [
		{ "name": "jab", "windup": 7, "swing": 24, "recover": 0, "range": 1.5, "arc": 50.0, "damage": 6, "knock": 1.0, "lunge": 2.0, "anim": "jab", "shape": "thrust" },
		{ "name": "cross", "windup": 9, "swing": 28, "recover": 0, "range": 1.6, "arc": 55.0, "damage": 6, "knock": 1.5, "lunge": 2.5, "anim": "cross", "shape": "thrust" },
		{ "name": "kick", "windup": 14, "swing": 40, "recover": 8, "range": 1.9, "arc": 80.0, "damage": 7, "knock": 3.5, "lunge": 1.5, "anim": "kick", "shape": "arc" },
	] },
	{ "kind": "melee", "slow": 0.55, "moves": [
		{ "name": "bash", "windup": 24, "swing": 60, "recover": 0, "range": 2.2, "arc": 120.0, "damage": 7, "knock": 3.5, "lunge": 2.5, "anim": "c_swing", "shape": "arc" },
		{ "name": "backhand", "windup": 22, "swing": 56, "recover": 0, "range": 2.2, "arc": 120.0, "damage": 7, "knock": 3.5, "lunge": 2.0, "anim": "c_back", "shape": "arc" },
		{ "name": "smash", "windup": 34, "swing": 78, "recover": 10, "range": 2.4, "arc": 70.0, "damage": 9, "knock": 6.0, "lunge": 1.5, "anim": "c_smash", "shape": "smash", "aoe": 2.3 },
	] },
	{ "kind": "melee", "slow": 0.75, "moves": [
		{ "name": "slash", "windup": 12, "swing": 36, "recover": 0, "range": 2.5, "arc": 100.0, "damage": 8, "knock": 1.5, "lunge": 4.0, "anim": "s_swing", "shape": "arc" },
		{ "name": "backslash", "windup": 11, "swing": 34, "recover": 0, "range": 2.5, "arc": 100.0, "damage": 8, "knock": 1.5, "lunge": 4.0, "anim": "s_back", "shape": "arc" },
		{ "name": "thrust", "windup": 16, "swing": 44, "recover": 8, "range": 3.3, "arc": 28.0, "damage": 10, "knock": 4.5, "lunge": 10.0, "anim": "s_smash", "shape": "thrust" },
	] },
	{ "kind": "ranged", "draw": 45, "min_speed": 22.0, "max_speed": 58.0, "min_damage": 6, "max_damage": 10,
	  "gravity": 9.8, "shot": 16, "cooldown": 28, "slow": 0.35, "projectile": "arrow", "ammo": "arrows" },
	{ "kind": "ranged", "draw": 20, "min_speed": 20.0, "max_speed": 36.0, "min_damage": 6, "max_damage": 8,
	  "gravity": 14.0, "shot": 12, "cooldown": 14, "slow": 0.85, "projectile": "stone", "ammo": "rocks" },
	# magic: hold attack to cast the selected spell (R picks the spell) if you have the mana. cast: the whole casting
	# move in ticks; windup: ticks until the spell goes off; cooldown: extra ticks before the next cast; cost: mana.
	{ "kind": "magic", "slow": 0.5, "uses": "mana", "spells": [   # the wizard's staff, on top of the tower: uses mana
		{ "name": "Lightning", "cost": 34, "windup": 16, "cast": 34, "cooldown": 30, "range": 40.0,
		  "radius": 3.0, "max_damage": 28, "min_damage": 8, "knock": 5.0, "delay": 24 },
		{ "name": "Fireball", "cost": 22, "windup": 12, "cast": 28, "cooldown": 12, "speed": 26.0, "gravity": 3.0,
		  "radius": 3.4, "max_damage": 24, "min_damage": 6, "knock": 6.5 },
		# held: up while the button is held down (Jacob 2026-11-04); raising it costs a little mana, then none, but
		# mana doesn't come back while it's up
		{ "name": "Shield", "cost": 10, "windup": 0, "cast": 0, "cooldown": 20, "hold": true },
		# level 2 (3 kills with the staff): a ring of ice bursts out from you: damage, a shove, and a 2 s slow
		{ "name": "Frost Nova", "level": 2, "cost": 30, "windup": 14, "cast": 30, "cooldown": 30, "radius": 6.0,
		  "max_damage": 18, "min_damage": 6, "knock": 3.5, "slow": 120 },
		# level 3 (8 kills): a flaming rock falls where you aim after `delay` ticks, a big blast (strongest at the
		# centre), then the ground burns for burn_ticks: burn_damage every burn_every ticks within burn_radius
		{ "name": "Meteor", "level": 3, "cost": 45, "windup": 22, "cast": 40, "cooldown": 60, "range": 35.0, "delay": 60,
		  "radius": 5.0, "max_damage": 40, "min_damage": 10, "knock": 9.0,
		  "burn_radius": 3.0, "burn_ticks": 180, "burn_every": 30, "burn_damage": 4 },
		# level 4, the ultimate (18 kills): a storm gathers over where you aim and rains lightning for `duration` ticks,
		# a bolt every `every` ticks, each seeking an enemy under the cloud (or striking at random within `area`)
		{ "name": "Arcane Storm", "level": 4, "cost": 80, "windup": 30, "cast": 50, "cooldown": 120, "range": 35.0,
		  "duration": 300, "area": 7.0, "every": 20, "warn": 12,
		  "radius": 2.4, "max_damage": 22, "min_damage": 6, "knock": 4.5 },
	] },
	# the wand from the hidden vault: no mana; each spell has its own recharge (ticks) instead (Jacob 2026-11-04)
	{ "kind": "magic", "slow": 0.6, "uses": "recharge", "spells": [
		{ "name": "Golem", "cost": 0, "windup": 24, "cast": 40, "cooldown": 10, "recharge": 600, "range": 9.0 },
		{ "name": "Teleport", "cost": 0, "windup": 8, "cast": 16, "cooldown": 6, "recharge": 240, "range": 18.0 },
		# the stun bolt bursts where it lands (the first person or golem in its way, a wall, or the crosshair point):
		# every enemy within `radius` of the burst is held for `duration` (Jacob 2026-11-04: an area, to catch them)
		{ "name": "Stun", "cost": 0, "windup": 10, "cast": 26, "cooldown": 10, "recharge": 300, "range": 24.0, "duration": 180, "radius": 2.5 },
		# level 2 (3 kills with the wand): stone spikes burst up one after another in a line toward the crosshair
		{ "name": "Earth Spikes", "level": 2, "cost": 0, "windup": 12, "cast": 30, "cooldown": 10, "recharge": 360,
		  "range": 16.0, "spikes": 9, "spacing": 1.7, "radius": 1.5, "max_damage": 16, "min_damage": 8, "knock": 7.0 },
		# level 3 (8 kills): a vortex where you aim, dragging enemies within `pull_radius` toward it for `duration`
		# ticks (nibbling at those near its heart), then bursting outward
		{ "name": "Gravity Well", "level": 3, "cost": 0, "windup": 14, "cast": 30, "cooldown": 10, "recharge": 900,
		  "range": 25.0, "duration": 180, "pull_radius": 7.0, "pull": 14.0, "nibble": 3, "nibble_radius": 2.0,
		  "radius": 3.5, "max_damage": 18, "min_damage": 8, "knock": 9.0 },
		# level 4, the ultimate (18 kills): one great stone titan (Golems: TITAN_*), recharging for a minute
		{ "name": "Stone Titan", "level": 4, "cost": 0, "windup": 36, "cast": 60, "cooldown": 20, "recharge": 3600, "range": 10.0 },
	] },
]

const MAX_MANA := 100
## Kills with the staff or wand level it up: level 2 after 3, level 3 after 5 more, the ultimate (level 4) after 10 more.
## Each level adds that weapon's next spell.
const LEVEL_KILLS := [0, 3, 8, 18]
const MAX_LEVEL := 4
const MANA_EVERY := 5      # ticks per point of mana back (12 a second), not while casting
const SHIELD_RADIUS := 1.25
## Holding the shield up against hits costs mana (Jacob 2026-11-04): per point of damage it soaks, 1.5 mana for
## weapons (melee, arrows, stones, golems) and 2 for spells; a stun costs a flat 25. When the mana can't pay for a hit,
## the shield shatters: the rest of the hit goes through and it can't be raised again for SHIELD_BROKEN ticks.
const SHIELD_MANA_WEAPON := 1.5
const SHIELD_MANA_SPELL := 2.0
const SHIELD_MANA_STUN := 25
const SHIELD_BROKEN := 120


## The level the staff or wand reaches with this many kills.
static func level_for(kills: int) -> int:
	var lv := 1
	for i in range(1, LEVEL_KILLS.size()):
		if kills >= int(LEVEL_KILLS[i]):
			lv = i + 1
	return lv


## Can a staff / wand at this level cast its spell i?
static func unlocked(w: int, i: int, level: int) -> bool:
	var d := get_data(w)
	if d.kind != "magic" or i < 0 or i >= (d.spells as Array).size():
		return false
	return int((d.spells[i] as Dictionary).get("level", 1)) <= level


static func is_magic(w: int) -> bool:
	return get_data(w).kind == "magic"


static func is_ranged(w: int) -> bool:
	return get_data(w).kind == "ranged"


## The spell slot i of a magic weapon, or {}.
static func spell(w: int, i: int) -> Dictionary:
	var d := get_data(w)
	if d.kind != "magic":
		return {}
	var sp: Array = d.spells
	return sp[clampi(i, 0, sp.size() - 1)]


## Area damage: full at the centre, falling off evenly to min_damage at the edge, nothing beyond.
static func area_damage(sp: Dictionary, dist: float) -> int:
	var r := float(sp.radius)
	if dist > r:
		return 0
	return int(round(lerpf(float(sp.max_damage), float(sp.min_damage), clampf(dist / r, 0.0, 1.0))))


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
enum Item { CLUB, SWORD, BOW, SLING, ARROWS, ROCKS, STAFF, WAND }
const ITEM_NAMES := ["Club", "Sword", "Bow", "Slingshot", "Arrows", "Rocks", "Wizard staff", "Magic wand"]
const ITEM_WEAPON := [CLUB, SWORD, BOW, SLING, -1, -1, STAFF, WAND]
const MAX_AMMO := 60
