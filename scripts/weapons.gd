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
		# v0.8.2: everyone inside the strike takes the full damage (no falloff); then it chains: from each one hit to
		# the nearest enemy not yet hit within chain_range (body to body), half the damage each jump, every chain_every
		# ticks, at most chain_max jumps, stopping when the damage would fall below 2; a shield soaks a jump and ends it
		{ "name": "Lightning", "cost": 34, "windup": 16, "cast": 34, "cooldown": 30, "range": 40.0,
		  "radius": 3.0, "max_damage": 28, "min_damage": 8, "knock": 5.0, "delay": 24, "falloff": false,
		  "chain_range": 6.0, "chain_max": 5, "chain_every": 5,
		  # v0.12.7 mastery (see MASTERY below): II hits harder and chains further and more often, each jump keeping more;
		  # III also forks: a second bolt leaps from the strike to the nearest enemy outside it (fork_k of the damage)
		  "mastery": [600, 1800], "by": "damage dealt to enemies (chain jumps count double)",
		  "m2": { "max_damage": 35, "min_damage": 10, "chain_range": 8.0, "chain_max": 7, "chain_keep": 0.6,
			"text": "+25% damage, chains 8 m, 7 jumps" },
		  "m3": { "max_damage": 42, "min_damage": 12, "chain_range": 10.0, "chain_max": 9, "chain_keep": 0.65,
			"fork": 8.0, "fork_k": 0.7, "text": "+50% damage, chains 10 m, 9 jumps, the bolt forks" } },
		{ "name": "Fireball", "cost": 22, "windup": 12, "cast": 28, "cooldown": 12, "speed": 26.0, "gravity": 3.0,
		  "radius": 3.4, "max_damage": 24, "min_damage": 6, "knock": 6.5,
		  # v0.12.7 mastery: a bigger orb and blast; III bursts into `bomblets` small fire bombs that scatter and pop
		  "mastery": [600, 1800], "by": "damage dealt to enemies",
		  "m2": { "radius": 4.25, "max_damage": 29, "min_damage": 7, "knock": 7.5, "size": 1.3,
			"text": "Bigger blast, +20% damage" },
		  "m3": { "radius": 5.1, "max_damage": 34, "min_damage": 8, "knock": 8.5, "size": 1.6, "bomblets": 3,
			"bomb_radius": 1.8, "bomb_damage": 8, "text": "Huge blast, +40% damage, 3 fire bomblets" } },
		# held: up while the button is held down (Jacob 2026-11-04); raising it costs a little mana, then none, but
		# mana doesn't come back while it's up. v0.12.7 mastery: `drain` scales the mana every hit costs; III reflects
		# projectiles back at whoever shot them (Net._shield_bounce)
		{ "name": "Shield", "cost": 10, "windup": 0, "cast": 0, "cooldown": 20, "hold": true,
		  "mastery": [250, 750], "by": "damage the bubble soaks (+4 for every shot it turns away)",
		  "m2": { "cost": 5, "drain": 0.7, "text": "Half the cost to raise, hits drain 30% less" },
		  "m3": { "cost": 5, "drain": 0.5, "reflect": true, "text": "Hits drain 50% less, and shots fly back at the shooter" } },
		# level 2 (3 kills with the staff): a ring of ice bursts out from you: damage, a shove, and a 2 s slow.
		# v0.12.7 mastery III: everyone within freeze_r is frozen solid (a stun of `freeze` ticks)
		{ "name": "Frost Nova", "level": 2, "cost": 30, "windup": 14, "cast": 30, "cooldown": 30, "radius": 6.0,
		  "max_damage": 18, "min_damage": 6, "knock": 3.5, "slow": 120,
		  "mastery": [350, 1050], "by": "damage dealt to enemies + 2 for every second of slow on one",
		  "m2": { "radius": 7.5, "max_damage": 21, "slow": 180, "text": "+25% reach, slows for 3 s" },
		  "m3": { "radius": 7.5, "max_damage": 24, "slow": 180, "freeze": 60, "freeze_r": 3.5,
			"text": "Freezes enemies near you solid for 1 s, ice spikes" } },
		# level 3 (7 kills): a flaming rock falls where you aim after `delay` ticks, a big blast (strongest at the
		# centre), then the ground burns for burn_ticks: burn_damage every burn_every ticks within burn_radius.
		# v0.12.7 mastery: `meteors` rocks (the aimed one, then the rest round it `spread` m out, a little later, each
		# hitting side_k as hard)
		{ "name": "Meteor", "level": 3, "cost": 45, "windup": 22, "cast": 40, "cooldown": 60, "range": 35.0, "delay": 60,
		  "radius": 5.0, "max_damage": 40, "min_damage": 10, "knock": 9.0,
		  "burn_radius": 3.0, "burn_ticks": 180, "burn_every": 30, "burn_damage": 4,
		  "mastery": [600, 1800], "by": "damage dealt to enemies (the burning ground too)",
		  "m2": { "meteors": 3, "spread": 4.5, "side_k": 0.7, "text": "Calls down 3 meteors" },
		  "m3": { "meteors": 5, "spread": 5.0, "side_k": 0.75, "burn_radius": 4.5, "burn_ticks": 240,
			"text": "Calls down 5 meteors, wider, longer fires" } },
		# level 3 too (v0.12.0, Jacob): a channel. Hold to raise the staff: `drain` fifths of mana a tick (12 mana a
		# second), and every `every` ticks the caster and every ally within `radius` m is healed `heal` (8 a second);
		# it stops when the button is let go, the mana runs out, or everyone in range is already full (Net).
		# v0.12.7 mastery III: each pulse cleanses stuns, slows and Static, and leaves `regen` ticks of afterglow
		# (+1 every 20 ticks)
		{ "name": "Heal Aura", "level": 3, "cost": 0, "windup": 0, "cast": 0, "cooldown": 20, "channel": true,
		  "drain": 1, "radius": 7.0, "every": 30, "heal": 4,
		  "mastery": [300, 900], "by": "health restored (yours and your allies'; overhealing doesn't count)",
		  "m2": { "radius": 9.0, "every": 24, "text": "Heals faster (10 a second), reaches 9 m" },
		  "m3": { "radius": 10.0, "every": 20, "cleanse": true, "regen": 180,
			"text": "12 a second, 10 m, cleanses stuns and slows, leaves a regen glow" } },
		# level 4, the ultimate (12 kills): a storm gathers over where you aim and rains lightning for `duration` ticks,
		# a bolt every `every` ticks, each seeking an enemy under the cloud (or striking at random within `area`).
		# v0.12.7 mastery III: each bolt chains once
		{ "name": "Arcane Storm", "level": 4, "cost": 80, "windup": 30, "cast": 50, "cooldown": 120, "range": 35.0,
		  "duration": 300, "area": 7.0, "every": 20, "warn": 12,
		  "radius": 2.4, "max_damage": 22, "min_damage": 6, "knock": 4.5,
		  "mastery": [500, 1500], "by": "damage dealt to enemies",
		  "m2": { "duration": 420, "every": 15, "text": "Lasts 7 s, a bolt every quarter second" },
		  "m3": { "duration": 420, "every": 15, "area": 9.5, "bolt_chain": true,
			"text": "A wider cloud, and every bolt chains once" } },
	] },
	# the wand from the hidden vault: no mana; each spell has its own recharge (ticks) instead (Jacob 2026-11-04)
	{ "kind": "magic", "slow": 0.6, "uses": "recharge", "spells": [
		# v0.12.0 the wand's basic spell: an instant zap along the aim (hit-scan from the wand toward the crosshair, the
		# first enemy body, golem or dummy within `range`), light damage, ready again every second
		{ "name": "Spark Beam", "cost": 0, "windup": 5, "cast": 14, "cooldown": 4, "recharge": 60, "range": 30.0,
		  "damage": 7, "knock": 1.0,
		  # v0.12.7 mastery: `pierce` more enemies behind the first; III also arcs to one more within arc_r (arc_k damage)
		  "mastery": [500, 1500], "by": "damage dealt to enemies (x1.5 for hits beyond 15 m)",
		  "m2": { "damage": 9, "pierce": 1, "text": "+30% damage, pierces 1 enemy" },
		  "m3": { "damage": 11, "pierce": 2, "arc_r": 5.0, "arc_k": 0.6,
			"text": "+60% damage, pierces 2, arcs to one more" } },
		# v0.12.7 mastery: the golems it raises are `size` times bigger (reach too), with hp_k the health and dmg_k the
		# punch; III golems' slams crush everyone within `slam` m of where they land
		{ "name": "Golem", "cost": 0, "windup": 24, "cast": 40, "cooldown": 10, "recharge": 600, "range": 9.0,
		  "mastery": [500, 1500], "by": "damage your golems deal to enemies",
		  "m2": { "size": 1.3, "hp_k": 1.4, "dmg_k": 1.35, "text": "Bigger golems: +40% health, harder punches" },
		  "m3": { "size": 1.6, "hp_k": 1.8, "dmg_k": 1.7, "slam": 2.2, "text": "Huge golems: +80% health, ground-slam" } },
		# v0.12.7 mastery: further (Sim predicts the reach), and an arrival burst: arrive_dmg to enemies within arrive_r m
		# of where you appear, thrown arrive_knock m/s outward (server)
		{ "name": "Teleport", "cost": 0, "windup": 8, "cast": 16, "cooldown": 6, "recharge": 240, "range": 18.0,
		  "mastery": [250, 750], "by": "metres travelled (+ arrival-burst damage)",
		  "m2": { "range": 25.0, "arrive_r": 2.5, "arrive_dmg": 8, "arrive_knock": 6.0,
			"text": "Reaches 25 m, a burst where you arrive" } ,
		  "m3": { "range": 32.0, "arrive_r": 4.0, "arrive_dmg": 16, "arrive_knock": 10.0,
			"text": "Reaches 32 m, a shockwave where you arrive" } },
		# the stun bolt bursts where it lands (the first person or golem in its way, a wall, or the crosshair point):
		# every enemy within `radius` of the burst is held for `duration` (Jacob 2026-11-04: an area, to catch them).
		# v0.12.7 mastery III: an NPC it holds is charmed for `charm` ticks after: it fights for the caster (Net._charm)
		{ "name": "Stun", "cost": 0, "windup": 10, "cast": 26, "cooldown": 10, "recharge": 300, "range": 24.0, "duration": 180, "radius": 2.5,
		  "mastery": [120, 360], "by": "seconds of stun on enemies + a quarter of the damage your side deals them while stunned",
		  "m2": { "duration": 240, "radius": 3.0, "text": "Holds 4 s, a wider burst" },
		  "m3": { "duration": 300, "radius": 3.0, "charm": 360,
			"text": "Holds 5 s; challengers and units fight for you 6 s after" } },
		# level 2 (3 kills with the wand; v0.12.0, replaces Earth Spikes): a cloud of fog round the caster (see Fog):
		# `half` m each way from the centre, `duration` ticks, thinning and drifting over the last `fade`.
		# v0.12.7 mastery: `poison` damage a second to enemies inside (Net._server_fog_poison); III: slowed inside too
		{ "name": "Fog", "level": 2, "cost": 0, "windup": 16, "cast": 32, "cooldown": 10, "recharge": 1080,
		  "duration": 600, "fade": 120, "half": 12.5,
		  "mastery": [250, 750], "by": "enemy-seconds blinded in it + a quarter of the damage your side deals them inside + poison",
		  "m2": { "poison": 2, "text": "Poison: 2 damage a second to enemies inside" },
		  "m3": { "poison": 4, "half": 15.0, "slow_in": true, "text": "30 x 30 m, 4 poison a second, enemies slowed" } },
		# level 3 (7 kills; v0.12.0): a draining stream from the first enemy along the aim back into the wand: `damage`,
		# and `drain` of what it really took comes back to the caster as health. If the first one along the aim is an
		# ALLY (a player the caster can't hurt, or an ally's / the caster's golem) it hurts nobody and heals them
		# `ally_heal` instead (about what a drain gives back); the caster gets nothing from that.
		# v0.12.7 mastery III: the stream jumps on to a second enemy within jump_r (jump_k damage, drained too)
		{ "name": "Life Drain", "level": 3, "cost": 0, "windup": 12, "cast": 30, "cooldown": 8, "recharge": 180,
		  "range": 18.0, "damage": 18, "drain": 0.45, "knock": 0.5, "ally_heal": 12,
		  "mastery": [400, 1200], "by": "damage drained + health given to allies",
		  "m2": { "damage": 23, "drain": 0.55, "ally_heal": 16, "text": "+25% damage, drains 55%" },
		  "m3": { "damage": 27, "drain": 0.6, "ally_heal": 22, "jump_r": 6.0, "jump_k": 0.6,
			"text": "+50% damage, jumps to a second enemy, bigger ally heal" } },
		# level 3 (7 kills): a vortex where you aim, dragging enemies within `pull_radius` toward it for `duration`
		# ticks (nibbling at those near its heart), then bursting outward. v0.12.7 mastery III: `bursts` 2 (half-way too)
		{ "name": "Gravity Well", "level": 3, "cost": 0, "windup": 14, "cast": 30, "cooldown": 10, "recharge": 900,
		  "range": 25.0, "duration": 180, "pull_radius": 7.0, "pull": 14.0, "nibble": 3, "nibble_radius": 2.0,
		  "radius": 3.5, "max_damage": 18, "min_damage": 8, "knock": 9.0,
		  "mastery": [400, 1200], "by": "damage dealt to enemies + 1 for every second an enemy is dragged",
		  "m2": { "pull_radius": 9.5, "radius": 4.0, "text": "Pulls from 9.5 m, a wider burst" },
		  "m3": { "pull_radius": 9.5, "pull": 20.0, "radius": 4.5, "bursts": 2,
			"text": "Pulls harder, bursts twice" } },
		# level 4, the ultimate (12 kills): one great stone titan (Golems: TITAN_*), recharging for a minute.
		# v0.12.7 mastery: bigger and tougher; III: every slam also sends a stomp shockwave (stomp m, stomp_dmg)
		{ "name": "Stone Titan", "level": 4, "cost": 0, "windup": 36, "cast": 60, "cooldown": 20, "recharge": 3600, "range": 10.0,
		  "mastery": [600, 1800], "by": "damage your titan deals to enemies",
		  "m2": { "size": 1.2, "hp_k": 1.35, "dmg_k": 1.25, "text": "A bigger titan: +35% health, harder slams" },
		  "m3": { "size": 1.35, "hp_k": 1.7, "dmg_k": 1.5, "stomp": 6.0, "stomp_dmg": 10,
			"text": "+70% health, every slam sends a stomp shockwave" } },
	] },
]

## v0.12.7 SPELL MASTERY (Jacob): every spell levels up on its own, I -> II -> III, from what it ACHIEVES (each spell's
## "by": damage dealt to enemies, health restored, metres teleported, seconds of stun...; never practice dummies), the
## points needed for II and III in its "mastery". "m2" / "m3" are what changes at II and III (merged over the spell in
## that order, so III keeps II's numbers unless it says otherwise; "text": the line on the level-up toast). The levels
## are packed 2 bits a spell (level - 1) into Sim.PlayerState.mastery (synced: Sim needs them for the teleport's reach
## and the shield's cost); the points live on Net.ServerPlayer.mxp. Slots: the staff's spells 0-6, then the wand's 7-14.
## NPC wizards stay at I (their mastery is 0).
const MASTERY_SLOTS := 15
const MASTERY_ROMAN := ["I", "II", "III"]

const MAX_MANA := 100
## Kills with the staff or wand level it up: level 2 after 3, level 3 after 5 more, the ultimate (level 4) after 10 more.
## Each level adds that weapon's next spell.
const LEVEL_KILLS := [0, 3, 7, 12]   # v0.12.0: 3, then 4 more, then 5 more (was 3, 8, 18)
const MAX_LEVEL := 4
## v0.12.5 (Jacob): the other weapons (fists, club, sword, bow, slingshot) level up too, at the same kill counts, and
## just hit harder: every hit (each melee move, the club smash's shockwave, an arrow or a stone at any draw) times
## ARM_DAMAGE[level - 1]. Kills are knock-outs of players, challengers and minions, as for the staff and wand.
const ARM_DAMAGE := [1.0, 1.25, 1.5, 1.8]


## v0.12.5 blocking (Jacob): braced, a hit from the front lets only this much of its damage through. The sword, the
## club and the staff (something solid to catch a blow on) block more than fists, the bow, the slingshot and the wand.
## Thunderhorn hits too hard to stop as well: against him a block saves only half as much. Blocked hits push you back
## GUARD_KNOCK as far. From behind or the side (outside GUARD_ARC degrees each way of where you face), no block at all.
const BLOCK_KEEP := { FISTS: 0.6, CLUB: 0.35, SWORD: 0.35, BOW: 0.6, SLING: 0.6, STAFF: 0.35, WAND: 0.6 }
const GUARD_ARC := 75.0
const GUARD_KNOCK := 0.4


## What part of a frontal hit gets through a block with weapon w (boss: from Thunderhorn).
static func block_keep(w: int, boss := false) -> float:
	var k := float(BLOCK_KEEP.get(w, 0.6))
	return lerpf(k, 1.0, 0.5) if boss else k


## Does this weapon level up by damage (not spells)?
static func is_arm(w: int) -> bool:
	return w >= FISTS and w <= SLING


## A fists/club/sword/bow/slingshot hit of `base` at weapon level `lv`.
static func arm_damage(base: int, lv: int) -> int:
	return int(round(float(base) * float(ARM_DAMAGE[clampi(lv, 1, MAX_LEVEL) - 1])))
const MANA_EVERY := 5      # ticks per point of mana back (12 a second), not while casting
## v0.8.1: the bubble is centred SHIELD_CENTER_Y above the feet and big enough to hold the whole caster, the raised
## staff (its orb sits at the top of the bubble), the hat and the robe. The server tests hits against this same sphere.
const SHIELD_RADIUS := 1.5
const SHIELD_CENTER_Y := 1.1
## What's left of a projectile's speed after it bounces off a shield.
const SHIELD_BOUNCE := 0.6
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


## v0.12.0: the slot of the spell with this name on a magic weapon, or -1 (code names spells, so slots can move).
static func idx(w: int, spell_name: String) -> int:
	var d := get_data(w)
	if d.kind != "magic":
		return -1
	var sp: Array = d.spells
	for i in sp.size():
		if str(sp[i].name) == spell_name:
			return i
	return -1


## v0.12.0: the spell with this name, or {}.
static func spell_named(w: int, spell_name: String) -> Dictionary:
	var i := idx(w, spell_name)
	return spell(w, i) if i >= 0 else {}


## v0.12.7 mastery: the slot (0-14) of spell i of the staff / wand, or -1 (not a magic weapon).
static func mastery_slot(w: int, i: int) -> int:
	if w == STAFF:
		return clampi(i, 0, (DATA[STAFF].spells as Array).size() - 1)
	if w == WAND:
		return (DATA[STAFF].spells as Array).size() + clampi(i, 0, (DATA[WAND].spells as Array).size() - 1)
	return -1


## The weapon and spell index of a mastery slot: [w, i].
static func slot_spell(slot: int) -> Array:
	var n := (DATA[STAFF].spells as Array).size()
	return [STAFF, slot] if slot < n else [WAND, slot - n]


## The mastery level (1-3) of a slot in a packed `mastery` int.
static func mastery_of(packed: int, slot: int) -> int:
	if slot < 0:
		return 1
	return ((packed >> (2 * slot)) & 3) + 1


## `packed` with that slot's level set to lv (1-3).
static func with_mastery(packed: int, slot: int, lv: int) -> int:
	if slot < 0:
		return packed
	return (packed & ~(3 << (2 * slot))) | ((clampi(lv, 1, 3) - 1) << (2 * slot))


## Every slot at level lv, packed.
static func mastery_all(lv: int) -> int:
	var m := 0
	for s in MASTERY_SLOTS:
		m = with_mastery(m, s, lv)
	return m


## The points a slot's spell needs for II and III.
static func mastery_need(slot: int) -> Array:
	var ws := slot_spell(slot)
	return spell(ws[0], ws[1]).get("mastery", [1000, 3000])


## The level `points` reach for a slot.
static func mastery_for(slot: int, points: float) -> int:
	var need := mastery_need(slot)
	return 3 if points >= float(need[1]) else (2 if points >= float(need[0]) else 1)


static var _lv_cache := {}

## v0.12.7 the spell slot i of a magic weapon at mastery level lv: its numbers with "m2" (and then "m3") merged over
## them, and "lv" set. Level 1 is the spell itself. Cached: don't change what it returns.
static func spell_lv(w: int, i: int, lv: int) -> Dictionary:
	var base := spell(w, i)
	if lv <= 1 or base.is_empty():
		return base
	var key := w * 1000 + i * 10 + lv
	if _lv_cache.has(key):
		return _lv_cache[key]
	var out := base.duplicate()
	out.merge(base.get("m2", {}), true)
	if lv >= 3:
		out.merge(base.get("m3", {}), true)
	out["lv"] = lv
	_lv_cache[key] = out
	return out


## The spell slot i at the mastery a player has (their packed PlayerState.mastery): what to read damage, reach and the
## rest from.
static func spell_at(w: int, i: int, packed: int) -> Dictionary:
	return spell_lv(w, i, mastery_of(packed, mastery_slot(w, i)))


## The spell with this name at mastery level lv.
static func spell_named_lv(w: int, spell_name: String, lv: int) -> Dictionary:
	var i := idx(w, spell_name)
	return spell_lv(w, i, lv) if i >= 0 else {}


## The mastery level a packed int gives the spell with this name.
static func mastery_named(packed: int, w: int, spell_name: String) -> int:
	var i := idx(w, spell_name)
	return mastery_of(packed, mastery_slot(w, i)) if i >= 0 else 1


## v0.12.0: the names of the spells a staff / wand gains at exactly this level (the level-up banner names them all).
static func spells_at(w: int, level: int) -> Array:
	var out := []
	var d := get_data(w)
	if d.kind == "magic":
		for sp in d.spells:
			if int(sp.get("level", 1)) == level:
				out.append(str(sp.name))
	return out


## Area damage: full at the centre, falling off evenly to min_damage at the edge, nothing beyond.
static func area_damage(sp: Dictionary, dist: float) -> int:
	var r := float(sp.radius)
	if dist > r:
		return 0
	if not bool(sp.get("falloff", true)):   # lightning: the full damage anywhere inside the strike
		return int(sp.max_damage)
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
